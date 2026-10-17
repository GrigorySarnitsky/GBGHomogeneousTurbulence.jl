# Observables

```@autodocs
Modules = [GBGHomogeneousTurbulence.Observables]
Order   = [:module]
```

## Energy and variance

These are the velocity kinetic energy and its scalar analogue, the variance — both Parseval quadratic
invariants.

```@docs
kinetic_energy
scalar_variance
```

## Dissipation rates

These are the kinetic-energy dissipation ``\varepsilon`` and the scalar-variance dissipation ``\varepsilon_\varphi``.

```@docs
dissipation
scalar_dissipation
```

## The fused energy–dissipation pairs

One traversal measures both quadratic reductions of a field. The velocity's pair gives the
eddy-turnover time ``k/\varepsilon``, the time scale of the energy-containing eddies; the scalar's
gives its decay time ``\langle\varphi^{2}\rangle/\varepsilon_\varphi``.

```@docs
kinetic_energy_and_dissipation
scalar_variance_and_dissipation
```

## Energy and dissipation below a scale

These are the kinetic energy and the dissipation held in scales below each box side the grid offers —
what a box of that side measures once its own mean is removed, averaged over every position.

```@docs
kinetic_energy_and_dissipation_below_scale
```

## Reynolds numbers and the Taylor and Kolmogorov scales

The box and Taylor-microscale Reynolds numbers, the Taylor microscale and the three Kolmogorov scales
are computed from measured scalars (a run's time-mean ``\varepsilon`` and ``k``, its ``\nu`` and box
side) rather than from a field. The arguments run from the largest scale to the smallest.

```@docs
reynolds_box
reynolds_taylor
taylor_length
kolmogorov_length
kolmogorov_time
kolmogorov_velocity
```

## Derivative skewness

The velocity-derivative skewness is the developed-turbulence marker that can gate the warm-up.

```@docs
derivative_skewness
```

## Timestep control

The fastest flow speed on the grid sets the advective-CFL step; it is a reduction, not a physics
invariant.

```@docs
max_speed
```

## Vorticity recovery

The vorticity ``\boldsymbol{\omega} = \nabla\times\boldsymbol{u}`` is recovered in physical
representation from the state's spectral representation; it is the field-valued observable the iteration deposits (its cached read is
[`vorticity_physical`](@ref)).

```@docs
vorticity_physical!
```

## Spectrum and length scale

The energy spectrum as a density per unit wavenumber, and the integral length scale read from it.

```@docs
energy_spectrum
integral_length
```
