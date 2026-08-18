# Doc-policy hat — findings

Hat: does each docstring obey CLAUDE.md's "Documentation policy" / "Doc-edit checklist"? Findings below are
ranked most-severe first.

---

## 1. Cache module docstring embeds formulas in its per-operation bullets

- **Type:** format (documentation policy — module docstring)
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: api / Cache, module docstring: "`max_speed` — the cached largest flow speed $\max_{\boldsymbol{x}}\lvert\boldsymbol{u}\rvert$, the number the timestep choice reads…"
  - Same block: "`particle_velocities` — the checked read of the particle velocities $\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))$, the velocity sampled along each trajectory."
- **Contradicts:** CLAUDE.md, Documentation policy: "Module docstring = map… then a **linked one-liner per operation, and no formulas**." The sibling `Generator` module docstring gets this right and even says so explicitly: "Its contents (**each formula lives in the operation's own docstring**)."
- **Description:** The module map for `Cache` is the one module docstring in the corpus that puts an explicit mathematical expression into a per-operation bullet, twice. Every other module docstring (`Generator`, `Observables`, `Forcing`, `SimulationDomain`, `Particles`, `Propagator`, `SimulationRun`, `State`, `Phenomenology`, `Spectra`, `Scalings`, `StructureFunctions`) keeps its bullets formula-free and defers the formula to the operation's own docstring, exactly as the rule and `Generator`'s explicit note prescribe. `Cache` should push these two formulas down into `max_speed`'s and `particle_velocities`' own docstrings (which already carry them) and keep the module bullet a formula-free one-liner.

---

## 2. `StationarityCriterion` names and displays the "internal" positional constructor the omission rule exists to hide

- **Type:** format (documentation policy — type docstring / constructor)
- **Severity:** major
- **Confidence:** high
- **Locations:** PAGE: api / SimulationRun, `StationarityCriterion` — Fields section: "The plain constructor `StationarityCriterion(monitor, max_turnovers, gate_scalar, elapsed_turn, last_time, started)` is internal. Note the keyword arguments above do not map one-to-one onto these fields…"
- **Contradicts:** CLAUDE.md, Documentation policy (Type docstring template): "Omit [the plain positional constructor] for a type whose positional form takes preallocated internals (`Simulation`, `ObservablesCache`, `IntegratorBuffers`, `ResolvedGenerator`): **advertising that form invites a caller to assemble machinery by hand, which the derived constructor exists to prevent**."
- **Description:** `StationarityCriterion` is exactly the case the omission rule targets — its own docstring admits the keyword constructor and the positional fields do not correspond 1:1 (`monitor` bundles five of the seven keywords). Rather than omitting the positional form, the docstring names it in full and only afterward disclaims it as "internal." This is the precise thing the rule says not to do, regardless of the caveat; a reader is still shown, verbatim, exactly the assembly-by-hand path the rule exists to prevent. Either drop the positional signature entirely (matching `Simulation`/`ObservablesCache`/`IntegratorBuffers`/`ResolvedGenerator`) or keep only the field list without spelling out the constructor call.

---

## 3. `BandRescaling` never enumerates its own keyword arguments — no `# Arguments`, no `# Fields`, and `lowest_shell`/`highest_shell` defaults go unstated

- **Type:** format (documentation policy — argument enumeration)
- **Severity:** major
- **Confidence:** medium-high
- **Locations:**
  - PAGE: api / Forcing, `BandRescaling(domain; target, over, lowest_shell = 1, highest_shell = 2)`: the whole docstring only ever says "the integer shells `lowest_shell` to `highest_shell`… are rescaled" — the defaults `1`/`2` are never stated anywhere in the docstring.
  - Contrast, same page, `Linear(domain; rate, lowest_shell = 1, highest_shell = 2)`: "`lowest_shell = 1`, `highest_shell = 2` — the forced band, as integer shells…" under an explicit `Arguments` heading.
  - Contrast, same page, `ConstantPower`: identical `Arguments` treatment of the same two keywords.
- **Contradicts:** CLAUDE.md, Doc-edit checklist item 2: "every signature argument documented — enumerated **from the signature** (positional + keyword), each its own entry, so an 'obvious' `domain` or `dt` cannot be skipped (this is how `domain` / `dt` once slipped past)."
- **Description:** `BandRescaling` shares the identical `lowest_shell`/`highest_shell` band keywords with `Linear` and `ConstantPower`, which both enumerate them (with defaults) under `# Arguments`. `BandRescaling` documents `target` and `over` in full prose paragraphs but drops the band keywords and never states their defaults, and it has neither an `Arguments` nor a `Fields` section at all — the only forcing type in the corpus missing both.

---

## 4. `VonKarman1948` / `Pao1965` re-derive the composed-spectrum formula instead of linking to `ModelSpectrum`'s home, unlike sibling `Pope2000`

- **Type:** format (documentation policy — one concept, one home)
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: api / phenomenology / Spectra, `Pope2000`: "the `ModelSpectrum` composition (**whose docstring carries the formula**) with `PopeLargeScale` supplying $f_L$…" — no formula restated.
  - Same page, `VonKarman1948`: "a preset `ModelSpectrum`… : \[E(\kappa) = C_K \varepsilon^{2/3} \kappa^{-5/3}\bigl(\ldots\bigr)^{17/6},\]" — the composed formula is fully restated with the roll-off substituted in.
  - Same page, `Pao1965`: restates the composed formula again, in the same way.
- **Contradicts:** CLAUDE.md, Documentation policy: "One concept, one home. One docstring per operation… no second copy of the formula." `ModelSpectrum`'s own docstring is explicitly the declared home for the composed formula, and `Pope2000` correctly defers to it.
- **Description:** Three sibling presets of the same `ModelSpectrum` family are treated two different ways: `Pope2000` avoids duplicating the formula and links back to `ModelSpectrum`; `VonKarman1948` and `Pao1965` both write out the fully-substituted formula again. This is an inconsistency in whether the composed-spectrum formula's "home" is honored, not merely a style choice — `scalar_integrating_factor` shows the corpus can and does avoid this kind of duplication elsewhere ("the same exponential parameters `velocity_integrating_factor` returns… with $\varkappa$ in place of $\nu$").

---

## 5. `ResolvedFields` omits naming its plain positional constructor, unlike comparably small records that name theirs

- **Type:** format (documentation policy — type docstring template)
- **Severity:** minor
- **Confidence:** low-medium
- **Locations:**
  - PAGE: api / State, `ResolvedFields(domain; scalar = false)` — Fields section lists `velocity_spectral`, `scalar_spectral` with no "The plain constructor `ResolvedFields(velocity_spectral, scalar_spectral)`…" sentence.
  - Contrast, PAGE: api / Generator, `FlowConditions` — Fields section: "The plain constructor `FlowConditions(viscosity, schmidt, velocity_forcing, scalar_forcing)` takes the four fields directly, in this order…"
- **Contradicts:** CLAUDE.md, Documentation policy: "Name the plain positional constructor only where a reader might reasonably call it — a small parameter record (`HouLi`, `FlowConditions`, `Reference`, a `Phenomenology` law)." `ResolvedFields`, with exactly two fields (one nullable), reads as the same class of small record as `FlowConditions`, yet its plain constructor is left unnamed while `FlowConditions`'s is spelled out.
- **Description:** Given only two fields, no coordinated invariant analogous to `Tracers`' `positions`/`position_points` pairing is at stake here, so the case for omission (as for `Simulation`/`ObservablesCache`/`IntegratorBuffers`/`ResolvedGenerator`) is weaker than for those machinery types; the omission reads as inconsistent with `FlowConditions`'s treatment rather than a deliberate application of the omission rule. Flagged at lower confidence since the two conventions (name it / fold into Fields only) both appear elsewhere in the corpus and the line is a judgment call.

---

## 6. `Simulation`'s docstring likely re-links several targets more than once (unverifiable from the plain-text render, flagged for a source check)

- **Type:** other (documentation policy — cross-reference discipline)
- **Severity:** minor
- **Confidence:** low
- **Locations:** PAGE: api / SimulationRun, `Simulation` type docstring: `FixedDomain`, `IntegratorBuffers`, `ResolvedGenerator`, and `ObservablesCache` each appear by name in the opening identity sentence ("the `FixedDomain`, the `IntegratorBuffers`, the `ResolvedGenerator`…, the `ObservablesCache` holding…") **and again** in the `# Fields` section ("`domain`, `buffers`, `generator`, `scheme` — the `FixedDomain`, `IntegratorBuffers`, the `ResolvedGenerator`…").
- **Contradicts:** CLAUDE.md, Documentation policy: "link a target **at most once per docstring** — its first genuine mention."
- **Description:** The manuscript's reader-text extraction does not preserve which backticked mentions are `@ref` links versus plain code spans, so this cannot be confirmed as an actual double-link from this document alone. But the shape is exactly what the rule warns against — four major cross-module types each named twice in one docstring — and it is the single largest, most cross-reference-dense docstring in the corpus, making it the most likely place for the "at most once" rule to have been missed. Worth a source check (does the `# Fields` mention re-`@ref`, or is it a bare, unlinked backtick as the rule allows for a second occurrence?).
