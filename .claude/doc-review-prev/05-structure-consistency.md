# Documentation-structure audit — hat: structure-consistency

## Inferred template

**Function docstring** (the modal shape across `Observables`, `Generator`, `Cache`, `Forcing` methods,
`Phenomenology` evaluators): (1) one identity sentence that usually *embeds* the physical formula
inline (`kinetic_energy`, `dissipation`, `max_speed`, `kolmogorov_length`, …) rather than deferring the
formula to the end; (2) for a multi-signature function, an explanation of the extra call forms, given
as inline "The second form…"/"The third form…" prose in the large majority of cases; (3) caveats as a
`Note`/`Warning` admonition; (4) for a named/published method, an "(Author Year)" citation placed
*inside the identity sentence itself*, near the front, in the majority of instances.

**Type docstring** (constructor-first): (1) identity sentence; (2) constructor + argument explanation —
either flowing prose, or (in a minority of cases) a separate bulleted list; (3) an example, only for a
few complex constructors; (4) a demoted `Fields` section, usually a flat bullet list, sometimes preceded
by "The plain constructor `X(a, b)` takes the field(s) directly:".

**Module docstring** ("map"): an identity paragraph, then a bulleted, formula-free, one-liner-per-
operation contents list, whose bullet order matches the physical order of the page's own `##`
subsections in 7 of 9 `api/*` module pages.

Below are the outliers against these inferred norms.

---

### Finding 1 — Three different shapes for "enumerate each constructor argument"
- **Type**: organization
- **Severity**: major
- **Confidence**: high
- **Locations**:
  - PAGE: api / SimulationDomain, `FixedDomain`: `"Arguments\nAll keyword, all required:"` then a bulleted list.
  - PAGE: api / SimulationRun, `Simulation`: `"Keywords\nThe keywords marked (front door only) configure the FixedDomain..."` then a bulleted list.
  - PAGE: api / SimulationRun, `StationarityCriterion`: bullets (`gate_scalar`, `gate_skewness`, …) begin immediately after "…gives up with a warning at `max_turnovers`." — no heading word at all.
  - PAGE: api / Generator, `FlowConditions`: no bulleted argument list at all — "Every argument is required." is the only structural marker; each argument is explained purely in the identity sentence's parentheticals.
- **Contradicts**: same conceptual section (per-argument enumeration of a multi-keyword constructor) rendered four different ways: headed "Arguments", headed "Keywords", unheaded bullets, and prose-only.
- **Description**: A reader learning the corpus's convention for "where do I find what each keyword does" gets four different answers depending which type they open, with no signal (all four types have 4–9 keywords, comparable complexity) for why the shape differs.

### Finding 2 — Named-method citation placement: front-loaded in the majority, deferred to the tail in a minority
- **Type**: organization
- **Severity**: major
- **Confidence**: high
- **Locations**:
  - Front-loaded (citation inside the opening identity sentence): PAGE: api / Propagator, `IFLowStorageRK3`: `"Integrating-factor third-order low-storage Runge–Kutta (Williamson 1980, 2N-storage)."`; PAGE: api / SimulationDomain, `PhaseShift`: `"Phase-shift dealiasing (Patterson & Orszag 1971; ... Rogallo 1981):"`; PAGE: api / phenomenology / Spectra, `VonKarmanLarge`/`PopeLargeScale` cite `(von Kármán 1948)`/`(Pope 2000)` at the end of their own (short) identity paragraph, not deferred to a later section.
  - Deferred to the closing sentence, after the formula and behavioral discussion: PAGE: api / SimulationDomain, `HouLi`: the filter's own eponymous citation `"The smooth spectral filter is due to Hou & Li (2007)."` is the *last* sentence, after the formula, the `order`/`strength` explanation, and three behavioral remarks.
  - PAGE: api / phenomenology / StructureFunctions, `Lundgren2002`: the identity sentence never names "Lundgren" — the citation `(Lundgren 2002; Sagaut & Cambon 2018, Table 4.5)` only appears in the closing clause.
  - PAGE: api / phenomenology / Spectra, `ObukhovCorrsin1949`: identity sentence names neither Obukhov nor Corrsin; `"The name is a dual eponym — Obukhov (1949) and Corrsin ... (1951)"` is the final sentence of the docstring.
- **Contradicts**: `IFLowStorageRK3`/`PhaseShift`/`Pope2000`/`VonKarman1948`/`Pao1965`/`Kolmogorov1941`/`SheLeveque1994`/`Yaglom1949` all name their author-year in the very first clause; `HouLi`/`Lundgren2002`/`ObukhovCorrsin1949` — equally eponymous types — hold the same fact back to the closing sentence.
- **Description**: The corpus has no single rule for where a type's own provenance citation sits; roughly 10 instances front-load it and 3 defer it to the very end, with no apparent reason (all four are "named after the paper" types).

### Finding 3 — Module-docstring "map" bullet order does not track the page's physical section order (Cache, Particles)
- **Type**: organization
- **Severity**: major
- **Confidence**: high
- **Locations**:
  - PAGE: api / Cache module docstring lists `resolved_fields_modified!` **last** of five bullets, after `particle_velocities`; but on the same page it is documented **second**, immediately after `ObservablesCache`, under `## The observables cache` — before `## The checked reads` (`velocity_physical`, `vorticity_physical`, `scalar_physical`, `particle_velocities`) even begins.
  - PAGE: api / Particles module docstring lists `particle_positions`, `number_of_tracers` **last** of five bullets, after `sample!`; but on the page they are documented **second and third**, directly under `## The tracer set` right after `Tracers`, before `## The tracking loop` (`record_trajectory_velocity!`, `advect!`, `sample!`) begins.
- **Contradicts**: every other `api/*` module page (`Generator`, `Observables`, `Propagator`, `SimulationDomain`, `State`, `SimulationRun`) has a map bullet order that matches its own page's `##` subsection order exactly.
- **Description**: A reader using the module docstring as a table of contents will be misled about where two operations actually sit on the page, in exactly these two modules.

### Finding 4 — Two documented, page-headed operations are absent from their own module's contents map
- **Type**: organization
- **Severity**: major
- **Confidence**: high
- **Locations**:
  - PAGE: api / Forcing module docstring's bulleted contents list never names `DeferredForcing`, even though the page carries a full `## Deferred forcing` subsection with its own `DeferredForcing` — Type entry (only reached via a trailing, unbulleted sentence: "An operator-free keyword constructor (…) returns a `DeferredForcing`…").
  - PAGE: api / phenomenology / Scalings module docstring's bulleted contents list (`ScalingLaw`, `Sreenivasan1998`, `Sreenivasan1995`, `Li2008`) never names `stationary_dissipation`, even though the page carries a full `## Predicting dissipation` subsection documenting it.
- **Contradicts**: every other module bullet-list names every subtype and function the page documents (e.g. `Generator`'s map explicitly lists `prepare!`, `velocity_rhs!`, `scalar_rhs!`, `velocity_factor`, `scalar_factor`, `finalize!` — all six protocol verbs it hosts).
- **Description**: The "map = every operation gets a linked one-liner" convention is broken twice, both times for a function that is arguably a secondary/derived operation on its page — but the corpus gives no other module an exemption of this kind.

### Finding 5 — "The plain constructor … takes the field(s) directly" preamble: present on some `Fields` sections, absent on most
- **Type**: format
- **Severity**: moderate
- **Confidence**: high
- **Locations**:
  - Present: PAGE: api / SimulationDomain, `HouLi`: `"The plain constructor HouLi(order, strength) takes the two fields directly:"`; PAGE: api / phenomenology / Phenomenology, `Reference`: same phrasing; PAGE: api / phenomenology / StructureFunctions, `Kolmogorov1941`/`Kolmogorov1962`; PAGE: api / phenomenology / Scalings, `Li2008`/`Sreenivasan1998`/`Sreenivasan1995`; PAGE: api / SimulationRun, `StationarityCriterion` (worded "…is internal:").
  - Absent (straight into bullets): PAGE: api / Cache, `ObservablesCache`; PAGE: api / Forcing, `DeferredForcing`; PAGE: api / Generator, `FlowConditions`, `ResolvedGenerator`; PAGE: api / Particles, `Tracers`; PAGE: api / SimulationRun, `Simulation`; PAGE: api / phenomenology / Spectra, `PopeLargeScale`, `PopeDissipation`, `VonKarmanLarge`, `PaoDissipation`, `ExponentialDissipation`, `ObukhovCorrsin1949`, `ModelSpectrum`.
- **Contradicts**: roughly 8 type docstrings frame their `Fields` list with the plain-constructor sentence; roughly 14 others (including the two most-used front-door types, `Simulation` and `ObservablesCache`) omit it entirely.
- **Description**: Since "the plain positional constructor" is exactly what the `Fields` section is supposed to document per the corpus's own stated pattern, its presence should be uniform; instead it correlates with no obvious property (short vs. long field lists both appear on either side).

### Finding 6 — `StationarityCriterion`'s two field-like lists enumerate different, mismatched sets
- **Type**: organization
- **Severity**: moderate
- **Confidence**: high
- **Locations**: PAGE: api / SimulationRun, `StationarityCriterion`. The unheaded keyword-argument bullets are `gate_scalar`, `gate_skewness`, `min_turnovers`, `window_turnovers`, `tol`, `skew_floor`, `max_turnovers` (7 items). The subsequent `Fields` section lists `monitor`, `max_turnovers`, `gate_scalar`, `elapsed_turn`, `last_time`, `started` (6 items) — most of the keyword arguments (`gate_skewness`, `min_turnovers`, `window_turnovers`, `tol`, `skew_floor`) simply do not appear; they have collapsed into the opaque `monitor` field.
- **Contradicts**: every other type whose constructor keywords and `Fields` co-exist (`FlowConditions`, `ResolvedGenerator`, `ObservablesCache`) keeps the two in a 1:1 correspondence — the `Fields` section either *is* the argument list, or directly mirrors it by name.
- **Description**: A reader who reads the bulleted keyword list, then the `Fields` list right below it, sees two structurally similar-looking bulleted enumerations that silently describe different things — a shape unique to this one type.

### Finding 7 — `IntegratorBuffers` is the only `Fields` section broken into sub-headings rather than one flat list
- **Type**: format
- **Severity**: minor
- **Confidence**: high
- **Locations**: PAGE: api / Propagator, `IntegratorBuffers`: `"Fields\nShared — every scheme allocates this:\n\n- stage1 ...\nScheme-specific — allocated only for the scheme that uses it, else nothing:\n\n- nonlinear ...\nNested:\n\n- scalar ..."`.
- **Contradicts**: every other multi-field type with comparable or greater field count (`ObservablesCache` — 8 fields, `Simulation` — 8 fields, `Tracers` — 6 fields, `FixedDomain` — 6 fields) presents its `Fields` list as one undivided flat bullet list.
- **Description**: The three-way grouping (Shared/Scheme-specific/Nested) is informative given the content, but it is a one-off deviation from the corpus's otherwise universal flat-list `Fields` shape.

### Finding 8 — `Phenomenology`'s standing in the "Components" map differs between the Home page and the `api` overview page
- **Type**: organization
- **Severity**: minor
- **Confidence**: medium
- **Locations**:
  - PAGE: Home, `## Components`: `Phenomenology` gets its own full bullet — `"Phenomenology: the reference turbulence laws — model spectra, structure-function laws, and scaling constants — to validate a run against. A separate, opt-in group..."` — a peer of `SimulationDomain`, `State`, etc.
  - PAGE: api, `## API overview`: the identical content is folded into the *tail* of the `SimulationRun` bullet instead: `"...validate_spectrum. The reference turbulence laws (...) live in a separate, opt-in Phenomenology group..."`, with no bullet of its own.
- **Contradicts**: the two pages otherwise describe the same nine-module set with matching per-module bullets; only `Phenomenology` shifts from a first-class entry (Home) to a subordinate clause (api overview).
- **Description**: Two pages doing the same "one paragraph per module" job disagree on whether `Phenomenology` is a peer module or an appendage of `SimulationRun`.

### Finding 9 — `dissipation`'s multi-signature explanation uses a bulleted "routes" list; every sibling multi-signature function uses inline prose instead
- **Type**: organization
- **Severity**: minor
- **Confidence**: medium
- **Locations**: PAGE: api / Observables, `dissipation`: `"Two routes to the same rate; take the one whose input is already in hand.\n\n- dissipation(ω, viscosity) — ...\n- dissipation(û, domain, viscosity) — ..."`.
- **Contradicts**: PAGE: api / Cache, `velocity_physical`/`vorticity_physical`/`scalar_physical`/`particle_velocities`, and PAGE: api / Observables, `max_speed`, and PAGE: api / Particles, `particle_positions`, and PAGE: api / Propagator, `deposit!` all explain their second/third call forms with an inline sentence ("The second form reads…", "The third form reads…") rather than a bulleted list.
- **Description**: `dissipation` is the one multi-signature function in the corpus that promotes its variant forms to their own bullets; every other such function keeps them as a trailing prose sentence.

### Finding 10 — `Examples` heading used on some complex constructors, absent from others of comparable complexity
- **Type**: organization
- **Severity**: minor
- **Confidence**: medium
- **Locations**: PAGE: api / SimulationRun, `Simulation` carries a full `Examples` section with three worked code blocks; PAGE: api / SimulationRun, `run!` carries its own `Examples` section with three code blocks.
- **Contradicts**: PAGE: api / Particles, `Tracers` (two distinct constructor forms — seeded-random vs. given-positions — exactly the kind of "non-obvious construction" the corpus's own stated policy earmarks for an example) has no `Examples` section; PAGE: api / SimulationDomain, `FixedDomain` and PAGE: api / phenomenology / Phenomenology, `FlowParameters` likewise have no `Examples` heading despite comparably multi-keyword constructors.
- **Description**: Only two docstrings in the whole corpus use a headed `Examples` section; several other constructors with equally non-obvious argument combinations show no worked example at all (or only an inline, unheaded snippet embedded in prose, as on the `Phenomenology` module page).

### Finding 11 — `Scalings` module docstring embeds full formulas in two of its three per-law bullets, contrary to the corpus's formula-free "map" bullets everywhere else
- **Type**: format
- **Severity**: moderate
- **Confidence**: medium
- **Locations**: PAGE: api / phenomenology / Scalings module docstring: `"- Sreenivasan1998 — the normalized dissipation constant C_ε = εL₁₁/u'³ (...), a high-Reynolds-number plateau..."` and `"- Li2008 — the box-normalized dissipation group k/(Lε)^{2/3}, which (inverted, via stationary_dissipation) predicts..."`; by contrast the third bullet in the same list, `"- Sreenivasan1995 — the (three-dimensional) Kolmogorov constant C_K of the inertial-range spectrum."`, names its symbol without a formula.
- **Contradicts**: every other module-docstring contents bullet in the corpus (`Cache`, `Generator`, `Observables`, `Forcing`, `Propagator`, `SimulationDomain`, `State`, `SimulationRun`, top-level `Phenomenology`) names the operation and its symbol without writing out the formula in the bullet itself — formulas are reserved for the operation's own docstring.
- **Description**: Two of three bullets on this one page break the map/formula separation the rest of the corpus holds to, and inconsistently so even within the same three-item list (the third bullet stays formula-free).

### Finding 12 — `FlowConditions` documents no `Examples`/constructor-arity contrast even though its sibling `ResolvedGenerator` and `ObservablesCache` both spell out "Build it on `domain`..." guidance; and `FlowConditions` skips the argument-bullet step other >2-argument constructors use
- **Type**: organization
- **Severity**: nit
- **Confidence**: low
- **Locations**: PAGE: api / Generator, `FlowConditions(; viscosity, schmidt, velocity_forcing, scalar_forcing)` — four keyword arguments explained purely inside one identity sentence's parenthetical asides, with no bulleted breakdown (contrast with `Finding 1`'s `FixedDomain`/`Simulation`, which bullet a similar or smaller argument count).
- **Contradicts**: see Finding 1 — restated narrowly to flag `FlowConditions` specifically as the only *four*-keyword constructor in the corpus using pure-prose argument description with no bulleted list at all (`StationarityCriterion`, at 7 keywords, at least gets an unheaded bulleted list).
- **Description**: A minor, low-confidence corollary of Finding 1 — noted separately because it is the most extreme point on the "prose vs. bullets" spectrum (zero bullets for four keywords).
