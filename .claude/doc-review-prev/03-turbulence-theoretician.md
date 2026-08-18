# Hat 03 — Turbulence theoretician

Fresh-eyed audit of the rendered docs for physical definitions, conservation laws, scaling
constants, derived scales, and category/type errors (field vs representation, rate vs field,
operator vs parameter, density vs energy).

**Verified clean** (expanded against theory, no defect): `derivative_skewness`
(`C_S = 4/7·√(15/2)`, `⟨tr S³⟩ = (105/8)⟨(∂ₓ₁u₁)³⟩`, `⟨S:S⟩ = (15/2)⟨(∂ₓ₁u₁)²⟩` — mutually
consistent, and `3C_S⟨det S⟩` follows from `tr S³ = 3 det S`); Yaglom `−2/3 ε_φ r` (correct once
`ε_φ = 2ϰ⟨|∇φ|²⟩` is the full-variance rate — derived from the KHM balance); `ε = ν⟨|ω|²⟩ =
2ν⟨SᵢⱼSᵢⱼ⟩` and its Dirichlet route; `L₁₁ = (3π/4)∫E/κ / ∫E`, `L_E = (2/3)L₁₁ = (π/2)∫E/κ / ∫E`,
`L₂₂ = L₁₁/2`; `u' = √(2k/3)`, `λ`, `η`, `τ_η`, `Re_λ = u'²√(15/νε)`; `G = (3/2)C_ε^{−2/3}` and
`ε = (k/G)^{3/2}/L`; `κ_max η = fπη/Δx`, `Re_λ ∼ N^{2/3}`; the alias-freedom condition
`2κ_max < N` (and the cubic skewness residual at the 2/3 rule); phase-shift `2√2/3 κ_Ny`, ×2.8
modes; RK3/RK2 coefficients, `|R(iy)|² = 1 + y⁴/4`, `C ≲ 0.83`; Gaussian-envelope peak at
`κ_p/√2`; She–Lévêque, K62, Pope/von Kármán/Pao/Obukhov–Corrsin forms and constants.

---

## 1. The default run uses the forcing the docs call unfit for measurement, with no caveat at the front door

- **type**: contradiction · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: api / SimulationRun, `Simulation` — "By default the run is forced and stationary — a
    `BandRescaling` holds the total (whole-field) energy at `kinetic_energy`"
  - PAGE: api / Forcing, `BandRescaling` Note — "This is a deterministic clamp, not a faithful
    stationary sampler." … "when the held quantity is itself measured, prefer a fixed-injection
    forcing (`ConstantPower`)"
- **contradicts**: the two pages disagree on the axis *is the default configuration fit for
  measurement*. ARCHITECTURE §4.4 takes the Forcing page's side: "a deterministic clamp, fit for
  spin-up and amplitude-holding but not a faithful stationary sampler".
- **description**: Every front-door run is driven by the Berendsen-class clamp, and the clamped
  quantity is `kinetic_energy` — precisely what a validation run measures (it pins `u'`, hence the
  scale of `Re_λ`, and suppresses the physical fluctuations of `k`). The `Simulation` docstring
  presents this as "forced and stationary" with no caveat and no pointer to the `BandRescaling`
  note, so a reader who never opens the Forcing page samples a non-physical ensemble by default.
- **resolution_hint**: carry a one-line `!!! note` on `Simulation` ("the default holds `k`; for
  fluctuation statistics of the held quantity use `ConstantPower`"), or reconsider the default.

## 2. Does a velocity forcing carry a Leray projection, or does none act on `f`?

- **type**: contradiction · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: architecture §4.4 — "the only field-specific step is the solenoidal (Leray) projection,
    applied to the velocity alone"
  - PAGE: observables_cache §2.1 — "No projection acts on $\boldsymbol{f}$: every velocity forcing
    the package provides is already divergence-free"
- **contradicts**: axis — whether the forcing pipeline contains a projection step for the current
  strategy menu.
- **description**: §4.4 names the Leray projection as the one field-specific step of the four-hook
  interface; the cache page states no projection acts on the forcing at all, and the docstrings
  agree (`BandRescaling` "preserves the divergence-free constraint either way"; `ConstantPower`
  "preserves a solenoidal velocity"). The only projector is the archived `StochasticOU`, so §4.4
  describes a step no built forcing performs.

## 3. "Energy-conserving" is attached to the rotational form, not to the exact-dealiasing condition

- **type**: physics · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: architecture §4.2 — "Rotational form is the cheap, energy-conserving way to compute the
    advection spectrally"
  - PAGE: architecture §7 — "the skew-symmetric momentum form (which reorganizes the quadratic
    product to conserve energy in the discrete equations)"; and, of `HouLi`, "the one deliberately
    non-conservative strategy"
- **contradicts**: axis — which object owns the discrete energy conservation: the *form* of the
  advective term, or the *sharp (exact-Galerkin) dealiasing*.
- **description**: In the continuum every form conserves energy; discretely, conservation follows
  from exact dealiasing (§7's own ν = 0 entry: "the sharp-masked assembly is the exact Galerkin
  truncation … which conserves kinetic energy"). Under `HouLi` the same rotational assembly is
  documented as dissipative, and §7 credits discrete conservation to the skew-symmetric form. The
  unqualified §4.2 claim reads as a property of rotational form itself.

## 4. "Spectral fields" / "the spectral velocity" — the field-vs-representation rule the docs themselves set

- **type**: contradiction · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: architecture §4.1 — "`ResolvedFields` is the record of the evolving spectral fields"
  - PAGE: architecture §4.5 — "advances the spectral velocity $\hat{\boldsymbol{u}}$ and scalar
    $\hat\varphi$ together"
  - PAGE: api / Cache, `resolved_fields_modified!` — "the resolved fields — the spectral
    $\hat{\boldsymbol{u}}$, $\hat\varphi$ — were changed"
- **contradicts**: PAGE: notation — "A field is one physical object; physical and spectral are two
  representations of it."; PAGE: architecture §10 — the category-error class names "a field with
  its representation (physical vs spectral)".
- **description**: The rule is stated twice and broken three times on surfaces that must model it
  (the design doc's current-state sections and a user-facing docstring). Everywhere else the docs
  are exact — "the velocity `û` in spectral representation" — so these are the residue of the older
  phrasing, and one of them is a rendered REPL docstring.

## 5. "Every diagnostic is dimensionless" versus the dimensional flow-parameter bundle

- **type**: dimensional · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: architecture §9 — "No units. Control is by $\mathrm{Re}$ (through $\nu$) and
    $\mathrm{Sc}$; every diagnostic is dimensionless."
  - PAGE: api / phenomenology / Phenomenology, `FlowParameters` — "It carries the independent
    dimensional quantities of a homogeneous isotropic state ($\nu$, $\varepsilon$, $u'$, $L_{11}$)"
- **contradicts**: axis — the dimensional status of the measured diagnostics. The `Scalings` page
  reinforces the second reading ("Dimensionless turbulence constants", $C_\varepsilon$, $C_K$, $G$
  — dimensionless *because* they are groups formed from dimensional quantities).
- **description**: `ε`, `k`, `u'`, `L₁₁`, `η`, `τ_η`, `λ` all carry dimensions in code units;
  what is unitless is the *control* (Re, Sc) and the *reference constants*. As written, invariant
  "every diagnostic is dimensionless" is false for every diagnostic in `Observables` except the
  skewness, and it collides with the phenomenology surface that reasons in dimensional groups.
- **resolution_hint**: "no physical units — quantities are in box units, and control is by Re and
  Sc" says the intended thing without the false quantifier.

## 6. `C` denotes both the CFL ceiling and the skewness isotropy constant

- **type**: contradiction · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: notation, Numerics — "$C$ | advective-CFL ceiling, $\Delta t = C \Delta x/\max_i\lvert
    u_i\rvert$ (the derivative-skewness isotropy constant wears the subscripted $C_S$)"
  - PAGE: architecture §4.3 — "$3C\langle\det\boldsymbol{S}\rangle/\langle\boldsymbol{S}:
    \boldsymbol{S}\rangle^{3/2}$ with the exact isotropy constant $C_S = \tfrac{4}{7}\sqrt{15/2}$"
- **contradicts**: axis — one symbol, two concepts. The glossary explicitly reserves bare `C` for
  the CFL ceiling; §4.3 (and §11 decision 17, which repeats the formula verbatim) puts bare `C`
  inside the skewness formula and then names the same constant `C_S` in the following clause.
- **description**: The rendered `derivative_skewness` docstring uses `C_S` consistently, so the
  design document is the outlier — and it is the surface that states the "one symbol per concept"
  rule. A reader tracking `C` through the docs meets the CFL ceiling and a strain invariant.

## 7. `τ` means the integrating-factor substep everywhere except one turnover budget

- **type**: contradiction · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: notation — "$\mathcal{E}(\boldsymbol{\kappa})$ … over an interval $\tau$ — a Runge–Kutta
    stage substep $d_i\Delta t$, or the whole step $\Delta t$"
  - PAGE: observables_cache §1.3 — "a budget in turnovers, for instance, is a callback that
    accumulates $\Delta t/\tau$ and says stop"
- **contradicts**: axis — the referent of `τ`: a stage sub-interval of the propagator versus the
  large-eddy turnover time. The glossary also holds `τ_η` for the Kolmogorov time, so the reader
  has two neighbouring bindings to choose from.
- **description**: The turnover time is never bound on that page, and every other surface writes
  the same budget explicitly as `Δt ε/k` (`run!`, `StationarityCriterion`). Given `τ` is the
  factor-verb argument name throughout `Generator` and `Propagator`, the bare `Δt/τ` reads at first
  as a ratio of numerical intervals.

## 8. `StationarityCriterion` is documented as not reading `k`, but its turnover clock is `Δt ε/k`

- **type**: contradiction · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: architecture §4.7 — "a trailing-window flatness test, reading $\varepsilon$ rather than
    the clampable $k(t)$"
  - PAGE: api / SimulationRun, `StationarityCriterion` — "it measures the dissipation $\varepsilon$
    (one reduction …), accumulates the eddy-turnover clock $\Delta t \varepsilon/k$"
- **contradicts**: axis — whether `k` is measured by the criterion at all, and how many reductions
  an observation costs.
- **description**: `k` *is* measured — it normalizes the turnover clock that gates
  `min_turnovers` / `window_turnovers` / `max_turnovers`, so the clock inherits whatever the forcing
  does to `k`. The distinction the docs want is *gate* versus *clock*: `k` is excluded from the
  flatness gate, not from the criterion. As written, "(one reduction)" also undercounts the per-
  observation cost.

## 9. The RK3 docstring rotates the accumulator at every stage; the audit records the last rotation skipped

- **type**: contradiction · **severity**: nit · **confidence**: medium
- **locations**:
  - PAGE: api / Propagator, `IFLowStorageRK3` — "$\boldsymbol{h} \leftarrow \mathcal{E}_D(d_i\Delta
    t)\boldsymbol{h}$" listed for stages "$i = 1,2,3$"
  - PAGE: architecture §11 (compute audit) — "upgraded to pass-exact fidelity to `step!` (stage 1
    seeds the low-storage accumulator, the last stage skips its rotation)"
- **contradicts**: axis — the per-stage operation count of the implemented schedule.
- **description**: Mathematically the final rotation is dead work (its result is never read), so
  skipping it is correct; but the docstring presents the four-line stage body as uniform over
  `i = 1,2,3` and a reader counting exponential applications against the frozen ledgers finds one
  too many. A half-sentence ("the final stage's accumulator rotation is dead and is skipped")
  reconciles them.

## 10. "The enstrophy" without the ½, against the package's own half-quantity convention

- **type**: physics · **severity**: nit · **confidence**: low
- **locations**:
  - PAGE: api / Observables, `dissipation` — "the enstrophy of a divergence-free velocity is its
    Dirichlet ($H^{1}$) energy, $\langle\lvert\boldsymbol{\omega}\rvert^{2}\rangle = \langle
    \hat{\boldsymbol{u}},\lvert\boldsymbol{\kappa}\rvert^{2}\hat{\boldsymbol{u}}\rangle$"
- **contradicts**: the package's stated half-quantity convention for the vorticity's twin —
  `kinetic_energy` $k = \tfrac{1}{2}\langle\lvert\boldsymbol{u}\rvert^{2}\rangle$ — under which the
  vorticity analogue is $\tfrac{1}{2}\langle\lvert\boldsymbol{\omega}\rvert^{2}\rangle$.
- **description**: Both conventions exist in the literature, so this is a house-consistency point
  rather than an error: the doc names $\langle|\omega|^2\rangle$ "the enstrophy" while naming
  $\tfrac{1}{2}\langle|u|^2\rangle$ (not $\langle|u|^2\rangle$) the energy. Since the notation page
  binds every other symbol, "the mean-square vorticity" or an explicit factor would remove the
  ambiguity — the same care the scalar variance's missing ½ already gets.
