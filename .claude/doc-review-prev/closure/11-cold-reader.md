# Closure — Hat 11: cold-reader (first-year grad student)

## Finding 1 — `epoch` used with zero gloss on the very first page
**Verdict:** PRESENT
**Evidence:** docs/src/index.md:48 ("each recorded against the epoch of the state it came from") still uses "epoch" with no inline gloss and no `@ref`/link to notation.md, whose Vocabulary entry (notation.md:122, "a counter of changes to the state...") remains the only definition, many screens later.

## Finding 2 — the same cache-slot state is given three different names
**Verdict:** PRESENT
**Evidence:** src/Cache.jl still uses three unlinked synonyms for the mid-iteration-scratch state on the same page: "taken" (line 92, "a read that finds a stale, taken, or never-deposited slot"), "in use as scratch" (line 114, Fields doc), "mid-iteration scratch" (line 171, `velocity_physical` docstring). No sentence states they are the same state; only the thrown error text (lines 154-156) is internally consistent.

## Finding 3 — tracer / particle / trajectory: three overlapping words, never disambiguated
**Verdict:** PRESENT
**Evidence:** src/Particles.jl module doc still mixes "tracer set" (line 20), "trajectory time-integration schemes" (line 25), `AbstractParticleIntegrator`/`particle_positions`/`particle_velocities"`; notation.md:37-39 still calls the object a "tracer particle". No sentence anywhere states whether tracer/particle/trajectory are synonyms or a general/concrete pair (decision 51's rule is in CLAUDE.md only, not surfaced to the reader).

## Finding 4 — "seam" is used as settled jargon but is never introduced anywhere
**Verdict:** PRESENT
**Evidence:** Still unglossed at src/Propagator.jl:248 ("the dealiasing seam's assembly register"), src/Phenomenology.jl:31 ("the (future) seam for fitting..."), src/phenomenology/Scalings.jl:43,149. notation.md has no "seam" entry. ARCHITECTURE.md:243 does define a "metriplectic seam" (reversible/irreversible split), but that is a different sense of the word than the three usages above, so it does not resolve them.

## Finding 5 — "the resolution criterion" is used, unglossed, in the very first Quick Start
**Verdict:** REGRESSED
**Evidence:** The unglossed-term defect is gone — docs/src/index.md:39 now names the quantity inline: "ν is set so the grid resolves the dissipation scale (the κ_max·η criterion". But the edit introduced a new defect: the parenthesis is never closed and the sentence is truncated mid-clause, both in source and in docs/build/index.html:7 — the very first Quick Start code comment now renders a broken sentence.

## Finding 6 — a circular definition: "a budget is a callback that accumulates what it budgets"
**Verdict:** PRESENT
**Evidence:** src/SimulationRun.jl:437-438 now reads "a fixed-length run is a callback that accumulates what it budgets" — the subject noun changed ("budget"→"fixed-length run") but the defining verb "budgets" is still self-referential; not glossed in notation.md. Same circularity, reworded.

## Finding 7 — "sugar" used as a bare technical noun at its first appearance
**Verdict:** PARTIAL
**Evidence:** The flagged module-doc instance is fixed: src/SimulationRun.jl:25 now reads "the packaged spin-up-to-stationarity observation, and `warmup!`, the one-line shorthand that runs it" (sugar→shorthand).
**Surviving class:** docs/src/api/SimulationRun.md:22 ("its sugar spin a fresh run up to measurement readiness") and warmup!'s own docstring, src/SimulationRun.jl:658, which now *opens* with "Sugar, and nothing more:" — unglossed, and reached before any explanation.

## Finding 8 — `PointSet` / `VectorPointValues` / `ScalarPointValues` given no provenance note
**Verdict:** PRESENT
**Evidence:** src/Particles.jl:121,207,316-317,348,357 now link these via `@extref GBGPeriodicFields …` (rendering as external grigorysarnitsky.github.io URLs), but there is no explicit flag sentence. src/SimulationDomain.jl:181-182 carries the sentence Particles.jl lacks: "The machinery types below are [`GBGPeriodicFields`](...) objects, each linked to its own documentation." The asymmetry the finding named persists.

## Finding 9 — "artifact" used as the mirror-opposite of "measurable" without being anchored as a pair
**Verdict:** PARTIAL
**Evidence:** The flagged docstring is fixed — src/Forcing.jl's `BandRescaling` (lines ~239-249) no longer uses either word; it now says "The band's energy is then set by the forcing rather than by the flow, while k still measures the flow itself" / "Here it is k that the forcing sets, and the band is free."
**Surviving class:** docs/src/architecture.md:1768-1769 (decision 54) still runs the identical unglossed opposition: "the kinetic energy is an artifact of the forcing and the band is free; under `:band` the band is the artifact and k is a measurable of the flow."
