# DNS-practitioner hat — findings

Reviewer stance: a performance-focused DNS practitioner scrutinizing the numerical methods
(integrating factor, dealiasing bands, IF-RK2/RK3, the deposit-driven cache schedule and its
transform/traffic accounting, particle interpolation, forcing) and the performance claims
(allocation-free hot loop, in-place buffers, transform counts, CFL scaling) across the rendered
site. Extensive cross-page arithmetic verification was performed (transform counts, memory sizes
in MiB/GiB, the √2/3·N PhaseShift band, the 2/3-rule band, Re_λ ~ N^(2/3) scaling, the Li2008
dissipation-group inversion, the RKW3 coefficients, the IFRK2 stability-function derivation) — the
document is unusually rigorous and internally consistent on nearly every numeric claim checked.
The findings below are the genuine survivors of that pass.

---

## Finding 1 — The cache's one non-free cost is described as both a recurring per-iteration charge and a one-time per-run charge

- **Type:** contradiction
- **Severity:** blocker
- **Confidence:** high
- **Locations:**
  - PAGE: observables_cache, §1.3: "so, relative to a cacheless solver serving only its own dynamics, the run pays one extra closing deposit: the state-only share of one first-stage evaluation, **one reduction**, and one interpolation, **per run rather than per iteration**."
  - PAGE: observables_cache, §1.4 (two sentences later in the *same* section): "the closing deposit's maximum-speed reduction is **one physical-vector pass every iteration**, paid even by a hand-fixed-Δt run that never reads the number... the only work it adds is §1.3's final closing deposit ... **paid per run rather than per iteration**."
  - PAGE: api / Propagator, `deposit!`: "It costs one pass: **the maximum-speed reduction runs every iteration**, including under a hand-fixed Δt that never reads it."
  - PAGE: architecture, decision log (2026-08, "observables cache is deposit-driven"): "surfaces the **once-per-iteration** maximum-speed readback in the pass and synchronization ledgers (+1 physical-vector pass **in every cell**; a hand-fixed-Δt iteration still pays it — held by the new UNIFORM DEPOSIT SCHEDULE design holder)."
- **Contradicts:** itself, within §1.4 of observables_cache — the same paragraph first names the max-speed reduction as "one exception" that costs "one physical-vector pass every iteration," then two sentences later says "the only work [the cache] adds" is a single closing deposit "paid per run rather than per iteration." Three other locations (§1.3 of the same page, the `deposit!` docstring, and the architecture decision log) split 1-vs-3 on which framing is correct, with the majority (and the more careful accounting in §1.4's own opening clause) supporting "every iteration."
- **Description:** This is a load-bearing performance claim — whether the deposit-driven cache design is genuinely free except for a one-time end-of-run cost, or whether it pays a real per-iteration traffic tax (as ARCHITECTURE.md's UNIFORM_DEPOSIT_SCHEDULE holder explicitly records: a hand-fixed-Δt run pays a pass it never needs, on *every* iteration, not once). A reader budgeting traffic for a long fixed-Δt run would reach opposite conclusions depending which sentence they trust. The correct reading (every iteration, per the majority and per the explicitly-named design holder) should be the one stated consistently; §1.3's summary sentence and §1.4's closing sentence both need to stop lumping the max-speed reduction in with the (genuinely once-per-run) chart-recovery amortization argument.

---

## Finding 2 — `recommended_cfl` cannot express the one variable IFRK2's own stability is said to depend on

- **Type:** method
- **Severity:** major
- **Confidence:** medium
- **Locations:**
  - PAGE: api / Propagator, `recommended_cfl(scheme, domain)`: "`IFRK2` is imaginary-axis unstable ($y_{\mathrm{s}} = 0$, relying on viscous damping), which makes the formula degenerate — its $0.25$ is an empirical margin, not a computed limit, **and the damping it leans on weakens as $\nu$ falls**."
  - Same page, `IFRK2` type docstring: "the scheme is unstable on the imaginary axis, so it is stable only where the viscous damping of the integrating factor dominates... prefer `IFLowStorageRK3` for high Reynolds number or marginal resolution."
  - The function signature itself takes only `(scheme, domain)` — no viscosity, no `FlowConditions` — so it structurally cannot scale the empirical margin with $\nu$.
- **Description:** For every other scheme/dealiasing combination the CFL ceiling is a genuinely computed bound (stability limit ÷ eigenvalue estimate). For IFRK2 the docs candidly say the "conservative" 0.25 is empirical and that the very damping it depends on **weakens as ν falls** — i.e. exactly the axis this package is built to let a user push (the whole point of `viscosity`/grid-mode Re selection). Yet `recommended_cfl` has no way to see ν, so the same constant 0.25 is offered at every Reynolds number, including ones where the docs themselves say the stabilizing mechanism is weaker. This is a genuine numerical-safety gap in the API surface (mitigated only by prose telling the user to switch schemes), not merely a documentation slip.

---

## Finding 3 — `max_speed`'s stated justification for being cached overstates its necessity

- **Type:** contradiction
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: api / Observables, `max_speed`: "The maximum speed qualifies because **the run itself needs it**: the next timestep is chosen from it, so the reduction happens whether or not anyone reads the value."
  - PAGE: api / Propagator, `deposit!`: "the maximum-speed reduction runs every iteration, **including under a hand-fixed Δt that never reads it**."
  - PAGE: api / SimulationRun, `advance!`: "pass `dt` to force a fixed step" — confirming the fixed-Δt mode is a first-class, documented path.
- **Description:** `max_speed`'s docstring justifies its cached slot on the premise that "the run itself needs it," implying the reduction is intrinsic to advancing the run. But the package explicitly supports fixed-Δt advancement (`advance!(sim; dt=...)`), in which case, per `deposit!`'s own docstring, the reduction is computed and never consumed. The justification is true only for the adaptive-CFL path; stated flatly it reads as a stronger necessity claim than the schedule actually delivers.

---

## Finding 4 — `IFRK2` is called "cheaper" without the memory axis this codebase treats as primary

- **Type:** clarity
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: architecture, §4.5: "`IFRK2` (Heun) is a cheaper two-stage option..."
  - PAGE: api / Propagator (module docstring): "`IFRK2`/Heun a cheaper two-stage alternative, imaginary-axis unstable."
  - PAGE: api / Propagator, `IntegratorBuffers` Fields: `IFLowStorageRK3` allocates `stage1` + `nonlinear` (2 spectral registers/field); `IFRK2` allocates `stage1` + `stage2` + `velocity_star_spectral` (3 spectral registers/field).
- **Description:** "Cheaper" is accurate on the compute/transform axis (2 nonlinear evaluations vs. 3), but IFRK2 actually resides at **more** spectral registers per field than the default `IFLowStorageRK3` (3 vs. 2) — the opposite ranking on the memory axis. In a package whose own charter states "'Low footprint' is the default working point on a studied axis" (§6) and that elsewhere is careful to caveat exactly this kind of register-count nuance (e.g. RK3's own docstring explicitly notes its `IntegratorBuffers` "can hold more than" Williamson's nominal 2N count, "because the count measures the scheme, not the solver it is embedded in"), the unqualified "cheaper" for IFRK2 invites a memory-conscious reader to assume it is cheaper on both axes.

---

## Findings considered and ruled out (recorded for the panel's benefit, not to be re-flagged)

- The PhaseShift band (√2/3·N·2π/L ≈ 0.94 κ_Ny, ≈2.8× the modes, exactly 2× the transforms for velocity and scalar alike) is stated identically and arithmetically consistently across architecture.md, notation.md, observables_cache.md's transform table, and the SimulationDomain/Propagator API pages — verified by direct recomputation, no defect.
- The frame-memory "322.5 MiB (three field-scale arrays) / some 8% on top of the default working set" figure (decision 36) initially looked inconsistent with observables_cache.md's later "~2.3 GiB / six vector-shaped fields" working-set figure, but the two describe different points in time (decision 36 predates the decision-40/41 register reductions that shrank the working set); 322.5 MiB / (a ~3.8 GiB pre-reduction working set) ≈ 8%, consistent. Not a defect — decision-log entries are append-only history per the adjudication file.
- The 21-inverse/18-forward (mask, with scalar) and 42-inverse/36-forward (PhaseShift, with scalar) transform counts in observables_cache.md §2.3 were independently re-derived from the stated per-evaluation transform breakdown and match exactly, including the RK3 51→42 / RK2 34→28 c2r figures from the decision log's shifted-velocity-reuse fix.
- The grid-mode $\mathrm{Re}_\lambda \sim N^{2/3}$ scaling claim (architecture decision log, SimulationRun docstring) was independently re-derived from the stated $\kappa_{\max}\eta$ resolution criterion and the Li2008 dissipation law, and checks out exactly.
