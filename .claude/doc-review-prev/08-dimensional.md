# Hat 08 — Dimensional analysis & normalization

Fresh-eyed audit of every formula, factor and constant in the rendered site, checked for dimensional
consistency and for cross-page agreement. Findings are ranked most-severe first.

**Verified clean (no finding raised)** — recorded so the negative results are visible: the ½ in
`kinetic_energy` (5 surfaces); the 2ϰ in `scalar_dissipation` (4 surfaces); ε = ν⟨|ω|²⟩ = 2ν⟨S:S⟩ and
the dilatation caveat; the Dirichlet identity ⟨|ω|²⟩ = ⟨û,|κ|²û⟩ and its solenoidal condition;
κ_max = f(N/2)(2π/L) with f = 2/3, 1, 2√2/3 — the PhaseShift cutoff is the *same* number in all four
places it appears ((√2/3)N·2π/L = (2√2/3)κ_Ny ≈ 0.94κ_Ny, √2 wider ⇒ 2.83× the modes); the alias-free
condition 2κ_max < N (2/3 ✓, PhaseShift 0.943N ✓, HouLi at the boundary ✓); the cubic-invariant
residual for the skewness; C_S = (4/7)√(15/2) ≈ 1.5649, reconstructed from Betchov (−3/4) and Taylor
(−35/2) — 105/8 is right; ⟨S:S⟩ = (15/2)⟨(∂₁u₁)²⟩; tr S³ = 3 det S; L₁₁ = (3π/4)∫(E/κ)/∫E, L₂₂ = L₁₁/2,
L_E = (π/2)∫(E/κ)/∫E = (2/3)L₁₁ = (1/3)(L₁₁+2L₂₂) — all three π factors derived and confirmed;
E(κ) [L³T⁻²] vs E_n [L²T⁻²] and Δκ = 2π/L; the shell-width cancellation in `integral_scale`;
u' = √(2k/3); η, τ_η, λ, Re_λ; the CFL numbers (κ_maxΔx = 2π/3 ≈ 2.09, y_s = √3 ⇒ C ≲ 0.83);
the RK3 coefficients (Σd = 1, c = (0,1/3,3/4) from d) and the IFRK2 stability function |R(iy)|² = 1+y⁴/4;
E = exp((A − D|κ|²)τ) and the returned parameters (coefficient = −ντ, offset_scale = τ);
ConstantPower's A = injection_rate/(2E_band) — correct for BOTH fields under the "½ only for the
vector" convention; G = k/(Lε)^{2/3}, ε = (k/G)^{3/2}/L, G = (3/2)C_ε^{−2/3}, and the L/L₁₁ ≈ 5
carry-across giving 0.81 (recomputed: 0.814); κ_maxη = fπη/Δx and Re_λ ∼ N^{2/3}; the Gaussian
envelope's peak at κ_p/√2; the transform ledgers (mask (6,3)+(1,3) ⇒ 21/18; PhaseShift exactly 2×
⇒ 42/36, and 51→42 / 34→28); the byte ledgers (384/192 MiB per vector, 322.5 MiB frame = 64.5+129+129,
2.52 GiB at 512³, 2.3 GiB for six vector fields); Yaglom −4/3 → −2/3 under the full-variance ε_φ;
ζ_p of K62 and She–Lévêque (both ζ₃ = 1); Lundgren's zero at Re_λ ≈ 34; C₂ = 2.0 ↔ C_K = 1.5
(C₂ ≈ 1.31 C_K); C_OC = 0.67 as the 3-D, full-variance constant.

---

## 1. `Pope2000`'s `c_L = 6.78` is Pope's constant for `L = k^{3/2}/ε`, but the factor is evaluated at `κL₁₁`

- **type**: dimensional  **severity**: major  **confidence**: high

**Locations**

- PAGE: api / phenomenology / Spectra — `ModelSpectrum`:
  "E(\kappa) = C_K \varepsilon^{2/3} \kappa^{-5/3} f_L(\kappa L_{11}) f_\eta(\kappa\eta)"
  and "reads $\varepsilon$ and the integral scale $L_{11}$ from `fp`".
- Same page — `PopeLargeScale`: "The coefficient `c_L` is set by the requirement that the spectrum
  integrate to the kinetic energy".
- Same page — `Pope2000`: "the defaults `c_L = 6.78`, `c_η = 0.40` are the high-Reynolds-number values
  Pope obtains from the energy and dissipation normalizations".
- PAGE: architecture §4.8 states the same composition: "an inertial core $C_K \varepsilon^{2/3}\kappa^{-5/3}$
  times a swappable large-scale factor $f_L(\kappa L_{11})$".

**Description**

With `PopeLargeScale` (p₀ = 2) the integral evaluates in closed form to
∫E dκ = 1.5·c_L^{−5/6}·B(3/2,1/3)/2·ε^{2/3}L^{2/3}. Dimensionally the only length that makes a *pure
number* c_L satisfy ∫E dκ = k is L = k^{3/2}/ε — and at c_L = 6.78 the integral is then exactly k
(numerically 0.999). L₁₁ is smaller by C_ε/1.837 ≈ 1/2.3…1/3.7, so evaluating f_L at κL₁₁ with
c_L = 6.78 leaves ∫E dκ ≈ 0.4–0.6 k and moves the spectral peak up by the same factor. The docstring's
own claim ("c_L is set by the requirement that the spectrum integrate to the kinetic energy") cannot
hold at the length the code passes. `VonKarman1948`'s `c_L = 1.0` "fixes the peak scale" carries the same
length question. (c_η = 0.40 is unaffected: the dissipation integral lives where f_L → 1.)

**resolution_hint**: either pass L₀ = k^{3/2}/ε (derivable from `rms_velocity` and `dissipation` in
`FlowParameters`) to `f_L`, or re-derive c_L for L₁₁ (≈ 2.4 at L₁₁/L₀ ≈ 0.27) and say so.

---

## 2. `recommended_cfl`: an eigenvalue multiplied by the dimensionless CFL number, compared to `y_s`

- **type**: dimensional  **severity**: minor  **confidence**: high

**Location** — PAGE: api / Propagator, `recommended_cfl`: "The advective eigenvalues … of magnitude up
to $\kappa_{\max}\sup\lvert\boldsymbol{u}\rvert$; stability needs this times $C_{\mathrm{CFL}}$ to stay
within the scheme's imaginary-axis stability limit $y_{\mathrm{s}}$."

**Description**

κ_max·sup|u| has dimensions T⁻¹; C_CFL is dimensionless; y_s is dimensionless. The quantity that must
stay within y_s is λΔt, i.e. C_CFL·κ_max·Δx — which is exactly how the very next sentence computes
√3/(2π/3) ≈ 0.83. The prose skips the Δt. **resolution_hint**: "…needs this times Δt — that is,
C_CFL κ_max Δx — to stay within y_s."

---

## 3. Two different values for the same far-dissipation decay rate β, in one module

- **type**: physics  **severity**: minor  **confidence**: medium

**Locations** — PAGE: api / phenomenology / Spectra —
`PopeDissipation`: "$f_\eta(\kappa\eta) = \exp(-\beta\{[(\kappa\eta)^4 + c_\eta^4]^{1/4} - c_\eta\})$",
with `Pope2000`'s default "`β = 5.2`";
`ExponentialDissipation`: "$f_\eta(\kappa\eta) = \exp(-\beta \kappa\eta)$ … DNS resolving that range fit
$\beta \approx 6.7$".

**Description**

Pope's factor is asymptotically exp(−β κη) for κη ≫ c_η, so both `β`s name the same physical quantity —
the far-dissipation exponential decay rate — yet the page carries 5.2 and 6.7 with no note that they
disagree by 30 %, and reuses one symbol for both. A reader comparing the two cutoffs has no way to
tell whether the difference is physical (fit range, Re_λ, the c_η offset) or a transcription slip.

---

## 4. Parseval and the "normalized inner product" are asserted, but no transform normalization is stated

- **type**: dimensional  **severity**: minor  **confidence**: medium

**Locations**

- PAGE: api / Observables, `kinetic_energy`: "Computed as $\tfrac{1}{2}\langle\boldsymbol{u},\boldsymbol{u}\rangle$
  with the normalized inner product, so by Parseval's theorem it accepts the velocity in either representation".
- PAGE: notation, Spectral representation: "$\hat f$ | The field $f$ in spectral (Fourier) representation,
  to_spectral(f)" — no 1/N³ or 1/|Ω| convention.

**Description**

Every representation-independence claim (kinetic_energy, scalar_variance, dissipation, the halved radial
spectrum) rests on a transform normalization the rendered corpus never states, and on a two-argument
⟨·,·⟩ the glossary does not define (it defines only the one-argument box average ⟨·⟩). A cold reader
cannot check any of the 1/N factors my hat is asked to verify. **resolution_hint**: one glossary row —
⟨f,g⟩ = |Ω|⁻¹∫f·g, and the Parseval statement it implies for the backend's convention.

---

## 5. `FlowParameters` calls four dependent quantities "independent", and its examples violate the package's own C_ε

- **type**: dimensional  **severity**: minor  **confidence**: medium

**Locations**

- PAGE: api / phenomenology / Phenomenology, `FlowParameters`: "It carries the independent dimensional
  quantities of a homogeneous isotropic state ($\nu$, $\varepsilon$, $u'$, $L_{11}$)".
- Same page, example: "FlowParameters(; viscosity = 1e-3, dissipation = 0.1, rms_velocity = 1.0,
  integral_scale = 0.5)".
- PAGE: api / phenomenology / Scalings, `Sreenivasan1998`: "$C_\varepsilon = \varepsilon L_{11}/u'^3$ …
  `asymptote = 0.5`".

**Description**

Four quantities in two dimensions leave two dimensionless groups, and one of them — C_ε = εL₁₁/u'³ — is
fixed at ≈ 0.5 by the package's own `Sreenivasan1998`. The documented example states C_ε = 0.05 (the
PAGE: phenomenology front-page example gives 0.1), i.e. 5–10× off a realizable HIT state, so a reader
who evaluates a law there is off the manifold every law is fitted on. "Independent" is the wrong word
for a set the package elsewhere constrains.

---

## 6. `Sreenivasan1995`'s C_K = 1.5 ± 0.1 is not the value that paper reports for the 3-D spectrum

- **type**: citation  **severity**: minor  **confidence**: low

**Location** — PAGE: api / phenomenology / Scalings, `Sreenivasan1995`: "Sreenivasan (1995) found it
close to universal, a reliable estimate being $C_K = 1.5 \pm 0.1$ (the default; Sagaut & Cambon 2018)".

**Description**

Sreenivasan (1995) reports the one-dimensional constant C₁ ≈ 0.53 ± 0.055; the three-dimensional
constant follows by C_K = (55/18)C₁ ≈ 1.6. The docstring attributes 1.5 ± 0.1 to the finding of the
named paper while crediting the number to Sagaut & Cambon — precisely the 1-D/3-D normalization
conversion this hat is asked to police, and the one the sibling `ObukhovCorrsin1949` docstring handles
explicitly ("≈ 0.67 for the three-dimensional spectrum"). The value itself is internally consistent
with `Kolmogorov1941`'s C₂ = 2.0 (C₂ ≈ 1.31 C_K), so only the attribution is at issue.

---

## 7. `Re = 1/ν` is stated on three surfaces under a units condition the shipped default violates

- **type**: dimensional  **severity**: minor  **confidence**: medium

**Locations**

- PAGE: notation, Parameters: "$\mathrm{Re}$ | Reynolds number … | 1 / ν (in units where $u' = L = 1$)".
- PAGE: architecture §4.2: "the viscosity $\nu$ ($\mathrm{Re} = 1/\nu$ in units where $u' = L = 1$)".
- PAGE: api / Generator, `FlowConditions`: "on the shipped defaults ($u' = 1$, $L = 2\pi$) the box-scale
  value is $2\pi/\nu$" — against PAGE: api / SimulationRun, `Simulation`: "`side_length = 2π`".

**Description**

Every default run has L = 2π, so the condition under which Re = 1/ν holds is never met by a shipped
case, and the box-scale Reynolds number is 2π/ν — a factor 6.28. Only `FlowConditions` says so; the
glossary row and the architecture, which are where a reader looks the number up, do not. Not a
contradiction (both are conditioned), but the correction lives on the one surface least likely to be
read for it.

---

## 8. χ is assigned to the half-variance rate, against the more common convention

- **type**: dimensional  **severity**: nit  **confidence**: low

**Location** — PAGE: api / phenomenology / Phenomenology, `FlowParameters`: "$\varepsilon_\varphi =
2\varkappa\langle\lvert\nabla\varphi\rvert^{2}\rangle$, the full-variance convention (not the
half-variance $\chi$, which is half of it — a law fed the wrong one is off by a factor of 2 with no
error)".

**Description**

The arithmetic is right (χ = ϰ⟨|∇φ|²⟩ = ε_φ/2, matching `Yaglom1949`'s −4/3 → −2/3 conversion), but a
large part of the mixing literature — including Sreenivasan's Obukhov–Corrsin papers, cited two pages
later for C_OC — writes χ for the *full*-variance rate 2ϰ⟨|∇φ|²⟩. A warning built on the opposite
reading of χ can send a reader the wrong way on exactly the factor of 2 it exists to prevent.
**resolution_hint**: name the half-variance rate by its formula rather than by the contested glyph.
