# Style-editor hat — findings

Fresh-eyed technical copy-edit pass for internal uniformity (notation rendering, docstring
skeleton, headings/tables/citations, register/voice, grammar) plus a raw-HTML check for silent
rendering failures. Findings ranked most-severe first.

---

## Finding 1 — `record_trajectory_velocity!`'s call order is described two contradictory ways on the same page

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: `api / Particles`, "## The tracking loop" section intro: *"put the start-of-step velocity
  on record along the trajectories, advance the tracers with second-order Heun-in-time advection
  once the fields have moved... The push is two verbs because the run holds a single physical
  velocity field, so the start-of-step values are taken off it **before the state advances**."*
- PAGE: `api / Particles`, `record_trajectory_velocity!` docstring, same page: *"The run layer
  calls it **at the end of each iteration**, on the **just-deposited** velocity at the
  just-advanced positions... and the next iteration's `advect!` reads them as the first half of
  its Heun pair."*
- Corroborated by `advect!`'s own Note on the same page: *"recorded by `record_trajectory_velocity!`
  **at the previous iteration's end**."*

**Contradicts:** the section-intro prose (call it *before* the step, off the about-to-be-overwritten
single velocity register) versus the function's own docstring and the `advect!` Note (call it
*after* the closing deposit, at the iteration's end, on the just-deposited velocity) — an axis of
**when** the call happens and **which** velocity it reads.

**Description:** This reads as the pre-2026-08 mechanism (before the observables-cache redesign,
when the tracer push recorded the sample off the single physical velocity buffer immediately
before `step!` overwrote it). The decision log's 2026-08 "trajectory sample is a cache slot" entry
explicitly moved the record call to the iteration's end, using the deposited velocity. The section
intro was not updated to match and now misdescribes the current schedule to a reader who has not
also read the decision log.

---

## Finding 2 — `derivative_skewness` formula uses a bare `$C$` where the constant is named `$C_S$` in the same sentence

**Type:** typesetting
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: `architecture`, §4.3 Observables: *"computed coordinate-free as the normalized third
  invariant of the strain rate $\boldsymbol S$, $3C\langle\det\boldsymbol S\rangle/\langle
  \boldsymbol S:\boldsymbol S\rangle^{3/2}$ with the exact isotropy constant
  $C_S = \tfrac{4}{7}\sqrt{15/2}$"* (verified in the built HTML, not a manuscript-extraction
  artifact).
- Contrast PAGE: `notation`, Numerics table: *"the derivative-skewness isotropy constant wears the
  subscripted $C_S$"*.
- Contrast PAGE: `api / Observables`, `derivative_skewness`: formula correctly uses `$C_S$`
  throughout, $S = C_S\langle\operatorname{tr}\boldsymbol S^3\rangle/\dots = 3C_S\langle\det
  \boldsymbol S\rangle/\dots$.

**Contradicts:** the bare `$C$` in the ARCHITECTURE.md formula against the `$C_S$` that names the
"exact isotropy constant" in the very same sentence, and against notation.md's explicit rule that
this constant is always subscripted.

**Description:** A one-symbol slip in the design document's summary of an operation whose own
docstring gets it right — but ARCHITECTURE.md is the spec readers are told to consult first, so the
inconsistency is visible exactly where a reader is most likely to compare formula against symbol.

---

## Finding 3 — Home page uses "the instant between steps"; the corpus's settled vocabulary is "between iterations"

**Type:** language-tone
**Severity:** minor
**Confidence:** high

**Locations:**
- PAGE: `Home`, quick-start snippet comment: *"velocity_physical(sim) # a cached observable at the
  iteration's end (the instant **between steps**)"*.
- Contrast the corpus-wide settled term, e.g. PAGE: `architecture` decision log (2026-08): *"the
  instant between iterations is named plainly — **between iterations**, the iteration's end, the
  instant $t_n$"*; PAGE: `observables_cache`, §1.1: *"between iterations the observation... sits."*

**Description:** ARCHITECTURE.md §4.9/§1.1 of the cache design page draw a careful distinction — a
"step" is strictly contained inside an "iteration" (which also includes the particle push and the
deposits) — and a whole decision-log entry retires informal/ambiguous phrasing for precisely this
instant in favor of "between iterations." The one Home-page comment is the sole remaining spot
using the narrower, retired-in-spirit "between steps."

---

## Finding 4 — Citation-list format differs between `ARCHITECTURE.md` and the `Phenomenology` submodule pages

**Type:** citation
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: `architecture`, `## References`: *"Kolmogorov, A. N. (1941). The local structure of
  turbulence in incompressible viscous fluid for very large Reynolds numbers. Dokl. Akad. Nauk
  SSSR 30, 301–305."* (initials, full title, journal, volume, en-dash page range).
- PAGE: `api / phenomenology / StructureFunctions`, `## References`: *"Kolmogorov (1941), Dokl.
  Akad. Nauk SSSR 30, 301"* (no initials, no title, single page number).
- Same short form repeated on `api / phenomenology / Scalings` and `api / phenomenology / Spectra`.

**Description:** The same author/year is cited in both bibliographic registers with visibly
different formatting conventions. `Phenomenology`'s exemption from *duplicating* the architecture
reference list is explicit and reasonable (the "extraction-bound leaf" carries its own citations),
but nothing calls for the *format* itself to differ; a reader jumping between the two reference
blocks sees two house styles for the same kind of entry.

---

## Finding 5 — Inconsistent "(front door …)" annotation in `Simulation`'s Keywords list

**Type:** format
**Severity:** nit
**Confidence:** high

**Locations:**
- PAGE: `api / SimulationRun`, `Simulation` Keywords: `grid_points_per_axis` — *"(front door
  only); required."*; `side_length` — *"(front door only)."*; `dealiasing` — *"(front door
  only)."*
- Same list: `element_type = Float64`, `array_type = Array` — *"the real element type and storage
  backend **(front door)**."* (missing "only").

**Description:** Three of the four front-door-scoped keyword entries in this bulleted list say
"(front door only)"; the `element_type`/`array_type` entry drops "only" for no apparent reason,
reading as a stray inconsistency in an otherwise uniform annotation scheme within the same list.

---

## Finding 6 — A decision-log sentence opens with a lowercase code identifier

**Type:** language-tone
**Severity:** nit
**Confidence:** medium

**Locations:**
- PAGE: `architecture`, decision log (2026-08, "The chart recoveries are not package verbs..."):
  *"...is an observable. `velocity_to_physical!` and `scalar_to_physical!` are deleted: each was
  the same two lines..."*

**Description:** CLAUDE.md's house rule: "A prose sentence never opens with a lowercase code
identifier... (bulleted `arg` entries and signatures are exempt)." This is a full decision-log
narrative sentence, not a bulleted argument entry, so the exemption does not obviously apply; the
sentence begins directly with the lowercase-initial identifier `velocity_to_physical!`. A very
minor, single-instance slip against an otherwise consistently observed rule (checked across the
whole corpus; this was the only continuous-prose instance found).

---

## Finding 7 — `StationarityCriterion`'s Fields section documents `gate_scalar` individually but folds every other gate/tolerance keyword into one `monitor` bullet

**Type:** organization
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: `api / SimulationRun`, `StationarityCriterion` constructor:
  `(; gate_scalar = true, gate_skewness = true, min_turnovers = 5, window_turnovers = 4, tol =
  0.05, skew_floor = 0.1, max_turnovers = 60)`.
- Same docstring's `Fields` list: `monitor` — *"the sampled signals and gates."*; `max_turnovers`
  — its own bullet; **`gate_scalar`** — its own bullet ("the requested scalar gate..."); then
  `elapsed_turn`, `last_time`, `started` bundled together.

**Description:** `gate_scalar` and `gate_skewness` are introduced as parallel sibling keywords in
the main prose (both described as gates with the same "also require..." phrasing), yet only
`gate_scalar` gets a named `Fields` entry; `gate_skewness`, `min_turnovers`, `window_turnovers`,
`tol`, and `skew_floor` are all silently absorbed into the single `monitor` bullet with no
individual field named. The asymmetry between the two gate keywords is the sharpest instance — a
reader who trusts the Fields list to enumerate storage 1:1 with keywords cannot tell where
`gate_skewness` lives.

---

## Notes on checks that came back clean

- The pipe-delimited "tables" and the admonition-title-glued-to-body ("NoteThis is...",
  "WarningConstruct...", "ProvisionalHow...", "Work in progressThe package...") patterns seen
  throughout the manuscript were verified against the built HTML (`docs/build/notation/index.html`,
  `docs/build/index.html`) and render correctly as real `<table>` elements and Documenter
  admonitions with a separated title/body — these are artifacts of the plain-text manuscript
  extraction, not rendering defects, consistent with the adjudicated-file precedent for the same
  class of artifact.
- Cross-checked the observables_cache.md transform-count table (§2.3) against the compute-audit
  decision-log numbers by re-deriving the scalar-flux vector-transform accounting by hand; both
  the `TwoThirds`/`HouLi` and `PhaseShift` rows check out exactly (no defect).
- Checked notation (bold-italic vectors, upright `\mathrm i`, subscripted `\partial_{x_i}`,
  `\varphi` never `\theta`, the `\boldsymbol\kappa`/`\kappa`/`k`/`\varkappa` glyph set) across every
  page — no violations found outside Finding 2.
- Checked for stale renamed terms (`trajectory_sample`, `tracer_positions`, `tracer_velocities`,
  "tail deposit", "boundary velocity/observables") — none found outside the decision-log entries
  that are explicitly recording the old names (exempt, per the adjudicated file).
- `Fields` sections render uniformly as `<p><strong>Fields</strong></p>` (bold paragraph, not a
  heading) on every API page checked (Cache, Generator, SimulationRun, State, Particles,
  Propagator, and all four Phenomenology pages) — no heading-level drift found.
