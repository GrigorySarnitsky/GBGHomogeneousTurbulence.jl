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
number_of_tracers
```

## The tracking loop

The steps of Lagrangian tracking: put the start-of-step velocity on record along the trajectories,
advance the tracers with second-order Heun-in-time advection once the fields have moved, then read a
physical field along their trajectories — all feeding the Lagrangian statistics. The push is two
verbs because the run holds a single physical velocity field, so the start-of-step values are taken
off it before the state advances.

```@docs
record_trajectory_velocity!
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
