# Particles — the Lagrangian particles a run carries, as state and as a place to measure. Tracers are
# positions in the periodic box; any physical field can be sampled at them through the package's
# grid→point interpolation (a selectable `GBGPeriodicFields` spline scheme; `CatmullRom` by default,
# `LalescuSpline`/`LagrangeSpline` for higher order), and a `ParticleTrail` keeps the last few
# samples of one quantity with their times, so that its time derivative along the trajectories can
# be taken. Accumulating statistics over the samples is the caller's analysis, not this package's.
#
# What advances the positions in time is not here: the schemes and the step live in
# `ParticlePropagator`, which loads after the observables cache it reads. This module loads before
# the cache, because the cache holds a trail of the velocity at the particles.

"""
    Particles

It holds Lagrangian particles, today the massless tracer, and what is measured at them:

- [`Tracers`](@ref) — the tracer set: the positions (a
  [`PointSet`](@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet)), a selectable
  interpolation scheme, and opt-in unwrapped positions read by [`unwrapped_positions`](@ref).
- [`interpolate_at_particles!`](@ref) — read a field at the particle positions; [`new_vector_point_values`](@ref) /
  [`new_scalar_point_values`](@ref) allocate the output buffers it fills.
- [`ParticleTrail`](@ref) — the last few samples of one quantity at the particles, each with its
  time; [`time_derivative!`](@ref) and [`time_derivative`](@ref) differentiate it in time along
  the trajectories. The run keeps one for the velocity, read through
  [`velocity_at_particles_trail`](@ref GBGHomogeneousTurbulence.Cache.velocity_at_particles_trail).
- [`ParticleTraversal`](@ref) — the memory-locality order the gathers visit the tracers in, a
  value-preserving accelerator; [`rebuild_traversal!`](@ref) refreshes it from the current
  positions.
- [`write_tracers`](@ref) / [`read_tracers`](@ref) and [`write_trail`](@ref) /
  [`read_trail`](@ref) — the HDF5 persistence of a tracer set and of a trail, each as one
  self-describing group (available once `HDF5` is loaded).

The schemes that advance the positions are in
[`ParticlePropagator`](@ref GBGHomogeneousTurbulence.ParticlePropagator).
"""
module Particles

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, _real_type

export Tracers, ParticleTraversal, rebuild_traversal!, interpolate_at_particles!,
       unwrapped_positions, new_vector_point_values, new_scalar_point_values,
       ParticleTrail, time_derivative!, time_derivative


"""
    Tracers(domain; number_of_particles, interpolation_scheme, unwrapped = false,
            rng = default_rng())
    Tracers(domain; positions, interpolation_scheme, unwrapped = false)

A set of Lagrangian tracers, built on `domain`'s backend and element type.

Give exactly one of the two. The `number_of_particles` form seeds that many tracers uniformly
at random in the periodic box. The `positions` form supplies the tracer positions as a [`GBGPeriodicFields`](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/)
[`PointSet`](@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet), copied to `domain`'s
backend and element type. Supplying both, or neither, raises an `ArgumentError`, and so does a raw
array in place of the `PointSet`: coordinates cross into the package only through the
`GBGPeriodicFields` point types.

The `interpolation_scheme` is the `GBGPeriodicFields` scheme used to evaluate the velocity — and any
sampled field — at the tracer positions.
[`CatmullRom`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.CatmullRom) is the ``C^1``
choice and [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation)'s default; it is a ready-made value rather than a type, so it is passed
bare. [`LalescuSpline`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.LalescuSpline)
and [`LagrangeSpline`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.LagrangeSpline)
offer higher smoothness or interpolation order at a wider stencil — useful for derivative-sensitive
readouts such as acceleration statistics. Each takes its stencil width in grid points per axis
(`CatmullRom` is `LalescuSpline(4)`), and `LalescuSpline` also takes its order of continuity as the
`smoothness` keyword.

# Arguments

- `domain` — the [`FixedDomain`](@ref) whose backend, element type and box the set is built on.
- `number_of_particles` — seed this many tracers uniformly at random in the box.
- `positions` — or copy this `PointSet` in instead; give exactly one of the two.
- `interpolation_scheme` — the scheme used to evaluate a field at the tracer positions.
- `unwrapped = false` — set to `true` to also track the winding-preserving unwrapped positions
  [`unwrapped_positions`](@ref) serves; the wrapped positions stay the dynamical state either way.
- `rng` — the random stream seeding the positions (used with `number_of_particles`, ignored with
  `positions`); defaults to `Random.default_rng()`.

# Examples

A run carries tracers when `Simulation` is given a count;
[`advance!`](@ref GBGHomogeneousTurbulence.SimulationRun.advance!) then advances them with the
fields and records the Lagrangian velocity each iteration, so both reads below are current between
iterations:

```julia
sim = Simulation(grid_points_per_axis = 64, scalar = PassiveScalar(),
                 particles = ParticleTracking(number_of_particles = 4096))
advance!(sim)

# the (M, 3) positions, via GBGPeriodicFields
X = point_positions(sim.tracers.positions)
# u(tₙ, X(tₙ)), the Lagrangian velocity — throws if stale
v = velocity_at_particles_trail(sim.cache)[0].value

out = new_scalar_point_values(sim.tracers)  # allocate once, then reuse every iteration
interpolate_at_particles!(out, scalar_physical(sim.cache), sim.tracers)
```

Building a set directly, to place tracers deliberately rather than at random, takes the
`positions` form, and a run adopts the set through
[`ParticleTracking`](@ref GBGHomogeneousTurbulence.SimulationRun.ParticleTracking):

```julia
tracers = Tracers(domain; positions = PointSet([0.1 0.2 0.3; 1.0 1.0 1.0]),
                  interpolation_scheme = CatmullRom)
sim = Simulation(domain; particles = ParticleTracking(tracers))
```

Read the particle state straight off the struct's own fields — the positions are
[`PointSet`](@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet)s, and raw arrays and
counts come from `GBGPeriodicFields`'
[`point_positions`](@extref GBGPeriodicFields GBGPeriodicFields.Points.point_positions) and
[`npoints`](@extref GBGPeriodicFields GBGPeriodicFields.Points.npoints), never from accessors of
this package. Passing `unwrapped = true` additionally tracks the winding-preserving
unwrapped positions `unwrapped_positions` serves — the wrapped positions stay the dynamical
state either way. The velocities are a *deposited observable*, not tracer state: the particle form
of [`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!) writes them into the run's observables cache at the end of each iteration, and
[`velocity_at_particles_trail`](@ref GBGHomogeneousTurbulence.Cache.velocity_at_particles_trail) reads them there.

# Fields
- `positions` — the tracer positions, as the
  [`PointSet`](@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet) every operation takes:
  the one storage, always wrapped — the dynamical state. `GBGPeriodicFields`' `point_positions`
  serves its `(M, 3)` matrix view, with ``M`` the tracer count.
- `interpolation_scheme` — the scheme used to evaluate a field at the tracer positions.
- `unwrapped_positions` — the opt-in unwrapped positions (`unwrapped = true`) as a `PointSet`, advanced
  by every push with the same displacement terms but never reduced to the box; `nothing` when
  untracked. Read it through `unwrapped_positions`.
"""
struct Tracers{PSX, S, UP}
  positions::PSX      # PointSet — the (always wrapped) dynamical state; the ONE storage
  interpolation_scheme::S
  unwrapped_positions::UP      # PointSet (the opt-in unwrapped positions, winding kept), or nothing
end


# The two forms, given `positions` or a `number_of_particles` to seed, are ONE method, not two: they are distinguished by which keyword is supplied, and
# Julia dispatches on positional arguments only. Hence the explicit either/or check, which also gives
# a better error than a missing-keyword one would.
function Tracers(domain::FixedDomain; interpolation_scheme, positions = nothing,
                 number_of_particles = nothing, unwrapped::Bool = false,
                 rng = Random.default_rng())
  count(!isnothing, (positions, number_of_particles)) == 1 ||
    throw(ArgumentError("give exactly one of `positions` (a `PointSet` of tracer positions) or " *
                        "`number_of_particles` (a count to seed at random)"))
  T = _real_type(domain)
  if isnothing(positions)
    M = Int(number_of_particles)
    pos = domain.array_family{T}(undef, M, 3)
    # Drawn on the host so one seed gives the same positions on every backend (decision 107), and
    # scaled in place: on the CPU the kept array IS host memory and takes the draw directly; on a
    # device one host array is drawn into and moved.
    host = domain.array_family === Array ? pos : Array{T}(undef, M, 3)
    rand!(rng, host)
    host .*= T(domain.grid.domain_size[1])
    host === pos || copyto!(pos, host)
  else
    positions isa PointSet ||
      throw(ArgumentError("`positions` must be a `GBGPeriodicFields` `PointSet` (wrap an (M, 3) " *
                          "array with `PointSet(array)`); got a $(typeof(positions)). Raw arrays " *
                          "cross into the package only through the `GBGPeriodicFields` point types."))
    supplied = point_positions(positions)
    pos = domain.array_family{T}(undef, size(supplied)...)    # the domain's backend + element type
    copyto!(pos, supplied)
  end
  # The unwrapped record starts equal to the wrapped positions and thereafter receives the same
  # displacements WITHOUT the periodic reduction (the grid-free `displace!` — PF's universal-cover
  # lift), so the two can never disagree on a step, only on the winding the wrap discards.
  return Tracers(PointSet(pos), interpolation_scheme,
                 unwrapped ? PointSet(copy(pos)) : nothing)
end


"""
    ParticleTraversal(domain, tracers; automatic = true)

The memory-locality order in which a field is gathered at the tracers — a
[`PointTraversalOrder`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.PointTraversalOrder)
over the tracer set `tracers` on the grid of `domain` (a [`FixedDomain`](@ref)), together with the
scratch that lets it be rebuilt in place. Tracers seeded at random, or mixed by the flow, visit the
grid in no order at all, so each interpolation stencil is a cache miss; visiting them
tile-by-tile turns the gather into a sweep, and `GBGPeriodicFields`' `interpolate!` accepts such an
order through its `traversal` keyword. The order only reorders the visits — it changes no value,
so a run with and without it produces bitwise-identical trajectories and samples.

A run builds one for you: the `traversal_mode` of its
[`ParticleTracking`](@ref GBGHomogeneousTurbulence.SimulationRun.ParticleTracking) decides whether,
and whether the run or the caller rebuilds it.
A caller's own gather takes it through the `traversal` keyword of
[`interpolate_at_particles!`](@ref); on a run, that is `sim.particle_traversal`.

# Arguments

- `domain` — the `FixedDomain` whose grid the tiles are laid over.
- `tracers` — the [`Tracers`](@ref) whose positions are ordered; the order is sized to their count
  and built from their current positions.
- `automatic = true` — whether a run rebuilds the order every iteration (`true`) or leaves the
  rebuilding to the caller, through [`rebuild_traversal!`](@ref) (`false`). A rebuild costs a small
  fraction of the gather it accelerates, so every iteration is the default; a stale order is never
  wrong, only progressively less useful as the flow mixes the tracers away from it.

!!! note "One order serves every gather of the step"
    `GBGPeriodicFields` accepts any same-length order for a point set of the same count, so the one
    order built from the tracer positions is also passed to the gather at the predicted positions
    a [`Heun`](@ref GBGHomogeneousTurbulence.ParticlePropagator.Heun) step makes; those sit a step's displacement from the tracers, well inside the
    tiles the order groups.

# Fields
- `order` — the `PointTraversalOrder`: one `Int32` index per tracer, a permutation of the visits.
- `scratch` — the
  [`PointTraversalOrderScratch`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.PointTraversalOrderScratch)
  the in-place rebuild sorts in: the per-tracer tile keys and the per-tile counts and offsets.
- `automatic` — whether a run rebuilds the order every iteration.
"""
struct ParticleTraversal{O, S}
  order::O           # PointTraversalOrder — the Int32 permutation the gathers visit the tracers in
  scratch::S         # PointTraversalOrderScratch — the counting-sort scratch of the in-place rebuild
  automatic::Bool    # a run rebuilds every iteration (true), or the caller does through rebuild_traversal!
end


# Built through the in-place rebuild with the scratch the run keeps: the allocating
# `point_traversal_order` would make a second, temporary sorting scratch beside it. The identity
# permutation is the starting order the rebuild overwrites.
function ParticleTraversal(domain::FixedDomain, tracers::Tracers; automatic::Bool = true)
  coordinates = point_positions(tracers.positions)
  scratch = PointTraversalOrderScratch(domain.grid, tracers.positions)
  identity = similar(coordinates, Int32, size(coordinates, 1))
  identity .= Int32(1):Int32(length(identity))
  order = point_traversal_order!(PointTraversalOrder(identity), domain.grid, tracers.positions, scratch)
  return ParticleTraversal(order, scratch, automatic)
end


"""
    rebuild_traversal!(traversal, domain, tracers) -> traversal
    rebuild_traversal!(sim) -> sim

Rebuild the tracer traversal order from the current tracer positions, in place.

# Arguments
- `traversal` — the [`ParticleTraversal`](@ref) to rebuild.
- `domain` — the [`FixedDomain`](@ref) whose grid the order is taken on.
- `tracers` — the tracer set whose positions are ordered.
- `sim` — a run ([`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation)), in the second
  form: the traversal it carries as `sim.particle_traversal` is rebuilt.

Call it from a run's callback when the run was built with `traversal_mode = :manual`, at
whatever cadence you choose — every so many steps with
[`every_steps`](@ref GBGHomogeneousTurbulence.SimulationRun.every_steps), or every so much time with
[`every_time`](@ref GBGHomogeneousTurbulence.SimulationRun.every_time). With the default automatic
mode the run rebuilds every iteration and the call is never needed. The rebuild allocates nothing
at the tracer scale; a run without a traversal order refuses the call with an `ArgumentError`.
"""
function rebuild_traversal! end

# The order a gather hands to the field library: the `traversal` keyword takes the `ParticleTraversal`
# itself, or `nothing` for a gather in tracer order.
_order(::Nothing) = nothing
_order(traversal::ParticleTraversal) = traversal.order


function rebuild_traversal!(traversal::ParticleTraversal, domain::FixedDomain, tracers::Tracers)
  point_traversal_order!(traversal.order, domain.grid, tracers.positions, traversal.scratch)
  return traversal
end


"""
    interpolate_at_particles!(out, field, tracers; traversal = nothing) -> out

Sample a physical field at the current tracer positions. This is how a field is gathered along the
trajectories; what is then accumulated over those values is the caller's own analysis.

# Arguments
- `out` — the point-value buffer written: a
  [`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) for the
  velocity, a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues)
  for the scalar ``\\varphi``.
- `field` — the field in physical representation.
- `tracers` — the tracer set, whose positions and interpolation scheme are used.
- `traversal = nothing` — a [`ParticleTraversal`](@ref), to gather in its memory-locality order
  (on a run, `sim.particle_traversal`); `nothing` gathers in tracer order, with identical values.
"""
function interpolate_at_particles!(out, field, tracers::Tracers; traversal = nothing)
  interpolate!(out, field, tracers.positions, tracers.interpolation_scheme; traversal = _order(traversal))
  return out
end


"""
    unwrapped_positions(tracers)

The *unwrapped* positions of the tracer set `tracers`, as a
[`PointSet`](@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet) — the trajectory with its
winding kept, each coordinate the literal sum of every displacement since seeding, never reduced to
the periodic box. These are the positions a mean-square-displacement or dispersion diagnostic
needs: those are functions of the displacement ``\\boldsymbol{X}(t) - \\boldsymbol{X}(0)``, with
``\\boldsymbol{X}`` a tracer's position, which box-wrapped
positions cannot supply across a crossing. Accumulating such statistics over them — on the raw
`(M, 3)` array `GBGPeriodicFields`'
[`point_positions`](@extref GBGPeriodicFields GBGPeriodicFields.Points.point_positions) extracts —
is the caller's analysis.

The unwrapped positions exist only when the tracer set was built with `unwrapped = true`; reading
an untracked set throws an `ArgumentError` (which is why this throwing read exists while the plain
state is read straight off the struct's fields). The wrapped positions remain the dynamical state either
way — the dynamics always advance wrapped, since a coordinate that grows with winding loses
absolute floating-point resolution, while the unwrapped positions only ever feed differences,
whose *relative* accuracy the growth does not touch.
"""
function unwrapped_positions(tracers::Tracers)
  tracers.unwrapped_positions === nothing &&
    throw(ArgumentError("this tracer set carries no unwrapped positions: build it with " *
                        "`unwrapped = true` (a `Tracers` keyword, forwarded by `Simulation`) " *
                        "to track winding alongside the wrapped positions"))
  return tracers.unwrapped_positions
end


"""
    new_vector_point_values(tracers)

Allocate a [`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) of
shape `(M, 3)` matching the tracer set `tracers`, for use as the `out` of
[`interpolate_at_particles!`](@ref) when sampling the velocity at the particle positions.
"""
new_vector_point_values(tracers::Tracers) = VectorPointValues(similar(point_positions(tracers.positions)))

"""
    new_scalar_point_values(tracers)

Allocate a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues) of
length ``M``, the number of tracers in the set `tracers`, for use as the `out` of
[`interpolate_at_particles!`](@ref) when sampling the scalar ``\\varphi`` at the particle positions.
"""
new_scalar_point_values(tracers::Tracers) =
  ScalarPointValues(similar(point_positions(tracers.positions),
                            eltype(point_positions(tracers.positions)),
                            npoints(tracers.positions)))


# ————————————————————————————————————————————————————————————————————————————————————————————————
# The trail: a fixed number of slots used as a ring. Nothing is ever copied from slot to slot — a
# new sample is written into the slot after the newest, which is the oldest once the ring is full.
# A slot is readable exactly while it lies in the index range `1 - filled : 0`; a slot outside it
# (never filled, or handed out to be written) is reachable by no public call.

"""
    ParticleTrail(allocator, tracers, capacity)

The last few samples of one quantity at the particles, each kept with the simulation time it was
taken at — the record a time derivative along the trajectories is computed from
([`time_derivative!`](@ref)). A *sample* is the quantity's value at every particle together with its
time. The trail keeps at most `capacity` of them, and adding one to a full trail drops the oldest:
it serves derivatives, and a long history is the caller's to keep, more sparsely.

# Arguments
- `allocator` — a function of `tracers` that returns one fresh point-values object:
  [`new_scalar_point_values`](@ref) or [`new_vector_point_values`](@ref). It is called `capacity`
  times, so the trail owns all of its storage and adding a sample allocates nothing.
- `tracers` — the [`Tracers`](@ref) the values are sized to.
- `capacity` — the largest number of samples kept, at least 1.

A sample is read by its offset in steps from the newest: `trail[0]` is the newest, `trail[-1]` the
one before it, and each is a named pair, `trail[-1].time` and `trail[-1].value`. A positive
index, or one further back than the samples present, is an `ArgumentError`. `length(trail)` is the
number of samples present, and iteration runs from the oldest to the newest. A value is the
trail's own storage, to be read and never written.

A sample is added with `push!`, which hands the storage to a function to fill — here a
[`do` block](https://docs.julialang.org/en/v1/manual/functions/#Do-Block-Syntax-for-Function-Arguments) —
and labels it with the time `t`, which must be later than the newest sample's. If the function
throws, no sample is added, and a full trail has by then given up its oldest:

```julia
push!(trail, t) do value
    interpolate_at_particles!(value, field, tracers)
end
```

The trail a run keeps for the velocity, read through
[`velocity_at_particles_trail`](@ref GBGHomogeneousTurbulence.Cache.velocity_at_particles_trail),
is filled by the run alone and refuses `push!`.

# Examples
The scalar along the trajectories and its rate of change, sampled once per iteration:

```julia
trail = ParticleTrail(new_scalar_point_values, sim.tracers, 3)
rate = new_scalar_point_values(sim.tracers)
run!(sim) do s
    push!(trail, current_time(s)) do value
        interpolate_at_particles!(value, scalar_physical(s.cache), s.tracers)
    end
    length(trail) == 3 && time_derivative!(rate, trail)
    current_step(s) < 100
end
```

# Fields
These are the trail's internals; read a trail through its indexing, never through them.

- `values`, `times` — the slots of the ring, one point-values object each, and the time of the
  sample in each.

- `newest`, `filled` — the slot of the newest sample, and how many slots hold one.

- `cache_owned` — whether the trail is a run's own, which `push!` refuses.

- `nodes`, `weights` — host scratch of `time_derivative!`.
"""
mutable struct ParticleTrail{V <: AbstractPointValues}
  const values::Vector{V}           # `capacity` point-value objects, the ring's slots
  const times::Vector{Float64}      # the time of the sample in each slot
  newest::Int                       # the slot of the newest sample; 0 while the trail is empty
  filled::Int                       # how many slots hold a sample, 0 … capacity
  const cache_owned::Bool           # the run's own trail: only the particle deposit adds to it
  # Host scratch of `time_derivative!`: the nodes and the differentiation weights, sized once.
  const nodes::Vector{Float64}
  const weights::Matrix{Float64}
end

function _new_trail(allocator, tracers::Tracers, capacity::Integer, cache_owned::Bool)
  capacity >= 1 ||
    throw(ArgumentError("`capacity` must be at least 1, got $capacity: a trail holds at least " *
                        "its newest sample"))
  first_slot = allocator(tracers)
  first_slot isa AbstractPointValues ||
    throw(ArgumentError("`allocator(tracers)` must return a `GBGPeriodicFields` point-values " *
                        "object — pass `new_scalar_point_values` or `new_vector_point_values`; " *
                        "it returned a $(typeof(first_slot))"))
  values = typeof(first_slot)[first_slot]
  for _ in 2:capacity
    push!(values, allocator(tracers))
  end
  return ParticleTrail(values, zeros(Float64, capacity), 0, 0, cache_owned,
                       zeros(Float64, capacity), zeros(Float64, capacity, capacity))
end

ParticleTrail(allocator, tracers::Tracers, capacity::Integer) =
  _new_trail(allocator, tracers, capacity, false)

# The capacity a particle integration scheme needs of the run's velocity trail. The generic is here,
# where the trail is, so that the cache can size its trail from the scheme; the schemes add their
# methods in `ParticlePropagator`.
function trail_capacity end

_capacity(trail::ParticleTrail) = length(trail.values)

# The slot of the sample `offset` steps back from the newest (`offset <= 0`, already checked).
_slot(trail::ParticleTrail, offset::Integer) = mod1(trail.newest + offset, _capacity(trail))

# The storage the next sample is written into. On a full trail the oldest sample is retired first,
# so a slot being written is already outside the readable range — and stays there if the writing
# fails. Asking twice returns the same slot: the second call finds the trail no longer full.
function _next_slot!(trail::ParticleTrail)
  trail.filled == _capacity(trail) && (trail.filled -= 1)
  return trail.values[_slot(trail, 1)]
end

function _check_time(trail::ParticleTrail, t::Real)
  isfinite(t) || throw(ArgumentError("a sample's time must be finite, got $t"))
  trail.filled == 0 || t > trail.times[trail.newest] ||
    throw(ArgumentError("a sample's time must be later than the newest sample's, " *
                        "$(trail.times[trail.newest]); got $t"))
  return Float64(t)
end

# Make the slot `_next_slot!` handed out the newest sample, at time `t`.
function _commit!(trail::ParticleTrail, t::Float64)
  slot = _slot(trail, 1)
  trail.times[slot] = t
  trail.newest = slot
  trail.filled += 1
  return trail
end

function _push!(fill_value!, trail::ParticleTrail, t::Real)
  time = _check_time(trail, t)
  fill_value!(_next_slot!(trail))
  return _commit!(trail, time)
end

_empty!(trail::ParticleTrail) = (trail.newest = 0; trail.filled = 0; trail)

function Base.push!(fill_value!::Function, trail::ParticleTrail, t::Real)
  trail.cache_owned &&
    throw(ArgumentError("this trail belongs to a run's observables cache, and the particle " *
                        "deposit closing each iteration is its only writer; keep a trail of " *
                        "your own with `ParticleTrail(allocator, tracers, capacity)`"))
  return _push!(fill_value!, trail, t)
end

# The two calls a reader of Base's `push!(collection, item)` would try. The trail hands out its own
# storage to be filled, so that adding a sample copies nothing; there is no form taking the values.
Base.push!(::ParticleTrail, ::Real) =
  throw(ArgumentError("a sample is added by filling the trail's own storage: " *
                      "`push!(trail, t) do value … end`"))
Base.push!(::ParticleTrail, ::AbstractPointValues, ::Real) =
  throw(ArgumentError("a sample is added by filling the trail's own storage, so nothing is " *
                      "copied: `push!(trail, t) do value … end`, writing into `value`"))

Base.length(trail::ParticleTrail) = trail.filled
Base.isempty(trail::ParticleTrail) = trail.filled == 0
Base.firstindex(trail::ParticleTrail) = 1 - trail.filled
Base.lastindex(::ParticleTrail) = 0
Base.keys(trail::ParticleTrail) = firstindex(trail):0
Base.eltype(::Type{ParticleTrail{V}}) where {V} = @NamedTuple{time::Float64, value::V}

function Base.getindex(trail::ParticleTrail, offset::Integer)
  offset <= 0 ||
    throw(ArgumentError("a trail is indexed by the offset in steps from its newest sample: " *
                        "`trail[0]` is the newest and `trail[-1]` the one before it; got $offset"))
  offset >= 1 - trail.filled ||
    throw(ArgumentError(offset >= 1 - _capacity(trail) ?
      "the trail holds only $(trail.filled) sample(s) so far, so it has no `trail[$offset]`" :
      "the trail's capacity is $(_capacity(trail)), so it never has a `trail[$offset]`"))
  slot = _slot(trail, offset)
  return (time = trail.times[slot], value = trail.values[slot])
end

Base.iterate(trail::ParticleTrail, offset::Int = firstindex(trail)) =
  offset > 0 ? nothing : (trail[offset], offset + 1)


# The weights of the derivatives of order 0 … `order` at zero of the polynomial through values at
# the first `n` of `nodes`: `weights[j, m + 1]` multiplies the value at node `j` in the derivative
# of order `m`. Fornberg's recursion (1988), which is stable on unevenly spaced nodes and costs
# O(n² · order) host arithmetic.
function _derivative_weights!(weights::Matrix{Float64}, nodes::Vector{Float64}, n::Int, order::Int)
  fill!(weights, 0.0)
  weights[1, 1] = 1.0
  product = 1.0
  previous_node = nodes[1]
  for i in 2:n
    highest = min(i - 1, order)
    new_product = 1.0
    last_node = previous_node
    previous_node = nodes[i]
    for j in 1:i-1
      distance = nodes[i] - nodes[j]
      new_product *= distance
      if j == i - 1
        for m in highest:-1:1
          weights[i, m + 1] = product * (m * weights[i - 1, m] - last_node * weights[i - 1, m + 1]) / new_product
        end
        weights[i, 1] = -product * last_node * weights[i - 1, 1] / new_product
      end
      for m in highest:-1:1
        weights[j, m + 1] = (nodes[i] * weights[j, m + 1] - m * weights[j, m]) / distance
      end
      weights[j, 1] = nodes[i] * weights[j, 1] / distance
    end
    product = new_product
  end
  return weights
end

# `out ← Σ coefficient · values` over the terms, or `out ← out + Σ …` when `continued`: one checked
# point-value broadcast, so the sum is a single pass on the CPU and a single kernel on a device.
function _assign_combination!(out::AbstractPointValues, terms::Tuple, continued::Bool)
  products = map(term -> Base.Broadcast.broadcasted(*, term[1], term[2]), terms)
  total = length(products) == 1 ? products[1] : Base.Broadcast.broadcasted(+, products...)
  Base.Broadcast.materialize!(out, continued ? Base.Broadcast.broadcasted(+, out, total) : total)
  return out
end

# How many samples one pass combines; a longer trail takes further passes, each continuing the sum.
const _TERMS_PER_PASS = 8


"""
    time_derivative!(out, trail; order = 1) -> out

The time derivative of the quantity a [`ParticleTrail`](@ref) holds, at the time of its newest
sample: writing ``f(t)`` for the quantity at one particle along its trajectory, ``\\mathrm{d}^{m}f/\\mathrm{d}t^{m}``
at ``t_n``, with ``m`` the order. For the run's velocity trail and ``m = 1`` this is the Lagrangian
acceleration.

It is the derivative of the polynomial through all the samples present, taken at their actual,
possibly uneven times. With ``d`` samples spaced ``\\Delta t`` apart the error is of order
``\\Delta t^{d - m}``, so the trail's capacity bounds the accuracy and a higher derivative needs a
longer trail.

# Arguments
- `out` — the point-values object written, of the same kind as the trail's values and not one of them.
- `trail` — the `ParticleTrail` to differentiate; it must hold at least `order + 1` samples, or
  the call is an `ArgumentError`.
- `order = 1` — the order ``m`` of the derivative; `0` copies the newest value.

The weights are computed on the host from the samples' times, by Fornberg's recursion,
and the values are combined in one pass over the particles, without allocating at their scale.
"""
function time_derivative!(out::AbstractPointValues, trail::ParticleTrail; order::Integer = 1)
  order >= 0 || throw(ArgumentError("`order` must be non-negative, got $order"))
  n = trail.filled
  n >= order + 1 ||
    throw(ArgumentError("a derivative of order $order needs at least $(order + 1) samples, and " *
                        "the trail holds $n"))
  any(value -> value === out, trail.values) &&
    throw(ArgumentError("`out` is one of the trail's own values; a derivative is written into " *
                        "storage the caller owns"))
  newest = trail[0]
  # A broadcast would spread a scalar per particle over the three components of a vector `out`
  # without complaint, so the kind is checked here; the count is the broadcast's own check.
  (point_value_tensor_order(out) == point_value_tensor_order(newest.value) &&
   eltype(out) == eltype(newest.value)) ||
    throw(ArgumentError("`out` must be point values of the trail's own kind, " *
                        "$(nameof(typeof(newest.value))){$(eltype(newest.value))}; got " *
                        "$(nameof(typeof(out))){$(eltype(out))}"))
  if order == 0
    Base.Broadcast.materialize!(out, Base.Broadcast.broadcasted(identity, newest.value))
    return out
  end
  for j in 1:n
    trail.nodes[j] = trail[1 - j].time - newest.time     # relative to the newest: 0, then negative
  end
  _derivative_weights!(trail.weights, trail.nodes, n, Int(order))
  T = eltype(out)
  for first in 1:_TERMS_PER_PASS:n
    last = min(first + _TERMS_PER_PASS - 1, n)
    terms = ntuple(i -> (T(trail.weights[first + i - 1, order + 1]), trail[2 - first - i].value),
                   last - first + 1)
    _assign_combination!(out, terms, first > 1)
  end
  return out
end


"""
    time_derivative(trail; order = 1)

The time derivative of the quantity a [`ParticleTrail`](@ref) holds, at the time of its newest
sample, in a newly allocated point-values object: the allocating form of
[`time_derivative!`](@ref), whose docstring states what is computed and how accurately.

# Arguments
- `trail` — the `ParticleTrail` to differentiate; one that holds no sample is an `ArgumentError`.
- `order = 1` — the order of the derivative; `0` returns a copy of the newest value.
"""
function time_derivative(trail::ParticleTrail; order::Integer = 1)
  isempty(trail) &&
    throw(ArgumentError("the trail holds no sample yet, so it has no derivative of any order"))
  return time_derivative!(similar_point_values(trail.values[1]), trail; order)
end



# ————————————————————————————————————————————————————————————————————————————————————————————————
# Display (the convention is stated once, at `SimulationDomain`'s display section). A tracer set
# is its positions through the field library's `show` (count, element type, storage — what a run
# refuses a tracer set on), its interpolation scheme, and the unwrapped record, which the unwrapped
# read refuses on — through its own display when kept, `no unwrapped positions` when not.

function Base.show(io::IO, tracers::Tracers)
  print(io, "Tracers(", tracers.positions, ", ", tracers.interpolation_scheme)
  isnothing(tracers.unwrapped_positions) ? print(io, ", no unwrapped positions") :
    print(io, ", unwrapped_positions ", tracers.unwrapped_positions)
  print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", tracers::Tracers)
  row(name, value) = print(io, "\n  ", rpad(name, 22), value)
  print(io, "Tracers")
  row("positions", tracers.positions)
  row("interpolation_scheme", tracers.interpolation_scheme)
  row("unwrapped_positions", something(tracers.unwrapped_positions, "nothing (no unwrapped positions)"))
end

# A trail is its values' kind and count through the field library's display of one slot, the
# capacity a scheme matches it on, how many samples it holds, and the newest one's time.
function Base.show(io::IO, trail::ParticleTrail)
  print(io, "ParticleTrail(", trail.values[1], ", capacity ", _capacity(trail), ", ")
  trail.filled == 0 ? print(io, "no samples") :
    print(io, trail.filled, trail.filled == 1 ? " sample" : " samples", ", newest at time ",
          trail.times[trail.newest])
  print(io, ")")
end

Base.show(io::IO, traversal::ParticleTraversal) =
  print(io, "ParticleTraversal(", traversal.order, traversal.automatic ? ", automatic" : ", manual", ")")



# ————————————————————————————————————————————————————————————————————————————————————————————————
# HDF5 persistence. The bare generics live here so the docstrings and the docs build work without
# HDF5 in the environment; the methods live in the `GBGHomogeneousTurbulenceHDF5Ext` weak-dependency
# extension, loaded automatically alongside the HDF5 package (the arrangement the field library's
# persistence pairs established).

export write_tracers, read_tracers


"""
    write_tracers(parent::HDF5.H5DataStore, name::AbstractString, tracers::Tracers)

Write the [`Tracers`](@ref) `tracers` under `parent` as one self-describing HDF5 group — the
wrapped positions, the unwrapped positions when tracked, and the interpolation scheme, each
persisted through `GBGPeriodicFields`' own pairs. Available once the `HDF5` package is loaded; the
caller owns the file.

# Arguments
- `parent` — the open HDF5 file or group to write under.
- `name` — the created group's name.
- `tracers` — the tracer set to record.

Returns the created group. Reload with [`read_tracers`](@ref).
"""
function write_tracers end


"""
    read_tracers(parent::HDF5.H5DataStore, name::AbstractString,
                 domain::FixedDomain) -> Tracers

Rebuild a [`Tracers`](@ref) from the group [`write_tracers`](@ref) wrote, its positions allocated
on the storage backend of `domain` (a [`FixedDomain`](@ref)), whose element type must agree with
the file or the read is refused with an `ArgumentError`, as is a group not written by
`write_tracers`. Available once the `HDF5` package is loaded.

# Arguments
- `parent` — the open HDF5 file or group holding the tracer group.
- `name` — the group's name.
- `domain` — the `FixedDomain` whose backend the rebuilt set lives on.
"""
function read_tracers end


export write_trail, read_trail


"""
    write_trail(parent::HDF5.H5DataStore, name::AbstractString, trail::ParticleTrail)

Write the [`ParticleTrail`](@ref) `trail` under `parent` as one self-describing HDF5 group: its
capacity and every sample it holds, the values through `GBGPeriodicFields`' own pair and the
times beside them. Available once the `HDF5` package is loaded; the caller owns the file.

A run's checkpoint stores the run's own velocity trail; a trail the caller keeps is the caller's
to store, with this function.

# Arguments
- `parent` — the open HDF5 file or group to write under.
- `name` — the created group's name.
- `trail` — the trail to record.

Returns the created group. Reload with [`read_trail`](@ref).
"""
function write_trail end


"""
    read_trail(parent::HDF5.H5DataStore, name::AbstractString,
               tracers::Tracers) -> ParticleTrail

Rebuild a [`ParticleTrail`](@ref) from the group [`write_trail`](@ref) wrote, with the stored
capacity, samples and times, its storage allocated on the backend of `tracers`. A group not written
by `write_trail`, or one whose values do not fit `tracers` in count or element type, is refused
with an `ArgumentError`. Available once the `HDF5` package is loaded.

# Arguments
- `parent` — the open HDF5 file or group holding the trail's group.
- `name` — the group's name.
- `tracers` — the [`Tracers`](@ref) the rebuilt trail's values are sized to.
"""
function read_trail end


end # module Particles
