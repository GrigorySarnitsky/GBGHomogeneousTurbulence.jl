# Hat 05 — Turbulence theoretician (physics, dimensionless constants, category/type errors)

Substrate: the rendered-site manuscript only. Verified by expansion: `dissipation`'s two forms,
the strain-skewness constant chain (`⟨tr S³⟩ = 105/8 ⟨(∂₁u₁)³⟩`, `⟨S:S⟩ = 15/2 ⟨(∂₁u₁)²⟩`,
`C_S = 4/7 √(15/2) = 1.5649`), Yaglom's `−2/3 ε_φ r` in full-variance variables, the
`L₁₁ / L₂₂ / L_E = 2/3 L₁₁` family, `G = 3/2 C_ε^{-2/3}` and its `L/L₁₁ ≈ 5` carry-over to
`G ≈ 0.81`, `ν ∝ f^{-4/3}` ⇒ 31 % higher `Re_λ` for `HouLi`, `Re_λ ∼ N^{2/3}`, the
`VarianceController` closure `dk/dt = −G(k−k_∞)/t_ℓ`, `ConstantPower`'s `A = P/2E_band`,
the CFL numbers (`κ_max Δx = 2π/3`, `C ≲ 0.83`), the PhaseShift band (`2√2/3 κ_Ny`, `≈2.8×`
modes), the transform tables, the `κ_p/√2` envelope peak, and every model-spectrum roll-off.
Those all check out; the findings below are what did not.

---

## 1. `ARCHITECTURE` §4.6 still says there is only one trajectory scheme; the Particles page ships two

- **type**: contradiction · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: architecture, §4.6 Particles — "the trajectory scheme — today the single second-order
    `EndpointHeun`, with higher-order schemes the studied future axis"
  - PAGE: api / Particles, `AbstractParticleIntegrator` — "Two members today: `EndpointHeun` …
    and `AdamsBashforth`"
- **contradicts**: the same axis (how many trajectory schemes exist *today*) is stated as one in the
  spec and two in the API page; `Simulation`'s `trajectory_scheme` keyword also advertises
  `AdamsBashforth()`.
- **description**: §4.6 is a current-state section (not the append-only log), so this is a stale
  claim, not history. The same staleness propagates: the api overview calls Particles
  "second-order `advect!` (Heun-in-time)" and the Home page "second-order advection", both naming
  only the one-step method now that a variable-step Adams–Bashforth of order up to 8 is exported.
  §4.6's `allocate_buffers(scheme, tracers)` is likewise incomplete — the multistep scheme's form
  takes a third argument, the cache.
- **resolution_hint**: rewrite §4.6's "two axes matter" sentence around the two shipped schemes and
  sweep the Home/api-overview one-liners in the same pass.

## 2. "Four strategies are provided" — five are

- **type**: contradiction · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: architecture, §4.4 Forcing — "Four strategies are provided." … then `NoForcing`,
    `Linear`, `ConstantPower`, `VarianceController`, `VarianceRescaling`
  - PAGE: architecture, §4.4 — "because these four methods are written through
    tensor-order-generic field operators"
  - PAGE: api / Forcing, module map — five bullets, `NoForcing` … `VarianceRescaling`
- **contradicts**: the count of built forcing strategies, four in the spec against five everywhere
  else (Home page also lists five).
- **description**: The count was correct before `VarianceController` became the default (decision
  58) and was not swept. Both instances sit in one paragraph, and the second ("these four methods")
  is the sentence a reader uses to decide which strategies share one implementation.

## 3. A fixed-injection forcing: does `k` ring, or random-walk with nothing to return it?

- **type**: physics · **severity**: major · **confidence**: medium
- **locations**:
  - PAGE: api / Forcing, `VarianceController` — "the variance random-walks with nothing to return
    it — which is what the rate-clamping forcings do"
  - PAGE: api / Observables, module — "a fixed-injection forcing makes it ring"
  - PAGE: api / Forcing, `ConstantPower` — "`injection_rate` is the value $\varepsilon$ relaxes to
    in the stationary mean"
- **contradicts**: whether a rate-holding forcing leaves `k` unrestored (a random walk) or restored
  and oscillatory (ringing / relaxing).
- **description**: With injection held at `P`, `dk/dt = P − ε(k)` has a single attracting
  equilibrium reached through the cascade — that is exactly the "ring" and "relaxes to" the other
  two surfaces describe. "Every `k` an equilibrium, nothing to return it" is true of the *marginal*
  law `A = ε/2k_f` alone, which no shipped strategy uses; attributing it to "the rate-clamping
  forcings" reads as a claim about `ConstantPower` and mis-states its physics.
- **resolution_hint**: keep the marginal-law sentence, and name what actually has no restoring
  term (the bare `ε`-matching rate) rather than the shipped fixed-injection strategy.

## 4. The large-eddy turnover time is defined two ways (a factor 3/2 apart)

- **type**: contradiction · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / Forcing, `VarianceController` — "the large-eddy turnover time $t_\ell$. When
    omitted it is taken as $2k_\infty/3\varepsilon_\infty$"
  - PAGE: api / SimulationRun, `StationarityCriterion` — "the eddy-turnover clock
    $\Delta t \varepsilon/k$"
  - PAGE: observables_cache, §1.3 — "a budget in turnovers … accumulates $\Delta t \varepsilon/k$"
- **contradicts**: the eddy-turnover time is `k/ε` on the run-layer surfaces and `2k/(3ε) = u'²/ε`
  in the controller, under one name.
- **description**: Both are conventional, but the docs bind one name to two numbers, and the two
  meet in practice: `min_turnovers`/`window_turnovers` are counted on the `k/ε` clock while the
  controller's settling time `t_ℓ/G` is set on the `u'²/ε` one, so a user comparing "5 turnovers of
  warm-up" with "settling time `t_ℓ`" is off by 1.5×.
- **resolution_hint**: state the convention once in `notation.md` and have the other say
  "= 2k/3ε, i.e. u'²/ε, not the k/ε clock" if the difference is deliberate.

## 5. Pope's `ℓ₁₁ = 0.43 ℓ₀` implies `C_ε ≈ 0.79`, against the package's own plateau of 0.5

- **type**: physics · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: api / phenomenology / Spectra, `large_scale_length` — "at Pope's high-Reynolds-number
    $\ell_{11} = 0.43\,\ell_{0}$"
  - PAGE: api / phenomenology / Scalings, `Sreenivasan1998` — "`asymptote = 0.5`" … "a constant of
    order $0.5$"
  - PAGE: api / phenomenology / Scalings, `Li2008` — "whose high-Reynolds-number plateau
    $C_\varepsilon \approx 0.5$"
- **contradicts**: the value of the normalized dissipation constant — 0.5 in two places, and 0.79
  implied by the same docstring's own identity `ℓ₁₁/ℓ₀ = C_ε (2/3)^{3/2}` at `0.43`.
- **description**: The identity is correct and so are both quoted numbers in their own sources, but
  the page uses them side by side ("at $C_\varepsilon = 0.5$ … and at Pope's … $0.43$") without
  saying that the second *is* a third value of the first constant. A reader taking `Sreenivasan1998`
  as the package's `C_ε` and Pope's `0.43` as its high-Re limit gets two incompatible numbers.
- **resolution_hint**: add "(i.e. `C_ε ≈ 0.79` in this identity)" to the `0.43` clause.

## 6. `1/(D κ_min²)` is a box-scale diffusive bound, not a "resolution bound"

- **type**: dimensional · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: api / SimulationRun, `Simulation` `max_dt` — "a resolution bound $1/(D\kappa_{\min}^{2})$
    built from the run's own diffusivity and box"
  - PAGE: api / SimulationRun, `advance!` — "the resolution bound the box and its diffusivity impose"
  - PAGE: api / SimulationDomain, `max_wavenumber` — "the resolution criterion
    $\kappa_{\max}\eta$"
- **contradicts**: "resolution" denotes the *smallest* resolved scale (`κ_max η`) everywhere else,
  while this bound is built from `κ_min = 2π/L`, the largest scale.
- **description**: The formula matches its stated job — `exp(−Dκ²Δt)` annihilates even the gravest
  mode once `Δt ≳ 1/(Dκ_min²)`, which is what stops a decaying run's step from running away — but
  that is a *box-scale* (largest-eddy diffusive) bound. Naming it "resolution" invites the reader to
  type it as a grid-scale constraint and to expect `κ_max` in it.
- **resolution_hint**: call it the box-scale diffusive bound (or "gravest-mode bound").

## 7. The longitudinal integral scale wears two glyphs, `L₁₁` and `ℓ₁₁`

- **type**: notation · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: notation, Derived scales — "$L_{11}$ | longitudinal (parallel) integral length scale"
  - PAGE: notation, Derived scales — "$\ell$ | the length a large-scale roll-off is evaluated
    against ($\ell_{11}$, or Pope's $\ell_0$…)"
  - PAGE: api / phenomenology / Spectra, `large_scale_length` — "The default is the longitudinal
    integral scale $L_{11}$" … "related by $\ell_{11}/\ell_{0}$"
- **contradicts**: one concept, two symbols — inside a single docstring, and inside a single
  glossary table whose whole job is one-symbol-one-concept.
- **resolution_hint**: keep `L₁₁` for the scale and reserve `ℓ` for "whatever length this roll-off
  was fitted against", writing `ℓ = L₁₁` where they coincide.

## 8. The glossary gives `E_φ(κ)` no code object, though `spectrum` evaluates it

- **type**: api-gap · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: notation, Diagnostics — "$E_\varphi(\kappa)$ | the scalar-variance spectrum … | —"
  - PAGE: api / phenomenology / Phenomenology, `spectrum` — "or the scalar spectrum
    $E_\varphi(\kappa)$ for a `ScalarSpectrum`"
- **contradicts**: the same table binds `E(κ)` to `spectrum` and leaves `E_φ(κ)` unbound, although
  one generic serves both and `ObukhovCorrsin1949` is shipped.
- **description**: The dash reads as "not built"; `random_scalar_spectral!`'s `initial_spectrum`
  keyword also takes a `κ ↦ E_φ(κ)` target, so the symbol has two live code homes.

## 9. The cache's "formed mid-step and discarded" case names only `k`; the default forcing also forms `ε`

- **type**: contradiction · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: observables_cache, §1.2 — "This test is where $\varepsilon$ and $k$ fall out … no
    component of the iteration performs that reduction"
  - PAGE: observables_cache, §2.4 table — "(a constant-energy forcing forms $k$ mid-step and
    discards it)"
  - PAGE: architecture, §7 — "$\langle f, \lvert\boldsymbol{\kappa}\rvert^{2} f\rangle$ for the
    dissipation it replaces" (three per-stage reductions in the default run)
- **contradicts**: whether an iteration's components ever form `ε`. §7 says the default controller
  reduces for `ε` at every stage; the cache page's counterexample paragraph names only `k`.
- **description**: The conclusion (`ε` is not cached) survives — the stage value fails the survival
  test, exactly as `k` does — but the stated *reason* ("no component performs that reduction") is
  false for the default configuration, and the qualification that rescues it is written for `k`
  alone. `add_forcing_source!`'s "three per stage for `VarianceController`" is the third witness.
- **resolution_hint**: extend the counterexample sentence to `ε` and the band variance.

## 10. `VarianceController` is the only strategy with no `domain`-taking form, and is absent from the deferred list

- **type**: api-gap · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: api / Forcing, `VarianceController` — "`VarianceController(; target, gain = 1, …)`" (no
    `domain`), with a "`band` — the band-pass kernel, lazy" field
  - PAGE: api / Forcing, `DeferredForcing` — the operator-free list gives only `Linear`,
    `ConstantPower`, `VarianceRescaling`
- **contradicts**: the module's stated two-form construction convention — every other band forcing
  has a `domain`-taking constructor plus an operator-free twin returning a `DeferredForcing`.
- **description**: `ConstantPower`'s band kernel is documented as lazy too, yet it still takes
  `domain`; the reader cannot tell whether `VarianceController(; target = 1.5)` yields a concrete
  forcing or a `DeferredForcing`, which matters because it is the front door's default and because
  `FlowConditions` accepts either kind.
- **resolution_hint**: state in the docstring why this one needs no domain, and say which kind of
  object it returns.

## 11. The `ObservablesCache` signature omits `history_depth`, which its own Arguments document

- **type**: format · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / Cache, `ObservablesCache` — "`ObservablesCache(domain; scalar = false,
    particle_velocities = nothing)`"
  - same docstring, Arguments — "`history_depth = 1` — how many Lagrangian samples the run must be
    able to look back over"
- **contradicts**: the shown constructor against its own argument list; the `Fields` section then
  documents `particle_velocity_history`, `sample_steps` and `history_filled`, which only exist
  because of that keyword.
- **description**: The Cache page's §3.1 example also builds a cache without it. A reader wiring an
  `AdamsBashforth` run by hand has no way to size the history from the signature.

## 12. Two measured `CatmullRom` trajectory floors that cannot both hold under the stated `Δx^{d+1}` law

- **type**: physics · **severity**: minor · **confidence**: low
- **locations**:
  - PAGE: decisions, (2026-08) second trajectory scheme — "`CatmullRom` ($C^1$, degree 2) floors at
    $1.2\times10^{-5}$" (frozen ABC flow at $64^3$)
  - PAGE: api / Particles, `EndpointHeun` — "at $N = 128$, floor $1\times10^{-5}$ against time
    error $6\times10^{-5}$"
- **contradicts**: the same interpolant's error floor, quoted at essentially the same value for two
  grids a factor of two apart, while the surrounding text asserts the floor "falls as
  $\Delta x^{d+1}$" (a factor 8 between them).
- **description**: The two experiments differ (frozen ABC flow vs "a band-limited field"), so this
  need not be an error — but as rendered the reader sees one quantity, two grids, one number, and a
  scaling law the pair violates.
- **resolution_hint**: name the test field beside each number, or quote both at one `N`.

## 13. `E_φ(κ)` is described as "summing", though it is a density like `E(κ)`

- **type**: dimensional · **severity**: nit · **confidence**: medium
- **locations**:
  - PAGE: notation, Diagnostics — "$E_\varphi(\kappa)$ | the scalar-variance spectrum, summing to
    $\langle\varphi^{2}\rangle$"
  - PAGE: notation, Diagnostics — "$E(\kappa)$ | … as a density per unit wavenumber … $k =
    \int_0^\infty E(\kappa)\,\mathrm{d}\kappa$"; "$E_n$ … so $k = \sum_n E_n$"
- **description**: The table's own discriminator is that a density integrates and a shell set sums —
  the distinction the package elsewhere treats as a category error worth a whole guard. `E_φ(κ)`
  carries a continuous argument and is evaluated by `spectrum`, so it integrates; "summing" types it
  as the measured `E_n` kind.
