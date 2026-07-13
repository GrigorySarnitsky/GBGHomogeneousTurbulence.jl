# Architecture

This is the design document for `GBGIsotropicTurbulence` — what the package is, how it is organised,
and *why* it is shaped the way it is. It is the spec: read it before any structural change, and do not
re-litigate a recorded decision (§11) without the user. `CLAUDE.md` is the terse working copy and defers
here; the rendered symbol glossary is [`docs/src/notation.md`](notation.md).

The document is self-contained — every symbol, mathematical or `code`, is introduced in plain language at
first use — and reads top to bottom. Mathematics follows the glossary's notation: the wavenumber vector
is ``\boldsymbol{\kappa}`` with magnitude ``\kappa``; the turbulent kinetic energy is ``k``; the scalar
diffusivity is ``\varkappa``; the integrating factor is ``\mathcal E``. Pope (2000) is a standard
reference for turbulence notation (§References).

---

## 1. Identity

> `GBGIsotropicTurbulence` **is** a small, focused pseudospectral direct numerical simulation (DNS) of
> homogeneous isotropic turbulence: one incompressible velocity field ``\boldsymbol u`` and one passive
> scalar ``\varphi`` on a triple-periodic box, advanced by interchangeable integrating-factor
> time-stepping, with Lagrangian particle probes and Eulerian + Lagrangian statistics. It is a **library
> of composable pieces with a thin ergonomic run layer on top**, built as a *consumer* of
> [`GBGPeriodicFields`](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl) (the field and spectral
> machinery) and
> [`GBGStreamingStatistics`](https://grigorysarnitsky.github.io/GBGStreamingStatistics.jl) (the statistics).
>
> It **is not** a general PDE or CFD framework, and not multi-physics: the physics is a **thin, fixed
> core** — Navier–Stokes plus one passive scalar, no chemistry, phases, or processes. It is **not
> dimensional** — control is by Reynolds and Schmidt number, never units. It is **not** a field library
> (that is `GBGPeriodicFields`) or a statistics library (that is `GBGStreamingStatistics`), and it builds
> **no** speculative extension points — no generality ahead of a concrete need (§9).

The package inverts the richness of its sibling consumer
[`GBGCloudPhysics`](https://grigorysarnitsky.github.io/GBGCloudPhysics.jl): where Cloud carries a rich
constitutive physics over a thin numerical core, `GBGIsotropicTurbulence` carries a **thin fixed physics
over rich, interchangeable numerics and statistics**. That inversion is the single fact that explains most
of what follows.

---

## 2. Running a simulation

The primary measure of this library's quality is how easily one sets up and runs a case — including
**warm-up** to a statistically stationary state before any measurement. The headline interface is
therefore a thin run layer that assembles the machinery with sensible defaults and owns the time loop:

```julia
using GBGIsotropicTurbulence

# Assemble a forced case. Everything the run needs — the domain, buffers, physics,
# integrator, state, and initial condition — is built with defaults from a few numbers.
sim = Simulation(grid_points_per_axis = 128, viscosity = 5e-3;
                 velocity_forcing = ConstantPower(target = 0.1),
                 scalar = true, schmidt = 1.0)

# Spin past the transient: advance until the running dissipation ε(t) stops drifting
# (k(t) is deliberately not used — a constant-energy forcing would clamp it flat).
warmup!(sim)

# Advance and measure. The callback fires on a fixed interval with the current state.
run!(sim; turnovers = 20, every = 0.1) do s
    accumulate_statistics!(my_stats, s)
end
```

The run layer holds the pieces of §4 in one `Simulation` value, chooses a stable timestep each step from
the advective CFL condition (§4.5), refreshes the cached start-of-step fields the propagator needs, and
treats **warm-up as a first-class verb**. By default `warmup!` advances until the flow is statistically
stationary, watching the running dissipation ``\varepsilon(t)`` and the velocity-derivative skewness
``S(t)`` — the small-scale signals that settle last — rather than the kinetic energy a constant-energy
forcing clamps flat; a fixed turnover, time, or step budget is the explicit alternative, and §4.7 gives
the exact stopping test. A forced flow must reach statistical stationarity before a structure function or
a PDF taken over it means anything.

The composable pieces stay fully exposed: a study that needs to run the loop by hand, swap a stage, or
interleave a bespoke measurement drops straight to §4. The run layer is a convenience over that machinery,
never a wall in front of it.

> **Status.** The run layer is implemented (module `SimulationRun`) and covered by tests; the example
> above runs as written — a forcing can be named operator-free (`ConstantPower(target = 0.1)`, a
> `DeferredForcing`) and `warmup!` detects stationarity. The API may still evolve, since setup ergonomics is
> the package's primary quality target, but it is no longer a sketch.

---

## 3. The organising frame

A run is fixed by two independent things: **what** continuous problem you pose, and **how** you realise it
numerically. Beneath both lies a single organising idea.

### The foundation — one dynamics under a ladder of projections

**The architecture is founded on the Mori–Zwanzig decomposition.** One dynamics, seen under a ladder of
projections, resolves into the four roles every rung shares — **State**, **Generator**, **Observables**,
**Propagator** — and the modules *are* those roles. The decomposition can bear this weight because it is
*exact*: projecting the full dynamics onto a coarser description is not an approximation but an identity,
one that leaves behind an exact memory and an exact noise. What is *investigated, never assumed* is the
**closure** — the model of that memory. So founding the architecture on Mori–Zwanzig and refusing to
assume the physics are one commitment, not two: the framework is exact, and the approximation it demands
is precisely the research question.

The four roles are level-agnostic — a DNS, a large-eddy model, and a moment closure all carry them,
differing only in *which* state each holds and *how much* memory its generator must model:

- the **State** — the field the dynamics acts on (§4.1);
- the **Generator** — the right-hand side that evolves it, itself split into a reversible and an
  irreversible part (§4.2);
- the **Observables** — the measured functions of the state (§4.3);
- the **Propagator** — the map that advances the state through time, realised by a choice of
  integrating-factor scheme (§4.5).

Today only the finest rung, DNS, is built. The roles are named and carved so the coarser rungs slot in
without re-carving (§7), but no generality is built ahead of them.

### Specification and realization

On this foundation, a run is fixed by a **specification** — the continuous problem — and a
**realization** — the numerics. The specification has two parts:

- The **System**: the flow scenario — forced homogeneous isotropic turbulence, freely decaying
  turbulence, uniform-mean-gradient scalar mixing, and (a deferred frame, §7) homogeneous shear. A System
  is a choice of forcing, initial condition, and the dimensionless parameters ``\mathrm{Re}`` and
  ``\mathrm{Sc}``.
- The **Model**: the level of description — a *rung on the ladder of projections*. DNS resolves every
  active scale; a large-eddy Model resolves the large scales and models the rest; a
  filtered-density-function or moment Model carries statistics rather than fields. Descending the ladder
  applies a coarser projection, and the memory it leaves is what the Model's closure must supply.

The realization is the **Method** — the numerics — in two layers the package keeps distinct:

- A **Model-fibered family** — the choices that only make sense *for a given Model*: the time-stepping
  scheme and its dealiasing for a field Model (§4.5), or the particle pushers and mixing model a
  statistical Model would need. The Model sets these.
- **Model-agnostic axes** — precision, memory footprint, and compute backend (§6) — which cut across
  every Model uniformly.

Naming these apart is why the frame is *specification × realization* rather than three co-equal axes: the
Method is fibered over the Model, not independent of it.

### The comparison machine

Two research disciplines live on these two kinds of variation:

- **Method-independence.** Vary the realization, hold the specification fixed, and the answer must not
  change beyond discretisation error. Two schemes, two precisions, or two grid sizes for the *same* DNS
  must agree; agreement is the correctness signal, and the cheapest realization that still agrees is a
  finding, not merely a default.
- **Statistical commutation.** Descend the Model ladder, hold the System fixed, and the coarse Model must
  reproduce the fine Model's *statistics*. Filtered DNS against LES of the same flow is the test — a match
  in distribution, never pathwise (§8), because the coarse state cannot determine its own tendency, and
  that missing tendency is exactly the Mori–Zwanzig memory. This is the closure question made operational.

Both disciplines are the *same comparison machine* — run a configuration against a reference and check
chosen physical functionals (spectra, fluxes, conserved quantities, a target statistic) within tolerance —
pointed at different axes. Those functionals are exactly the Observables of §4.3.

---

## 4. Modules

Each concern is its own module, included in dependency order by the umbrella
`src/GBGIsotropicTurbulence.jl`. The four Mori–Zwanzig roles carry their role names — `State`, `Generator`,
`Observables`, `Propagator`; the System's forcing, the discretised frame, the Lagrangian instruments, the
run layer, and the reference laws are named by their job. The rule is that **a role recurring at every
rung of the ladder wears its role name, while a concrete mechanism wears its job** — so the load-bearing
structure is legible at a glance, and no piece of plain machinery is dressed in theory it does not carry.

### 4.1 `State` and `SimulationDomain` — the field and the frame it lives on

Two modules separate *what evolves* from the *frame it evolves on*.

- **`SimulationDomain`** provides the discretised periodic box the run lives on — the reusable,
  read-only frame. Its concrete type is the **`FixedDomain`**, the fixed, unsheared cube, realised by
  the grid, the real–Fourier layout, the real-to-complex transform plans (one for the
  velocity, one for the scalar, one for the rank-2 strain tensor the skewness diagnostic needs), the
  spectral multipliers, the squared-wavenumber array ``\lvert\boldsymbol{\kappa}\rvert^2`` (in spectral
  space, ``-\nabla^2`` acts as multiplication by ``\lvert\boldsymbol{\kappa}\rvert^2``), and the dealias
  kernel from the run's chosen dealiasing strategy (the sharp ``2/3`` rule by default). The name marks what can vary: a `FixedDomain` has time-independent,
  separable wavenumbers, unlike the deferred sheared frame (`ShearedDomain`, §7). **Precision and backend enter here and flow everywhere
  from here**: `scalar_type` fixes the real element type (`Float32` or `Float64`)
  and `array_type` the storage (`Array`, `CuArray`, `ROCArray`), and every buffer is allocated `similar`
  to this frame, so a run is CPU/GPU-agnostic and single- or double-precision by construction.
- **`State`** owns the DNS realisation of the Mori–Zwanzig State role. **`ResolvedFields`** is the inert
  record of the evolving spectral fields — the velocity ``\hat{\boldsymbol u}`` and, when the run carries
  one, the scalar ``\hat\varphi`` — and the *single source of truth*: the physical velocity, vorticity, and
  scalar are derived from it on demand and never stored, so the state cannot go stale. No operation hangs
  on it; the generator advances it and the observables read it, both as external functions of
  ``(\hat{\boldsymbol u}, \hat\varphi)`` — the reification the Mori–Zwanzig lens demands, kept a bare
  carrier so the arrows stay primary (§11 decision 26). Its initial conditions seed it:
  `random_solenoidal_velocity!` fills a divergence-free velocity with a large-scale spectral envelope,
  rescaled to a target ``k``, and `random_scalar!` fills a mean-zero scalar to a target variance. The
  per-step scratch is **not** state: it lives with the integrator that owns it (`IntegratorBuffers` in
  `Propagator`, §4.5), preallocated so a step allocates no field-sized memory (§9, invariant 4) and sized
  to the run (no scalar buffers when the run carries no scalar; GPU memory is tight). A `Simulation`
  composes the `ResolvedFields`, and the time loop advances it in place.

### 4.2 `Generator` — the evolution, split reversible and irreversible

`Generator` realises the Mori–Zwanzig generator: the right-hand side the propagator advances. Its physical
inputs are bundled in `FlowConditions` — the viscosity ``\nu`` (``\mathrm{Re} = 1/\nu``), the Schmidt number
``\mathrm{Sc}`` (scalar diffusivity ``\varkappa = \nu/\mathrm{Sc}``), and the two forcings; ``\nu`` and
``\mathrm{Sc}`` set the diffusion, the forcings the source, and folding this bundle into `Generator` is what
adds the `Generator → Forcing` dependency. It carries a
**metriplectic seam** — a reversible part that conserves energy and an irreversible part that dissipates
it (§8) — and the numerical split is built to honour it. The incompressible momentum equation is
advanced in **rotational (Lamb-vector) form**: writing the convective term through the identity
``(\boldsymbol u\cdot\nabla)\boldsymbol u = \nabla(\tfrac12\lvert\boldsymbol u\rvert^2) - \boldsymbol u\times\boldsymbol\omega``
(with vorticity ``\boldsymbol\omega = \nabla\times\boldsymbol u``) and letting the Leray–Helmholtz
projection ``\mathbb P`` onto divergence-free fields absorb the pressure and the kinetic-energy gradient,
the equation becomes

```math
\partial_t\boldsymbol u = \mathbb P\,(\boldsymbol u\times\boldsymbol\omega) + \nu\nabla^2\boldsymbol u + \boldsymbol f .
```

Its three terms are the seam made explicit, and the time-stepping treats each according to its nature:

- **The reversible term.** `velocity_to_physical!` and `vorticity_to_physical!` recover the physical velocity and vorticity from
  ``\hat{\boldsymbol u}``; `velocity_nonlinear!` then assembles
  ``\mathbb P\,(\boldsymbol u\times\boldsymbol\omega)``, dealiased by the ``2/3`` rule to remove the
  aliasing of the quadratic product (the pseudospectral method; Orszag & Patterson 1972, the ``2/3`` rule
  Orszag 1971). Rotational form is the cheap, energy-conserving way to compute the advection spectrally,
  and incompressible Euler is genuinely Hamiltonian — so this term is the flow's *reversible*,
  energy-conserving generator, stepped explicitly.
- **The irreversible term.** The diffusion ``\nu\nabla^2\boldsymbol u`` is the flow's *irreversible*,
  net-dissipative generator. Being diagonal in Fourier, it is integrated *exactly*: `integrating_factor!`
  builds the flow map
  ``\mathcal E(\boldsymbol{\kappa}) = \exp\!\big((A(\boldsymbol{\kappa}) - D\lvert\boldsymbol{\kappa}\rvert^2)\,\Delta t\big)``
  — the exact propagator of the linear part over a step, with diffusivity ``D = \nu`` for the velocity and
  ``D = \varkappa = \nu/\mathrm{Sc}`` for the scalar, and ``A(\boldsymbol{\kappa})`` an optional linear
  forcing rate (the source, below) — and multiplying a field by ``\mathcal E`` advances its diffusion with
  no stability restriction. ``\mathcal E`` is a *propagator*, a flow map over a step, not a generator;
  keeping the two apart is exactly the Generator/Propagator distinction of §4.5.
- **The source.** ``\boldsymbol f`` is the forcing, an external drive that is neither seam half (§4.4).
  When a forcing is *linear* in the field (``\boldsymbol f = A\,\boldsymbol u``), its rate
  ``A(\boldsymbol{\kappa})`` is diagonal and linear like the diffusion, so it folds into the same
  exponential ``\mathcal E`` for exactness — and there it *injects* energy, ``\mathcal E > 1`` wherever
  ``A > D\lvert\boldsymbol{\kappa}\rvert^2``. So ``\mathcal E`` cross-cuts the seam: it carries the
  irreversible diffusion and, when the drive is linear, the source. The seam is a decomposition of the
  right-hand side, not of ``\mathcal E``.

The passive scalar rides the same generator: `scalar_to_physical!` transforms ``\hat\varphi`` to the
physical ``\varphi`` at each stage, and `scalar_nonlinear!` assembles the advection in conservative form
``-\nabla\cdot(\boldsymbol u\varphi)`` (equal to ``-\boldsymbol u\cdot\nabla\varphi`` since
``\nabla\cdot\boldsymbol u = 0``); the conservative form conserves the scalar mean exactly under the
``2/3`` rule.

The metriplectic reading is a **lens, not a literal thermodynamics**: incompressible isothermal flow
carries no genuine entropy — the dissipated kinetic energy simply leaves the model as untracked heat — so
the load-bearing content is the reversible/irreversible split of the right-hand side and the constraint it
puts on any closure: net dissipation lives in the diffusion term alone, so a subgrid model may only
*remove* energy through that half (§8).

### 4.3 `Observables` — the measured functions of the state

`Observables` realises the Mori–Zwanzig observables: the functions of the state that are measured. Each
states the physical quantity first, then the reduction that computes it:

- `kinetic_energy` ``k = \tfrac12\langle\lvert\boldsymbol u\rvert^2\rangle`` and `dissipation`
  ``\varepsilon = \nu\langle\lvert\boldsymbol\omega\rvert^2\rangle``;
- `scalar_variance` ``\langle\varphi^2\rangle`` and `scalar_dissipation`
  ``\varepsilon_\varphi = 2\varkappa\langle\lvert\nabla\varphi\rvert^2\rangle``;
- `max_speed`, which sets the advective CFL;
- `derivative_skewness`, the K41 marker ``S \approx -0.5`` of developed turbulence, computed
  coordinate-free as the normalised third invariant of the strain rate ``\boldsymbol S``,
  ``3C\langle\det\boldsymbol S\rangle/\langle\boldsymbol S:\boldsymbol S\rangle^{3/2}`` with the exact
  isotropy constant ``C = \tfrac47\sqrt{15/2}`` (which reproduces the classical longitudinal skewness);
- `energy_spectrum` ``E(\kappa)``, the halved `GBGPeriodicFields` radial spectrum, and `integral_scale`
  derived from it.

These are not incidental: they are the **fitness functionals** the comparison machine of §3 evaluates,
and the stationarity signals `warmup!` watches. They are also the *measured* half of the validation
harness whose *predicted* half is `Phenomenology` (§4.8).

### 4.4 `Forcing` — the source

Forcing is the System's energy-injection strategy — the source term ``\boldsymbol f`` of §4.2, and the one
deliberately designed-in extension point. `AbstractForcing` is the supertype; a forcing enters the
step through a small interface whose four methods each default to doing nothing:

- `set_forcing_rate!` — for a forcing *linear* in the field (``\boldsymbol f = A\,\boldsymbol u``): fill the
  per-mode rate ``A(\boldsymbol{\kappa})``, folded into the integrating factor (exact, order-preserving);
- `add_forcing_source!` — add an additive source at each Runge–Kutta stage;
- `prepare_forcing!` — advance internal state once per step (a stochastic process);
- `apply_forcing!` — apply a post-step projection or rescale.

`NoForcing` (free decay), `BandRescaling` (hold a band's *or* the total energy fixed), and `Linear` and
`ConstantPower` (negative-damping, folded into ``\mathcal E``) are provided; a stochastic Eswaran–Pope
Ornstein–Uhlenbeck forcing is archived (§7). **One implementation serves both** the velocity (a vector
field) and the scalar (a scalar field), because these four methods are written through tensor-order-generic field
operators — the only field-specific step is the solenoidal (Leray) projection, applied to the velocity
alone. Each forcing has an operator-taking constructor and an operator-free keyword form
(`ConstantPower(target = 0.1)`, a `DeferredForcing`) materialised when `Simulation` builds the frame, so a case
can name its forcing before the grid exists.

### 4.5 `Propagator` — the map that advances the state in time

`Propagator` realises the Mori–Zwanzig propagator: the map that carries the state forward in time, built
on the generator's reversible/irreversible seam. Its numerical schemes are the Model-fibered part of the
Method (§3).

- **`AbstractIntegrator`** is the family of integrating-factor schemes dispatched by **`step!`**, which
  advances the spectral velocity ``\hat{\boldsymbol u}`` and scalar ``\hat\varphi`` **together** through
  the same Runge–Kutta stages. Coupled stepping is deliberate: the scalar is passive, so time-accuracy
  needs both nonlinear terms evaluated at each stage's state; advancing the velocity fully and the scalar
  afterward would drop the substage velocities and degrade the coupling to first order.
- **`IFLowStorageRK3`** (the Williamson 2N / RKW3 workhorse) is third-order and imaginary-axis stable;
  **`IFRK2`** (Heun) is a cheaper two-stage option that is imaginary-axis unstable and leans on viscous
  damping. `recommended_cfl` gives each scheme its conservative advective-CFL ceiling ``C`` (for
  ``\Delta t = C\,\Delta x/\max_i\lvert u_i\rvert``), which the run layer uses with `max_speed` to choose
  ``\Delta t``.
- **`IntegratorBuffers`** is the per-step scratch the propagator owns and writes into — the shared
  right-hand-side working fields (the physical-recovery copies, the `product_physical`/`product_spectral`
  that carry the quadratic products, the physical registers, the integrating factor, the linear forcing
  rates) plus the scheme's Runge–Kutta stage registers — built by `allocate_buffers` dispatching on the
  concrete scheme, so each allocates exactly its working set. Because the generator's operators take their
  scratch fields individually (naming no bundle), this scratch belongs to the propagator's realization,
  not upstream with the state; it is decidedly *not* the state (§11 decision 26).

### 4.6 `Particles` — Lagrangian instruments

Particles are **instruments** — probes of the turbulence — not a second physics. A particle is a
state-carrying trajectory object: today a tracer (position ``\boldsymbol x``); the deferred ladder is
inertial (``\boldsymbol x, \boldsymbol v``) and oriented (``\boldsymbol x, \boldsymbol v, \boldsymbol L``)
probes (§7). `Tracers` holds positions and a chosen interpolation scheme; `advect!` pushes them
Heun-in-time on the velocity at the start and end of the step (the fields the solver already produces);
`sample!` reads any field along the trajectories for Lagrangian statistics.

Their **numerics are first-class**, on the same footing as the field schemes. Two axes matter: the
trajectory integrator — today a single second-order Heun push, with higher-order pushers the studied
future axis — and the sampling-consistency axis, the interpolation scheme's order relative to the field's
spectral accuracy (`CatmullRom` by default, higher-order `LalescuSpline` / `LagrangeSpline` available).
When the inertial and oriented probes arrive, the integrating-factor split carries over for the
*translational* stiff drag (field viscosity and a particle's linear or matrix drag are the same
linear-exact move), while **orientation dynamics on the rotation group is a distinct geometric
integrator** — the reversible generator of §8 again — so the split does not naively unify all of it.

### 4.7 `SimulationRun` — the front door

A `Simulation` value bundles what a case advances: the `FixedDomain`, the `ResolvedFields` state (the
spectral fields ``\hat{\boldsymbol u}`` and ``\hat\varphi`` the generator acts on), the `IntegratorBuffers`
scratch, the `FlowConditions`, the chosen `AbstractIntegrator`, any `Tracers`, a stored CFL ceiling and the tracer-velocity buffer
for the Heun push, and a clock. Over it:

- **`Simulation(...)`** — the assemble-with-defaults constructor: from a grid size and a forcing it
  builds every piece of §4.1–§4.6, seeds a divergence-free initial condition, and picks the default
  scheme. The viscosity is set from the grid by default — the highest Reynolds number the grid
  resolves (decision 20) — with an explicit `viscosity` the opt-in override. Setup is a few numbers.
- **`advance!(sim; dt)`** and **`run!(sim; ...)`** own the time loop: choose ``\Delta t`` from the
  scheme's CFL and the current `max_speed`, refresh the cached start-of-step velocity and vorticity,
  `step!`, advect tracers, and fire a user callback on a fixed time interval.
- **`warmup!(sim; ...)`** advances to statistical stationarity — by default until the running dissipation
  ``\varepsilon(t)`` and the velocity-derivative skewness ``S(t)`` have both plateaued (a trailing-window
  flatness test), reading ``\varepsilon`` rather than the clampable ``k(t)``, and, when the scalar is
  forced, until ``\langle\varphi^2\rangle`` settles too; or a fixed turnover, time, or step budget.
- **`current_time(sim)`** and **`current_step(sim)`** report the clock, and `kinetic_energy(sim)` /
  `dissipation(sim)` / `scalar_variance(sim)` the current-state diagnostics, for a callback to read.

The layer wires §4.1–§4.6 together and holds no physics or numerics of its own.

### 4.8 `Phenomenology` — the reference laws (extraction-bound)

`Phenomenology` is the library of **reference turbulence phenomenology**: the fitted scalings, model
spectra, structure-function laws, and dimensionless constants that theory and experiment have established.
It is the **symmetric counterpart to `Observables`** — those are the *measured* functions of the DNS
state; these are the *predicted* values of the same functions. The DNS measures, the laws predict, and the
comparison machine of §3 sets them side by side. Two properties follow, both instances of the charter
*investigate the physics, do not assume it*:

- **A provider, not a comparer.** A law evaluates itself from the flow parameters; it knows nothing of the
  DNS. The comparison lives consumer-side (the validation layer), which reads both.
- **No parametrization is privileged.** A published fit and one of our own are the same kind of object —
  subtypes of one law family, discovered and validated alike, never baked in as truth.

**The abstraction is the strategy pattern** already used for `AbstractForcing` / `AbstractIntegrator` /
`DealiasingStrategy`: **a law family is an abstract type, each parametrization a concrete subtype**
carrying its fitted coefficients and provenance, implementing one small interface — evaluate the law at its
argument (``\kappa``, ``r``, ``\mathrm{Re}_\lambda``) given a `FlowParameters` bundle; report its
`provenance` (the citation and validity range); and eventually `fit` itself to data. Choosing a law is
choosing the subtype (`Pope2000` versus `VonKarman1948`) and optionally overriding its coefficients
(`Pope2000(; C_K = 1.6)`, the published fit being the default). Provenance is first-class — the comparison
needs a law's validity range to be fair, and it is the single source of the citation.

**Naming is a three-level handle**, because one author publishes many models across years and quantities:
the **quantity is the submodule** (`Spectra.Pope…` versus `StructureFunctions.Pope…`), the **paper is the
author-year type** (`Pope2000`, first author's surname, the full list in `provenance`), and a **same
author-year-quantity collision takes a trailing letter** (`Pope2014a`, `Pope2014b`). The validating case
is Kolmogorov 1941, in two submodules at once — `Spectra.Kolmogorov1941` (the ``-5/3`` spectrum) and
`StructureFunctions.Kolmogorov1941` (the 2/3 and 4/5 laws) — separated by the submodule alone. The full
handle `Phenomenology.Spectra.Pope2000` reads like a citation and is unique by construction.

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

Three exist now — enough for the validation checklist — and the count caps near six: `PDFs`, `Decay` (``k \sim t^{-n}``),
and `Lagrangian` are named future seams (§7), not owed. A single `FlowParameters` bundle carries every
dimensionless group a law might read (``\mathrm{Re}_\lambda``, ``\varepsilon``, ``\nu``, ``L``, ``u'``,
``\mathrm{Sc}``, ``\varepsilon_\varphi``), the derived scales (``\eta``, ``\tau_\eta``, ``k``, ``\lambda``)
as helpers — the analogue of the `FlowConditions` and `FixedDomain` bundles.

The laws are **consumed to build runs**, not only compared against: an initial-condition or forcing
spectrum drawn from `Spectra`, and the reference curves the validation harness reads, all from one library.
And the loop closes: we measure (with this package and SS), `fit` a parametrization to that measurement,
and the new fit lands beside the literature, to be validated against the next run.

**Formula verification.** A transcribed law is checked not against a reference implementation — none is
authoritative, and cross-checking against another code merely moves the trust — but against the physical
relations it *must* satisfy: the asymptotic slopes (the ``\kappa^{-5/3}`` inertial range, the low-wavenumber
``\kappa^\sigma``, the dissipation cutoff), the ``\zeta_3 = 1`` constraint on every intermittency model,
and the roll-off limits ``f_L, f_\eta \to 1``. This self-consistency battery lives in the test suite and
catches a wrong exponent, coefficient, or sign without trusting a second source.

**Extraction requirement (recorded).** `Phenomenology` is built inside this package for now but is
**designed to be cut into a standalone `GBGTurbulencePhenomenology` with no rewrite** — the demand-driven
path that extracted `GBGStreamingStatistics`. The requirement constrains the design. It is a
**dependency-light leaf**, depending on *neither* `GBGPeriodicFields` (a law is a scalar function, no field
math) *nor* `GBGStreamingStatistics` (it provides reference values, computes no statistics) *nor* this
package's dynamics — first in the include order, importing nothing turbulence-dynamical. And it is a
**self-contained namespace**: the umbrella does *not* re-export it (`using GBGIsotropicTurbulence` brings
the DNS API only; the laws are reached opt-in through `Phenomenology`), and its notation and API pages form
their own group, separable from the DNS surface. Extract when a second consumer appears; until then the
seam is real but uncrossed (decision 18).

### 4.9 Layout summary

`SimulationDomain → State → Generator → Observables → Forcing → Propagator → Particles → SimulationRun`.
Cross-module access is through explicit `using ..Module: name` lists; `Phenomenology` (§4.8) leads this
order as the dependency-light leaf the initial-condition, forcing, and validation consumers read.
Statistics live consumer-side of this package too: the sampling in `Particles` and the observables in
`Observables` produce the *samples*, and a statistics bridge that streams them to `GBGStreamingStatistics`
is deferred (§7).

---

## 5. The consumer boundary — what belongs here, and what does not

`GBGIsotropicTurbulence` owns the turbulence-specific glue and delegates everything domain-neutral. The
dividing line is **domain-neutrality**, not "thinness":

- **To `GBGPeriodicFields`** — every field operation: the transforms, `curl!` / `cross!` / `divergence!`,
  the Leray projection `helmholtz_projection!` (``\mathbb P``), `convolve!` and the dealias/band kernels,
  the reductions (`inner`, the radial spectrum and correlation), and grid↔point interpolation. The rule
  *everything diagonal in Fourier is a `GBGPeriodicFields` operator* is followed in the code.
- **To `GBGStreamingStatistics`** — every estimator: histograms, densities, conditional means and
  variances, conditional and transition densities.
- **Owned here** — the Navier–Stokes and scalar nonlinear assembly, the integrating factor, the forcing
  strategies, the coupled time-stepping, the particle tracking, the run layer, and the turbulence-specific
  spectral glue a backend must not carry (the deferred sheared frame's non-separable multipliers, §7).

Two standing rules follow:

1. **If a capability's true home is `GBGPeriodicFields` or `GBGStreamingStatistics`, raise it and extend
   it *there* — do not reimplement it here.** Only genuinely *domain-neutral* capability migrates out; a
   backend has an anti-accretion charter, so turbulence-specific glue stays here.
2. **A deferred-by-design future is not a missing feature** (§7).

---

## 6. Precision and footprint as studied axes

Precision and the memory-footprint/accuracy trade-off are **objects of study**, not fixed defaults — the
numerical counterpart of the charter that the tool investigates the physics rather than assuming it (§8).

- **Both precisions are supported equally, with no privileged default.** `Float32` is the
  development and desktop precision; `Float64` is the production precision. The element type
  ``T`` flows from the frame (§4.1): no kernel silently fixes the arithmetic. (The `FlowConditions` scalar
  parameters are stored `Float64` and converted to ``T`` at use — a scalar convenience, not a field
  commitment.) The **one computational exception** is statistics: reductions and online moments aggregate in
  `Float64` even for a `Float32` field, since summing many single-precision values loses accuracy —
  precision flows from the frame where the field is *stored and stepped*, never where it is *accumulated*.
- **The footprint/accuracy trade-off is held at both ends** — low-storage integrators, the dealias
  fraction, truncation — and the working point is chosen by *direct fitness test*, never decreed. Which
  precision, order, or footprint suffices for a regime is a measured finding.
- **The fitness arbiter is the comparison machine of §3** — the same one that adjudicates
  method-independence and DNS-versus-LES statistical commutation. One machine ranges over model
  fidelity, integrator, precision, footprint, and closure; the *sufficiency frontier* (the cheapest
  realization that still passes) is a deliverable of the tool.

This is why the `GBGPeriodicFields` element-type genericity and GPU-first, allocation-free discipline are
load-bearing here: they are what make precision and backend free to vary, and they are what keep the state
a compile-time product of concretely-typed buffers (§9, invariant 4). "Low footprint" is the default
working point on a studied axis, not a universal law.

---

## 7. Deliberately deferred

These are **named so they are not precluded, and deliberately left un-abstracted**: no extension point or
generalisation is built for them until a second concrete case forces the abstraction. None is a gap.

- **Stochastic (Eswaran–Pope OU) forcing** — `StochasticOU`, a band-limited Ornstein–Uhlenbeck process
  added to the RHS. *Built and validated, then archived* from the public surface (un-exported,
  undocumented) to be re-added; its host-side random increment is the one allocation-free exception
  (invariant 4), so the re-add is gated on a GPU-tuned generator (Eswaran & Pope 1988).
- **Inertial and oriented particles** — ``(\boldsymbol x,\boldsymbol v)`` with matrix drag, then
  ``(\boldsymbol x,\boldsymbol v,\boldsymbol L)`` with torque. The translational drag reuses the
  integrating-factor split; orientation needs a geometric integrator (§4.6, §8).
- **The sheared frame (Rogallo), a `ShearedDomain`.** A uniform mean velocity gradient makes the
  wavenumbers time-dependent (``d\boldsymbol{\kappa}/dt = -\boldsymbol{A}^{\!\top}\boldsymbol{\kappa}``)
  and non-separable — the `SimulationDomain` counterpart to `FixedDomain` (§4.1). This is
  the one future with a concrete `GBGPeriodicFields` dependency: its separable per-axis multipliers cannot
  hold a sheared lattice, so it is a bounded extension *there* (rule 1 of §5), not a job here.
- **The Model ladder beyond DNS** — a large-eddy Model (filter the DNS, model the subgrid stress) and a
  filtered-density-function or moment Model (§8). Each is a coarser projection on the ladder of §3, and the
  four roles are already carved to receive it — but, per invariant 9, no generality is built until a second
  rung forces it. Each is discriminated from DNS by statistical commutation; the canonical acceptance test
  is the relaxation of a two-mode scalar distribution (a micromixing benchmark).
- **The statistics bridge** — the sampling-to-`GBGStreamingStatistics` path (Eulerian field samples and
  Lagrangian trajectory samples in, streamed summaries out).
- **Alternative dealiasing and nonlinear forms.** `DealiasingStrategy` today supplies a *kernel* applied
  coefficient-wise *after* the nonlinear term is assembled — which carries the sharp ``2/3`` rule and the
  smooth Hou–Li filter, but not ``3/2`` zero-padding or phase-shifting (which restructure how the
  nonlinear product is *computed*, not merely filter its output), nor the **skew-symmetric** momentum form
  (which reorganises how the quadratic product is assembled, to conserve energy in the discrete equations).
  Their common generalisation is a single strategy that *owns the de-aliased nonlinear assembly* —
  ``\hat{\boldsymbol u}`` and ``\hat\varphi`` in, the de-aliased product out — with the present
  kernel-multiply one realisation and padding, phase-shift, and skew-symmetric its siblings. It touches
  only the `Generator`'s nonlinear assembly and its scratch, never the State (§4.1); deferred, with the
  rotational form + spherical ``2/3`` the recorded lean default.
- **A temporal-accuracy step control.** The step is set today by the advective **CFL** — a
  stability-calibrated, conservative ceiling with a manual `cfl` override — and nothing adapts it to a
  target *temporal* accuracy. An embedded-error or PI step controller, distinct in purpose from the
  stability CFL, would make temporal accuracy a studied fitness axis beside precision and footprint (§5).
  Deferred: HIT runs are typically stability-limited near the CFL ceiling, so a fixed step at the CFL is
  rarely the accuracy bottleneck.

---

## 8. Lenses and prior art

The package makes real theory legible. One framework — **Mori–Zwanzig — is its foundation** (§3); the rest
are lenses read through it. Nothing in the *numerics* is load-bearing on the subordinate lenses — the
arithmetic would be identical had they never been named — but the *architecture* is founded on the
Mori–Zwanzig decomposition, which is exact and so can carry that weight. The lenses organise
*understanding* and set what the tool is built to *investigate*, not assume.

- **Mori–Zwanzig — the foundation, elaborated.** §3 states the decomposition; here is its machinery. A
  projection ``\mathcal P`` splits the full state into a resolved part and the rest, and applying it to the
  exact dynamics gives the resolved variables a **generalised Langevin equation**: a streaming term (the
  projected drift), a **memory integral** over a kernel ``K(t-s)`` carrying the history the projection
  discarded, and a **coloured-noise** term living in the unresolved subspace. A Model is a choice of
  ``\mathcal P`` and a closure that approximates that kernel and that noise; DNS is the identity
  projection, for which both vanish, so it needs no closure. The memory kernel ``K`` is the precise content
  of the tendency a coarse state cannot supply on its own (§3), and modelling it is the closure problem the
  tool exists to test.
- **Open systems / non-equilibrium — a reading of the projection.** The Mori–Zwanzig cut *is* the
  open-system system/environment split: the **resolved** variables are the system, the projected-out
  variables the environment, which survives only as the memory + noise above. A driven-dissipative flow is
  an open system in a non-equilibrium steady state — energy injected by the forcing (an energy *reservoir*,
  the source of §4.2), dissipated to the unmodelled viscous *bath* (the sink), balanced at stationarity. The
  lens carries its own caveat: whatever a model *retains* of the environment — a stochastic forcing's
  internal state, a closure's subgrid degrees of freedom — is not the environment but the finite
  **Markovian surrogate** kept on the system's own side, a *modelled* degree of freedom; so it homes, when
  built, as a modelled slot on the one `State`, never a separate "environment state".
- **The commuting square — the modeling ideal.** With ``\Pi`` a coarse-graining and ``S`` a flow map, one
  would like ``\Pi\circ S_{\text{fine}} = S_{\text{coarse}}\circ\Pi``. It cannot hold pathwise: the coarse
  state does not determine its own tendency (that is the memory and noise made concrete), and turbulence is
  chaotic. The achievable ideal — the design target of any Model — is **statistical** commutation,
  agreement of the distributions and fluxes on the attractor, exactly what the DNS-versus-LES comparison of
  §3 measures.
- **Geometric mechanics (metriplectic / GENERIC) — the reversible/irreversible split.** The
  integrating-factor method *is* a split into a reversible generator (the advection, in rotational form,
  §4.2) and an irreversible one (the diffusion, integrated exactly). Read as a metriplectic system — a
  Hamiltonian (symplectic) bracket generating the reversible part, a dissipative (metric) bracket the
  irreversible — the lens says *why* the split is structure-preserving and constrains every closure to be
  net-dissipative. Here it is a lens rather than a literal thermodynamics: isothermal incompressible flow
  has no genuine entropy (§4.2). The term is Morrison's (metric + symplectic); GENERIC (Grmela–Öttinger)
  is the same structure.
- **Renormalisation / scale invariance — a hypothesis, never a foundation.** Small-scale universality is
  what would make closure constants transferable, but it is approximate (intermittency), it fails for
  scalar small scales (persistent gradient anisotropy), and the unclosed terms are *conditional* quantities
  that re-import the large scales. So the tool is built to *test* how universal a closure is, per regime,
  not to assume it. This is the general charter: **the architecture investigates the physics; it must not
  assume it** — the same discipline as the model-free statistics it consumes.

---

## 9. Invariants — the deliberate absences

The public surface and these absences are the spec. Do not add a capability "for completeness"; a missing
one usually encodes a decision.

1. **No units.** Control is by ``\mathrm{Re}`` (through ``\nu``) and ``\mathrm{Sc}``; every diagnostic is
   dimensionless.
2. **No field or statistics machinery reimplemented.** Field operations come from `GBGPeriodicFields`,
   estimators from `GBGStreamingStatistics` (§5).
3. **No privileged precision or backend.** ``T`` and the array type flow from the frame; both precisions
   and CPU/GPU are first-class (§6).
4. **Allocation-free stepping over a compile-time state.** A time step allocates no field-sized memory over
   the preallocated `IntegratorBuffers` — load-bearing for GPU hot loops. The evolving state is a **compile-time
   product of concretely-typed buffers** (a parametrised record the compiler specialises), never a
   runtime-heterogeneous container — the discipline that keeps the step type-stable and device-generic, and
   that lets the state grow (a scalar today, a coarser Model's extra fields tomorrow) to more slots at no
   runtime cost.
5. **GPU-first, single-node, backend-agnostic.** Shared-memory only; no distributed or multi-GPU scope
   (inherited from `GBGPeriodicFields`).
6. **No baked-in physical model, closure, or universality assumption.** The tool investigates these; it
   does not assume them (§8). The Mori–Zwanzig foundation is exempt because it is *exact*, not a model — a
   projection is an identity, and what remains modelled is the closure the tool is built to test (§3).
7. **A library, not a framework.** The run layer is a convenience over exposed pieces (§2, §4.7), never a
   mandatory shell.
8. **The scalar is denoted ``\varphi``**, never ``\theta`` — in code, mathematics, and prose.
9. **Deferred futures are accounted for, not owed** (§7); no speculative extension points.

---

## 10. Conventions

- **Docstrings are operator-first, then scheme.** State the continuous operator or PDE term and its
  exact/ideal form, *then* the discrete realisation — as `integrating_factor!` leads with
  ``\partial_t f = D\nabla^2 f`` before ``\mathcal E(\boldsymbol{\kappa})``, and `velocity_nonlinear!` with
  the Lamb-vector identity before the pseudospectral product. This is the turbulence analogue of the
  siblings' physical-form-first / estimand-first rules.
- **Coordinate-free where a coordinate-free form exists.** Homogeneous isotropic turbulence is
  statistically isotropic — no preferred direction — so a diagnostic or computation that picks a coordinate
  axis imports a spurious direction-dependence; state the **rotation-invariant** form, not an axis
  projection. The reference is `derivative_skewness`: the normalised third invariant of the strain rate
  ``\boldsymbol S``, not the axis-picking longitudinal velocity-derivative skewness (decision 17).
- **Two-tier docs.** `CLAUDE.md` is the terse working map and defers here; this document carries the
  rationale and the decision log. Mathematics is rendered LaTeX in the glossary's notation
  ([`docs/src/notation.md`](notation.md)); a code identifier is always in `backticks` and never inside a
  math span; each code object is bound to its mathematical symbol on first mention — rendered as one
  LaTeX span, ``\texttt{dissipation} \equiv \varepsilon``.
- **No dead references on the user-facing surface.** A rendered docstring — and a thrown error — must
  read complete at the REPL, where cross-links are dead: it cites no section number (`§4.5`),
  decision-log entry, or repo path. Design rationale and section citations stay in `#` comments and this
  document.
- **Cross-referencing is discriminating-minimalist.** A link earns its place: promote a backticked
  identifier to `@ref` / `@extref` only for a genuine jump with one clear destination; link a target at
  most once per docstring; never link the docstring's own binding, its arguments, or bare `Base` names —
  except the storage-backend / element types and `GBGPeriodicFields` objects, which `@extref` to their
  own package docs (the `DocumenterInterLinks` setup).
- **Verification is by numerical oracle, not a formalization ledger.** Because the package introduces no
  novel mathematical *objects* (they are `GBGPeriodicFields`' and `GBGStreamingStatistics`'), its
  nontrivial claims are *dynamical* — the exactness of ``\mathcal E``, the order of the integrator,
  imaginary-axis stability, mean conservation — and are pinned by numerical oracle tests (a Taylor–Green
  order study, unforced energy decay, exact diffusion). This is why the package follows the
  `GBGCloudPhysics` consumer pattern with **no `FORMALIZATION.md`**; a typed-statement ledger is a
  backend's need. The design's *structure* — the module carving and role wiring — is separately checked
  against a relational-logic model (`docs/architecture.als`, decisions 21–22); that model carries no
  dynamics, so it complements the oracle rather than becoming the ledger. Revisit only if a built Model
  rung introduces genuinely package-specific formalism.
- **Category/type errors are their own correctness class.** A claim can be perfectly formatted and read
  true yet conflate two *kinds* of object — a field with its representation (physical vs spectral); a
  diagnostic scalar with the field it reduces (the rate ``\varepsilon``, a number, vs a dissipation
  field; ``k`` vs the spectrum ``E(\kappa)``); an operator with its parameter (``\mathcal E`` vs ``\nu``;
  ``\mathbb P`` vs ``\mathcal P``); a rate with its time-integral; a spectral density ``E(\kappa)`` with an
  energy. Type each object from the code and expand the statement — the physics mirror of the sibling
  backends' type-error guard (`GBGStreamingStatistics`' density-vs-measure, estimator-vs-estimand).
- **The `/check-docs` battery.** Documentation quality is enforced by a full matrix — (Correct /
  Self-contained / Notation / Formatted / Current / Cited / variant-pairs) × (every surface:
  `ARCHITECTURE.md`, every `src/*.jl` docstring, every `docs/src` page) — run to completion in one pass
  (`.claude/commands/check-docs.md`). *Correct* extends to physical-formula and normalization checking
  (the ``1/N``, the ``2\varkappa``, the ``\tfrac12`` in the energy, Parseval factors) and to the
  category/type-error class above. Two build lints (`lint_inline_math`, `lint_notation_variants`) and
  `checkdocs = :exports` are the mechanical backstop.
- **Citations** follow author–year; the full references are §References. Never cite an inaccessible source;
  the material under `inspiration/` is private and never referenced. A reference *block* of two or more
  citations is a bullet list — one citation per line — never a semicolon-joined paragraph.

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
21. **(2026-07) The physics-first carving is checked against a formal structural model
    (`docs/architecture.als`).** The module carving and the Mori–Zwanzig role wiring were re-examined
    against an explicit relational-logic model (built and checked in Alloy) under an adversarial multi-lens
    review — a design-time artifact, deliberately not a shipped ledger — to counter a pull toward
    software-shaped, object-first structure. The model carries only **structure**: the dependency graph
    (checked against the actual `using` edges), the state as one product of typed slots on a single module,
    the Model ladder as a coarsening poset with an explicit fine→coarse projection, the
    reversible/irreversible/source split of the generator wired to the observables that measure it, closure
    required exactly where a rung is a proper projection, and the passive tracer kept distinct from an
    inertial (slipping) phase. It carries **no dynamics** — the nonlinear operator, the exact rates, the
    memory integral, the symplectic bracket stay with the numerical oracle (§10, decision 12) — so it is not
    a `FORMALIZATION.md` by another route. Four adversarial passes converged: the structural claims are
    mutually consistent and every self-check is non-vacuous (perturb its premise and the check fails). The
    exercise confirmed the carving is internally consistent and surfaced two things now recorded: the four
    MZ roles are level-agnostic — abstractions the coarser Model rungs will populate, *ready but not
    populated* while DNS is the only built rung (not a speculative extension point, invariant 9) — and the
    state-realisation discipline now folded into invariant 4.
22. **(2026-07) Mori–Zwanzig raised to foundation; the physics-first renames; this document rewritten.**
    Following the structural verification (decision 21), Mori–Zwanzig is made the **foundation** of the
    architecture, not merely the central lens — *reversing decision 8*. The reversal is safe because the
    decomposition is *exact* (a projection is an identity, not an approximation); what stays *investigated,
    never assumed* is the closure that models the memory it leaves, so the foundation and the "investigate,
    don't assume" charter (invariant 6) are one commitment. It founds the **architecture** — the carving
    and the names — not the numerics, which are Navier–Stokes solved pseudospectrally regardless. The four
    roles take their role names: `Dynamics → Generator`, `TimeIntegration → Propagator`, and
    `SimulationState` split into `SimulationDomain` (the frame) and `State` (the field), *completing and
    partly revising decision 16*. Decision 16's "realization keeps job-names" is re-cut on the sharper line
    it was reaching for — **a level-agnostic Mori–Zwanzig role wears its role name, a concrete mechanism
    wears its job** — under which the propagator is a role present at every rung, not mere realization, so
    `Propagator` is correct while its schemes (`IFLowStorageRK3`) keep their descriptive names.
    `ARCHITECTURE.md` was rewritten whole (except this append-only log) to read holistically from the
    foundation down.
23. **(2026-07) Review-round refinements: `Physics` → `FlowConditions` folded into `Generator`, the
    forcing-protocol renames, and an open-systems sub-lens.** A close read of the rewrite settled three
    changes. (a) The parameter bundle `Physics` — the viscosity, the Schmidt number, and the two forcings,
    the physical *conditions* that tune the generator, misfiled under the `Propagator` stepper — is renamed
    **`FlowConditions`** and folded into **`Generator`**, the right-hand side it parametrises; this adds the
    honest `Generator → Forcing` dependency (the RHS includes the forcing source). A six-perspective naming
    panel chose `FlowConditions` over `System` (the bundle is a proper *subset* of the §3 System axis — it
    lacks the initial condition and the domain — so a type named for the axis while holding less is ambiguous
    and imprecise) and over `GeneratorParameters` (relational, and imprecise once a coarser rung's generator
    gains closure coefficients). (b) The `AbstractForcing` protocol methods are made grammatically uniform,
    verb-first: `set_forcing_rate!`, `add_forcing_source!`, `prepare_forcing!`, `apply_forcing!`. (c) The
    open-systems / non-equilibrium reading is recorded as a **sub-lens under Mori–Zwanzig** (§8), not new
    state types: a six-tradition panel (unanimous) confirmed the system/environment split *is* the
    Mori–Zwanzig resolved/modelled cut, but that whatever a model retains of the environment is a finite
    **Markovian surrogate on the system's own side** — a `modelled` slot on the one `State`, never a separate
    'environment state' — so a stateful forcing's internal state homes there when `StochasticOU` is
    de-archived, and no type is minted now (invariant 9).
24. **(2026-07) The domain module is `SimulationDomain`, its concrete type `FixedDomain`.** Decision 22
    split the frame into a `SimulationDomain` module; naming its concrete type took one more cut, because
    Julia will not let a module cleanly re-export a type of its *own* name — `using ..SimulationDomain:
    SimulationDomain` binds the module and shadows the type, so a bare `SimulationDomain(...)` constructor
    call stops resolving (verified empirically). The module keeps the user-facing concern name
    `SimulationDomain` (the discretised box a run lives on); its type takes a name for *what it is among the
    alternatives*. Weighed against `SimpleDomain` (relational and vague — simple next to what?) and
    `PeriodicCube` (a property the deferred sheared frame *also* has), the choice is **`FixedDomain`**: the
    fixed, unsheared, orthogonal cube with time-independent, separable wavenumbers. It names the very axis
    the deferred **`ShearedDomain`** (the Rogallo moving frame, §7) varies — fixed versus sheared, separable
    versus time-dependent — so the two type names read as one family. `FlowConditions` needs no such care: a
    type, not a module, it cannot collide.
25. **(2026-07) Design-review batch: the recovery split, `ForcingSpec` → `DeferredForcing`, a scalar
    spectrum IC, and precision-aware Hou–Li damping.** Four refinements settled on a reading of the API.
    (a) The fused `velocity_vorticity!` is split into the sibling recoveries **`velocity_to_physical!`**
    and **`vorticity_to_physical!`**: its two halves share no intermediate — curl-then-transform for the
    vorticity, copy-then-transform for the velocity, over separate buffers — so the split carries no
    compute or memory penalty and reads as one convention with `scalar_to_physical!` (`X_to_physical!`
    produces the physical `X`, its source shown in the signature). (b) **`ForcingSpec` is renamed
    `DeferredForcing`**, naming the object by its meaning — a forcing specified before the domain exists
    and materialised once it does — rather than the `spec` abbreviation (superseding the name minted in
    decision 14). (c) **`random_scalar!` gains a `spectrum` keyword** mirroring
    `random_solenoidal_velocity!`, seeding the scalar from a target radial scalar-variance spectrum (an
    Obukhov–Corrsin form from `Phenomenology`) for spectrum-matched initial conditions and faster
    warm-up. (d) **`HouLi`'s `strength` defaults to `nothing`, meaning auto**: resolved at kernel-build
    time to ``-\log`` of the element type's machine epsilon (``\approx 36`` for `Float64`,
    ``\approx 16`` for `Float32`), so the Nyquist mode always damps to that precision's epsilon —
    precision as a studied axis (invariant 4); an explicit `strength` overrides.
26. **(2026-07) The state reified as `ResolvedFields`; the per-step scratch relocated to `Propagator`.**
    The DNS state — the evolving spectral velocity ``\hat{\boldsymbol u}`` and optional scalar
    ``\hat\varphi`` — is made first-class as **`ResolvedFields`** (module `State`), completing the
    Mori–Zwanzig triad whose State leg had been missing: the fields were scattered across the `Simulation`
    value while the diagnostics read the physical *scratch* as if it were state (`kinetic_energy(sim)` read
    `buffers.velocity`). It is a **bare, inert record with every operation external** — the panel's ruling,
    which adopts the category lens's guardrail (arrows primary, no methods on the carrier) and rejects its
    dissolution. **`ResolvedFields` holds only the spectral truth** (``\hat{\boldsymbol u}``,
    ``\hat\varphi``); the physical velocity, vorticity, and scalar are a Method-side derived view, never
    stored, so the state cannot go stale — and because the physical chart is rung-specific (EDQNM has no
    phases to invert), keeping it out of the state keeps the record fit to lift, unchanged, to one slot of
    the future product-of-slots `State` (§7, abstraction-ready, not built). The observables become **thin
    functions of the natural representation** with no `State` dependency:
    `kinetic_energy`/`scalar_variance`/`derivative_skewness`/`energy_spectrum` are Parseval reductions of
    ``\hat{\boldsymbol u}``/``\hat\varphi``, `dissipation` curls into scratch and reduces, and the run layer
    prepares what each needs — the mirror of the generator, both now thin externals over bare fields.
    Consequently the monolithic `FieldBuffers` is dissolved: the generator's operators take their
    **individual scratch fields** (naming no bundle), so the scratch is free to live with the integrator
    that owns it as **`IntegratorBuffers`** (module `Propagator`), built by `allocate_buffers` dispatching
    on the concrete scheme; `ScalarBuffers` stays a nested optional sub-bundle. The name `ResolvedFields`
    (over `ResolvedState` / `DNSState` / `FieldState`) follows the `FixedDomain` axis-lesson taken to the
    slot level: the module `State` carries the level-agnostic role, so the concrete slot is named for its
    representation — the *resolved fields* — with `FilteredFields` (LES/FDF) and a spectrum record (EDQNM)
    its eventual siblings in the product. A six-lens naming panel with an adversarial pass fixed the slate
    (`IntegratorBuffers`, and the scratch-field names `product_physical`/`product_spectral` over the
    velocity-only `lamb`).

---

## References

Cited author–year above; full entries here. DOIs to be confirmed against the user's copies before the
docs are published (they are not yet filled in, per the no-guessed-citation rule).

- Kolmogorov, A. N. (1941). The local structure of turbulence in incompressible viscous fluid for very
  large Reynolds numbers. *Dokl. Akad. Nauk SSSR* **30**, 301–305.
- Betchov, R. (1956). An inequality concerning the production of vorticity in isotropic turbulence.
  *J. Fluid Mech.* **1**(5), 497–504. *(The isotropy relations behind the strain-skewness constant, §4.3.)*
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
  215–220. *(The projection formalism, the foundation of §3 and §8.)*
- Morrison, P. J. (1986). A paradigm for joined Hamiltonian and dissipative systems. *Physica D* **18**,
  410–419. *(The metriplectic bracket formulation; the reversible/irreversible split, §4.2, §8.)*
- Öttinger, H. C. (2005). *Beyond Equilibrium Thermodynamics.* Wiley. *(GENERIC; the
  reversible/irreversible split, §8.)*
