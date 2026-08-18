# Cache

```@autodocs
Modules = [GBGIsotropicTurbulence.Cache]
Order   = [:module]
```

## The observables cache

The storage the iteration fills at its end with its observables — every read serves the
deposited value or throws, and nothing is ever recomputed on a read.

```@docs
ObservablesCache
fields_modified!
particles_modified!
deposit_sample!
```

## The checked reads

Each accessor returns the observable deposited at the current epoch, or throws; the cached
maximum speed is read through `max_speed`, documented with the reduction it stores.

```@docs
velocity_physical
vorticity_physical
scalar_physical
particle_velocities
```
