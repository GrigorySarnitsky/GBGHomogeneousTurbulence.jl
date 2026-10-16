# Spectra

```@autodocs
Modules = [GBGHomogeneousTurbulence.Phenomenology.Spectra]
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

The factor evaluators, extended by each roll-off form, and the length a large-scale form is
evaluated against.

```@docs
large_scale_factor
large_scale_length
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

The published provenance of each law on this page, read from its
[`provenance`](@ref GBGHomogeneousTurbulence.Phenomenology.provenance)`(law)`; a source cited inline
for an individual coefficient or a comparison is cited in place and not repeated here.

```@eval
import GBGHomogeneousTurbulence.Phenomenology as Phen
import GBGHomogeneousTurbulence.Phenomenology.Spectra as Spec
import Markdown
laws = [Spec.Pope2000(), Spec.VonKarman1948(), Spec.Pao1965(), Spec.ObukhovCorrsin1949()]
cites = unique([Phen.provenance(l).citation for l in laws])
Markdown.parse(join(["- " * c for c in cites], "\n"))
```
