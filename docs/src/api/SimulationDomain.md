# SimulationDomain

```@autodocs
Modules = [GBGIsotropicTurbulence.SimulationDomain]
Order   = [:module]
```

## The discretised box

The reusable, read-only frame every buffer is allocated from — the `FixedDomain`, a fixed, unsheared
periodic cube (a sheared frame is deferred).

```@docs
FixedDomain
```

## De-aliasing strategies

The aliasing-control strategy passed to `FixedDomain` — the supertype, then the sharp 2/3-rule default
and the smooth Hou–Li filter.

```@docs
DealiasingStrategy
TwoThirds
HouLi
PhaseShift
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
