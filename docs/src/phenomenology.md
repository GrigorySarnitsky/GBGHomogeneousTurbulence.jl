# Phenomenology — reference turbulence laws

`Phenomenology` collects the established turbulence phenomenology — model spectra, structure-function
laws, and dimensionless scaling constants — as evaluatable reference predictions. It is the *predicted*
counterpart to the measured observables: the DNS measures, the laws predict, and the validation layer
sets them side by side. No law is assumed by the solver; each is a testable prediction, and our own
fits sit beside the literature on equal footing.

**One pattern.** Each law family is an abstract type; each parametrization is a named preset
carrying its fitted coefficients and its provenance, evaluated against a
[`FlowParameters`](@ref) bundle. Usually the preset is itself a concrete subtype; the composite
model spectra are the exception — `Pope2000`, `VonKarman1948`, and `Pao1965` are factory
*functions* returning a ready-assembled `ModelSpectrum` (the subtype), so test `spec isa
EnergySpectrum` on the value they return, not on the preset name. Choosing a law is choosing the
preset — the published fit is the default, and any coefficient can be overridden to re-fit:

```julia
using GBGIsotropicTurbulence.Phenomenology         # FlowParameters, spectrum, …
using GBGIsotropicTurbulence.Phenomenology.Spectra  # the model presets (Pope2000, …)

fp = FlowParameters(viscosity = 1e-3, dissipation = 0.1, rms_velocity = 1.0, integral_scale = 1.0)
E  = spectrum(Pope2000(), 10.0, fp)          # Pope (2000) model spectrum at κ = 10
```

**Naming — a three-level handle.** A model's name disambiguates on three axes: the **quantity** is the
submodule ([`Spectra`](api/phenomenology/Spectra.md) versus
[`StructureFunctions`](api/phenomenology/StructureFunctions.md)), the **paper** is the author-year type
(`Pope2000`), and a same-author-year-quantity collision takes a trailing letter (`Pope2014a`). So the
existing `StructureFunctions.Kolmogorov1941` (the 2/3 and 4/5 laws) and a spectrum counterpart — a
`Spectra.Kolmogorov1941`, were one added — would be distinct, separated by the submodule alone.

**Opt-in namespace.** `using GBGIsotropicTurbulence` brings the DNS API only; the laws are reached
through the submodule namespace, e.g. `using GBGIsotropicTurbulence.Phenomenology.Spectra` (this module
is [designed to be extractable](architecture.md) into a standalone package).

## Pages

- [Reference laws](api/phenomenology/Phenomenology.md) — the law interface and the `FlowParameters`
  bundle with its derived scales.
- [Spectra](api/phenomenology/Spectra.md) — model energy spectra ``E(\kappa)``, composed of an inertial
  core and swappable roll-off factors.
- [StructureFunctions](api/phenomenology/StructureFunctions.md) — the inertial-range structure-function
  laws ``D_{L\dots}(r)``.
- [Scalings](api/phenomenology/Scalings.md) — the dimensionless constants and their Reynolds-number
  trends.
