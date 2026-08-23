# Documentation-structure audit (hat: structure-consistency)

## Inferred template

**Function docstring** (in order): (1) signature code block; (2) an identity sentence
binding the function to its symbol/meaning; (3) when-to-use / the alternative route, for a
function with more than one method; (4) each argument explained in prose, parenthesised
against the argument name (never a bulleted `# Arguments` block — that shape is reserved for
types); (5) the physical-meaning-first formula; (6) a named-method citation, which may open
the identity sentence instead of trailing it; (7) a caveat admonition (custom bold title,
plain text) as the **last substantive block**; (8) for an in-place mutator whose signature
carries no `->` arrow, a closing `Returns x.` sentence — placed **before** the caveat
admonition, not after.

**Type docstring**, constructor-first: (1) signature code block (the keyword form when one
exists); (2) identity sentence; (3) either a bulleted `# Arguments` section (independent
keyword settings) or the keywords folded into prose (one coherent object); (4) an `# Examples`
section, with a lead-in sentence before the code, where construction is non-obvious; (5) a
caveat admonition as the **last substantive block, immediately before `# Fields`**; (6) a
demoted `# Fields` section — bulleted when the stored fields differ from the constructor
keywords or when there was no `# Arguments` section to name them, a single summary sentence
when the fields already map 1:1 onto an `# Arguments` list just given.

**Module docstring** = a map: identity sentence, then one **bulleted one-liner per public
object** the module exports, then an optional short trailing remark — not an essay, and never
an admonition box (admonitions are a type/function-docstring device in every other module).

Below, the entries that break this inferred shape.

---

## Finding 1 — Caveat-admonition placement drifts across four different spots (BandRescaling, ConstantPower)

- **Type**: organization
- **Severity**: major
- **Confidence**: high
- **Locations**:
  - PAGE: api / Forcing, `BandRescaling` — admonition *before* `# Arguments`: "Which one a run wants depends on what else reads the kinetic energy"
  - PAGE: api / Forcing, `BandRescaling` — two more admonitions *after* `# Fields`: "A band with nothing in it is left alone" and "A deterministic clamp, not a stationary sampler"
  - PAGE: api / Forcing, `ConstantPower` — admonition *before* `# Arguments`: "An empty band is left alone, not driven infinitely hard"
- **Contradicts**: PAGE: api / Generator, `ResolvedGenerator` — admonition "One optimization crosses two verbs" sits immediately before `## Fields`, the compliant placement; PAGE: api / Generator, `FlowConditions` embeds its caveat inside the last `# Arguments` bullet instead, a third variant.
- **Description**: The corpus's own rule (visible everywhere it is followed — `ResolvedGenerator`, `dissipation`, `velocity_rhs!`, `truncate_to_band!`) is that a caveat admonition is the docstring's last substantive block. `BandRescaling` scatters three admonitions across three different positions (one before `Arguments`, two after `Fields`), and `ConstantPower` puts its one admonition before `Arguments` too — neither ends on the caveat the way `ResolvedGenerator`/`PhaseShift` do.

## Finding 2 — Forcing's module docstring never bullets its own concrete strategy types

- **Type**: organization
- **Severity**: major
- **Confidence**: high
- **Locations**: PAGE: api / Forcing — "The strategies are `NoForcing`, `BandRescaling`, `Linear` and `ConstantPower`, one implementation serving both the velocity and the scalar" (plain prose, no bullet)
- **Contradicts**: every sibling module docstring bullets each public type it exports, e.g. PAGE: api / Cache — "`ObservablesCache` — the cache itself: the slots, their epochs, and the two counters"; PAGE: api / Propagator — "`IFLowStorageRK3`, `IFRK2` — the schemes …"; PAGE: api / SimulationDomain — "`FixedDomain` — the fixed, unsheared cubic box …"
- **Description**: The module-docstring "map" template gives every public type its own bulleted one-liner (Cache, Particles, Propagator, SimulationDomain, Observables, State, SimulationRun all do this). `Forcing`'s four concrete strategies — arguably the module's main public surface — are relegated to one parenthetical sentence instead of four bullets, an outlier shape among the DNS-side module docstrings.

## Finding 3 — Module-docstring "trailing remark" ranges from none to a multi-paragraph essay

- **Type**: organization
- **Severity**: major
- **Confidence**: medium
- **Locations**:
  - PAGE: api / Particles and PAGE: api / Propagator — the docstring ends right at the last bullet, no trailing remark at all.
  - PAGE: api / Cache — three separate trailing paragraphs after the bullets, ending "An epoch counts changes to the state, not advances of the run …"
  - PAGE: api / Observables — a 5-sentence trailing paragraph after the bullets, ending "… the cubic skewness carries the slight residual its own docstring prices."
- **Description**: The map template's trailing remark is meant to be optional and short. In practice it varies from absent (Particles, Propagator, Generator has one sentence) to an essay-length block (Cache, Observables, Forcing, State) carrying real explanatory content (epoch semantics, aliasing conditions) that arguably belongs in the individual function/type docstrings instead.

## Finding 4 — `Simulation` inserts a bespoke narrative section before its `# Arguments`

- **Type**: organization
- **Severity**: minor
- **Confidence**: medium
- **Locations**: PAGE: api / SimulationRun, `Simulation` — "Setting the Reynolds number\nBy default the run is forced and stationary …" (with an embedded admonition and a bulleted Grid-mode/Explicit-mode list) appears between the identity sentence and the `## Arguments` heading.
- **Contradicts**: every other configurable type (`FixedDomain`, `FlowConditions`, `Tracers`, `StationarityCriterion`, `BandRescaling`) goes directly from the identity sentence/short prose to `# Arguments`.
- **Description**: No other type docstring in the corpus interposes a full custom-titled subsection — prose, an admonition, and a bulleted mode list — ahead of `# Arguments`. It is the one place the constructor-first template's step (2)→(3) transition is not direct.

## Finding 5 — `ObservablesCache` doesn't end on its caveat admonition either

- **Type**: organization
- **Severity**: minor
- **Confidence**: medium
- **Locations**: PAGE: api / Cache, `ObservablesCache` — admonition "A cached array is the next iteration's scratch" is followed by a further paragraph, "The word epoch names two things here, and the fields below are of both kinds …", before `## Fields`.
- **Contradicts**: PAGE: api / Generator, `ResolvedGenerator` — its two admonitions sit with nothing between them and `## Fields`.
- **Description**: A second instance of the same class as Finding 1: a caveat admonition that is not the docstring's final block before `# Fields`, this time with a stray explanatory paragraph rather than more admonitions.

## Finding 6 — `Phenomenology`'s module docstring is the only one to use an admonition box

- **Type**: organization
- **Severity**: minor
- **Confidence**: medium
- **Locations**: PAGE: phenomenology / Phenomenology — "Extraction-boundBuilt inside `GBGIsotropicTurbulence` but designed to be cut into a standalone `GBGTurbulencePhenomenology` …" is a boxed, custom-titled admonition inside the module docstring itself.
- **Contradicts**: no DNS-side module docstring (Cache, Forcing, Generator, Observables, Particles, Propagator, SimulationDomain, SimulationRun, State) uses an admonition at the module level — admonitions there are confined to type and function docstrings.
- **Description**: Whatever the merits of flagging extraction-boundedness prominently, it is the one module-level admonition in the whole corpus — a shape no sibling module docstring uses.

## Finding 7 — `Simulation`'s `# Examples` skips the lead-in sentence every other one has

- **Type**: organization
- **Severity**: nit
- **Confidence**: low
- **Locations**: PAGE: api / SimulationRun, `Simulation` — "Examples\n\n```\n# Grid mode — a 128³ forced-stationary run …" — code begins with no prose sentence first.
- **Contradicts**: PAGE: api / SimulationDomain, `FixedDomain` — "Examples\nA default box, and one that keeps a wider band on the same grid:"; PAGE: api / Particles, `Tracers`; PAGE: api / Forcing, `DeferredForcing`; PAGE: phenomenology/Phenomenology, `FlowParameters` — all open `# Examples` with a framing sentence before the code block.
- **Description**: Minor, but consistent across four other types: `# Examples` always gets one framing sentence before the fenced code. `Simulation`'s is the one that jumps straight to the code comment.

## Finding 8 — Six positional-only presets restate their own already-positional signature in `# Fields`

- **Type**: organization
- **Severity**: nit
- **Confidence**: low
- **Locations**: PAGE: phenomenology / Spectra — `PopeLargeScale(c_L, p₀)`, `PopeDissipation(c_η, β)`, `VonKarmanLarge(c_L)`, `PaoDissipation(α)`, `ExponentialDissipation(β)`, `ModelSpectrum(C_K, large_scale, dissipation, ref)`: each type's top code block is already positional-only, and `# Fields` then opens "The plain constructor `ModelSpectrum(C_K, large_scale, dissipation, ref)` takes the four fields directly, in the order shown" — the identical call already shown above.
- **Contradicts**: PAGE: api / SimulationDomain, `HouLi` — top signature `HouLi(; order = 36, strength = nothing)` is keyword, and `# Fields`' "The plain constructor `HouLi(order, strength)` takes the two fields directly" genuinely reveals a second, distinct (positional) way to build it.
- **Description**: The "plain constructor" sentence is meant to tell the reader about an *additional* way to build the value. For these six presets there is no keyword form anywhere in the docstring, so the sentence just repeats the code box verbatim — boilerplate carried over from the pattern's other, informative instances.
