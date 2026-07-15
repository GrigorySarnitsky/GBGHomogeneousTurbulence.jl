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
- [`advect!`](@ref) — the second-order tracer push (Heun-in-time on the start- and end-of-step velocity).
- [`sample!`](@ref) — read a field along the trajectories; [`velocity_buffer`](@ref) /
  [`scalar_buffer`](@ref) allocate its `out` buffers.
- [`tracer_positions`](@ref), [`tracer_velocities`](@ref), [`ntracers`](@ref) — the trajectory readouts.
"""
module Particles

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain

export Tracers, advect!, sample!,
       tracer_positions, tracer_velocities, ntracers, velocity_buffer, scalar_buffer


"""
    Tracers(domain, count; scheme, rng = default_rng())
    Tracers(domain, positions; scheme)

A set of Lagrangian tracers, built on `domain`'s backend and element type. The first form seeds `count`
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

Read the tracer state with [`tracer_positions`](@ref), [`tracer_velocities`](@ref), and
[`ntracers`](@ref); the remaining fields are preallocated predictor and point-value scratch, so
[`advect!`](@ref) allocates no per-step memory.

# Fields
- `positions` — the `(M, 3)` tracer positions (read with [`tracer_positions`](@ref)).
- `predictor` — `(M, 3)` scratch for the Heun predictor.
- `position_points`, `predictor_points` — `PointSet`s wrapping `positions` / `predictor` for interpolation.
- `velocity1`, `velocity2` — the interpolated velocities at the start-of-step and predictor positions;
  `velocity1` is the retained trajectory velocity (read with [`tracer_velocities`](@ref)).
- `scheme` — the velocity-interpolation scheme.
"""
struct Tracers{P, PSX, PSP, VV, S}
  positions::P              # (M, 3)
  predictor::P              # (M, 3) scratch for the Heun predictor
  position_points::PSX      # PointSet wrapping `positions`
  predictor_points::PSP     # PointSet wrapping `predictor`
  velocity1::VV             # VectorPointValues: velocity at the start-of-step positions
  velocity2::VV             # VectorPointValues: velocity at the predictor positions
  scheme::S
end


function Tracers(domain::FixedDomain, positions::AbstractMatrix; scheme)
  size(positions, 2) == 3 || throw(DimensionMismatch("tracer positions must have shape (M, 3); got $(size(positions))"))
  T = real(eltype(field_data(domain.dealias)))
  pos = similar(domain.squared_wavenumber, T, size(positions))     # the domain's backend + element type
  copyto!(pos, positions)
  predictor = similar(pos)
  return Tracers(pos, predictor,
                 PointSet(pos), PointSet(predictor),
                 VectorPointValues(similar(pos)), VectorPointValues(similar(pos)),
                 scheme)
end

function Tracers(domain::FixedDomain, count::Integer; scheme, rng = Random.default_rng())
  T = real(eltype(field_data(domain.dealias)))
  L = T(domain.grid.domain_size[1])
  positions = similar(domain.squared_wavenumber, T, (Int(count), 3))
  copyto!(positions, L .* rand(rng, T, Int(count), 3))
  return Tracers(domain, positions; scheme)
end


"""
    advect!(tracers, velocity_start, velocity_end, domain, dt) -> tracers

Advance the tracer positions by one step of size `dt`, in place, by Heun-in-time on the physical
velocity fields at the start (`velocity_start` ``= \\boldsymbol{u}(t_n)``) and end
(`velocity_end` ``= \\boldsymbol{u}(t_{n+1})``) of the step:

```math
\\begin{aligned}
\\boldsymbol{v}_1 &= \\boldsymbol{u}(t_n, \\boldsymbol{X}), &
\\boldsymbol{X}^{*} &= \\boldsymbol{X} + \\Delta t\\,\\boldsymbol{v}_1, \\\\
\\boldsymbol{v}_2 &= \\boldsymbol{u}(t_{n+1}, \\boldsymbol{X}^{*}), &
\\boldsymbol{X} &\\leftarrow \\boldsymbol{X} + \\tfrac{\\Delta t}{2}(\\boldsymbol{v}_1 + \\boldsymbol{v}_2),
\\end{aligned}
```

with positions wrapped into ``[0, L)``, where the box side ``L`` is read from `domain` (a
[`FixedDomain`](@ref)). This is second-order accurate in time. The start-of-step
velocity ``\\boldsymbol{v}_1`` is retained ([`tracer_velocities`](@ref)) as the trajectory velocity for
the forthcoming Lagrangian statistics.
"""
function advect!(tracers::Tracers, velocity_start, velocity_end, domain::FixedDomain, dt::Real)
  L = real(eltype(tracers.positions))(domain.grid.domain_size[1])
  Δt = real(eltype(tracers.positions))(dt)
  X = tracers.positions
  Xstar = tracers.predictor

  interpolate!(tracers.velocity1, velocity_start, tracers.position_points, tracers.scheme)
  v1 = point_values(tracers.velocity1)
  Xstar .= mod.(X .+ Δt .* v1, L)
  interpolate!(tracers.velocity2, velocity_end, tracers.predictor_points, tracers.scheme)
  v2 = point_values(tracers.velocity2)
  X .= mod.(X .+ (Δt / 2) .* (v1 .+ v2), L)
  return tracers
end


"""
    sample!(out, field, tracers) -> out

Sample the physical `field` at the current tracer positions into the point-value buffer `out` (a
[`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) for the
velocity, a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues)
for the scalar ``\\varphi``), using the
tracers' interpolation scheme. Used to gather a field along the trajectories for the forthcoming Lagrangian
statistics.
"""
function sample!(out, field, tracers::Tracers)
  interpolate!(out, field, tracers.position_points, tracers.scheme)
  return out
end


"""
    tracer_positions(tracers)

The `(M, 3)` array of current tracer positions.
"""
tracer_positions(tracers::Tracers) = tracers.positions


"""
    tracer_velocities(tracers)

The `(M, 3)` array of the most recent trajectory velocities ``\\boldsymbol{u}(t_n, \\boldsymbol{X})`` (set by
[`advect!`](@ref)).
"""
tracer_velocities(tracers::Tracers) = point_values(tracers.velocity1)


"""
    ntracers(tracers)

The number of tracers `M`.
"""
ntracers(tracers::Tracers) = size(tracers.positions, 1)


"""
    velocity_buffer(tracers)

Allocate a [`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) of
shape `(M, 3)` matching the tracers, for use as the `out` of
[`sample!`](@ref) when sampling the velocity along the trajectories.
"""
velocity_buffer(tracers::Tracers) = VectorPointValues(similar(tracers.positions))

"""
    scalar_buffer(tracers)

Allocate a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues) of
length `M` matching the tracers, for use as the `out` of
[`sample!`](@ref) when sampling the scalar ``\\varphi`` along the trajectories.
"""
scalar_buffer(tracers::Tracers) =
  ScalarPointValues(similar(tracers.positions, eltype(tracers.positions), ntracers(tracers)))


end # module Particles
