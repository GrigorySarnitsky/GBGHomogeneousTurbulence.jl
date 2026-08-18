# Closure audit — Hat 14: doc-policy

## Finding 1 — `Phenomenology.Spectra` module docstring embeds a formula
**VERDICT: ABSENT**

Evidence: `src/phenomenology/Spectra.jl:1-25` module docstring now reads "A velocity model is
**composed** — an inertial-range core times a large-scale roll-off and a dissipation-range
roll-off, each swappable — and [`ModelSpectrum`](@ref) owns the formula." No computed expression
(``C_K\varepsilon^{2/3}\kappa^{-5/3}``) appears anywhere in the module docstring; only bare
notation (``E(\kappa)``, ``\kappa^4``) remains, matching every sibling module docstring's style.
`grep 'E(\\kappa) = C_K'` across the module docstring returns nothing.

---

## Finding 2 — `Pope2000` duplicates `ModelSpectrum`'s generic formula verbatim
**VERDICT: ABSENT**

Evidence: `src/phenomenology/Spectra.jl:292-307` — `Pope2000`'s docstring now reads "the
[`ModelSpectrum`](@ref) composition (whose docstring carries the formula) with
[`PopeLargeScale`](@ref) supplying ``f_L`` and [`PopeDissipation`](@ref) supplying ``f_\eta``" —
no displayed equation at all, linking instead. `VonKarman1948` (:315-336) and `Pao1965`
(:341-362) still substitute their own closed forms, so the three presets are now internally
consistent (link vs. substitute, no bare duplication).

---

## Finding 3 — Named-method citations open the identity sentence, ahead of the formula
**VERDICT: ABSENT**

Evidence: `CLAUDE.md:139-141` (Documentation policy, function-docstring order) now reads: "(6) an
inline citation for a **named / published** method — which may open the identity sentence when
the citation *names* the method ("the smooth spectral filter of Hou & Li (2007) …"), the
corpus-wide convention". The source docstrings (`IFLowStorageRK3` at `src/Propagator.jl:209-246`,
`HouLi`/`PhaseShift` in `src/SimulationDomain.jl`) still open with the citation exactly as the
finding quoted — but the policy text itself was amended to state this placement as the sanctioned
convention, which is precisely the "one-line carve-out" the finding's low-confidence framing
proposed as the alternative resolution. The contradiction between stated policy and corpus
practice no longer exists.
