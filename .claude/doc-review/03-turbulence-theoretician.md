# Doc-review panel — hat 03: TURBULENCE THEORETICIAN

Rendered-docs audit of physical definitions, conservation laws, scaling laws, dimensionless
constants, derived scales, and category/type errors. Findings ranked most-severe first.

Verified-clean (checked and correct, recorded so a later round need not redo them): the
derivative-skewness constant `C_S = (4/7)√(15/2) ≈ 1.5649` together with both Betchov bridges
`⟨tr S³⟩ = (105/8)⟨(∂ₓ₁u₁)³⟩` and `⟨S:S⟩ = (15/2)⟨(∂ₓ₁u₁)²⟩`; `ε = ν⟨|ω|²⟩ = 2ν⟨SᵢⱼSᵢⱼ⟩` and its
`2⟨(∇·u)²⟩` difference; the Dirichlet route `⟨|ω|²⟩ = ⟨û,|κ|²û⟩`; the Yaglom half/full-variance
factor (`−4/3 → −2/3 ε_φ`); Obukhov–Corrsin 0.67 as the 3-D partner of Sreenivasan's 1-D 0.4;
`C₂ ≈ 2.0` against `C_K = 1.5`; `G = (3/2)C_ε^{−2/3}` and the `G ≈ 0.81 vs 0.9` reconciliation at
`L/L₁₁ ≈ 5`; `L₁₁/L₀ = C_ε(2/3)^{3/2}` with the 0.42k / 0.57k numbers; `L_E = (2/3)L₁₁ =
(1/3)(L₁₁+2L₂₂)`; the alias-free condition `2κ_max < N`; `κ_max Δx = 2π/3`, `C_CFL ≲ 0.83`,
`|R(iy)|² = 1 + y⁴/4`; the RKW3 coefficients and their `c = (0,1/3,3/4)` consistency; the
Williamson/IF-Heun linear exactness; the phase-shift `√2` band and `2.83×` mode count; the
`κ_p/√2` envelope peak; the Lundgren `Re_λ ≈ 34` sign flip and the "half the coefficient at 100";
She–Lévêque and K62 at `ζ₃ = 1`; `Re_λ ~ N^{2/3}`; the transform ledgers (18/9, 21/18, and their
exact doubling).

---

## 1. `Li2008` attributes this package's own fit to Li et al. (2008)

- **type**: citation
- **severity**: major
- **confidence**: high

**Locations**

- PAGE: api / phenomenology / Scalings, `Li2008`: "The value is this package's **own reduction** of
  the Johns Hopkins Turbulence Database (JHTDB) forced-isotropic dataset"
- PAGE: api / SimulationRun, `Simulation` → Grid mode: "a dimensionless constant calibrated on
  box-confined DNS (**≈ 0.9; Li et al. 2008**)"
- PAGE: api / phenomenology / Phenomenology (naming rule): "its **author-year** (the paper)"

**Contradicts**: the `Li2008` docstring says the number is ours; the `Simulation` grid-mode
paragraph cites it to Li et al. (2008), and the author-year handle asserts the same.

**Description**

Li et al. (2008) is a database-description paper; it does not publish `G = k/(Lε)^{2/3} ≈ 0.9`.
The preset's own docstring concedes the value is the package's reduction of their *data*, yet the
name and the run-layer citation both present it as a published fit. `Phenomenology`'s charter says
our own fits sit beside the literature as equals — which requires they not borrow a literature
handle. This is the one law the run layer *acts* on (it sets ν), so the provenance matters.

**resolution_hint**: rename to our own author-year handle (with the JHTDB dataset cited as the
calibration source inside `provenance`), or keep `Li2008` only if a Li-et-al. figure is quoted.

---

## 2. Grid mode's `κ_max_η` treats `HouLi`'s merely-damped band as clean signal

- **type**: physics
- **severity**: major
- **confidence**: medium

**Locations**

- PAGE: api / SimulationRun, `Simulation`: "That criterion treats the whole retained band as clean
  signal — exact for `TwoThirds` and `PhaseShift`, **approximate for `HouLi`**"
- PAGE: api / SimulationDomain, `max_wavenumber`: "$f$ the retained-Nyquist fraction … **$1$ for
  `HouLi`**"
- PAGE: api / Observables, `kinetic_energy`: "`HouLi` … **alias-free in practice, not exactly**"

**Description**

With `f = 1`, `κ_max η = f π η/Δx = 2` gives **η ≈ 0.64 Δx** — the dissipation scale falls below the
grid spacing — and ν ∝ f^{−4/3} makes grid mode hand `HouLi` a ~31 % higher Re_λ than `TwoThirds` on
the same N. The page states `Δx ≈ η` for `f = 2/3` but gives no number for `HouLi`, so "the highest
Reynolds number consistent with the resolution criterion" reads as comparable across strategies when
it is not. The word "approximate" understates a band that is damped rather than dealiased.

**resolution_hint**: quote `η/Δx` per strategy, or exclude `HouLi` from grid mode's default
criterion.

---

## 3. Grid mode is self-consistent only under a k-clamping forcing, and only `BandRescaling` says so

- **type**: physics
- **severity**: major
- **confidence**: medium

**Locations**

- PAGE: api / SimulationRun, `Simulation` → Grid mode: "$\varepsilon = (k/G)^{3/2}/L$ **with
  `kinetic_energy` the kinetic energy $k$**"
- PAGE: api / Forcing, `BandRescaling`: "the resolution criterion $\kappa_{\max}\eta$ is **only
  self-consistent if the run really holds $k$ there**"

**Description**

The constraint lives in the `BandRescaling` docstring, not where the trap is. `Simulation(;
grid_points_per_axis = 128, velocity_forcing = ConstantPower(injection_rate = 0.1))` is legal, stays
in grid mode, and silently violates it: `ConstantPower` lets k find its own level, so the assumed k
— and with it ε, η and the chosen ν — is wrong, and the run is resolved to a criterion it never
meets. The grid-mode paragraph names only the *band* assumption, not the *amplitude* one.

**resolution_hint**: state the constraint (or warn/error) at the grid-mode branch when a
non-k-clamping `velocity_forcing` is supplied.

---

## 4. `VonKarman1948` does not integrate to k, and the page does not say so

- **type**: physics
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE: api / phenomenology / Spectra, `VonKarman1948`: "`c_L` … is a **shape parameter** of this
  form rather than a normalization — **no energy condition determines it**, and the default `1.0` is
  the conventional choice"
- PAGE: api / phenomenology / Spectra, `large_scale_length`: "the spectrum integrates to **$0.42k$**"

**Description**

The sibling normalization breakage is quantified for Pope's form; the same defect in
`VonKarman1948` is only hinted at. Integrating `E = C_K ε^{2/3}κ^{−5/3}((κL)²/((κL)²+1))^{17/6}`
gives `∫E dκ = 1.55 (εL₁₁)^{2/3}` against `k = (3/2)C_ε^{−2/3}(εL₁₁)^{2/3}` — **≈ 0.65 k at
C_ε = 0.5**, 0.88 k at 0.79. Harmless as an IC (the field is renormalized), but a systematic
amplitude offset in any relative-L² comparison of a measured spectrum against this preset.

**resolution_hint**: state the offset (as `large_scale_length` does), or make `c_L` normalization-
determined for this form too.

---

## 5. The assumed integral scale `1/envelope_wavenumber` is not the seeded field's `L₁₁`

- **type**: dimensional
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE: api / SimulationRun, `Simulation`, `initial_spectrum`: "and the integral scale as
  **`1/envelope_wavenumber`**"
- PAGE: api / Observables, `integral_scale`: "$L_{11} = \frac{3\pi}{4}\frac{\int E/\kappa}{\int E}$"

**Description**

Applying the package's own `integral_scale` definition to the default envelope
`E ∝ κ²exp(−2κ²/κ_p²)` gives `L₁₁ = (3/4)√(8π)/κ_p = 3.76/κ_p` — **1.88 at the default κ_p = 2**,
not 0.5. Using 0.5 to position a model spectrum pushes its energy-containing peak up by a factor
≈ 2 (VonKarman1948 with c_L = 1 peaks at κ ≈ 3.1 against the Gaussian branch's 1.41), so the two IC
branches seed visibly different large scales at the same nominal setting.

**resolution_hint**: either derive the assumed `L₁₁` from the envelope (≈ 3.76/κ_p) or expose it as
its own keyword.

---

## 6. `envelope_wavenumber` is said both to feed and not to feed the `initial_spectrum` branch

- **type**: contradiction
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE: api / SimulationRun, `Simulation`: "it **also sets the integral scale in the assumed state
  `initial_spectrum` reads**"
- PAGE: api / State, `random_solenoidal_velocity_spectral!`: "The `envelope_wavenumber` setting has
  **no effect in the `initial_spectrum` branch**"

**Contradicts**: the two sentences make opposite claims about whether `envelope_wavenumber`
influences a run seeded from a model spectrum; the axis is which layer is meant (front door vs
seeder), which neither sentence names.

**Description**

Both are true at their own layer — the seeder receives an already-evaluated `κ ↦ E(κ)`, while the
front door builds that closure from an assumed state whose integral scale is `1/envelope_wavenumber`
— but a reader meeting the two sentences has no way to see that, and the seeder's flat "no effect"
is the one they will believe. The identical text appears in `random_scalar_spectral!`.

**resolution_hint**: qualify the seeder sentence ("no effect *on this call*; the front door uses it
to build the spectrum function").

---

## 7. The resolution criterion is silent about the scalar's Batchelor scale

- **type**: physics
- **severity**: minor
- **confidence**: high

**Locations**

- PAGE: api / SimulationRun, `Simulation`: "sets $\nu$ so that $\kappa_{\max}\eta$ equals
  `κ_max_η` — the resolution criterion"
- PAGE: api / SimulationRun, `Simulation`: "`schmidt = 1.0` — the Schmidt number $\mathrm{Sc}$"

**Description**

`κ_max η` is a velocity criterion. `schmidt` is a free keyword with no stated bound, and at Sc > 1
the scalar's smallest scale is `η_B = η/√Sc`, so `Simulation(; grid_points_per_axis = N,
schmidt = 4)` reports a well-resolved run whose scalar is resolved only to `κ_max η_B = 1`. No page —
grid mode, `FlowConditions`, `scalar_dissipation` — records that the criterion covers one field
only. (Not a request for high-Sc machinery; a request for the caveat.)

**resolution_hint**: one sentence in the grid-mode paragraph: the criterion is set on η, so scale
`κ_max_η` by √Sc when Sc > 1.

---

## 8. Under `over = :band` the claim "k still measures the flow" overstates what is left free

- **type**: physics
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE: api / Forcing, `BandRescaling`: "The band's energy is then set by the forcing rather than by
  the flow, **while $k$ still measures the flow itself**"
- PAGE: architecture, §11 decision (`over` required): "under `:band` the band is the artifact and
  **$k$ is a measurable of the flow**"

**Description**

The clamped band is `lowest_shell = 1` to `highest_shell = 2` — the energy-containing range, which
in a 2π box carries the large majority of k. A deterministic clamp on it therefore suppresses most
of k's physical fluctuation too; what remains free is the out-of-band remainder, a small fraction.
The docstring's own framing ("`over` decides which quantity your run may no longer measure") is
right, but the `:band` bullet then promises more freedom for k than the shell choice delivers.

**resolution_hint**: soften to "k retains its out-of-band fluctuation" rather than "measures the
flow itself".

---

## 9. The glossary binds ω to a producer verb, and leaves Re_λ the one scale without its formula

- **type**: typesetting
- **severity**: nit
- **confidence**: high

**Locations**

- PAGE: notation, Physical variables: "$\boldsymbol{\omega}$ | the vorticity $\nabla\times
  \boldsymbol{u}$ | **vorticity_physical!**"
- PAGE: notation, Derived scales: "$\mathrm{Re}_\lambda$ | Taylor-microscale Reynolds number,
  **measured from the flow state** | taylor_reynolds"

**Description**

Two small breaks in the glossary's own pattern. The Code column elsewhere names the storage a symbol
denotes ("the velocity state", "the scalar state", `particle_positions`); ω is given the recovery
*verb* instead, though `cache.vorticity_physical` is exactly its storage. And every neighbouring
derived scale carries its defining expression (η, τ_η, λ, u', L₁₁) while Re_λ alone carries a
description — the reader must leave for `taylor_reynolds` to learn it is `u'λ/ν`.

**resolution_hint**: `Cache.vorticity_physical` in the Code column; add `= u'\lambda/\nu`.
