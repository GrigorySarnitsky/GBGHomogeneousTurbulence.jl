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

## Physical-field recovery

Recover the velocity, vorticity, and scalar in physical representation from the state in spectral
representation (the sources are preserved) — the recoveries the iteration's tail deposits and the
nonlinear assemblies consume.

```@docs
velocity_to_physical!
vorticity_to_physical!
scalar_to_physical!
```

## Random initial conditions

Seed a large-scale-peaked, dealiased, rescaled random solenoidal velocity, or a mean-zero scalar.

```@docs
random_solenoidal_velocity!
random_scalar!
```
