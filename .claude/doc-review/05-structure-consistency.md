# Documentation-structure audit — hat: structure-consistency

## Inferred template

**Function docstring** (the `f` / `f!` home carries all of this; the wrapper only links):
1. Identity sentence — what it computes, in the user's terms, often binding `code` ≡ symbol.
2. When to use it / vs. the alternative method or route (where more than one exists).
3. Each argument's effect, given **inline in prose** (never a bulleted `## Arguments` — that
   shape is reserved for types) — confirmed corpus-wide: no function docstring in this manuscript
   uses a bulleted arguments list.
4. Caveats, as one or more titled `!!! note`/`!!! warning` admonitions (rendered here as a title
   glued to its first body word), the **last** substantive block before `source`.
5. The physical-meaning-first formula.
6. A named-method citation, which may open the identity sentence.
7. A terminal **"Returns `x`."** sentence *only* when the signature carries no `-> Type` arrow;
   an arrow and the sentence are the two sanctioned, mutually exclusive shapes.

**Type docstring** (constructor-first):
1. Identity sentence.
2. Constructor code block + prose.
3. `## Arguments` (bulleted) when keywords are independent settings, folded into prose for one
   coherent object.
4. `## Examples` where construction is non-obvious.
5. A trailing caveat admonition, last before `## Fields`.
6. `## Fields` (demoted), naming the plain positional constructor only for a small parameter
   record a reader might reasonably call directly.

**Module docstring**: identity → contents list (linked one-liner per operation) → *one* optional
trailing remark.

Below are the entries that break shape or order against this inferred template.

---

## Finding 1

- **Type**: organization
- **Severity**: major
- **Confidence**: high
- **Locations**:
  - PAGE: api / Cache, `ObservablesCache` — Fields block reads "`velocity_physical`,
    `vorticity_physical` — the cached velocity and vorticity..." then, mid-list, "Two kinds of
    field share the word: the two counters below tick as the state changes..." then resumes with
    "`velocity_epoch`, `vorticity_epoch`, ...".
- **Contradicts**: every other type's `## Fields` section in the corpus (`ResolvedFields`,
  `FlowConditions`, `FixedDomain`, `Tracers`, `IntegratorBuffers`, `ResolvedGenerator`,
  `ModelSpectrum`, `Reference`, …) is a single, uninterrupted bulleted list.
- **Description**: `ObservablesCache` is the only type docstring in the corpus whose demoted
  `# Fields` section is split into two bullet lists by an intervening paragraph of narrative
  prose. Every peer type keeps Fields as one unbroken list; the epoch-explanation paragraph reads
  as a stray caveat admonition that should sit before `# Fields`, not inside it.

## Finding 2

- **Type**: organization
- **Severity**: major
- **Confidence**: high
- **Locations**:
  - PAGE: api / Forcing, `BandRescaling` — ends "...`(e.g., `HouLi`, out to the Nyquist
    wavenumber) ... `source`" straight after its two caveat admonitions, with no `# Fields`.
  - Same page, `Linear` and `ConstantPower` — both end their `## Arguments` bullets (plus, for
    `ConstantPower`, one caveat) and go straight to `source`.
- **Contradicts**: `FlowConditions` ("Arguments\nAll keyword, all required" then "Fields\nThe
  plain constructor...") — a comparably-sized multi-keyword constructor that does carry Fields.
- **Description**: The three concrete, stateful `Forcing` strategies (`BandRescaling`, `Linear`,
  `ConstantPower`) are constructor-first type docstrings with genuine multi-field state (`domain`,
  `target`/`rate`, shell bounds) yet none carries the demoted `# Fields` section the template
  requires and every comparably-scoped type elsewhere supplies. `NoForcing` is correctly exempt
  (it truly has no fields); these three are not in that class.

## Finding 3

- **Type**: organization
- **Severity**: minor
- **Confidence**: high
- **Locations**:
  - PAGE: api / Cache — `deposit_sample!(cache) -> particle velocities`, body ends "...so this
    call stamps both from the cache's current counters. Returns the slot's array."
- **Contradicts**: every other arrow-bearing mutator omits the redundant sentence, e.g.
  `advect!(...) -> tracers` ends on its caveat with no "Returns" line; `allocate_buffers(...) ->
  IntegratorBuffers` likewise.
- **Description**: `deposit_sample!` carries both the `-> Type` arrow *and* a terminal "Returns
  `x`." sentence — the corpus's own stated rule treats these as the two sanctioned, mutually
  exclusive shapes (arrow for a fixed return type, sentence for an arrow-less mutator). No other
  function in the manuscript combines both.

## Finding 4

- **Type**: organization
- **Severity**: minor
- **Confidence**: high
- **Locations**:
  - PAGE: api / phenomenology / Scalings — `stationary_dissipation(law, kinetic_energy,
    side_length)`, no `-> Float64` and no terminal "Returns" sentence anywhere in the body.
- **Contradicts**: every sibling pure evaluator in `Phenomenology` carries the arrow, e.g.
  `kolmogorov_length(fp) -> Float64`, `taylor_reynolds(fp) -> Float64`, `scaling(law, fp) ->
  Float64`, `provenance(law) -> Reference`.
- **Description**: `stationary_dissipation` is the sole pure-function evaluator on the
  Phenomenology side whose signature omits the `-> Float64` return-type arrow every peer in
  `Phenomenology`/`Scalings`/`Spectra`/`StructureFunctions` uses, and it supplies no substitute
  "Returns" sentence either — a return-type statement is simply absent.

## Finding 5

- **Type**: organization
- **Severity**: major
- **Confidence**: medium
- **Locations**:
  - PAGE: api / SimulationRun, `Simulation` — "Setting the Reynolds number\nBy default the run is
    forced and stationary..." appears as a standalone lead-in before the constructor's `##
    Arguments` heading.
- **Contradicts**: no other type docstring in the corpus (including comparably complex ones like
  `StationarityCriterion`, `FixedDomain`, `Tracers`) inserts a named internal subsection outside
  the standard Arguments/Examples/Fields/admonition sections.
- **Description**: `Simulation`'s docstring introduces an internal, hand-titled subsection
  ("Setting the Reynolds number") holding a multi-paragraph discussion plus its own nested
  admonition and a two-item bulleted Grid/Explicit-mode breakdown, before reaching `## Arguments`.
  This is a structural device unique to this one docstring; every other type folds comparable
  discussion into ordinary identity-sentence prose or a titled caveat admonition instead.

## Finding 6

- **Type**: organization
- **Severity**: minor
- **Confidence**: medium
- **Locations**:
  - PAGE: api / Generator, `FlowConditions` — "A stateful strategy must not be the same instance
    for both fields... the constructor throws an `ArgumentError`" sits inside an `## Arguments`
    bullet.
  - PAGE: api / Forcing, `AbstractForcing` — the identical constraint is its own titled
    admonition, "One instance per forced field, for a strategy that carries state".
  - PAGE: api / Generator, `ResolvedGenerator` — the analogous constructor-validation caveat is
    also a titled admonition, "The constructor rejects a misdeclared forcing".
- **Contradicts**: same caveat *class* (a constructor that throws `ArgumentError` on a bad forcing
  configuration) gets a titled admonition on two docstrings and plain in-bullet prose on a third.
- **Description**: `FlowConditions` embeds its constructor-validation caveat inline in an
  `Arguments` bullet rather than promoting it to a titled admonition, the shape its two closest
  structural siblings both use for the same class of caveat.

## Finding 7

- **Type**: organization
- **Severity**: minor
- **Confidence**: medium
- **Locations**:
  - PAGE: api / SimulationRun, `StationarityCriterion` — "Fields\nThe fields are not the
    keywords... Build one through the keyword constructor above — the positional form takes
    assembled internals and is not part of the interface."
- **Contradicts**: `Simulation`, `ObservablesCache`, `IntegratorBuffers`, `ResolvedGenerator`, and
  `ParticleIntegratorBuffers` — the corpus's other "internals" types — all omit any mention of
  their plain positional constructor, silently.
- **Description**: `StationarityCriterion` is the only type in the exempted-from-plain-constructor
  group that spells out *why* the form is unadvertised; its structural peers apply the same
  omission with no explanatory sentence, so the disclosure shape is inconsistent across one
  otherwise-uniform group.

## Finding 8

- **Type**: organization
- **Severity**: minor
- **Confidence**: medium
- **Locations**:
  - PAGE: api / Propagator, module docstring — bulleted contents list, then directly "`source`",
    no trailing remark.
  - PAGE: api / Particles, module docstring — same: bullets then "`source`" with nothing after.
  - PAGE: api / Cache, module docstring — three full paragraphs follow the bulleted list (the
    solver's-side-of-the-contract paragraph, the epoch-counter paragraph, the epoch-vs-clock
    paragraph).
  - PAGE: api / Observables, module docstring — a four-plus-sentence trailing paragraph covering
    element type, warm-up gating, and dealiasing exactness.
- **Contradicts**: the template's "optional trailing remark" is singular; `SimulationDomain` and
  `SimulationRun` each supply exactly one short sentence.
- **Description**: The length of the module-docstring trailing remark ranges from none
  (`Propagator`, `Particles`) to a single sentence (`SimulationDomain`, `SimulationRun`) to several
  substantive paragraphs (`Cache`, `Observables`, `State`) — the "map, then one optional remark"
  shape is not applied evenly across sibling modules.

## Finding 9

- **Type**: organization
- **Severity**: nit
- **Confidence**: medium
- **Locations**:
  - PAGE: api / State, `ResolvedFields` — "takes the two fields directly, in this order."
  - PAGE: api / Generator, `FlowConditions` — "takes the four fields directly, in this order".
  - PAGE: api / phenomenology / Phenomenology, `Reference` — "takes the two fields directly:" (no
    "in this order").
  - PAGE: api / SimulationDomain, `HouLi` — "takes the two fields directly:" (no "in this order").
- **Contradicts**: `ResolvedFields`/`FlowConditions`/`FlowParameters`/`ModelSpectrum` all add ", in
  this order" to an equally multi-field plain-constructor sentence that `Reference`, `HouLi`, and
  `Sreenivasan1998` omit.
- **Description**: The "in this order" qualifier — which flags that positional field order is
  load-bearing — is attached to some two-plus-field plain constructors and not to others of
  identical shape, with no apparent rule (field count and "all required"-ness are the same across
  both groups).

## Finding 10

- **Type**: organization
- **Severity**: minor
- **Confidence**: low
- **Locations**:
  - PAGE: api / Forcing, `DeferredForcing` — carries a full `## Examples` block with two code
    snippets.
  - PAGE: api / Forcing, `BandRescaling` — no `## Examples` block, despite its `over` keyword
    prose calling itself "the choice that decides which quantity your run may no longer measure".
- **Contradicts**: the stated rule that Examples appear "where construction is non-obvious" — none
  of `BandRescaling`, `Linear`, `ConstantPower` gets one, while the comparatively mechanical
  `DeferredForcing` does.
- **Description**: Among the `Forcing` family, only the pass-through `DeferredForcing` type shows
  a worked construction example; the three concrete strategies — whose keyword semantics the prose
  itself flags as consequential — have none, an uneven application of the Examples rule within one
  tightly-related family.

## Finding 11

- **Type**: organization
- **Severity**: nit
- **Confidence**: low
- **Locations**:
  - PAGE: api / Cache, module docstring — bullet order "`ObservablesCache`" → "`fields_modified!`,
    `particles_modified!`" → the three physical reads → "`max_speed`" → "`particle_velocities`" →
    "`deposit!`, `deposit_sample!`".
  - Same page, section headings — "## The observables cache" (covers `ObservablesCache`,
    `fields_modified!`, `particles_modified!`, `deposit_sample!`) then "## The checked reads"
    (covers the three physical reads plus `particle_velocities`).
- **Contradicts**: the module map's linear bullet order interleaves items that the page itself
  splits into two non-adjacent sections.
- **Description**: `Cache`'s module docstring lists its contents in an order that does not track
  the two `##`-level groupings the rendered page actually uses — `deposit_sample!` sits at the
  bullet list's end though its page section is the first of the two, and the reads are separated
  from `max_speed`/`particle_velocities` in the bullets but not on the page.
