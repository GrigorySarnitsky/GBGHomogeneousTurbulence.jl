# Particles

```@autodocs
Modules = [GBGIsotropicTurbulence.Particles]
Order   = [:module]
```

## The tracer set

Tracer positions plus a pluggable interpolation scheme, preallocated for allocation-free advection.

```@docs
Tracers
```

## Advection and sampling

Second-order Heun-in-time advection, and reading a physical field along the trajectories.

```@docs
advect!
sample!
```

## Sample buffers

Allocate the point-value `out` for `sample!` — a `VectorPointValues` for the velocity, a
`ScalarPointValues` for the scalar.

```@docs
velocity_buffer
scalar_buffer
```

## Tracer accessors

The current positions, the most-recent trajectory velocities, and the tracer count.

```@docs
tracer_positions
tracer_velocities
ntracers
```
