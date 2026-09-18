# Hat 18 — Dimensional-analysis & normalization specialist

Substrate: the rendered-site manuscript only. Every listed factor was expanded and cross-checked
mechanically; the following are the defects that survived. Verified-consistent (no finding):
k = ½⟨|u|²⟩ and ε_φ = 2ϰ⟨|∇φ|²⟩ across all surfaces; C_S = (4/7)√(15/2) ≈ 1.5649 (re-derived from
the quoted Betchov relations 105/8 and 15/2 — exact); L11 = (3π/4)∫(E/κ)/∫E, L22 = L11/2,
L_E = (π/2)∫(E/κ)/∫E = (2/3)L11 (exact); Δκ = 2π/L and k = Σ E(κ_n)Δκ; the phase-shift cutoff
(√2/3)N·(2π/L) = (2√2/3)κ_Ny ≈ 0.94κ_Ny, identical at every site; ℰ = exp((A − D|κ|²)τ) with
coefficient = −Dτ, identical at every site but one (finding 2); CFL: κ_maxΔx = 2π/3, √3/2.09 ≈ 0.83
→ 0.5; the transform table (18/9, 21/18, ×2 for PhaseShift) against the (6,3)/(1,3) per-evaluation
counts and decision 45's 42/28 c2r; G = (3/2)C_ε^(−2/3) and the 0.81-vs-0.9 cross-check (exact);
L11/ℓ₀ = C_ε(2/3)^{3/2} with 0.42k/0.57k (exact); κ_maxη = fπη/Δx with 0.96Δx/0.64Δx/31 %/N^{2/3}
(all exact); Re_λ = u'²√(15/(νε)); the alias-free condition 2κ_max < N per strategy; the
Yaglom −(2/3)ε_φ r full-variance conversion; ζ_p of K41/K62/She–Lévêque (ζ₃ = 1 in each);
Lundgren's (8.45/0.8)^{3/2} ≈ 34; VonKarmanLarge κ⁴ and PopeLargeScale κ^{p₀} slopes;
A = injection_rate/(2E_band) ↔ A = ε/(2k_f); t_ℓ = 2k/(3ε) = (2/3)τ.

---

## 1. [contradiction / blocker / high] §4.1 states the default dealias mask as "the sharp 3/4 rule"

- **Location:** PAGE architecture, §4.1 (SimulationDomain paragraph): "and the dealias kernel of
  the run's chosen strategy (the sharp $3/4$ rule by default)".
- **Contradicts:** PAGE Home, "What it solves": "dealiased by the default $2/3$ rule"; PAGE
  architecture §4.2: "dealiased by the $2/3$ rule"; §7: "the rotational form + spherical $2/3$
  stays the lean default"; PAGE api/Generator `scalar_rhs!`: "the sharp $2/3$ rule by default";
  PAGE api/SimulationRun: "dealiasing = TwoThirds()". Axis: the value of the default dealias
  fraction.
- No "3/4 rule" exists anywhere else in the corpus or in the strategy catalogue (`TwoThirds`,
  `HouLi`, `PhaseShift`). A design-doc reader takes §4.1 as the spec, and 3/4 would even change
  the alias-free condition (2·(3/4) ≥ 1 fails 2κ_max < N). Clear typo for 2/3, but a wrong number
  in the spec's own module section.
- resolution_hint: change $3/4$ → $2/3$.

## 2. [physics / major / high] The step-divergence damping factor carries the wrong sign: exp(+νκ²Δt)

- **Location:** PAGE decisions, the 2026-08 re-projection entry: "whose divergence … is damped only
  by $\exp(+\nu\kappa^{2}\Delta t)$, nearly nothing at the largest scales".
- **Contradicts:** the integrating factor's own definition everywhere else — PAGE notation:
  "$\mathcal{E}(\boldsymbol{\kappa}) = \exp((A(\boldsymbol{\kappa})-D\lvert\boldsymbol{\kappa}\rvert^2)\tau)$";
  PAGE api/Generator `velocity_integrating_factor`: "$\texttt{coefficient} = -\nu\tau$". Axis: the
  sign of the viscous exponent.
- exp(+νκ²Δt) > 1 is amplification, not damping. The entry's own qualifier "nearly nothing at the
  largest scales" is correct only for exp(−νκ²Δt) → 1 as κ → 0, confirming the minus sign was
  intended. This is a current (2026-08) entry, not superseded history.
- resolution_hint: exp(−νκ²Δt).

## 3. [contradiction / major / high] The developed-cascade skewness written as −0.05 beside 0.5 in one sentence

- **Location:** PAGE decisions, the 2026-07 warm-up entry: "against the $\lvert S\rvert \approx
  0.5$ of a developed cascade ($S$ runs from $0$ toward $\approx -0.05$)".
- **Contradicts:** itself (|S| ≈ 0.5 four words earlier), and PAGE api/Observables
  `derivative_skewness`: "fully developed isotropic turbulence has $S \approx -0.5$"; PAGE
  architecture §4.3: "the classical marker $S \approx -0.5$". Axis: the magnitude of the
  developed-turbulence skewness (factor of 10).
- A parenthetical claiming S runs toward −0.05 makes the 0.4 skew_floor advice in the same entry
  unreachable. Numeric typo, but in a physics claim a reader may quote.
- resolution_hint: −0.05 → −0.5.

## 4. [contradiction / major / high] §10's check-battery names "the 1/3 in the energy"

- **Location:** PAGE architecture, §10 Conventions, the `/check-docs` bullet: "the $1/N$, the
  $2\varkappa$, the $\tfrac{1}{3}$ in the energy, Parseval factors".
- **Contradicts:** PAGE architecture §4.3: "$k = \tfrac{1}{2}\langle\lvert\boldsymbol{u}\rvert^2\rangle$";
  PAGE notation Diagnostics table; PAGE api/Observables `kinetic_energy`. Axis: the normalization
  factor in the kinetic energy.
- The battery's whole point is normalization-factor vigilance, and its own exemplar factor is
  wrong: the energy carries ½ (the 1/3 belongs to nothing in the corpus; u' = √(2k/3) has a 3 but
  not "in the energy"). A checklist stating the wrong canonical factor trains the checker wrong.
- resolution_hint: $\tfrac{1}{3}$ → $\tfrac{1}{2}$.

## 5. [contradiction / major / high] Forcing docstrings still count the pre-fusion device readbacks

- **Location:** PAGE api/Forcing `add_forcing_source!`: "Each reduction costs one blocking
  device-to-host transfer, at every stage — three per stage for `VarianceController`"; and
  `VarianceRescaling`: "each step blocks on a device-to-host transfer — two under `:total`".
- **Contradicts:** PAGE decisions, the 2026-08 three-item PF-request entry: the multi-weight fused
  reduction is "wired at every same-field multi-reduction site: `VarianceController` (three weights
  per stage …), `VarianceRescaling`'s `:total` pair", and "the default row fell 10 → 4 crossings
  (one fused reduction per stage plus the $\Delta t$ choice)". Axis: the per-stage/per-step
  readback count after the fused wiring.
- The controller's three reductions are now one traversal and one readback per stage, and
  `:total`'s pair one; the docstrings still price 3/stage and 2/step — the exact counts the
  decision log says fell. Stale cost claims on the user-facing surface.
- resolution_hint: re-price both docstrings to the fused counts (one per stage; one under
  `:total`).

## 6. [contradiction / major / medium] The energy_spectrum density supersession note is attached to the wrong decision entry

- **Location:** PAGE decisions, the memory-audit entry (frozen ledger + liveness bound) ends:
  "(Superseded 2026-08-23, owner-directed: `energy_spectrum` now returns the density — the shell
  energy over $\Delta\kappa$ — so the seam this entry documents is gone …)".
- **Contradicts:** the memory-audit entry documents no spectra seam; the seam ("`energy_spectrum`
  returns the per-shell energy $E_n$, a model returns the density $E(\kappa)$, and $E_n \approx
  E(\kappa_n)\Delta\kappa$") lives in the earlier measured-vs-predicted validation-harness entry,
  which carries no supersession marker. Axis: which entry the per-shell → density convention
  change supersedes.
- The per-shell-vs-density distinction is the manuscript's most factor-sensitive convention; the
  entry that states the old convention reads as un-superseded while an unrelated entry carries the
  retraction. (Adjudication protects old entries' content, not a misplaced supersession note.)
- resolution_hint: move the parenthetical to the validation-harness entry.

## 7. [citation / minor / high] Rogallo's TM-81315 is dated 1981 in References and 1984 in the PhaseShift docstring

- **Location:** PAGE api/SimulationDomain `PhaseShift`: "the spherical truncation of Rogallo
  (1984) — Numerical experiments in homogeneous turbulence, NASA TM-81315".
- **Contradicts:** PAGE decisions (phase-shift entry): "Patterson & Orszag 1971, Rogallo 1981";
  PAGE architecture §References: "Rogallo, R. S. (1981). Numerical experiments in homogeneous
  turbulence. NASA TM-81315." Axis: the year of one and the same technical memorandum.
- Same document, two years; 1981 is correct.

## 8. [contradiction / minor / high] §4.7 writes the scalar variance as ⟨θ²⟩, violating the document's own φ-never-θ invariant

- **Location:** PAGE architecture §4.7: "When the scalar is forced, $\langle\theta^2\rangle$ must
  settle too".
- **Contradicts:** PAGE architecture §9: "The scalar is denoted $\varphi$, never $\theta$ — in
  code, mathematics, and prose"; the same gate is written $\langle\varphi^2\rangle$ in the
  decisions-page warm-up entry and in `StationarityCriterion`. Axis: the scalar's symbol.
- One glyph slip, but it breaks a build-enforced-elsewhere house rule inside the document that
  states the rule.

## 9. [contradiction / minor / medium] "Per-shell energy" residues survive the density convention

- **Location:** PAGE api/Observables module map: "the energy spectrum reduces to a per-shell
  energy over wavenumber"; PAGE observables_cache §2.4 table: "$E_n$, the per-shell energy".
- **Contradicts:** PAGE notation: "$E(\kappa_n)$ … the shell's energy over the shell width … the
  same kind of object as a model $E(\kappa)$"; PAGE api/Observables `energy_spectrum`: "the
  measured kinetic-energy spectral density". Axis: whether the measured object is a per-shell
  energy $E_n$ or a density $E(\kappa_n) = E_n/\Delta\kappa$.
- The module map's "per-shell energy over wavenumber" is at best ambiguous (it can parse as the
  stale bin-sum), and the design page's table row still names the object $E_n$, "the per-shell
  energy". On the default $2\pi$ box the factor is 1, which is exactly how the old convention hid
  the last time.
- resolution_hint: "the spectral density (the shell energy over the shell width)" in both.

## 10. [contradiction / minor / high] Decision 62's heading says "scheme → integrator"; its body and the API say "integration_scheme"

- **Location:** PAGE decisions: "The `Simulation` keyword and field `scheme` → `integrator`. …
  The keyword family is now uniformly `<role>_scheme`: `integration_scheme` …".
- **Contradicts:** its own body, the decision-55 cross-reference ("Refined 2026-08-23, decision
  62: the `Simulation` keyword and field are now the qualified `integration_scheme`"), and PAGE
  api/SimulationRun (`integration_scheme = IFLowStorageRK3()`). Axis: the name the keyword was
  renamed to.
- The heading names a rename to `integrator` that the entry itself then argues against (the SciML
  false cognate the same log retired). A reader skimming headings records the wrong rename.
