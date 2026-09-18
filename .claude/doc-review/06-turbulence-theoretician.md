# Hat: Turbulence theoretician — rendered-docs audit

Substrate: `manuscript-full.md` (the full rendered site). Every formula, constant, and scaling
relation was expanded and checked; the list below is what did not survive. Verified clean (not
findings): the strain-skewness constant C_S = (4/7)√(15/2) against the Betchov isotropy relations;
ε = ν⟨|ω|²⟩ = 2ν⟨S:S⟩ with the dilatation as the exact difference; the Yaglom −(2/3)ε_φ r form
(derived from the Kármán–Howarth–Yaglom balance — the classical −4/3 does pair with ϰ⟨|∇φ|²⟩);
L11 = (3π/4)∫(E/κ)/∫E, L_E = (2/3)L11, λ = √(15νu′²/ε), Re_λ = u′²√(15/(νε)); the L11/ℓ0 =
C_ε(2/3)^{3/2} conversion and its 0.42k / 0.57k integrals; G = (3/2)C_ε^{−2/3} and the 0.81-vs-0.9
cross-check; the κ_p/√2 envelope peak; the 2κ_max < N alias-free condition; the CFL algebra
(2π/3 · 0.83 → 0.5); HouLi's η = 0.64Δx vs 0.96Δx and the 31% Re_λ gap (ν ∝ f^{−4/3});
Re_λ ~ N^{2/3}; the transform tables (21/18, 42/36; 51→42, 34→28); the controller's
dk/dt = −G(k−k∞)/t_ℓ and the gain-0 marginal law; |R(iy)|² = 1 + y⁴/4 for Heun; the 4-point
Gauss–Legendre order-8 cap; the von Kármán 17/6 ↔ κ⁴ identity; the K62 and She–Lévêque exponents
(ζ₃ = 1 both); Lundgren's Re_λ ≈ 34 sign floor.

---

## 1. Pao's hypothesis is mis-stated as "constant spectral flux through the dissipation range"

- **type**: physics · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: api / phenomenology / Spectra, `PaoDissipation`: "from the hypothesis that the spectral
    energy flux stays constant through the dissipation range"
  - PAGE: api / phenomenology / Spectra, `Pao1965`: "It covers the inertial and dissipation ranges
    from a constant-spectral-flux hypothesis"
- **contradicts**: the displayed formula itself — a flux constant through the dissipation range
  yields no cutoff at all.
- **description**: Pao's 1965 closure assumes the *cascade rate* (the flux-to-spectrum ratio
  σ(κ) = ε^{1/3}κ^{5/3}/C_K) keeps its inertial form into the dissipation range; the flux then
  *decays* there, obeying dF/dκ = −2νκ²E, and integrating that decay is precisely what produces
  the exp(−(3/2)C_K(κη)^{4/3}) factor the docstring displays. "The spectral energy flux stays
  constant" is the opposite of the mechanism: constant flux means zero dissipation and no roll-off.
  The formula is right; the stated hypothesis contradicts it.
- **resolution_hint**: say "the hypothesis that the cascade timescale (flux per unit spectral
  energy) retains its inertial-range form through the dissipation range".

## 2. `scalar_rhs!` contradicts itself on the κ = 0 mode: exact by construction vs "holds only to roundoff"

- **type**: contradiction · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: api / Generator, `scalar_rhs!`: "The conservative form conserves the scalar mean exactly:
    the divergence has no $\kappa=\boldsymbol{0}$ component"
  - PAGE: api / Generator, `scalar_rhs!` (three paragraphs later): "$\langle\nabla\cdot(\boldsymbol{u}\varphi)\rangle = 0$
    holds discretely only to roundoff" (the stated reason the mode "is zeroed exactly")
  - PAGE: observables_cache §2.1: "The conservative scalar form holds the $\kappa = 0$ tendency at
    zero"; PAGE: decisions (the κ = 0 pin entry) makes the same roundoff claim for the scalar.
- **contradicts**: the axis is whether the discrete scalar-mean identity is exact or roundoff-level.
- **description**: The scalar advection is computed as −dealias(iκ·(uφ)^); at κ = 0 the multiplier
  iκ is exactly zero, so the assembled tendency's mean mode is exactly zero with no pin — which is
  what the first sentence (and the observables_cache page) says. The "only to roundoff" rationale
  is the *velocity's* situation (the Lamb product's FFT mean survives the Leray projection, which
  keeps constants), pasted onto the scalar, where it appears false. One docstring asserts both.
- **resolution_hint**: keep the pin if wanted for uniformity, but attribute the roundoff residual
  to the velocity route only; for the divergence form state that iκ·(·) vanishes identically at κ = 0.

## 3. "The spectral field" / "the spectral state" — the corpus's own field-vs-representation discipline is violated

- **type**: other (category/type error) · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / Generator, `velocity_rhs!` arguments: "`N̂` — the spectral field receiving the
    assembled term"; identically in `scalar_rhs!`.
  - PAGE: api / Observables, module list: "the vorticity recovered in physical representation from
    the spectral state"; the "Vorticity recovery" section header repeats "from the spectral state".
- **contradicts**: PAGE: architecture §10: category errors include "a field with its representation
  (physical vs spectral)"; PAGE: notation, Conventions: "A field is one physical object; physical
  and spectral are two representations of it."
- **description**: The corpus elsewhere writes "a field in spectral representation" (e.g.
  `set_forcing_rate!`: "a scalar field in spectral representation") and declares the "spectral
  field" shorthand a category error in its own architecture and glossary. The `N̂` bullets and the
  two "spectral state" phrasings are the residual instances of the conflation the house rule bans.
- **resolution_hint**: "the field in spectral representation receiving …"; "recovered … from the
  state's spectral representation".

## 4. `ModelSpectrum` calls the roll-off length "$L$" — the glyph the glossary reserves for the box side

- **type**: contradiction · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / phenomenology / Spectra, `ModelSpectrum`: "reads $\varepsilon$ and the roll-off's
    own length $L$ (see `large_scale_length` …)"
- **contradicts**: PAGE: notation, Derived scales: "$\ell$ | the length a large-scale roll-off is
  evaluated against … — never the box side $L$"; and `ModelSpectrum`'s own displayed formula, which
  writes $f_L(\kappa \ell)$.
- **description**: The formula uses ℓ, the glossary binds ℓ to exactly this quantity and states
  "never the box side L", and the Numerics table binds $L$ to `side_length` — yet the evaluation
  sentence names the same length $L$. A reader cross-referencing the `Li2008` law (where $L$
  really is the box side) meets two meanings of one glyph inside one submodule.
- **resolution_hint**: replace "$L$" with "$\ell$" in that sentence.

## 5. Notation page: the τ row points to "the integrating factor's row below", but that row is above

- **type**: organization · **severity**: nit · **confidence**: high
- **locations**:
  - PAGE: notation, Derived scales, τ row: "in the integrating factor's row below, $\tau$ is a
    Runge–Kutta stage substep"
- **contradicts**: the same page's section order — "Spectral representation and operators" (holding
  the $\mathcal{E}(\boldsymbol{\kappa})$ row that uses τ as the substep) precedes "Derived scales".
- **description**: The disambiguation itself is correct and welcome (τ the eddy-turnover unit vs τ
  the stage substep), but the pointer's direction is wrong on the rendered page: the 𝓔 row sits two
  sections earlier, not below. A reader scanning downward for the promised row finds nothing.
- **resolution_hint**: "in the integrating factor's row above".

## 6. Obukhov–Corrsin "no factor-of-two conversion" claim argues from the dissipation convention alone

- **type**: citation · **severity**: minor · **confidence**: low
- **locations**:
  - PAGE: api / phenomenology / Spectra, `ObukhovCorrsin1949`: "quoted — unlike Yaglom's classical
    4/3 — for the full-variance scalar dissipation … so it pairs directly … with no factor-of-two
    conversion"
- **contradicts**: (suspicion, not a proven contradiction) the constant's invariance structure.
- **description**: In E_φ = C_OC ε_φ ε^{−1/3}κ^{−5/3} the constant is invariant only when the
  spectrum normalization and the dissipation convention flip *together* (halving both leaves C_OC
  unchanged); a mixed-convention source shifts it by 2. The docstring certifies only the
  dissipation half of Sreenivasan (1996)'s convention, saying nothing of whether his E_θ integrates
  to ⟨θ²⟩ or ⟨θ²⟩/2 — the very axis on which this package deliberately departs from the common
  half-variance spectrum (notation: "with no ½, unlike E(κ)"). Given this corpus's history of
  factor-2 defects in exactly this corner (the Yaglom blocker), the claim deserves a source-side
  check of both conventions, not one.
- **resolution_hint**: verify Sreenivasan 1996's E_θ normalization; if consistent, extend the
  parenthetical to certify both halves of the convention.
