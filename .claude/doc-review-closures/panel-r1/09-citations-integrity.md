# Closure verdicts — Hat 09: citations-integrity

## Finding 1 — "No privileged default" contradicted by front door's concrete defaults

**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:594-596` (§6) now reads "Both precisions are supported equally, and
no kernel privileges either." followed immediately by an explicit parenthetical: "(The `Simulation`
front door must start somewhere and starts at `Float64` / `Array`; that is a convenience
constructor's choice, not a property of the library, and `FixedDomain` takes both from the caller.)"
— the exact exception the finding said was missing. `src/SimulationRun.jl:145` independently marks
`element_type`/`array_type` "(front door only)" in the `# Arguments` list. Invariant 3 (§9, line 766)
still states the bullet tersely but explicitly defers to §6 for detail, where the qualification now
lives. Searched: `rg "privileged"`, read §6 and §9 in full, read `SimulationRun.jl` docstring.

## Finding 2 — Meyers & Meneveau (2008) cited for generic spectrum form vs. its bottleneck contribution

**VERDICT: ABSENT**

Evidence: `rg -ni "meyers|meneveau" .` (excluding `.claude/`) returns only an unrelated "Meneveau, C."
co-author in the Li et al. 2008 JHTDB reference (`docs/ARCHITECTURE.md:1862`). The `ModelSpectrum`
docstring at `src/phenomenology/Spectra.jl:291` now reads "(Sagaut & Cambon 2018; Pope 2000)" with no
Meyers & Meneveau citation at all — the disputed reference was removed rather than resolved in place.

## Finding 3 — Kaneda (1993) bare citation beside fully-detailed Kaneda et al. (2003)

**VERDICT: PRESENT**

Evidence: `src/phenomenology/Spectra.jl:233` — `ExponentialDissipation` docstring still reads "...
consistently predict (Kaneda 1993; Sagaut & Cambon 2018)." with no journal/volume/DOI. The
fully-detailed neighbor persists at `src/phenomenology/Scalings.jl:137`: "Kaneda et al. 2003,
[doi:10.1063/1.1539855](...)". Unchanged from the finding's description.

## Finding 4 — Kolmogorov (1941) in `§References` with no inline author-year citation

**VERDICT: REGRESSED**

Evidence: The "K41" shorthand the finding flagged (`docs/ARCHITECTURE.md:329`, "K41 implies a
constant skewness but fixes no number") is unchanged and still has no "(Kolmogorov 1941)" inline
form. But the underlying reference entry has now been **deleted**: `docs/ARCHITECTURE.md`'s
`## References` section (lines 1827-1885) contains no Kolmogorov entry at all (`rg -n
"Kolmogorov, A"` / `"Dokl"` / `"301.305"` all empty), while its own intro sentence (line 1830-1831)
still asserts one exists — "Three do not [have a DOI] ... a 1941 *Doklady* note, a NASA technical
memorandum, and a CTR research brief" — naming only two of the three by content (Rogallo 1981's TM,
Lundgren 2003's CTR brief are both present; the "1941 Doklady note" has no matching entry). The
References section now self-contradicts: it describes a citation it no longer lists. This is a new
defect, not the original one.

## Finding 5 — Sreenivasan (1996) cited with journal/volume but no DOI, unlike 1995/1998 neighbors

**VERDICT: PRESENT**

Evidence: `src/phenomenology/Spectra.jl:413` — `ObukhovCorrsin1949` docstring still reads "the
high-Reynolds-number value of Sreenivasan 1996, *Phys. Fluids* **8**, 189" with no DOI.
`src/phenomenology/Scalings.jl:49,87` still carry `doi:10.1063/1.869575` (1998) and
`doi:10.1063/1.868656` (1995) for the same author's neighboring papers. Unchanged from the finding.
