# State

```@autodocs
Modules = [GBGIsotropicTurbulence.State]
Order   = [:module]
```

## The state

The evolving fields a run advances, in spectral representation — the single source of truth. The
physical representations are recovered from it with the source-preserving four-argument form of
[`to_physical!`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.to_physical!), and the vorticity
with [`vorticity_physical!`](@ref) — see [Observables](Observables.md).

```@docs
ResolvedFields
```

## Random initial conditions

Seed a large-scale-peaked, dealiased, rescaled random solenoidal velocity, or a mean-zero scalar.

```@docs
random_solenoidal_velocity_spectral!
random_scalar_spectral!
```

## Persistence

The state's HDF5 persistence — the spectral fields as one self-describing group, available once `HDF5` is loaded.

```@docs
write_state
read_state
```
