# Closure audit — Hat 14: doc-policy

## Finding 1 — `Phenomenology.Spectra` module docstring embeds a formula
**VERDICT: ABSENT**

Evidence: `src/phenomenology/Spectra.jl:4-7` module docstring now reads "an inertial-range core times a
large-scale roll-off and a dissipation-range roll-off, each swappable — and [`ModelSpectrum`](@ref)
owns the formula." No `math`/formula span remains in the module docstring body; grepped the whole
docstring (lines 1-35) for `\varepsilon`/`\kappa^{-5/3}` — none present. The formula lives only in
`ModelSpectrum`'s own docstring (line 251), matching the `Generator` precedent the finding cited.

## Finding 2 — `Pope2000` duplicates `ModelSpectrum`'s generic formula verbatim
**VERDICT: ABSENT**

Evidence: `src/phenomenology/Spectra.jl:296-297` — `Pope2000`'s docstring now reads "the
[`ModelSpectrum`](@ref) composition (whose docstring carries the formula) with [`PopeLargeScale`]…
supplying ``f_L`` and [`PopeDissipation`]… supplying ``f_\eta``" — no displayed equation at all, just
a link. No verbatim or substituted formula duplicated; contrast with `VonKarman1948` (:319-326) and
`Pao1965` (:345-352), which still substitute their own closed forms, exactly as the finding wanted.

## Finding 3 — Named-method citations open the identity sentence, ahead of the formula
**VERDICT: NOT-A-DEFECT**

Evidence: The flagged pattern is unchanged in source — `IFLowStorageRK3` (`src/Propagator.jl:212-214`),
`HouLi` (`src/SimulationDomain.jl:70-73`), `PhaseShift` (`src/SimulationDomain.jl:102-105`) all still
open with the citation before the formula. But CLAUDE.md's own ordering rule was amended: it now reads
(house rulebook, "Documentation policy" §Function docstring, item 6) "an inline citation for a **named /
published** method — which may open the identity sentence when the citation *names* the method ('the
smooth spectral filter of Hou & Li (2007) …'), the corpus-wide convention" — verified verbatim at
`CLAUDE.md:139-141`. The finding's own resolution hint (a carve-out rather than a corpus-wide rewrite)
is exactly what was adopted, so the docstrings no longer contradict policy.
