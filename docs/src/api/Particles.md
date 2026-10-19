# Particles

```@autodocs
Modules = [GBGHomogeneousTurbulence.Particles]
Order   = [:module]
```


## The tracer set

Tracer positions plus a selectable interpolation scheme, with the accessors that read a tracer set's
state — its positions and its count. The set holds trajectory *state* only; a scheme's working
storage lives apart.

```@docs
Tracers
```

```@docs
unwrapped_positions
```

## The particle integration scheme

How the positions are advanced over one step — the Lagrangian counterpart of the field schemes.
[`Heun`](@ref GBGHomogeneousTurbulence.Particles.Heun) reaches second order with a second interpolation per step; [`AdamsBashforth`](@ref GBGHomogeneousTurbulence.Particles.AdamsBashforth) reaches
further by reusing the Lagrangian samples already deposited, at no extra interpolation. Each
scheme's storage is allocated by
[`allocate_buffers`](@ref GBGHomogeneousTurbulence.Propagator.allocate_buffers), which a run calls for
you.

```@docs
AbstractParticleIntegrator
Heun
AdamsBashforth
```

```@docs
ParticleIntegratorBuffers
```

## The tracking loop

The steps of Lagrangian tracking: record the flow velocity where each tracer currently sits, advance
the tracers once the fields have moved, then read any physical field at the particle positions for
the Lagrangian statistics. Recording and pushing are two verbs because `Heun` needs the velocity
at both ends of the step: the run records the sample at the iteration's end, off the just-deposited
velocity, and the next iteration's [`advect!`](@ref GBGHomogeneousTurbulence.Particles.advect!) reads it back as the first half of its pair.

```@docs
advect!
restart!
history_depth
interpolate_at_particles!
```

## The traversal order

The memory-locality order the gathers visit the tracers in — a value-preserving accelerator: the
interpolated values are bit-identical with or without it, only the visiting order changes. A run
builds and refreshes it for you (the `traversal_mode` of a [`ParticleTracking`](@ref GBGHomogeneousTurbulence.SimulationRun.ParticleTracking)); the type and
its rebuild verb are here for a caller driving the tracking loop by hand, or refreshing on a chosen
cadence from a [`run!`](@ref GBGHomogeneousTurbulence.SimulationRun.run!) callback.

```@docs
ParticleTraversal
```

```@docs
rebuild_traversal!
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
velocity_at_particles(sim.cache)  # the sample u(tₙ, X(tₙ)); throws if stale
out = new_vector_point_values(sim.tracers)   # allocate once, then reuse
interpolate_at_particles!(out, velocity_physical(sim.cache), sim.tracers)
```

## Persistence

The tracer set's HDF5 persistence — positions, the unwrapped record and the interpolation scheme as one self-describing group, available once `HDF5` is loaded.

```@docs
write_tracers
read_tracers
```
