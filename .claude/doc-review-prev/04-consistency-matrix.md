# Consistency-matrix audit

Hat: systematic consistency auditor — cross-referencing every recurring entity (symbol, formula,
default, citation, naming convention, ordering claim) across all pages of the rendered manuscript
(`manuscript-full.md`), diffing each entity's stated value/behaviour against every other place it
appears. Read-only; findings only.

Candidates considered before the 25-cap: ~50 (formulas verified by hand-expansion: kinetic energy,
dissipation, Yaglom 4/3→2/3 conversion, Taylor Reynolds, integral-scale ratios, Li2008 G↔Cε
identity, PhaseShift/mask transform-count tables, CFL margins, resolution-criterion Δx/η numbers;
naming cross-checks: every type's Arguments-vs-Fields keyword pairing across ~25 types; citation
cross-checks: every author-year handle against the References lists; the "iteration"/"push"/
"deposit" vocabulary; the decision-log's self-consistency on the most recent (2026-08-23) renames).
Only the findings below survived; everything else checked out (see notes below the findings for a
sample of what was verified clean).

---

## Finding 1 — Decision-log entry's own title contradicts its own body

- **Type:** contradiction
- **Severity:** blocker
- **Confidence:** high
- **Locations:**
  - PAGE: decisions — entry title: *"The `Simulation` keyword and field `scheme` → `integrator`."*
  - Same entry, two sentences later: *"The keyword family is now uniformly `<role>_scheme`: `integration_scheme` (the fields in time), `trajectory_scheme` (the particles in time), `interpolation_scheme` (space)"* and *"Scope: the `Simulation` keyword and struct field only — bare `scheme` remains the positional-argument name in the protocol"*
- **Contradicts:** itself — the header claims the field is renamed to `integrator`; the body of the same entry states the actual rename target is `integration_scheme`, and every live API page (`Simulation`'s own docstring: `integration_scheme = IFLowStorageRK3()`) confirms `integration_scheme` is correct.
- **Description:** This is not a case of "an old decision-log entry naming a superseded API" (the adjudicated exemption for historical entries) — the title is wrong even *at the moment it was written*, contradicted by its own next sentence. A reader skimming decision headers would come away believing the field is called `integrator`, which does not exist anywhere in the package.

## Finding 2 — Rogallo citation year: 1984 vs 1981

- **Type:** citation
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: api / SimulationDomain, `PhaseShift` docstring: *"combined with the spherical truncation of Rogallo (1984) — Numerical experiments in homogeneous turbulence, NASA TM-81315 (no DOI)"*
  - PAGE: architecture, §References: *"Rogallo, R. S. (1981). Numerical experiments in homogeneous turbulence. NASA TM-81315."*
  - PAGE: architecture, decision log (decision 27): *"(Patterson & Orszag 1971, Rogallo 1981)"*
- **Contradicts:** the same paper (same title, same NASA TM number) is dated 1984 in one docstring and 1981 in the architecture References list and decision log. Only one year can be correct for a single technical memorandum.
- **Description:** A same-paper, same-identifier citation year mismatch — the `PhaseShift` docstring is the odd one out against two other citing locations that agree on 1981.

## Finding 3 — `VarianceController`: constructor keyword `turnover_time` vs Fields entry `relaxation_time`

- **Type:** contradiction
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: api / Forcing, `VarianceController` Arguments: *"`turnover_time = nothing` — the large-eddy turnover time $t_\ell = 2k_\infty/3\varepsilon_\infty$ …"*
  - Same docstring, Fields section: *"`target`, `gain`, `relaxation_time` — $k_\infty$, $G$ and $t_\ell$."*
- **Contradicts:** the constructor keyword documented for $t_\ell$ is `turnover_time`; the Fields list names the stored value for the same symbol $t_\ell$ `relaxation_time` — two different identifiers for one quantity, with no note explaining a deliberate rename between keyword and field.
- **Description:** Checked against every other type in the corpus with both an Arguments and a Fields section (`Linear`, `ConstantPower`, `VarianceRescaling`, `HouLi`, `FlowConditions`, `Tracers`-adjacent records, every `Phenomenology` law) — all of them use the identical name in both sections. `VarianceController` is the sole exception, which is what makes it stand out as a probable naming slip rather than a deliberate convention.

## Finding 4 — Forcing docstring's per-stage device-readback counts are stale after the 2026-08-23 fusion decision

- **Type:** contradiction
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: api / Forcing, `add_forcing_source!`: *"Each reduction costs one blocking device-to-host transfer, at every stage — three per stage for `VarianceController`, one for `ConstantPower`"*
  - PAGE: api / Forcing, `VarianceRescaling`: *"each step blocks on a device-to-host transfer, at every stage — two under `:total`, which measures the band and the whole field."*
  - PAGE: decisions, the 2026-08-23 "three-item PF request" entry: *"Wired at every same-field multi-reduction site: `VarianceController` (three weights per stage — the unit, the band, $\lvert\boldsymbol{\kappa}\rvert^2$), `VarianceRescaling`'s `:total` pair … The synchronization ledger re-froze: the default row fell 10 → 4 crossings (one fused reduction per stage plus the $\Delta t$ choice)"*
- **Contradicts:** the decision log states `VarianceController`'s three per-stage weighted reductions were fused into **one** reduction per stage (10→4 crossings only works if 3 stages × 1 fused reduction + 1 Δt choice = 4, i.e., down from 3 stages × 3 = 9 + 1 = 10). `VarianceRescaling`'s `:total`-mode pair of reductions is stated as fused the same way. The Forcing-module docstrings for both strategies still describe the pre-fusion counts (three separate reductions; two separate readbacks).
- **Description:** A same-day (2026-08-23) architecture-level performance decision was not propagated into the two Forcing docstrings that state the exact counts it changed — a live, quotable discrepancy between the decision log and the API-facing text about the same quantity (device-to-host transfer counts).

## Finding 5 — "Iteration" ordering: does the particle push precede or follow the deposit?

- **Type:** contradiction
- **Severity:** major
- **Confidence:** medium
- **Locations:**
  - PAGE: notation, Vocabulary, `iteration`: *"one advance of the run, in this order: choose the timestep, step! the fields, deposit! to close them, then advance any tracers and record their sample."*
  - PAGE: observables_cache, §1.1: *"An iteration is everything a run does to advance from $t_n$ to $t_{n+1}$: the timestep choice, the step, **the particle push**, and **the deposits at its end**."*
- **Contradicts:** `notation.md`'s vocabulary entry states the field deposit happens, and *only then* are tracers advanced. `observables_cache.md`'s own top-level definition of the same term lists "the particle push" *before* "the deposits", i.e. the reverse order on its face. (The mechanism described elsewhere — `advect!`'s predictor step needs the just-deposited $t_{n+1}$ velocity field, and `SimulationRun.advance!`'s docstring says "Closes the iteration with `deposit!` … Advects the tracers" — supports `notation.md`'s order, which makes `observables_cache.md`'s summary phrase the one that reads backwards.)
- **Description:** Two design-doc pages give literally-ordered lists for the same defined term ("iteration") that disagree on the relative order of two of its four listed events. Flagged at medium confidence because `observables_cache.md`'s phrase can be charitably read as a loose, non-chronological enumeration rather than a strict sequence — but as written, "in this order" (notation.md) versus a bare comma list ending in "at its end" (observables_cache.md) do not obviously agree.

## Finding 6 — `IFLowStorageRK3`'s "2N" register count: which two registers?

- **Type:** contradiction
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: architecture, §4.5: *"three spectral registers per field against the low-storage scheme's two — `IFLowStorageRK3` an accumulator plus the assembly register; `IFRK2` a predictor plus two stage registers …"*
  - PAGE: api / Propagator, `IFLowStorageRK3`: *"in Williamson's 2N count, where $N$ counts evolved field registers — two registers per field: the state's own array plus one accumulator (`stage1`). The `IntegratorBuffers` a run allocates also holds `nonlinear` … the 2N count measures the scheme, not the solver it is embedded in."*
- **Contradicts:** Architecture attributes the scheme's "two" registers to *the accumulator and the assembly/`nonlinear` register* (excluding the state array from the count). The Propagator page attributes the same "two" to *the state array and the accumulator* (explicitly excluding `nonlinear` from the 2N count, calling it an addition "the solver" carries, not the scheme). Both arrive at the label "two", but by excluding a different one of the three actual registers (state, accumulator, `nonlinear`).
- **Description:** A subtle bookkeeping mismatch rather than a numeric one — the totals (`IFLowStorageRK3` needs one fewer register than `IFRK2`) agree everywhere; only the *composition* of what the classical "2N" figure counts differs between the design document and the API docstring for the same scheme.

---

## Verified clean (sample, not exhaustive)

To document the audit's coverage: kinetic energy / dissipation / scalar-variance / scalar-dissipation
formulas and normalizations agree across `architecture`, `notation`, and every `Observables`
docstring; the derivative-skewness isotropy constant $C_S = \tfrac47\sqrt{15/2}$ agrees everywhere it
appears; the Yaglom $4/3\to 2/3$ full-variance conversion in `Yaglom1949` checks out by hand
expansion; `taylor_reynolds`'s two stated forms are algebraically equivalent; the `Li2008`
$G = \tfrac32 C_\varepsilon^{-2/3}$ identity and its worked $G\approx0.81$-at-$L/L_{11}\approx5$ example
check out numerically; the PhaseShift/mask transform-count table (`observables_cache.md` §2.3) is
internally consistent once the scalar flux's 3-component vector nature is accounted for; every other
type's Arguments-keyword-to-Fields-name pairing across ~25 documented types matches exactly (only
`VarianceController` diverges, Finding 3); the `κ_max η` resolution-criterion worked numbers
($\eta\approx0.64\Delta x$ / $0.96\Delta x$ for `HouLi` / `TwoThirds` at `κ_max_η=2`) check out; the
API index pages (per-module) match their corresponding docstring-page contents exactly with no
missing or extra entries.
