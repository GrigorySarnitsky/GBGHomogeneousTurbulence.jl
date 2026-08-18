# Documentation-structure audit — hat: structure-consistency

## Inferred template

**Function docstring** (the shape most entries follow): (1) an identity sentence naming the quantity in
user terms and its arguments; (2) the physical-meaning formula, usually as an offset `\[...\]` display
block right after the identity sentence (occasionally fused inline into the identity sentence itself);
(3) argument/route explanation in prose (functions never use a bulleted "Arguments" header — that is
reserved for types); (4) a caveat as a `!!!`-style admonition, generally the last content block before
`source`; (5) an inline citation for a named method, usually inside the identity sentence; (6) for a
mutating `f!`, an explicit "Returns `x`." sentence as the final or near-final line — *unless* the code
block itself already shows a `-> ReturnType` arrow, in which case the prose omits a "Returns" sentence.

**Type docstring** (constructor-first): (1) identity sentence; (2) the constructor's keyword arguments —
either a dedicated bulleted "Arguments" header (used for the busier, front-door-style constructors) or
folded into the identity/following prose (used for most others); (3) an "Examples" section, only on the
minority of types whose usage is non-obvious; (4) a demoted "Fields" section, present exactly when the
type has fields, closing with either a full one-liner-per-field description or (for a "plain positional
constructor" restatement) a single "documented above" back-reference.

**Module docstring**: identity sentence, immediately followed by one bulleted "contents" list (each
item linked, no formulas), with any extended discursive aside placed *after* that list, not before it.

Below are the corpus's departures from this inferred template.

---

## Finding 1 — Admonition titling is not uniform: bare `Note`/`Warning` vs. custom titles

**Type**: format
**Severity**: major
**Confidence**: high

**Locations**:
- PAGE: api / Forcing, `BandRescaling`: `"NoteThis is a deterministic clamp, not a faithful stationary sampler..."` (bare-word title) — in the *same* docstring as `"Which one a run wants depends on what else reads k"` (custom-titled aside, no "Note"/"Warning" word at all).
- PAGE: api / Cache, `ObservablesCache`: `"NoteA slot is also the array its producer computes in..."` (bare) vs. the Cache module docstring's own `"An epoch is not an iteration numberAn epoch counts changes to the state..."` (custom-titled, same page).
- PAGE: api / Observables, `max_speed`: `"A grid maximum, not a continuum supremumThe reduction runs over grid points..."` (custom-titled, no bare word).
- PAGE: api / Generator, `velocity_rhs!`: `"ω_consumed is read and then overwrittenThe Lamb vector is formed in place..."` (custom-titled) vs. `scalar_rhs!` on the same page: `"NoteThe assembly consumes u_consumed..."` (bare word), for the structurally identical caveat on the paired function.

**Description**: The same semantic device — a single admonition box — is rendered two ways across the
corpus: with the bare type word ("Note"/"Warning") as its title, or with a custom descriptive title that
replaces the word entirely. Both styles recur dozens of times, sometimes within one docstring
(`BandRescaling`) and sometimes across a paired `f`/`f!` docstring that should share one convention
(`velocity_rhs!` vs. `scalar_rhs!`). No rule distinguishes when each is used.

---

## Finding 2 — Formula placement: offset display block vs. inline-fused-into-identity, inconsistent even within one module

**Type**: format
**Severity**: major
**Confidence**: high

**Locations**:
- PAGE: api / phenomenology / Scalings, `Sreenivasan1995`: `"the inertial-range energy spectrum $E(\kappa) = C_K \varepsilon^{2/3}\kappa^{-5/3}$ — the amplitude..."` (inline, fused into the identity sentence).
- PAGE: api / phenomenology / Scalings, `Sreenivasan1998` (same page, same module): `"\[C_\varepsilon(\mathrm{Re}_\lambda) = C_{\varepsilon\infty}\Bigl(1 + \frac{a}{\mathrm{Re}_\lambda}\Bigr),\]"` (separate offset display block).
- PAGE: api / phenomenology / Scalings, `Li2008` (same page): `"\[G = \frac{k}{(L\varepsilon)^{2/3}} \approx 0.9,\]"` (separate display block).
- PAGE: api / phenomenology / Spectra, all six roll-off factors (`PopeLargeScale`, `PopeDissipation`, `VonKarmanLarge`, `PaoDissipation`, `ExponentialDissipation`, `SaffmanDissipation`) fuse their formula into the identity sentence, while the three composed presets on the same page (`Pope2000`, `VonKarman1948`, `Pao1965`) all use a separate display block.

**Description**: Whether the physical-meaning formula is its own visual block or folded into the running
identity sentence is not decided by any evident rule (quantity type, formula complexity, etc.) — three
sibling laws on the very same `Scalings` page split 1-inline/2-block, and the `Spectra` page splits
cleanly along "roll-off factor" (always inline) vs. "composed preset" (always block) with no stated
reason for the split.

---

## Finding 3 — A dedicated "Arguments" header is used for some multi-keyword types, folded into prose for siblings with the same keyword count

**Type**: organization
**Severity**: major
**Confidence**: medium

**Locations**:
- PAGE: api / Generator, `FlowConditions`: `"Arguments\nAll keyword, all required:\n\n- \`viscosity\` — ..."` (explicit header, 4 keywords).
- PAGE: api / Forcing, `BandRescaling(domain; target, over, lowest_shell = 1, highest_shell = 2)`: no "Arguments" header at all — `target`, `over`, `lowest_shell`, `highest_shell` (4 keywords) are explained purely in running prose.
- Same for `Linear`/`ConstantPower` (3 keywords each, no header) and `ResolvedGenerator`/`ObservablesCache`/`Tracers` (2–3 keywords each, no header).

**Description**: `FlowConditions`, `FixedDomain`, `Simulation`, `StationarityCriterion`, and
`FlowParameters` get an explicit bulleted "Arguments" section; every other multi-keyword type
(`BandRescaling`, `Linear`, `ConstantPower`, `ResolvedGenerator`, `ObservablesCache`, `Tracers`,
`IntegratorBuffers`) documents a comparable or larger keyword set purely in prose. No axis (keyword
count, "front-door only" status, required-ness) cleanly separates the two groups.

---

## Finding 4 — Cache's module docstring interposes a conceptual aside before its contents list; every sibling module docstring puts the list first

**Type**: organization
**Severity**: major
**Confidence**: medium

**Locations**:
- PAGE: api / Cache: `"Each slot carries the value and the moment that value belongs to... An epoch is not an iteration number[...] "` — this entire epoch-mechanism discussion sits *between* the module's identity sentence and `"The cache's operations:"` bulleted list.
- Contrast PAGE: api / Forcing: `"The interchangeable energy-injection strategies:\n\n- \`AbstractForcing\` — ..."` — the list follows the identity sentence immediately, with all discursive elaboration (the four-hook lifecycle) *inside* the list's own bullet, not before it.
- Contrast PAGE: api / Observables and PAGE: api / Particles, whose module docstrings both put the "measured functions" / "tracer tracking" list first and reserve trailing prose for *after* the list.

**Description**: Every other module-map docstring follows identity-sentence → contents-list → (optional)
trailing remark. Cache alone precedes its list with a substantial standalone explanation of the epoch
mechanism, breaking the "module docstring is a map, formula-free, list-first" shape the rest of the
corpus keeps.

---

## Finding 5 — The two random-seeding functions never state a "Returns" sentence that sibling in-place mutators consistently include

**Type**: organization
**Severity**: minor
**Confidence**: medium

**Locations**:
- PAGE: api / State, `random_solenoidal_velocity_spectral!(û, domain; ...)`: docstring ends on the "Seeding a running case invalidates the observables cache" note — no "Returns `û`" sentence anywhere in the body.
- PAGE: api / State, `random_scalar_spectral!(φ̂, domain; ...)`: same omission.
- Contrast PAGE: api / Observables, `vorticity_physical!(ω, û, domain, spectral_scratch)`: `"...no preservation copy is needed. Returns \`ω\`."`
- Contrast PAGE: api / Cache, `fields_modified!(cache)`: `"...Returns \`cache\`."`; PAGE: api / Generator, `prepare!`/`velocity_rhs!`/`scalar_rhs!`/`finalize!`, and PAGE: api / Propagator, `step!`/`deposit!` — all explicitly state "Returns `x`." near the end.

**Description**: Every in-place mutator whose signature omits the `-> ReturnType` arrow instead states
an explicit "Returns `x`." sentence in prose (Cache, Generator, Propagator, and `vorticity_physical!`
itself). The two `State` seeding functions have the same no-arrow signature shape yet supply no such
sentence — a documented-return gap against their own template class.

---

## Finding 6 — `FlowConditions`'s "Fields" section duplicates full prose (plus Julia types); `FlowParameters`'s equivalent section is a one-line back-reference

**Type**: organization
**Severity**: minor
**Confidence**: medium

**Locations**:
- PAGE: api / Generator, `FlowConditions` Fields: `"- \`viscosity\`, \`schmidt\` — the kinematic viscosity ν and the Schmidt number Sc (both \`Float64\`)."` — restates the Arguments-section prose nearly verbatim, adding element-type annotations found nowhere else in the corpus's Fields sections.
- PAGE: api / phenomenology / Phenomenology, `FlowParameters` Fields: `"...each holds the value documented for the keyword of the same name above."` — one line, no restatement.

**Description**: Both types share the same "plain positional constructor takes the fields directly, in
this order" convention, but one fully re-describes every field (and uniquely annotates concrete Julia
types) while the sibling compresses to a single referring sentence. `HouLi`'s Fields section sits closer
to `FlowConditions`'s fuller style; most other parameter types (`Li2008`, `Sreenivasan1998`, `Reference`,
`PopeLargeScale`, etc.) use short one-liners that are shorter still than either — a spread of at least
three distinct verbosity levels for the same structural slot.

---

## Finding 7 — `ResolvedGenerator`'s admonition sits mid-docstring, not near the end like its siblings

**Type**: organization
**Severity**: minor
**Confidence**: medium

**Locations**:
- PAGE: api / Generator, `ResolvedGenerator`: `"One optimization crosses two verbsUnder \`PhaseShift\`, \`velocity_rhs!\` leaves the stage's displaced velocity fresh..."` appears *before* the `"Build it on the \`FixedDomain\` \`domain\`..."` construction paragraph and the Fields section — i.e., in the middle of the docstring.
- Contrast PAGE: api / Propagator, `IFRK2`: its stability-caveat Note is the last content block before `source`; PAGE: api / SimulationDomain, `PhaseShift`: its Nyquist-mode Note is likewise the last block before `source`.

**Description**: The corpus's dominant convention places a caveat admonition as the last substantive
block before `source`. `ResolvedGenerator` breaks this by placing one aside mid-docstring (before the
constructor-usage paragraph) and a second, different aside ("The constructor rejects a misdeclared
forcing") at the true end — the two admonition placements coexist in one docstring without an evident
reason for the split.

---

## Finding 8 — The `Phenomenology` module docstring carries two separate "contents" lists; every sibling module docstring has exactly one

**Type**: organization
**Severity**: minor
**Confidence**: medium

**Locations**:
- PAGE: api / phenomenology / Phenomenology: `"The flow state a law reads:\n\n- \`FlowParameters\` — ...\n- \`provenance\` — ..."` followed immediately by a second list: `"The law families, one submodule per representation:\n\n- \`Spectra\` — ...\n- \`StructureFunctions\` — ...\n- \`Scalings\` — ..."`.
- Contrast every DNS-side module docstring (Cache, Forcing, Generator, Observables, Particles, Propagator, SimulationDomain, State, SimulationRun) — each has exactly one bulleted "contents" list.

**Description**: All nine DNS-side module docstrings converge on a single flat contents list; the
`Phenomenology` root docstring alone splits its map into two consecutive lists (bundle-and-helpers vs.
law-family submodules), an outlier shape not seen anywhere else in the corpus.

---

## Finding 9 — Particles is the only API page opening with a usage-example section before its reference material

**Type**: organization
**Severity**: minor
**Confidence**: medium

**Locations**:
- PAGE: api / Particles: `"## Wiring tracers into a run\nPass \`number_of_particles\` to the front door and the run carries a tracer set..."` — a full worked code example — appears as the *first* `##` section, before `"## The tracer set"` (the first type/function reference section).
- Every sibling reference page (Cache, Forcing, Generator, Observables, Propagator, SimulationDomain, State, SimulationRun) opens its first `##` section directly with reference material (a type or function group), with no page-level usage-example preamble.

**Description**: No other API module page front-loads a standalone usage vignette ahead of its type/function
catalogue; Particles alone does, giving it a different opening shape than every sibling page.

---

## Finding 10 — "Examples" sections appear on a minority of types with no stated selection rule

**Type**: organization
**Severity**: nit
**Confidence**: low

**Locations**:
- Present: PAGE: api / SimulationDomain `FixedDomain`; PAGE: api / Particles `Tracers`; PAGE: api / SimulationRun `Simulation`; PAGE: api / phenomenology / Phenomenology `FlowParameters`.
- Absent despite comparable or greater constructor complexity: PAGE: api / Cache `ObservablesCache`; PAGE: api / Generator `ResolvedGenerator` / `FlowConditions`; PAGE: api / Forcing `BandRescaling`.

**Description**: Only four types in the whole corpus carry an "Examples" section. The type-docstring
template says an example belongs "where the construction is non-obvious," which plausibly explains most
of the split, but `ObservablesCache` and `ResolvedGenerator` — both central, non-trivially-constructed
run-layer objects — get none, while `Tracers` (arguably simpler to intuit) does. Flagged at low
confidence since the omission may be a deliberate judgment call rather than a structural drift.
