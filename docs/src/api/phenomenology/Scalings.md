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

## References

The published provenance of each law on this page, read from its
[`provenance`](@ref GBGIsotropicTurbulence.Phenomenology.provenance)`(law)` — the extraction-bound leaf
carries its own citations, so these are not duplicated in the `ARCHITECTURE.md` reference list. This
list is scoped to the laws' own provenance; sources cited inline for an individual coefficient or a
comparison (e.g. Sagaut & Cambon, *Homogeneous Turbulence Dynamics*, 2nd ed., Springer, 2018) are
cited in place and deliberately not repeated here.

```@eval
import GBGIsotropicTurbulence.Phenomenology as Phen
import GBGIsotropicTurbulence.Phenomenology.Scalings as Scal
import Markdown
laws = [Scal.Sreenivasan1998(), Scal.Sreenivasan1995(), Scal.Li2008()]
cites = unique([Phen.provenance(l).citation for l in laws])
Markdown.parse(join(["- " * c for c in cites], "\n"))
```
