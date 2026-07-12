# State

```@autodocs
Modules = [GBGIsotropicTurbulence.State]
Order   = [:module]
```

## The state

The inert record of the evolving spectral fields a run advances — the single source of truth (velocity
`û` and, optionally, scalar `φ̂`); the physical velocity, vorticity, and scalar are derived on demand,
never stored.

```@docs
ResolvedFields
```

## Random initial conditions

Seed a large-scale-peaked, de-aliased, rescaled random solenoidal velocity, or a mean-zero scalar φ.

```@docs
random_solenoidal_velocity!
random_scalar!
```
