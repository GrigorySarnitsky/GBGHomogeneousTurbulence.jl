# Particles

```@autodocs
Modules = [GBGIsotropicTurbulence.Particles]
Order   = [:module]
```

## The tracer set

Tracer positions plus a selectable interpolation scheme, preallocated for allocation-free advection,
with the accessors that read a tracer set's state — its positions, most-recent trajectory velocities,
and count.

```@docs
Tracers
```

```@docs
tracer_positions
tracer_velocities
ntracers
```

## The tracking loop

The two steps of Lagrangian tracking: advance the tracers along the flow with second-order
Heun-in-time advection, then read a physical field along their trajectories — both feeding the
Lagrangian statistics.

```@docs
advect!
sample!
```

## Sample buffers

Allocate the point-value `out` for `sample!` — a
[`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) for the
velocity, a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues)
for the scalar.

```@docs
velocity_buffer
scalar_buffer
```
