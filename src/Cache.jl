# Cache — the observables cache: the storage where a component of the iteration puts a value another
# component (or an observation) will read. The design is the no-recompute rule
# (docs/src/observables_cache.md): the schedule is fixed at construction and identical on every
# iteration; every slot is deposited at the end of the iteration from the state it has just
# produced; a read either finds a current value or throws — there is no path, internal or on
# request, by which reading causes a computation. A slot IS the register its producer computes in:
# mid-iteration the step takes the array as stage scratch (marking its epoch as scratch), and the
# closing deposit re-fills it, so caching adds nothing to what an iteration computes, moves, or stores.

"""
    Cache

The observables cache — where the iteration leaves the observables it produces, for the run's own
components and any observation to read.

Each slot carries the value **and** the moment that value belongs to, so a read can be refused
rather than served stale. That moment is the slot's **epoch**, and the cache keeps two epoch
counters saying what the current moment is: one for the resolved fields, one for the tracer
positions. A slot is readable exactly when its own epoch equals the counter it depends on.

!!! note "An epoch is not an iteration number"
    An epoch counts *changes to the state*, not advances of the run. A completed
    [`step!`](@ref GBGIsotropicTurbulence.Propagator.step!) advances the fields epoch, but so does
    any announced out-of-band mutation — so a run at step 2 may stand at fields epoch 4. The epoch
    answers "is this value still the right one?"; the clock's
    [`current_step`](@ref GBGIsotropicTurbulence.SimulationRun.current_step) answers "how far has
    the run gone?".

The cache's operations:
- [`ObservablesCache`](@ref) — the cache itself: the slots, their epochs, and the two counters.
- [`fields_modified!`](@ref), [`particles_modified!`](@ref) — announce a state or tracer
  mutation made outside the iteration, so the affected slots go stale and reads throw until the
  next deposit.
- [`velocity_physical`](@ref), [`vorticity_physical`](@ref), [`scalar_physical`](@ref) — the checked
  reads of the cached fields (the velocity, vorticity, and scalar in physical representation).
- [`max_speed`](@ref GBGIsotropicTurbulence.Observables.max_speed) — the cached maximum velocity
  component, the number the timestep choice reads (one
  generic with the field reduction in `Observables`, whose docstring is the home).
- [`particle_velocities`](@ref) — the checked read of the particle velocities
  ``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))``, the velocity sampled along each trajectory.

The solver's side of the contract is [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!)
— homed in `Propagator`, with the iteration it closes — which fills every slot at the iteration's
end and sets its epoch; internal per-slot deposit and take verbs move the individual epochs. A
caller reads through the accessors and never deposits.
"""
module Cache

using GBGPeriodicFields: point_values
using ..SimulationDomain: FixedDomain, new_vector_field_physical, new_scalar_field_physical
import ..Observables: max_speed           # one generic: the field reduction there, the cached read here

export ObservablesCache, velocity_physical, vorticity_physical, scalar_physical,
       particle_velocities, fields_modified!, particles_modified!


# Epoch sentinels. A slot's epoch is the fields epoch it was deposited at; the sentinels mark the
# two states with no value: never deposited (fresh construction, or a cleared cache) and taken as a
# producer's mid-iteration scratch.
const NEVER_DEPOSITED = -2
const SCRATCH = -1


"""
    ObservablesCache(domain; scalar = false, particle_velocities = nothing)

The observables cache of a run — the storage where each iteration deposits, at its end, the
observables its own schedule produces: the velocity ``\\boldsymbol{u}`` and vorticity
``\\boldsymbol{\\omega}`` in physical representation, the scalar ``\\varphi`` in physical
representation when the run carries one, the fastest flow speed on the grid (the
[`max_speed`](@ref GBGIsotropicTurbulence.Observables.max_speed) number
the next timestep choice reads), and — when the run advects tracers — the particle velocities
``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))``. The contents are automatic — derived from the
configuration, never declared: the cache holds exactly what the iteration computes, materializes,
and leaves alive at the iteration's end, and nothing may be added on any cost axis.

Build it on a [`FixedDomain`](@ref) `domain`; pass `scalar = true` when the run evolves a passive
scalar (it adds the scalar's slot), and `particle_velocities` — the tracer set's own point-value
storage — when the run advects tracers: the slot IS that storage, so the tracers' push writes the
values and the cache only records which epochs they belong to. The [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) front door —
the build-everything convenience constructor — builds,
wires, and seeds one for you.

Read through the accessors — [`velocity_physical`](@ref), [`vorticity_physical`](@ref),
[`scalar_physical`](@ref), and `max_speed` — each of which returns the deposited value or throws.
Nothing in the cache is ever recomputed: a read that finds a stale, taken, or never-deposited slot
reports a scheduling error — it throws an `ErrorException` whose message names the slot and which
of the three states it is in — and the only repair is to fix the schedule that failed to deposit.

!!! note
    A slot is also the array its producer computes in: between deposits the step writes its own
    stage values there, so a cached field is meaningful only between iterations. Treat every
    returned array as read-only — it is the storage the next iteration will work in.

# Fields
- `velocity_physical`, `vorticity_physical` — the cached velocity and vorticity in physical
  representation. Mid-iteration the step also computes its stage recoveries *into these same
  arrays*, which is why they are not readable then.
- `scalar_physical` — the cached scalar in physical representation, or `nothing` for a scalar-free run.
- `max_speed` — the cached fastest flow speed (a host number).
- `particle_velocities` — the particle-velocities slot, or `nothing` for a tracer-free run.
- `velocity_epoch`, `vorticity_epoch`, `scalar_epoch`, `max_speed_epoch` — the epoch each slot's
  value belongs to, or a sentinel (never deposited / in use as scratch).
- `sample_fields_epoch`, `sample_particles_epoch` — the particle velocities' epochs against **both**
  counters, since that sample is a function of the state and the positions together.
- `fields_epoch` — the resolved fields' counter: advanced by every completed step and by
  [`fields_modified!`](@ref). A field-derived slot is readable exactly when its epoch equals this.
- `particles_epoch` — the tracer positions' counter, advanced by the tracer push.
"""
mutable struct ObservablesCache{PV, PS, TS}
  const velocity_physical::PV
  const vorticity_physical::PV
  const scalar_physical::PS
  const particle_velocities::TS
  velocity_epoch::Int
  vorticity_epoch::Int
  scalar_epoch::Int
  max_speed::Float64
  max_speed_epoch::Int
  sample_fields_epoch::Int
  sample_particles_epoch::Int
  fields_epoch::Int
  particles_epoch::Int
end

ObservablesCache(domain::FixedDomain; scalar::Bool = false, particle_velocities = nothing) =
  ObservablesCache(new_vector_field_physical(domain), new_vector_field_physical(domain),
                   scalar ? new_scalar_field_physical(domain) : nothing,
                   particle_velocities,
                   NEVER_DEPOSITED, NEVER_DEPOSITED, NEVER_DEPOSITED,
                   NaN, NEVER_DEPOSITED, NEVER_DEPOSITED, NEVER_DEPOSITED, 1, 1)


# The checked read shared by every accessor: serve the slot only when its epoch names the current
# fields epoch; otherwise throw with the schedule-facing message.
function _checked(cache::ObservablesCache, epoch::Int, what::String)
  epoch == cache.fields_epoch && return nothing
  if epoch == SCRATCH
    error("the cached $what is in use as a producer's scratch: mid-iteration the slot holds a " *
          "stage intermediate, not the observable; read it only between iterations")
  elseif epoch == NEVER_DEPOSITED
    error("the cached $what was never deposited: the schedule of this run does not fill the slot " *
          "before this read (a fresh cache is seeded by its deposit at construction)")
  else
    error("the cached $what is stale: the state has advanced past the deposited value, and " *
          "nothing in the cache is ever recomputed; read between iterations, after the closing deposit")
  end
end


"""
    velocity_physical(cache)

The velocity ``\\boldsymbol{u}`` in physical representation at the current epoch — the checked
read of the [`ObservablesCache`](@ref) `cache`'s velocity slot. Returns the deposited field when its
epoch is current, and throws otherwise (the slot is mid-iteration scratch, stale, or was never
deposited): the throw is an `ErrorException` naming the slot and which of the three states it is in,
and nothing is ever recomputed on a read. Treat the returned field as read-only — it is the
storage the next iteration works in.
"""
function velocity_physical(cache::ObservablesCache)
  _checked(cache, cache.velocity_epoch, "velocity")
  return cache.velocity_physical
end


"""
    vorticity_physical(cache)

The vorticity ``\\boldsymbol{\\omega} = \\nabla\\times\\boldsymbol{u}`` in physical representation
at the current epoch — the checked read of the [`ObservablesCache`](@ref) `cache`'s vorticity
slot, with exactly [`velocity_physical`](@ref)'s contract (the deposited field or a throw; never a
recomputation; read-only). The deposited value is produced by
[`vorticity_physical!`](@ref GBGIsotropicTurbulence.Observables.vorticity_physical!) — measure with
that function, read with this one.
"""
function vorticity_physical(cache::ObservablesCache)
  _checked(cache, cache.vorticity_epoch, "vorticity")
  return cache.vorticity_physical
end


"""
    scalar_physical(cache)

The scalar ``\\varphi`` in physical representation at the current epoch — the checked read of the
[`ObservablesCache`](@ref) `cache`'s scalar slot, with exactly [`velocity_physical`](@ref)'s
contract (the deposited field or a throw; never a recomputation; read-only). Throws an
`ArgumentError` when the run carries no scalar.
"""
function scalar_physical(cache::ObservablesCache)
  cache.scalar_physical === nothing &&
    throw(ArgumentError("this run carries no passive scalar, so the cache has no scalar slot"))
  _checked(cache, cache.scalar_epoch, "scalar")
  return cache.scalar_physical
end


# The cached-number read of the maximum speed. The generic and its docstring are homed in
# `Observables` (the field reduction); this method extends it with the checked cached read.
function max_speed(cache::ObservablesCache)
  _checked(cache, cache.max_speed_epoch, "maximum speed")
  return cache.max_speed
end


"""
    particle_velocities(cache)

The particle velocities ``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))`` at the current epoch — the
``(M, 3)`` array of the flow velocity sampled at the position each tracer occupies at that instant:
the genuine Lagrangian velocity the statistics accumulate. The checked read of the
[`ObservablesCache`](@ref) `cache`'s particle-velocities slot: it serves the deposited values or
throws, like every cached read — the sample depends on the state **and** the positions, so it is
current only when both counters match its own. Throws an `ArgumentError` when the run advects no
tracers.

"""
function particle_velocities(cache::ObservablesCache)
  cache.particle_velocities === nothing &&
    throw(ArgumentError("this run advects no tracers, so the cache has no particle-velocities slot"))
  cache.sample_fields_epoch == cache.fields_epoch &&
    cache.sample_particles_epoch == cache.particles_epoch ||
    error("the cached particle velocities are stale: the state or the tracer positions have advanced " *
          "past the deposited values, and nothing in the cache is ever recomputed; read " *
          "between iterations, after the closing deposit")
  return point_values(cache.particle_velocities)
end


# ————————————————————————————————————————————————————————————————————————————————————————————————
# The producers' side: take a slot as scratch (its epoch goes to SCRATCH), deposit into it (its
# epoch becomes the current fields epoch). Deposits happen at the end of the iteration, from the state it has
# just produced; the completeness check refuses to close an iteration with an undeposited slot.

# Take a slot's array as mid-iteration scratch. The epoch goes to SCRATCH, so a read between the
# take and the next deposit throws instead of returning a stage intermediate.
take_velocity!(cache::ObservablesCache) = (cache.velocity_epoch = SCRATCH; cache.velocity_physical)
take_vorticity!(cache::ObservablesCache) = (cache.vorticity_epoch = SCRATCH; cache.vorticity_physical)
take_scalar!(cache::ObservablesCache) = (cache.scalar_epoch = SCRATCH; cache.scalar_physical)

# Mark a slot as holding the observable at the current fields epoch. The producer writes the value
# into the slot's array first, then sets the epoch.
deposit_velocity!(cache::ObservablesCache) = (cache.velocity_epoch = cache.fields_epoch; cache.velocity_physical)
deposit_vorticity!(cache::ObservablesCache) = (cache.vorticity_epoch = cache.fields_epoch; cache.vorticity_physical)
deposit_scalar!(cache::ObservablesCache) = (cache.scalar_epoch = cache.fields_epoch; cache.scalar_physical)
deposit_max_speed!(cache::ObservablesCache, value::Real) =
  (cache.max_speed = Float64(value); cache.max_speed_epoch = cache.fields_epoch; value)
deposit_sample!(cache::ObservablesCache) =
  (cache.sample_fields_epoch = cache.fields_epoch;
   cache.sample_particles_epoch = cache.particles_epoch; cache.particle_velocities)


# The deposit-completeness check: every slot the configuration carries must sit at the
# current epoch when an iteration closes. No caller can fail this — a slot exists only because the
# schedule fills it — so a throw here names a solver bug at its source rather than letting the slot
# hold scratch for the rest of the run.
function check_deposits(cache::ObservablesCache)
  cache.velocity_epoch == cache.fields_epoch ||
    error("iteration closed with the velocity slot undeposited — a solver scheduling bug")
  cache.vorticity_epoch == cache.fields_epoch ||
    error("iteration closed with the vorticity slot undeposited — a solver scheduling bug")
  cache.scalar_physical === nothing || cache.scalar_epoch == cache.fields_epoch ||
    error("iteration closed with the scalar slot undeposited — a solver scheduling bug")
  cache.max_speed_epoch == cache.fields_epoch ||
    error("iteration closed with the maximum speed undeposited — a solver scheduling bug")
  cache.particle_velocities === nothing ||
    (cache.sample_fields_epoch == cache.fields_epoch &&
     cache.sample_particles_epoch == cache.particles_epoch) ||
    error("iteration closed with the particle velocities undeposited — a solver scheduling bug")
  return cache
end


"""
    fields_modified!(cache)

Announce that the resolved fields — ``\\hat{\\boldsymbol{u}}`` and ``\\hat\\varphi``, in spectral
representation —
were changed outside the iteration (a re-seeded velocity, any direct write to the state's storage).
Advances the fields epoch of `cache`, so every cached observable is stale and reads throw until
the next deposit; that interval belongs to whoever made the change. Returns `cache`.

The sanctioned mutators call this for you: [`step!`](@ref GBGIsotropicTurbulence.Propagator.step!)
advances the epoch itself when it completes, and
the iteration's closing deposit then restores the cache. After a hand-made mutation, re-deposit with the
run layer's [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!) before advancing again —
the timestep choice reads the cached maximum speed.
"""
fields_modified!(cache::ObservablesCache) = (cache.fields_epoch += 1; cache)


"""
    particles_modified!(cache)

Announce that the tracer positions were changed outside the iteration (a reseed, a hand-written
correction, any direct write to the tracer storage) — the particle counterpart of
[`fields_modified!`](@ref). Advances the particles epoch of `cache`, so every
trajectory-bound observable is stale and reads throw until the next deposit. Returns `cache`.

The sanctioned mutator calls it for you: the run layer's tracer push announces its own advance, and
the closing deposit then re-records the sample at the new epoch. A hand-run loop that repositions tracers itself must
call this, then re-record the trajectory sample before advancing.
"""
particles_modified!(cache::ObservablesCache) = (cache.particles_epoch += 1; cache)


end # module Cache
