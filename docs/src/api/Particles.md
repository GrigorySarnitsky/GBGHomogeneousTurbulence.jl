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

particle_positions(sim.tracers)              # (M, 3) positions at the current instant
particle_velocities(sim.cache)               # u(tₙ, X(tₙ)) — the Lagrangian sample, a checked read
out = new_vector_point_values(sim.tracers)   # allocate once, then reuse
interpolate_at_particles!(out, velocity_physical(sim.cache), sim.tracers)
```

## The tracer set

Tracer positions plus a selectable interpolation scheme, with the accessors that read a tracer set's
state — its positions and its count. The set holds trajectory *state* only; a scheme's working
storage lives apart.

```@docs
Tracers
```

```@docs
particle_positions
number_of_particles
```

## The trajectory scheme

How the positions are advanced over one step — the Lagrangian counterpart of the field schemes, with
`EndpointHeun` is the one scheme today; its storage is allocated by
[`allocate_buffers`](@ref GBGIsotropicTurbulence.Propagator.allocate_buffers), which a run calls for
you.

```@docs
AbstractParticleIntegrator
EndpointHeun
```

```@docs
ParticleIntegratorBuffers
```

## The tracking loop

The steps of Lagrangian tracking: record the flow velocity where each tracer currently sits, advance
the tracers once the fields have moved, then read any physical field along the trajectories for the
Lagrangian statistics. Recording and pushing are two verbs because `EndpointHeun` needs the velocity
at both ends of the step: the run records the sample at the iteration's end, off the just-deposited
velocity, and the next iteration's `advect!` reads it back as the first half of its pair.

```@docs
record_trajectory_velocity!
advect!
interpolate_at_particles!
```

## Point-value buffers

Allocate the point-value `out` for `interpolate_at_particles!` — a
[`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) for the
velocity, a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues)
for the scalar.

```@docs
new_vector_point_values
new_scalar_point_values
```
