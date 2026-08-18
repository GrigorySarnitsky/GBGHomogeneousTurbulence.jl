# Closure audit — 09-citations-integrity

## Finding 1 — Phenomenology pages' "not duplicated" claim false for three works

**VERDICT: ABSENT**

Evidence: `grep -rn "not duplicated" src/ docs/` returns nothing. The disclaimer sentence in all
three Phenomenology API pages (`docs/src/api/phenomenology/{Spectra,Scalings,StructureFunctions}.md`,
§References) now reads: "A few works are cited in `ARCHITECTURE.md` as well, where the DNS side
needs them — the leaf's independence means it does not *rely* on that list, not that the two never
overlap." `docs/ARCHITECTURE.md:1821-1823` matches: "so this list need not duplicate the ~two dozen
it cites" (no absolute non-overlap claim). Pope 2000 / Li 2008 / Kolmogorov 1941 still appear in
both lists, but the claim being audited (an absolute "not duplicated") no longer exists to
contradict that fact.

---

## Finding 2 — Williamson (1980) "his recommended case 7" unverifiable attribution

**VERDICT: ABSENT**

Evidence: `grep -rn "case 7\|recommended case" src/ docs/` returns nothing. `docs/ARCHITECTURE.md:1861-1863`
now reads: "the package's third-order coefficients are the low-storage set later adopted for
spectral DNS and popularly named \"RKW3\"; it is also attributed to an unpublished 1986 note of
Wray's, so this entry cites the family rather than a numbered case." The specific, unverifiable
"case 7" attribution the finding flagged is gone, replaced with a hedged, accurate statement.

---

## Finding 3 — "Kaneda 1993" cited with zero bibliographic detail

**VERDICT: PRESENT**

Evidence: `src/phenomenology/Spectra.jl:209` — "...consistently predict (Kaneda 1993; Sagaut &
Cambon 2018)." `grep -rn "Kaneda" src/ docs/src/ docs/ARCHITECTURE.md` shows only this bare mention
plus the unrelated "Kaneda et al. 2003" in `Scalings.jl:132` (a different, fully-cited work). No
journal, title, or DOI for Kaneda 1993 exists anywhere in the corpus, while its paragraph neighbors
(Khurshid, Donzis & Sreenivasan 2018; Chen et al. 1993) both carry full DOIs. Confirmed unchanged in
`docs/build/api/phenomenology/Spectra/index.html` ("Kaneda 1993; Sagaut &amp; Cambon 2018").

---

## Finding 4 — "the leanest of the three on a GPU" unsubstantiated overclaim

**VERDICT: ABSENT**

Evidence: `grep -rn "leanest" src/ docs/src/ docs/ARCHITECTURE.md` returns nothing. `src/SimulationDomain.jl`
(`TwoThirds` docstring, ~line 62) now reads "Exact dealiasing of the quadratic nonlinearity, with the
narrowest retained band of the three and no taper to evaluate." This replaces the flat GPU-performance
superlative with a verifiable, structural claim (2/3 keeps the narrowest band vs. HouLi's full-Nyquist
retention and PhaseShift's 2√2/3 cutoff; TwoThirds alone has no taper to evaluate) — not an overclaim.
