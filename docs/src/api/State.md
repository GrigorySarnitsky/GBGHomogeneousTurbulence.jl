# State

```@autodocs
Modules = [GBGIsotropicTurbulence.State]
Order   = [:module]
```

## The state

The evolving fields a run advances, in spectral representation — the single source of truth.

```@docs
ResolvedFields
```

## Random initial conditions

Seed a large-scale-peaked, de-aliased, rescaled random solenoidal velocity, or a mean-zero scalar.

```@docs
random_solenoidal_velocity!
random_scalar!
```
