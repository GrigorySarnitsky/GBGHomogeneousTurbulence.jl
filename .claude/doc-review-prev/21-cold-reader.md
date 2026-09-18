# Hat: cold-reader (first-year turbulence grad student, new to the package)

Read the full rendered-docs manuscript top-to-bottom (Home → api index → decisions → notation →
phenomenology overview → each `api/*` module page in the api page's own stated reading order →
each `api/phenomenology/*` page). Findings below are ordered most-significant first. Each cites the
exact page (the `PAGE:` banner) and quotes the decisive text.

---

## 1. The epoch counter is called two different, unreconciled things: a "staleness counter" and a "freshness counter"

- **Type:** contradiction
- **Severity:** minor
- **Confidence:** high
- **Locations:**
  - Home: *"the EPOCH — the cache's staleness counter, advanced by every step and every announced mutation"*
  - api/Propagator (`deposit!`): *"record each slot at the current epoch (the cache's freshness counter)"*
  - api/Propagator (`step!`): *"The cache's fields epoch — the freshness counter every new deposit is recorded at"*
  - api/State (both seeders): *"which advances the fields epoch — the cache's freshness counter"*
- **Contradicts:** Home's inline code comment names the epoch a "staleness counter" (used exactly once, and it's the very first page a reader meets); four other sites across two later pages (Propagator, State) consistently call the identical object a "freshness counter." Neither the Notation page's Vocabulary entry for "epoch" uses either word, so nothing reconciles the two.
- **Description:** A newcomer meets "staleness counter" on Home before anything else, then meets "freshness counter" repeatedly later with no signal these are the same counter viewed differently rather than two different mechanisms. One vocabulary choice should win everywhere the concept is named.

---

## 2. Cache page tells a hand-run loop to call two verbs it hasn't defined yet

- **Type:** organization
- **Severity:** major
- **Confidence:** medium-high
- **Locations:**
  - api/Cache (module doc): *"`deposit_sample!` — records the particle velocities `record_particle_velocities!` wrote."*
  - api/Cache (`particles_modified!`): *"A hand-run loop that repositions tracers itself calls this, then `record_particle_velocities!`, then `deposit_sample!`... also takes `restart!`"*
  - api/Particles (`record_particle_velocities!`, `restart!`): defined four sections later, on the page the api index itself schedules after Cache.
- **Description:** The api page's own stated reading order is SimulationRun → SimulationDomain → State → Observables → Cache → Forcing → Generator → Propagator → Particles. Cache (5th) hands a reader an explicit hand-run recipe naming `record_particle_velocities!` and `restart!` as steps to call, but neither is explained — or even cross-linked — until Particles (9th). A reader trying to follow the recipe in place has nothing to go on beyond guessing from the names.

---

## 3. `history_depth` keyword's source is never stated where it's needed

- **Type:** api-gap
- **Severity:** major
- **Confidence:** medium-high
- **Locations:**
  - api/Cache (`ObservablesCache`): *"`history_depth = 1` — how many Lagrangian samples the run must be able to look back over... an `order`-step scheme needs `order`."*
  - api/Particles (`history_depth`): *"`history_depth(scheme) -> Int`... A run reads this to size the sample history its `ObservablesCache` carries."*
- **Description:** The Cache page invites a reader to hand-build an `ObservablesCache` ("a hand-assembled run constructs it here") and asks for `history_depth`, but never says the value comes from calling `history_depth(trajectory_scheme)`. That connection is stated only in reverse, and only later, on the Particles page ("a run reads this to size..."). A reader assembling a run by hand — the exact audience the Cache docstring addresses — has to reverse-engineer where the number comes from.

---

## 4. `VarianceController` silently breaks the forcing family's constructor pattern, unexplained

- **Type:** organization
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - api/Forcing (`Linear`, `ConstantPower`, `VarianceRescaling`): each shown as `Strategy(domain; ...)`, and all three are exactly the constructors the `DeferredForcing` docstring enumerates as the operator-free forms.
  - api/Forcing (`VarianceController`): only signature shown is *"`VarianceController(; target, gain = 1, turnover_time = nothing, lowest_shell = 1, highest_shell = 2)`"* — no `domain` argument anywhere, and it is not among the three constructors `DeferredForcing` lists.
- **Description:** `VarianceController` is the front door's default forcing and, like its siblings, carries a `band` kernel field — yet it is the one strategy in the family that never takes `domain` and is left out of the `DeferredForcing` enumeration. Nothing on the page tells a reader whether this is deliberate (it needs no domain at all) or an undocumented gap; having just read three siblings that all take `domain`, the asymmetry reads as an omission.

---

## 5. "Lie–Trotter operator splitting" backs a load-bearing accuracy claim with no gloss anywhere on the site

- **Type:** clarity
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - api/Forcing (`VarianceRescaling`): *"the rescale is applied after the step, which is Lie–Trotter operator splitting, and Lie–Trotter is first-order however good the scheme is."*
- **Description:** The claim that `VarianceRescaling` caps a third-order scheme at first order rests entirely on the reader already knowing what Lie–Trotter splitting is; the term is never defined, linked, or even repeated elsewhere except as unglossed plain "operator splitting" in the Forcing module docstring. A first-year turbulence student who hasn't taken a numerical-splitting course has no way to check the claim from the page itself.

---

## 6. `flow_parameters` points at a whole undocumented-so-far module on the very first page read

- **Type:** clarity
- **Severity:** minor
- **Confidence:** low-medium
- **Locations:**
  - api/SimulationRun (first page in the api's own reading order): *"`flow_parameters` — the run's measured flow state as a `Phenomenology` `FlowParameters`."*
  - api/phenomenology/Phenomenology (last page group, marked "opt-in"): where `FlowParameters` is actually documented.
- **Description:** `Phenomenology` and `FlowParameters` are named on the very first API page with nothing behind them yet except Home's one-line preview ("model spectra, structure-function laws, and scaling constants"). Low severity because Home does pre-introduce the module name, but a cold reader meets a bundle type by name pages before its fields, units, or constructor are shown.

---

## 7. Two labels for the same accessor family: "checked reads" vs "checked accessors"

- **Type:** language-tone
- **Severity:** nit
- **Confidence:** low
- **Locations:**
  - Home: *"read through checked accessors that serve the deposited value or throw"*
  - api/Cache (section header): *"## The checked reads"*
- **Description:** Minor vocabulary drift for the identical concept (the cache's throw-or-serve reads) between the two pages a reader is likeliest to compare. Harmless on its own but is exactly the kind of naming variance the rest of the corpus is careful to avoid.

---

## 8. `particle_velocities` names both a checked accessor and a bare struct field with no epoch check

- **Type:** clarity
- **Severity:** nit
- **Confidence:** low
- **Locations:**
  - api/Cache: *"`particle_velocities` — the checked read of the `ObservablesCache` `cache`'s particle-velocities slot"* (met first, on the Cache page)
  - api/Particles (`Tracers` Fields, met later): *"This array is the observables cache's particle-velocities slot, the same storage under two names... treat it as read-only."*
- **Description:** By the time a reader reaches Particles the collision is explicitly flagged and safely handled, so this is not a live bug — but on first meeting `particle_velocities(cache)` (Cache page), nothing yet warns that a same-named, unchecked field (`tracers.particle_velocities`) also exists and bypasses the epoch guard. Logged as a low-priority forward-reference nit, not a defect in the eventual explanation.

---

## Notes on scope

Checked and found **internally consistent** (not flagged): `energy_spectrum`'s current density-based
definition (Observables page and Notation agree; the decision-log's older per-shell description is
correctly historical); the retired "tail deposit"/"boundary" vocabulary (no live residue found outside
the decision-log entry that documents the rename); the `FlowConditions` vs `Phenomenology.FlowParameters`
disambiguation (explicitly handled at first mention); dimensional checks on `E(κ)` and `E_φ(κ)`;
the `PhaseShift` cutoff arithmetic; `recommended_cfl`'s calibration arithmetic for `IFLowStorageRK3`.
Several items already covered by `.claude/doc-review-adjudicated.md` were re-verified as still settled
(Saffman attribution, `kinetic_energy` default, `HouLi`'s shared `36`, the two DOI-link formats) and are
not repeated here.
