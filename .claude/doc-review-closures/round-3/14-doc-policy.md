# Closure audit — Hat 14: doc-policy

## Finding 1 — `Phenomenology.Spectra` module docstring embeds a formula

**VERDICT: ABSENT**

Evidence: `src/phenomenology/Spectra.jl:1-7` module docstring now reads "an inertial-range core times
a large-scale roll-off and a dissipation-range roll-off, each swappable — and [`ModelSpectrum`](@ref)
owns the formula" — no computed expression (`C_K`, exponents) present. Checked sibling module
docstrings `Scalings.jl`, `StructureFunctions.jl` for the same class: both bare-notation only, no
formulas. Class clean.

---

## Finding 2 — `Pope2000` duplicates `ModelSpectrum`'s formula verbatim

**VERDICT: ABSENT**

Evidence: `src/phenomenology/Spectra.jl:293-306` — `Pope2000`'s docstring now reads "the
[`ModelSpectrum`](@ref) composition (whose docstring carries the formula) with [`PopeLargeScale`](@ref)
supplying ``f_L`` … " — no displayed equation at all, just a link to `ModelSpectrum` (line 251-256,
which alone carries `E(\kappa) = C_K\varepsilon^{2/3}\kappa^{-5/3}f_L f_\eta`). `VonKarman1948`
(:334-337) and `Pao1965` (:359-362) still substitute their own closed forms, so the corpus is now
internally consistent: link-or-substitute, never a bare re-copy.

---

## Finding 3 — Named-method citations open the docstring, ahead of the formula

**VERDICT: PRESENT**

Evidence: unchanged. `src/Propagator.jl:210-214` (`IFLowStorageRK3`) still opens "Integrating-factor
third-order low-storage Runge–Kutta, 2N-storage — Williamson (1980) …" with the formula (lines
225-232) several sentences later. `src/SimulationDomain.jl:68-72` (`HouLi`, Hou & Li 2007),
`:100-104` (`PhaseShift`, Patterson & Orszag 1971 / Rogallo 1981), and `:54-58` (`TwoThirds`, Orszag
1971) all follow the identical citation-first pattern. CLAUDE.md's stated order (formula §5 before
citation §6) is unchanged. No carve-out was added to CLAUDE.md and no docstring was reordered — the
corpus-wide convention flagged at low confidence stands exactly as described.
