# Doc-policy hat — findings

Scope: does each docstring obey CLAUDE.md's "Documentation policy" and "Doc-edit checklist"? All
findings below are verified against the authored source (`src/*.jl`), not just the rendered
manuscript extraction, to rule out extraction artifacts.

---

## Finding 1 — `Phenomenology` module docstring inserts an essay paragraph before the contents list

- **Type:** organization
- **Severity:** major
- **Confidence:** high
- **Location:** PAGE: api / phenomenology / Phenomenology, module docstring (`src/Phenomenology.jl`,
  lines 10–24)
- **Quote:** "This is the *predicted* counterpart to the measured `Observables` … A law family is an
  abstract subtype of `TurbulenceLaw` … Choosing a law is choosing the preset … a name is
  disambiguated by its **submodule** … The module's contents:\n- `FlowParameters` — …"
- **Contradicts:** CLAUDE.md, Template conventions: "A module map is identity → contents list →
  optional trailing remark, in that order, with **no essay before the list**."
- **Description:** Between the one-sentence identity and the `The module's contents:` bulleted
  list sits a full second paragraph (~4 sentences) explaining the `TurbulenceLaw` subtyping
  mechanism, the `Spectra.Pope2000`-style aliasing, and the submodule/author-year/trailing-letter
  disambiguation scheme. That is exactly the "essay before the list" the house rule forbids. Every
  sibling module docstring in the corpus (`Cache`, `Generator`, `Observables`, `Scalings`,
  `StructureFunctions`, …) goes identity-sentence → list with no such interposed paragraph, so this
  is an outlier, not the house style.
- **Resolution hint:** Move the "law family is an abstract subtype…" paragraph to a trailing remark
  after the list, or fold its content into the individual bullet for `TurbulenceLaw`/`provenance`.

---

## Finding 2 — Caveat admonitions are not positioned as the docstring's last substantive block (class, 4 instances)

- **Type:** format
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: api / Forcing, `BandRescaling` (`src/Forcing.jl` ~253–298): one `!!! note` sits **before**
    `# Arguments`, and **two** further `!!! note` blocks sit **after** `# Fields`.
    Quote: `over` bullet ends "…Which one a run wants depends on what else reads the kinetic
    energy…" (before `# Arguments`); then after `# Fields`: `!!! note "A band with nothing in it
    is left alone"` and `!!! note "A deterministic clamp, not a stationary sampler"`.
  - PAGE: api / Forcing, `ConstantPower` (`src/Forcing.jl` ~400–419): `!!! note "An empty band is
    left alone, not driven infinitely hard"` sits **before** `# Arguments` instead of immediately
    before `# Fields`.
  - PAGE: api / Cache, `ObservablesCache` (`src/Cache.jl` ~93–121): `!!! note "A cached array is
    the next iteration's scratch"` is followed by a further substantive paragraph ("The word
    *epoch* names two things here…") **before** `# Fields` — the admonition is not last.
  - PAGE: api / Propagator, `recommended_cfl` (`src/Propagator.jl` ~543–557): `!!! warning "The
    IFRK2 margin does not know the viscosity"` is followed by a further substantive paragraph
    ("It scales that base by the domain's dealiasing…") that ends the docstring — the admonition is
    not last.
- **Contradicts:** CLAUDE.md, Template conventions: "A caveat admonition is the **last substantive
  block** of a docstring, before `# Fields`."
- **Description:** Four separate docstrings (two types, one more type, one function) all place a
  titled caveat admonition somewhere other than the required position — either ahead of
  `# Arguments`, or with ordinary explanatory prose still following it. Other docstrings in the same
  files (e.g. `dissipation`, `max_speed`, `Kolmogorov1941`, `PhaseShift`) get this right (admonition
  as the true final block), so the rule is known and followable; these four are the exceptions.
- **Resolution hint:** In each case, move the admonition to immediately precede `# Fields` (types)
  or to the true end (functions); for `BandRescaling`, consolidate the pre-Arguments note and the
  two post-Fields notes into one place.

---

## Finding 3 — The umbrella `GBGIsotropicTurbulence` module docstring is not a map: no linked one-liner per submodule

- **Type:** organization
- **Severity:** major
- **Confidence:** medium-high
- **Location:** PAGE: api / GBGIsotropicTurbulence, module docstring (`src/GBGIsotropicTurbulence.jl`
  lines 32–48)
- **Quote:** "Tools for simulating homogeneous isotropic turbulence … The package produces the flow
  and the values sampled from it … Built on `GBGPeriodicFields`. The `GBG` part in the name comes
  from the city of Göteborg …" — no per-submodule bullet list anywhere in the docstring itself.
- **Contradicts:** CLAUDE.md, Documentation policy: "Module docstring = map. What the module is, its
  scope, its invariants — then a **linked one-liner per operation**." Every other module docstring
  in the corpus (`SimulationDomain`, `State`, `Observables`, `Cache`, `Forcing`, `Generator`,
  `Propagator`, `Particles`, `SimulationRun`, `Phenomenology`, `Scalings`, `Spectra`,
  `StructureFunctions`) opens with exactly such a bulleted, `@ref`-linked contents list; the
  umbrella is the sole module whose docstring skips it entirely (the similar bulleted list a reader
  sees on the rendered page is Documenter's separate auto-generated Index, not part of this
  docstring).
- **Description:** The package's front-door module — the one `using GBGIsotropicTurbulence` brings
  into scope, and the first thing a REPL `?GBGIsotropicTurbulence` shows — has no map of its nine
  submodules inside its own docstring, unlike every other module in the codebase. A reader who
  types `?GBGIsotropicTurbulence` gets trivia about Göteborg but no linked orientation to
  `SimulationRun`, `SimulationDomain`, etc.
- **Resolution hint:** Add the same `- SubModule — one-liner` list the Home page's "Components"
  section and `docs/src/api.md` already carry, so the docstring is self-contained at the REPL.

---

## Finding 4 — `Cache.vorticity_physical` restates the formula its `!` home already owns

- **Type:** format
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: api / Observables, `vorticity_physical!` (home): "Compute the vorticity
    $\boldsymbol{\omega} = \nabla\times\boldsymbol{u}$ in physical representation into `ω` …"
  - PAGE: api / Cache, `vorticity_physical` (checked read): "The vorticity
    $\boldsymbol{\omega} = \nabla\times\boldsymbol{u}$ in physical representation at the current
    epoch … The deposited value is produced by `vorticity_physical!` — measure with that function,
    read with this one."
- **Contradicts:** CLAUDE.md, Documentation policy: "One concept, one home… Across an `f` / `f!`
  pair the in-place `!` form is the **home**… the allocating [thin-wrapper] form is a thin
  `@ref`-linking wrapper with **no second copy of the formula**."
- **Description:** The docstring itself names the measure/read split explicitly ("measure with that
  function, read with this one"), i.e. treats `vorticity_physical!` as home and `vorticity_physical`
  as the thin wrapper — but the wrapper restates $\boldsymbol{\omega}=\nabla\times\boldsymbol{u}$
  rather than only cross-referencing it. Contrast with the sibling `velocity_physical` /
  `scalar_physical` cache reads, which carry no formula at all (correctly, since there is nothing to
  duplicate).
- **Resolution hint:** Drop the restated formula from the Cache accessor and lean on the `@ref` to
  `vorticity_physical!` for it, matching `velocity_physical`'s pattern.

---

## Finding 5 — Three `Phenomenology` submodule "References" sections cite the bare `ARCHITECTURE.md` filename on the rendered page

- **Type:** citation
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: api / phenomenology / Scalings, `## References` (`docs/src/api/phenomenology/Scalings.md`
    line 33)
  - PAGE: api / phenomenology / Spectra, `## References`
    (`docs/src/api/phenomenology/Spectra.md` line 67)
  - PAGE: api / phenomenology / StructureFunctions, `## References`
    (`docs/src/api/phenomenology/StructureFunctions.md` line 27)
  - Quote (identical in all three): "A few works are cited in `ARCHITECTURE.md` as well, where the
    DNS side needs them — the leaf's independence means it does not *rely* on that list…"
- **Contradicts:** CLAUDE.md, Documentation policy: "No dead references on the user-facing surface…
  never cite an `ARCHITECTURE.md` section number (§4.5), a decision-log entry, or a repo path
  (`src/…`, `inspiration/…`) there. A cross-reference adds depth one hop away; it never carries a
  fact the reader needs."
- **Description:** All three `Phenomenology` submodule pages name the file `ARCHITECTURE.md` by
  name on their public "References" section — a repo path a reader at the API page (or the extracted
  manuscript) cannot follow. The rule's own named example is a *section number* in that same file;
  naming the bare file is the same class of dead reference on the same user-facing surface. This sits
  in tension with `Phenomenology`'s own "extraction-bound" promise ("a reader never has to leave the
  page for them," stated in the very same sentence) — the aside about `ARCHITECTURE.md` is exactly
  the kind of leave-the-page dependency that promise disclaims.
- **Resolution hint:** Drop the `ARCHITECTURE.md` mention (the preceding sentence already states the
  page is self-contained), or replace it with a reason that needs no external file name.
