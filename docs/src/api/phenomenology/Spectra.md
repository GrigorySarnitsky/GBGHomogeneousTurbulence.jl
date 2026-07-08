# Spectra

```@autodocs
Modules = [GBGIsotropicTurbulence.Phenomenology.Spectra]
Order   = [:module]
```

## The composed spectrum

A model energy spectrum is an inertial core times a large-scale and a dissipation-range roll-off.

```@docs
EnergySpectrum
ModelSpectrum
```

## Roll-off factors

The swappable large-scale and dissipation-range shapes, and Pope's forms.

```@docs
LargeScaleFactor
DissipationFactor
PopeLargeScale
PopeDissipation
VonKarmanLarge
UnitLargeScale
UnitDissipation
PaoDissipation
ExponentialDissipation
```

The factor evaluators, extended by each roll-off form.

```@docs
large_scale_factor
dissipation_factor
```

## Velocity models

The named velocity-spectrum presets of the composed [`ModelSpectrum`](@ref).

```@docs
Pope2000
VonKarman1948
Pao1965
```

## Scalar spectra

The passive-scalar spectrum models.

```@docs
ScalarSpectrum
ObukhovCorrsin1949
```
