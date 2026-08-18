# Doc-policy hat — findings

Hat brief: does each docstring obey THIS package's written documentation policy (CLAUDE.md
"Documentation policy" and "Doc-edit checklist")? Module docstring = map (no formulas); function
docstring = home in the prescribed order; type docstring = constructor-first with demoted `# Fields`;
f/f! one-home; cross-reference discipline; no dead references. Substrate: CLAUDE.md, the rendered
manuscript, and `src/*.jl` (this hat is explicitly granted source access, which let several checks —
`@ref` link-uniqueness, self-reference, argument enumeration — be verified directly against the
docstring markup rather than only the rendered text).

Overall the corpus is disciplined: an automated sweep of every docstring in `src/` found **zero**
duplicate `@ref` targets within a single docstring and **zero** self-referencing `@ref`s anywhere —
the cross-reference "link once, never the docstring's own binding" rule is cleanly observed
throughout. Argument enumeration is likewise thorough everywhere checked. The findings below are the
exceptions to that otherwise-clean record.

---

## Finding 1 — `Phenomenology.Spectra`'s module docstring embeds a formula, violating "map, no formulas"

- **Type:** format
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: api / phenomenology / Spectra — module docstring: *"A velocity model is composed: an
    inertial-range core $C_K\varepsilon^{2/3}\kappa^{-5/3}$ times a large-scale roll-off and a
    dissipation-range roll-off, each swappable."*
  - Source: `src/phenomenology/Spectra.jl:6` — `` inertial-range core ``\\C_K\\varepsilon^{2/3}\\kappa^{-5/3}`` times a large-scale roll-off ``.
- **Contradicts:** CLAUDE.md, Documentation policy, "Two-tier structure": *"Module docstring = map. …
  then a **linked one-liner per operation, and no formulas**."* The sibling `Generator` module
  docstring states and keeps the rule explicitly — *"Its contents (each formula lives in the
  operation's own docstring)"* (`src/Generator.jl:15`) — with zero formulas in the module body, and
  every other module docstring in the corpus (`Cache`, `Forcing`, `Observables`, `Particles`,
  `Propagator`, `SimulationDomain`, `State`, `Phenomenology`, `Scalings`, `StructureFunctions`) uses
  bare notation only ($E(\kappa)$, $C_\varepsilon$, $D_{L\dots}(r)$ …) with no computed expression.
  `Spectra`'s module docstring is the one exception: $C_K\varepsilon^{2/3}\kappa^{-5/3}$ is a genuine
  formula (a coefficient times two exponentiated physical quantities), not a symbol binding — it
  belongs in `ModelSpectrum`'s docstring, which already carries the full composed formula.
- **Description:** The house rule is explicit and is followed everywhere else in the corpus, making
  this a clean, isolated miss rather than a matter of interpretation. Fix is mechanical: drop the
  inline formula from the module map and either state the shape in words ("an inertial core times two
  swappable roll-offs") or link to `ModelSpectrum`, which already owns it.

---

## Finding 2 — `Pope2000` duplicates `ModelSpectrum`'s generic formula verbatim, where its sibling presets substitute the specific form

- **Type:** format
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - Source: `src/phenomenology/Spectra.jl:247-251` (`ModelSpectrum`) — `` E(\kappa) = C_K \varepsilon^{2/3} \kappa^{-5/3} f_L(\kappa L_{11}) f_\eta(\kappa\eta), `` (the generic, unsubstituted composed form — this type's home formula).
  - Source: `src/phenomenology/Spectra.jl:297-299` (`Pope2000`) — the *exact same* unsubstituted
    formula, `` E(\kappa) = C_K \varepsilon^{2/3} \kappa^{-5/3} f_L(\kappa L_{11}) f_\eta(\kappa\eta). ``
- **Contradicts:** `VonKarman1948` (`src/phenomenology/Spectra.jl:323-326`) and `Pao1965`
  (`:349-352`), whose docstrings instead substitute their own roll-off's closed form into the
  composed spectrum — e.g. `VonKarman1948`: `` E(\kappa) = C_K\varepsilon^{2/3}\kappa^{-5/3}\bigl(\tfrac{(\kappa L_{11})^2}{(\kappa L_{11})^2+c_L}\bigr)^{17/6} ``,
  a genuinely more specific, informative formula than the generic one.
- **Description:** CLAUDE.md's one-concept-one-home rule (stated for the `f`/`f!` pair, but its
  spirit is "no second copy of the formula … that drifts across the pair") is best served by each
  preset either linking `ModelSpectrum` for the generic shape or, like its two siblings, substituting
  its own closed form. `Pope2000` does neither: it repeats `ModelSpectrum`'s unsubstituted formula
  character-for-character, adding no information the reader doesn't already have from `ModelSpectrum`
  — a redundant second copy, and an internal inconsistency against the very next two docstrings on the
  same page.
- **Resolution hint:** Either substitute Pope's `PopeLargeScale`/`PopeDissipation` closed forms into
  the displayed equation (matching `VonKarman1948`/`Pao1965`), or drop the repeated equation and link
  `ModelSpectrum` for the generic shape.

---

## Finding 3 — Named-method citations are placed in the identity sentence, ahead of the formula, contrary to the stated home-docstring order

- **Type:** format
- **Severity:** minor
- **Confidence:** low
- **Locations:**
  - PAGE: api / Propagator — `IFLowStorageRK3`: *"Integrating-factor third-order low-storage
    Runge–Kutta, 2N-storage — **Williamson (1980)**, Low-storage Runge–Kutta schemes …"* — the
    citation opens the docstring; the formula (the three-stage update) follows several sentences later.
  - PAGE: api / SimulationDomain — `HouLi`: *"The smooth spectral filter of **Hou & Li (2007)** …
    Transfer function $\exp(-\texttt{strength}(\kappa/\kappa_{\mathrm{Ny}})^{\texttt{order}})$."* —
    same pattern.
  - PAGE: api / SimulationDomain — `PhaseShift`: *"Phase-shift dealiasing — **Patterson & Orszag
    (1971)** … combined with the spherical truncation of **Rogallo (1981)** …"* — citation leads.
- **Contradicts:** CLAUDE.md, Documentation policy, function-docstring order: *"(5) the
  physical-meaning-first formula … (6) an inline citation for a named / published method."* — citation
  is listed last, after the formula.
- **Description:** This placement is completely consistent across every named-method docstring in the
  corpus (also `TwoThirds`/Orszag 1971, `Linear`/Lundgren 2003, `BandRescaling`'s Berendsen caveat,
  every `Phenomenology` preset), which suggests it is a deliberate, uniform convention — the citation
  reads as part of *naming* the method ("the X of Author (Year)"), not a trailing appendix — rather
  than scattered drift. Flagged at low confidence because a strict reading of the stated order
  disagrees with essentially the whole corpus; if the convention is intentional, CLAUDE.md's ordering
  list arguably needs a one-line carve-out rather than every docstring needing rewriting.
