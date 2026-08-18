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
carries its own citations, so a reader never has to leave the page for them. A few works are cited
in `ARCHITECTURE.md` as well, where the DNS side needs them — the leaf's independence means it does
not *rely* on that list, not that the two never overlap. This
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
