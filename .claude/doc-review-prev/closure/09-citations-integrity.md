# Closure — 09-citations-integrity

## Finding 1 — "Berendsen thermostat" named but its own paper never cited

**Verdict: ABSENT**

Evidence: `src/Forcing.jl:283-286` now reads "…the limit of the Berendsen thermostat (Berendsen,
Postma, van Gunsteren, DiNola & Haak 1984, *Molecular dynamics with coupling to an external bath*,
*J. Chem. Phys.* **81**, 3684, doi:10.1063/1.448118)…", with a matching `§References` entry at
`docs/ARCHITECTURE.md:1872-1874` ("Berendsen, H. J. C., … (1984). Molecular dynamics with coupling to
an external bath. … *(The thermostat whose deterministic-rescaling limit `BandRescaling` is; named
there and now cited.)*"). Searched for "Berendsen" and "Bussi" across `src/` and `docs/`; both the
1984 foundational paper and the 2007 follow-up are now present and cross-consistent.

## Finding 2 — Ambiguous dual attribution of the Kolmogorov constant's numeric value

**Verdict: ABSENT**

Evidence: `src/phenomenology/Scalings.jl:98-102` now reads "Reviewing the experimental and numerical
record, Sreenivasan (1995) found it close to universal. The default ``C_K = 1.5 \pm 0.1`` used here
is the consensus value as quoted by Sagaut & Cambon (2018), **not a figure read off the 1995
paper**…" — the exact ambiguity the finding flagged (which source the ±0.1 figure comes from) is now
stated explicitly.

## Finding 3 — Inconsistent DOI treatment for comparison citations within one docstring

**Verdict: PRESENT**

Evidence: `src/phenomenology/Spectra.jl:236-241` (`ExponentialDissipation`) still cites "Sagaut &
Cambon 2018" with no DOI/journal, immediately followed by "Khurshid, Donzis & Sreenivasan 2018,
doi:10.1103/PhysRevFluids.3.082601" and "Chen et al. 1993, doi:10.1103/PhysRevLett.70.3051" both with
full DOIs — the same split flagged originally. Checked the page's own `## References` note
(`docs/src/api/phenomenology/Spectra.md:63-71`): it explains why Sagaut & Cambon needs no formal
`§References` entry, but states no rule for the inline DOI/no-DOI split. `rg "Sagaut" | grep -i doi`
across `docs/` and `src/` returns no hits anywhere — Sagaut & Cambon is never given a DOI in the
corpus, consistent with it being a monograph rather than a journal article, but this convention is
nowhere stated, so the inconsistency the finding describes is unexplained exactly as before.
