# Closure audit — 09-citations-integrity

## Finding 1 — Phenomenology pages' "not duplicated" claim false for Pope 2000 / Li 2008 / Kolmogorov 1941
**VERDICT: ABSENT**

Evidence: `docs/src/api/phenomenology/{Scalings,Spectra,StructureFunctions}.md` References intros now
all read "A few works are cited in `ARCHITECTURE.md` as well, where the DNS side needs them — the
leaf's independence means it does not *rely* on that list, not that the two never overlap." — the
absolute "not duplicated" claim is gone, replaced with an accurate acknowledgment of deliberate
overlap. `docs/src/architecture.md:1821-1822` mirrors this: "this list need not duplicate the ~two
dozen it cites" (permissive, not exclusive). Searched all three phenomenology pages plus
`architecture.md`; wording is uniform and no longer contradicts the actual overlap of Pope 2000 / Li
2008 / Kolmogorov 1941 across both lists.

---

## Finding 2 — Williamson (1980) "his recommended case 7" unverifiable attribution
**VERDICT: ABSENT**

Evidence: `docs/src/architecture.md:1861-1863` now reads "the package's third-order coefficients are
the low-storage set later adopted for spectral DNS and popularly named \"RKW3\"; it is also attributed
to an unpublished 1986 note of Wray's, so this entry cites the family rather than a numbered case." The
specific, unverifiable "his recommended case 7" claim is gone; `grep -rn "case 7" docs/ src/` returns
no hits anywhere in the corpus.

---

## Finding 3 — "Kaneda 1993" cited with zero bibliographic detail, unlike its paragraph neighbors
**VERDICT: PRESENT**

Evidence: `src/phenomenology/Spectra.jl:209` still reads "…consistently predict (Kaneda 1993; Sagaut &
Cambon 2018)." with no journal, title, or DOI anywhere in the corpus (`grep -rn "Kaneda" docs/src/
src/` finds only this bare mention and the unrelated, fully-detailed "Kaneda et al. 2003" in
`Scalings.jl:137`), while the same paragraph's "Khurshid, Donzis & Sreenivasan 2018" and "Chen et al.
1993" both carry inline DOIs. Asymmetry unchanged.

---

## Finding 4 — "the leanest of the three on a GPU" unsubstantiated relative-performance claim
**VERDICT: ABSENT**

Evidence: `src/SimulationDomain.jl:63-64` (`TwoThirds` docstring) now reads "Exact dealiasing of the
quadratic nonlinearity, with the narrowest retained band of the three and no taper to evaluate." — the
flat performance superlative is replaced with a precise, verifiable structural claim (band width, no
taper), matching what `HouLi` (damping, smaller CFL) and `PhaseShift` (2× transforms) docstrings
actually substantiate. `grep -rn "leanest" docs/src/ src/` returns no hits.
