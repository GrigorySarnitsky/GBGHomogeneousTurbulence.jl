# Scalings

```@autodocs
Modules = [GBGIsotropicTurbulence.Phenomenology.Scalings]
Order   = [:module]
```

## Laws

The dimensionless scaling constants and their Reynolds-number trends, evaluated by [`scaling`](@ref).

```@docs
ScalingLaw
Sreenivasan1998
Sreenivasan1995
Li2008
```

## Predicting dissipation

Invert a box-normalized dissipation law to the dissipation a stationary run sustains — the seam the run
layer uses to set the viscosity from the grid and target energy.

```@docs
stationary_dissipation
```
