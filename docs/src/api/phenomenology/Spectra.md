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
SaffmanDissipation
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

## References

The published provenance of each preset on this page, read from its
[`provenance`](@ref GBGIsotropicTurbulence.Phenomenology.provenance)`(law)` — the extraction-bound leaf
carries its own citations, so these are not duplicated in the `ARCHITECTURE.md` reference list.

```@eval
import GBGIsotropicTurbulence.Phenomenology as Phen
import GBGIsotropicTurbulence.Phenomenology.Spectra as Spec
import Markdown
laws = [Spec.Pope2000(), Spec.VonKarman1948(), Spec.Pao1965(), Spec.ObukhovCorrsin1949()]
cites = unique([Phen.provenance(l).citation for l in laws])
Markdown.parse(join(["- " * c for c in cites], "\n"))
```
