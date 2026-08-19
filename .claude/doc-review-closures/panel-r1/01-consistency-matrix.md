# Closure — Hat 01: consistency-matrix

## Finding 1 — `GBGStreamingStatistics` current-consumer overclaim in §1 vs deferred in §4.9
**VERDICT: ABSENT**
Evidence: docs/ARCHITECTURE.md:22-23 (= docs/src/architecture.md:22-23), §1 Identity now reads "...and
`GBGStreamingStatistics` (the statistics — the division is settled and the bridge to it is deferred,
§4.9)." §4.9 (docs/ARCHITECTURE.md:559-561) still says the bridge "is deferred (§7)". §1 no longer
overclaims a present-tense wired dependency; it self-flags the deferred status with a forward pointer,
matching §4.9. Searched all `GBGStreamingStatistics` occurrences in docs/ARCHITECTURE.md, docs/src/*.md,
src/*.jl, CLAUDE.md — no remaining overclaim found.

---

## Finding 2 — `deposit_sample!` unnamed in sibling docstring / absent from index
**VERDICT: ABSENT**
Evidence: src/Particles.jl:234, `record_particle_velocities!`'s docstring now names it explicitly:
"the slot becomes readable once [`deposit_sample!`](@ref GBGIsotropicTurbulence.Cache.deposit_sample!)
records them as current." It is exported (src/GBGIsotropicTurbulence.jl:99, :178) and appears in the
rendered `docs/build/api/GBGIsotropicTurbulence/index.html` and `docs/build/api/Cache/index.html`.
Both sibling docstrings (Cache.jl:337, Particles.jl:234) now name it consistently.

---

## Finding 3 — `skew_floor` guidance disagreement (0.4 vs 0.5) between architecture and API docstring
**VERDICT: ABSENT**
Evidence: docs/ARCHITECTURE.md:888-889 (decision 13, 2026-07): "...whose default floor is a permissive
one: raise it to `0.4` when the run must be strict, against the ``\lvert S\rvert \approx 0.5`` of a
developed cascade..." — src/SimulationRun.jl:583: "Raise it toward `0.4` when the run's statistics
depend on the cascade being mature." Both pages now cite 0.4 as the raise target and 0.5 only as the
reference value for a fully developed cascade; no disagreement remains.

---

## Finding 4 — `HouLi` `order` default (36) coincides with Float64 `strength` auto-value (~36)
**VERDICT: ABSENT**
Evidence: src/SimulationDomain.jl:83-85, the docstring now explicitly addresses the coincidence: "(That
`Float64` value lands on ``36``, which the default `order` also is: Hou & Li's own filter takes both as
``36``, and the coincidence is theirs rather than a transcription slip.)" The suspicious-coincidence
concern the finding raised (low confidence, requesting a second look) is now directly resolved in prose
with a citation-backed explanation, not merely left as a silent numeric match.

---

## Finding 5 — `velocity_predictor` called "not readable"/"never exposed" yet is a plain public struct field
**VERDICT: PRESENT**
Evidence: docs/ARCHITECTURE.md:415-416 (identical in docs/src/architecture.md) retains the exact original
claim verbatim: "`ParticleIntegratorBuffers.velocity_predictor` is a stage register of the scheme, never
a sample of the flow, and is not readable." Meanwhile the sibling `# Fields` entry, src/Particles.jl:203-205,
was rewritten to concede: "It is reachable like any field of this type, but it is a scheme intermediate
rather than a sample of the flow at any instant, so nothing in the package offers it as one." The two
pages now directly contradict each other on whether the field is readable — ARCHITECTURE.md's "not
readable" claim is unchanged and, per the sibling's own current text, false (plain Julia field access
`buffers.velocity_predictor` works). The finding's exact quoted ARCHITECTURE.md location is untouched.
