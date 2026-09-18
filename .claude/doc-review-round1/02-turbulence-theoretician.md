# Turbulence Theoretician — findings

Auditing the rendered GBGHomogeneousTurbulence documentation (full site incl. Architecture)
for physical correctness and internal consistency of every definition, conservation law,
scaling law, and dimensionless constant.

Overall the physics is unusually clean: kinetic energy `½⟨|u|²⟩`, dissipation
`ε = ν⟨|ω|²⟩` (with the correct homogeneous identity `ε = 2ν⟨SᵢⱼSᵢⱼ⟩`), the derived scales
(`η`, `τ_η`, `λ`), the coordinate-free skewness constant `C = (4/7)√(15/2) ≈ 1.5649`, the 4/5
law, the K41/K62/She–Léveque exponents, the Williamson RK3 coefficients, the CFL calibration,
`u' = √(2k/3)`, `L₁₁`/`L₂₂ = L₁₁/2`, and the model-spectrum roll-off exponents all check out
and agree across pages. The findings below are the exceptions.

---

## Finding 1 — Yaglom 4/3 law is inconsistent with the package's own scalar-dissipation definition (factor of 2)

- **type:** dimensional (contradiction / normalization)
- **severity:** blocker
- **confidence:** high

**Locations (both quoted):**

- PAGE: Phenomenology — StructureFunctions, `Yaglom1949`:
  "\[\langle\delta u_L\,(\delta\varphi)^2\rangle(r) = -\tfrac{4}{3}\,\varepsilon_\varphi\,r,\]
  … `structure_function`(law, r, fp; order = 3) returns it, reading the scalar dissipation
  $\varepsilon_\varphi$ (`fp.scalar_dissipation`, which must be set)".
- PAGE: API — Observables, `scalar_dissipation`:
  "The mean scalar-variance dissipation rate $\varepsilon_\varphi = 2\varkappa\,\langle\lvert\nabla\varphi\rvert^{2}\rangle$".
  (Same definition also on the Notation page — "$\varepsilon_\varphi$ | scalar dissipation rate
  $2\varkappa\langle\lvert\nabla\varphi\rvert^2\rangle$" — and in Architecture §4.3.)
- PAGE: API — Observables, `scalar_variance`: "The scalar variance $\langle\varphi^{2}\rangle$"
  (the FULL variance, not `½⟨φ²⟩`).

**Contradicts:** its own `scalar_dissipation` definition. The package defines
`ε_φ = 2κ⟨|∇φ|²⟩`, i.e. the dissipation rate of the FULL variance `⟨φ²⟩`
(indeed `d/dt⟨φ²⟩ = −2κ⟨|∇φ|²⟩ = −ε_φ`). But the Yaglom (4/3) constant is a *derived*
mathematical constant, and in every standard derivation it pairs with the dissipation of the
HALF-variance `½⟨φ²⟩`, namely `ε_θ = κ⟨|∇φ|²⟩ = ½ ε_φ`. Axis of disagreement: the half-vs-full
scalar-variance convention baked into the coefficient.

**Description:**
The exact Yaglom relation (the scalar analogue of the 4/5 law) is
`⟨δu_L (δφ)²⟩ = −(4/3) ε_θ r`, where `ε_θ = κ⟨|∇φ|²⟩` is the dissipation rate of the
half-variance `½⟨φ²⟩` — exactly as the velocity 4/5 law `D_LLL = −(4/5) ε r` pairs with
`ε = ν⟨|ω|²⟩`, the dissipation rate of the half-energy `k = ½⟨|u|²⟩`. The package's velocity
side is therefore consistent: `Kolmogorov1941` gives `D_LLL = −(4/5) ε r` and `dissipation`
gives `ε = ν⟨|ω|²⟩` (the ½-energy rate). But the scalar side mixes conventions: it feeds the
FULL-variance rate `ε_φ = 2κ⟨|∇φ|²⟩ = 2 ε_θ` into the coefficient `4/3` that only holds for the
half-variance rate. As written, the law evaluates to `−(4/3)(2 ε_θ) r = −(8/3) ε_θ r`, i.e.
**twice** the correct `−(4/3) ε_θ r`.

In the package's own variables the correct statement is
`⟨δu_L (δφ)²⟩ = −(2/3) ε_φ r`.

The root cause is the deliberate half/full asymmetry the docs elsewhere state explicitly — see
PAGE: API — Forcing, `BandRescaling`: "the scalar variance $\langle\varphi^{2}\rangle$ …
the field's L² observable, **carrying the ½ only for the vector**." The kinetic energy carries a
½, the scalar variance does not; the Yaglom coefficient was transcribed from the literature
(where it pairs with the ½-variance rate) without absorbing that factor.

Consequence: as a validation reference this makes a correctly-mixing DNS appear to disagree with
Yaglom's exact law by a factor of 2 (or make a wrong run look right). Because it is an *exact*
inertial-range law with no free constant, this is a hard error, not a tunable.

**resolution_hint:** Either change the Yaglom coefficient to `2/3` in the package's `ε_φ`
convention, or (less cleanly) have `Yaglom1949` read a half-variance rate. Cross-check the
Obukhov–Corrsin spectrum too — `E_φ = C_OC ε_φ ε^{-1/3} κ^{-5/3}` with `C_OC ≈ 0.67` is
internally consistent because there BOTH the dissipation and the spectrum integral use the full
variance; only the Yaglom coefficient (a derived, not fitted, constant) is wrong.

---

## Finding 2 — `ExponentialDissipation` β ≈ 0.6 clashes with `PopeDissipation` β = 5.2 for the same asymptotic exponential decay

- **type:** physics
- **severity:** major
- **confidence:** medium

**Locations (both quoted):**

- PAGE: Phenomenology — Spectra, `ExponentialDissipation`:
  "The pure-exponential dissipation-range roll-off $f_\eta(\kappa\eta) = \exp(-\beta\,\kappa\eta)$
  … `β` is fit-dependent — **of order `0.6`** in high-Reynolds-number DNS (Ishihara et al. 2005)".
- PAGE: Phenomenology — Spectra, `PopeDissipation` / `Pope2000`:
  "$f_\eta(\kappa\eta) = \exp\!\big(-\beta\{[(\kappa\eta)^4 + c_\eta^4]^{1/4} - c_\eta\}\big)$" with
  the default "`β = 5.2`".

**Contradicts:** `PopeDissipation`'s `β = 5.2`. Both β's govern the exponential decay rate of the
dissipation-range spectrum against `κη`: Pope's factor is `∝ exp(−5.2 κη)` asymptotically
(`[(κη)⁴+c_η⁴]^{1/4} → κη` for large `κη`), while `ExponentialDissipation` is `exp(−0.6 κη)`
throughout. Axis of disagreement: the numerical value of the far-dissipation exponential decay
rate — a ~9× discrepancy for the same physical tail on the same page.

**Description:**
Physically the far-dissipation range decays as `E(κ) ∝ exp(−β κη)` with `β` of order 5–7
(Pope's 5.2 is representative; Ishihara–Kaneda-type DNS give ≈5–7). A value `β ≈ 0.6` is far too
small: it puts `exp(−0.6) ≈ 0.55` at the Kolmogorov scale `κη = 1`, i.e. half the inertial-range
amplitude still surviving at `η`, contradicting the observed sharp cutoff (Pope's own factor
gives `≈0.04` there). Even the most generous reading — a self-consistent *pure* exponential over
the whole spectrum, fixed by the dissipation integral `ε = 2ν∫κ²E dκ` with `C_K = 1.5` — yields
`β = (2 C_K Γ(4/3))^{3/4} ≈ 2.1`, still ~3.5× larger than 0.6. Under any reading, 0.6 is
anomalously small, and it sits next to Pope's 5.2 (same asymptotic role) with no explanation of
the ~9× gap. Likely a mis-transcribed constant or a value from a different normalization.

**resolution_hint:** Re-check the intended value against Ishihara et al. (a pure `exp(−β κη)` fit
of the dissipation range should give `β` of order a few, not 0.6); if 0.6 is genuinely a fitted
value under some special normalization, state that normalization so it does not read as
contradicting Pope's 5.2.

---

## Finding 3 — The `StructureFunction` supertype and `structure_function` generic define only pure-velocity moments, but `Yaglom1949` returns a mixed velocity–scalar moment

- **type:** clarity (category coverage)
- **severity:** minor
- **confidence:** medium

**Locations (both quoted):**

- PAGE: Phenomenology — StructureFunctions, `StructureFunction` type:
  "Supertype of the velocity structure-function laws — parametrizations of
  $D_{L\dots}(r) = \langle(\delta u_L)^p\rangle$ (the $p$-th moment of the longitudinal velocity
  increment …)". And the `structure_function` generic (Reference-laws page):
  "The reference velocity structure function $D_{L\dots}(r) = \langle(\delta u)^{\texttt{order}}\rangle$".
- PAGE: Phenomenology — StructureFunctions, `Yaglom1949`:
  "$\langle\delta u_L\,(\delta\varphi)^2\rangle(r) = -\tfrac{4}{3}\,\varepsilon_\varphi\,r$".

**Contradicts:** the supertype/generic identity. `Yaglom1949` is listed under `StructureFunctions`
and implements `structure_function`, yet it returns the *mixed* velocity–scalar third moment
`⟨δu_L (δφ)²⟩`, which is not of the form `⟨(δu_L)^p⟩` (a pure-velocity moment). Axis of
disagreement: a mixed velocity–scalar structure function vs a pure-velocity structure function —
two different physical objects.

**Description:**
A reader taking the supertype at its word expects every `StructureFunction` to be a velocity
moment `⟨(δu_L)^p⟩` and will misread the Yaglom output. This is a category slip of exactly the
kind the docs' own "category/type-error" convention warns against (Architecture §10). The
supertype/generic identity should be widened to cover mixed velocity–scalar increments, or Yaglom
should be split out.

**resolution_hint:** Broaden the `structure_function`/`StructureFunction` identity to
"longitudinal velocity and mixed velocity–scalar increment moments," or give the mixed law its own
family.

---

## Finding 4 — Undocumented half/full convention asymmetry between the velocity spectrum and the scalar spectrum (the systemic root of Finding 1)

- **type:** contradiction (convention)
- **severity:** minor
- **confidence:** medium

**Locations (both quoted):**

- PAGE: API — Observables, `energy_spectrum` and Reference-laws `spectrum`:
  "$k = \sum_\kappa E(\kappa)$" / "the velocity energy spectrum $E(\kappa)$ … $k = \int_0^\infty E(\kappa)\,d\kappa$",
  with `kinetic_energy` = "$\tfrac12\langle\lvert\boldsymbol{u}\rvert^{2}\rangle$" — so the velocity
  spectrum integrates to the HALF-energy `k = ½⟨|u|²⟩`.
- PAGE: Phenomenology — Spectra, `ScalarSpectrum`:
  "$E_\varphi(\kappa)$, the density in wavenumber of the scalar variance $\langle\varphi^2\rangle$"
  — so the scalar spectrum integrates to the FULL variance `⟨φ²⟩`.

**Contradicts:** each other in *convention*: the two "energy-like" spectra normalize to a
half-quantity (velocity) and a full-quantity (scalar) respectively. Axis of disagreement: the
factor-of-½ convention on the reduced quantity.

**Description:**
Each choice is individually standard (`k` conventionally carries the ½; scalar variance
conventionally does not). But the pairing is never flagged, and it is precisely what made the
Yaglom coefficient (Finding 1) wrong: any coefficient derived in the half-variance convention
(the 4/3 law, and potentially future two-point/spectral scalar relations) must absorb a factor of
2 before being applied to the package's full-variance `ε_φ`, `⟨φ²⟩`, `E_φ`. Worth a one-line
notation note so the next transcribed scalar law does not inherit the same trap.

**resolution_hint:** Add a sentence to the Notation page (or the `ScalarSpectrum`/`scalar_dissipation`
docstrings) stating that scalar variance and its spectrum/dissipation carry no ½ (unlike the
velocity `k`), and that classical scalar coefficients quoted for `½⟨φ²⟩` must be halved here.

---

## Finding 5 — Kinetic-energy default is set two ways: `random_solenoidal_velocity!` defaults to 0.5, `Simulation` to 1.5

- **type:** other (default mismatch)
- **severity:** minor
- **confidence:** low

**Locations (both quoted):**

- PAGE: API — State, `random_solenoidal_velocity!`:
  "`random_solenoidal_velocity!(û, domain; kinetic_energy = 0.5, …)`".
- PAGE: API — SimulationRun, `Simulation`:
  "`kinetic_energy = 1.5`" and "`1.5` gives $u' = 1$".

**Contradicts:** the front-door `Simulation` default. The two entry points seed the same physical
quantity (the target kinetic energy `k`) with different defaults — 0.5 (giving the non-round
`u' = √(2·0.5/3) ≈ 0.577`) at the low level, 1.5 (giving the clean `u' = 1`) at the front door.
Axis of disagreement: the default value of `k`.

**Description:**
Not a physics error — different entry points may reasonably differ — but a reader dropping to the
low-level IC filler for a hand-rolled run silently gets a different `u'` than the ergonomic path
advertises. Minor cross-reference note; the api-user / consistency hats will also see it.

---

## Finding 6 — "`k_max_η = 2` means `Δx ≈ η`" is only exact for the 2/3 rule, stated right after introducing the general fraction f

- **type:** physics (imprecision)
- **severity:** nit
- **confidence:** low

**Location (quoted):**

- PAGE: API — SimulationRun, `Simulation` (Grid mode):
  "Since $\kappa_{\max}\eta = f\pi\,\eta/\Delta x$ with $f$ the retained-Nyquist fraction,
  `k_max_η = 2` means $\Delta x \approx \eta$."

**Description:**
With `κ_max η = f π η/Δx = 2`, one gets `η/Δx = 2/(fπ)`, so `Δx ≈ η` holds only for `f = 2/3`
(the default `TwoThirds`, giving `η/Δx ≈ 0.955`). For `PhaseShift` (`f = 2√2/3 ≈ 0.943`) the same
`k_max_η = 2` gives `η/Δx ≈ 0.68`, i.e. `Δx ≈ 1.5 η`. The sentence introduces the general `f` and
then states `Δx ≈ η` as if `f`-independent. True for the default; imprecise in general.

**resolution_hint:** Qualify as "for the default 2/3 rule, `k_max_η = 2` means `Δx ≈ η`."

---

## Finding 7 — JHTDB isotropic Reynolds-number range `Re_λ ≈ 400–2500` overstates the JHTDB datasets

- **type:** citation (data range)
- **severity:** minor
- **confidence:** low

**Location (quoted):**

- PAGE: Phenomenology — Scalings, `Li2008`:
  "nearly Reynolds-number-independent across the JHTDB isotropic datasets
  ($\mathrm{Re}_\lambda \approx 400\text{–}2500$) and comparable box DNS".

**Description:**
The JHTDB forced-isotropic datasets sit near `Re_λ ≈ 433` (with a higher-Re isotropic case well
below 2500); `Re_λ ≈ 2500` is beyond the JHTDB isotropic range and belongs to "comparable box
DNS," not JHTDB. The bundled phrasing attributes the top of the range to JHTDB. Low-confidence,
citation-adjacent (also relevant to the citations hat).

**resolution_hint:** Attribute the upper Re_λ to the comparable box DNS, or narrow the JHTDB range
to what those datasets actually cover.
