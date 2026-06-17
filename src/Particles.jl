# Particles — Lagrangian tracer tracking. Tracers are advected by the velocity through the package's
# grid→point interpolation (a pluggable `GBGPeriodicFields` spline scheme; `CatmullRom` by default,
# `LalescuSpline`/`LagrangeSpline` for higher order), and any physical field can be sampled along the
# trajectories for the Lagrangian statistics.
#
# Trajectory time integration is Heun-in-time using the velocity at the start and end of the step
# (tₙ and tₙ₊₁), which is second-order accurate — unlike advecting on the frozen start-of-step
# velocity (effectively first order). The two velocity fields are exactly what the field solver
# already produces each step, so the tracer push stays decoupled from the field Runge–Kutta internals.

"""
    Particles

Lagrangian tracer tracking: `Tracers` (positions + a pluggable interpolation scheme), the
second-order [`advect!`](@ref) (Heun-in-time on the start- and end-of-step velocity), and
[`sample!`](@ref) for reading a field along the trajectories.
"""
module Particles

using GBGPeriodicFields
using Random
using ..SimulationState: SpectralOperators

export Tracers, advect!, sample!,
       tracer_positions, tracer_velocities, ntracers, velocity_buffer, scalar_buffer


"""
    Tracers(ops, count; scheme = CatmullRom, rng = default_rng())
    Tracers(positions; scheme = CatmullRom)

A set of Lagrangian tracers. The first form seeds `count` tracers uniformly at random in the periodic
box of `ops` (on the operators' backend and element type); the second wraps a given `(M, 3)` position
array. `scheme` is the `GBGPeriodicFields` interpolation scheme used to evaluate the velocity (and any
sampled field) at the tracer positions — `CatmullRom` (the default), `LalescuSpline(n, m)`, or
`LagrangeSpline(n)`.

The struct preallocates the predictor positions and the point-value buffers, so [`advect!`](@ref)
allocates no per-step memory.
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


function Tracers(positions::AbstractMatrix; scheme = CatmullRom)
  size(positions, 2) == 3 || throw(DimensionMismatch("tracer positions must have shape (M, 3); got $(size(positions))"))
  predictor = similar(positions)
  return Tracers(positions, predictor,
                 PointSet(positions), PointSet(predictor),
                 VectorPointValues(similar(positions)), VectorPointValues(similar(positions)),
                 scheme)
end

function Tracers(ops::SpectralOperators, count::Integer; scheme = CatmullRom, rng = Random.default_rng())
  T = real(eltype(field_data(ops.dealias)))
  L = T(ops.grid.domain_size[1])
  positions = similar(ops.squared_wavenumber, T, (Int(count), 3))
  copyto!(positions, L .* rand(rng, T, Int(count), 3))
  return Tracers(positions; scheme)
end


"""
    advect!(tracers, velocity_start, velocity_end, ops, dt) -> tracers

Advance the tracer positions by one step of size `dt`, in place, by Heun-in-time on the physical
velocity fields at the start (`velocity_start` ``= \\mathbf{u}(t_n)``) and end
(`velocity_end` ``= \\mathbf{u}(t_{n+1})``) of the step:

```math
\\mathbf{v}_1 = \\mathbf{u}(t_n, \\mathbf{X}),
\\quad
\\mathbf{X}^{*} = \\mathbf{X} + \\Delta t\\,\\mathbf{v}_1,
\\quad
\\mathbf{v}_2 = \\mathbf{u}(t_{n+1}, \\mathbf{X}^{*}),
\\quad
\\mathbf{X} \\leftarrow \\mathbf{X} + \\tfrac{\\Delta t}{2}(\\mathbf{v}_1 + \\mathbf{v}_2),
```

with positions wrapped into ``[0, L)``. This is second-order accurate in time. The start-of-step
velocity ``\\mathbf{v}_1`` is retained ([`tracer_velocities`](@ref)) as the trajectory velocity for
the Lagrangian statistics.
"""
function advect!(tracers::Tracers, velocity_start, velocity_end, ops::SpectralOperators, dt::Real)
  L = real(eltype(tracers.positions))(ops.grid.domain_size[1])
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
`VectorPointValues` for the velocity, a `ScalarPointValues` for the scalar ``\\varphi``), using the
tracers' interpolation scheme. Used to gather a field along the trajectories for the Lagrangian
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

The `(M, 3)` array of the most recent trajectory velocities ``\\mathbf{u}(t_n, \\mathbf{X})`` (set by
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
    scalar_buffer(tracers)

Allocate a point-value buffer matching the tracers (a `VectorPointValues` of shape `(M, 3)`, or a
`ScalarPointValues` of length `M`) for use as the `out` of [`sample!`](@ref).
"""
velocity_buffer(tracers::Tracers) = VectorPointValues(similar(tracers.positions))
scalar_buffer(tracers::Tracers) =
  ScalarPointValues(similar(tracers.positions, eltype(tracers.positions), ntracers(tracers)))


end # module Particles
