# Particles

```@autodocs
Modules = [GBGIsotropicTurbulence.Particles]
Order   = [:module]
```

## Wiring tracers into a run

Pass `number_of_particles` to the front door and the run carries a tracer set: `advance!` pushes it
every iteration and records the Lagrangian sample, so the reads below are always current between
iterations.

```julia
sim = Simulation(grid_points_per_axis = 64, number_of_particles = 4096)
warmup!(sim)
advance!(sim)

particle_positions(sim)             # (M, 3) positions at the current instant
particle_velocities(sim)            # u(tₙ, X(tₙ)) — the Lagrangian sample, a checked cache read
out = new_vector_point_values(sim.tracers)  # allocate once, then reuse
interpolate_at_particles!(out, velocity_physical(sim), sim.tracers)
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
number_of_particles
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
interpolate_at_particles!
```

## Sample buffers

Allocate the point-value `out` for `interpolate_at_particles!` — a
[`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) for the
velocity, a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues)
for the scalar.

```@docs
new_vector_point_values
new_scalar_point_values
```
