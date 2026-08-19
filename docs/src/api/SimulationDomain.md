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
truncation, the smooth Hou–Li filter, and the exact half-cell phase-shift with spherical
truncation.

```@docs
DealiasingStrategy
TwoThirds
HouLi
PhaseShift
```

The dealiasing cutoff it sets — the dealiasing cutoff — the highest wavenumber the run treats as resolved signal, and the resolution
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

## Band truncation

Restrict a field in spectral representation to the retained band, in place, by the domain's
low-pass kernel. Under `PhaseShift` this is only part of the dealiasing — the averaging of two
displaced evaluations is the other half, and the generator performs it where it assembles the
product.

```@docs
truncate_to_band!
```
