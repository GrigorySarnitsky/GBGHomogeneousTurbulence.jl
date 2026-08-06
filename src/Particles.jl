# Particles — Lagrangian tracer tracking. Tracers are advected by the velocity through the package's
# grid→point interpolation (a selectable `GBGPeriodicFields` spline scheme; `CatmullRom` by default,
# `LalescuSpline`/`LagrangeSpline` for higher order), and any physical field can be sampled along the
# trajectories for the Lagrangian statistics.
#
# Trajectory time integration is Heun-in-time using the velocity at the start and end of the step
# (tₙ and tₙ₊₁), which is second-order accurate — unlike advecting on the frozen start-of-step
# velocity (effectively first order). The two velocity fields are exactly what the field solver
# already produces each step, so the tracer push stays decoupled from the field Runge–Kutta internals.

"""
    Particles

Lagrangian tracer tracking:
- [`Tracers`](@ref) — the tracer set (positions and a selectable interpolation `scheme`).
- [`record_trajectory_velocity!`](@ref) — put the start-of-step Lagrangian velocity on record.
- [`advect!`](@ref) — the second-order tracer push (Heun-in-time on the start- and end-of-step velocity).
- [`sample!`](@ref) — read a field along the trajectories; [`velocity_buffer`](@ref) /
  [`scalar_buffer`](@ref) allocate its `out` buffers.
- [`particle_positions`](@ref), [`number_of_tracers`](@ref) — the particle-state readouts (the
  trajectory velocities are read from the run's observables cache through
  [`particle_velocities`](@ref GBGIsotropicTurbulence.Cache.particle_velocities), where the tail
  deposit stamps them).
"""
module Particles

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, _reference, _real_type

export Tracers, record_trajectory_velocity!, advect!, sample!,
       particle_positions, number_of_tracers, velocity_buffer, scalar_buffer


"""
    Tracers(domain, number_of_tracers; scheme, rng = default_rng())
    Tracers(domain, positions; scheme)

A set of Lagrangian tracers, built on `domain`'s backend and element type. The first form seeds `number_of_tracers`
tracers uniformly at random in the periodic box of `domain`; the second wraps a given `(M, 3)` array of
`M` tracer positions (the three columns are the ``x, y, z`` components), converting it to `domain`'s
backend and element type. The `scheme` is the `GBGPeriodicFields` velocity-interpolation scheme used to
evaluate the velocity (and any sampled field) at the tracer positions.
[`CatmullRom`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.CatmullRom) is the ``C^1`` choice
(the `Simulation` front door's default `tracer_scheme`);
[`LalescuSpline(n, m)`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.LalescuSpline) and
[`LagrangeSpline(n)`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.LagrangeSpline) offer higher
smoothness or interpolation order — at a wider stencil, useful for derivative-sensitive readouts such as
acceleration statistics — with `n` (and, for `LalescuSpline`, `m`) the stencil and smoothness parameters.
The `rng` (first form only) is the random stream seeding the uniformly-random tracer positions; it
defaults to `Random.default_rng()`.

Read the particle state with [`particle_positions`](@ref) and [`number_of_tracers`](@ref); the
trajectory velocities are read from the run's observables cache (`particle_velocities`), where the
iteration's tail deposit stamps them. The remaining fields are preallocated predictor and
point-value scratch, so the tracer push allocates no per-step memory.

# Fields
- `positions` — the `(M, 3)` tracer positions (read with [`particle_positions`](@ref)).
- `predictor` — `(M, 3)` scratch for the Heun predictor positions.
- `position_points`, `predictor_points` — `PointSet`s wrapping `positions` / `predictor` for interpolation.
- `trajectory_velocity` — the interpolated velocity at the positions the tracers occupy, at the
  boundary they occupy them: the genuine Lagrangian sample, and the observables cache's
  particle-velocities slot.
- `predictor_velocity` — the interpolated velocity at the Heun **predictor** positions, which no
  tracer ever occupies: a stage register of the push, never a sample of the flow, and never exposed.
- `scheme` — the velocity-interpolation scheme.
"""
struct Tracers{P, PSX, PSP, VV, S}
  positions::P              # (M, 3)
  predictor::P              # (M, 3) scratch for the Heun predictor
  position_points::PSX      # PointSet wrapping `positions`
  predictor_points::PSP     # PointSet wrapping `predictor`
  trajectory_velocity::VV   # VectorPointValues: u at the occupied positions — the Lagrangian sample
  predictor_velocity::VV    # VectorPointValues: u at the predictor positions — a stage register
  scheme::S
end


function Tracers(domain::FixedDomain, positions::AbstractMatrix; scheme)
  size(positions, 2) == 3 || throw(DimensionMismatch("tracer positions must have shape (M, 3); got $(size(positions))"))
  T = _real_type(domain)
  pos = similar(_reference(domain), T, size(positions))     # the domain's backend + element type
  copyto!(pos, positions)
  predictor = similar(pos)
  return Tracers(pos, predictor,
                 PointSet(pos), PointSet(predictor),
                 VectorPointValues(similar(pos)), VectorPointValues(similar(pos)),
                 scheme)
end

function Tracers(domain::FixedDomain, number_of_tracers::Integer; scheme, rng = Random.default_rng())
  T = _real_type(domain)
  L = T(domain.grid.domain_size[1])
  positions = similar(_reference(domain), T, (Int(number_of_tracers), 3))
  copyto!(positions, L .* rand(rng, T, Int(number_of_tracers), 3))
  return Tracers(domain, positions; scheme)
end


"""
    record_trajectory_velocity!(tracers, u) -> tracers

Record the Lagrangian velocity ``\\boldsymbol{u}(t_n, \\boldsymbol{X})`` — the flow velocity seen by
each tracer where it currently sits — by interpolating the velocity field `u` (physical
representation) onto the positions of the tracer set `tracers`, with the set's interpolation
scheme.

The run layer calls it at the tail of each iteration, on the just-deposited boundary velocity at the
just-advanced positions; the recorded values are the observables cache's particle-velocities slot,
stamped there, and the next iteration's [`advect!`](@ref) reads them as the first half of its Heun
pair. Recording costs ``M \\times 3`` values for ``M`` tracers, where keeping the field itself would
cost ``N^{3} \\times 3``. What is recorded is the trajectory velocity the run's `particle_velocities`
returns, and the quantity the Lagrangian statistics accumulate.
"""
function record_trajectory_velocity!(tracers::Tracers, u)
  interpolate!(tracers.trajectory_velocity, u, tracers.position_points, tracers.scheme)
  return tracers
end


"""
    advect!(tracers, velocity_end, domain, dt) -> tracers

Advance the positions of the tracer set `tracers` by one step of size `dt`, in place, by
Heun-in-time on the velocity at the two ends of the step — the start-of-step values that
[`record_trajectory_velocity!`](@ref) put on record, and the end-of-step velocity field
``\\texttt{velocity\\_end} = \\boldsymbol{u}(t_{n+1})`` in physical representation:

```math
\\begin{aligned}
\\boldsymbol{v}_1 &= \\boldsymbol{u}(t_n, \\boldsymbol{X}), &
\\boldsymbol{X}^{*} &= \\boldsymbol{X} + \\Delta t \\boldsymbol{v}_1, \\\\
\\boldsymbol{v}_2 &= \\boldsymbol{u}(t_{n+1}, \\boldsymbol{X}^{*}), &
\\boldsymbol{X} &\\leftarrow \\boldsymbol{X} + \\tfrac{\\Delta t}{2}(\\boldsymbol{v}_1 + \\boldsymbol{v}_2),
\\end{aligned}
```

with positions wrapped into ``[0, L)``, where the box side ``L`` is read from `domain` (a
[`FixedDomain`](@ref)). This is second-order accurate in time — advecting on the frozen start-of-step
velocity alone would be first order.

!!! note
    ``\\boldsymbol{v}_1`` is read from the tracer set, not recomputed here: it must hold
    ``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))``, recorded by [`record_trajectory_velocity!`](@ref)
    at the previous boundary. In a run the observables cache stamps that sample and the run layer
    reads it checked before pushing; a hand-run loop must re-record between pushes itself.
"""
function advect!(tracers::Tracers, velocity_end, domain::FixedDomain, dt::Real)
  L = real(eltype(tracers.positions))(domain.grid.domain_size[1])
  Δt = real(eltype(tracers.positions))(dt)
  X = tracers.positions
  Xstar = tracers.predictor

  v1 = point_values(tracers.trajectory_velocity)
  Xstar .= mod.(X .+ Δt .* v1, L)
  # v₂ is evaluated at the PREDICTOR positions and is a stage register, never deposited particle velocities —
  # and it must never be reused as the next step's v₁: the two differ only at O(Δt²), but that reuse
  # would corrupt the recorded observable the Lagrangian statistics accumulate (never approximate
  # the thing you measure).
  interpolate!(tracers.predictor_velocity, velocity_end, tracers.predictor_points, tracers.scheme)
  v2 = point_values(tracers.predictor_velocity)
  X .= mod.(X .+ (Δt / 2) .* (v1 .+ v2), L)
  return tracers
end


"""
    sample!(out, field, tracers) -> out

Sample the physical `field` at the current tracer positions into the point-value buffer `out` (a
[`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) for the
velocity, a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues)
for the scalar ``\\varphi``), using the interpolation scheme of the tracer set `tracers`. Used to gather a field along the trajectories for the forthcoming Lagrangian
statistics.
"""
function sample!(out, field, tracers::Tracers)
  interpolate!(out, field, tracers.position_points, tracers.scheme)
  return out
end


"""
    particle_positions(tracers)
    particle_positions(sim)

The `(M, 3)` array of current tracer positions — the probes' own state, read off the tracer set
`tracers`. The second form reads a `Simulation`'s tracers (and throws an `ArgumentError` when the
run advects none).
"""
particle_positions(tracers::Tracers) = tracers.positions


"""
    number_of_tracers(tracers)

The number of tracers ``M`` in the tracer set `tracers`.
"""
number_of_tracers(tracers::Tracers) = size(tracers.positions, 1)


"""
    velocity_buffer(tracers)

Allocate a [`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) of
shape `(M, 3)` matching the tracer set `tracers`, for use as the `out` of
[`sample!`](@ref) when sampling the velocity along the trajectories.
"""
velocity_buffer(tracers::Tracers) = VectorPointValues(similar(tracers.positions))

"""
    scalar_buffer(tracers)

Allocate a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues) of
length ``M`` matching the tracer set `tracers`, for use as the `out` of
[`sample!`](@ref) when sampling the scalar ``\\varphi`` along the trajectories.
"""
scalar_buffer(tracers::Tracers) =
  ScalarPointValues(similar(tracers.positions, eltype(tracers.positions), number_of_tracers(tracers)))


end # module Particles
