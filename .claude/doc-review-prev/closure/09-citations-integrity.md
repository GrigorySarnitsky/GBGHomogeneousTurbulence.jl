# Closure — Hat 09: Scientific-Integrity & Citations Audit

## Finding 1 — `Sreenivasan1995`'s cited provenance is not the source of its default value

**Verdict:** PRESENT

**Evidence:** `src/phenomenology/Scalings.jl:87` — `provenance(::Sreenivasan1995) = _SREENIVASAN1995`,
and `_SREENIVASAN1995` (line 87) still resolves only to Sreenivasan (1995). Docstring (lines 100–101)
still reads "The default `C_K = 1.5 ± 0.1` used here is the consensus value as quoted by Sagaut &
Cambon (2018), not a figure read off the 1995 paper." `grep -rn -i Sagaut src/` finds Sagaut & Cambon
mentioned in prose in three files (`Scalings.jl:100`, `Spectra.jl:238,297`, `StructureFunctions.jl:184`)
but never as a `Reference` value anywhere in `src/`; no §References entry in `docs/ARCHITECTURE.md`
either (`grep -n -i Sagaut docs/ARCHITECTURE.md` returns nothing). Machine-readable `provenance` still
disagrees with the prose.

---

## Finding 2 — an unattributed bare-name citation breaks the corpus's own author–year rule

**Verdict:** PRESENT

**Evidence:** `src/phenomenology/Spectra.jl:239` still reads "...the closure result is originally
Kaneda's)" — no year, no `Reference`. `grep -n -i Kaneda src/phenomenology/*.jl` finds one other,
unrelated, fully-cited instance ("Kaneda et al. 2003," `Scalings.jl:138`, with DOI) for a different
claim (the dissipation-anomaly plateau), which does not resolve the bare "Kaneda's" in `Spectra.jl`.
House rule confirmed live at `docs/ARCHITECTURE.md:845` ("Citations follow author–year..."). The
closure-result attribution is still the one un-yeared, unlinked name in the corpus.

---

## Finding 3 — two inline comparison citations omit DOIs with no "no DOI" disclosure

**Verdict:** PRESENT

**Evidence:** `src/phenomenology/Spectra.jl:423` — "Sreenivasan 1996, *Phys. Fluids* **8**, 189" —
still no DOI and no disclosure. `src/phenomenology/StructureFunctions.jl:111` — "Obukhov (1962,
*J. Fluid Mech.* **13**, 77)" — still no DOI and no disclosure. Contrast still holds:
`docs/ARCHITECTURE.md:1855,1873` are the only two explicitly marked "(No DOI; ...)" entries in the
whole document (`grep -n "No DOI" docs/ARCHITECTURE.md` → exactly those two lines). Both flagged
instances are unchanged.

---

## Finding 4 — one reference-list entry alone uses an issue-number format the other entries omit

**Verdict:** PRESENT

**Evidence:** `docs/ARCHITECTURE.md:1846` — "Betchov, R. (1956)... *J. Fluid Mech.* **1**(5),
497–504." `grep -n '\*\*[0-9]*\*\*([0-9]' docs/ARCHITECTURE.md` matches only this one line in the
entire §References list; every other journal entry (Patterson & Orszag, Orszag, Orszag & Patterson,
Hou & Li, Cichowlas et al., Chollet & Lesieur, Eswaran & Pope, Li et al., Williamson, Mori, Zwanzig,
Morrison, ...) still gives volume-then-pages with no parenthetical issue number. Unchanged.
