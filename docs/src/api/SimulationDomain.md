# SimulationDomain

```@autodocs
Modules = [GBGIsotropicTurbulence.SimulationDomain]
Order   = [:module]
```

## The discretized box

The reusable, read-only frame every buffer is allocated from — the `FixedDomain`, a fixed, unsheared
periodic cube (a sheared frame is deferred).

```@docs
FixedDomain
```

## Dealiasing strategies

The aliasing-control strategy passed to `FixedDomain` — the supertype, then the sharp ``2/3``-rule
default, the smooth Hou–Li filter, and the exact half-cell phase-shift with spherical truncation.

```@docs
DealiasingStrategy
TwoThirds
HouLi
PhaseShift
```

The dealiasing cutoff it sets — the highest wavenumber the domain evolves, and the resolution
criterion ``\kappa_{\max}\eta`` a run is built to meet.

```@docs
max_wavenumber
```

## Scratch-field allocators

Allocate one zeroed velocity, scalar, or second-order tensor field on the domain's backend and
element type.

```@docs
new_vector_field_spectral
new_vector_field_physical
new_scalar_field_spectral
new_scalar_field_physical
new_tensor_field_spectral
new_tensor_field_physical
```

## Dealias filtering

Apply the domain's dealias low-pass kernel to a field in spectral representation, in place.

```@docs
truncate_to_band!
```
