# Closure — Hat 04: DNS practitioner / GPU performance

## Finding 1 — "Float64 is the production precision" framing tension
**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md` §6 (lines 586–612) no longer contains the phrase "production
precision" or "development and desktop precision" anywhere (`rg -ni "production precision"` and
`rg -ni "desktop precision"` across the corpus, excluding `.claude/`, both return zero hits). The
section now reads neutrally: "`Float32` buys twice the grid per byte and roughly twice the
throughput on a consumer GPU; `Float64` buys the accuracy margin a long integration or a sensitive
diagnostic may need. Which one a run wants is a fitness question, settled by test rather than by a
house default." (line 591–594) — no normative label pre-judging the fitness-test outcome. The
`Simulation` front-door default `element_type = Float64` (`src/SimulationRun.jl:66,182,285`) is
unchanged, but the finding's specific complaint — the doc handing out a normative "production"
label in the same breath as disclaiming one — is gone.

---

## Finding 2 — §2.3 transform-count table's scheme scope stated only once, far from the table
**VERDICT: ABSENT**

Evidence: `docs/src/observables_cache.md` line 293–294, immediately above the table (line
296–299), now reads: "Counts are per step of a three-stage scheme (`IFLowStorageRK3`); a scheme
with a different stage count scales them by its own." This is the exact resolution hint the
finding proposed (repeat the scheme qualifier at the table). The §2 opening mention (line 222,
"a three-stage scheme") still exists as well, but the table is no longer scheme-scope-silent: the
scoping sentence sits in the paragraph directly preceding it.

---

## Finding 3 — "two field registers per field" headline vs. three-array `IntegratorBuffers`
**VERDICT: ABSENT**

Evidence: `src/Propagator.jl` lines 240–245 (the `IFLowStorageRK3` docstring) now reads: "Three
nonlinear evaluations per step, and — in Williamson's 2N-storage count, whose `N` counts evolved
field registers, not the grid points `N` of the rest of the documentation — two field registers
per field: the state's own array plus one accumulator (`stage1`). The `IntegratorBuffers` a run
allocates can hold more than that count — for this scheme it adds `nonlinear`, the dealiasing
seam's assembly register — because the count measures the scheme, not the solver it is embedded
in." This is a materially expanded, explicit sentence (not the easy-to-skim parenthetical the
finding quoted) that directly states the "2N" count is a classical-accounting convention distinct
from `IntegratorBuffers`' actual allocation, addressing the finding's own concession that this was
"very likely not a defect" at low confidence.
