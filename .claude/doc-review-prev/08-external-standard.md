# Hat 08 — Senior DNS Referee (external required-content standard)

Reviewed against the domain's required-content checklist (resolution criteria, timestep
constraints per term, closure/fit validity ranges, statistical-convergence statements,
initialization transients, periodicity consequences, conservation diagnostics) rather than
against the corpus's own claims. Findings below are absences or partial statements the
checklist requires; recorded deferrals (statistics layer, LES, high-Schmidt machinery, sheared
frame/rotation) are explicitly excluded per instructions.

---

## Finding 1 — The default viscosity-setting law is calibrated at one Re_λ, with no stated validity range

- **Type:** method
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: api / phenomenology / Scalings — `Li2008`: *"the value is this package's own reduction of that database's forced-isotropic dataset (Re_λ ≈ 433), consistent with higher-Reynolds-number periodic-box DNS."*
  - PAGE: api / SimulationRun — `Simulation`: *"First it estimates the dissipation the box sustains, from the box-normalized law `Li2008`"*
  - PAGE: api / phenomenology / Phenomenology — `Reference`: *"valid_Reλ = (lo, hi) ... it is advisory: a comparison that opts in reads it, nothing enforces it."*
  - PAGE: api / phenomenology / StructureFunctions — `Lundgren2002`: *"the law's `provenance` records a validity floor of Re_λ = 50"*
- **Description:** `Li2008`'s G≈0.9 is a single-dataset fit at Re_λ≈433, yet `Simulation`'s grid mode uses it by default to set ν for *any* `grid_points_per_axis`/`κ_max_η`, including small, low-Re_λ toy runs (32³, 64³) that sit far from the calibration point. The `Reference` type carries exactly the field needed to flag this (`valid_Reλ`), and `Lundgren2002` demonstrates it is used elsewhere in the same law family with a stated floor — but `Li2008`, `Sreenivasan1995`, and `Sreenivasan1998` (whose own prose states "above Re_λ ~ 50") never surface a numeric range in the rendered docs. The load-bearing default is the one law left unguarded.
- **Resolution hint:** state a `valid_Reλ` for `Li2008` (and the two `Scalings` laws), or have the constructor warn when the implied Re_λ falls outside it — the same way the scalar-resolution check already warns.

---

## Finding 2 — No stability bound is stated for source-routed (explicit-stage) forcing terms

- **Type:** method
- **Severity:** major
- **Confidence:** medium
- **Locations:**
  - PAGE: api / SimulationRun — `advance!`: *"the step is adaptive — the smallest of the advective-CFL value ... the longest mode's diffusive-decay time ... and `max_dt`"*
  - PAGE: api / Forcing — `add_forcing_source!`: *"three per stage for `VarianceController`"* (a state-dependent rate added at every RK stage)
- **Description:** The default velocity forcing (`VarianceController`) and `ConstantPower` inject a state-dependent rate through the explicit Runge–Kutta stages rather than the exact integrating factor (§4.2, §4.4). The documented adaptive Δt weighs only the advective CFL, a diffusive-decay cap, and a user ceiling `max_dt`; nothing addresses whether a large gain `G`, a mistuned `turnover_time`, or a poorly resolved forced band can itself impose a timestep restriction independent of advection — a real possibility once a stiff-looking source rides the explicit stages rather than the exact factor.
- **Resolution hint:** either state why the forcing rate is always dominated by the advective bound, or fold a forcing-magnitude term into `recommended_cfl`/the adaptive-step documentation.

---

## Finding 3 — No averaging-window or ensemble-size statement for any quoted diagnostic

- **Type:** method
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: notation — *"the single-realization estimate of the homogeneous ensemble average (exact only in the ergodic, infinite-box limit; at a finite box it retains the large-scale statistical fluctuation)"*
  - PAGE: api / Observables — `energy_spectrum`: *"At low κ the integer shells hold few lattice modes, so the density estimate is correspondingly lumpy there."*
  - PAGE: decisions — *"`validate_spectrum(sim, model)` compares the measured spectrum against a model spectrum evaluated at that state"*
- **Description:** `energy_spectrum`, `derivative_skewness`, `dissipation`, and the model-comparison harness are all evaluated from a single instantaneous field. The notation page states the general single-realization caveat and `energy_spectrum`'s own docstring flags low-κ "lumpiness," but nowhere is a reader told how many eddy-turnovers of time-averaging (or how many independent realizations) a diagnostic needs before a comparison against a `Phenomenology` law is statistically meaningful — a basic DNS reporting requirement, and the natural next sentence after the caveats already given.
- **Resolution hint:** state a minimum averaging window (in turnovers, as the package's own eddy-turnover clock already measures) for `energy_spectrum`/`derivative_skewness` before a `Phenomenology` comparison is drawn.

---

## Finding 4 — Scope of the scalar-resolution warning across grid/explicit viscosity modes is unstated

- **Type:** method
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: api / SimulationRun — `Simulation`: *"The constructor warns when the run's κ_max η_B falls below the 1.5 well-resolved floor"*
  - PAGE: api / SimulationRun — `Simulation`: *"Explicit mode: pass `viscosity` and it is used directly ... for a decaying run ... or manual control."*
- **Description:** The scalar under-resolution warning appears in the same paragraph as grid-mode ν selection. The explicit-mode paragraph never states whether the same κ_max η_B check still fires when ν is supplied by hand — the one case (high-Re, user-chosen ν) where an under-resolved scalar is most likely. A reader cannot tell whether the package's one automatic Sc>1 safeguard is grid-mode-only.
- **Resolution hint:** state explicitly that the warning is computed from ν regardless of how it was obtained (or that it is grid-mode-only, if that is the case).

---

## Finding 5 — No user-facing recipe to check a run's own numerical conservation

- **Type:** method
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: decisions — *"The ν = 0 truncated-Euler experiment — a scheme and dealiasing oracle ... It is not a turbulence run ... and it is deferred as a test, not a capability."*
  - PAGE: architecture §10 — *"its nontrivial claims are dynamical ... pinned by numerical oracle tests"*
- **Description:** The one instrument that isolates the time scheme's own numerical energy drift from viscous dissipation (the ν=0 truncated-Euler oracle, which would let a user verify their scheme's conservation order) is explicitly confined to the internal test suite. A user running a real forced, viscous case has no documented recipe for checking how much of a measured energy or scalar-variance budget is genuine physics versus scheme-introduced drift.
- **Resolution hint:** document a minimal user-runnable check (e.g., a short unforced/very-low-ν segment with energy logged) alongside the existing conservation discussion in §4.2.

---

## Finding 6 — Rogallo citation year contradicts itself (1984 vs 1981) for the identical report

- **Type:** contradiction
- **Severity:** minor
- **Confidence:** high
- **Locations:**
  - PAGE: api / SimulationDomain — `PhaseShift`: *"the spherical truncation of Rogallo (1984) — Numerical experiments in homogeneous turbulence, NASA TM-81315"*
  - PAGE: architecture — References: *"Rogallo, R. S. (1981). Numerical experiments in homogeneous turbulence. NASA TM-81315."*
  - PAGE: decisions — decision 27: *"Rogallo 1981"*
- **Contradicts:** the same title and report number (NASA TM-81315) is dated 1984 in one rendered docstring and 1981 everywhere else in the corpus (References list and decision log).
- **Description:** One of the two years is simply wrong; NASA TM-81315 is the 1981 report cited correctly elsewhere in the same document set.

---

## Finding 7 — No initialization-transient marker for a decaying (unforced) run

- **Type:** method
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: api / SimulationRun — `StationarityCriterion`: *"A freely decaying run (`NoForcing()`) has no stationary state to detect ... give a decaying run a fixed-length loop instead"*
  - PAGE: decisions — *"`Decay` (k ∼ t^{-n}) ... named future seams, not owed"*
- **Description:** `warmup!`/`StationarityCriterion` only detects the end of the initial transient for a *forced* run (via the ε-flatness and skewness gates). For a decaying run the documentation offers no criterion at all for when the initial-condition transient has ended and self-similar decay has begun — not even a suggestion to reuse the existing `derivative_skewness` plateau test by hand. This is distinct from the recorded deferral of a `k ∼ t^{-n}` fitting law (`Phenomenology.Scalings.Decay`): a transient-end *marker* is a documentation gap even without that fitted law.
- **Resolution hint:** note that the skewness-plateau gate (already built) can be applied by hand to a decaying run's own callback as a transient-end marker.

---

## Checklist items found adequately covered (no finding needed)

For completeness, noting where the corpus already meets the standard well, so these are not
silently absent from this review:

- **Velocity resolution criterion** (`κ_max η`, threshold 1.5–2, enforced at `Simulation`
  construction in grid mode) is thorough, including the cross-strategy consistency caveat
  (`HouLi` gives ~31% higher Re_λ at the same `κ_max η`).
- **Diffusive stability limit** is explicitly and repeatedly stated as removed by the exact
  integrating factor; the retained "longest mode's diffusive-decay time" cap is clearly
  explained as an accuracy/meaningfulness bound for decaying flows, not a stability limit.
- **Advective CFL** derivation, per-scheme ceiling, and its two competing loosenesses are
  unusually well documented (`recommended_cfl`).
- **Forcing-style validity axis** for `Li2008` (stationary-forced balance only, invalidated by
  moving the forcing band) is explicitly stated — only the Reynolds-number axis of the same
  law's validity is missing (Finding 1).
