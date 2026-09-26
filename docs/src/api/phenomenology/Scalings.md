# Scalings

```@autodocs
Modules = [GBGHomogeneousTurbulence.Phenomenology.Scalings]
Order   = [:module]
```

## Laws

The dimensionless scaling constants and their Reynolds-number trends, evaluated by [`scaling`](@ref).

```@docs
ScalingLaw
Sreenivasan1998
Sreenivasan1995
```

## References

The published provenance of each law on this page, read from its
[`provenance`](@ref GBGHomogeneousTurbulence.Phenomenology.provenance)`(law)`; a source cited inline
for an individual coefficient or a comparison is cited in place and not repeated here.

```@eval
import GBGHomogeneousTurbulence.Phenomenology as Phen
import GBGHomogeneousTurbulence.Phenomenology.Scalings as Scal
import Markdown
laws = [Scal.Sreenivasan1998(), Scal.Sreenivasan1995()]
cites = unique([Phen.provenance(l).citation for l in laws])
Markdown.parse(join(["- " * c for c in cites], "\n"))
```
