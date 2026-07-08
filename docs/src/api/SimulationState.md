# SimulationState

```@autodocs
Modules = [GBGIsotropicTurbulence.SimulationState]
Order   = [:module]
```

## The simulation domain and field buffers

The read-only spectral machinery every buffer is allocated from — the `SimulationDomain` — and the
preallocated per-step scratch a run advances.

```@docs
SimulationDomain
FieldBuffers
```

## De-aliasing strategies

The aliasing-control strategy passed to `SimulationDomain` — the supertype, then the sharp 2/3-rule
default and the smooth Hou–Li filter.

```@docs
DealiasingStrategy
TwoThirds
HouLi
```

The de-aliasing cutoff it sets — the highest wavenumber the domain evolves, and the resolution
criterion ``\kappa_{\max}\eta`` a run is built to meet.

```@docs
max_wavenumber
```

## Scratch-field allocators

Allocate one zeroed velocity, scalar, or second-order tensor field on the domain's backend and
element type.

```@docs
spectral_vector
physical_vector
scalar_spectral
scalar_physical
tensor_spectral
tensor_physical
```

## De-alias filtering

Apply the domain's de-alias low-pass kernel to a spectral field in place.

```@docs
dealias!
```

## Random initial conditions

Seed a large-scale-peaked, de-aliased, rescaled random solenoidal velocity, or a mean-zero scalar φ.

```@docs
random_solenoidal_velocity!
random_scalar!
```
