# Panel hat: invariants-and-decisions

Scope: `CLAUDE.md`'s Core invariants, `docs/ARCHITECTURE.md` §11's decision log, the rendered
manuscript, and `src/*.jl`, cross-checked for whether the package still honours its own recorded
invariants and decisions. Method: read the full decision log (56 entries) and CLAUDE.md's
invariants, then cross-referenced every current-state claim in the rendered pages against them,
verifying a large sample of the load-bearing claims (naming, signatures, module contents, memory
figures, forcing archival status, extraction-boundary purity) directly against `src/*.jl`.

Overall verdict: this corpus is unusually self-consistent — CLAUDE.md, the ARCHITECTURE.md
decision log, the rendered pages, and the source all agreed on every substantive check performed
(the six-verb protocol, the `ω_consumed`/`u_consumed` naming of decision 56, `StochasticOU`'s
un-exported archival status, the extraction-bound `Phenomenology` leaf's zero PF/SS dependency,
the 384 MiB-per-vector arithmetic behind decisions 37/41, the `advect!`/`particle_positions`/
`number_of_particles` renames of decisions 50–51, and more). Only one genuine class of defect
surfaced.

## Finding 1: The umbrella module's own "Module layout" comment states the wrong include order — reversing the very dependency decision 23(a) added

- **Type:** contradiction
- **Severity:** minor
- **Confidence:** high
- **Locations:**
  - `src/GBGIsotropicTurbulence.jl`, lines 12–25 (the "Module layout" comment): lists
    `"Cache … Generator … Forcing … Propagator"` — i.e. **Generator before Forcing**.
  - `src/GBGIsotropicTurbulence.jl`, lines 58–66 (the actual `include(...)` calls, ~30 lines
    below the comment): `include("Cache.jl")`, then `include("Forcing.jl")`, then
    `include("Generator.jl")` — i.e. **Forcing before Generator**.
  - `CLAUDE.md`, "Modules and wiring": `"Include order: SimulationDomain → State → Observables →
    Cache → Forcing → Generator → Propagator → Particles → SimulationRun"`.
  - `docs/ARCHITECTURE.md` §4.9 / rendered `architecture` page: `"SimulationDomain → State →
    Observables → Cache → Forcing → Generator → Propagator → Particles → SimulationRun."`
  - `src/Generator.jl` line 43: `using ..Forcing: AbstractForcing, NoForcing, …` — Generator
    *consumes* Forcing, confirming Forcing must be included first.
  - A secondary, weaker echo of the same drift: `src/SimulationRun.jl` line 5's prose comment
    ("it wires the pieces of SimulationDomain/State/**Generator**/Observables/**Forcing**/
    Propagator/Particles") also places Generator before Forcing and omits Cache entirely.
- **Contradicts:** the umbrella file's own `include()` statements 30 lines below the comment, and
  both authoritative documents' explicit "Include order" statement (CLAUDE.md and ARCHITECTURE
  §4.9 both say Forcing precedes Generator) — the axis of disagreement is the ordering of two
  named modules in a five-way described sequence.
- **Description:** Decision 23(a) explicitly earned the `Generator → Forcing` *dependency* edge
  ("this adds the honest Generator → Forcing dependency (the RHS includes the forcing source)"),
  which is why Forcing must be textually included first — and the real `include()` list, and both
  CLAUDE.md and ARCHITECTURE.md, get this right. But the umbrella module's own top-of-file "Module
  layout" comment — whose opening line says "it sets the include order" — states the modules in
  the opposite order for exactly this pair, an internal inconsistency a maintainer reading the file
  top-to-bottom would trip on immediately (the comment's claim is falsified by the code 30 lines
  below it). This is a source-level, not user-facing, defect, but it is squarely a decision/
  invariant currency lapse: the file never got the memo its own dependency decision required.
