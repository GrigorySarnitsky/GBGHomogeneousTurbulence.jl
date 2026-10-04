# SimulationDomain

```@autodocs
Modules = [GBGHomogeneousTurbulence.SimulationDomain]
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

A strategy sets two band edges: the **retained** cutoff (the highest wavenumber kept energetic, which
prices the advective-CFL step) and the **resolved** cutoff (the highest wavenumber whose dynamics is
genuine Navier–Stokes — the ``\kappa_{\max}`` of the resolution criterion ``\kappa_{\max}\eta`` a
run is built to meet). The two coincide for the sharp strategies and differ under `HouLi`.

```@docs
max_retained_wavenumber
max_resolved_wavenumber
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

## Persistence

The domain persists to HDF5 as its defining parameters in one self-describing group, available once `HDF5` is loaded.

```@docs
write_domain
read_domain
```
