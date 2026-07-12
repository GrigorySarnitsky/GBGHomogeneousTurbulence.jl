# State

```@autodocs
Modules = [GBGIsotropicTurbulence.State]
Order   = [:module]
```

## Field buffers

The preallocated per-step scratch a run advances — allocated only for what the configured run needs (no
scalar scratch when the run carries no scalar).

```@docs
FieldBuffers
```

## Random initial conditions

Seed a large-scale-peaked, de-aliased, rescaled random solenoidal velocity, or a mean-zero scalar φ.

```@docs
random_solenoidal_velocity!
random_scalar!
```
