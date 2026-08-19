# Style / copy-edit review — hat: style-editor

Scope: `manuscript-full.md` (full rendered site) plus spot-checks of the raw built HTML under
`docs/build` for silent rendering failures. Findings ranked most-severe first. Items already
settled in `.claude/doc-review-adjudicated.md` (Saffman attribution, `kinetic_energy` 1.5 vs 0.5,
decision-log history, deferred capabilities, `vorticity_spectral(sim)`, `Lundgren2002` in
StructureFunctions refs, `deposit_velocity!`/`take_velocity!` existence, host-device-sync floor
vs achieved, `integrator` false cognate, PascalCase presets, `No DOI`/`no DOI`, bare `CatmullRom`,
arrow vs `Returns` sentence, citation-opens-identity) are excluded.

---

## Finding 1 — "observation" is used for three different objects

- **Type:** clarity / notation
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - `notation.md`, Vocabulary: *"observation | the callback a run is driven by: it reads the run once per iteration and its return decides whether to continue."* (defines *observation* = the callback, a single object per run)
  - `architecture.md` §3/§4.7 and `SimulationRun` module docstring: *"the callback is the observation — the thing that reads the run each iteration — and its return decides continuation"* (same sense: object)
  - `architecture.md` §2 / `SimulationRun.run!`: *"n iterations, n+1 observations"*, *"A run of n iterations therefore observes n + 1 instants"* (here *observation* is a countable **event**, not an object — there is exactly one callback per run, never n+1 of them)
  - `observables_cache.md` §1.1: *"between those times... sits the observation: the caller's callback reads the state and the cache"* (event again)
  - `architecture.md` §8 and `SimulationRun.Simulation` docstring: *"the `ObservablesCache` observation cache"*, *"the observation cache holds spent compute, reconstructable from the record"* — here *observation cache* is used as an informal alias for **the `ObservablesCache` itself**, a third referent distinct from both the callback and the event.
- **Contradicts:** `notation.md`'s own Vocabulary section states each term "means exactly this and nothing looser," yet *observation* is bound to three distinct kinds of object (the callback, the per-iteration event of it firing, and the cache) across the corpus — precisely the field/representation-style category conflation the house rules ask reviewers to guard against.
- **Description:** This is a load-bearing term (it names the run's whole driving mechanism) used inconsistently enough that a cold reader cannot form one mental model of what "an observation" is. The event sense ("n+1 observations") and the object sense ("the callback is the observation") cannot both be literal; the "observation cache" sense adds a third name for something that already has a canonical name (`ObservablesCache`/"the cache") everywhere else, including the Cache module's own docstring.
- **Resolution hint:** Pick one referent for the glossary entry (most usage supports "the discrete act of a callback reading the run"), retire "observation cache" in favor of "the cache"/`ObservablesCache" wherever it appears, and word the callback-defining sentences ("the callback is the observation") to say the callback *performs* the observation rather than *is* it.

---

## Finding 2 — `deposit_sample!` is prescribed to the reader but never documented

- **Type:** api-gap / self-containedness
- **Severity:** major
- **Confidence:** high
- **Locations:** `api/Cache/index.html` (`Cache.particles_modified!` docstring): *"A hand-run loop that repositions tracers itself must call this, then `record_particle_velocities!` to write the new values, and finally `deposit_sample!` to record them at the current epochs"*.
- **Contradicts:** No other occurrence of `deposit_sample!` exists anywhere in the manuscript — not as its own docstring entry, not in the master `GBGIsotropicTurbulence` API index (which lists every other public verb, including the sibling `record_particle_velocities!`), and not on the Cache or Particles pages' section lists.
- **Description:** The docstring tells a reader following a hand-run loop that they "must" call `deposit_sample!`, but a cold reader has no way to find its signature, its module, or confirm it is even public API — it fails the doc policy's own cold-read test ("every signature argument documented... a term of art... is explained or `@ref`-linked"). Either the function needs a docstring and an index entry, or the instruction is stale and should name whatever verb actually serves this role today.
- **Resolution hint:** Add `deposit_sample!` to the Cache (or Particles) API page with its own docstring, or replace the reference with the currently-correct verb name.

---

## Finding 3 — Two citation/DOI formats coexist across the corpus

- **Type:** citation / format
- **Severity:** minor
- **Confidence:** medium-high
- **Locations:**
  - `architecture.md` §References: *"Orszag, S. A. (1971)... J. Atmos. Sci. 28, 1074. https://doi.org/10.1175/1520-0469(1971)028%3C1074:OTEOAI%3E2.0.CO;2"* — full `https://doi.org/` URL, percent-encoded `<`/`>`.
  - `api/SimulationDomain/index.html` (`TwoThirds` docstring), citing the same Orszag (1971) work: *"doi:10.1175/1520-0469(1971)028<1074:OTEOAI>2.0.CO;2"* — bare `doi:` prefix, literal (unescaped) `<`/`>`.
  - Every `Phenomenology` submodule's own `## References` list (`Scalings`, `Spectra`, `StructureFunctions`) uniformly uses the bare `doi:10.xxxx` form with no article title, e.g. *"Sreenivasan (1998), Phys. Fluids 10, 528. doi:10.1063/1.869575"*, versus `architecture.md`'s `LastName, Initial. (Year). Title. Journal Vol, pages. https://doi.org/...` form.
- **Contradicts:** the same physical citation (Orszag 1971) is rendered two different ways depending on which page cites it; the two DOI conventions are never reconciled or acknowledged as deliberate.
- **Description:** `CLAUDE.md`'s citation rule ("Citations follow author–year; the full references are §References... never cite an inaccessible source") does not license a second citation-string format. This is a real, checkable, corpus-wide split between a verbose `ARCHITECTURE.md`-style reference and a terse docstring/Phenomenology-style reference, most visible where both cite the identical paper.
- **Resolution hint:** Standardize on one DOI-string convention (either always the resolvable `https://doi.org/` URL, or always the bare `doi:` prefix) across `ARCHITECTURE.md`, inline docstring citations, and the `Phenomenology` reference lists.

---

## Finding 4 — `to_spectral` is `@extref`-linked on its second mention but bare on its first, same page

- **Type:** typesetting / cross-referencing
- **Severity:** minor
- **Confidence:** high
- **Locations:**
  - `notation.md`, "## Conventions" table, row for $\hat f$: rendered HTML is `<code>to_spectral(f)</code>` — plain code span, **no link**.
  - `notation.md`, "## Spectral representation and operators" table, a few rows below on the **same page**: `<a href="https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/dev/api/Fields/#GBGPeriodicFields.Fields.to_spectral"><code>to_spectral</code></a>` — properly `@extref`-linked to `GBGPeriodicFields`.
- **Contradicts:** `CLAUDE.md`'s cross-referencing rule: "(1) Link a target at most once per docstring — its first genuine mention." The first genuine mention of `to_spectral` on `notation.md` is the unlinked one; the link appears only on the second mention.
- **Description:** Confirmed directly in the built HTML (not an extraction artifact): identical identifier, same page, inconsistent linking. A reader hitting the first occurrence has no way to jump to the backend's actual documentation for it.
- **Resolution hint:** Move the `@extref` link to the first occurrence (the Conventions-table row), or drop the link from the second and rely on the first.

---

## Finding 5 — No single convention for where a trailing caveat admonition sits relative to the closing "Returns" sentence

- **Type:** format (docstring skeleton)
- **Severity:** nit
- **Confidence:** medium
- **Locations:**
  - Admonition **before** the final `Returns` sentence (i.e. `Returns` is the true last line): `Generator.velocity_rhs!` (admonition *"The vorticity argument is read and then overwritten..."*, then eventually *"Returns `N̂`."*); `Propagator.step!` (admonition *"A step alone leaves the cache mid-iteration..."* immediately followed by *"Returns `state`."*).
  - Admonition **after** the `Returns` sentence (i.e. `Returns` is not last): `State.random_solenoidal_velocity_spectral!` (*"Returns `û`."* then the admonition *"Seeding a running case invalidates the observables cache..."*); `State.random_scalar_spectral!` (same pattern with `φ̂`); `SimulationDomain.truncate_to_band!` (*"Returns `field`."* then *"Truncating the band is not always the whole of dealiasing..."*).
- **Contradicts:** the two groups place the same two elements (a load-bearing caveat, and the closing `Returns` sentence) in opposite relative order, with no discernible rule distinguishing which docstrings get which order.
- **Description:** `CLAUDE.md` states a caveat admonition is "the last substantive block... before `# Fields`" for **type** docstrings; for **function** docstrings with a `Returns` sentence, the corpus is split roughly evenly (3 vs 3 among the sampled instances) with no stated rule, so this reads as skeleton drift rather than a deliberate two-shape convention.
- **Resolution hint:** Pick one order for function docstrings that both mutate a field and carry a caveat (recommend: caveat first, `Returns` last, mirroring the type-docstring rule) and apply it uniformly.

---

## Finding 6 — `notation.md`'s reference-conventions table has no header separator sanity issue, but the intro rule about `Code`-column linking doesn't apply to the "Conventions" table (design ambiguity, not a defect)

- **Type:** organization
- **Severity:** nit
- **Confidence:** low
- **Locations:** `notation.md`, "## Conventions" table (`Concept | Symbol | Convention`, no `Code` column) versus every later table on the same page (`Symbol | Meaning | Code`).
- **Description:** Noted for completeness only: the page states "Every Code entry naming a package object links to its documentation," but the very first table has no `Code` column at all, so `to_spectral(f)` inside its "Convention" cell sits outside that rule's literal scope — which is why Finding 4 has to invoke the general cross-referencing rule rather than this one. Flagging as a low-confidence "smells inconsistent" observation, not a separate defect from Finding 4.
- **Resolution hint:** none needed beyond Finding 4's fix.
