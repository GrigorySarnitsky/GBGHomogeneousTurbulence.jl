# Dimensional-Analysis & Normalization audit — GBGIsotropicTurbulence rendered docs

Hat: **DIMENSIONAL-ANALYSIS & NORMALIZATION specialist**. I mechanically checked every
formula for dimensional consistency and every normalization factor (the ½ in kinetic
energy, the 2ϰ in scalar dissipation, the spectrum halving, the integrating-factor
exponent, transform/Parseval factors, CFL and dealiasing factors, the derived-scale
constants) for correctness *and* cross-page identity.

**What checks out (verified, no defect):** the ½/no-½ split between kinetic energy
`(1/2)⟨|u|²⟩` and scalar variance `⟨φ²⟩` and their dissipations `ν⟨|ω|²⟩` / `2ϰ⟨|∇φ|²⟩`
(each internally consistent with its own budget `dk/dt=−ε`, `d⟨φ²⟩/dt=−ε_φ`; the docs even
flag the asymmetry explicitly in `BandRescaling`); the energy-spectrum **halving** (stated
identically in Notation, Observables, Architecture §4.3); the Betchov skewness constant
`C = (4/7)√(15/2) ≈ 1.5649` (I re-derived it from the stated `⟨trS³⟩=(105/8)⟨(∂₁u₁)³⟩` and
`⟨S:S⟩=(15/2)⟨(∂₁u₁)²⟩`, and `trS³=3detS`); the dealias band `κ_max = f·(N/2)·(2π/L)` with
`f = 2/3, 1, 2√2/3` (identical across Notation, `TwoThirds`, `PhaseShift`, `max_wavenumber`,
`recommended_cfl`'s `κ_maxΔx=2π/3`, and decision 27; `2√2/3≈0.94`, `(√2)³≈2.8×` modes all
consistent); `u'=√(2k/3) ⇔ k=(3/2)u'²` (Notation, `flow_parameters`, `FlowParameters`);
`η,τ_η,λ,Re_λ` and `ε=15νu'²/λ²`; the Williamson RK3 coefficients (`d` sums to 1,
`d_i=c_{i+1}−c_i`); the IF-RK2 stability `|R(iy)|²=1+y⁴/4`; the integrating-factor exponent
`exp((A−D|κ|²)Δt)` and its `D=ν`/`D=ϰ=ν/Sc` split (Notation, `integrating_factor!`, §4.2);
every `Spectra` roll-off exponent (`PopeLargeScale 5/3+p₀→σ=2`, `VonKarmanLarge 17/6→κ⁴`,
`Pao −(3/2)C_K(κη)^{4/3}`); all structure-function laws and intermittency exponents
(`ζ₃=1` for both K62 and She–Lévêque); and `stationary_dissipation ε=(k/G)^{3/2}/L` (correct
inverse of `k/(Lε)^{2/3}=G`). The dimensional core of the package is sound.

The findings below are the residual normalization/typing inconsistencies.

---

## Finding 1 — Measured `energy_spectrum` is typed as BOTH a spectral density and a per-shell energy, then compared against a genuine density model spectrum

- **type:** dimensional
- **severity:** major
- **confidence:** high

**Locations (exact rendered quotes):**

- PAGE: Notation — *Diagnostics* table:
  "`$E(\kappa)$` | energy spectrum (**energy per unit wavenumber**), `$k = \sum_\kappa E(\kappa)$` | `energy_spectrum` (the `GBGPeriodicFields` radial spectrum, halved)"
- PAGE: API — Observables — *Spectrum and length scale* (`energy_spectrum`):
  "the turbulent kinetic energy resolved over wavenumber-magnitude shells, `$k = \sum_\kappa E(\kappa)$`. Returns `(κ, E)`: the shell-center wavenumber magnitudes and **the energy in each shell** …"
- PAGE: Phenomenology — Reference laws — *The law interface* (`spectrum`):
  "the velocity energy spectrum `$E(\kappa)$` … (**the density in wavenumber** of the kinetic energy, `$k = \int_0^\infty E(\kappa)\,d\kappa$`)"
- PAGE: API — SimulationRun — *Flow parameters and spectrum validation* (`validate_spectrum`):
  "the measured and predicted `$E(\kappa)$`, and the **relative L² discrepancy** over the resolved (non-empty) shells."

**contradicts:** The *same object* — the return value of `energy_spectrum` — is called
"energy **per unit wavenumber**" (Notation: a density, units L³/T²) and "the energy **in each
shell**" (Observables: a shell-integrated energy, units L²/T²). Axis of disagreement: **density
vs. integrated quantity** (they differ by the shell width Δκ). Simultaneously, the *model*
spectrum it is compared against is unambiguously a density, `k = ∫₀^∞ E dκ`, whereas the
measured one satisfies `k = Σ_κ E(κ)` (a bare sum, no Δκ).

**Description:**
A per-unit-wavenumber density `E(κ)` and a per-shell energy differ by the shell width
`Δκ = 2π/L`: `E_shell(κ_n) = E_density(κ_n)·Δκ`. The measured spectrum is described (and
normalized, `k = Σ_κ E`) as a **per-shell energy**, yet Notation labels it "energy per unit
wavenumber" (a **density**) — an internal dimensional contradiction. The model spectra
(`ModelSpectrum`, `spectrum`, `ScalarSpectrum`) are genuine densities (`k = ∫E dκ`). Because
`validate_spectrum` sets the two side by side and reports a pointwise relative-L² discrepancy,
the comparison silently omits a `Δκ = 2π/L` factor. It is `1` only for the **default box
`side_length = 2π`**; for any other `side_length` the measured (shell-energy) and predicted
(density) curves differ by a constant `2π/L` even for a perfect run, so the reported discrepancy
is spurious. Recommended: state one convention for the *measured* `E(κ)` — either divide the
shell sum by `Δκ` to make it a true density that integrates to `k` (matching the model and the
`k = ∫E dκ` / `L_{11}` formulas), or make the model comparison sum-based. Note the ratio-form
`integral_scale = (3π/4)∫(E/κ)dκ/∫E dκ` is immune (Δκ cancels), so this only bites
`validate_spectrum` and the density-vs-shell-energy labeling.

**resolution_hint:** Pick one normalization for the measured `E(κ)` (density, integrating to
`k`) and make Notation, `energy_spectrum`, and `validate_spectrum` all state it; if the measured
value stays a per-shell energy, `validate_spectrum` must multiply the model density by `Δκ`
before differencing.

---

## Finding 2 — `Li2008`: `k/(Lε)^{2/3}` is NOT `C_ε = εL/u'³` "written with the box side"; the two are different dimensionless groups (related by a −3/2 power), and the "≈0.5 becomes ≈0.9" substitution is numerically wrong

- **type:** dimensional
- **severity:** minor
- **confidence:** medium

**Locations (exact rendered quotes):**

- PAGE: Phenomenology — Scalings — *Laws* (`Li2008`):
  "The box-normalized dissipation group `$\frac{k}{(L\varepsilon)^{2/3}} \approx 0.9$` … It is the
  dissipation anomaly / normalized-dissipation law `$C_\varepsilon = \varepsilon L/u'^3$` (Taylor
  1935; Sreenivasan 1998; Kaneda et al. 2003 for the periodic box) **written with the box side in
  place of the integral scale**, which folds the setup-dependent integral-scale-to-box ratio into
  the constant (**≈0.5 becomes ≈0.9**)."
- Cross-reference — PAGE: Phenomenology — Scalings (`Sreenivasan1998`):
  "`$C_\varepsilon = \varepsilon L/u'^3$` … approaches a constant of order `$0.5$`".

**Description:**
`C_ε = εL/u'³` and the Li group `G = k/(Lε)^{2/3}` are **not the same functional form** — using
`u'³ = (2k/3)^{3/2}`, one finds `G = (3/2)·C_ε^{-2/3}` (a −3/2 power relation, not a substitution
of the length scale). So "written with the box side in place of the integral scale" is not what
turns `C_ε` into `G`. Concretely, literally substituting the box side into `C_ε = εL/u'³` gives
`C_ε(box) = (3/2)^{3/2}/G^{3/2} ≈ (3/(2·0.9))^{3/2} ≈ 2.15`, **not 0.9** — the value `0.9` is that
of the *distinct* group `k/(Lε)^{2/3}`, whose corresponding `C_ε(box)` is ≈2.15. The narrative
"≈0.5 becomes ≈0.9" therefore conflates the value of one dimensionless group (`G`) with that of
another (`C_ε` with a swapped length). Both groups are dimensionless and the operational inverse
`ε = (k/G)^{3/2}/L` is correct, so this is a narrative/definitional slip in one docstring, not a
compute error — but it is exactly the "one dimensionless group presented as another" category the
docs elsewhere warn against.

**resolution_hint:** Either state the exact relation `G = (3/2)·C_ε^{−2/3}` (so the "≈0.5 ↔ ≈0.9"
mapping is `0.9 = (3/2)·0.5^{−2/3}·…` done honestly), or drop the "written with the box side in
place of the integral scale" phrasing and present `k/(Lε)^{2/3}` as its own box-normalized group.

---

## Finding 3 — The symbol `L` denotes two different physical lengths (box side vs. integral scale `L₁₁`); the model-spectrum roll-off argument `κL` uses `L₁₁` while Notation/`κ_max`/`Li2008` use the box side

- **type:** dimensional
- **severity:** minor
- **confidence:** medium

**Locations (exact rendered quotes):**

- PAGE: Notation — *Numerics* table: "`$L$` | box side (`$\Omega = [0,L)^3$`) | `side_length`"
  (also `κ_max = f·(N/2)·(2π/L)` and `Li2008`'s `ε=(k/G)^{3/2}/L` use `L` = box side).
- PAGE: Phenomenology — Spectra — *The composed spectrum* (`ModelSpectrum`):
  "`$E(\kappa) = C_K\,\varepsilon^{2/3}\,\kappa^{-5/3}\,f_L(\kappa L)\,f_\eta(\kappa\eta)$` …
  Evaluated by `spectrum(model, κ, fp)`, which **reads `$\varepsilon$` and `$L$` from `fp`** and
  forms `$\eta$` with `kolmogorov_length`."
- PAGE: Phenomenology — Reference laws — *The flow-state bundle* (`FlowParameters`):
  "`integral_scale` — the longitudinal integral length `$L_{11}$`".
- PAGE: Architecture — decision 20 (2026-07): "`flow_parameters` bridges a `Simulation` to a
  `Phenomenology` `FlowParameters` (`$\nu$`, `$\varepsilon$`, `$u'$`, **`$L$`** from the measured
  state)" — here bare `$L$` is the measured `integral_scale` = `L₁₁`.

**contradicts:** Notation binds `$L$` ≡ box side (`side_length`); but in `f_L(κL)` the `$L$` is
read from `fp`, whose only length is `integral_scale = L₁₁`, and decision 20 writes bare `$L$` for
that same `L₁₁`. Axis of disagreement: **which length `L` names** (periodic-box side vs.
energy-containing integral scale) — two different numbers (e.g. box `2π` vs. an IC integral scale
`1/peak_wavenumber = 0.5`).

**Description:**
Both are lengths, so nothing is dimensionally *inconsistent*, but the glyph `L` is overloaded:
the roll-off `f_L(κL)` bends the spectrum at the **integral scale** (`L = L₁₁`, correct physics),
while Notation, the `κ_max` formulas, and `Li2008` reserve `L` for the **box side**. A reader who
maps the `L` in `f_L(κL)` to Notation's `L` (box side) would evaluate the large-scale roll-off at
the wrong scale (here off by `L_box/L₁₁ ≈ 4×`). The clash is sharpest in `Li2008`, where `L` = box
side, sitting one module away from `ModelSpectrum`, where `L` = `L₁₁`.

**resolution_hint:** Reserve `L` for the box side (per Notation) and write the integral scale as
`L₁₁` everywhere it appears — `f_L(κL₁₁)`, "reads `ε` and `L₁₁` from `fp`", and decision 20's list
`(ν, ε, u', L₁₁)`.

---

## Finding 4 — "`k_max_η = 2` means `Δx ≈ η`" is stated as general but holds only for the default `2/3` rule; with `HouLi` (f = 1) the same criterion gives `Δx ≈ 1.57 η`

- **type:** dimensional
- **severity:** minor
- **confidence:** medium

**Locations (exact rendered quotes):**

- PAGE: API — SimulationRun — *The simulation* (`Simulation`, grid mode):
  "Since `$\kappa_{\max}\eta = f\pi\,\eta/\Delta x$` with `$f$` the retained-Nyquist fraction,
  `k_max_η = 2` means `$\Delta x \approx \eta$`."
- PAGE: API — SimulationDomain — `max_wavenumber`: "`$f$` the retained-Nyquist fraction … (`$2/3$`
  for `TwoThirds`, **`$1$` for `HouLi`**, `$2\sqrt2/3$` for `PhaseShift`)".

**Description:**
The relation `κ_max η = fπ·η/Δx` is correct and carries the general `f`. But the conclusion
"`k_max_η = 2` means `Δx ≈ η`" is `f`-specific: solving `2 = fπ·η/Δx`,
- `f = 2/3` (default `TwoThirds`): `η/Δx = 3/π ≈ 0.955`, so `Δx ≈ 1.05 η ≈ η` ✓;
- `f = 1` (`HouLi`): `η/Δx = 2/π ≈ 0.637`, so `Δx ≈ 1.57 η` — **not** `≈ η`;
- `f = 2√2/3` (`PhaseShift`): `Δx ≈ 1.48 η`.

Presenting "`Δx ≈ η`" immediately after introducing a *general* `f` reads as if it were
`f`-independent; it is only the `f = 2/3` special case. Minor, but it is a resolution/normalization
statement that changes by ~50% across the (documented, selectable) dealiasing options.

**resolution_hint:** Qualify the conclusion — e.g. "for the default `2/3` rule (`f = 2/3`),
`k_max_η = 2` gives `Δx ≈ η`; a higher-`f` strategy resolves a finer `Δx` for the same
`k_max_η`" — or express the criterion directly as `Δx = fπη/k_max_η`.

---

## Finding 5 — `peak_wavenumber` `κ_p` does not locate the initial energy-spectrum peak for the default Gaussian envelope; the shell-summed spectrum peaks at `κ_p/√2`

- **type:** physics
- **severity:** nit
- **confidence:** low

**Locations (exact rendered quotes):**

- PAGE: API — State — *Random initial conditions* (`random_solenoidal_velocity!`):
  "the velocity is concentrated at large scales by the Gaussian envelope
  `$\exp\!\big(-\lvert\boldsymbol{\kappa}\rvert^{2}/\kappa_p^{2}\big)$` (`$\kappa_p$` is
  `peak_wavenumber`)".
- PAGE: API — SimulationRun — *The simulation* (`Simulation`):
  "`peak_wavenumber = 2.0` — … the **large-scale spectral peak** of the initial condition."

**Description:**
The envelope multiplies the mode **amplitudes** by `exp(−|κ|²/κ_p²)`, so the shell-summed energy
spectrum is `∝ κ²·exp(−2κ²/κ_p²)` (the `κ²` is the shell mode count the same docstring cites for
the `spectrum`-path). That peaks where `d/dκ[κ²exp(−2κ²/κ_p²)] = 0`, i.e. `κ = κ_p/√2 ≈ 0.707 κ_p`,
not at `κ_p`. So the argument named `peak_wavenumber` (and described as "the large-scale spectral
peak") sits a factor `√2` above the actual spectral peak of the default IC. For the `spectrum`-path
(`∝ E(κ)`) the peak is wherever the supplied `E` peaks, so the name is only loose for the default
Gaussian. Low confidence — this may be an accepted "characteristic wavenumber" naming rather than
a literal peak — but flagged because the docstring explicitly calls it the "spectral peak."

**resolution_hint:** Either describe `κ_p` as the Gaussian envelope's characteristic wavenumber
(peak at `κ_p/√2`), or center the envelope so the shell-summed spectrum peaks at `κ_p`.
