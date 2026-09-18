# Closure audit — 06-turbulence-theoretician

## 1. Architecture §4.1 "sharp 3/4 rule" vs 2/3 rule elsewhere
**VERDICT: ABSENT**
Evidence: `docs/ARCHITECTURE.md:189` now reads "the dealias kernel of the run's chosen strategy (the sharp ``2/3`` rule by default)". Searched `rg "3/4 rule"` across `docs/ARCHITECTURE.md`, `src/`, `docs/src/` — zero hits. All surfaces (§4.1, §4.2 line 264, §7 line 294, decision 27 line 1144) now agree on `2/3`.

## 2. Scalar as ⟨θ²⟩ in architecture §4.7 vs house rule "never θ"
**VERDICT: ABSENT**
Evidence: `docs/ARCHITECTURE.md:489`, the `StationarityCriterion` bullet, now reads "When the scalar is forced, ``\langle\varphi^2\rangle`` must settle too". `rg "theta|\\\\theta"` across `docs/ARCHITECTURE.md` returns only the invariant statement itself (line 838) and one prose mention of `\hat\varphi` (line 1116) — no stray `θ` remains.

## 3. Stale sync counts: add_forcing_source! "three per stage", VarianceRescaling "two under :total"
**VERDICT: ABSENT**
Evidence: `src/Forcing.jl:261-264` (`add_forcing_source!` docstring) now reads "one blocking device-to-host transfer at every stage — a single fused multi-weight reduction answers `VarianceController`'s three weighted sums together". `src/Forcing.jl:366-367` (`VarianceRescaling`) now reads "each step blocks on one device-to-host transfer: the band and whole-field observables ride a single fused traversal, in either mode." Both quote the post-fusion (one-readback) counts, not the pre-fusion three/two.

## 4. Decision log "S runs from 0 toward ≈ −0.05"
**VERDICT: ABSENT**
Evidence: `docs/ARCHITECTURE.md:947` now reads "against the ``\lvert S\rvert \approx 0.5`` of a developed cascade (``S`` runs from ``0`` toward ``\approx -0.5``)" — consistent with the −0.5 value used elsewhere (line 331, 945).

## 5. PhaseShift cites "Rogallo (1984)" vs 1981 everywhere else
**VERDICT: ABSENT**
Evidence: `src/SimulationDomain.jl:114`, the `PhaseShift` docstring, now reads "Rogallo (1981) — *Numerical experiments in homogeneous turbulence*, NASA TM-81315". Matches `docs/ARCHITECTURE.md:2110`'s §References entry and decision 27's inline citation (line 1144), both 1981. `rg "Rogallo"` across `src/` and `docs/ARCHITECTURE.md` shows no remaining "1984".

## 6. Divergence "damped only by exp(+νκ²Δt)" — sign inverted
**VERDICT: ABSENT**
Evidence: `docs/ARCHITECTURE.md:2026-2027` now reads "is damped only by ``\exp(-\nu\kappa^{2}\Delta t)``, nearly nothing at the largest scales" — negative sign, consistent with `velocity_integrating_factor`'s damping multiplier.

## 7. Architecture §10 names "the 1/3 in the energy" as a checked normalization
**VERDICT: ABSENT**
Evidence: `docs/ARCHITECTURE.md:893-894`, the `/check-docs` bullet, now reads "the ``1/N``, the ``2\varkappa``, the ``\tfrac{1}{2}`` in the energy, Parseval factors" — matches the actual ``k = \tfrac{1}{2}\langle\lvert\boldsymbol{u}\rvert^2\rangle`` definition (line 342, `src/Observables.jl`-referenced notation). No `\tfrac{1}{3}` remains in that sentence.

## 8. energy_spectrum supersession note appended to the wrong decision entry
**VERDICT: ABSENT**
Evidence: The "(Superseded 2026-08-23, owner-directed: `energy_spectrum` now returns the **density**... so the conversion seam this entry documents is gone...)" note now sits at `docs/ARCHITECTURE.md:1003-1006`, inside decision entry 19 ("(2026-07) The measured-vs-predicted validation harness"), which is the entry that actually states the ``E_n`` vs ``E(\kappa)`` bin-sum seam (lines 1000-1002). Checked entry 33 (the memory-audit entry, line 1269) — carries no supersession note. Correctly relocated.

## 9. Bin-sum vocabulary residue: "per-shell energy" survives where corpus says density
**VERDICT: ABSENT**
Evidence: `docs/src/observables_cache.md:362` table row now reads "``E(\kappa_n)``, the spectral density | per shell | no | — | not computed...". `src/Observables.jl:27-28` module map now reads "the energy spectrum reduces to the spectral density sampled on the wavenumber shells". Neither surface still calls the observable "per-shell energy" / ``E_n``.

## 10. §2.4 table breaks its own Built-column rule on the sample-history row
**VERDICT: ABSENT**
Evidence: `docs/src/observables_cache.md:346-348`, the rule now reads "Its **Built** column says whether the package holds the observable today, and reads `—` wherever *Cached* is *no* or *never* (a *depends* row is built whenever its configuration asks for it)." The sample-history row (line 356: Cached=depends, Built=yes) is now an explicit carve-out consistent with the stated rule, not a violation of it.

## 11. MD-thermostat analogy places VarianceController beside Nosé–Hoover
**VERDICT: PRESENT**
Evidence: `src/Forcing.jl:565-571`, the `VarianceController` docstring, unchanged in substance: "The mechanism is the one molecular dynamics settled on for the same problem: ... feedback inside the equations is the Nosé–Hoover move (Nosé 1984; Hoover 1985), and gain-limited relaxation toward a target is Berendsen weak coupling (Berendsen et al. 1984)" immediately following the stated law "``\mathrm{d}k/\mathrm{d}t = -G(k-k_\infty)/t_\ell``" (line 549), which is exactly Berendsen's relaxation form. The three-item list (naive rescaling / Nosé–Hoover / Berendsen) still stands as in the original finding; framing still invites reading the controller as the Nosé–Hoover node.

## 12. "Its host-side random increment is the one allocation-free exception" — self-inverting phrase
**VERDICT: PRESENT**
Evidence: `docs/ARCHITECTURE.md:662-664` unchanged: "it owns its noise scratch (decision 32), and its host-side random increment is the one allocation-free exception (invariant 4)". This still contradicts `docs/ARCHITECTURE.md:1306-1307`, which correctly states "an OU-forced step is not allocation-free today (``\approx 3`` units per step)". The self-inverting preposition at line 663 was not fixed.
