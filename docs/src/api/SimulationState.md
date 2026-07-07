# SimulationState

```@autodocs
Modules = [GBGIsotropicTurbulence.SimulationState]
Order   = [:module]
```

## Spectral operators and workspace

The read-only spectral machinery every buffer is allocated from, and the preallocated per-step scratch
a run advances.

```@docs
SpectralOperators
Workspace
```

## De-aliasing strategies

The aliasing-control strategy passed to `SpectralOperators` — the supertype, then the sharp 2/3-rule
default and the smooth Hou–Li filter.

```@docs
DealiasingStrategy
TwoThirds
HouLi
```

## Scratch-field allocators

Allocate one zeroed velocity or scalar field on the operators' backend and element type.

```@docs
spectral_vector
physical_vector
scalar_spectral
scalar_physical
```

## De-alias filtering

Apply the operators' de-alias low-pass kernel to a spectral field in place.

```@docs
dealias!
```

## Random initial conditions

Seed a large-scale-peaked, de-aliased, rescaled random solenoidal velocity, or a mean-zero scalar φ.

```@docs
random_solenoidal_velocity!
random_scalar!
```
