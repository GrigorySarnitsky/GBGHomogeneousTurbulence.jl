# Hat: cross-package parity reviewer (IT vs PF)

Comparing GBGIsotropicTurbulence's rendered manuscript + `CLAUDE.md` against sibling
`GBGPeriodicFields`'s `CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/src/`, and a representative
`src/` docstring sample. Findings already dispositioned in `.claude/doc-review-adjudicated.md`
(the conditional admonition-title rule, the economy/full-on-request cost modes, IT's
constructor-first type-docstring template, the two-DOI-format internal split) are **not**
repeated here.

---

## Finding 1 — Citation architecture: PF uses one verbatim-identical link format on both
surfaces; IT deliberately splits into two, and the split adds a class of drift PF's choice avoids

- **type**: citation
- **severity**: major
- **confidence**: high
- **locations**:
  - IT `CLAUDE.md`: "a `§References` entry ends in a bare autolink `<https://doi.org/…>`
    (bibliography style), an inline docstring cite uses the labelled
    `[doi:10.…](https://doi.org/…)`; the same identifier percent-encodes differently in the
    two, which is why `doi_crosscheck.py` compares them decoded."
  - IT manuscript, PAGE: architecture, §References: `- Betchov, R. (1956). An inequality
    concerning the production of vorticity in isotropic turbulence. J. Fluid Mech. 1(5),
    497–504. https://doi.org/10.1017/S0022112056000317 (…)` — plain-text title, bare trailing
    URL, no hyperlink on the title at all.
  - PF `docs/ARCHITECTURE.md` §References (via `docs/src/api.md`, itself sourced from
    `CLAUDE.md`'s citation policy): "- C. C. Lalescu, B. Teaca, D. Carati,
    [*Implementation of high order spline interpolations for tracking test particles in
    discretized fields*](https://doi.org/10.1016/j.jcp.2010.04.006), J. Comput. Phys.
    **229**(17) (2010) 5862–5869." — the *title itself* is the hyperlink, in the bibliography.
  - PF `CLAUDE.md` citation policy: "Every reference carries a clickable DOI on its title —
    `[*Title*](https://doi.org/…)`… verbatim-identical in the §References list and every
    inline docstring copy."
- **contradicts**: PF's policy is *one* format used identically on both surfaces (bibliography
  and inline docstring); IT's policy is *two* formats, one per surface, whose same DOI
  percent-encodes differently between them — a distinction PF's single-format choice never
  needs and IT had to build a dedicated script (`doi_crosscheck.py`) to police.
- **description**: This is not the previously-adjudicated question of whether IT's own two
  formats contradict each other (they don't, and that finding is closed). It is a new
  comparison: PF's citation architecture is simpler and self-verifying by construction (one
  format, so nothing to cross-check); IT's is a genuine architectural divergence with no
  stated physics-vs-non-physics rationale — it looks like an independent design choice rather
  than an adaptation forced by IT being the physics package. Worth a decision on which to keep,
  or record why IT's costs (a whole crosscheck script) are worth the two-surface split.

## Finding 2 — IT's inline citation link text is the bare DOI, never the paper's title

- **type**: citation
- **severity**: major
- **confidence**: high
- **locations**:
  - IT manuscript (Forcing page): "the constant-$k$ controller of Bassenne, Urzay, Park & Moin
    (2016, doi:10.1063/1.4944629)." — the rendered link text is the numeric DOI string itself.
  - PF `src/Interpolation.jl`: "Reference: C. C. Lalescu, B. Teaca, D. Carati,
    [*Implementation of high order spline interpolations for tracking test particles in
    discretized fields*](https://doi.org/10.1016/j.jcp.2010.04.006), J. Comput. Phys. …" — the
    rendered link text is the paper's actual title.
- **contradicts**: PF's rule: "Every reference carries a clickable DOI **on its title**" (the
  title is what a reader sees and clicks); IT's inline convention instead surfaces "doi:10.xxxx"
  as the only clickable text, so a REPL/rendered reader never sees the paper's name at the
  citation site, only at the (separately-formatted) bibliography entry.
- **description**: A readability regression versus PF's convention with no domain-driven
  justification — physics citations are exactly the citations where a reader benefits most from
  seeing the paper's name at the point of use (e.g. "the smooth spectral filter of Hou & Li
  (2007), doi:10.1016/j.jcp.2007.04.014" tells a reader nothing they didn't already get from the
  author–year; the DOI adds no information until followed).

## Finding 3 — PF's author-count truncation rule ("≤3 named, 4+ → First et al.") is absent
from IT's rulebook, and IT's corpus routinely names 4–9 authors in running prose

- **type**: citation
- **severity**: major
- **confidence**: medium
- **locations**:
  - PF `CLAUDE.md`: "Name **up to three** authors (`A & B`; `A, B & C`); **four or more →
    `First et al.`** — except keep enough surnames to disambiguate two works that would
    otherwise collide."
  - IT manuscript (Forcing page): "the mechanism is the one molecular dynamics settled on…
    (Nosé 1984 …; Hoover 1985 …), and gain-limited relaxation… is Berendsen weak coupling
    (Berendsen et al. 1984 …)" — but elsewhere the SAME work is spelled out in full: IT
    §References gives "Berendsen, H. J. C., Postma, J. P. M., van Gunsteren, W. F., DiNola, A.
    & Haak, J. R. (1984)" (5 authors) and the constant-$k$ controller is introduced in-text as
    "Bassenne, Urzay, Park & Moin (2016, doi:10.1063/1.4944629)" — 4 full surnames, not
    truncated to "Bassenne et al."
  - IT §References (Observables page): "Li, Y., Perlman, E., Wan, M., Yang, Y., Meneveau, C.,
    Burns, R., Chen, S., Szalay, A. & Eyink, G. (2008)." — 9 authors listed in full.
- **contradicts**: IT's `CLAUDE.md` states no author-count rule at all for in-text citations
  (its citation-policy paragraph covers link format and physical-meaning-first ordering, not
  author truncation); PF's rule would truncate the 4-author Bassenne et al. in-text mention and
  is silent on whether the full bibliography entry is exempt — IT's practice is internally
  inconsistent between "Berendsen et al." (truncated) and "Bassenne, Urzay, Park & Moin" (not
  truncated) at the same author count, four.
- **description**: Either IT never adopted PF's truncation convention (a plausible, unstated
  adaptation, since IT's citations are denser and more numerous than PF's), or it partially did
  and drifted. Given the corpus shows both a truncated 4-author case and an untruncated one,
  this reads as an inconsistency worth a decision either way, not a clean adaptation.

## Finding 4 — PF's numeric arguments-shape threshold ("≥3 args or any keyword → bulleted
form") is written down as a rule; IT's corpus visibly follows the identical threshold but
`CLAUDE.md` never states it

- **type**: format
- **severity**: minor
- **confidence**: medium
- **locations**:
  - PF `CLAUDE.md`: "**(1) Arguments.** A docstring documenting **three or more arguments, or
    any keyword argument**, uses the bulleted form led by `The arguments are:`; with fewer, the
    arguments are bound in running prose… Never mix the two within one docstring." (user-decided
    2026-07-24 shape rule)
  - IT manuscript (Observables page), `derivative_skewness(û, domain)` — 2 positional args,
    documented entirely in running prose, no bullets.
  - IT manuscript (Observables page), the kinetic-energy-and-dissipation function (3 args:
    `û`, `domain`, `viscosity`) — documented as "The arguments are: - `û` — … - `domain` — …
    - `viscosity` — …", the bulleted form.
- **description**: The IT corpus already obeys PF's exact numeric threshold, but IT's
  `CLAUDE.md` docstring-template section states only "(3) each argument (positional and
  keyword) and its effect" with no bullets-vs-prose rule or count. An unwritten-but-practiced
  convention is exactly the kind of thing that drifts on the next docstring pass with no rule to
  check it against; writing PF's rule into IT's `CLAUDE.md` verbatim (adapted) would close the
  gap between practice and policy.

## Finding 5 — IT's "Known weaknesses — self-guards" section has no PF counterpart

- **type**: organization
- **severity**: minor
- **confidence**: high
- **locations**:
  - IT `CLAUDE.md` §"Known weaknesses — self-guards" (four documented recurring failure
    patterns: circular self-justification, asserting a shape instead of expanding it, treating
    what is in place as evidence it should be so, fixing the instance not the class — each with
    dated, named instances).
  - PF `CLAUDE.md` section headers (`Modules and wiring`, `Core invariants`, `Code generation
    rules`, `Documentation policy`, `Style`, `Verification workflow`, `Current state and
    roadmap`, `Planned directions`, `Working agreements`) — no analogous section anywhere.
- **description**: Not a defect in IT — this looks like a genuinely valuable IT-side invention
  (a track record of self-caught failure modes with instances) that PF's rulebook lacks
  entirely. Worth naming per the brief's item 5 as a candidate reverse-transfer to PF, not IT
  work to do.

## Finding 6 — IT's "a citation may open the identity sentence" clause has no PF counterpart

- **type**: format
- **severity**: nit
- **confidence**: medium
- **locations**:
  - IT `CLAUDE.md`: "an inline citation for a **named / published** method — which may open the
    identity sentence when the citation *names* the method (\"the smooth spectral filter of
    Hou & Li (2007) …\"), the corpus-wide convention."
  - PF `CLAUDE.md` docstring-home order: "(6) an inline citation for a **named/published**
    method (verbatim-consistent with `ARCHITECTURE.md` §References)… **(7)** cross-links" —
    citation is step 6 of 7, after the formula (step 5); no exception is stated for a citation
    opening the identity sentence (step 1).
- **description**: Already adjudicated that this is *not* an inversion of IT's own
  physical-meaning-first rule (round 2026-08-18). The new observation here is narrower: PF's
  rulebook does not carry the equivalent permission at all. Given how many IT docstrings open on
  a named method (`HouLi`, `AdamsBashforth`, `IFLowStorageRK3`, `VarianceController`, …), this
  reads as a reasonable IT-side refinement worth naming as a candidate reverse-transfer, not a
  defect — flagged at nit severity since it is additive, not contradictory.

## Finding 7 — Wavenumber glyph remapping (IT: bold `κ` vector / plain `κ` magnitude; PF:
plain `k` vector / distinct `κ` shell-radius) — noted, judged an adaptation, not a defect

- **type**: other
- **severity**: nit
- **confidence**: low
- **locations**:
  - PF `docs/src/notation.md`: "`k` | a wavenumber vector (`k_a` is its `a`-th component,
    `|k|` its magnitude) |"; "The worked turbulence example sets the wavenumber vector bold, as
    `\mathbf{k}`, because it follows the turbulence convention in which italic `k` is the
    turbulent kinetic energy. That override is **local to the example**."
  - IT manuscript (notation page): "Wavenumber clash | `\boldsymbol{\kappa}` / `\kappa` / `k` |
    Kept distinct: bold `\boldsymbol{\kappa}` is the wavenumber vector, `\kappa` its magnitude…
    italic scalar `k` is the turbulent kinetic energy."
- **description**: IT has promoted PF's own documented *local override* (the worked example's
  bold `\mathbf{k}` for the turbulence reading) into its *package-wide default*, and renamed the
  vector glyph from `k` to `\boldsymbol{\kappa}` to free plain `k` for kinetic energy. This is
  exactly the kind of physics-driven necessity PF's own comment anticipates, so it reads as a
  correct, well-motivated adaptation rather than an unexplained divergence — recorded here only
  because it was a candidate worth checking, not because it needs a decision.

---

**Candidates considered beyond the seven reported:** PF's `\mathbf`/`\boldsymbol` vector
convention vs IT's (adaptation, PF has no concrete vector *quantities* to bold); PF's notation
page having an explicit "Differential" (`\mathrm dx`) glossary row that IT's notation page omits
(low value — IT's page states up front it inherits field/spectral conventions from PF); PF's
"Consent gate" verification-workflow paragraph vs IT's shorter one (likely subsumed by the
already-adjudicated cost-mode disposition, not re-flagged); PF's "not citations" eponym-name
carve-out vs no equivalent explicit IT statement (narrow, already covered in spirit by the
adjudicated `CatmullRom`-bare finding); module-docstring map shape (both packages'
practice matches their own stated templates, no divergence found); API-page grouping principle
(IT groups by diagnostic/physical family, PF by math family — a reasonable one-for-one
adaptation, not a divergence).
