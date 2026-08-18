# Style / Copy-Editor hat — findings

Fresh-eyed technical copy-edit for internal uniformity across the rendered GBGIsotropicTurbulence
docs, cross-checked against the raw built HTML under `docs/build`. Ranked most-severe first.

---

## 1. Admonition titles do not render Markdown code spans — literal backticks shown to the reader

- **Type:** typesetting (silent rendering failure)
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - `docs/build/api/Forcing/index.html` — admonition header renders literally as
    `Which one a run wants depends on what else reads ``k```
  - `docs/build/api/SimulationRun/index.html` — admonition header renders literally as
    `The default holds ``k`` fixed, so ``k`` is not a measurable of the default run`
  - `docs/build/api/Generator/index.html` — admonition header renders literally as
    `` `ω_consumed` is read and then overwritten `` (single backticks also unprocessed)
- **Description:** Custom admonition titles (`!!! note "…"`-style headers) are not run through the
  Markdown/code-span renderer, so a title written with backtick-wrapped code (`` `k` `` or a double
  backtick escape ``` ``k`` ```) shows the literal backtick characters to the reader instead of
  monospaced code. Every other admonition title in the corpus that avoids backticks (`Note`,
  `Warning`, `An epoch is not an iteration number`, `Extraction-bound`, …) renders cleanly — so this
  is a real, avoidable defect in exactly the three titles that tried to use inline code, not a
  universal limitation the corpus already works around. A reader lands on three separate pages and
  sees stray backtick characters in a section header.
- **resolution_hint:** Either rewrite these three titles to avoid inline code (as every other title
  in the corpus already does), or confirm Documenter's admonition-title Markdown support and fix the
  source syntax.

---

## 2. `Phenomenology` submodule References lists render every DOI as dead plain text, while the identical DOIs are live links everywhere else on the very same pages

- **Type:** citation (silent rendering failure)
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - `docs/build/api/phenomenology/Scalings/index.html`, `## References` — `doi:10.1063/1.869575`,
    `doi:10.1063/1.868656`, `doi:10.1080/14685240802376389` all render as bare text, no `<a>` tag.
  - `docs/build/api/phenomenology/Spectra/index.html`, `## References` — all four DOIs (Pope 2000,
    von Kármán 1948, Pao 1965, Corrsin 1951) likewise unlinked.
  - `docs/build/api/phenomenology/StructureFunctions/index.html`, `## References` — all three DOIs
    unlinked.
  - Contrast, on the **same** `Scalings` page, inside the `Li2008` docstring body: `Sreenivasan 1998,
    <a href="https://doi.org/10.1063/1.869575">doi:10.1063/1.869575</a>` — the identical DOI is a
    working hyperlink two sections above the dead one in the reference list.
- **Description:** Every in-body citation across the docstrings (and the whole of
  `ARCHITECTURE.md`'s `## References`) renders its `doi:10.xxxx` text as a clickable link to
  `https://doi.org/10.xxxx`. The three `Phenomenology` submodule pages' trailing `## References`
  lists — generated from each law's `provenance(law).citation` string — render the same DOI text as
  inert plain text. Per the project's own stated policy ("A DOI here has been resolved against the
  registry, never recalled"), a DOI on this surface is meant to be a working citation link; here it
  silently is not, on nine separate entries across three pages.
- **resolution_hint:** Wrap the DOI substring of each `Reference` citation string in a Markdown link
  (or emit it as one at render time), matching the in-body citation convention.

---

## 3. A stray space renders before closing punctuation after a linked/coded term, across five pages

- **Type:** typesetting
- **Severity:** minor
- **Confidence:** high
- **Locations:**
  - `docs/build/api/Cache/index.html` — "…by `record_trajectory_velocity!` **,** both inside
    `advance!`…"
  - `docs/build/api/Forcing/index.html` — "…measured by `dissipation`) and $\varepsilon_\varphi$ for
    the scalar (by `scalar_dissipation` **)**." and "`velocity_forcing` **,** `scalar_forcing`"
  - `docs/build/api/Generator/index.html`, `docs/build/api/Propagator/index.html` — e.g. "a
    `ResolvedFields` **)** the step has just produced", "an `ObservablesCache` **)**. Dispatches on…"
  - `docs/build/api/phenomenology/Phenomenology/index.html` — "a `StructureFunction` **)** at
    separation…"
- **Description:** A visible extra space sits before a closing parenthesis or a comma immediately
  following a linked code term, in at least 16 places across 5 pages (verified directly in the
  rendered HTML: `</code></a> [,.)]`). It reads as a typo to anyone who notices it, and is
  inconsistent with the ~equally common case elsewhere in the same docstrings where the punctuation
  correctly hugs the preceding code span with no gap.
- **resolution_hint:** Drop the trailing space inside the Markdown source immediately before the
  closing bracket/punctuation that follows a `` `code` `` reference.

---

## 4. Prose sentences open with a lowercase code identifier, against the corpus's own stated rule

- **Type:** language-tone
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - `ARCHITECTURE.md` decision log (2026-08, "The consumed operand is named for it…"): "…`ω_consumed`,
    `u_consumed`. **`velocity_rhs!` reads the vorticity and overwrites it**; `scalar_rhs!` reads the
    velocity and overwrites it."
  - `observables_cache.md` §3.1 opens its very first sentence with "**`run!` is the observation-first
    loop**: after every iteration…"
- **Description:** The corpus's own house rule (stated verbatim in the project documentation policy)
  is: "A prose sentence never opens with a lowercase code identifier… lead with a capitalized word…
  (bulleted `` `arg` `` entries and signatures are exempt)." Neither instance above is a bulleted arg
  entry or a signature — one is a plain decision-log sentence, the other opens a numbered
  subsection's very first paragraph — so both read as the flagged typo pattern the rule exists to
  prevent.
- **resolution_hint:** Reword ("The `velocity_rhs!` verb reads…", "A `run!` call is the
  observation-first loop…") or otherwise front-load a capitalized word.

---

## 5. "No DOI" / "no DOI" capitalization is inconsistent between `ARCHITECTURE.md` and the `Phenomenology` reference lists

- **Type:** citation
- **Severity:** nit
- **Confidence:** high
- **Locations:**
  - `ARCHITECTURE.md` References — "(**No** DOI: the 1941 Doklady notes predate the system.)",
    "(**No** DOI; a NASA technical memorandum…)", "(**No** DOI; a Center for Turbulence Research
    brief.)"
  - `docs/build/api/phenomenology/Spectra/index.html` References — "Obukhov (1949)… (**no** DOI)"
  - `docs/build/api/phenomenology/StructureFunctions/index.html` References — "…(**no** DOI, the
    1941 Doklady notes predate the system)", "…(**no** DOI: a 1949 Doklady note)"
- **Description:** The same stock parenthetical ("this citation has no DOI") is capitalized as a
  sentence-initial "No DOI" in one bibliography and left lowercase "no DOI" in the other two,
  despite both playing the identical grammatical role (a self-contained parenthetical aside).
- **resolution_hint:** Pick one capitalization for the parenthetical and use it everywhere.

---

## 6. The stated `@extref` exception for backend/element types is followed in `notation.md` but not in `ARCHITECTURE.md`'s own prose

- **Type:** citation
- **Severity:** minor
- **Confidence:** low
- **Locations:**
  - `docs/build/notation/index.html` — `Float32` in the Numerics table links out to
    `docs.julialang.org`, and `to_physical` links to the `GBGPeriodicFields` API docs.
  - `docs/build/architecture/index.html` — the near-identical sentence "`element_type` fixes the real
    element type (`Float32` or `Float64`) and `array_type` the storage (`Array`, `CuArray`,
    `ROCArray`)" leaves every one of those five type names as plain, unlinked `<code>` — as do all
    other `Float32`/`Float64`/`CuArray`/`to_physical!` mentions throughout `ARCHITECTURE.md`.
- **Description:** The corpus's own cross-referencing rule names "the storage-backend and element
  types (`Array` / `CuArray` / `ROCArray`, `Float32` / `Float64`) and the `GBGPeriodicFields` types"
  as "the deliberate `@extref` exception". `notation.md` applies it; `ARCHITECTURE.md`, discussing the
  identical objects in near-identical wording, never does. This may be a deliberate choice specific
  to the design document (kept link-light on purpose), in which case this is not a defect — flagged
  at low confidence for that reason.
- **resolution_hint:** Either confirm `ARCHITECTURE.md` is intentionally exempt from the `@extref`
  rule, or link the first mention of each type there too, for consistency with `notation.md`.
