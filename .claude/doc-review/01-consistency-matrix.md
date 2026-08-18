# Consistency Matrix — fresh-eyed cross-page audit

Hat: **consistency-matrix** (systematic entity/claim diff across every page of the rendered manuscript)

Method: built a running matrix of every recurring physical quantity, numerical constant, module-dependency
claim, and cross-referenced code-object name across Home, API overview, `architecture`, `notation`,
`observables_cache`, `phenomenology` (+ Spectra/StructureFunctions/Scalings), and every per-module API page;
diffed each entity's stated value/definition/status pairwise. Most of the corpus (formulas, transform-count
ledgers, byte-size figures, module include order, nav/section-heading cross-references, RK coefficients,
dealiasing cutoff constants) checked out internally consistent under independent re-derivation — this
report lists only the genuine divergences found, not the (much larger) set of checks that passed.

---

## Finding 1 — `GBGStreamingStatistics` is called a current architectural consumer in §1, but the actual bridge to it is stated deferred in §4.9

- **Type:** contradiction
- **Severity:** major
- **Confidence:** medium
- **Locations:**
  - PAGE: architecture, §1 Identity — *"It is a library of composable pieces with a thin ergonomic run layer on top, built as a consumer of `GBGPeriodicFields` (the field and spectral machinery) and `GBGStreamingStatistics` (the statistics)."*
  - PAGE: architecture, §4.9 Layout summary — *"a statistics bridge that streams them to `GBGStreamingStatistics` is deferred (§7)"*
- **Contradicts:** §1 states, in present tense and as a foundational architectural fact, that the package is "built as a consumer of ... `GBGStreamingStatistics`"; §4.9 (and §7's deferred-capabilities list, and the Home/API-overview pages' "accumulating statistics ... is the caller's own analysis") state that the actual code path which would make IT a consumer of SS does not exist yet.
- **Description:** A fresh reader of §1 comes away believing GBGStreamingStatistics is already wired into the package on the same footing as `GBGPeriodicFields`. Nothing in §1 flags that this is aspirational. Only much later (§4.9, and the deferred-capabilities §7) does the reader learn the SS bridge is not built. This is not the adjudicated "absence of a statistics layer" finding (that one is about flagging the *absence itself* as a gap, which is out of scope) — this is about §1's wording actively overclaiming a *current* dependency relationship that §4.9 explicitly contradicts.

---

## Finding 2 — `deposit_sample!` is named as something a user must call, but is unnamed in its sibling docstring and absent from the API index

- **Type:** contradiction
- **Severity:** major
- **Confidence:** medium
- **Locations:**
  - PAGE: api / Cache, `particles_modified!` docstring — *"A hand-run loop that repositions tracers itself must call this, then `record_trajectory_velocity!` to write the new values, and finally `deposit_sample!` to record them at the current epochs"*
  - PAGE: api / Particles, `record_trajectory_velocity!` docstring — describes the very same second step only as *"a second call the cache owns"* — never naming it.
  - PAGE: api / GBGIsotropicTurbulence, the full `## Index` (lines listing every `Cache.*` and `Particles.*` export) — contains no `deposit_sample!` entry anywhere.
- **Contradicts:** One docstring names the operation a hand-run-loop author must call (`deposit_sample!`); its sibling docstring, describing the exact same operation, declines to name it at all; and the function does not appear in the package's own public index. A reader who tries to follow the `particles_modified!` docstring's explicit instructions has no way to locate `deposit_sample!` from the API pages.
- **Description:** Either `deposit_sample!` is a real, callable verb that should be indexed (and its sibling docstring should name it too), or it is a stale/renamed reference left over from an earlier vocabulary sweep (cf. the `check_boundary` → `check_deposits`, `tail` → `closing` renames recorded in the decision log) and the docstring text was not updated. As written, a reader cannot resolve the reference either way.

---

## Finding 3 — `StationarityCriterion`'s `skew_floor` guidance disagrees with the architecture decision log on where to raise it

- **Type:** contradiction
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: architecture, §11 decision log (2026-07, `warmup!` stationarity entry) — *"whose default floor is a permissive one to be raised toward the developed $\lvert S\rvert \approx 0.5$ when the run must be strict"*
  - PAGE: api / SimulationRun, `StationarityCriterion` docstring — *"Raise it toward `0.4` when the run's statistics depend on the cascade being mature."*
- **Contradicts:** The architecture doc's stated destination for a stricter skewness gate is "toward ≈0.5" (the fully developed value); the API docstring's concrete practical recommendation is "toward 0.4" — a different number for the same tuning action, on the same parameter.
- **Description:** A reader who reads the architecture rationale first and then goes to configure `skew_floor` for a "strict" run gets two different target numbers for the same intent. Minor because both readings agree 0.4 is "closer to 0.5 than the 0.1 default," but the two pages do not actually agree on the recommended value.

---

## Finding 4 — `HouLi`'s `order` default (36) coincides exactly with the unrelated Float64 `strength` auto-value (also ≈36)

- **Type:** other
- **Severity:** nit
- **Confidence:** low
- **Locations:**
  - PAGE: api / SimulationDomain, `HouLi` — signature shown as `HouLi(; order = 36, strength = nothing)`
  - Same docstring — *"`strength` is chosen for the domain's element type as $-\log$ of its machine epsilon — $\approx 36$ for `Float64`, $\approx 16$ for `Float32`"*
- **Contradicts:** N/A (not a stated contradiction — a suspicious numeric coincidence worth a second pair of eyes).
- **Description:** `order` (the roll-off sharpness exponent) and `strength`'s Float64 auto-value (the Nyquist damping magnitude, a derived quantity) are conceptually unrelated parameters, yet the docstring's literal default for `order` is the same number (36) as the auto-derived `strength` for double precision. This may be a deliberate, independently-motivated literature convention (order≈36 is a common Hou–Li exponent choice in spectral codes) — flagged as low-confidence because I cannot rule out a copy/paste leak from one default into the other without seeing the source.

---

## Finding 5 — `ParticleIntegratorBuffers.predictor_velocity` is called "not readable" / "never exposed," yet is documented as an ordinary public struct field

- **Type:** contradiction
- **Severity:** nit
- **Confidence:** low
- **Locations:**
  - PAGE: architecture, §4.6 — *"`ParticleIntegratorBuffers.predictor_velocity` is a stage register of the scheme, never a sample of the flow, and is not readable."*
  - PAGE: api / Particles, `ParticleIntegratorBuffers` Fields section — *"`predictor_velocity` — the velocity interpolated at the predicted positions: an intermediate value the scheme works with, never a sample of the flow, and never exposed as one."*
- **Contradicts:** Both passages assert the value is inaccessible/"not readable"/"never exposed," yet the second passage is itself a `# Fields` entry documenting `predictor_velocity` as a plain, dot-accessible field of a public type (`buffers.predictor_velocity` works in Julia like any other field). Nothing marks it `#`-internal or otherwise structurally hidden.
- **Description:** Low confidence because this may simply be the package's established convention (per its own doc policy, a demoted `# Fields` section documents internals as reference detail even when a checked accessor is the sanctioned read path elsewhere, e.g. `ObservablesCache`'s "treat every returned array as read-only" caveat for a technically-public field). Flagged because the specific wording ("not readable," "never exposed") reads as a stronger claim than "discouraged" and is worth a second look against the actual export list.
