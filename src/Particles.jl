# Particles — Lagrangian tracer tracking. Tracers are advected by the velocity through the package's
# grid→point interpolation (a selectable `GBGPeriodicFields` spline scheme; `CatmullRom` by default,
# `LalescuSpline`/`LagrangeSpline` for higher order), and any physical field can be sampled along the
# trajectories; accumulating statistics over them is the caller's analysis, not this package's.
#
# Trajectory time integration is pluggable, exactly as the field side is: the scheme is an
# `AbstractParticleIntegrator` and its per-step registers are allocated per scheme by
# `allocate_buffers`, so the tracer set holds only trajectory STATE and never one scheme's scratch.
# `EndpointHeun` is the one scheme today — second-order, on the velocity at the start and end of the
# step (tₙ and tₙ₊₁), unlike advecting on the frozen start-of-step velocity (effectively first
# order). Its two velocity fields are exactly what the field solver already produces each step, so
# the tracer advance stays decoupled from the field Runge–Kutta internals. A higher-order scheme would
# want different registers (RK4 several stage velocities; a multistep scheme a velocity HISTORY and
# no predictor at all) — which is precisely why they are not in `Tracers`.

"""
    Particles

Lagrangian tracer tracking:
- [`Tracers`](@ref) — the tracer set (positions and a selectable `interpolation_scheme`).
- [`particle_positions`](@ref), [`number_of_particles`](@ref) — the particle-state readouts (the
  trajectory velocities are read from the run's observables cache through
  [`particle_velocities`](@ref GBGIsotropicTurbulence.Cache.particle_velocities), where the closing
  deposit leaves them).
- [`AbstractParticleIntegrator`](@ref), [`EndpointHeun`](@ref) — the trajectory time-integration
  schemes, and [`ParticleIntegratorBuffers`](@ref) the per-step storage each one needs.
- [`record_particle_velocity!`](@ref) — store the flow velocity at the tracers' current positions,
  which is both the measured Lagrangian sample and the first velocity the next advance needs.
- [`advect!`](@ref) — advance the trajectories one step under the chosen scheme.
- [`interpolate_at_particles!`](@ref) — read a field along the trajectories; [`new_vector_point_values`](@ref) /
  [`new_scalar_point_values`](@ref) allocate its `out` buffers.
"""
module Particles

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, _reference, _real_type
# One generic builds the per-scheme registers on both sides of the run — the field scheme's and
# the trajectory scheme's — because it is one concept: allocate exactly what this scheme needs.
import ..Propagator: allocate_buffers

export Tracers, AbstractParticleIntegrator, EndpointHeun, ParticleIntegratorBuffers,
       record_particle_velocity!, advect!, interpolate_at_particles!,
       particle_positions, number_of_particles, new_vector_point_values, new_scalar_point_values


"""
    Tracers(domain; number_of_particles, interpolation_scheme, rng = default_rng())
    Tracers(domain; positions, interpolation_scheme)

(One method, shown as the two ways it is called — keywords do not dispatch.)

A set of Lagrangian tracers, built on `domain`'s backend and element type. Give **exactly one** of
`number_of_particles`, which seeds that many tracers uniformly at random in the periodic box of
`domain`, or `positions`, an `(M, 3)` array of `M` tracer positions to wrap (the three columns are
the ``x, y, z`` components), converted to `domain`'s backend and element type. Supplying both, or
neither, is an `ArgumentError`. The `interpolation_scheme` is the `GBGPeriodicFields` scheme used to
evaluate the velocity (and any sampled field) at the tracer positions.
[`CatmullRom`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.CatmullRom) — a ready-made
value rather than a type, so it is passed bare — is the ``C^1`` choice
(the default `interpolation_scheme` of the
[`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) front door, the
build-everything convenience
constructor);
[`LalescuSpline(n, m)`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.LalescuSpline) and
[`LagrangeSpline(n)`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.LagrangeSpline) offer higher
smoothness or interpolation order — at a wider stencil, useful for derivative-sensitive readouts such as
acceleration statistics — with `n` (and, for `LalescuSpline`, `m`) the stencil and smoothness parameters.
# Arguments

- `domain` — the [`FixedDomain`](@ref) whose backend, element type and box the set is built on.
- `number_of_particles` — seed this many tracers uniformly at random in the box.
- `positions` — or wrap this `(M, 3)` array instead; give exactly one of the two.
- `interpolation_scheme` — the scheme used to evaluate a field at the tracer positions.
- `rng` — the random stream seeding the positions (used with `number_of_particles`, ignored with
  `positions`); defaults to `Random.default_rng()`.

# Examples

A run carries tracers when the front door is given a count;
[`advance!`](@ref GBGIsotropicTurbulence.SimulationRun.advance!) then advances them with the
fields and records the Lagrangian velocity each iteration, so both reads below are current between
iterations:

```julia
sim = Simulation(grid_points_per_axis = 64, number_of_particles = 4096, scalar = true)
advance!(sim)

X = particle_positions(sim.tracers)         # the (M, 3) positions at this instant
v = particle_velocities(sim.cache)          # u(tₙ, X(tₙ)), the Lagrangian velocity — a checked read

out = new_scalar_point_values(sim.tracers)  # allocate once, then reuse every iteration
interpolate_at_particles!(out, scalar_physical(sim.cache), sim.tracers)
```

Building a set directly — to place tracers deliberately rather than at random, and to advance them
by hand — takes the `positions` form, and then the scheme's per-step storage is yours to allocate:

```julia
tracers = Tracers(domain; positions = [0.1 0.2 0.3; 1.0 1.0 1.0], interpolation_scheme = CatmullRom)
buffers = allocate_buffers(EndpointHeun(), tracers)

record_particle_velocity!(tracers, u)     # u(tₙ) at the current positions — do this first
advect!(EndpointHeun(), tracers, u_end, domain, buffers, dt)
```

Read the particle state with [`particle_positions`](@ref) and [`number_of_particles`](@ref), both of
which read the tracer set directly. The velocities are the exception, and deliberately so: they are a
*deposited observable* rather than tracer state, so they are read from the run's observables cache
through
[`particle_velocities`](@ref GBGIsotropicTurbulence.Cache.particle_velocities), where the
iteration's
closing deposit leaves them.

The trajectory scheme's own working storage is **not** here: it lives in a
[`ParticleIntegratorBuffers`](@ref), whose docstring explains the split.

# Fields
- `positions` — the `(M, 3)` tracer positions (read with `particle_positions`).
- `position_points` — a
  [`PointSet`](@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet) wrapping `positions`: the
  same coordinates in the form `GBGPeriodicFields`' interpolation takes, which is why both exist.
- `particle_velocities` — the interpolated velocity at the positions the tracers occupy, at the
  instant they occupy them: the genuine Lagrangian sample. This array **is** the observables cache's
  particle-velocities slot, the same storage under two names, so it carries that slot's rules —
  read it through
  `particle_velocities`, which serves it only when current, and treat it as read-only, since the tracer advance writes here mid-iteration.
- `interpolation_scheme` — the scheme used to evaluate a field at the tracer positions.
"""
struct Tracers{P, PSX, VV, S}
  positions::P              # (M, 3)
  position_points::PSX      # PointSet wrapping `positions`
  particle_velocities::VV   # VectorPointValues: u at the occupied positions — the Lagrangian sample
  interpolation_scheme::S
end


# The two forms are ONE method, not two: they are distinguished by which keyword is supplied, and
# Julia dispatches on positional arguments only. Hence the explicit either/or check, which also gives
# a better error than a missing-keyword one would.
function Tracers(domain::FixedDomain; interpolation_scheme, positions = nothing,
                 number_of_particles = nothing, rng = Random.default_rng())
  count(!isnothing, (positions, number_of_particles)) == 1 ||
    throw(ArgumentError("give exactly one of `positions` (an (M, 3) array to wrap) or " *
                        "`number_of_particles` (a count to seed at random)"))
  T = _real_type(domain)
  if isnothing(positions)
    M = Int(number_of_particles)
    positions = similar(_reference(domain), T, (M, 3))
    copyto!(positions, T(domain.grid.domain_size[1]) .* rand(rng, T, M, 3))
    pos = positions
  else
    size(positions, 2) == 3 ||
      throw(DimensionMismatch("tracer positions must have shape (M, 3); got $(size(positions))"))
    pos = similar(_reference(domain), T, size(positions))   # the domain's backend + element type
    copyto!(pos, positions)
  end
  return Tracers(pos, PointSet(pos), VectorPointValues(similar(pos)), interpolation_scheme)
end


"""
    AbstractParticleIntegrator

The supertype of the trajectory time-integration schemes — how the tracer positions are advanced
over one step, the Lagrangian counterpart of the field side's
[`AbstractIntegrator`](@ref GBGIsotropicTurbulence.Propagator.AbstractIntegrator). A scheme is a
value (`EndpointHeun()`), passed to [`advect!`](@ref) and to
[`allocate_buffers`](@ref GBGIsotropicTurbulence.Propagator.allocate_buffers), which builds exactly
the working storage that scheme needs.

Today the family has one member, [`EndpointHeun`](@ref). Higher-order schemes are the studied future
axis; the supertype exists so that adding one changes no other type.
"""
abstract type AbstractParticleIntegrator end


"""
    EndpointHeun()

Second-order Heun-in-time on the velocity at the two **ends** of the step — the trajectory
scheme a run uses by default. It advances the positions with the start-of-step Lagrangian
velocity that [`record_particle_velocity!`](@ref) stored and the end-of-step velocity field
the solver has just produced, so it needs nothing from inside the field scheme's stages.

It needs one set of predicted positions and the velocity interpolated there
([`ParticleIntegratorBuffers`](@ref)); the formula is given with [`advect!`](@ref).
"""
struct EndpointHeun <: AbstractParticleIntegrator end


"""
    ParticleIntegratorBuffers

The per-step storage a trajectory scheme computes in, sized to a tracer set and allocated once,
so advancing the tracers allocates nothing. Build it with
[`allocate_buffers`](@ref GBGIsotropicTurbulence.Propagator.allocate_buffers)`(scheme, tracers)`,
which allocates exactly what `scheme` needs and nothing more; a run builds it for you.

This storage belongs to the scheme, not to the trajectory: a different scheme wants a different
set — a multistep scheme wants a velocity history and no predicted positions at all — which is why it
lives here rather than in [`Tracers`](@ref).

# Fields
- `predictor` — the `(M, 3)` predicted positions, which no tracer ever occupies.
- `predictor_points` — a
  [`PointSet`](@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet) wrapping `predictor`.
- `predictor_velocity` — the velocity interpolated at the predicted positions (the particle-side
  counterpart of the field schemes' `velocity_predictor_spectral`). It is reachable like
  any field of this type, but it is a scheme intermediate rather than a sample of the flow at any
  instant, so nothing in the package offers it as one: read
  [`particle_velocities`](@ref GBGIsotropicTurbulence.Cache.particle_velocities) for the Lagrangian
  sample.
"""
struct ParticleIntegratorBuffers{P, PS, VV}
  predictor::P
  predictor_points::PS
  predictor_velocity::VV
end


function allocate_buffers(::EndpointHeun, tracers::Tracers)
  predictor = similar(tracers.positions)
  return ParticleIntegratorBuffers(predictor, PointSet(predictor),
                                   VectorPointValues(similar(predictor)))
end


"""
    record_particle_velocity!(tracers, u) -> tracers

Store the Lagrangian velocity ``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))`` — the flow velocity seen by
each tracer where it currently sits — by interpolating the velocity field `u` (physical
representation) onto the positions of the tracer set `tracers`, with the set's interpolation scheme.

The values go into the tracer set's own `particle_velocities` storage, which is also the observables
cache's particle-velocities slot. **This call is that slot's only producer of values**, but it writes
values only: the slot stays stale, and reads of it throw, until
[`deposit_sample!`](@ref GBGIsotropicTurbulence.Cache.deposit_sample!) records them as current.
Interpolate here, then mark current there — a run does both at the end of each iteration, on the just-deposited velocity at
the just-advanced positions, and reading
[`particle_velocities`](@ref GBGIsotropicTurbulence.Cache.particle_velocities) after only the first
throws.

The stored values serve twice: they are the genuine Lagrangian velocity a caller accumulates, and they
are the start-of-step velocity ``\\boldsymbol{v}_1`` the next [`advect!`](@ref) needs — which is why
an [`EndpointHeun`](@ref) advance never interpolates at ``t_n`` itself. Storing them costs
``M\\times 3`` values for ``M`` tracers, where keeping the velocity field would cost
``N^{3} \\times 3``.
"""
function record_particle_velocity!(tracers::Tracers, u)
  interpolate!(tracers.particle_velocities, u, tracers.position_points, tracers.interpolation_scheme)
  return tracers
end


"""
    advect!(scheme, tracers, velocity_end, domain, buffers, dt) -> tracers

Advance the positions of the tracer set `tracers` by one step of size `dt` (written ``\\Delta t``
below), in place, under the trajectory scheme `scheme` (an
[`AbstractParticleIntegrator`](@ref)), using its working storage `buffers` (a
[`ParticleIntegratorBuffers`](@ref) built for that scheme). The `domain` (a [`FixedDomain`](@ref))
supplies the box side the positions are wrapped into.

Under [`EndpointHeun`](@ref), the scheme is Heun-in-time on the velocity at the two ends of the
step — the start-of-step values that [`record_particle_velocity!`](@ref) stored, and
`velocity_end`, the end-of-step velocity field ``\\boldsymbol{u}(t_{n+1})`` in physical
representation:

```math
\\begin{aligned}
\\boldsymbol{v}_1 &= \\boldsymbol{u}(t_n, \\boldsymbol{X}), &
\\boldsymbol{X}^{*} &= \\boldsymbol{X} + \\Delta t \\boldsymbol{v}_1, \\\\
\\boldsymbol{v}_2 &= \\boldsymbol{u}(t_{n+1}, \\boldsymbol{X}^{*}), &
\\boldsymbol{X} &\\leftarrow \\boldsymbol{X} + \\tfrac{\\Delta t}{2}(\\boldsymbol{v}_1 + \\boldsymbol{v}_2),
\\end{aligned}
```

with positions wrapped into ``[0, L)``. This is second-order accurate in time — advecting on the
frozen start-of-step velocity alone would be first order.

!!! note "The start-of-step velocity is read, never recomputed"
    ``\\boldsymbol{v}_1`` is read from the tracer set, not recomputed here: it must hold
    ``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))``, recorded by `record_particle_velocity!`
    at the previous iteration's end. In a run the observables cache records that sample at its epoch
    and the run layer reads it checked before each advance; a hand-run loop must call
    `record_particle_velocity!` itself between advances.
"""
function advect! end

function advect!(::EndpointHeun, tracers::Tracers, velocity_end, domain::FixedDomain,
                 buffers::ParticleIntegratorBuffers, dt::Real)
  L = real(eltype(tracers.positions))(domain.grid.domain_size[1])
  Δt = real(eltype(tracers.positions))(dt)
  X = tracers.positions
  Xstar = buffers.predictor

  v1 = point_values(tracers.particle_velocities)
  Xstar .= mod.(X .+ Δt .* v1, L)
  # v₂ is evaluated at the PREDICTOR positions and is a stage register, never deposited particle velocities —
  # and it must never be reused as the next step's v₁: the two differ only at O(Δt²), but that reuse
  # would corrupt the recorded observable the Lagrangian statistics accumulate (never approximate
  # the thing you measure).
  interpolate!(buffers.predictor_velocity, velocity_end, buffers.predictor_points, tracers.interpolation_scheme)
  v2 = point_values(buffers.predictor_velocity)
  X .= mod.(X .+ (Δt / 2) .* (v1 .+ v2), L)
  return tracers
end


"""
    interpolate_at_particles!(out, field, tracers) -> out

Sample the physical `field` at the current tracer positions into the point-value buffer `out` (a
[`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) for the
velocity, a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues)
for the scalar ``\\varphi``), using the interpolation scheme of the tracer set `tracers`. This is how
a field is gathered along the trajectories; what is then accumulated over those values is the
caller's own analysis.
"""
function interpolate_at_particles!(out, field, tracers::Tracers)
  interpolate!(out, field, tracers.position_points, tracers.interpolation_scheme)
  return out
end


"""
    particle_positions(tracers)

The `(M, 3)` array of current tracer positions — the probes' own state, read off the tracer set
`tracers`.
"""
particle_positions(tracers::Tracers) = tracers.positions


"""
    number_of_particles(tracers)

The number of tracers ``M`` in the tracer set `tracers`.
"""
number_of_particles(tracers::Tracers) = size(tracers.positions, 1)


"""
    new_vector_point_values(tracers)

Allocate a [`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) of
shape `(M, 3)` matching the tracer set `tracers`, for use as the `out` of
[`interpolate_at_particles!`](@ref) when sampling the velocity along the trajectories.
"""
new_vector_point_values(tracers::Tracers) = VectorPointValues(similar(tracers.positions))

"""
    new_scalar_point_values(tracers)

Allocate a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues) of
length ``M`` matching the tracer set `tracers`, for use as the `out` of
[`interpolate_at_particles!`](@ref) when sampling the scalar ``\\varphi`` along the trajectories.
"""
new_scalar_point_values(tracers::Tracers) =
  ScalarPointValues(similar(tracers.positions, eltype(tracers.positions), number_of_particles(tracers)))


end # module Particles
