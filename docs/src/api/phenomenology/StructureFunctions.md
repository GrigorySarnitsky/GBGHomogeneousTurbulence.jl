# Structure functions

```@autodocs
Modules = [GBGIsotropicTurbulence.Phenomenology.StructureFunctions]
Order   = [:module]
```

## Laws

The inertial-range structure-function laws, evaluated by [`structure_function`](@ref) (amplitudes) or
[`scaling_exponent`](@ref) (the intermittency exponents, for `SheLeveque1994` and `Kolmogorov1962`).

```@docs
StructureFunction
Kolmogorov1941
Kolmogorov1962
SheLeveque1994
Yaglom1949
Lundgren2002
```
