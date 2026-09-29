# Observables

```@autodocs
Modules = [GBGHomogeneousTurbulence.Observables]
Order   = [:module]
```

## Energy and variance

The velocity kinetic energy and its scalar analogue, the variance — both Parseval quadratic invariants.

```@docs
kinetic_energy
scalar_variance
```

## Dissipation rates

The kinetic-energy dissipation ``\varepsilon`` and the scalar-variance dissipation ``\varepsilon_\varphi``.

```@docs
dissipation
scalar_dissipation
```

## The fused energy–dissipation pair

Both quadratic reductions of the velocity from one traversal — the eddy-turnover clock's pair.

```@docs
kinetic_energy_and_dissipation
```

## Energy and dissipation below a scale

The kinetic energy and the dissipation held in scales below each box side the grid offers — what a
box of that side measures once its own mean is removed, averaged over every position.

```@docs
kinetic_energy_and_dissipation_below_scale
```

## Reynolds numbers

The box and Taylor-microscale Reynolds numbers, computed from measured scalars (a run's time-mean
``\varepsilon`` and ``k``, its ``\nu`` and box side) rather than from a field.

```@docs
reynolds_box
reynolds_taylor
```

## Derivative skewness

The velocity-derivative skewness — the developed-turbulence marker that gates warm-up.

```@docs
derivative_skewness
```

## Timestep control

The fastest flow speed on the grid, which sets the advective-CFL step — a reduction, not a physics
invariant.

```@docs
max_speed
```

## Vorticity recovery

The vorticity ``\boldsymbol{\omega} = \nabla\times\boldsymbol{u}`` recovered in physical representation
from the state's spectral representation — the field-valued observable the iteration deposits (its cached read is
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
