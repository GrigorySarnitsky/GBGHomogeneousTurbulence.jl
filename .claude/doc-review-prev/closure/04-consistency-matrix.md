# Closure audit — 04-consistency-matrix

## Finding 1 — Decision-log entry's own title contradicts its own body

**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:2039` decision 62 now reads "The `Simulation` keyword and field
`scheme` → `integration_scheme`." — title and body agree (body: "the `Simulation` keyword and struct
field only … integration_scheme"). Searched for any surviving `scheme` → `integrator` title with
`grep -n '`scheme`.*integrator|integrator.*`scheme`'` — only decision 55, whose title is the *reverse*
direction (`integrator` → `scheme`, correctly, an earlier decision) and which carries its own forward
pointer: "*(Refined 2026-08-23, decision 62: the `Simulation` keyword and field are now the qualified
`integration_scheme` …)*". `src/SimulationRun.jl` confirms the live field is `integration_scheme`
(lines 214, 260, 271, 295–296, 352, 407, 565). No `integrator` field/keyword exists anywhere.

## Finding 2 — Rogallo citation year: 1984 vs 1981

**VERDICT: ABSENT**

Evidence: `grep -rn "Rogallo" src/*.jl docs/ARCHITECTURE.md docs/src/*.md` — every citing location now
reads 1981: `src/SimulationDomain.jl:114` ("Rogallo (1981) — *Numerical experiments in homogeneous
turbulence*, NASA TM-81315"), `docs/ARCHITECTURE.md:2110` and `docs/src/decisions.md:1212`
(References list), and `docs/ARCHITECTURE.md:1144` / `docs/src/decisions.md:246` (decision log). No
instance of "1984" attached to Rogallo remains in the corpus.

## Finding 3 — `VarianceController`: constructor keyword `turnover_time` vs Fields entry `relaxation_time`

**VERDICT: ABSENT**

Evidence: `src/Forcing.jl:579` (Arguments) and `:592` (Fields) both now read `turnover_time`; the
struct field is `turnover_time::T` (`:598`), the constructor keyword is `turnover_time` throughout
(`:144, :529, :531, :603, :618, :621, :623, :667, :832, :834`). `grep -n "relaxation_time"
src/Forcing.jl` returns nothing — the divergent name is gone, both sections and the field agree.

## Finding 4 — Forcing docstring's per-stage device-readback counts are stale after the fusion decision

**VERDICT: ABSENT**

Evidence: `src/Forcing.jl:261-264` (`add_forcing_source!`) now reads "Measuring the state costs one
blocking device-to-host transfer **at every stage** — a single fused multi-weight reduction answers
`VarianceController`'s three weighted sums together, `ConstantPower` reads its band … the same fused
way, and `Linear` pays none." `src/Forcing.jl:366-367` (`VarianceRescaling`) now reads "each step
blocks on one device-to-host transfer: the band and whole-field observables ride a single fused
traversal, in either mode" — the stale "two under `:total`" language is gone. Both match the decision
log's 10→4 crossing accounting (`docs/ARCHITECTURE.md:2072`). Grep for stale phrasing ("three per
stage", "two under", "two separate", "three separate") in `src/Forcing.jl` / `docs/src/*.md` finds
only a `#` comment (`:658`) correctly describing what the fusion *avoids*, not a stale claim.

## Finding 5 — "Iteration" ordering: does the particle push precede or follow the deposit?

**VERDICT: ABSENT**

Evidence: `docs/src/notation.md:127` still gives deposit-then-push ("`step!` the fields, `deposit!` to
close them, then advance any tracers"). `docs/src/observables_cache.md:29-30` now reads "the timestep
choice, the step, the closing deposits, **and the particle push that ends on them**" — the push is
now stated as depending on / following the deposits, matching notation.md's order. The previously
flagged "the particle push, and the deposits at its end" phrasing (push-before-deposit) is gone.

## Finding 6 — `IFLowStorageRK3`'s "2N" register count: which two registers?

**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:403-411` still states its own comparison count (`IFLowStorageRK3`'s
"two: an accumulator plus the assembly register") distinctly from `src/Propagator.jl:254-258`'s
Williamson-2N count ("two registers per field: the state's own array plus one accumulator … the 2N
count measures the scheme, not the solver"), but the ARCHITECTURE passage now explicitly reconciles
them: "Williamson's own '2N' label counts differently — the state's array plus the accumulator, the
assembly excluded as the solver's, not the scheme's (the `IFLowStorageRK3` docstring keeps that
ledger); the two bookkeepings agree on the point that matters, one register in `IFRK2`'s disfavor."
The composition difference is now named and explained rather than left as a silent, unexplained
mismatch — the defect the finding described (an unreconciled contradiction) no longer exists.
