# Hat 08 — Dimensional analysis & normalization

Mechanical audit of every formula, factor, and cutoff in the rendered site for dimensional
consistency and for cross-page agreement of the *same* number.

## What was verified clean (no finding)

Recorded so the negative result is on the record, since these are the factors the hat exists to
catch:

- `kinetic_energy` ½, `scalar_variance` (no ½), `dissipation` ν⟨|ω|²⟩ = 2ν⟨S:S⟩ (differ by the
  dilatation — expanded and confirmed), `scalar_dissipation` 2ϰ⟨|∇φ|²⟩ — identical on all four
  surfaces (ARCHITECTURE §4.3, notation, Observables, `FlowParameters`).
- **Yaglom**: −(2/3)ε_φ r with the full-variance ε_φ. Re-derived from the scalar KHM
  (∇_r·⟨δu(δθ)²⟩ = −4ϰ⟨|∇θ|²⟩ ⇒ F = −(4/3)ϰ⟨|∇θ|²⟩r = −(2/3)ε_φ r). **Correct.**
- **Betchov constant**: C_S = (8/105)(15/2)^{3/2} = (4/7)√(15/2) = 1.5649, and both stated Betchov
  relations (105/8, 15/2) reproduce it exactly. `tr S³ = 3 det S` for symmetric traceless. Correct.
- **Phase-shift cutoff**: (√2/3)N·(2π/L) = (2√2/3)κ_Ny = 0.9428κ_Ny — the *same number* at all six
  sites (ARCH §7, decision 27, notation, `DealiasingStrategy`, `PhaseShift`, `truncate_to_band!`,
  `max_wavenumber`). The √2 band factor and the 2.8× (=√2³) mode count check out.
- **CFL**: κ_max Δx = 2π/3 = 2.094; y_s = √3 ⇒ C ≲ 0.827 ("≲0.83"). |R(iy)|² = 1 + y⁴/4 for RK2.
  RK3 A/B/d coefficients: Σd = 1, cumulative d = c = (0, 1/3, 3/4). All correct.
- **Integrating factor**: exp((A − D|κ|²)τ), coefficient = −ντ, offset_scale = τ — identical in
  ARCH §4.2, notation, `observables_cache` §2.2, both factor verbs, decision 52.
- **Spectrum**: E_n vs E(κ), Δκ = 2π/L, dimensions L²T⁻² vs L³T⁻², the "halved radial spectrum",
  the cancellation of Δκ in L₁₁ — consistent everywhere. L₁₁ = (3π/4)∫(E/κ)/∫E, L₂₂ = L₁₁/2,
  L_E = (π/2)R = (2/3)L₁₁ = (1/3)(L₁₁+2L₂₂) — algebraically consistent.
- **Li2008**: G = k/(Lε)^{2/3} ⇔ ε = (k/G)^{3/2}/L; G = (3/2)C_ε^{−2/3}; carrying C_ε = 0.5 at
  L/L₁₁ = 5 gives 1.5/2.5^{2/3} = 0.814 ("≈0.81"). κ_max η = fπη/Δx; κ_max_η = 2, f = 2/3 ⇒
  Δx ≈ η. All correct.
- **Forcing**: injection = 2A·E_band holds for *both* fields, because the velocity's band observable
  carries the ½ and the scalar's does not, and ε_φ is the full-variance rate. The factor-2 trap is
  navigated correctly; the "net rate A − D|κ|²" is the amplitude rate, consistent with 𝓔.
- **Memory/compute arithmetic**: 384/768 MiB, 3N³ reals, 322.5 MiB frame (64.5+129+129), ×7.97 at
  512³ = 2.52 GiB, 6 vector fields = 2.26 GiB, 24 B/point for a pointwise multiply, transform
  tables 18/9, 21/18, 36/18, 42/36 and the RK2 scaling 51→42 / 34→28 — every one reproduces.
- **Phenomenology**: ζ_p (K62, She–Lévêque) exact at ζ₃ = 1; Lundgren zero at (8.45/0.8)^{3/2} =
  34.3 and ~half the coefficient at Re_λ = 100; VonKarmanLarge exponent 17/6 ⇒ κ⁴; PopeLargeScale
  p₀ ⇒ κ^{p₀}; Pao (3/2)C_K(κη)^{4/3}; OC dimensions; L₀/L₁₁ ≈ 3.7 ⇒ energy × 3.7^{−2/3} = 0.42
  ("well under half"). C₂ = 2.0 and C_K = 1.5 are mutually consistent (C₂ ≈ 4.02·(18/55)C_K).

## Findings

---

### 1. The seeded model spectrum's large scale: `Simulation` promises `1/envelope_wavenumber`, `large_scale_length` overrides it

- **type**: contradiction (dimensional / normalization input)
- **severity**: major
- **confidence**: medium

**Locations**

- PAGE: api / SimulationRun, `Simulation` → Arguments, `initial_spectrum`:
  "The model is evaluated at the run's state, with its integral scale taken as
  `1/envelope_wavenumber`".
- PAGE: api / phenomenology / Spectra, `large_scale_length`:
  "`PopeLargeScale` overrides it with $L_{0} = k^{3/2}/\varepsilon$".

**Contradicts**: the same page states the override changes the length "smaller by a factor of order
three", i.e. the two lengths differ by ≈3.7 at C_ε = 0.5.

**Description**: The front-door claim is unconditional, but for every `PopeLargeScale`-based preset
(`Pope2000`, the flagship example of a model spectrum) the roll-off is evaluated at L₀ = k^{3/2}/ε,
not at the supplied L₁₁ = 1/`envelope_wavenumber`. The seeded spectrum's energy-containing peak then
sits at a length ~3.7× the promised one, and the setting the user turned has no effect. Only the
`VonKarman1948` example named in the docstring actually honours the promise.

**resolution_hint** (advisory): qualify the front-door sentence — the supplied scale is the bundle's
`integral_scale`, which a form using `large_scale_length`'s default reads and Pope's form does not.

---

### 2. `ε_target` is bound to "energy-injection rate" but also carries a scalar-variance rate

- **type**: dimensional
- **severity**: minor
- **confidence**: high

**Locations**

- PAGE: notation, § Forcing table: "$\varepsilon_{\mathrm{target}}$ | target energy-injection rate |
  `ConstantPower(injection_rate=…)`".
- PAGE: api / Forcing, `ConstantPower`: "the rate $\varepsilon$ for the velocity … and
  $\varepsilon_\varphi$ for the scalar".
- PAGE: api / Forcing, module map: "The interchangeable energy-injection strategies".

**Contradicts**: one glossary symbol, two dimensionally distinct quantities — ε is L²T⁻³, ε_φ is
[φ²]T⁻¹.

**Description**: The glossary is the single reference that binds each symbol to one concept, and it
binds ε_target to an *energy*-injection rate; the same keyword on the scalar side injects scalar
variance, whose rate has different dimensions and a different symbol (ε_φ) already in the glossary.
The `Forcing` module map inherits the slip by calling every strategy an "energy-injection" strategy
while one implementation serves the scalar too.

**resolution_hint**: name the glossary entry for the held quantity's rate ("the target injection rate
of the forced field's quadratic invariant — ε for the velocity, ε_φ for the scalar").

---

### 3. "Two registers per field" names two different sets on two pages

- **type**: contradiction (count convention)
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE: architecture, §4.5: "dearer in memory — three spectral registers per field against the
  low-storage scheme's two".
- PAGE: api / Propagator, `IFLowStorageRK3`: "two field registers per field: the state's own array
  plus one accumulator (`stage1`)".
- PAGE: api / Propagator, `allocate_buffers`: "`IFLowStorageRK3` allocates `stage1` and `nonlinear`;
  `IFRK2` allocates `stage1`, `stage2`, and `velocity_predictor_spectral`".

**Contradicts**: axis = what the count includes. ARCH's "two" = {stage1, nonlinear} (state excluded);
the scheme docstring's "two" = {state, stage1} (nonlinear excluded).

**Description**: The two "two"s coincide numerically by accident and denote disjoint sets, so ARCH's
3-against-2 comparison cannot be checked against either page. The `IFLowStorageRK3` docstring
anticipates the collision ("the `IntegratorBuffers` a run allocates can hold more than that count"),
but ARCH never says which convention it uses, and the reader who carries Williamson's 2N count across
gets 4-against-3 for the same comparison.

---

### 4. `max_wavenumber` calls κ_max "the highest wavenumber magnitude that `domain` actually evolves" — false for `HouLi`

- **type**: physics / definition
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE: api / SimulationDomain, `max_wavenumber`: "The highest wavenumber magnitude that `domain`
  (a `FixedDomain`) actually evolves … $f$ … ($1$ for `HouLi`)".
- Same docstring, two sentences later: "`HouLi`, whose band runs to the Nyquist wavenumber, damps
  them instead (to machine epsilon at Nyquist)".

**Description**: Under `HouLi` nothing is zeroed, and the grid carries modes out to the cube corner
(√3 κ_Ny), all still evolved with a taper. κ_Ny is therefore a *convention* for HouLi, not the
highest evolved magnitude — and this κ_max is what feeds both the CFL scaling and the resolution
criterion κ_max·η. The docstring already knows this; the opening identity sentence contradicts it.

**resolution_hint**: "the highest wavenumber the run treats as resolved signal" covers all three
strategies without the false claim.

---

### 5. `Sreenivasan1995`'s default C_K = 1.5 is not Sreenivasan's own value

- **type**: citation / normalization constant
- **severity**: minor
- **confidence**: low

**Location**

- PAGE: api / phenomenology / Scalings, `Sreenivasan1995`: "Reviewing the experimental and numerical
  record, Sreenivasan (1995) found it close to universal, a reliable estimate being $C_K = 1.5 \pm
  0.1$ (the default; Sagaut & Cambon 2018)".

**Description**: Sreenivasan (1995) reports the *one-dimensional* longitudinal constant C₁ = 0.53 ±
0.055; converted with the isotropy factor 55/18 that is C_K = 1.62 ± 0.17 for the three-dimensional
spectrum this preset evaluates — outside the stated 1.5 ± 0.1. The parenthetical credits 1.5 to
Sagaut & Cambon, but the sentence reads as Sreenivasan's finding, so a preset named for the 1995
review ships a different amplitude. C_K is the spectrum's overall normalization, so the ~8 %
difference propagates into every `validate_spectrum`-style comparison.

---

### 6. `initial_spectrum` is "evaluated at the run's state" at *t* = 0, where ε and η do not yet exist

- **type**: method / underspecified normalization
- **severity**: minor
- **confidence**: low

**Location**

- PAGE: api / SimulationRun, `Simulation`, `initial_spectrum`: "The model is evaluated at the run's
  state, with its integral scale taken as `1/envelope_wavenumber`, and the result normalized to
  `kinetic_energy`."

**Description**: Every `ModelSpectrum` needs ε (for the C_K ε^{2/3} core) and η (for f_η), both
measured quantities that do not exist before the field is seeded. Only L₁₁ and k are said to be
supplied. Which ε the seeder uses — the `Li2008` prediction of grid mode? a value derived from k and
the box? — decides the shape of the dissipation roll-off and is not stated anywhere on the page.

---

### 7. "Carrying the ½ only for the vector" attributes an energy-vs-variance convention to tensor rank

- **type**: clarity / normalization statement
- **severity**: nit
- **confidence**: medium

**Location**

- PAGE: api / Forcing, `BandRescaling`: "the kinetic energy $\tfrac{1}{2}\langle\lvert\boldsymbol{u}
  \rvert^{2}\rangle` … the scalar variance $\langle\varphi^{2}\rangle$ … the field's $L^{2}$
  observable, carrying the $\tfrac{1}{2}$ only for the vector."

**Description**: The ½ is present because the *kinetic energy* is conventionally half the mean square
and the *variance* is not; it has nothing to do with the field being a vector. As written a reader
generalizing the rule to a future vector-valued scalar, or to a second scalar diagnostic, would carry
the ½ to the wrong quantity. The consequence matters: the same ½ decides whether `target` and
`ConstantPower`'s 2A·E_band relation stay consistent across the two fields.

---

### 8. The notation glossary writes κ_max in two algebraic shapes and omits `HouLi`

- **type**: format / notation consistency
- **severity**: nit
- **confidence**: high

**Locations**

- PAGE: notation, § Numerics: "$\kappa_{\max}$ | dealiased maximum wavenumber, $\tfrac{2}{3}\cdot
  \tfrac{N}{2}\cdot\tfrac{2\pi}{L}$ for the default $2/3$ rule ($\tfrac{\sqrt{2}}{3}N\cdot
  \tfrac{2\pi}{L}$ for PhaseShift; set by the dealiasing strategy)".
- PAGE: api / SimulationDomain, `max_wavenumber`: "$\kappa_{\max} = f \frac{N}{2}\frac{2\pi}{L}$ …
  ($2/3$ for `TwoThirds`, $1$ for `HouLi`, $\tfrac{2\sqrt{2}}{3}$ for `PhaseShift`)".

**Description**: The glossary — the page that is "the single reference" — gives the same quantity in
two incompatible-looking forms (one with N/2 factored out, one with N), so the reader must do the
algebra to see that (√2/3)N = (2√2/3)(N/2), and `HouLi`'s f = 1 is absent. The API page's uniform
f·(N/2)·(2π/L) form makes all three commensurable at a glance.
