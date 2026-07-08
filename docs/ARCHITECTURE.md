# Architecture

This is the design document for `GBGIsotropicTurbulence` — what the package is, how it is
organised, and *why* it is shaped the way it is. It is the spec: read it before any structural
change, and do not re-litigate a recorded decision (§11) without the user. `CLAUDE.md` is the
terse working copy and defers here; the rendered symbol glossary is
[`docs/src/notation.md`](notation.md).

The document is self-contained — every symbol, mathematical or `code`, is introduced in plain
language at first use — and reads top to bottom. Mathematics is written in the notation of the
glossary (Pope's turbulence conventions: the wavenumber vector is ``\boldsymbol{\kappa}`` with magnitude
``\kappa``; the turbulent kinetic energy is ``k``; the scalar diffusivity is ``\varkappa``; the integrating factor is
``\mathcal E``).

---

## 1. Identity

> `GBGIsotropicTurbulence` **is** a small, focused pseudospectral direct numerical simulation (DNS)
> of homogeneous isotropic turbulence: one incompressible velocity field ``\boldsymbol u`` and one
> passive scalar ``\varphi`` on a triple-periodic box, advanced by interchangeable
> integrating-factor time-stepping, with Lagrangian particle probes and Eulerian + Lagrangian
> statistics. It is a **library of composable pieces with a thin ergonomic run layer on top**, built
> as a *consumer* of [`GBGPeriodicFields`](https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl)
> (the field/spectral machinery) and
> [`GBGStreamingStatistics`](https://github.com/GrigorySarnitsky/GBGStreamingStatistics.jl) (the
> statistics).
>
> It **is not** a general PDE or CFD framework, and not multi-physics: the physics is a **thin,
> fixed core** — Navier–Stokes plus one passive scalar, no chemistry, phases, or processes. It is
> **not dimensional** — control is by Reynolds and Schmidt number, never units. It is **not** a field
> library (that is `GBGPeriodicFields`) or a statistics library (that is `GBGStreamingStatistics`),
> and it is **not** built on a grand theory or a lattice of speculative extension points.

The package inverts the richness of its sibling consumer `GBGCloudPhysics`: where Cloud has a rich
constitutive physics over a thin numerical core, `GBGIsotropicTurbulence` has a **thin fixed physics
over rich, interchangeable numerics and statistics**. That inversion is the single fact that explains
most of what follows.

---

## 2. Running a simulation

The primary measure of this library's quality is how easily one sets up and runs a case — including
**warm-up** to a statistically stationary state before any measurement. So the headline interface is
a thin run layer that assembles the machinery with sensible defaults and owns the time loop:

```julia
using GBGIsotropicTurbulence

# Assemble a forced case. Everything the run needs — the domain, workspace, physics,
# integrator, state, and initial condition — is built with defaults from a few numbers.
sim = Simulation(grid_points_per_axis = 128, viscosity = 5e-3;
                 velocity_forcing = ConstantPower(power = 0.1),
                 scalar = true, schmidt = 1.0)

# Spin past the transient: advance until the running dissipation ε(t) stops drifting
# (k(t) is deliberately not used — a constant-energy forcing would clamp it flat).
warmup!(sim)

# Advance and measure. The callback fires on a fixed interval with the current state.
run!(sim; turnovers = 20, every = 0.1) do s
    accumulate_statistics!(my_stats, s)
end
```

The run layer holds the pieces of §4 in one `Simulation` value, chooses a stable timestep each step
from the advective CFL condition (§4.4), refreshes the cached start-of-step fields the integrator
needs, and defines **warm-up as a first-class verb**: by default `warmup!` advances until the running
dissipation ``\varepsilon(t)`` stops drifting *and* the velocity-derivative skewness ``S(t)`` has
plateaued — the decisive "real turbulence yet" gate, since ``S`` runs from ``0`` (a random-phase field)
toward ``\approx -0.5`` — and, when the scalar is forced, until ``\langle\varphi^2\rangle`` does too,
since the scalar reaches stationarity *after* the velocity; or a fixed turnover/time/step budget if one
is passed. It reads ``\varepsilon`` (the small scales, which settle last), not the kinetic energy, which
a constant-energy forcing clamps flat. A forced flow
must reach statistical stationarity before a structure function or a PDF taken over it is meaningful.

The composable pieces stay fully exposed — a study that needs to run the loop by hand, swap a
stage, or interleave a bespoke measurement drops straight to §4.1–§4.5. The run layer is a
convenience over that machinery, never a wall in front of it.

> **Status.** The run layer is implemented (module `SimulationRun`) and covered by tests; the example above
> runs as written — a forcing can be named operator-free (`ConstantPower(power = 0.1)`, a `ForcingSpec`)
> and `warmup!` detects stationarity. The API may still evolve — setup ergonomics is the package's
> primary quality target — but it is no longer a sketch.

---

## 3. The organising frame: specification × realization

A run is fixed by two independent things: **what** continuous problem you pose, and **how** you
realise it numerically.

**Specification — what you solve.** Two parts:

- The **System**: the flow scenario — forced homogeneous isotropic turbulence, freely decaying
  turbulence, uniform-mean-gradient scalar mixing, and (a deferred frame, §7) homogeneous shear. A
  System is a choice of forcing, initial condition, and the dimensionless parameters ``\mathrm{Re}``,
  ``\mathrm{Sc}``.
- The **Model**: the level of description. This is a *rung on a ladder of projections* — DNS resolves
  every active scale; a large-eddy Model (LES) resolves the large scales and models the rest; a
  filtered-density-function or moment Model carries statistics rather than fields. Today only the
  finest rung, DNS, is realised (§7).

**Realization — how you compute it.** The **Method**: the numerics. A Method has two layers that
behave differently, so the package keeps them distinct:

- A **Model-fibered family** — the choices that only make sense *for a given Model*: the time
  integrator and its dealiasing for a field Model (§4.4), or the particle pushers and mixing model a
  statistical Model would need. These are set by the Model.
- **Model-agnostic axes** — precision, memory footprint, and compute backend (§6), which cut across
  every Model uniformly.

Two research disciplines live on these two kinds of variation, and naming them apart is the reason
the frame is *specification × realization* and not three co-equal axes:

- **Method-independence.** Vary the realization, hold the specification fixed, and the answer must not
  change (to discretisation error). Two integrators, two precisions, or two resolutions of the *same*
  DNS must agree. Agreement is the correctness signal; the cheapest realization that still agrees is a
  research finding, not merely a default.
- **Statistical commutation.** Descend the Model ladder, hold the System fixed, and the coarse Model
  must reproduce the fine Model's *statistics*. Filtered DNS versus LES of the same flow is the test;
  it is a match in distribution, never pathwise (§8, Lenses). This is the closure question made
  operational.

Both disciplines are the *same comparison machine* — run a configuration against a reference and
check chosen physical functionals (spectra, fluxes, conserved quantities, a target statistic) within
tolerance — pointed at different axes. The functionals are exactly the observables of §4.2.

---

## 4. Modules and types

Each concern is its own module, included in dependency order by the umbrella
`src/GBGIsotropicTurbulence.jl`. The types are motivated below by their *job*, not by theory.

### 4.1 `SimulationState` — the machinery and the buffers

- **`SimulationDomain`** is the reusable, read-only machinery for a cubic run: the `Grid3D`, the real–Fourier layout, the
  real-to-complex transform plans (one for the velocity, one for ``\varphi``, one for the rank-2 strain
  tensor of the skewness diagnostic), the spectral
  multipliers, the squared-wavenumber array ``\lvert\boldsymbol{\kappa}\rvert^2`` (the symbol of ``-\nabla^2``),
  and the de-alias kernel built by the run's pluggable de-aliasing strategy (the sharp ``2/3`` rule by
  default, or the smooth Hou–Li filter). It is the concrete realisation of the flow's *frame* — today a
  fixed periodic box (a sheared frame is deferred, §7). **Precision and backend enter here and flow
  everywhere from here**: `scalar_type` fixes the real element type (``\texttt{Float32}`` or
  ``\texttt{Float64}``) and `array_type` the storage (`Array`, `CuArray`, `ROCArray`); every buffer is
  allocated `similar` to this machinery, so a run is CPU/GPU-agnostic and single-precision or double
  by construction.
- **`Workspace`** preallocates *all* field-sized scratch a coupled velocity + scalar step writes into
  — the spectral vorticity, the Runge–Kutta stage registers and predictor, the physical
  velocity/vorticity/Lamb-vector buffers, the shared integrating factor, and the per-mode linear
  forcing rates. It is sized so that **a step allocates no field-sized memory** (§9, invariant 4).
- **Initial conditions** — `random_solenoidal_velocity!` fills a divergence-free velocity with a
  large-scale spectral envelope, rescaled to a target ``k``; `random_scalar!` fills a mean-zero
  ``\varphi`` to a target variance. These seed the state a run warms up from.

### 4.2 `Dynamics` and `Observables` — the flow's evolution and its observables

Two modules, named from the Mori–Zwanzig lens (§8): **`Dynamics`** is the generator of the evolution
— the right-hand side the integrators advance — and **`Observables`** are the functions of that state
that are measured. This is the naming rule the whole package follows: *physics concerns take their
names from the central lens; realization and infrastructure concerns are named by their job* (hence
`TimeIntegration`, `Forcing`, `SimulationState`, `SimulationRun`).

**`Dynamics`.** The incompressible momentum equation is advanced in **rotational (Lamb-vector) form**. Writing the
convective term through the identity
``(\boldsymbol u\cdot\nabla)\boldsymbol u = \nabla(\tfrac12\lvert\boldsymbol u\rvert^2) - \boldsymbol u\times\boldsymbol\omega``
(with vorticity ``\boldsymbol\omega = \nabla\times\boldsymbol u``) and letting the Leray–Helmholtz
projection ``\mathbb P`` onto divergence-free fields absorb the pressure and the kinetic-energy
gradient, the equation becomes

```math
\partial_t\boldsymbol u = \mathbb P\,(\boldsymbol u\times\boldsymbol\omega) + \nu\nabla^2\boldsymbol u + \boldsymbol f .
```

- **`velocity_vorticity!`** and **`velocity_nonlinear!`** assemble ``\mathbb P\,(\boldsymbol u\times\boldsymbol\omega)``,
  dealiased by the ``2/3`` rule to remove the aliasing of the quadratic product (the pseudospectral
  method; Orszag & Patterson 1972, the ``2/3`` rule Orszag 1971). The rotational form
  is chosen because it is the cheap, energy-conserving way to compute the advection spectrally, and —
  read through the geometric lens (§8) — it is the flow's *reversible* generator.
- **`integrating_factor!`** builds the exact diffusive factor
  ``\mathcal E(\boldsymbol{\kappa}) = \exp\!\big((A(\boldsymbol{\kappa}) - D\lvert\boldsymbol{\kappa}\rvert^2)\,\Delta t\big)``, with
  diffusivity ``D = \nu`` for the velocity and ``D = \nu/\mathrm{Sc}`` for the scalar, and an optional
  per-mode linear forcing rate ``A(\boldsymbol{\kappa})`` folded in. Multiplying a field by ``\mathcal E``
  advances its viscous/diffusive part *exactly*, with no stability restriction. This is the flow's
  *irreversible* generator; keeping it exact is what the integrating-factor split buys.
- **`scalar_to_physical!`** transforms ``\hat\varphi`` to the physical ``\varphi`` at each stage — the
  scalar analogue of the velocity-side transform folded into `velocity_vorticity!`.
- **`scalar_nonlinear!`** assembles the passive-scalar advection in conservative form
  ``-\nabla\cdot(\boldsymbol u\varphi)`` (equal to ``-\boldsymbol u\cdot\nabla\varphi`` since
  ``\nabla\cdot\boldsymbol u = 0``); the conservative form is used because, with the ``2/3`` rule, it
  conserves the scalar mean exactly.
- **`Observables`** (the measured functions of the state) — `kinetic_energy` ``k = \tfrac12\langle\lvert\boldsymbol u\rvert^2\rangle``,
  `dissipation` ``\varepsilon = \nu\langle\lvert\boldsymbol\omega\rvert^2\rangle``, `max_speed` (for the
  CFL), `scalar_variance` ``\langle\varphi^2\rangle``, `scalar_dissipation`
  ``\varepsilon_\varphi = 2\varkappa\langle\lvert\nabla\varphi\rvert^2\rangle``, and `derivative_skewness` (the K41 marker
  ``S \approx -0.5`` of developed turbulence, computed coordinate-free as ``3C\langle\det\boldsymbol{S}\rangle/\langle\boldsymbol{S}:\boldsymbol{S}\rangle^{3/2}`` with the exact isotropy constant ``C = \tfrac47\sqrt{15/2}``, which reproduces the classical longitudinal skewness). These are not incidental: they are the
  **fitness functionals** the comparison machine of §3 evaluates, and the stationarity signals
  `warmup!` watches.

### 4.3 `Forcing` — energy injection as a strategy

`AbstractForcing` is the supertype of the injection strategies, hooking into the step through a small
protocol whose four methods all default to doing nothing:

- `forcing_rate!` — for a forcing *linear* in the field (``\boldsymbol f = A\,\boldsymbol u``): fill the
  per-mode rate ``A(\boldsymbol{\kappa})``, folded into the integrating factor (exact, order-preserving).
- `apply_forcing!` — a post-step projection or rescale.
- `prepare_forcing!` — advance internal state once per step (a stochastic process).
- `forcing_source!` — add an additive source at each Runge–Kutta stage.

`NoForcing` (free decay), `BandRescaling` (hold a band's *or* the total energy fixed), `Linear` and `ConstantPower`
(negative-damping, folded into ``\mathcal E``), and `StochasticOU` (the Eswaran–Pope
Ornstein–Uhlenbeck forcing) are provided. **One implementation serves both** the velocity (a vector
field) and ``\varphi`` (a scalar), because the hooks are written through tensor-order-generic field
operators — the only field-specific step is the solenoidal (Leray) projection, applied to the velocity
alone. Each forcing has an operator-taking constructor and an operator-free keyword form
(`ConstantPower(power = 0.1)`) that returns a `ForcingSpec`, materialised when `Simulation` builds the
operators. This protocol is the System axis's realisation, and the one deliberately designed-in
extension point.

### 4.4 `TimeIntegration` — the Method for the field evolution

- **`Physics`** bundles the problem parameters the step consumes: the viscosity ``\nu``, the Schmidt
  number ``\mathrm{Sc}`` (scalar diffusivity ``\varkappa = \nu/\mathrm{Sc}``), and the two forcings.
- **`AbstractIntegrator`** is the family of integrating-factor schemes dispatched by **`step!`**, which
  advances the velocity ``\hat{\boldsymbol u}`` and scalar ``\hat\varphi`` **together** through the same
  Runge–Kutta stages. Coupled stepping is deliberate: the scalar is passive, so time-accuracy needs
  both nonlinear terms evaluated at each stage's state; advancing the velocity fully and the scalar
  afterwards would drop the substage velocities and degrade the coupling to first order.
- **`IFLowStorageRK3`** (the Williamson 2N / RKW3 workhorse) is third-order and stable on the
  imaginary axis; **`IFRK2`** (Heun) is a cheaper two-stage option that is imaginary-axis unstable and
  relies on viscous damping. `recommended_cfl` gives each scheme its conservative advective-CFL
  ceiling ``C`` (for ``\Delta t = C\,\Delta x/\max_i\lvert u_i\rvert``); the run layer uses it with
  `max_speed` to choose ``\Delta t``. The integrator is the Model-fibered part of the Method (§3).

### 4.5 `Particles` — instruments, with first-class numerics

Particles are **instruments** — probes of the turbulence — not a second physics. A particle is a
state-carrying trajectory object: today a tracer (position ``\boldsymbol x``); the deferred ladder is
inertial (``\boldsymbol x, \boldsymbol v``) and oriented (``\boldsymbol x, \boldsymbol v, \boldsymbol L``) probes (§7).
`Tracers` holds positions and a pluggable interpolation scheme; `advect!` pushes them Heun-in-time on
the velocity at the start and end of the step (the fields the solver already produces); `sample!`
reads any field along the trajectories for Lagrangian statistics.

Their **numerics are first-class**, on the same footing as the field integrators. Two axes matter: the
trajectory integrator — today a single second-order Heun push, with higher-order pushers the studied
future axis — and the fitness-tested sampling-consistency axis, the interpolation
scheme's order relative to the field's spectral accuracy (`CatmullRom` by default, higher-order
`LalescuSpline`/`LagrangeSpline` available). When the inertial and oriented probes arrive, the
integrating-factor split carries over for the *translational* stiff drag (field viscosity and a
particle's linear/matrix drag are the same linear-exact move), while **orientation dynamics on the
rotation group is a distinct geometric integrator** — the reversible generator of §8 — so the split
does not naively unify all of it.

### 4.6 The run layer (`SimulationRun`) — the front door

A `Simulation` value bundles the state a case advances: the `SimulationDomain`, the `Workspace`, the
`Physics`, the chosen `AbstractIntegrator`, the spectral fields ``\hat{\boldsymbol u}`` and
``\hat\varphi``, any `Tracers`, a stored CFL ceiling and the tracer-velocity buffer for the Heun
push, and a clock. Over it:

- **`Simulation(...)`** — the assemble-with-defaults constructor: from a resolution, a viscosity, and
  a forcing it builds every piece of §4.1–§4.5, seeds a divergence-free initial condition, and picks
  the default integrator. Setup is a few numbers.
- **`advance!(sim; dt)`** / **`run!(sim; ...)`** — own the time loop: choose ``\Delta t`` from the
  scheme's CFL and the current `max_speed`, refresh the cached start-of-step velocity and vorticity,
  `step!`, advect tracers, and fire a user callback on a fixed time interval.
- **`warmup!(sim; ...)`** — advance to statistical stationarity: by default until the running
  dissipation ``\varepsilon(t)`` and the velocity-derivative skewness ``S(t)`` have both plateaued (a
  trailing-window flatness test) — reading ``\varepsilon`` (not the clampable ``k(t)``) and ``S`` (the
  strict "real turbulence" gate) — and, when the scalar is forced, until ``\langle\varphi^2\rangle``
  does too; or a fixed turnover/time/step budget if one is given.
- **`current_time(sim)`** / **`current_step(sim)`**, and `kinetic_energy(sim)` / `dissipation(sim)` /
  `scalar_variance(sim)` — the clock and the current-state diagnostics, for a callback to read.

The layer wires §4.1–§4.5 together; it holds no physics or numerics of its own.

### 4.7 `Phenomenology` — the reference laws (extraction-bound)

`Phenomenology` is the library of **reference turbulence phenomenology**: the fitted scalings, model
spectra, structure-function laws, and dimensionless constants that theory and experiment have
established. It is the **symmetric counterpart to `Observables`** — those are the *measured* functions of
the DNS state, these are the *predicted* values of the same functions. The DNS measures, the laws
predict, and the comparison machine of §3 sets them side by side. Two properties follow, both instances
of the charter *investigate the physics, do not assume it*:

- **A provider, not a comparer.** A law evaluates itself from the flow parameters; it knows nothing of
  the DNS. The comparison lives consumer-side (the validation layer), which reads both.
- **No parametrization is privileged.** A published fit and one of our own are the same kind of object —
  subtypes of one law family, discovered and validated alike, never baked in as truth.

**The abstraction is the strategy pattern** already used for `AbstractForcing` / `AbstractIntegrator` /
`DealiasingStrategy`: **a law family is an abstract type, each parametrization a concrete subtype**
carrying its fitted coefficients and provenance, implementing one small interface — evaluate the law at
its argument (``\kappa``, ``r``, ``\mathrm{Re}_\lambda``) given a `FlowParameters` bundle; report its
`provenance` (the citation and validity range); and eventually `fit` itself to data. Choosing a law is
choosing the subtype (`Pope2000` versus `VonKarman1948`) and optionally overriding its coefficients
(`Pope2000(; C_K = 1.6)`, the published fit being the default). Provenance is first-class — the
comparison needs a law's validity range to be fair, and it is the single source of the citation.

**Naming is a three-level handle**, because one author publishes many models across years and
quantities: the **quantity is the submodule** (`Spectra.Pope…` versus `StructureFunctions.Pope…`), the
**paper is the author-year type** (`Pope2000`, first author's surname, the full list in `provenance`),
and a **same author-year-quantity collision takes a trailing letter** (`Pope2014a`, `Pope2014b`). The
validating case is Kolmogorov 1941, in two submodules at once — `Spectra.Kolmogorov1941` (the ``-5/3``
spectrum) and `StructureFunctions.Kolmogorov1941` (the 2/3 and 4/5 laws) — separated by the submodule
alone. The full handle `Phenomenology.Spectra.Pope2000` reads like a citation and is unique by
construction.

**Submodules are cut by representation, so they stay few** while the models multiply as subtypes:

- **`Spectra`** — functions of ``\kappa`` (velocity ``E(\kappa)``, scalar ``E_\varphi(\kappa)``),
  **composed**: an inertial core ``C_K\,\varepsilon^{2/3}\kappa^{-5/3}`` times a swappable large-scale
  factor ``f_L(\kappa L)`` and dissipation-range factor ``f_\eta(\kappa\eta)``, a named type fixing a
  published triple.
- **`StructureFunctions`** — functions of ``r`` (the ``S_p(r)`` laws and the two-point correlations,
  which share the representation).
- **`Scalings`** — the dimensionless numbers and their ``\mathrm{Re}_\lambda`` trends (``C_K``, the
  dissipation constant ``C_\varepsilon``, the derivative skewness ``S``, the flatness, the
  Obukhov–Corrsin constant, the Lagrangian ``C_0``, the mechanical-to-scalar timescale ratio).

Three now — enough for the validation checklist — capping near six: `PDFs`, `Decay` (``k \sim t^{-n}``),
and `Lagrangian` are named future seams (§7), not owed. A single `FlowParameters` bundle carries every
dimensionless group a law might read (``\mathrm{Re}_\lambda``, ``\varepsilon``, ``\nu``, ``L``, ``u'``,
``\mathrm{Sc}``, ``\varepsilon_\varphi``), the derived scales (``\eta``, ``\tau_\eta``, ``k``,
``\lambda``) as helpers — the analogue of the `Physics` and `SimulationDomain` bundles.

The laws are **consumed to build runs**, not only compared against: an initial-condition or forcing
spectrum drawn from `Spectra`, and the reference curves the validation harness reads, all from one
library. And the loop closes — measure (this package and SS), `fit` a parametrization to the
measurement, and our fit lands beside the literature to be validated against the next run.

**Formula verification.** A transcribed law is checked not against a reference implementation — none is
authoritative, and cross-checking against another code merely moves the trust — but against the physical
relations it *must* satisfy: the asymptotic slopes (the ``\kappa^{-5/3}`` inertial range, the
low-wavenumber ``\kappa^\sigma``, the dissipation cutoff), the ``\zeta_3 = 1`` constraint on every
intermittency model, and the roll-off limits ``f_L, f_\eta \to 1``. This self-consistency battery lives
in the test suite and catches a wrong exponent, coefficient, or sign without trusting a second source.

**Extraction requirement (recorded).** `Phenomenology` is built inside this package for now but is
**designed to be cut into a standalone `GBGTurbulencePhenomenology` with no rewrite** — the demand-driven
path that extracted `GBGStreamingStatistics`. The requirement constrains the design. It is a
**dependency-light leaf**, depending on *neither* `GBGPeriodicFields` (a law is a scalar function, no
field math) *nor* `GBGStreamingStatistics` (it provides reference values, computes no statistics) *nor*
this package's dynamics — first in the include order, importing nothing turbulence-dynamical. And it is a
**self-contained namespace**: the umbrella does *not* re-export it (`using GBGIsotropicTurbulence` brings
the DNS API only; the laws are reached opt-in through `Phenomenology`), and its notation and API pages
form their own group, separable from the DNS surface. Extract when a second consumer appears; until then
the seam is real but uncrossed (decision 18).

### 4.8 Layout summary

`SimulationState → Dynamics → Observables → Forcing → TimeIntegration → Particles → SimulationRun`.
Cross-module access is through explicit `using ..Module: name` lists; `Phenomenology` (§4.7), once built,
leads this order as the dependency-light leaf the initial-condition, forcing, and validation consumers
read. Statistics live consumer-side of this package too: the sampling in `Particles` and the observables
in `Observables` produce the *samples*; a statistics bridge that feeds them to `GBGStreamingStatistics`
is deferred (§7).

---

## 5. The consumer boundary — what belongs here, and what does not

`GBGIsotropicTurbulence` owns the turbulence-specific glue and delegates everything domain-neutral.
The dividing line is **domain-neutrality**, not "thinness":

- **To `GBGPeriodicFields`** — every field operation: the transforms, `curl!`/`cross!`/`divergence!`,
  the Leray projection `helmholtz_projection!` (``\mathbb P``), `convolve!` and the dealias/band
  kernels, the reductions (`inner`, the radial spectrum and correlation), and grid↔point
  interpolation. The rule *everything diagonal in Fourier is a `GBGPeriodicFields` operator* is
  followed in the code.
- **To `GBGStreamingStatistics`** — every estimator: histograms, densities, conditional means and
  variances, conditional and transition densities.
- **Owned here** — the Navier–Stokes and scalar nonlinear assembly, the integrating factor, the
  forcing strategies, the coupled time-stepping, the particle tracking, the run layer, and the
  turbulence-specific spectral glue a backend must not carry (the deferred sheared frame's
  non-separable multipliers, §7).

Two standing rules follow:

1. **If a capability's true home is `GBGPeriodicFields` or `GBGStreamingStatistics`, raise it and
   extend it *there* — do not reimplement it here.** Only genuinely *domain-neutral* capability
   migrates out; a backend has an anti-accretion charter, so turbulence-specific glue stays here.
2. **A deferred-by-design future is not a missing feature** (§7).

---

## 6. Precision and footprint as studied axes

Precision and the memory-footprint/accuracy trade-off are **objects of study**, not fixed defaults —
the numerical counterpart of the charter that the tool investigates the physics rather than assuming
it (§8).

- **Both precisions are supported equally, with no privileged default.** ``\texttt{Float32}`` is the
  development and desktop precision; ``\texttt{Float64}`` is the production precision. The element type
  ``T`` flows from the field (§4.1): no kernel silently fixes the arithmetic. (The `Physics` scalar
  parameters are stored `Float64` and converted to ``T`` at use — a scalar convenience, not a field
  commitment.)
- **The footprint/accuracy trade-off is held at both ends** — low-storage integrators, the dealias
  fraction, truncation — and the working point is chosen by *direct fitness test*, never decreed.
  Which precision, order, or footprint suffices for a regime is a measured finding.
- **The fitness arbiter is the comparison machine of §3** — the same one that adjudicates
  method-independence and DNS-versus-LES statistical commutation. One machine ranges over
  ``\{`` model fidelity, integrator, precision, footprint, closure ``\}``; the *sufficiency frontier*
  (the cheapest realization that still passes) is a deliverable of the tool.

This is why the `GBGPeriodicFields` element-type genericity and GPU-first, allocation-free discipline
are load-bearing here: they are what make precision and backend free to vary. "Low footprint" is the
default working point on a studied axis, not a universal law.

---

## 7. Deliberately deferred

These are **named so they are not precluded, and deliberately left un-abstracted**: no extension
point or generalisation is built for them until a second concrete case forces the abstraction. None
is a gap.

- **Inertial and oriented particles** — ``(\boldsymbol x,\boldsymbol v)`` with matrix drag, then
  ``(\boldsymbol x,\boldsymbol v,\boldsymbol L)`` with torque. The translational drag reuses the
  integrating-factor split; orientation needs a geometric integrator (§4.5, §8).
- **The sheared frame (Rogallo).** A uniform mean velocity gradient makes the wavenumbers
  time-dependent (``d\boldsymbol{\kappa}/dt = -\boldsymbol{A}^{\!\top}\boldsymbol{\kappa}``) and non-separable. This is the one
  future with a concrete `GBGPeriodicFields` dependency: its separable per-axis multipliers cannot
  hold a sheared lattice, so it is a bounded extension *there* (rule 1 of §5), not a job here.
- **The Model ladder beyond DNS** — LES (filter the DNS, model the subgrid stress) and a
  filtered-density-function / statistical Model (§8). Each is a coarser rung, discriminated from DNS
  by statistical commutation; the canonical acceptance test is the relaxation of a two-mode scalar
  distribution (a micromixing benchmark).
- **The statistics bridge** — the sampling-to-`GBGStreamingStatistics` path (Eulerian field
  samples and Lagrangian trajectory samples in, streamed summaries out).

---

## 8. Lenses and prior art

The package makes real theory legible, but **nothing in the code is load-bearing on it** — the code
would be identical had these frameworks never been named. They organise *understanding* and set what
the tool is built to *investigate*, not assume. Mori–Zwanzig is the central lens; the others are read
through it.

- **Mori–Zwanzig — the central lens.** The DNS/LES/statistical ladder is one dynamics under a ladder
  of projections. Each Model is a projection ``\mathcal P`` of the full state plus a closure of the residual it
  discards; the exact projected dynamics carries a *memory* integral and a *noise* term, and every
  closure is an approximation of those. DNS is simply the finest projection, not a thing apart. This
  is what makes the Model axis a *ladder* (§3) rather than a list.
- **The commuting square — the modeling ideal.** With ``\Pi`` a coarse-graining and ``S`` a flow map,
  one would like ``\Pi\circ S_{\text{fine}} = S_{\text{coarse}}\circ\Pi``. It cannot hold pathwise:
  the coarse state does not determine its own tendency (that is the Mori–Zwanzig memory and noise made
  concrete), and turbulence is chaotic. The achievable ideal — and the design target of any Model —
  is **statistical** commutation, agreement of the distributions and fluxes on the attractor. This is
  exactly what the DNS-versus-LES comparison of §3 measures.
- **Geometric mechanics (GENERIC) — the reversible/irreversible split.** The integrating-factor
  method *is* a split into a reversible generator (the advection, computed in rotational form, §4.2)
  and an irreversible one (the diffusion, integrated exactly). The lens says *why* the split is
  structure-preserving and constrains closures to be net-dissipative.
- **Renormalisation / scale invariance — a hypothesis, never a foundation.** Small-scale universality
  is what makes closure constants transferable at all, but it is approximate (intermittency), it fails
  for scalar small scales (persistent gradient anisotropy), and the unclosed terms are *conditional*
  quantities that re-import the large scales. So the tool is built to *test* how universal a closure
  is, per regime — not to assume it. This is the general charter: **the architecture investigates the
  physics; it must not assume it** — the same discipline as the model-free statistics it consumes.

---

## 9. Invariants — the deliberate absences

The public surface and these absences are the spec. Do not add a capability "for completeness"; a
missing one usually encodes a decision.

1. **No units.** Control is by ``\mathrm{Re}`` (through ``\nu``) and ``\mathrm{Sc}``; every diagnostic
   is dimensionless.
2. **No field or statistics machinery reimplemented.** Field operations come from
   `GBGPeriodicFields`, estimators from `GBGStreamingStatistics` (§5).
3. **No privileged precision or backend.** ``T`` and the array type flow from the field; both
   precisions and CPU/GPU are first-class (§6).
4. **Allocation-free stepping.** A time step allocates no field-sized memory over the preallocated
   `Workspace` — load-bearing for GPU hot loops. (The one documented exception is `StochasticOU`
   forcing, whose random increment is drawn host-side each step — portability-first, not yet tuned.)
5. **GPU-first, single-node, backend-agnostic.** Shared-memory only; no distributed or multi-GPU
   scope (inherited from `GBGPeriodicFields`).
6. **No baked-in physical model, closure, or universality assumption.** The tool investigates these;
   it does not assume them (§8).
7. **A library, not a framework.** The run layer is a convenience over exposed pieces (§2, §4.6),
   never a mandatory shell.
8. **The scalar is ``\varphi``.** Never ``\theta`` — in code, mathematics, and prose.
9. **Deferred futures are accounted for, not owed** (§7); no speculative extension points.

---

## 10. Conventions

- **Docstrings are operator-first, then scheme.** State the continuous operator or PDE term and its
  exact/ideal form, *then* the discrete realisation — as `integrating_factor!` leads with
  ``\partial_t f = D\nabla^2 f`` before ``\mathcal E(\boldsymbol{\kappa})``, and `velocity_nonlinear!` with the
  Lamb-vector identity before the pseudospectral product. This is the turbulence analogue of the
  siblings' physical-form-first / estimand-first rules.
- **Two-tier docs.** `CLAUDE.md` is the terse working map and defers here; this document carries the
  rationale and the decision log. Mathematics is rendered LaTeX in the glossary's notation
  ([`docs/src/notation.md`](notation.md)); a code identifier is always in `backticks` and never
  inside a math span.
- **Verification is by numerical oracle, not a formalization ledger.** Because the package introduces
  no novel mathematical *objects* (they are `GBGPeriodicFields`' and `GBGStreamingStatistics`'), its
  nontrivial claims are *dynamical* — the exactness of ``\mathcal E``, the order of the integrator,
  imaginary-axis stability, mean conservation — and are pinned by numerical oracle tests (a
  Taylor–Green order study, unforced energy decay, exact diffusion). This is why the package follows
  the `GBGCloudPhysics` consumer pattern with **no `FORMALIZATION.md`**; a typed-statement ledger is a
  backend's need. Revisit only if a built Model rung introduces genuinely package-specific formalism.
- **Citations** follow author–year; the full references are §References. Never cite an inaccessible
  source; the material under `inspiration/` is private and never referenced.

---

## 11. Decision log

Append-only; each entry stands on its own. Dates in `YYYY-MM`.

1. **(2026-06) Integrating-factor split with exact diffusion.** The stiff viscous/diffusive part is
   integrated exactly by ``\mathcal E(\boldsymbol{\kappa})``; only the advection is explicit. Removes the
   diffusive stability limit and preserves scheme order under linear forcing.
2. **(2026-06) Rotational (Lamb-vector) form for the advection.** Cheap, energy-conserving spectral
   advection; the reversible generator of the geometric lens.
3. **(2026-06) `IFLowStorageRK3` (Williamson 2N / RKW3) is the default; per-scheme CFL.** Third-order,
   imaginary-axis stable, two registers per field; `IFRK2` kept as a cheaper, viscously-stabilised
   option.
4. **(2026-06) One passive scalar ``\varphi``, coupled in-stage.** Velocity and scalar advance through
   the same RK stages to keep the passive coupling time-accurate.
5. **(2026-06) Lagrangian tracers by Heun-in-time; interpolation scheme is the accuracy axis.** The
   pusher uses the start- and end-of-step velocities the solver already produces.
6. **(2026-07) Statistics extracted to `GBGStreamingStatistics`.** The conditional/transition-density
   machinery is domain-neutral and shared across turbulence, cloud microphysics, and molecular
   dynamics; it is consumed, not owned (§5).
7. **(2026-07) Organising frame is specification × realization, not three co-equal axes.** Method is
   fibered over Model; the two research disciplines (method-independence, statistical commutation) map
   onto the two kinds of variation (§3). *(Revised from an earlier "System × Model × Method" framing
   after an adversarial review.)*
8. **(2026-07) Mori–Zwanzig is the central lens, not a foundation.** The code does not depend on it;
   it organises understanding and is demonstrated, not assumed. The other lenses (GENERIC, the
   commuting square, RG) are read through it, and RG/universality is a hypothesis to test (§8).
9. **(2026-07) Precision and footprint are studied axes.** Both precisions supported equally, the
   working point chosen by fitness test; the sufficiency frontier is a deliverable (§6).
10. **(2026-07) Particles are instruments with first-class numerics.** The role is a probe; the
    trajectory integrator and sampling-consistency are fitness-tested Method work (§4.5).
11. **(2026-07) The run + warm-up layer is a first-class, present concern.** Ease of setup and running
    is the primary quality metric, so the ergonomic front door is built now, not deferred (§2, §4.6).
12. **(2026-07) Single `ARCHITECTURE.md` (consumer archetype) + `docs/src/notation.md`; no
    `FORMALIZATION.md`.** IT is an operator consumer; its claims are dynamical and pinned by tests
    (§10).
13. **(2026-07) `warmup!` detects stationarity on the dissipation ``\varepsilon`` and the
    velocity-derivative skewness, not the kinetic energy.** ``\varepsilon(t)`` (the small scales, which
    settle last) must stop drifting over a trailing window; ``k(t)`` is avoided because a constant-energy
    forcing clamps it and a fixed-injection forcing makes it ring. The skewness ``S(t)``
    (`derivative_skewness`) must also have plateaued with ``\lvert S\rvert`` above a floor — the strict
    "real turbulence yet" gate (``S`` runs from ``0`` toward ``\approx -0.5``). When the scalar is
    forced, ``\langle\varphi^2\rangle`` must flatten too — the scalar reaches stationarity after the
    velocity. A fixed turnover/time/step budget is the explicit alternative. *(Follows the DNS warm-up
    research review.)*
14. **(2026-07) Operator-free forcing construction via `ForcingSpec`.** `ConstantPower(power = 0.1)`
    (and the other banded forcings) return a `ForcingSpec` capturing the parameters, materialised into
    the concrete `AbstractForcing` once `Simulation` builds the domain — so a case names its forcing
    before the grid exists. The operator-taking constructor is unchanged.
15. **(2026-07) `BandRescaling` can hold the band *or* the total energy (`target = :band | :total`).**
    `:band` (default) fixes the forced band's energy and lets the total float; `:total` rescales the band
    to pin the whole-field energy — hence the r.m.s. velocity ``u'`` and ``\mathrm{Re}_\lambda`` — the
    constant-total-energy forcing convention. A modeling choice with two defensible answers, so it is a selectable
    option rather than a fixed default.
16. **(2026-07) Modules named from the Mori–Zwanzig lens; `Equations` split into `Dynamics` +
    `Observables`; `Driver` → `SimulationRun`.** Since MZ is the central lens (§8), the physics concerns
    take their names from it — the **dynamics** (the generator/RHS) and its **observables** (the measured
    functions of state) — rather than from production-DNS convention (`rhs`/`stats`) or generic software
    terms. `Equations` conflated the two and under-described; splitting it makes each concern its own
    module and its own name. Realization and infrastructure concerns keep job-names (`TimeIntegration`,
    `Forcing`, `SimulationState`, and the run layer `SimulationRun`, paired with `SimulationState`).
17. **(2026-07) Consume `GBGPeriodicFields`'s fused domain; the velocity-derivative skewness becomes a
    coordinate-free strain invariant.** Four fused operations were requested of, and shipped by, PF —
    `combine!` (axpby), `weighted_inner`, `symmetric_gradient`, `det` — and wired in. `combine!` replaces
    the hand-rolled RK/OU `field_data` broadcasts (charter invariant 2). `weighted_inner` fuses the
    per-step band energy in the forcings and expresses `scalar_dissipation` as the Dirichlet energy, with
    no ``\nabla\varphi`` materialized. And `derivative_skewness` becomes the normalized third invariant of
    the strain rate ``\boldsymbol{S}``, ``3C\langle\det\boldsymbol{S}\rangle/\langle\boldsymbol{S}:\boldsymbol{S}\rangle^{3/2}``,
    with the exact isotropy constant ``C = \tfrac{4}{7}\sqrt{15/2}\approx 1.5649`` reproducing the classical
    ``S\approx-0.5`` — the axis-picking longitudinal form was coordinate-dependent, the invariant is the
    honest object, and `symmetric_gradient` forms the strain without the full velocity-gradient tensor.
    The physical strain tensor is unavoidable (cubic ⇒ non-Parseval), so this diagnostic allocates its
    rank-2 buffers per call (sampling cadence) rather than keeping them resident — footprint over compute.
18. **(2026-07) `Phenomenology` — a reference-law library, author-year naming, extraction-bound.** A new
    submodule (§4.7) collecting the established turbulence phenomenology — model spectra, structure-function
    laws, dimensionless-constant fits — as one strategy family per quantity: each law family an abstract
    type, each parametrization an author-year subtype (`Spectra.Pope2000`), disambiguated on three axes
    (quantity → submodule, paper → author-year, same-year collision → a trailing letter). It is the
    predicted counterpart to `Observables` — a provider the validation layer reads, not a comparer — and
    holds our own fits beside the literature on equal footing. **Built inside this package but designed to
    be cut into a standalone `GBGTurbulencePhenomenology` with no rewrite** (the `GBGStreamingStatistics`
    precedent): a dependency-light leaf — no `GBGPeriodicFields`, `GBGStreamingStatistics`, or dynamics
    dependency — that the umbrella does *not* re-export, with its own doc and API group. Extract when a
    second consumer appears.
19. **(2026-07) The measured-vs-predicted validation harness — the first `Phenomenology` consumer.** The
    velocity energy spectrum is measured from a run (`energy_spectrum`, the halved `GBGPeriodicFields`
    radial spectrum) and the integral scale `integral_scale` from it; `flow_parameters` bridges a
    `Simulation` to a `Phenomenology` `FlowParameters` (``\nu``, ``\varepsilon``, ``u'``, ``L`` from the
    measured state), and `validate_spectrum(sim, model)` compares the measured spectrum against a model
    spectrum evaluated at that state, returning the relative L² discrepancy. This realizes the
    comparison-machine path of §3 for spectra — the measured half is a `GBGPeriodicFields` reduction, so
    no `GBGStreamingStatistics` bridge is needed for it. The structure-function and scaling-constant
    paths (via `radial_correlation` and the scalar diagnostics) share the shape and are deferred.
20. **(2026-07) Resolution-based `viscosity` — the run layer *consumes* a `Phenomenology` law to build a
    run.** `Simulation` now sets ``\nu`` from the grid by default (no `viscosity`): it reads the
    dissipation the box sustains from the box-normalized dissipation law `Scalings.Li2008`
    (``k/(L\varepsilon)^{2/3} \approx 0.9``, the dissipation anomaly in box variables, calibrated to
    JHTDB), then sets ``\nu`` so the resolution criterion ``\kappa_{\max}\eta`` equals the `k_max_η`
    option (default `2`) — the highest Reynolds number the grid resolves. This is the **construction**
    half of the consume-and-fit loop (§4.7): laws are read to *build* runs, not only to validate them.
    The run is forced-and-stationary by default (a `BandRescaling` holds the total energy at `energy`,
    default `1.5`, i.e. ``u'=1``); an explicit `viscosity` opts back into direct control. It does **not**
    breach the extraction boundary — `Li2008` stays a pure scalar law with no `GBGPeriodicFields` /
    `GBGStreamingStatistics` / dynamics dependency; only the run layer (never `Phenomenology`) knows both
    sides. The accuracy target is ``\kappa_{\max}\eta`` (spectral content at the highest *evolved*
    wavenumber), not ``\eta/\Delta x`` (geometric): the former is dealiasing-aware through
    ``\kappa_{\max} = f\,\tfrac N2\tfrac{2\pi}{L}`` ([`max_wavenumber`](@ref)), which is correct because
    accuracy itself depends on the dealiasing.

---

## References

Cited author–year above; full entries here. DOIs to be confirmed against the user's copies before the
docs are published (they are not yet filled in, per the no-guessed-citation rule).

- Kolmogorov, A. N. (1941). The local structure of turbulence in incompressible viscous fluid for very
  large Reynolds numbers. *Dokl. Akad. Nauk SSSR* **30**, 301–305.
- Betchov, R. (1956). An inequality concerning the production of vorticity in isotropic turbulence.
  *J. Fluid Mech.* **1**(5), 497–504. *(The isotropy relations behind the strain-skewness constant, §4.2.)*
- Orszag, S. A. & Patterson, G. S. (1972). Numerical simulation of three-dimensional homogeneous
  isotropic turbulence. *Phys. Rev. Lett.* **28**, 76–79. *(Pseudospectral method; the ``2/3``
  dealiasing rule, Orszag 1971.)*
- Rogallo, R. S. (1981). Numerical experiments in homogeneous turbulence. *NASA TM-81315.* *(The
  sheared-frame scheme, §7.)*
- Eswaran, V. & Pope, S. B. (1988). An examination of forcing in direct numerical simulations of
  turbulence. *Computers & Fluids* **16**, 257–278. *(The stochastic Ornstein–Uhlenbeck forcing.)*
- Lundgren, T. S. (2003). Linearly forced isotropic turbulence. *CTR Annual Research Briefs*, 461–473.
  *(The linear negative-damping forcing.)*
- Williamson, J. H. (1980). Low-storage Runge–Kutta schemes. *J. Comput. Phys.* **35**, 48–56. *(The
  2N low-storage family; the third-order RKW3 coefficients.)*
- Pope, S. B. (2000). *Turbulent Flows.* Cambridge University Press. *(Notation; the
  filtered-density-function Model and mixing models, §7–§8.)*
- Mori, H. (1965). Transport, collective motion, and Brownian motion. *Prog. Theor. Phys.* **33**,
  423–455; Zwanzig, R. (1973). Nonlinear generalized Langevin equations. *J. Stat. Phys.* **9**,
  215–220. *(The projection formalism, §8.)*
- Öttinger, H. C. (2005). *Beyond Equilibrium Thermodynamics.* Wiley. *(GENERIC; the
  reversible/irreversible split, §8.)*
