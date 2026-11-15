# Particles

```@autodocs
Modules = [GBGHomogeneousTurbulence.Particles]
Order   = [:module]
```


## The tracer set

Tracer positions plus a selectable interpolation scheme, with the accessor that reads the
unwrapped positions. The set holds trajectory *state* only.

```@docs
Tracers
```

```@docs
unwrapped_positions
```

## Sampling at the particles

Read any physical field at the particle positions, for the Lagrangian statistics.

```@docs
interpolate_at_particles!
```

## Point-value buffers

Allocate the point-value `out` for [`interpolate_at_particles!`](@ref GBGHomogeneousTurbulence.Particles.interpolate_at_particles!) — a
[`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) for the
velocity, a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues)
for the scalar.

```@docs
new_vector_point_values
new_scalar_point_values
```

## The trail of a quantity

The last few samples of one quantity at the particles, each with its time, and its time derivative
along the trajectories. A run keeps a trail of the velocity itself, read through
[`velocity_at_particles_trail`](@ref GBGHomogeneousTurbulence.Cache.velocity_at_particles_trail); a
caller keeps one for any other quantity.

```@docs
ParticleTrail
```

```@docs
time_derivative!
time_derivative
```

## The traversal order

The memory-locality order the gathers visit the tracers in — a value-preserving accelerator: the
interpolated values are bit-identical with or without it, only the visiting order changes. A run
builds and refreshes it for you (the `traversal_mode` of a [`ParticleTracking`](@ref GBGHomogeneousTurbulence.SimulationRun.ParticleTracking)); the type and
its rebuild verb are here for a caller refreshing on a chosen
cadence from a [`run!`](@ref GBGHomogeneousTurbulence.SimulationRun.run!) callback.

```@docs
ParticleTraversal
```

```@docs
rebuild_traversal!
```

## Wiring tracers into a run

Give [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) a [`ParticleTracking`](@ref GBGHomogeneousTurbulence.SimulationRun.ParticleTracking)
and the run carries a tracer set: [`advance!`](@ref GBGHomogeneousTurbulence.SimulationRun.advance!) pushes it every iteration and records the Lagrangian
sample, so the reads below are always current between iterations.

```julia
sim = Simulation(grid_points_per_axis = 64,
                 particles = ParticleTracking(number_of_particles = 4096))
warmup!(sim)
advance!(sim)

point_positions(sim.tracers.positions)     # (M, 3) positions, via GBGPeriodicFields
trail = velocity_at_particles_trail(sim.cache)   # throws if stale
trail[0].value                             # the sample u(tₙ, X(tₙ)), and trail[0].time its time
out = new_vector_point_values(sim.tracers)   # allocate once, then reuse
interpolate_at_particles!(out, velocity_physical(sim.cache), sim.tracers)
```

## Persistence

The HDF5 persistence of a tracer set and of a trail, each one self-describing group, available once `HDF5` is loaded.

```@docs
write_tracers
read_tracers
```

```@docs
write_trail
read_trail
```
