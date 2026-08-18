# Hat: invariants-and-decisions

Audits whether the package's own recorded invariants (CLAUDE.md's "Core invariants") and its
append-only decision log (`ARCHITECTURE.md` §11) are honoured by the current documentation surface —
including `CLAUDE.md` itself, which the panel's brief lists as one of the two authoritative "law"
documents to read.

All three findings below are of one class: `CLAUDE.md`'s own current-state prose (not the decision
log, which is append-only history and exempt per the adjudicated notes) uses names that later
decisions in `ARCHITECTURE.md` §11 explicitly retired, and that no longer exist in the rendered docs
or the source. Each is corroborated directly against `src/*.jl`.

---

## Finding 1 — `CLAUDE.md`'s `Cache` bullet uses two retired terms: "stamped" and `resolved_fields_modified!`

- **Type:** other (naming/decision-log drift)
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - `CLAUDE.md`, "Modules and wiring": *"`Cache` — the observables cache (`ObservablesCache`): the
    **stamped storage** the iteration deposits its observables into at its end (… `resolved_fields_modified!`
    announces an out-of-band state mutation)."*
- **Contradicts:**
  - `ARCHITECTURE.md` §11 decision 53: *"'Stamp' is retired; a slot carries an **epoch**… The `*_stamp`
    fields become `*_epoch`… rather than 'stamping' it."*
  - `ARCHITECTURE.md` §11 decision 30 (as corrected): *"The verb was named `resolved_fields_modified!`
    when the decision was taken; decision 24 shortened it, and the sweep updated the log to the current
    name."* The current verb is `fields_modified!`, used consistently across the rendered `Cache` API
    page, the `observables_cache.md` design page, and decision 49.
  - `src/Cache.jl`: the exported, defined verb is `fields_modified!` (line 296:
    `fields_modified!(cache::ObservablesCache) = (cache.fields_epoch += 1; cache)`); no
    `resolved_fields_modified!` exists anywhere in the source.
- **Description:** `CLAUDE.md` is one of the two documents this panel treats as authoritative "law",
  and its own description of the `Cache` module contradicts two separate later decisions (24/30 and 53)
  that are otherwise followed everywhere else in the codebase and its docs — the rendered site never
  uses "stamped" or `resolved_fields_modified!` outside the decision log's historical record (where the
  terms are correctly quoted as *what used to be said*). Decision 48/53 explicitly retire this
  vocabulary "from every surface, prose and code alike"; `CLAUDE.md` is a surface that was missed. A
  reader following `CLAUDE.md` verbatim would call a function that does not exist.
- **Resolution hint:** replace "the stamped storage" → "the epoch-dated storage", and
  `resolved_fields_modified!` → `fields_modified!`.

---

## Finding 2 — `CLAUDE.md`'s `Generator` bullet names nonexistent verbs `velocity_factor` / `scalar_factor`

- **Type:** other (naming/decision-log drift)
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - `CLAUDE.md`, "Modules and wiring": *"`Generator` — … reified as `ResolvedGenerator` … behind the
    protocol `prepare!` / `velocity_rhs!` / `scalar_rhs!` / **`velocity_factor` / `scalar_factor`** /
    `finalize!`."*
- **Contradicts:**
  - `ARCHITECTURE.md` §11 decisions 31 and 39, and the rendered `api/Generator` page, all of which name
    the pair `velocity_integrating_factor` / `scalar_integrating_factor` (decision 39: *"the `!` is gone
    — nothing is mutated"*, i.e. even the pre-decision-39 name carried `_integrating_factor`, never a
    bare `_factor`).
  - `src/Generator.jl`: exports and defines exactly `velocity_integrating_factor` /
    `scalar_integrating_factor` (lines 27, 47, 376–416); no `velocity_factor` or `scalar_factor` exists
    anywhere in the source or the rendered docs.
- **Description:** The backtick-quoted verb names in this bullet are not, and have never been, the
  package's actual identifiers — house style (the doc policy's silent-rendering rule (e), which governs
  `CLAUDE.md`'s own authored surface) reserves a backtick span for "only well-formed Julia — a name,
  type, call, or expression", so this reads as a claim about real code that is false. A reader forming a
  mental API map from `CLAUDE.md` (its stated purpose) would look for a function that has never existed.
- **Resolution hint:** `velocity_factor` / `scalar_factor` → `velocity_integrating_factor` /
  `scalar_integrating_factor`.

---

## Finding 3 — `CLAUDE.md`'s naming-convention example list gives two stale storage-field names: `cache.vorticity`, `state.velocity`

- **Type:** other (naming/decision-log drift)
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - `CLAUDE.md`, "Style" → "Naming — flow-field math variables…": *"Storage slots keep descriptive
    names — `cache.vorticity`, `generator.product_spectral`, `state.velocity`,
    `Tracers.trajectory_velocity`…"*
- **Contradicts:**
  - Rendered `api/Cache` page, `ObservablesCache` Fields: *"`velocity_physical`, `vorticity_physical` —
    the cached velocity and vorticity in physical representation"* — the field is `vorticity_physical`,
    not `vorticity`.
  - Rendered `api/State` page, `ResolvedFields` Fields: *"`velocity_spectral` — the velocity in spectral
    representation, ``\hat{\boldsymbol{u}}``"* — the field is `velocity_spectral`, not `velocity`
    (decision 26 named the field this way when `ResolvedFields` was reified, precisely to distinguish it
    from a physical-representation slot).
  - `src/Cache.jl` line 117: `const vorticity_physical::PV` (no field named plain `vorticity`).
    `src/State.jl` line 57: `velocity_spectral::UH` (no field named plain `velocity`).
- **Description:** This is the worked example for the very rule it illustrates ("storage slots keep
  descriptive names") — the rule that is supposed to prevent exactly this kind of ambiguity (is it the
  physical or spectral representation? the source or the cached copy?) is demonstrated with two field
  names that do not exist on the objects named. `generator.product_spectral` and
  `Tracers.trajectory_velocity` in the same list are correct, which makes the two wrong entries read as
  drift (pre-dating decisions 26/30/40) rather than a deliberate abbreviation.
- **Resolution hint:** `cache.vorticity` → `cache.vorticity_physical`; `state.velocity` →
  `state.velocity_spectral`.

---

## Scope note

Beyond `CLAUDE.md` itself, the rendered site (`Home`, `api`, `architecture`, `observables_cache`,
`phenomenology`, and every `api/*` module page) was cross-checked against every decision-log entry
32–56 (the post-cache-redesign era most likely to have left stale prose) for: include-order claims,
the `step!`/`deposit!` signatures, the `IntegratorBuffers`/`ParticleIntegratorBuffers` field lists, the
`Forcing` hook lifecycle, the `BandRescaling`/`Li2008`/grid-mode viscosity construction, the
`StationarityCriterion`/`run!` stopping vocabulary, the `Tracers`/`EndpointHeun`
trajectory/predictor-register naming, and the memory-footprint arithmetic in
`observables_cache.md` §1.4 (independently re-derived: 6 vector-shaped fields × 384 MiB = 2.25 GiB ≈
"about 2.3 GiB" at 256³/`Float64`, and 10 → 6 matches the four retired registers decisions 40–41 name).
None of that surface showed a violation of invariant 1–5, decision 18's extraction boundary, or
invariant 4's footprint/allocation discipline — the rendered docs track the current decision-log state
closely. The three findings above are all in `CLAUDE.md`'s own prose, which the panel brief names as
authoritative but which was not swept when decisions 24, 26, 30, 39, and 53 landed.
