# The HDF5 persistence extension: the methods behind the write/read pairs whose generics and
# docstrings live in the core modules. Loaded automatically when both GBGIsotropicTurbulence and
# HDF5 are present (a Julia package extension). The design (decision 75) composes the field
# library's own persistence — `write_field`/`write_points`/`write_scheme` groups as the leaves —
# and stores nothing derivable: physical charts, the current velocity sample, kernels, plans and
# every register are recomputed on read. Each group is self-describing (a type tag and a schema
# version, checked on read), the file is opened and closed by the caller, and the storage backend
# is the READER's choice — a checkpoint written on one backend loads on any other.
module GBGIsotropicTurbulenceHDF5Ext

using HDF5
using GBGPeriodicFields: write_field, read_field, write_points, read_points, write_scheme,
                         read_scheme, field_data, point_coordinates, point_values, npoints,
                         PointSet
using GBGIsotropicTurbulence.SimulationDomain: FixedDomain, TwoThirds, HouLi, PhaseShift,
                                               _real_type
import GBGIsotropicTurbulence.SimulationDomain: write_domain, read_domain
using GBGIsotropicTurbulence.State: ResolvedFields
import GBGIsotropicTurbulence.State: write_state, read_state
using GBGIsotropicTurbulence.Particles: Tracers, Heun, AdamsBashforth, history_depth
import GBGIsotropicTurbulence.Particles: write_tracers, read_tracers
using GBGIsotropicTurbulence.Forcing: AbstractForcing, DeferredForcing, NoForcing, Linear,
                                      ConstantPower, VarianceRescaling, VarianceController,
                                      StochasticOU
import GBGIsotropicTurbulence.Forcing: write_forcing, read_forcing
using GBGIsotropicTurbulence.Cache: fields_modified!, particles_modified!
using GBGIsotropicTurbulence.Propagator: IFLowStorageRK3, IFHeun, deposit!
using GBGIsotropicTurbulence.SimulationRun: Simulation
import GBGIsotropicTurbulence.SimulationRun: write_simulation, read_simulation

const SCHEMA_VERSION = 1


# ————————————————————————————————————————————————————————————————————————————————————————————————
# Shared validation: a reader trusts nothing it did not check. The attributes are redundant with
# the data by design, which is exactly why a disagreement means the file is not what it claims.

function _require_group(parent, name::AbstractString, who::String)
  haskey(parent, name) ||
    throw(ArgumentError("$who: no object named \"$name\" under the given parent"))
  g = parent[name]
  g isa HDF5.Group ||
    throw(ArgumentError("$who: \"$name\" is a dataset, not a group"))
  return g
end

function _require_tag(g, name::AbstractString, who::String, tag::String)
  a = attrs(g)
  haskey(a, "type") || throw(ArgumentError(
    "$who: group \"$name\" has no `type` attribute — it was not written by this pair's writer"))
  a["type"] == tag || throw(ArgumentError(
    "$who: group \"$name\" holds a \"$(a["type"])\", not a \"$tag\""))
  if haskey(a, "version")
    v = Int(a["version"])
    v <= SCHEMA_VERSION || throw(ArgumentError(
      "$who: group \"$name\" declares schema version $v, but this package understands up to " *
      "$SCHEMA_VERSION — the file was written by a newer version"))
  end
  return a
end

function _element_type(a, name::AbstractString, who::String)
  tag = a["eltype"]
  tag == "Float64" && return Float64
  tag == "Float32" && return Float32
  throw(ArgumentError("$who: group \"$name\" records element type \"$tag\", which this package " *
                      "does not build runs on"))
end

# Copy a stored field into an existing (possibly device-resident) one, refusing a shape or element
# type that does not match the destination the domain built.
function _load_field!(dest, g, name::AbstractString, who::String)
  src = read_field(g, name)
  size(field_data(src)) == size(field_data(dest)) || throw(ArgumentError(
    "$who: the stored field \"$name\" has shape $(size(field_data(src))), but the domain builds " *
    "$(size(field_data(dest))) — the checkpoint belongs to a different grid"))
  eltype(field_data(src)) == eltype(field_data(dest)) || throw(ArgumentError(
    "$who: the stored field \"$name\" has element type $(eltype(field_data(src))), but the " *
    "domain builds $(eltype(field_data(dest)))"))
  copyto!(field_data(dest), field_data(src))
  return dest
end

# Read a stored point object's (M, 3) coordinates onto the domain's backend as a fresh PointSet.
function _points_on_backend(domain::FixedDomain, host_points)
  T = _real_type(domain)
  X_host = point_coordinates(host_points)
  eltype(X_host) == T || throw(ArgumentError(
    "the stored positions have element type $(eltype(X_host)), but the domain builds $T"))
  X = domain.storage_family{T}(undef, size(X_host)...)
  copyto!(X, X_host)
  return PointSet(X)
end


# ————————————————————————————————————————————————————————————————————————————————————————————————
# The domain: its defining parameters; plans, multipliers and kernels rebuild.

_dealiasing_tag(::TwoThirds) = "TwoThirds"
_dealiasing_tag(::HouLi) = "HouLi"
_dealiasing_tag(::PhaseShift) = "PhaseShift"

function write_domain(parent::HDF5.H5DataStore, name::AbstractString, domain::FixedDomain)
  g = create_group(parent, name)
  a = attrs(g)
  a["type"] = "GBGIsotropicTurbulence.FixedDomain"
  a["version"] = SCHEMA_VERSION
  a["grid_points_per_axis"] = Int(domain.grid.grid_size[1])
  a["side_length"] = Float64(domain.grid.domain_size[1])
  a["eltype"] = string(_real_type(domain))
  d = domain.dealiasing
  a["dealiasing"] = _dealiasing_tag(d)
  if d isa HouLi
    a["dealiasing_order"] = d.order
    d.strength === nothing || (a["dealiasing_strength"] = d.strength)
  end
  return g
end

function read_domain(parent::HDF5.H5DataStore, name::AbstractString; array_type = Array)
  g = _require_group(parent, name, "read_domain")
  a = _require_tag(g, name, "read_domain", "GBGIsotropicTurbulence.FixedDomain")
  tag = a["dealiasing"]
  dealiasing = tag == "TwoThirds" ? TwoThirds() :
               tag == "PhaseShift" ? PhaseShift() :
               tag == "HouLi" ? HouLi(order = Int(a["dealiasing_order"]),
                                      strength = haskey(a, "dealiasing_strength") ?
                                                 a["dealiasing_strength"] : nothing) :
               throw(ArgumentError("read_domain: unrecognized dealiasing tag \"$tag\" in group " *
                                   "\"$name\""))
  return FixedDomain(; grid_points_per_axis = Int(a["grid_points_per_axis"]),
                     side_length = a["side_length"],
                     element_type = _element_type(a, name, "read_domain"),
                     array_type, dealiasing)
end


# ————————————————————————————————————————————————————————————————————————————————————————————————
# The state: the spectral fields, the single source of truth; nothing physical is stored.

function write_state(parent::HDF5.H5DataStore, name::AbstractString, state::ResolvedFields)
  g = create_group(parent, name)
  a = attrs(g)
  a["type"] = "GBGIsotropicTurbulence.ResolvedFields"
  a["version"] = SCHEMA_VERSION
  a["scalar"] = state.scalar_spectral !== nothing
  write_field(g, "velocity_spectral", state.velocity_spectral)
  state.scalar_spectral === nothing || write_field(g, "scalar_spectral", state.scalar_spectral)
  return g
end

function read_state(parent::HDF5.H5DataStore, name::AbstractString, domain::FixedDomain)
  g = _require_group(parent, name, "read_state")
  a = _require_tag(g, name, "read_state", "GBGIsotropicTurbulence.ResolvedFields")
  scalar = Bool(a["scalar"])
  state = ResolvedFields(domain; scalar)
  _load_field!(state.velocity_spectral, g, "velocity_spectral", "read_state")
  scalar && _load_field!(state.scalar_spectral, g, "scalar_spectral", "read_state")
  return state
end


# ————————————————————————————————————————————————————————————————————————————————————————————————
# The tracer set: positions (and the unwrapped record when tracked) through the field library's
# point persistence, the interpolation scheme through its scheme persistence (PF decision 75).

function write_tracers(parent::HDF5.H5DataStore, name::AbstractString, tracers::Tracers)
  g = create_group(parent, name)
  a = attrs(g)
  a["type"] = "GBGIsotropicTurbulence.Tracers"
  a["version"] = SCHEMA_VERSION
  write_points(g, "positions", tracers.positions)
  write_scheme(g, "interpolation_scheme", tracers.interpolation_scheme)
  tracers.unwrapped_positions === nothing ||
    write_points(g, "unwrapped_positions", tracers.unwrapped_positions)
  return g
end

function read_tracers(parent::HDF5.H5DataStore, name::AbstractString, domain::FixedDomain)
  g = _require_group(parent, name, "read_tracers")
  _require_tag(g, name, "read_tracers", "GBGIsotropicTurbulence.Tracers")
  positions = _points_on_backend(domain, read_points(g, "positions"))
  scheme = read_scheme(g, "interpolation_scheme")
  unwrapped = haskey(g, "unwrapped_positions") ?
              _points_on_backend(domain, read_points(g, "unwrapped_positions")) : nothing
  return Tracers(positions, scheme, unwrapped)
end


# ————————————————————————————————————————————————————————————————————————————————————————————————
# The forcings: a strategy IS its parameters (the shell bounds included, stored on the struct for
# exactly this reason); the band kernel or indicator is rebuilt by the ordinary constructor. The
# stochastic forcing stores parameters only — its evolving force and random stream are ruled
# non-persistent, so a reloaded run resumes on a fresh stream.

function _forcing_group(parent, name, tag)
  g = create_group(parent, name)
  a = attrs(g)
  a["type"] = "GBGIsotropicTurbulence.$tag"
  a["version"] = SCHEMA_VERSION
  return g, a
end

write_forcing(parent::HDF5.H5DataStore, name::AbstractString, ::NoForcing) =
  first(_forcing_group(parent, name, "NoForcing"))

function write_forcing(parent::HDF5.H5DataStore, name::AbstractString, forcing::Linear)
  g, a = _forcing_group(parent, name, "Linear")
  a["rate"] = forcing.rate
  a["lowest_shell"] = forcing.lowest_shell
  a["highest_shell"] = forcing.highest_shell
  return g
end

function write_forcing(parent::HDF5.H5DataStore, name::AbstractString, forcing::ConstantPower)
  g, a = _forcing_group(parent, name, "ConstantPower")
  a["injection_rate"] = forcing.injection_rate
  a["lowest_shell"] = forcing.lowest_shell
  a["highest_shell"] = forcing.highest_shell
  return g
end

function write_forcing(parent::HDF5.H5DataStore, name::AbstractString, forcing::VarianceRescaling)
  g, a = _forcing_group(parent, name, "VarianceRescaling")
  a["target"] = forcing.target
  a["over"] = string(forcing.over)
  a["lowest_shell"] = forcing.lowest_shell
  a["highest_shell"] = forcing.highest_shell
  return g
end

function write_forcing(parent::HDF5.H5DataStore, name::AbstractString, forcing::VarianceController)
  g, a = _forcing_group(parent, name, "VarianceController")
  a["target"] = forcing.target
  a["gain"] = forcing.gain
  a["turnover_time"] = forcing.turnover_time
  a["turnover_time_derived"] = forcing.turnover_time_derived
  a["lowest_shell"] = forcing.lowest_shell
  a["highest_shell"] = forcing.highest_shell
  return g
end

function write_forcing(parent::HDF5.H5DataStore, name::AbstractString, forcing::StochasticOU)
  g, a = _forcing_group(parent, name, "StochasticOU")
  a["variance"] = forcing.variance
  a["correlation_time"] = forcing.correlation_time
  # The seed is a defining parameter (it fixes the stream, so a forced run is reproducible); the
  # stream's evolving POSITION is deliberately not stored — that is the documented divergence.
  a["seed"] = forcing.seed
  a["lowest_shell"] = forcing.lowest_shell
  a["highest_shell"] = forcing.highest_shell
  return g
end

write_forcing(::HDF5.H5DataStore, ::AbstractString, ::DeferredForcing) =
  throw(ArgumentError("write_forcing: a DeferredForcing is a constructor, not a built strategy — " *
                      "resolve it on a domain first (a Simulation's conditions hold the built form)"))

function read_forcing(parent::HDF5.H5DataStore, name::AbstractString, domain::FixedDomain)
  g = _require_group(parent, name, "read_forcing")
  a = attrs(g)
  haskey(a, "type") || throw(ArgumentError(
    "read_forcing: group \"$name\" has no `type` attribute — it was not written by write_forcing"))
  tag = a["type"]
  _require_tag(g, name, "read_forcing", tag)          # version check under the group's own tag
  tag == "GBGIsotropicTurbulence.NoForcing" && return NoForcing()
  lo = haskey(a, "lowest_shell") ? Int(a["lowest_shell"]) : 1
  hi = haskey(a, "highest_shell") ? Int(a["highest_shell"]) : 2
  if tag == "GBGIsotropicTurbulence.Linear"
    return Linear(domain; rate = a["rate"], lowest_shell = lo, highest_shell = hi)
  elseif tag == "GBGIsotropicTurbulence.ConstantPower"
    return ConstantPower(domain; injection_rate = a["injection_rate"],
                         lowest_shell = lo, highest_shell = hi)
  elseif tag == "GBGIsotropicTurbulence.VarianceRescaling"
    return VarianceRescaling(domain; target = a["target"], over = Symbol(a["over"]),
                             lowest_shell = lo, highest_shell = hi)
  elseif tag == "GBGIsotropicTurbulence.VarianceController"
    # A derived settling time is reconstructed by re-deriving (turnover_time = nothing): the
    # default is a pure function of the stored target and the box side, so the value is
    # bit-identical — and the provenance survives the round-trip, which the scalar-binding guard
    # of decision 77 reads. A file written before the flag existed reads as explicit, exactly
    # what such a file restored to.
    derived = haskey(a, "turnover_time_derived") ? Bool(a["turnover_time_derived"]) : false
    return VarianceController(domain; target = a["target"], gain = a["gain"],
                              turnover_time = derived ? nothing : a["turnover_time"],
                              lowest_shell = lo, highest_shell = hi)
  elseif tag == "GBGIsotropicTurbulence.StochasticOU"
    return StochasticOU(domain; variance = a["variance"],
                        correlation_time = a["correlation_time"],
                        # A checkpoint written before the seed was persisted carries no attribute;
                        # the constructor default 0 reproduces exactly what such a file restored to.
                        seed = haskey(a, "seed") ? a["seed"] : 0,
                        lowest_shell = lo, highest_shell = hi)
  else
    throw(ArgumentError("read_forcing: unrecognized forcing tag \"$tag\" in group \"$name\""))
  end
end


# ————————————————————————————————————————————————————————————————————————————————————————————————
# The checkpoint: composition of the pairs above, plus the three things only the run layer holds —
# the scheme and timestep settings (attributes), the Lagrangian sample history (the one cache
# content a restart cannot recompute), and the clock.

_field_scheme_tag(::IFLowStorageRK3) = "IFLowStorageRK3"
_field_scheme_tag(::IFHeun) = "IFHeun"
_particle_scheme_tag(::Heun) = "Heun"
_particle_scheme_tag(::AdamsBashforth) = "AdamsBashforth"

function write_simulation(parent::HDF5.H5DataStore, name::AbstractString, sim::Simulation)
  g = create_group(parent, name)
  a = attrs(g)
  a["type"] = "GBGIsotropicTurbulence.Simulation"
  a["version"] = SCHEMA_VERSION
  a["time"] = sim.clock.time
  a["step"] = sim.clock.step
  conditions = sim.generator.conditions
  a["viscosity"] = conditions.viscosity
  a["schmidt"] = conditions.schmidt
  a["cfl"] = sim.cfl
  a["max_dt"] = sim.max_dt
  a["scalar"] = sim.state.scalar_spectral !== nothing
  a["field_integration_scheme"] = _field_scheme_tag(sim.field_integration_scheme)
  a["storage_family"] = string(nameof(sim.domain.storage_family))   # informational, never read back
  write_domain(g, "domain", sim.domain)
  write_state(g, "state", sim.state)
  write_forcing(g, "velocity_forcing", conditions.velocity_forcing)
  write_forcing(g, "scalar_forcing", conditions.scalar_forcing)
  if sim.tracers !== nothing
    a["particle_integration_scheme"] = _particle_scheme_tag(sim.particle_integration_scheme)
    a["particle_scheme_order"] = history_depth(sim.particle_integration_scheme)
    write_tracers(g, "tracers", sim.tracers)
    filled = sim.cache.history_filled
    a["history_filled"] = filled
    if filled > 0
      a["history_steps"] = collect(sim.cache.history_steps[1:filled])
      hg = create_group(g, "sample_history")
      for j in 1:filled
        write_points(hg, "row$j", sim.cache.velocity_at_particles_history[j])
      end
    end
  end
  return g
end

function read_simulation(parent::HDF5.H5DataStore, name::AbstractString; array_type = Array)
  g = _require_group(parent, name, "read_simulation")
  a = _require_tag(g, name, "read_simulation", "GBGIsotropicTurbulence.Simulation")
  domain = read_domain(g, "domain"; array_type)
  scalar = Bool(a["scalar"])
  velocity_forcing = read_forcing(g, "velocity_forcing", domain)
  scalar_forcing = read_forcing(g, "scalar_forcing", domain)
  ftag = a["field_integration_scheme"]
  field_integration_scheme = ftag == "IFLowStorageRK3" ? IFLowStorageRK3() :
                             ftag == "IFHeun" ? IFHeun() :
                             throw(ArgumentError("read_simulation: unrecognized field scheme tag " *
                                                 "\"$ftag\" in group \"$name\""))
  has_tracers = haskey(g, "tracers")
  if has_tracers
    tg = _require_group(g, "tracers", "read_simulation")
    positions_host = read_points(tg, "positions")
    interpolation_scheme = read_scheme(tg, "interpolation_scheme")
    unwrapped = haskey(tg, "unwrapped_positions")
    ptag = a["particle_integration_scheme"]
    particle_integration_scheme =
      ptag == "Heun" ? Heun() :
      ptag == "AdamsBashforth" ? AdamsBashforth(order = Int(a["particle_scheme_order"])) :
      throw(ArgumentError("read_simulation: unrecognized particle scheme tag \"$ptag\" in " *
                          "group \"$name\""))
    sim = Simulation(domain; viscosity = a["viscosity"], schmidt = a["schmidt"], scalar,
                     velocity_forcing, scalar_forcing, field_integration_scheme,
                     cfl = a["cfl"], max_dt = a["max_dt"],
                     number_of_particles = npoints(positions_host), interpolation_scheme,
                     unwrapped, particle_integration_scheme)
  else
    sim = Simulation(domain; viscosity = a["viscosity"], schmidt = a["schmidt"], scalar,
                     velocity_forcing, scalar_forcing, field_integration_scheme,
                     cfl = a["cfl"], max_dt = a["max_dt"])
  end
  # The seeded state gives way to the stored one; the announcements and the closing deposits then
  # replay the constructor's own seeding schedule over it, so every derived slot is recomputed
  # rather than read. Order is load-bearing: `particles_modified!` restarts the unwrapped record at
  # the wrapped positions, so the stored unwrapped positions are copied AFTER it — and it discards
  # the sample history, so the stored history is restored after it too.
  sg = _require_group(g, "state", "read_simulation")
  _require_tag(sg, "state", "read_simulation", "GBGIsotropicTurbulence.ResolvedFields")
  _load_field!(sim.state.velocity_spectral, sg, "velocity_spectral", "read_simulation")
  scalar && _load_field!(sim.state.scalar_spectral, sg, "scalar_spectral", "read_simulation")
  fields_modified!(sim)
  if has_tracers
    copyto!(point_coordinates(sim.tracers.positions), point_coordinates(positions_host))
    particles_modified!(sim)
    if haskey(tg, "unwrapped_positions")
      copyto!(point_coordinates(sim.tracers.unwrapped_positions),
              point_coordinates(read_points(tg, "unwrapped_positions")))
    end
  end
  deposit!(sim)
  if has_tracers && haskey(g, "sample_history")
    hg = _require_group(g, "sample_history", "read_simulation")
    steps = a["history_steps"]
    depth = length(sim.cache.velocity_at_particles_history)
    n = min(Int(a["history_filled"]), depth)
    for j in 1:n
      row = read_points(hg, "row$j")
      copyto!(point_values(sim.cache.velocity_at_particles_history[j]), point_values(row))
      sim.cache.history_steps[j] = steps[j]
    end
    sim.cache.history_filled = n
  end
  sim.clock.time = a["time"]
  sim.clock.step = Int(a["step"])
  return sim
end


# The sugar, matching the field library's: `parent[name] = object` for each persisted type. The
# concrete parent types keep these strictly more specific than HDF5's own dataset-writing
# `setindex!`, never ambiguous with it.
for (T, writer) in ((:FixedDomain, :write_domain), (:ResolvedFields, :write_state),
                    (:Tracers, :write_tracers), (:AbstractForcing, :write_forcing),
                    (:Simulation, :write_simulation))
  @eval function Base.setindex!(parent::Union{HDF5.File, HDF5.Group}, object::$T,
                                name::AbstractString)
    $writer(parent, name, object)
    return parent
  end
end

end # module GBGIsotropicTurbulenceHDF5Ext
