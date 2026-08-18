# Closure audit — 09-citations-integrity

## Finding 1 — `Kolmogorov1941` attributes two distinct 1941 notes to one citation

**VERDICT: ABSENT**

Evidence: `src/phenomenology/StructureFunctions.jl:37-39`, `const _K41 = Reference("Kolmogorov
(1941), *Dokl. Akad. Nauk SSSR* **30**, 301–305 (the 2/3 law) and **32**, 16–18 (the exact 4/5
law); no DOI, the 1941 Doklady notes predate the system"; ...)`. The `provenance(::Kolmogorov1941)`
value now explicitly splits attribution: vol. 30/301-305 for the 2/3 law, vol. 32/16-18 for the
exact 4/5 law, matching the K41a/K41b historical record the finding described. Confirmed rendered
identically in `docs/build/api/phenomenology/StructureFunctions/index.html`.

---

## Finding 2 — `TwoThirds` carries no inline citation, unlike its sibling dealiasing strategies

**VERDICT: ABSENT**

Evidence: `src/SimulationDomain.jl:56-58`, the `TwoThirds()` docstring now reads "The sharp
isotropic ``2/3``-rule truncation of Orszag (1971) — *On the elimination of aliasing in
finite-difference schemes...*, *J. Atmos. Sci.* **28**, 1074, [doi:...]". Parity with `HouLi`
(line 70-72) and `PhaseShift` (line 102-105), each of which also cites inline with journal/DOI.

---

## Finding 3 — Several secondary citations in `Spectra` are never resolvable to a full reference, unlike their sibling `Sagaut & Cambon 2018`

**VERDICT: PARTIAL**

Evidence: `src/phenomenology/Spectra.jl:71-73` (Qian 1984, Ishihara 2005, Kraichnan 1959) and
`:210-212` (Khurshid Donzis & Sreenivasan 2018, Chen et al. 1993) and `:233-235` (Saffman 1963,
Townsend 1951) now all carry DOI links — 7 of the 8 originally-flagged names fixed. But
`:208`, `"...consistently predict (Kaneda 1993; Sagaut & Cambon 2018)"` — "Kaneda 1993" remains
author-year-only with no DOI or full title anywhere in the corpus (grep confirms only "Kaneda et
al. 2003" in `src/phenomenology/Scalings.jl:132`, a distinct paper with its own DOI, exists in
full). The unresolvable-inline-citation class survives at this one site, immediately adjacent to
the still-bare `Sagaut & Cambon 2018` the footnote exempts by design.

**Surviving class:** `Kaneda 1993` in `src/phenomenology/Spectra.jl:208` (`ExponentialDissipation`
docstring) — the sole remaining instance of an inline-only, non-resolvable secondary citation on
the `Spectra` page.

---

## Finding 4 — Kolmogorov (1941) page range differs between the two reference lists that cite it

**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:1816`, "*Dokl. Akad. Nauk SSSR* **30**, 301–305." vs.
`src/phenomenology/StructureFunctions.jl:37`, "*Dokl. Akad. Nauk SSSR* **30**, 301–305 (the 2/3
law)". Both now give the identical page range "301–305" for the vol.-30 paper; the earlier
truncation to "301" alone is gone.
