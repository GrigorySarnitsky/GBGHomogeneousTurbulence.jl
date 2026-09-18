# Closure — Hat 18 (Dimensional-analysis & normalization specialist)

## 1. §4.1 "sharp 3/4 rule" default dealias

**VERDICT: ABSENT**

Evidence: `docs/src/architecture.md`/`docs/ARCHITECTURE.md` §4.1 now reads "the dealias kernel of
the run's chosen strategy (the sharp `2/3` rule by default), likewise a compressed symbol."
Searched `rg --glob '!.claude/**' -n "3/4"` across `docs/src`, `docs/ARCHITECTURE.md`, `src` — the
only hit is an unrelated RK abscissa (`c = (0, 1/3, 3/4)`) in `src/Propagator.jl:250`. No "3/4
rule" survives anywhere; §4.1 now agrees with Home, §4.2, §7, `Generator.scalar_rhs!`, and
`SimulationRun`.

## 2. Step-divergence damping factor exp(+νκ²Δt)

**VERDICT: ABSENT**

Evidence: `docs/src/decisions.md:1129` and `docs/ARCHITECTURE.md:2027` both now read
"``\exp(-\nu\kappa^{2}\Delta t)``, nearly nothing at the largest scales." The plus sign is gone;
matches the integrating factor's definition elsewhere in the corpus.

## 3. Developed-cascade skewness written as −0.05 beside 0.5

**VERDICT: ABSENT**

Evidence: `docs/src/decisions.md:49` / `docs/ARCHITECTURE.md:947` now read "against the
``\lvert S\rvert \approx 0.5`` of a developed cascade (``S`` runs from ``0`` toward ``\approx
-0.5``)." Both numbers agree; `rg` for `-0.05` / `-0\.0?5` near "developed cascade" returns nothing.

## 4. §10's check-battery names "the 1/3 in the energy"

**VERDICT: ABSENT**

Evidence: `docs/src/architecture.md:894` / `docs/ARCHITECTURE.md:894` now read "(the ``1/N``, the
``2\varkappa``, the ``\tfrac{1}{2}`` in the energy, Parseval factors)". Matches
``k=\tfrac12\langle|u|^2\rangle`` elsewhere.

## 5. Forcing docstrings still count pre-fusion device readbacks

**VERDICT: ABSENT**

Evidence: `src/Forcing.jl:261` (`add_forcing_source!`) now reads "Measuring the state costs one
blocking device-to-host transfer **at every stage** — a single fused multi-weight reduction
answers `VarianceController`'s three weighted sums together…". `src/Forcing.jl:366`
(`VarianceRescaling`) now reads "Sizing the rescale reduces the field to a number, so each step
blocks on one device-to-host transfer: the band and whole-field observables ride a single fused
traversal, in either mode." Searched for residual "three per stage" / "two under" phrasing —
none found (only the correct "three weighted sums [share] a single fused reduction" survives).

## 6. energy_spectrum density supersession note attached to the wrong decision entry

**VERDICT: ABSENT**

Evidence: `rg "Superseded 2026-08-23"` finds exactly one occurrence, at `docs/src/decisions.md:105`
/ `docs/ARCHITECTURE.md:1003`, which is inside decision 19 — "The measured-vs-predicted validation
harness", the entry that states the per-shell-vs-density seam ("`energy_spectrum` returns the
per-shell energy ``E_n``… `E_n \approx E(\kappa_n)\Delta\kappa`"). Decision 33 (the memory-audit
entry, `docs/src/decisions.md:371`) carries no such note. The parenthetical now sits on the entry
it documents, matching the finding's own resolution_hint.

## 7. Rogallo's TM-81315 dated 1981 vs 1984

**VERDICT: ABSENT**

Evidence: `src/SimulationDomain.jl:114` (the `PhaseShift` docstring) now reads "Rogallo (1981) —
*Numerical experiments in homogeneous turbulence*, NASA TM-81315 (no DOI)". Searched
`rg "1984"` near "Rogallo" across `src`, `docs/src`, `docs/ARCHITECTURE.md` — zero hits. All
citations (decisions entry, §References, `PhaseShift` docstring) now agree on 1981.

## 8. §4.7 writes the scalar variance as ⟨θ²⟩

**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:489` / `docs/src/architecture.md:489` now read "When the scalar is
forced, ``\langle\varphi^2\rangle`` must settle too". Searched for `\theta` / `⟨θ` across
`docs/src/architecture.md` and `docs/ARCHITECTURE.md` — the only occurrence is the invariant-9
rule sentence itself ("never ``\theta``"), not a live use.

## 9. "Per-shell energy" residues survive the density convention

**VERDICT: ABSENT**

Evidence: `src/Observables.jl:27-28` module map now reads "the energy spectrum reduces to … the
spectral density sampled on the wavenumber shells" (no "per-shell energy" phrasing).
`docs/src/observables_cache.md` §2.4 table row now reads "``E(\kappa_n)``, the spectral density |
per shell | no | — | not computed…" — the object is named the spectral density, not ``E_n``/
"the per-shell energy". The one surviving "per-shell energy ``E_n``" phrase
(`docs/ARCHITECTURE.md:1000`) is inside decision 19's historical description of the *pre-2026-08-23*
convention, immediately followed by its own supersession note (see finding 6) — not a live
residue.

## 10. Decision 62's heading says "scheme → integrator"; body says "integration_scheme"

**VERDICT: ABSENT**

Evidence: `docs/src/decisions.md:1141` now reads "62. **(2026-08, user-directed) The `Simulation`
keyword and field `scheme` → `integration_scheme`.**" — heading and body (`integration_scheme`
throughout, lines 1146/1152) and the decision-55 cross-reference at line 978 all agree. Searched
`rg '"scheme".*→.*"integrator"'` and `scheme.*→.*integrator\b` — no hits anywhere in `docs/src` or
`docs/ARCHITECTURE.md`.
