# StructureFunctions

```@autodocs
Modules = [GBGIsotropicTurbulence.Phenomenology.StructureFunctions]
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
[`provenance`](@ref GBGIsotropicTurbulence.Phenomenology.provenance)`(law)` — the extraction-bound leaf
carries its own citations, so a reader never has to leave the page for them. A few works are cited
in `ARCHITECTURE.md` as well, where the DNS side needs them — the leaf's independence means it does
not *rely* on that list, not that the two never overlap. This
list is scoped to the laws' own provenance; sources cited inline for an individual coefficient or a
comparison (e.g. Sagaut & Cambon, *Homogeneous Turbulence Dynamics*, 2nd ed., Springer, 2018) are
cited in place and deliberately not repeated here.

```@eval
import GBGIsotropicTurbulence.Phenomenology as Phen
import GBGIsotropicTurbulence.Phenomenology.StructureFunctions as SF
import Markdown
laws = [SF.Kolmogorov1941(), SF.Kolmogorov1962(), SF.SheLeveque1994(), SF.Yaglom1949(), SF.Lundgren2002()]
cites = unique([Phen.provenance(l).citation for l in laws])
Markdown.parse(join(["- " * c for c in cites], "\n"))
```
