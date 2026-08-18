# Closure — Scientific-integrity & Citations hat (09-citations-integrity)

## Finding 1 — Phenomenology pages' "not duplicated" claim false for Pope 2000 / Li 2008 / Kolmogorov 1941

**VERDICT: ABSENT**

Evidence: `docs/src/api/phenomenology/{Scalings,Spectra,StructureFunctions}.md` References sections
now read "A few works are cited in `ARCHITECTURE.md` as well, where the DNS side needs them — the
leaf's independence means it does not *rely* on that list, not that the two never overlap." This
replaces the old absolute "not duplicated" wording with an explicit acknowledgment of overlap — the
exact contradiction the finding flagged is gone. `docs/ARCHITECTURE.md` still cites Pope 2000 (line
1860), Li et al. 2008 (line 1845), and Kolmogorov 1941 (line 1820), and the Phenomenology pages still
list them too, but the disclaimer no longer claims otherwise.

---

## Finding 2 — Williamson (1980) "his recommended case 7" unverifiable attribution

**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:1856-1859` now reads: "the package's third-order coefficients are the
low-storage set later adopted for spectral DNS and popularly named \"RKW3\"; it is also attributed to
an unpublished 1986 note of Wray's, so this entry cites the family rather than a numbered case." The
specific, unverifiable "his recommended case 7" claim is gone; `grep -rn "case 7"` across
`docs/ARCHITECTURE.md`, `docs/src`, `src` returns nothing.

---

## Finding 3 — "Kaneda 1993" cited with zero bibliographic detail unlike its paragraph neighbors

**VERDICT: PRESENT**

Evidence: `src/phenomenology/Spectra.jl:209` still reads "...consistently predict (Kaneda 1993; Sagaut
& Cambon 2018)." in the `ExponentialDissipation` docstring, with no journal, title, or DOI, while the
same paragraph's "Khurshid, Donzis & Sreenivasan 2018" (line 211) and "Chen et al. 1993" (line 213)
both carry full `doi:` links. `grep -rn "Kaneda"` across `src`, `docs/src`, `docs/ARCHITECTURE.md`
finds no fuller citation anywhere else in the corpus. Unchanged from the finding.

---

## Finding 4 — "the leanest of the three on a GPU" unsubstantiated relative-performance claim

**VERDICT: ABSENT**

Evidence: `src/SimulationDomain.jl:53-64`, the `TwoThirds` docstring, now reads "Exact dealiasing of
the quadratic nonlinearity, with the narrowest retained band of the three and no taper to evaluate." —
a concrete, substantiated axis (band width, no taper) replacing the flat "leanest ... on a GPU"
superlative. `grep -rn "leanest"` across `src`, `docs/src`, `docs/ARCHITECTURE.md` returns nothing.
