# Observables

```@autodocs
Modules = [GBGIsotropicTurbulence.Observables]
Order   = [:module]
```

## Energy and variance

The velocity kinetic energy and its scalar analogue, the variance — both Parseval quadratic invariants.

```@docs
kinetic_energy
scalar_variance
```

## Dissipation rates

The kinetic-energy dissipation ε and the scalar-variance dissipation ε_φ.

```@docs
dissipation
scalar_dissipation
```

## Derivative skewness

The velocity-derivative skewness — the developed-turbulence marker that gates warm-up.

```@docs
derivative_skewness
```

## Timestep control

The maximum velocity component, which sets the advective-CFL step — a max-norm reduction, not a physics
invariant.

```@docs
max_speed
```

## Vorticity recovery

The vorticity ``\boldsymbol{\omega} = \nabla\times\boldsymbol{u}`` recovered in physical representation
from the spectral state — the field-valued observable the iteration deposits (its cached read is
[`vorticity_physical`](@ref)).

```@docs
vorticity_physical!
```

## Spectrum and length scale

The measured energy spectrum and the integral scale — the measured counterparts of a
[`Phenomenology`](../phenomenology.md) model spectrum, for validation.

```@docs
energy_spectrum
integral_scale
```
