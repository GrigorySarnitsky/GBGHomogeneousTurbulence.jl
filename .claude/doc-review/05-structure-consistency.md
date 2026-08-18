# Documentation-structure audit — structure-consistency hat

**Inferred template.**

*Function docstring*: (1) identity sentence, often binding `code` ≡ symbol; (2) physical-meaning-first
formula; (3) each argument explained inline (prose, not bulleted, for a plain function); (4) a caveat
as a custom-titled admonition, placed as the **last substantive block** before `source`; (5) a
`Returns x.` sentence when the signature carries no `-> Type` arrow, otherwise the arrow states it;
(6) a named-method citation, which may open the identity sentence.

*Type docstring (constructor-first)*: (1) identity sentence; (2) constructor + a bulleted
**Arguments** section when the keywords are independent settings; (3) an **Examples** section when
construction is non-obvious; (4) a demoted **Fields** section, ending the docstring — the plain
positional constructor named only for a small parameter record.

Findings below are outliers against this inferred shape, not against the physics.

---

### Finding 1 — `Returns x.` sentence: sometimes the literal last sentence, sometimes mid-docstring

- **type**: organization
- **severity**: major
- **confidence**: high
- **locations**:
  - PAGE: api / Propagator — `step!`: "...and `deposit!`, and the run layer's `advance!` does both.\n\nReturns `state`.\n\nsource" (Returns is the final sentence, after its admonition)
  - PAGE: api / Generator — `prepare!`: "...the integrating factors then consume what it prepared. Returns `generator`." (final sentence)
  - PAGE: api / Cache — `fields_modified!`: "...that interval belongs to whoever made the change. Returns `cache`.\nThe sanctioned mutators call this for you: ..." (Returns mid-docstring, more prose follows)
  - PAGE: api / Observables — `vorticity_physical!`: "...no preservation copy is needed. Returns `ω`.\nThe deposited value is read back with `vorticity_physical`..." (Returns mid-docstring)
- **contradicts**: same "in-place mutator, no arrow" class, opposite placement of the one required sentence.
- **description**: `step!`, `deposit!`, `finalize!`, `prepare!` all place `Returns x.` as the literal final sentence of the docstring. `fields_modified!`, `particles_modified!`, `vorticity_physical!`, `truncate_to_band!`, and both `random_*_spectral!` seeders place it mid-docstring, then continue with further explanatory prose or an admonition. Both groups are in-place mutators lacking a `-> Type` arrow, so nothing in the class predicts which shape a given mutator gets.

---

### Finding 2 — Some constructors document their keywords only in prose, skipping the bulleted Arguments section their close siblings use

- **type**: organization
- **severity**: major
- **confidence**: high
- **locations**:
  - PAGE: api / Forcing — `Linear`/`ConstantPower` both carry "Arguments\n\n- `domain` — ...\n- `rate` — ...\n- `lowest_shell = 1`, `highest_shell = 2` — ..."
  - PAGE: api / Forcing — `BandRescaling(domain; target, over, lowest_shell = 1, highest_shell = 2)` has no "Arguments" heading at all; `domain`, `lowest_shell`, `highest_shell` are never explained anywhere in its docstring.
  - PAGE: api / Generator — `ResolvedGenerator(domain, conditions; scalar = false)` likewise has no "Arguments" heading; its three keywords are described only in the sentence "Build it on the `FixedDomain` `domain` from the `conditions`; pass `scalar = true`..."
- **contradicts**: `FixedDomain`, `FlowConditions`, `Tracers`, `ObservablesCache`, `StationarityCriterion` all give a comparable or smaller keyword count its own bulleted Arguments list.
- **description**: Three of the eight forcing/generator/domain constructors with 3–5 independent keywords fold them into prose instead of the bulleted Arguments section every sibling of similar shape uses — and for `BandRescaling` two of its four keywords (`lowest_shell`, `highest_shell`) go completely undocumented as a result.

---

### Finding 3 — A Module docstring carries a Type-docstring device (the titled admonition)

- **type**: organization
- **severity**: major
- **confidence**: medium
- **locations**:
  - PAGE: api / Cache (module docstring, not the `ObservablesCache` type): "An epoch is not an iteration numberAn epoch counts changes to the state, not advances of the run."
- **contradicts**: every other module docstring (Forcing, Generator, Observables, Particles, Propagator, SimulationDomain, SimulationRun, State) ends its bullet list with at most a short trailing remark in plain prose — none carries a custom-titled caveat block, a device the corpus otherwise reserves for type and function docstrings.
- **description**: The `Cache` module page's own docstring — the "map," per the inferred template — includes a fully-formed titled admonition about epochs, a unit of exposition every other module docstring omits. The content itself (epoch ≠ iteration) properly belongs on `ObservablesCache` or `fields_modified!`, both of which already restate it.

---

### Finding 4 — `StationarityCriterion`'s Fields section names its own constructor, then disclaims it as internal

- **type**: organization
- **severity**: major
- **confidence**: medium
- **locations**:
  - PAGE: api / SimulationRun — `StationarityCriterion`: "The plain constructor `StationarityCriterion(monitor, max_turnovers, gate_scalar, elapsed_turn, last_time, started)` is internal."
- **contradicts**: every other "plain constructor" line in the corpus (`FlowConditions`, `HouLi`, `FlowParameters`, `Reference`, `Sreenivasan1998`, `ModelSpectrum`, `Kolmogorov1941`, …) presents the positional form neutrally as something the reader may call, e.g. `FlowConditions`: "The plain constructor `FlowConditions(...)` takes the four fields directly."
- **description**: Naming a "plain constructor" and giving its exact signature only to say in the next clause that it is internal and that the keywords "do not map one-to-one onto these fields" is a different shape from every other Fields section, which either fully documents the plain form or (per the corpus's own machinery-type class — `Simulation`, `ObservablesCache`, `Tracers`) omits naming it altogether.

---

### Finding 5 — Two types append explanatory prose after their Fields bullet list, unlike every other Fields section

- **type**: organization
- **severity**: minor
- **confidence**: high
- **locations**:
  - PAGE: api / Propagator — `IntegratorBuffers`, after its last Fields bullet: "There are deliberately no physical-representation registers here: the substage velocity, vorticity, and scalar recoveries write into the run's `ObservablesCache` slots..."
  - PAGE: api / Particles — `Tracers`, after its last Fields bullet: "The trajectory scheme's own working storage is not here: it lives in a `ParticleIntegratorBuffers`, whose docstring explains the split."
- **contradicts**: `ObservablesCache`, `ResolvedGenerator`, `ResolvedFields`, `ParticleIntegratorBuffers`, `FlowConditions`, `FlowParameters` all end their docstring exactly at the last Fields bullet, immediately followed by `source`.
- **description**: The template's "Fields is the demoted, final section" is followed by the majority of types, but `IntegratorBuffers` and `Tracers` each tack a further paragraph on after the bullets — content that, by the template's own logic, belongs before Fields (as a caveat admonition) or inside the relevant bullet, not after the section that is supposed to close the docstring.

---

### Finding 6 — Two docstrings interleave ordinary prose between two caveat admonitions

- **type**: organization
- **severity**: minor
- **confidence**: medium
- **locations**:
  - PAGE: api / Observables — `max_speed`: admonition "A grid maximum, not a continuum supremum..." is followed by a plain paragraph ("The second form reads the number back from an `ObservablesCache`...") before a second admonition, "Why this observable alone has a cached form...".
  - PAGE: api / Forcing — `BandRescaling`: admonition "Which one a run wants depends on..." is followed by the plain sentence "Rescaling preserves the divergence-free constraint either way." before the second admonition, "A deterministic clamp, not a stationary sampler...".
- **contradicts**: `dissipation`, `scalar_dissipation`, `derivative_skewness`, `advect!`, and `PhaseShift` each carry exactly one caveat admonition, positioned as the literal last block before `source` — the pattern the template states explicitly.
- **description**: Where most docstrings treat "the admonition" as a single, final block, these two instead sandwich a plain paragraph between two admonitions, breaking the last-block convention twice within the same docstring rather than once.

---

### Finding 7 — `energy_spectrum` states an explicit `Returns` sentence; its sibling pure Observables functions never do

- **type**: organization
- **severity**: minor
- **confidence**: medium
- **locations**:
  - PAGE: api / Observables — `energy_spectrum`: "Returns a named tuple `(; wavenumbers, energy)`: the shell-center wavenumber magnitudes..."
  - PAGE: api / Observables — `kinetic_energy`, `integral_scale`, `derivative_skewness`, `dissipation`: none states a trailing "Returns ..." sentence; each ends its identity/formula prose directly.
- **contradicts**: none of these are in-place mutators, so the corpus's own rule ("a `Returns x.` sentence is required of any in-place mutator whose signature carries no arrow") does not obviously license `energy_spectrum`'s use of one while withholding it from its four closest siblings.
- **description**: All five functions are pure, non-mutating reductions with no `-> Type` arrow in their signature block. Only `energy_spectrum` closes with an explicit "Returns a named tuple ..." sentence describing its return shape; the others leave the return value to be inferred from the identity sentence alone.

---

*Seven findings reported, ranked most- to least-severe; none overlaps an adjudicated item.*
