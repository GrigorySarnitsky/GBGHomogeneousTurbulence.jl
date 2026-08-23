# Hat 08 — Dimensional analysis & normalization

Mechanical verification pass over every formula, factor and cross-page repetition.

## What verified CLEAN (recorded so a later round does not re-derive it)

- `k = ½⟨|u|²⟩`, `ε = ν⟨|ω|²⟩ = 2ν⟨S:S⟩`, `⟨φ²⟩`, `ε_φ = 2ϰ⟨|∇φ|²⟩` — identical on every surface (Home, ARCHITECTURE §4.3, notation, Observables, Forcing).
- `u' = √(2k/3)`, `k = 3/2 u'²`, `kinetic_energy = 1.5 ⇒ u' = 1` — consistent everywhere.
- `η = (ν³/ε)^{1/4}`, `τ_η = (ν/ε)^{1/2}`, `λ = √(15νu'²/ε)`, `Re_λ = u'λ/ν = u'²√(15/(νε))` — all mutually consistent.
- `L11 = (3π/4)∫(E/κ)dκ/∫E dκ`, `L22 = L11/2`, `L_E = (π/2)∫(E/κ)/∫E = (2/3)L11 = ⅓(L11+2L22)` — the π factors and the isotropic average check out exactly.
- `C_S = (4/7)√(15/2) ≈ 1.5649`; independently re-derived as `(8/105)(15/2)^{3/2}` from the two stated Betchov relations `⟨tr S³⟩ = (105/8)⟨(∂ₓ₁u₁)³⟩`, `⟨S:S⟩ = (15/2)⟨(∂ₓ₁u₁)²⟩`. The extra `3` in `3C_S⟨det S⟩/…` is correct (`tr S³ = 3 det S`). Sign correct.
- Phase-shift cutoff: `√2N/3·2π/L = (2√2/3)κ_Ny ≈ 0.94κ_Ny`, `√2` wider than `2/3`, `(√2)³ ≈ 2.8×` the modes — the SAME number in ARCHITECTURE §7, decision 27, notation, `PhaseShift`, `DealiasingStrategy`, `max_wavenumber`, `truncate_to_band!`, `kinetic_energy`. No drift.
- `κ_max = f(N/2)(2π/L)`, `κ_maxΔx = fπ`, `κ_maxη = fπη/Δx`; `κ_max_η = 2, f = 2/3 ⇒ Δx ≈ η`; `Re_λ ~ N^{2/3}`.
- CFL: `y_s = √3`, `κ_maxΔx = 2π/3 ≈ 2.09`, `√3/2.09 = 0.83` → conservative `0.5`. `|R(iy)|² = 1 + y⁴/4` for `R(z) = 1+z+z²/2`. RKW3 `A,B,d` sum/abscissae consistent (`Σd = 1`, `c = (0,1/3,3/4)`).
- Integrating factor `exp((A − D|κ|²)τ)` with `coefficient = −Dτ, offset_scale = τ, offset = Â` — expands correctly; identical in ARCHITECTURE §4.2, notation, `velocity_integrating_factor`, observables_cache §2.2. IFRK2's two lines are the exact IF-Heun.
- `E_n` vs `E(κ)`: shell width `Δκ = 2π/L`, `E_n ≈ E(κ_n)Δκ`, `=1` on the `2π` box, cancels in `integral_scale`'s ratio. Consistent.
- Transform ledgers: `(6,3)` velocity + `(1,3)` scalar per mask stage ⇒ 18/9, 21/18, and `PhaseShift` exactly 2× ⇒ 36/18, 42/36; matches decision 45's `RK3 51→42`, `RK2 34→28`.
- Memory arithmetic: 384 MiB/vector at 256³/F64, 768 MiB for two, 2.3 GiB for 4 spectral + 2 physical, 322.5 MiB frame (= 5 spectral-scalar units), 2.52 GiB at 512³, `10 → 6` field count. All reproduce.
- `ConstantPower`: injection `2A E_band` and `A = injection_rate/(2E_band)` — correct for BOTH the velocity (`E_band = ½Σ|û|²`) and the scalar (`E_band = ⟨φ²⟩`).
- Phenomenology: `G = (3/2)C_ε^{−2/3}`, `ε = (k/G)^{3/2}/L`, `L/L11 ≈ 5 ⇒ G ≈ 0.81`; `L11/L0 = C_ε(2/3)^{3/2}` ⇒ `3.7×`/`0.42k` and `2.3×`/`0.57k`; `ζ_p` for K62 and She–Lévêque both exact at `ζ₃ = 1`; Lundgren zero at `Re_λ ≈ 34`, half the coefficient at `Re_λ = 100`; Yaglom `−(4/3)ϰ⟨|∇φ|²⟩r = −(2/3)ε_φ r` — the half/full-variance conversion is CORRECT; `C_OC = 0.67` is the 3-D value consistent with Sreenivasan's 1-D `0.4` (`5/3` factor); Pope `p₀=2 ⇒ κ²`, von Kármán `17/6 ⇒ κ⁴`; `HouLi` auto-strength `−log(eps)` ≈ 36/16.

---

## Finding 1 — The assumed initial state carries an ε and an L₁₁ that contradict each other

- **type**: dimensional
- **severity**: major
- **confidence**: medium
- **locations**:
  - PAGE: api / SimulationRun, `Simulation`, `initial_spectrum` argument: "ε from the `Li2008` stationary-dissipation law … and the integral scale as `1/envelope_wavenumber`"
  - PAGE: api / phenomenology / Scalings, `Li2008`: "the quoted G ≈ 0.9 (box side) and C_ε ≈ 0.5 (integral scale) sit at different lengths (L/L₁₁ ≈ 5)"
- **contradicts**: `Li2008` — "L/L_{11} \approx 5" — axis: the value of L₁₁ implied by the two halves of one `FlowParameters` bundle.
- **description**: The assumed state fed to a model spectrum takes ε from `Li2008`, whose own calibration presumes `L₁₁ ≈ L/5 ≈ 1.26` on the default `2π` box, while asserting `L₁₁ = 1/κ_p = 0.5` — a factor ≈ 2.5 disagreement inside one bundle. Since `∫E dκ ∝ L^{2/3}` (stated in `large_scale_length`), that mis-places the large-scale roll-off by ≈ 0.54 in energy weight. Independently, the package's own `integral_scale` applied to the documented default envelope `κ²exp(−2κ²/κ_p²)` gives `L₁₁ = (3π/4)(1.60/κ_p) ≈ 3.8/κ_p`, not `1/κ_p`.
- **resolution_hint**: State which convention `1/envelope_wavenumber` is meant to be (a nominal large scale, not L₁₁), or derive the assumed L₁₁ from the same law the assumed ε comes from.

## Finding 2 — The spectrum normalization flips between velocity (half-energy) and scalar (full variance), and the glossary never pins it

- **type**: dimensional
- **severity**: minor
- **confidence**: high
- **locations**:
  - PAGE: notation, Diagnostics table: "$E(\kappa)$ … $k = \int_0^\infty E(\kappa)\,\mathrm{d}\kappa$ (dimensions $L^3T^{-2}$)" — and no row for $E_\varphi(\kappa)$
  - PAGE: api / phenomenology / Spectra, `ScalarSpectrum`: "the density in wavenumber of the scalar variance $\langle\varphi^2\rangle$"
- **contradicts**: the two spectra normalize to quantities differing by a factor 2 in convention (`k = ½⟨|u|²⟩` vs the FULL `⟨φ²⟩`); axis: half- vs full-variance normalization.
- **description**: `E(κ)` integrates to the half-energy `k`; `E_φ(κ)` integrates to the full variance `⟨φ²⟩`. Both are individually standard and individually correct, but the ×2 asymmetry is exactly the factor `Yaglom1949` and `ObukhovCorrsin1949` each spend a paragraph on — and `notation.md`, "the single reference", carries no `E_φ(κ)` row at all, so the one page a reader consults for a normalization is silent on the one place the corpus changes conventions.
- **resolution_hint**: Add an `E_φ(κ)` row stating `⟨φ²⟩ = ∫E_φ dκ` beside the `E(κ)` row, and note the deliberate asymmetry.

## Finding 3 — `IFRK2`'s CFL is scaled by a relation the same docstring calls degenerate for that scheme

- **type**: dimensional
- **severity**: minor
- **confidence**: medium
- **locations**:
  - PAGE: api / Propagator, `recommended_cfl`: "`IFRK2` is imaginary-axis unstable ($y_s = 0$), which makes the formula degenerate — its $0.25$ is an empirical margin, not a computed limit"
  - PAGE: api / Propagator, `recommended_cfl`: "It scales that base by the domain's dealiasing … $C_{\mathrm{CFL}} \propto 1/\kappa_{\max}$"
- **contradicts**: same docstring, two paragraphs apart; axis: whether the `y_s/(κ_max Δx)` relation applies to `IFRK2`.
- **description**: The `1/κ_max` scaling is derived from `C_CFL = y_s/(κ_maxΔx)`. For `IFRK2` the docstring states that formula is degenerate (`y_s = 0`) and that `0.25` comes from empirics, not from it — yet the strategy scaling is then applied to that empirical number as though it inherited the relation. Under `HouLi` this hands `IFRK2` a `0.167` whose provenance is neither measured nor computed, at precisely the low-ν regime the adjacent admonition warns about.
- **resolution_hint**: Say explicitly that the dealiasing scaling is applied to both schemes as a stability-conservative heuristic, and that for `IFRK2` it inherits the margin's empirical status.

## Finding 4 — `envelope_wavenumber`: "no effect" on one page, "sets the integral scale" on another

- **type**: contradiction
- **severity**: minor
- **confidence**: medium
- **locations**:
  - PAGE: api / State, `random_solenoidal_velocity_spectral!`: "The `envelope_wavenumber` setting has no effect in the `initial_spectrum` branch below"
  - PAGE: api / SimulationRun, `Simulation`: "it also sets the integral scale in the assumed state `initial_spectrum` reads"
- **contradicts**: the two quotes above; axis: whether `envelope_wavenumber` influences the `initial_spectrum` path.
- **description**: Both are true at different levels — the seeder ignores it once a spectrum function is supplied, but the front door consumed it earlier to build the assumed `FlowParameters` that generated that function, so the seeded field's large scale does depend on it. As written the two sentences read as flat contradiction, and the one that matters dimensionally (the length the model's roll-off is positioned at) is the front door's.
- **resolution_hint**: Qualify the seeder's sentence: "no effect on the shape in this branch — the front door has already used it to fix the assumed integral scale."

## Finding 5 — `PhaseShift`'s stated scratch cost does not match the registers the decision log names

- **type**: other
- **severity**: minor
- **confidence**: low
- **locations**:
  - PAGE: api / SimulationDomain, `PhaseShift`: "the displaced-evaluation scratch (a field-scale spectral-representation buffer per phase-shifted term)"
  - PAGE: architecture, decision (2026-08): "`velocity_rhs!` marks the generator's `u_shifted` fresh after its displaced recovery (its displaced Lamb consumes only `ω_shifted`…)"
- **contradicts**: the two quotes; axis: how many displaced buffers, and in which representation.
- **description**: The velocity term alone is documented to hold `u_shifted` and `ω_shifted`, and a "displaced recovery" consumed by a pointwise flux is a field in PHYSICAL representation — so "one spectral-representation buffer per phase-shifted term" understates both the count and misstates the representation. Decision 27's "a displaced-evaluation scratch field" (singular) reads the same way. This is the one memory figure the dealiasing memory↔compute trade rests on.
- **resolution_hint**: State the actual displaced working set per term (spectral shift target plus the physical recoveries it feeds).

## Finding 6 — The energy spectrum called "a distribution over wavenumber" where the corpus insists it is not a density

- **type**: dimensional
- **severity**: minor
- **confidence**: medium
- **locations**:
  - PAGE: api / Observables, module docstring: "the energy spectrum reduces to a distribution over wavenumber"
  - PAGE: api / Observables, `energy_spectrum`: "a per-shell energy $E_n$ … a model spectrum $E(\kappa)$ … is instead a density per unit wavenumber"
- **contradicts**: the two quotes; axis: per-shell energy (`L²T⁻²`) vs spectral density (`L³T⁻²`).
- **description**: "A distribution over wavenumber" is the reading the rest of the corpus works hard to forbid — ARCHITECTURE §4.3, the notation glossary and `energy_spectrum` all insist `E_n` is a per-shell energy and NOT the density `E(κ)`, differing by `Δκ = 2π/L`. The module map is the first thing a reader meets, and it re-introduces the density reading in the one sentence the class-fix did not sweep.
- **resolution_hint**: "…reduces to a per-shell energy over wavenumber shells."

## Finding 7 — The "single reference" glossary omits `κ_Ny` and `κ_p`, both then defined inline repeatedly

- **type**: format
- **severity**: minor
- **confidence**: high
- **locations**:
  - PAGE: notation: "This page is the single reference — a docstring introduces a symbol on first use and need not repeat the convention."
  - PAGE: api / SimulationDomain, `TwoThirds` / `HouLi` / `PhaseShift`: "$\kappa_{\mathrm{Ny}} = \tfrac{N}{2}\cdot\tfrac{2\pi}{L}$" (three times)
- **contradicts**: the stated no-repeat convention; axis: which symbols the glossary owns.
- **description**: `κ_Ny` — the wavenumber every dealiasing cutoff is quoted against — has no glossary row, so its definition is restated verbatim in three consecutive docstrings, exactly the repetition the page exists to prevent (and exactly where a future drift between `(N/2)(2π/L)` and `π/Δx` would go unnoticed). `κ_p` (`envelope_wavenumber`), which appears in both initial-condition docstrings and in `Simulation`, is likewise absent.
- **resolution_hint**: Add `κ_Ny` to the Numerics table beside `κ_max`, and `κ_p` beside them.

## Finding 8 — The deferred-bottleneck note carries a negative exponent where the cited fits carry a positive one

- **type**: physics
- **severity**: minor
- **confidence**: low
- **locations**:
  - PAGE: api / phenomenology / Spectra, `DissipationFactor` admonition: "all of the form $A(\kappa\eta)^\gamma\exp(-\beta\kappa\eta)$ with $\gamma < 0$"
  - PAGE: api / phenomenology / Spectra, `ExponentialDissipation`: "consistent with Chen et al. 1993 …, $\beta \approx 7.1$"
- **contradicts**: the cited far-dissipation family; axis: sign of the power-law prefactor exponent.
- **description**: The published far-dissipation / bottleneck fits of that family are `E(κ) ∝ (κη)^α exp(−βκη)` with α ≈ 3.3 POSITIVE (Chen et al. 1993, the very paper cited two docstrings later); recast as a factor on the `κ^{-5/3}` core the exponent is more positive still. The stated reason these forms "do not satisfy `f_η → 1`" survives either way — a positive exponent sends `f_η → 0`, a negative one diverges — so the sign looks transcribed rather than derived.
- **resolution_hint**: Re-derive γ for the factor convention (`f_η = E/(C_K ε^{2/3}κ^{-5/3})`) and state whether γ is quoted for `E` or for `f_η`.

## Finding 9 — Grid mode's `HouLi` caveat does not say which way the estimate errs

- **type**: dimensional
- **severity**: nit
- **confidence**: medium
- **locations**:
  - PAGE: api / SimulationRun, `Simulation`: "approximate for `HouLi`, whose top of band is damped rather than exactly dealiased"
  - PAGE: api / SimulationDomain, `max_wavenumber`: "$f$ the retained-Nyquist fraction … $1$ for `HouLi`"
- **description**: With `f = 1` the criterion `κ_maxη = 2` is evaluated at the full Nyquist wavenumber, where `HouLi` has already damped the field to machine epsilon — so grid mode credits the run with resolution it does not have and returns a ν that is too SMALL (Re too high). The CFL uses the same `f = 1` in the safe direction. The docstring flags the approximation but not its sign, which is the part a user setting up a `HouLi` run needs.
- **resolution_hint**: One clause: "…so grid mode over-states `HouLi`'s effective resolution and under-states the ν a given grid supports."
