# Style / Copy-Edit Panel — Technical Copy-Editor Hat

Findings from a fresh-eyed pass over the rendered manuscript and the raw built HTML, checking
internal uniformity of notation, docstring skeleton, headings, citation format, register, and
grammar. Ranked most-severe first.

---

## Finding 1 — Hyphenated compound splits into two words in rendered HTML ("deposit- completeness")

- **Type:** typesetting
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: observables_cache, §3.2 "What is not built" — rendered text reads "the seeding deposit
    at construction, the deposit- completeness check, and the slot=register merge."
  - PAGE: architecture, §4.7 "SimulationRun" — rendered text reads "the new sample, and the
    deposit- completeness check."
  - Contrast: the same page's own §11 decision log renders the term correctly twice as
    "deposit-completeness check" (no stray space).
- **Description:** In both `docs/src/observables_cache.md` (line 418) and `docs/src/architecture.md`
  (line 457), the compound word "deposit-completeness" is broken across a source line right after
  the hyphen: `...the deposit-\ncompleteness check...`. Markdown joins the wrapped line with a
  space, so the *rendered* HTML literally shows "deposit- completeness" — a hyphen dangling before
  a space, reading as two separate words. Confirmed in the built HTML
  (`docs/build/observables_cache/index.html`, `docs/build/architecture/index.html`): grepping the
  phrase in `architecture/index.html` finds it broken once and correctly hyphenated twice elsewhere
  on the same page, so the same term renders two different ways within one document.
- **Resolution hint:** rejoin the hyphen and the following word onto one source line (or write the
  whole compound after the wrap point) in both files.

---

## Finding 2 — Citation punctuation split: "Year, Title" vs "Year — Title"

- **Type:** citation
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: api / Observables, `derivative_skewness`: "(Betchov 1956 — An inequality concerning the
    production of vorticity in isotropic turbulence, J. Fluid Mech. 1(5), 497–504, doi:...)"
  - PAGE: api / Forcing, `Linear`: "a band-limited variant of Lundgren 2003 — CTR Annual Research
    Briefs, which carries no DOI"
  - PAGE: api / Forcing, `BandRescaling`: "(Bussi, Donadio & Parrinello 2007 — Canonical sampling
    through velocity rescaling, J. Chem. Phys. 126, 014101, doi:...)"
  - Contrasts with the corpus majority, e.g. same page: "(Berendsen, Postma, van Gunsteren, DiNola
    & Haak 1984, Molecular dynamics with coupling to an external bath, J. Chem. Phys. 81, 3684,
    doi:...)" — comma, not em dash, before the title.
- **Contradicts:** the majority pattern across the corpus is "Author Year, *Title*, Journal …" —
  confirmed also for Cambon 2018, Taylor 1935, Sreenivasan 1996/1998/2018, Qian 1984, Patterson
  1972, Orszag 1971, Kraichnan 1959 (all comma-joined). Only the three citations above use
  "Author Year — *Title*, …" instead.
- **Description:** Within the very same `BandRescaling` docstring, two adjacent full inline
  citations use two different punctuation marks between the year and the title (comma for
  Berendsen 1984, em dash for Bussi 2007) with no evident reason for the difference. The same
  em-dash variant recurs for Betchov 1956 and Lundgren 2003 elsewhere, against a clear
  comma-joined majority everywhere else.
- **Resolution hint:** normalize all three em-dash citations to the comma-joined house form.

---

## Finding 3 — Redundant, near-verbatim repeated sentence in the same admonition

- **Type:** clarity
- **Severity:** minor
- **Confidence:** high
- **Locations:** PAGE: api / Propagator, `recommended_cfl`, admonition "The IFRK2 margin does not
  know the viscosity": "...the practical course at high Reynolds number is to prefer
  `IFLowStorageRK3`, whose ceiling has no such dependence, or to pass an explicit `cfl` and verify
  it against a run that holds its energy. `IFLowStorageRK3`'s ceiling carries no such dependence."
- **Description:** The same claim — that `IFLowStorageRK3`'s CFL ceiling has no viscosity
  dependence — is made twice in immediate succession, once inside the "prefer `IFLowStorageRK3`"
  clause and again as a trailing standalone sentence restating it almost word for word. Reads as
  an editing leftover (two drafts of the closing line merged) rather than a deliberate emphasis.
  Confirmed verbatim in `src/Propagator.jl` lines 555–556.
- **Resolution hint:** drop the trailing repeated sentence.

---

## Finding 4 — Missing subsection heading breaks the page's one-heading-per-group pattern

- **Type:** organization
- **Severity:** minor
- **Confidence:** high
- **Locations:** PAGE: api / SimulationDomain, between the `PhaseShift` docstring and the
  `max_wavenumber` docstring: "The dealiasing cutoff it sets — the dealiasing cutoff — the highest
  wavenumber the run treats as resolved signal, and the resolution criterion κ_max η a run is
  built to meet." followed directly by the `max_wavenumber` `@docs` block, with no `##` heading
  above it.
- **Contradicts:** every other docstring group on the same page opens with its own `##` heading
  ("The discretized box", "Dealiasing strategies", "Scratch-field allocators", "Band truncation")
  and a one- or two-sentence blurb before the `@docs` block; `max_wavenumber` is the only group on
  the page (and one of very few across the whole API section) with a blurb but no heading, so it
  renders folded into "Dealiasing strategies" and is absent from that page's own contents list.
- **Description:** `docs/src/api/SimulationDomain.md` line 30 also duplicates the phrase "the
  dealiasing cutoff" back-to-back ("The dealiasing cutoff it sets — the dealiasing cutoff — the
  highest wavenumber…"), reading like a heading ("## The dealiasing cutoff") that was deleted and
  left its own wording stranded in the blurb.
- **Resolution hint:** add a `## Dealiasing cutoff` (or similar) heading above this blurb, and
  trim the doubled phrase.

---

## Finding 5 — Two distinct citations merged into one bulleted reference line

- **Type:** citation
- **Severity:** minor
- **Confidence:** medium
- **Locations:** PAGE: api / phenomenology / Spectra, "## References": "Obukhov (1949), Izv. Akad.
  Nauk SSSR, Ser. Geogr. Geofiz. 13, 58 (no DOI) / Corrsin (1951), J. Appl. Phys. 22, 469.
  doi:10.1063/1.1699986" — one bullet, two full author/year/journal/doi citations joined by "/".
- **Contradicts:** `CLAUDE.md`'s house rule, "A reference block of two or more citations is a
  bullet list — one citation per line — never a semicolon-joined paragraph"; and the corpus's own
  practice elsewhere of giving co-cited twin papers separate bullets, e.g. `architecture.md`'s
  `## References` lists "Mori, H. (1965)…" and "Zwanzig, R. (1973)…" — the equally paired
  foundational Mori–Zwanzig papers — as two separate bullets, not one joined line.
- **Description:** The dual-eponym Obukhov–Corrsin law is one `Reference` value whose `citation`
  string (`src/phenomenology/Spectra.jl` line 407) concatenates both papers with `" / "`; this
  string is reused verbatim in the page's generated bibliography, so the bibliography ends up with
  one bullet holding two independent, fully-cited works, unlike every other bullet on the three
  Phenomenology reference pages (Scalings, Spectra, StructureFunctions), which hold exactly one
  citation each.
- **Resolution hint:** if the `Reference` type is to stay one-citation-per-law, consider whether
  the joined string is acceptable as an exception for genuinely joint attributions (the docstring
  itself already treats the "1949" handle as one law with two independent discoverers), or split
  the bibliography rendering to break `" / "`-joined citations onto separate bullet lines.

---

## Finding 6 — Phenomenology "## References" bibliography uses the labelled DOI-link form, not the bare-autolink form the corpus's other bibliography section uses

- **Type:** citation
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: architecture, "## References": "...*J. Fluid Mech.* **1**(5), 497–504.
    <https://doi.org/10.1017/S0022112056000317>" (bare autolink).
  - PAGE: api / phenomenology / Scalings, "## References": "Sreenivasan (1998), Phys. Fluids 10,
    528. doi:10.1063/1.869575" — rendered in the built HTML as
    `<a href="https://doi.org/10.1063/1.869575">doi:10.1063/1.869575</a>` (labelled link, the
    inline-citation form).
  - Same pattern in the Spectra and StructureFunctions "## References" sections.
- **Contradicts:** the already-adjudicated ruling that "a `§References` entry ends in a bare
  autolink (bibliography style); an inline docstring cite uses the labelled `doi:10.…` format. One
  form per surface." The three Phenomenology "## References" pages are structurally the same kind
  of end-of-page bibliography as `ARCHITECTURE.md`'s `§References`, yet render with the *inline*
  labelled-link form throughout, because their bullet text is generated verbatim from the same
  `Reference.citation` string used inline.
- **Description:** This is a distinct case from the already-settled "two DOI link formats" finding
  (which contrasted `ARCHITECTURE.md`'s bibliography against inline docstring citations): here, two
  bibliography-role sections in the same corpus — one in the DNS core, three in the extraction-bound
  leaf — disagree on which of the two sanctioned forms a bibliography entry uses.
- **Resolution hint:** low priority — may be an accepted consequence of the leaf's
  reuse-the-citation-string design; worth a decision either way rather than leaving it unremarked.

---

## Finding 7 — Admonition title runs directly into its own body when read as flat text (extraction artifact, verified benign)

- **Type:** typesetting
- **Severity:** nit
- **Confidence:** high
- **Locations:** e.g. PAGE: Home, "Work in progressThe package is being built…"; PAGE: api / Cache,
  "A cached array is the next iteration's scratchA slot is also the array…".
- **Description:** Checked directly against the built HTML (`docs/build/index.html`,
  `docs/build/api/Cache/index.html`): each of these renders correctly as a proper `admonition-header`
  followed by a separate `admonition-body` — the manuscript's flat-text extraction simply drops the
  whitespace between the two. **Not a rendering defect**; recorded here only so a later pass does
  not re-flag the pattern. No fix needed.

---

## Notes on what did *not* turn up defects

Checked and found uniform across the corpus: bold-italic vector notation (no stray `\mathbf`),
upright imaginary unit, subscripted partials (no bare `\partial_i`), `\varphi` (never `\theta`),
constructor-first type docstrings, the `Arguments`/`Fields` skeleton, the `!!! warning`/custom-title
admonition convention, register (no "knob"/"tweak"/informal tone found), Markdown table rendering
(all render as proper `<table>` elements, no literal-pipe fallback), and KaTeX math spans (all
render as `<span>$…$</span>`, none literal).
