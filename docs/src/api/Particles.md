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
particle_positions
number_of_tracers
```

## The tracking loop

The steps of Lagrangian tracking: advance the tracers with second-order Heun-in-time advection once
the fields have moved, put the velocity at the new positions on record along the trajectories, then
read a physical field along those trajectories — all feeding the Lagrangian statistics. The push is
two verbs because Heun needs the velocity at both ends of the step: the run records the sample at
the iteration's end, off the just-deposited velocity, and the next iteration's `advect!` reads it
back as the first half of its pair.

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
