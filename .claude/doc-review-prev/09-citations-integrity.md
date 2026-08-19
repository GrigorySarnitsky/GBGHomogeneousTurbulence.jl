# Scientific-integrity & citations audit

Hat: citations-integrity. Reviewed the full rendered manuscript (`ARCHITECTURE.md`, `notation.md`,
`observables_cache.md`, `phenomenology.md`, and every `api/*` page including the three
`Phenomenology` submodule pages) against the ARCHITECTURE.md `§References` list and each
`Phenomenology` page's own scoped `## References` section.

**Overall assessment.** The corpus's citation discipline is unusually strong — every inline
author-year cite in the DNS-core pages (Betchov, Williamson, Orszag, Orszag & Patterson, Patterson
& Orszag, Rogallo, Hou & Li, Cichowlas et al., Chollet & Lesieur, Eswaran & Pope, Li et al.,
Lundgren, Bussi/Donadio/Parrinello, Pope, Mori, Zwanzig, Morrison, Öttinger) has a matching
`§References` entry, every entry is cited somewhere, and every checked inline docstring copy is
verbatim-consistent with its `§References` entry (title, journal, volume/page, DOI). No orphaned or
dangling citations were found in `ARCHITECTURE.md`. The `Phenomenology` leaf's per-page `##
References` sections are internally consistent with their own docstrings and explicitly, correctly
scoped (they state they exclude inline comparison/coefficient citations, matching CLAUDE.md's
stated exemption for the extraction-bound leaf). No overclaiming language ("optimal", "the
largest/first", "state of the art", "provably") was found applied to a claim the docs do not
substantiate; every "exact" / "allocation-free" claim checked is backed by an explicit derivation or
by the audited-suite claims described in the same document. Consequently this hat's findings are
few and modest.

---

## Finding 1 — "Berendsen thermostat" is named repeatedly but its own paper is never cited

- **Type:** citation
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: api / Forcing, `BandRescaling`: *"the Berendsen-thermostat limit of stochastic velocity
    rescaling: the molecular-dynamics thermostat that multiplies every velocity by one factor each
    step … (Bussi, Donadio & Parrinello 2007 — Canonical sampling through velocity rescaling …)"*
  - PAGE: architecture, decision log (2026-07): *"`BandRescaling` carries the Berendsen-class
    caveat — a deterministic clamp has no conserved quantity … (Bussi, Donadio & Parrinello 2007)."*
  - PAGE: architecture, §References: only "Bussi, G., Donadio, D. & Parrinello, M. (2007)…" is
    listed; no Berendsen entry exists anywhere in the manuscript.
- **Description:** The docs name a specific, well-known published method — "the Berendsen
  thermostat" (Berendsen, Postma, van Gunsteren, DiNola & Haak, *J. Chem. Phys.* **81**, 3684,
  1984) — by its eponym at least twice (once in a docstring, once in the decision log), which under
  CLAUDE.md's own rule ("an inline citation for a named / published method … may open the identity
  sentence when the citation *names* the method") is exactly the class of claim that earns its own
  citation. Only the 2007 follow-up paper that critiques the Berendsen scheme is cited; Berendsen's
  own foundational paper is never listed, even though it is an accessible, standard MD reference.
  The 2007 citation does substantively support the specific properties claimed (no conserved
  quantity, no well-defined ensemble), which limits the severity, but the named method itself is
  left without its own provenance.
- **Contradicts:** n/a (omission, not a contradiction).

## Finding 2 — Ambiguous dual attribution of the Kolmogorov constant's numeric value

- **Type:** citation
- **Severity:** nit
- **Confidence:** medium
- **Locations:**
  - PAGE: api / phenomenology / Scalings, `Sreenivasan1995`: *"Reviewing the experimental and
    numerical record, Sreenivasan (1995) found it close to universal, a reliable estimate being
    $C_K = 1.5 \pm 0.1$ (the default; Sagaut & Cambon 2018)…"*
- **Description:** The sentence attributes the finding ("close to universal") to Sreenivasan (1995)
  but then parenthetically appends "Sagaut & Cambon 2018" immediately after the specific numeric
  value $1.5\pm0.1$, with no word (e.g. "as tabulated in", "see also") distinguishing whether the
  ±0.1 uncertainty is Sreenivasan's own figure or Sagaut & Cambon's later restatement of it. A
  reader cannot tell which of the two sources the quoted number is drawn from.
- **Contradicts:** n/a — an ambiguity, not a stated contradiction.

## Finding 3 — Inconsistent DOI treatment for comparison citations within one docstring

- **Type:** citation
- **Severity:** nit
- **Confidence:** low
- **Locations:**
  - PAGE: api / phenomenology / Spectra, `ExponentialDissipation`: *"…the form the triadic spectral
    closures … consistently predict (Kaneda 1993; Sagaut & Cambon 2018)."* — no DOI or journal for
    either.
  - Same docstring, next sentence: *"…fit $\beta \approx 6.7$ (Khurshid, Donzis & Sreenivasan 2018,
    doi:10.1103/PhysRevFluids.3.082601; consistent with Chen et al. 1993,
    doi:10.1103/PhysRevLett.70.3051, $\beta \approx 7.1$)…"* — full DOIs given.
- **Description:** Within the same docstring, some comparison citations carry a full DOI and others
  (Kaneda 1993, Sagaut & Cambon 2018) carry none, with no stated rule for which comparison citations
  earn the fuller treatment. The page's own `## References` note explains why *none* of these need a
  formal `§References` entry, but does not explain the inline DOI/no-DOI split. Minor and unlikely
  to mislead a reader, but an inconsistency in citation completeness within one surface.
- **Contradicts:** n/a — internal formatting inconsistency, not a factual contradiction.

---

## Not flagged (checked and found consistent)

- Every `ARCHITECTURE.md §References` entry is cited inline at least once, and every inline
  author-year cite in `ARCHITECTURE.md` and the `api/*` DNS-core pages has a matching entry — no
  orphans in either direction.
- `Patterson & Orszag (1971)` vs `Orszag & Patterson (1972)` vs `Orszag (1971)` — three distinct,
  correctly-attributed works by overlapping authors in different years/orders; none conflated.
- `Williamson (1980)`'s docstring copy (title, journal, volume, pages, DOI) is verbatim-consistent
  with its `§References` entry; the entry's own honest caveat about the "RKW3" coefficients'
  informal (Wray 1986, unpublished) provenance is disclosed in the reference annotation rather than
  cited directly, correctly honoring "never cite an inaccessible source."
- `Betchov (1956)`, `Hou & Li (2007)`, `Patterson & Orszag (1971)` / `Rogallo (1981)` (`PhaseShift`),
  `Bussi, Donadio & Parrinello (2007)` (`BandRescaling`'s DOI-bearing citation), and `Lundgren
  (2003)` (`Linear`) are all verbatim-consistent between their docstring and `§References` copies.
- `Kolmogorov (1962)` / `Obukhov (1962)` page numbers (13, 82 vs 13, 77) are historically accurate
  (companion papers in the same *J. Fluid Mech.* issue), not a transcription error.
- No overclaiming language ("optimal", "the largest/first", "state of the art", "guarantees") was
  found applied beyond what the surrounding text substantiates.
