# Doc-review panel — Scientific-integrity & citations hat

Fresh-eyed audit of the rendered GBGIsotropicTurbulence documentation for citation
consistency, reference-list accuracy, and overclaiming. Findings below; the exhaustive
positive check (verifying each of the ~20 ARCHITECTURE.md References entries and the
~12 Phenomenology-page entries for author/year/journal/volume/page accuracy against the
turbulence literature, and cross-checking every inline author-year mention against its
list) turned up no fabricated citation and no unsubstantiated "exact"/"allocation-free"
overclaim; the four items below are the residue.

---

## Finding 1 — `Kolmogorov1941` attributes two distinct 1941 notes to one citation

- **Type:** citation
- **Severity:** major
- **Confidence:** medium
- **Locations:**
  - PAGE: api / phenomenology / StructureFunctions — `Kolmogorov1941` docstring: "`order = 2` — the 2/3 law $D_{LL}(r) = C_2(\varepsilon r)^{2/3}$ … `order = 3` — the 4/5 law $D_{LLL}(r) = -\tfrac{4}{5}\varepsilon r$ … this one is exact (a consequence of the Kármán–Howarth–Monin relation)"
  - PAGE: api / phenomenology / StructureFunctions — References: "Kolmogorov (1941), Dokl. Akad. Nauk SSSR 30, 301"
- **Contradicts:** the turbulence-history record — the 2/3 law for $D_{LL}$ appears in Kolmogorov's first 1941 Dokl. note, "The local structure of turbulence…" (Dokl. Akad. Nauk SSSR **30**, 299–303, the paper the citation gives), while the *exact* 4/5 law for $D_{LLL}$ is the result of the companion note "Dissipation of energy in locally isotropic turbulence" (Dokl. Akad. Nauk SSSR **32**, 16–18) — conventionally distinguished in the literature as K41a and K41b (e.g. Frisch 1995 catalogues the three 1941 notes separately).
- **Description:** One `Kolmogorov1941(; C₂ = 2.0)` type, with one `Reference` pointing at volume 30, is asked to carry both the 2/3 law (genuinely from vol. 30) and the exact 4/5 law (historically from the vol. 32 note). If the package intends one code identifier ↔ one paper (its own stated naming rule — "the paper is the author-year handle"), the citation for `order = 3` is pointing at the wrong specific paper, even though the author and year are right. If instead "K41" is meant loosely to cover the three companion 1941 notes together, that is a defensible simplification, but it is not stated, and it sits oddly next to a naming scheme that otherwise disambiguates same-author-year work with a trailing letter (`Pope2014a`/`Pope2014b`) — the K41a/K41b split is exactly that situation and is not used here.
- **Resolution hint:** either split into `Kolmogorov1941a` (vol. 30, the 2/3 law) / `Kolmogorov1941b` (vol. 32, the 4/5 law), consistent with the package's own same-year-collision convention, or add one sentence noting the citation aggregates the three 1941 Dokl. notes deliberately.

---

## Finding 2 — `TwoThirds` carries no inline citation, unlike its sibling dealiasing strategies

- **Type:** citation
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: api / SimulationDomain — `TwoThirds()`: "The sharp isotropic $2/3$-rule truncation… Exact dealiasing of the quadratic nonlinearity, and the lean, GPU-friendly default." (no author-year anywhere in the type's own docstring)
  - PAGE: api / SimulationDomain — `HouLi(...)`: "The smooth spectral filter is due to Hou & Li (2007)."
  - PAGE: api / SimulationDomain — `PhaseShift()`: "Phase-shift dealiasing (Patterson & Orszag 1971; combined with spherical truncation by Rogallo 1981)"
- **Contradicts:** the sibling docstrings' own practice — of the three concrete `DealiasingStrategy` types, two cite their origin inline in the type's own docstring and one does not, even though the ARCHITECTURE.md References entry ("Orszag, S. A. (1971)… The $2/3$ truncation rule.") shows the package does treat the $2/3$ rule as a named, citable method.
- **Description:** The $2/3$ rule's citation lives only in `ARCHITECTURE.md`'s module-map prose (§4.2) and its References entry, never in the rendered `TwoThirds` API page itself — the page a reader consulting the dealiasing-strategy family would actually land on. This is a "cold read" gap (the doc-policy's own test): a reader comparing `TwoThirds`/`HouLi`/`PhaseShift` side by side sees attribution on two of three and would reasonably read the omission on the third as "house default, no citable source," which is not the case.
- **Resolution hint:** add "(Orszag 1971)" to the `TwoThirds` docstring for parity with its siblings.

---

## Finding 3 — Several secondary citations in `Spectra` are never resolvable to a full reference, unlike their sibling `Sagaut & Cambon 2018`

- **Type:** citation
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: api / phenomenology / Spectra — `DissipationFactor` note: "a bump before the cutoff (Qian 1984; Ishihara et al. 2005; Kraichnan 1959, all of the form …)"
  - PAGE: api / phenomenology / Spectra — `ExponentialDissipation`: "the triadic spectral closures (EDQNM, DIA, LRA) consistently predict (Kaneda 1993; Sagaut & Cambon 2018)… DNS resolving that range fit $\beta \approx 6.7$ (Khurshid, Donzis & Sreenivasan 2018; consistent with Chen et al. 1993, $\beta \approx 7.1$)… (Ishihara et al. 2005)"
  - PAGE: api / phenomenology / Spectra — `SaffmanDissipation`: "Saffman (1963, appendix; about half the earlier Townsend 1951 spectrum)"
  - PAGE: api / phenomenology / Spectra — References footnote (verbatim, repeated on Scalings/StructureFunctions too): "sources cited inline for an individual coefficient or a comparison (e.g. **Sagaut & Cambon, Homogeneous Turbulence Dynamics, 2nd ed., Springer, 2018**) are cited in place and deliberately not repeated here."
- **Contradicts:** its own stated exemplar — the page explicitly names `Sagaut & Cambon 2018` as the *example* of an inline-only comparison citation, and then gives it a full title/publisher/edition right there in the footnote prose. None of the eight other inline-only citations on the same page (Qian 1984, Kraichnan 1959, Townsend 1951, Saffman 1963, Kaneda 1993, Khurshid Donzis & Sreenivasan 2018, Chen et al. 1993, Ishihara et al. 2005) receive that treatment anywhere in the rendered site — a reader has author-and-year only, with no journal, volume, or title to resolve it, for eight names and only full detail for one.
- **Description:** This is consistent with the stated policy (Phenomenology's inline-comparison citations are deliberately not duplicated in a References block), so it is not a rule violation — but the policy's own worked example sets an expectation of resolvability that the other eight citations on the same page do not meet, which reads as an inconsistency in how thoroughly the "cited in place" citations are actually specified.
- **Resolution hint:** either give all inline-only comparison citations the same one-line full-reference treatment `Sagaut & Cambon` gets, or drop the parenthetical journal detail from `Sagaut & Cambon`'s mention so the class is uniform.

---

## Finding 4 — Kolmogorov (1941) page range differs between the two reference lists that cite it

- **Type:** citation
- **Severity:** nit
- **Confidence:** low
- **Locations:**
  - PAGE: architecture — References: "Kolmogorov, A. N. (1941)… Dokl. Akad. Nauk SSSR **30, 301–305**."
  - PAGE: api / phenomenology / StructureFunctions — References: "Kolmogorov (1941), Dokl. Akad. Nauk SSSR **30, 301**."
- **Contradicts:** each other on the ending page — one gives the full "301–305" range, the other truncates to the opening page "301" only, for what appears to be the identical paper (same volume, same author, same year).
- **Description:** Likely harmless truncation for brevity in the scoped Phenomenology list rather than a factual disagreement, but since both lists otherwise give page ranges (e.g. `Betchov 1956`: "497–504" in ARCHITECTURE.md), the single-page form here reads as an inconsistency in citation completeness between the two independently-maintained reference lists for the one paper both index.
- **Resolution hint:** align to the same page range in both places, or note explicitly that the Phenomenology lists intentionally give first-page-only citations.

---

## Non-findings worth recording (checked, clean)

- No fabricated or unverifiable citation was found; every author/year/journal/volume/page
  triplet checked against the turbulence literature (Kolmogorov 1941/1962, Betchov 1956,
  Patterson & Orszag 1971, Orszag 1971, Orszag & Patterson 1972, Rogallo 1981, Hou & Li
  2007, Cichowlas et al. 2005, Chollet & Lesieur 1981, Eswaran & Pope 1988, Lundgren 2002 &
  2003, Bussi/Donadio/Parrinello 2007, Williamson 1980, Pope 2000, Mori 1965, Zwanzig 1973,
  Morrison 1986, Öttinger 2005, Sreenivasan 1995/1996/1998, Li et al. 2008, von Kármán 1948,
  Pao 1965, Obukhov 1949, Corrsin 1951, She & Lévêque 1994, Yaglom 1949) matched.
- The one apparent gap flagged in a prior round (`Lundgren2002` "missing" from
  `StructureFunctions`' References) was re-checked and confirmed present — not re-flagged,
  per the adjudication record.
- No citation to the private, gitignored `inspiration/` material was found anywhere on the
  user-facing surface — the house rule ("never cite an inaccessible source") holds.
- The "no-guessed-citation" DOI-omission policy is applied consistently — no DOI appears
  anywhere, matching the ARCHITECTURE.md References header's stated rule.
- No overclaiming language ("exact", "allocation-free", "optimal", "the largest/first") was
  found unsubstantiated — every "exact" claim checked (the $2/3$-rule dealiasing, the
  `PhaseShift` cancellation, the integrating factor, scalar-mean conservation, the K41 4/5
  law) is either classical/well-established or backed by an explicit verification claim
  (e.g. "verified against a zero-padded oracle — exact to machine precision") elsewhere in
  the same document; every "allocation-free" claim carries its stated exceptions (occasional
  diagnostics, the archived `StochasticOU`'s host-side draw).
