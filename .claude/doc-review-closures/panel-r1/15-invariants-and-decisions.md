# Closure verdicts — hat 15-invariants-and-decisions

## Finding 1: The umbrella module's own "Module layout" comment states the wrong include order — reversing the very dependency decision 23(a) added

**VERDICT: PARTIAL**

**Evidence:** The primary defect is fixed: `src/GBGHomogeneousTurbulence.jl`'s "Module layout" comment
(lines 11–24) now lists `Forcing` before `Generator` and explicitly says "Included BEFORE Generator:
decision 23(a) earned the Generator → Forcing edge, so Forcing's types must exist first" — matching the
actual `include()` order at lines 62–63 (`include("Forcing.jl")` then `include("Generator.jl")`).

**Surviving class:** The finding's own "secondary, weaker echo" is still present verbatim:
`src/SimulationRun.jl` line 5 still reads "…it wires the pieces of
SimulationDomain/State/Generator/Observables/Forcing/Propagator/Particles…" — Generator still placed
before Forcing, and Cache still omitted from the list entirely. The class (an ordering-drift echo of
decision 23(a) in a prose comment) survives at this second site even though the finding's primary,
more load-bearing instance (the umbrella module's own layout comment) was corrected.
