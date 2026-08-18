# Doc-review panel — Scientific-integrity & Citations hat

Reviewed the full rendered manuscript (Home, api, architecture, notation, observables_cache,
phenomenology landing + its four API pages, and every `api/*` module page). Checked: author-year
consistency, inline-cite ↔ References-entry matching (both directions), verbatim consistency of a
citation across its repeated appearances, accessibility of cited sources, and overclaim language
("exact", "optimal", "the leanest", …) against what the page substantiates.

Overall the citation apparatus is unusually rigorous — every DOI I could sanity-check against my own
knowledge of the literature (Williamson 1980, Betchov 1956, Patterson & Orszag 1971, Orszag 1971,
Orszag & Patterson 1972, Hou & Li 2007, Cichowlas et al. 2005, Chollet & Lesieur 1981, Eswaran & Pope
1988, Li et al. 2008, Bussi/Donadio/Parrinello 2007, Mori 1965, Zwanzig 1973, Morrison 1986, Öttinger
2005, von Kármán 1948, Pao 1965, Obukhov 1949/Corrsin 1951, Kolmogorov 1941/1962, Obukhov 1962, She &
Lévêque 1994, Yaglon 1949, Lundgren 2002/2003, Sreenivasan 1995/1998/1996, Kaneda et al. 2003, Taylor
1935) looked plausible and internally consistent, and the "no DOI, and here is why" bookkeeping in the
`architecture` page's References intro is exactly right (3 entries, 3 stated reasons). The findings
below are the exceptions found against that otherwise-solid baseline.

---

## Finding 1 — The Phenomenology pages' "not duplicated" claim is false for three works

- **Type:** contradiction
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: `api / phenomenology / Scalings`, §References: *"the extraction-bound leaf carries its own citations, so these are not duplicated in the `ARCHITECTURE.md` reference list."*
  - PAGE: `api / phenomenology / Spectra`, §References: identical sentence, verbatim.
  - PAGE: `api / phenomenology / StructureFunctions`, §References: identical sentence, verbatim.
  - PAGE: `architecture`, §References: *"Pope, S. B. (2000). Turbulent Flows. Cambridge University Press. https://doi.org/10.1017/CBO9780511840531"*
  - PAGE: `api / phenomenology / Spectra`, §References: *"Pope (2000), Turbulent Flows (Cambridge University Press), §6.5. doi:10.1017/CBO9780511840531"*
  - PAGE: `architecture`, §References: *"Li, Y., Perlman, E., … (2008). … J. Turbulence 9, N31. https://doi.org/10.1080/14685240802376389"*
  - PAGE: `api / phenomenology / Scalings`, §References: *"Li et al. (2008), J. Turbulence 9, N31 (JHTDB). doi:10.1080/14685240802376389"*
  - PAGE: `architecture`, §References: *"Kolmogorov, A. N. (1941). … Dokl. Akad. Nauk SSSR 30, 301–305."*
  - PAGE: `api / phenomenology / StructureFunctions`, §References: *"Kolmogorov (1941), Dokl. Akad. Nauk SSSR 30, 301–305 (the 2/3 law) and 32, 16–18 (the exact 4/5 law); no DOI…"*
- **Contradicts:** the disclaimer's own axis — "not duplicated in the `ARCHITECTURE.md` reference list" vs. Pope (2000), Li et al. (2008), and Kolmogorov (1941) each demonstrably present in *both* the `architecture` page's References and a Phenomenology page's own References.
- **Description:** All three Phenomenology API pages carry the identical disclaimer that a law's citation, read from its `provenance`, is "not duplicated" in `ARCHITECTURE.md`'s list. Three of the cited works are duplicated: Pope 2000 (cited by `architecture` §4.8/§References for notation and again by `Spectra`'s own References for `Pope2000`), Li et al. 2008 (cited by `architecture` for the run layer's `Li2008`-driven viscosity choice and again by `Scalings`'s own References), and Kolmogorov 1941 (used in `architecture` §4.8 as the worked naming example, and again in full in `StructureFunctions`'s References). The two Pope-2000 entries are also formatted differently — full name, title, and `https://doi.org/…` URL on the `architecture` page vs. short author-year, parenthetical publisher, and a bare `doi:` prefix on the `Spectra` page — so the same work is not even cited the same way across its two appearances. Sreenivasan 1995/1998, by contrast, correctly appear *only* on the Phenomenology page and nowhere in `architecture`'s list, showing the intended separation is real and just leaks for these three.
- **Resolution hint:** either drop the disclaimer sentence's absolute wording ("in general, not duplicated" or similar), or actually deduplicate: keep Pope 2000 / Li 2008 / Kolmogorov 1941 in exactly one list and `@ref`/point to it from the other, in one consistent citation format.

---

## Finding 2 — Williamson (1980) "his recommended case 7" is an unverifiable, oddly specific attribution

- **Type:** citation
- **Severity:** minor
- **Confidence:** low
- **Locations:**
  - PAGE: `architecture`, §References: *"the package's third-order coefficients are Williamson's Eq. (11), his recommended case 7 — the set later adopted for spectral DNS and popularly named \"RKW3\"."*
- **Description:** No other page corroborates or elaborates "case 7," and in the wider DNS literature this specific low-storage RK3 coefficient set (`A = (0, -5/9, -153/128)`, `B = (1/3, 15/16, 8/15)`) is more commonly attributed via Wray's unpublished 1990 notes or the Spalart–Moser–Rogallo (1991) re-derivation of a Williamson-style scheme, rather than credited directly to a numbered case inside Williamson (1980) itself. Worth checking "his recommended case 7" against the primary source before it is repeated elsewhere, since it is a specific, checkable factual claim rather than a general nod to the low-storage family.

---

## Finding 3 — "Kaneda 1993" cited with zero bibliographic detail, unlike its paragraph neighbors

- **Type:** citation
- **Severity:** nit
- **Confidence:** low
- **Locations:**
  - PAGE: `api / phenomenology / Spectra`: *"the form the triadic spectral closures (EDQNM, DIA, LRA) consistently predict (Kaneda 1993; Sagaut & Cambon 2018)."*
  - Same paragraph, same page: *"Khurshid, Donzis & Sreenivasan 2018, doi:10.1103/PhysRevFluids.3.082601"* and *"Chen et al. 1993, doi:10.1103/PhysRevLett.70.3051"*.
- **Description:** The page's References note exempts an inline "coefficient or comparison" citation from needing a full entry, and its own worked example (Sagaut & Cambon) still carries a full title and publisher when first given in full elsewhere on the page. "Kaneda 1993" gets neither a journal, a title, nor a DOI anywhere in the document, while every other bare-year citation in the same sentence and paragraph does. This also risks ambiguity against the differently-detailed "Kaneda et al. 2003" cited on the same page for the periodic-box dissipation constant — a different paper, but the asymmetric detail level makes that harder for a reader to confirm.

---

## Finding 4 — "the leanest of the three on a GPU" is an unsubstantiated relative-performance claim

- **Type:** citation *(overclaim)*
- **Severity:** nit
- **Confidence:** low
- **Locations:**
  - PAGE: `api / SimulationDomain`, `TwoThirds` docstring: *"Exact dealiasing of the quadratic nonlinearity, and the leanest of the three on a GPU."*
  - Same page, `HouLi` docstring: describes the same single-realization, kernel-multiply assembly with no extra transform, only a smaller CFL-driven step-count penalty relative to `TwoThirds`.
- **Description:** `TwoThirds` and `HouLi` are documented elsewhere (the compute-audit decision-log entries) as sharing the same per-step transform count — the only documented cost difference is `HouLi`'s smaller CFL ceiling (more steps for the same physical time), not a per-step compute difference. Calling `TwoThirds` "the leanest of the three" reads as a flat superlative the page's own numbers do not directly substantiate for the `TwoThirds`-vs-`HouLi` pair (it clearly holds against `PhaseShift`, which is explicitly `2×` the transforms). Worth softening to name the actual axis (fewer steps at a given accuracy, not fewer per-step flops than `HouLi`) or dropping the superlative.
