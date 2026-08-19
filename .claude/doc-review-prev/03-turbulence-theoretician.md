# Panel hat 03 — Turbulence theoretician

Fresh-eyed audit of the rendered site (`manuscript-full.md`) for physical definitions, conservation
relations, scaling laws, dimensionless constants, derived scales, and category/type errors.
Collect-only; nothing edited. Verified clean and *not* flagged: `ε = ν⟨|ω|²⟩ = 2ν⟨S:S⟩`;
`ε_φ = 2ϰ⟨|∇φ|²⟩` and its pairing with `⟨φ²⟩` and with Yaglom's −2/3 form; the Betchov constant
`C_S = (4/7)√(15/2)` against `⟨trS³⟩ = (105/8)⟨(∂₁u₁)³⟩` and `⟨S:S⟩ = (15/2)⟨(∂₁u₁)²⟩`;
`L₁₁ = (3π/4)∫(E/κ)/∫E`, `L₂₂ = L₁₁/2`, `L_E = (2/3)L₁₁`; `η`, `τ_η`, `λ`, `Re_λ`;
`G = (3/2)C_ε^{−2/3}` and the 0.81-vs-0.9 arithmetic; the 2/3, Hou–Li and phase-shift cutoffs
(`2√2/3 κ_Ny`, ×2.8 modes, the odd-axis cancellation); `2κ_max < N` alias-freedom;
`C_CFL ≲ y_s/(κ_maxΔx) = 1.732/2.094 ≈ 0.83`; `|R(iy)|² = 1 + y⁴/4`; the RKW3 coefficients and
node increments; `Re_λ ∼ N^{2/3}`; ζ_p for K62 and She–Lévêque; the Lundgren floor `Re_λ ≈ 34`;
Pope/von Kármán/Pao roll-off exponents and low-κ slopes.

---

## 1. The cache page still calls a landed reuse "blocked", and predicts the vorticity leaving the cache

- **type**: contradiction
- **severity**: major
- **confidence**: high

**Locations**

- PAGE `observables_cache`, §1.4 "What caching costs": "§2.3's blocked reuse keeps $\boldsymbol{\omega}$
  in the cache today, and the release that lands the reuse removes it."
- PAGE `observables_cache`, §1.2: "§2.3's blocked reuse keeps the vorticity in the cache today, and
  landing that reuse will take it out (§1.4)."
- PAGE `observables_cache`, §2.3: "The vorticity is deposited at the iteration's end either way, so the
  reuse changes the run's residency, not the cache's contents."
- PAGE `observables_cache`, §2.4 table row: "$\boldsymbol{\omega}$ | physical, grid | yes | yes".
- PAGE `architecture`, decision (2026-08): "This is the reuse §2.3 of the design page recorded as
  blocked before the backend's alias-safe kernels landed".

**Contradicts**: §2.3/§2.4 and decision 41 (reuse landed, ω still cached) vs §1.2/§1.4 (reuse blocked,
ω about to leave). Axis: whether the in-place Lamb-vector reuse has landed, and whether the vorticity
is a cache slot.

**Description**: §1.2 and §1.4 are written from the pre-landing world: they present the in-place
product reuse as still blocked and forecast that landing it removes ω from the cache. §2.3, the §2.4
table and the decision log all record it as landed, with ω deposited "either way". Both readings
cannot be current, and §1.4's central example of "what the design pays" rests on the stale one.

**resolution_hint**: rewrite §1.2/§1.4's illustration in the past tense (the reuse landed and did
*not* change contents), or pick a live example of a storage decision that would change contents.

---

## 2. The model spectrum evaluates Pope's roll-off at `L₁₁` while keeping Pope's normalization constant

- **type**: physics
- **severity**: major
- **confidence**: medium

**Locations**

- PAGE `api / phenomenology / Spectra`, `ModelSpectrum`:
  "$E(\kappa) = C_K \varepsilon^{2/3} \kappa^{-5/3} f_L(\kappa L_{11}) f_\eta(\kappa\eta)$"
- PAGE `api / phenomenology / Spectra`, `PopeLargeScale`: "The coefficient `c_L` is set by the
  requirement that the spectrum integrate to the kinetic energy"
- PAGE `api / phenomenology / Spectra`, `Pope2000`: "the defaults `c_L = 6.78`, `c_η = 0.40` are the
  high-Reynolds-number values Pope obtains from the energy and dissipation normalizations"

**Description**: Pope's `c_L = 6.78` / `c_η = 0.40` are fixed with the energy-containing scale
`L = k^{3/2}/ε`, not with `L₁₁`. The package's own constants give the ratio:
`L/L₁₁ = (3/2)^{3/2}/C_ε ≈ 1.84/0.5 ≈ 3.7` (`Sreenivasan1998`, `C_ε = εL₁₁/u'³ ≈ 0.5`). Feeding
`κL₁₁` into `f_L` with `c_L = 6.78` therefore places the energy-containing roll-off about 3.7× too
high in wavenumber and breaks `∫E dκ = k` — matching `c_L` at `L₁₁` would need ≈ 0.5. §4.8's
verification battery checks slopes, `ζ₃ = 1` and `f_L, f_η → 1`, never the energy normalization,
so nothing catches it.

**resolution_hint**: either derive `L = k^{3/2}/ε` inside `spectrum` (all of `u'`, `ε` are in
`FlowParameters`), or re-fit `c_L` for the `L₁₁` argument and drop the "Pope obtains" claim.

---

## 3. The validation path differences a per-shell energy against a spectral density

- **type**: dimensional
- **severity**: major
- **confidence**: medium

**Locations**

- PAGE `architecture`, decision (2026-07): "`validate_spectrum(sim, model)` compares the measured
  spectrum against a model spectrum evaluated at that state ... their relative $L^2$ discrepancy"
- PAGE `architecture`, decision (2026-08, user-directed): "to `test/validation.jl` as
  `compare_to_model`: comparing a run against a model spectrum"
- PAGE `notation`: "$E_n$ ... (dimensions $L^2T^{-2}$, a density times $\Delta\kappa$)" vs
  "$E(\kappa)$ ... (dimensions $L^3T^{-2}$)"
- PAGE `api / Observables`, `energy_spectrum`: "the two differ by the shell width
  $\Delta\kappa = 2\pi/L$ and are not interchangeable"

**Contradicts**: `energy_spectrum` / `notation` (E_n and E(κ) are different kinds of object, differing
by Δκ) vs the two decision entries describing a direct L² comparison of one against the other.
Axis: whether the comparison converts by Δκ.

**Description**: The package's headline measured-vs-predicted path is described as an L² difference of
`energy_spectrum`'s `E_n` (an energy, `L²T⁻²`) against `spectrum`'s `E(κ)` (a density, `L³T⁻²`), with
no Δκ conversion stated anywhere. The error is exactly invisible on the shipped default box, where
`Δκ = 2π/L = 1`, and becomes a silent scale error at any other `side_length` — the kind of factor the
documentation policy elsewhere insists on expanding.

**resolution_hint**: state the conversion (`E_n ≈ E(κ_n)Δκ`) where the comparison is described, and add
a non-2π-box case to the validation test.

---

## 4. `ConstantPower`'s keyword is described as holding the dissipation rate, which it does not

- **type**: contradiction
- **severity**: minor
- **confidence**: high

**Locations**

- PAGE `api / Forcing`, `ConstantPower`: "`injection_rate` — the value of the dissipation rate to hold."
  and "so `injection_rate` is a number: the value of the dissipation rate to hold"
- PAGE `notation`, Forcing table: "$\varepsilon_{\mathrm{target}}$ | target energy-injection rate |
  ConstantPower(injection_rate=…)"
- PAGE `architecture`, §2: "advance until the running dissipation ε(t) stops drifting ... a
  fixed-injection forcing like this makes it ring"

**Contradicts**: the notation glossary and §4.4 ("its rate reset each step to hold the injection rate")
vs the `ConstantPower` argument gloss. Axis: which quantity the forcing clamps.

**Description**: `ConstantPower` fixes the *injection* rate exactly, every step. ε is a measured,
fluctuating observable that equals it only in the long-time stationary mean — which is precisely why
`warmup!` gates on ε drift under this forcing, and why `BandRescaling`'s caveat recommends
`ConstantPower` when the held quantity is itself measured. Calling the keyword "the value of the
dissipation rate to hold" conflates a control input with a measured rate.

**resolution_hint**: "the energy-injection rate to hold — the value ε relaxes to in the stationary mean".

---

## 5. The `FlowParameters` example states violate the package's own normalized-dissipation constant

- **type**: physics
- **severity**: minor
- **confidence**: high

**Locations**

- PAGE `phenomenology`: "`FlowParameters(viscosity = 1e-3, dissipation = 0.1, rms_velocity = 1.0,
  integral_scale = 1.0)`"
- PAGE `api / phenomenology / Phenomenology`, `FlowParameters` Examples: "`integral_scale = 0.5`"
  (both examples)
- PAGE `api / phenomenology / Scalings`, `Sreenivasan1998`: "$C_\varepsilon = \varepsilon L_{11}/u'^3$
  ... approaches a constant of order $0.5$"

**Description**: These states give `C_ε = εL₁₁/u'³ = 0.1` and `0.05` — five to ten times below the
package's own high-Reynolds plateau — at `Re_λ = u'²√(15/(νε)) ≈ 390`, well inside the range where
the plateau is asserted to hold. Equivalently `L₁₁/η = 50` where `ν` and `ε` imply ≈ 500. A reader who
evaluates `Pope2000` or `ObukhovCorrsin1949` at the documented example state is evaluating a law far
outside the regime it was fitted for.

**resolution_hint**: pick example numbers that satisfy `ε ≈ 0.5 u'³/L₁₁` (e.g. ν = 1e-3, ε = 0.1,
u' = 1, L₁₁ = 5).

---

## 6. The flagship explicit-viscosity example is under-resolved by the package's own criterion

- **type**: physics
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE `architecture`, §2: "`Simulation(grid_points_per_axis = 128, viscosity = 5e-3;
  velocity_forcing = ConstantPower(injection_rate = 0.1)`"
- PAGE `api / SimulationRun`, `Simulation`: "`κ_max_η = 2` — the resolution criterion ... $\ge 1.5$ is
  well-resolved"

**Description**: With `ConstantPower(injection_rate = 0.1)` the stationary ε ≈ 0.1, so
`η = (ν³/ε)^{1/4} = 0.0334` and `κ_max = (2/3)(N/2)(2π/L) = 42.7` on the default 2π box, giving
`κ_max η ≈ 1.43` — below the docstring's own "well-resolved" threshold and well below the grid-mode
default of 2. The same pairing (`128³`, `viscosity = 5e-3`) recurs in the `Simulation` examples.

**resolution_hint**: use `viscosity ≈ 3e-3` in the examples, or note that the explicit-mode example is
deliberately marginal.

---

## 7. `envelope_wavenumber` means two different large scales in its two modes

- **type**: physics
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE `api / SimulationRun`, `Simulation`: "`envelope_wavenumber = 2.0` — the large-scale envelope
  wavenumber $\kappa_p$ ... (each shell-summed spectrum peaks at $\kappa_p/\sqrt{2}$); it also sets the
  integral scale `initial_spectrum` is evaluated at"
- PAGE `api / SimulationRun`, `Simulation`: "with its integral scale taken as `1/envelope_wavenumber`"

**Description**: Read as a Gaussian envelope, `κ_p = 2` puts the initial spectral peak at
`κ_p/√2 ≈ 1.41`. Read as an integral scale, `L₁₁ = 0.5` with `VonKarman1948(c_L = 1)` peaks where
`(κL₁₁)² = 12/5`, i.e. `κ ≈ 3.1` — a factor ≈ 2.2 higher, and a much broader spectrum with no viscous
cutoff. Passing `initial_spectrum` therefore silently moves the energy-containing scale while the
keyword that "sets" it is unchanged.

**resolution_hint**: state the two peak locations explicitly, or convert the envelope wavenumber to a
matching `L₁₁` so both modes seed the same large scale.

---

## 8. `Li2008`'s `G` is transferred to grid mode with no forcing-band caveat

- **type**: physics
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE `api / phenomenology / Scalings`, `Li2008`: "$G = \frac{k}{(L\varepsilon)^{2/3}} \approx 0.9$ ...
  nearly Reynolds-number-independent from the ... JHTDB forced-isotropic dataset"
- PAGE `api / SimulationRun`, `Simulation`: "Grid mode is calibrated on a stationary forced balance ...
  so a decaying run should set $\nu$ explicitly"
- PAGE `api / Forcing`, `BandRescaling`: "`lowest_shell = 1`, `highest_shell = 2`"

**Description**: `G` is a box-normalized group, i.e. `C_ε` rescaled by `L₁₁/L`; that ratio is fixed by
*where the run is forced*, not by Reynolds number. Its transfer to a new run therefore assumes the
same low-shell forcing band as the calibrating dataset. Grid mode caveats only the decaying case, so a
user who overrides `velocity_forcing` with a higher band (`lowest_shell = 4`, say) still gets ν set
from `G`, silently missing the intended `κ_max η`.

**resolution_hint**: add "and a forcing confined to the same low-wavenumber band" to grid mode's
stated validity condition.

---

## 9. `StationarityCriterion` is recommended for runs that have no stationary state

- **type**: method
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE `api / SimulationRun`, `StationarityCriterion`: "Use it before measurement on any freshly seeded
  run"
- PAGE `api / SimulationRun`, `StationarityCriterion`: "an unforced scalar has no stationary state and
  is never gated"
- PAGE `api / SimulationRun`, `Simulation`: "for a decaying run (`velocity_forcing = NoForcing()`)"

**Contradicts**: the criterion's own scalar-gate reasoning (an unforced field has no stationary state)
vs its blanket recommendation for "any freshly seeded run". Axis: forced vs freely decaying.

**Description**: A freely decaying run's ε never plateaus, so the criterion can only run to
`max_turnovers` and warn — the exact argument the docstring already makes for the unforced scalar,
applied one field short. `NoForcing` is a supported first-class configuration, so the recommendation
should be scoped to forced runs.

**resolution_hint**: "before measurement on any freshly seeded *forced* run; a decaying run has no
stationary state — use a fixed budget".

---

## 10. `deposit_sample!` is named as a required user call but is documented nowhere

- **type**: api-gap
- **severity**: minor
- **confidence**: high

**Locations**

- PAGE `api / Cache`, `particles_modified!`: "must call this, then `record_particle_velocity!` ...
  and finally `deposit_sample!` to record them at the current epochs"
- PAGE `api / GBGIsotropicTurbulence`, Index: no `deposit_sample!` entry.

**Description**: A hand-run tracer loop is instructed to call `deposit_sample!` as the step that makes
the sample readable, yet the verb appears in no module map, no `@docs` block, and no index — the
reader has no signature, argument list, or ordering contract for a call the docstring calls mandatory.
Its neighbours in the same sentence are all exported and documented.

**resolution_hint**: document and export it, or rewrite the instruction in terms of the documented
`deposit!` / `advance!` path.

---

## 11. The `ScalingLaw` family advertises the derivative skewness, which it does not carry

- **type**: current-and-complete
- **severity**: nit
- **confidence**: high

**Locations**

- PAGE `api / phenomenology / Scalings`, `ScalingLaw`: "a pure number characterizing developed
  turbulence (the normalized dissipation $C_\varepsilon$, the Kolmogorov constant $C_K$, the derivative
  skewness, …)"
- PAGE `architecture`, §4.8: "The derivative skewness, the flatness, the Lagrangian $C_0$ ... are
  forward-looking additions to the family, not yet built."

**Description**: The supertype's illustrative list names a law the module does not provide, and the
module map lists only four objects. A cold reader looking for a reference `S ≈ −0.5` to compare
`derivative_skewness` against will hunt for a preset that does not exist — the more so as the skewness
is the one constant the warm-up gate already measures.

**resolution_hint**: illustrate with built laws only, or mark the skewness entry as a future addition.

---

## 12. `ConstantPower`'s rate has an unguarded singular limit

- **type**: physics
- **severity**: nit
- **confidence**: low

**Locations**

- PAGE `api / Forcing`, `ConstantPower`: "$A = \frac{\texttt{injection\_rate}}{2 E_{\mathrm{band}}}$"
- PAGE `api / Forcing`, `BandRescaling`: "the band is zeroed — the closest reachable state — and the
  most violent intervention the rescale can make"

**Description**: The rate diverges as the band's own energy goes to zero — reachable from a scalar
seeded with no content in shells 1–2, or immediately after a `:total` rescale zeroes the band. The
sibling strategy documents its extreme case explicitly; this one states no floor, guard, or resulting
behaviour, and the divergence lands inside an exponential integrating factor.

**resolution_hint**: state the guard (or its absence) in a caveat admonition, as `BandRescaling` does.
