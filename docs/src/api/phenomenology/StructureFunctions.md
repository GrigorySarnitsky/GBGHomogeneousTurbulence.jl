# StructureFunctions

```@autodocs
Modules = [GBGHomogeneousTurbulence.Phenomenology.StructureFunctions]
Order   = [:module]
```

## Laws

The inertial-range structure-function laws, evaluated by [`structure_function`](@ref) (amplitudes) or
[`scaling_exponent`](@ref) (the exponents ``\zeta_p`` — self-similar for `Kolmogorov1941`, anomalous for `SheLeveque1994` and `Kolmogorov1962`).

```@docs
StructureFunction
Kolmogorov1941
Kolmogorov1962
SheLeveque1994
Yaglom1949
Lundgren2002
```

## References

The published provenance of each law on this page, read from its
[`provenance`](@ref GBGHomogeneousTurbulence.Phenomenology.provenance)`(law)`; a source cited inline
for an individual coefficient or a comparison is cited in place and not repeated here.

```@eval
import GBGHomogeneousTurbulence.Phenomenology as Phen
import GBGHomogeneousTurbulence.Phenomenology.StructureFunctions as SF
import Markdown
laws = [SF.Kolmogorov1941(), SF.Kolmogorov1962(), SF.SheLeveque1994(), SF.Yaglom1949(), SF.Lundgren2002()]
cites = unique([Phen.provenance(l).citation for l in laws])
Markdown.parse(join(["- " * c for c in cites], "\n"))
```
