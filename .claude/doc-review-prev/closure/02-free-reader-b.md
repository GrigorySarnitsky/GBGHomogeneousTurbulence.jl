# Closure — Hat 02-free-reader-b

## Finding 1 — Rogallo's report dated both 1981 and 1984
**VERDICT: ABSENT**

Evidence: `rg -i "Rogallo" src/ docs/src/ docs/ARCHITECTURE.md` shows the `PhaseShift` docstring
(`src/SimulationDomain.jl:114`) now reads "Rogallo (1981) — *Numerical experiments in homogeneous
turbulence*, NASA TM-81315 (no DOI)", matching `docs/ARCHITECTURE.md:2110`/`docs/src/decisions.md:1212`
("Rogallo, R. S. (1981)...") and the decision-log entry (`docs/ARCHITECTURE.md:1144`, "Rogallo 1981").
`rg "1984" src/ docs/src/ docs/ARCHITECTURE.md` returns only unrelated Nosé/Berendsen/Qian 1984
citations — no "Rogallo... 1984" anywhere in the corpus.

## Finding 2 — Warm-up gate skewness stated as both ≈−0.5 and ≈−0.05
**VERDICT: ABSENT**

Evidence: `rg "developed cascade" docs/src/decisions.md docs/ARCHITECTURE.md` shows the decision-log
sentence now reads "...against the ``\lvert S\rvert \approx 0.5`` of a developed cascade (``S`` runs
from ``0`` toward ``\approx -0.5``)" (`docs/src/decisions.md:49`, `docs/ARCHITECTURE.md:947`) — both
numbers now agree at 0.5, consistent with `skew_floor = 0.1` being glossed "a fifth of" 0.5
(`src/SimulationRun.jl:831`). No "-0.05" occurrence found anywhere near this passage.

## Finding 3 — `VarianceController` missing the two-constructor-form pattern
**VERDICT: ABSENT**

Evidence: `src/Forcing.jl:144` now lists `VarianceController(; target, gain = 1, turnover_time =
nothing, lowest_shell = 1, highest_shell = 2)` inside the `DeferredForcing` docstring's enumerated
operator-free forms. `src/Forcing.jl:529-532` shows both signatures (`VarianceController(domain; ...)`
and `VarianceController(; ...)`) documented together; `src/Forcing.jl:602` and `:832-835` implement
both, the keyword form wrapping a `DeferredForcing(domain -> VarianceController(domain; ...))` exactly
like its three siblings. The architecture's blanket claim (`docs/ARCHITECTURE.md:387`, "Each forcing
has an operator-taking constructor and an operator-free keyword form") now holds for
`VarianceController` with no unstated exception.

## Finding 4 (nit) — Notation glossary omits skewness symbol S
**VERDICT: ABSENT**

Evidence: `docs/src/notation.md:78`, `## Diagnostics` table now carries the row
`| ``S`` | the velocity-derivative skewness — the developed-cascade marker, ``\approx -0.5`` for
developed turbulence | [`derivative_skewness`](@ref) |`, alongside the other diagnostics ($k$,
$\varepsilon$, $E_\varphi(\kappa)$, $E(\kappa)$, $E(\kappa_n)$, $\langle\varphi^2\rangle$,
$\varepsilon_\varphi$).

## Finding 5 (nit) — Kolmogorov (1941) page range reads 301–305 vs standard 299–303
**VERDICT: PRESENT**

Evidence: `src/phenomenology/StructureFunctions.jl:37` still reads `Reference("Kolmogorov (1941),
*Dokl. Akad. Nauk SSSR* **30**, 301–305 (the 2/3 law) ...")` — unchanged from the finding's quoted
text. The commonly cited pagination for Kolmogorov's 1941 "local structure" paper is Dokl. Akad. Nauk
SSSR 30, 299–303, so the discrepancy the finding flagged (at low confidence) is still in the source
verbatim; no correction found.
