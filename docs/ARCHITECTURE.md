# Architecture

This is the design document for `GBGIsotropicTurbulence` — what the package is, how it is organized,
and *why* it is shaped the way it is. It is the spec: read it before any structural change, and do not
re-litigate a recorded decision (§11) without the user. `CLAUDE.md` is the terse working copy and defers
here; the rendered symbol glossary is [`docs/src/notation.md`](notation.md).

The document is self-contained — every symbol, mathematical or `code`, is introduced in plain language at
first use — and reads top to bottom. Mathematics follows the glossary's notation: the wavenumber vector
is ``\boldsymbol{\kappa}`` with magnitude ``\kappa``; the turbulent kinetic energy is ``k``; the scalar
diffusivity is ``\varkappa``; the integrating factor is ``\mathcal{E}``. Pope (2000) is a standard
reference for turbulence notation (§References).

---

## 1. Identity

> `GBGIsotropicTurbulence` **is** a small, focused pseudospectral direct numerical simulation (DNS) of
> homogeneous isotropic turbulence: one incompressible velocity field ``\boldsymbol{u}`` and one passive
> scalar ``\varphi`` on a triple-periodic box, advanced by interchangeable integrating-factor
> time-stepping, with Lagrangian particle probes and field sampling along their trajectories. It is a **library
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
# scheme, state, and initial condition — is built with defaults from a few numbers.
sim = Simulation(grid_points_per_axis = 128, viscosity = 5e-3;
                 velocity_forcing = ConstantPower(injection_rate = 0.1),
                 scalar = true, schmidt = 1.0)

# Spin past the transient: advance until the running dissipation ε(t) stops drifting
# (k(t) is deliberately not used — a fixed-injection forcing like this makes it ring).
warmup!(sim)

# Observe and advance. The callback fires after every iteration (and once at the start); it records
# what it wants and its return decides continuation — stopping is the caller's decision.
t_end = current_time(sim) + 20.0
run!(sim) do s
    accumulate_statistics!(my_stats, s)
    current_time(s) < t_end
end
```

The run layer holds the pieces of §4 in one `Simulation` value, chooses a stable timestep each
iteration from the advective-CFL condition over the cached maximum speed (§4.5), serves the deposited
observables from the deposit-driven `ObservablesCache` (§4.1), and runs the **observation-first
loop**: after every iteration, and once at the seeded ``t_0`` — ``n`` iterations, ``n+1``
observations — the callback reads the run and decides whether it continues (§11 decision 43).
Spin-up is the packaged `StationarityCriterion` observation, `warmup!` its one-line sugar: it
advances until the flow is statistically stationary, watching the running dissipation
``\varepsilon(t)`` and the velocity-derivative skewness ``S(t)`` — the small-scale signals that
settle last — rather than the kinetic energy a constant-energy forcing clamps flat; §4.7 gives the
exact stopping test. A forced flow must reach statistical stationarity before a structure function
or a PDF taken over it means anything.

The composable pieces stay fully exposed: a study that needs to run the loop by hand, swap a stage, or
interleave a bespoke measurement drops straight to §4. The run layer is a convenience over that machinery,
never a wall in front of it.

> **Status.** The run layer is implemented (module `SimulationRun`) and covered by tests; the example
> above runs as written — a forcing can be named operator-free (`ConstantPower(injection_rate = 0.1)`, a
> `DeferredForcing`) and `warmup!` detects stationarity. The API may still evolve, since setup ergonomics is
> the package's primary quality target, but it is no longer a sketch.

---

## 3. The organizing frame

A run is fixed by two independent things: **what** continuous problem you pose, and **how** you realize it
numerically. Beneath both lies a single organizing idea.

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
- the **Propagator** — the map that advances the state through time, realized by a choice of
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
  change beyond discretization error. Two schemes, two precisions, or two grid sizes for the *same* DNS
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
`Observables`, `Propagator`; the System's forcing, the discretized frame, the Lagrangian instruments, the
run layer, and the reference laws are named by their job. The rule is that **a role recurring at every
rung of the ladder wears its role name, while a concrete mechanism wears its job** — so the load-bearing
structure is legible at a glance, and no piece of plain machinery is dressed in theory it does not carry.

### 4.1 `State` and `SimulationDomain` — the field and the frame it lives on

Two modules separate *what evolves* from the *frame it evolves on*.

- **`SimulationDomain`** provides the discretized periodic box the run lives on — the reusable,
  read-only frame. Its concrete type is the **`FixedDomain`**, the fixed, unsheared cube, realized by
  the grid, the real–Fourier layout, the real-to-complex transform plans (one for the
  velocity, one for the scalar, one for the rank-2 strain tensor the skewness diagnostic needs), the
  spectral multipliers, ``\lvert\boldsymbol{\kappa}\rvert^2`` as a lazy radial kernel (in spectral
  space, ``-\nabla^{2}`` acts as multiplication by it; never materialized — evaluated per mode from
  the multipliers, with no array allocated — decision 38), and the dealias
  kernel from the run's chosen dealiasing strategy (the sharp ``2/3`` rule by default; every
  strategy's kernel is likewise a compressed per-mode symbol). The name marks what can vary: a `FixedDomain` has time-independent,
  separable wavenumbers, unlike the deferred sheared frame (`ShearedDomain`, §7). **Precision and backend enter here and flow everywhere
  from here**: `element_type` fixes the real element type
  ([`Float32`](@extref Julia Core.Float32) or [`Float64`](@extref Julia Core.Float64))
  and `array_type` the storage ([`Array`](@extref Julia Core.Array), `CuArray`, `ROCArray`), and every buffer is allocated `similar`
  to this frame, so a run is CPU/GPU-agnostic and single- or double-precision by construction.
- **`State`** owns the DNS realization of the Mori–Zwanzig State role. **`ResolvedFields`** is the
  record of the evolving fields in spectral representation — the velocity ``\hat{\boldsymbol{u}}`` and, when the run carries
  one, the scalar ``\hat\varphi`` — and the *single source of truth*: the physical velocity, vorticity, and
  scalar are functions of it, never independent state. No operation hangs
  on it; the generator advances it and the observables read it, both as external functions of
  ``(\hat{\boldsymbol{u}}, \hat\varphi)`` — the reification the Mori–Zwanzig lens demands, kept a bare
  carrier so the arrows stay primary (§11 decision 26). The **chart map** — the recovery of the
  physical representations — is not a package verb: the velocity and scalar are recovered by the
  source-preserving four-argument form of `GBGPeriodicFields`' `to_physical!` (the extra argument is
  a scratch field the transform consumes in the state's place) at the sites that consume
  them, and the derived vorticity by `Observables.vorticity_physical!` (decision 47). The values
  land in the **`ObservablesCache`** (its own
  module, `Cache`, after `Observables`): the storage each iteration
  fills at its end with its observables — the physical velocity, vorticity, and scalar, the
  maximum speed, and, when tracers ride the run, the particle velocities
  ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` — under the no-recompute rule (`docs/src/observables_cache.md` is the design page;
  §11 decision 40). A slot IS its producer's register: the step takes the chart arrays as its
  substage recovery registers mid-iteration (their epochs go to *scratch*, so a mid-iteration read
  throws instead of serving a stage intermediate), and the closing `deposit!` re-fills them at the new epoch
  from the state the step just produced. An accessor (`velocity_physical`, `vorticity_physical`,
  `scalar_physical`, the cached `max_speed`) serves the deposited value or throws; no read ever
  causes a computation.

  Freshness is tracked by one epoch counter per dynamical factor of the run — fields, particles.
  `step!` advances the fields epoch as it completes. An out-of-band mutation of the spectral state is
  the one freshness event the cache cannot detect itself, so it is declared through
  `fields_modified!` and followed by a `deposit!` before the run advances again (§11 decision 30). The `State` module's initial conditions seed the state:
  `random_solenoidal_velocity_spectral!` fills a divergence-free velocity with a large-scale spectral envelope,
  rescaled to a target ``k``, and `random_scalar_spectral!` fills a mean-zero scalar to a target variance. The
  per-step scratch is **not** state: the scheme's registers live with the scheme (`IntegratorBuffers`
  in `Propagator`, §4.5) and the assembly scratch with the generator (`ResolvedGenerator`, §4.2), each
  preallocated so a step allocates no field-sized memory (§9, invariant 4) and sized
  to the run (no scalar buffers when the run carries no scalar; GPU memory is tight). A `Simulation`
  composes the `ResolvedFields` and its `ObservablesCache`, and the time loop advances the state in
  place — each iteration a `step!` closed by the closing `deposit!`.

### 4.2 `Generator` — the evolution, split reversible and irreversible

`Generator` realizes the Mori–Zwanzig generator: the right-hand side the propagator advances. Its physical
inputs are bundled in `FlowConditions` — the viscosity ``\nu`` (``\mathrm{Re} = 1/\nu``), the Schmidt number
``\mathrm{Sc}`` (scalar diffusivity ``\varkappa = \nu/\mathrm{Sc}``), and the two forcings; ``\nu`` and
``\mathrm{Sc}`` set the diffusion, the forcings the source, and folding this bundle into `Generator` is what
adds the `Generator → Forcing` dependency. It carries a
**metriplectic seam** — a reversible part that conserves energy and an irreversible part that dissipates
it (§8) — and the numerical split is built to honor it. The incompressible momentum equation is
advanced in **rotational (Lamb-vector) form**: writing the convective term through the identity
``(\boldsymbol{u}\cdot\nabla)\boldsymbol{u} = \nabla(\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^2) - \boldsymbol{u}\times\boldsymbol{\omega}``
(with vorticity ``\boldsymbol{\omega} = \nabla\times\boldsymbol{u}``) and letting the Leray–Helmholtz
projection ``\mathbb{P}`` onto divergence-free fields absorb the pressure and the kinetic-energy gradient,
the equation becomes

```math
\partial_t\boldsymbol{u} = \mathbb{P} (\boldsymbol{u}\times\boldsymbol{\omega}) + \nu\nabla^{2}\boldsymbol{u} + \boldsymbol{f} .
```

Its three terms are the seam made explicit, and the time-stepping treats each according to its nature:

- **The reversible term.** The recoveries — the source-preserving four-argument `to_physical!` and
  the vorticity observable `vorticity_physical!` (decision 47) — produce the physical velocity and
  vorticity from ``\hat{\boldsymbol{u}}``; `velocity_rhs!` then assembles
  ``\mathbb{P} (\boldsymbol{u}\times\boldsymbol{\omega})``, dealiased by the ``2/3`` rule to remove the
  aliasing of the quadratic product (the pseudospectral method; Orszag & Patterson 1972, the ``2/3`` rule
  Orszag 1971). Rotational form is the cheap way to compute the advection spectrally, and under a sharp mask the
  truncation is exactly Galerkin, so the discrete advection conserves kinetic energy (`HouLi`, which
  only damps, is the deliberately non-conservative strategy),
  and incompressible Euler is genuinely Hamiltonian — so this term is the flow's *reversible*,
  energy-conserving generator, stepped explicitly.
- **The irreversible term.** The diffusion ``\nu\nabla^{2}\boldsymbol{u}`` is the flow's *irreversible*,
  net-dissipative generator. Being diagonal in Fourier, it is integrated *exactly* through the flow map
  ``\mathcal{E}(\boldsymbol{\kappa}) = \exp\!\bigl((A(\boldsymbol{\kappa}) - D\lvert\boldsymbol{\kappa}\rvert^2) \tau\bigr)``
  — the exact propagator of the linear part over an interval ``\tau`` (a Runge–Kutta stage substep
  ``d_i\Delta t``, or the whole step ``\Delta t``), with diffusivity ``D = \nu`` for the velocity and
  ``D = \varkappa = \nu/\mathrm{Sc}`` for the scalar, and ``A(\boldsymbol{\kappa})`` an optional linear
  forcing rate (the source, below). ``\mathcal{E}`` is **never materialized** (decision 39): the factor
  pair `velocity_integrating_factor` / `scalar_integrating_factor` supplies its *parameters* — the coefficient on
  ``\lvert\boldsymbol{\kappa}\rvert^2``, the rate's scale, the armed rate field — and the backend's
  fused exponential convolution evaluates ``\mathcal{E}`` per mode as it applies it, advancing the
  diffusion with no stability restriction and no kernel field built or stored. ``\mathcal{E}`` is a *propagator*, a flow map over a step, not a generator;
  keeping the two apart is exactly the Generator/Propagator distinction of §4.5.
- **The source.** ``\boldsymbol{f}`` is the forcing, an external drive that is neither seam half (§4.4).
  When a forcing is *linear* in the field (``\boldsymbol{f} = A \boldsymbol{u}``), its rate
  ``A(\boldsymbol{\kappa})`` is diagonal and linear like the diffusion, so it folds into the same
  exponential ``\mathcal{E}`` for exactness — and there it *injects* energy, ``\mathcal{E} > 1`` wherever
  ``A > D\lvert\boldsymbol{\kappa}\rvert^2``. So ``\mathcal{E}`` cross-cuts the seam: it carries the
  irreversible diffusion and, when the drive is linear, the source. The seam is a decomposition of the
  right-hand side, not of ``\mathcal{E}``.

The passive scalar rides the same generator: the source-preserving four-argument `to_physical!` recovers the
physical ``\varphi`` from ``\hat\varphi`` at each stage, and `scalar_rhs!` assembles the advection in conservative form
``-\nabla\cdot(\boldsymbol{u}\varphi)`` (equal to ``-\boldsymbol{u}\cdot\nabla\varphi`` since
``\nabla\cdot\boldsymbol{u} = 0``); the conservative form conserves the scalar mean exactly under the
``2/3`` rule.

The metriplectic reading is a **lens, not a literal thermodynamics**: incompressible isothermal flow
carries no genuine entropy — the dissipated kinetic energy simply leaves the model as untracked heat — so
the load-bearing content is the reversible/irreversible split of the right-hand side and the constraint it
puts on any closure: net dissipation lives in the diffusion term alone, so a subgrid model may only
*remove* energy through that half (§8).

The generator is **reified**: **`ResolvedGenerator`** bundles the `FlowConditions` with the assembly
scratch its evaluations write through (the quadratic products' spectral image, the `PhaseShift`
displaced-evaluation buffers, the per-mode forcing-rate arrays — in physical representation each
quadratic product forms in place over an operand's own register, §11 decision 41), behind a six-verb
protocol —
`prepare!` opens the step (advances each forcing's internal state, arms the linear rates),
`velocity_rhs!` / `scalar_rhs!` evaluate each field's explicit right-hand side at a stage state
(dealiased nonlinear term plus additive forcing source), `velocity_integrating_factor` / `scalar_integrating_factor` supply
each field's exact linear subflow, and `finalize!` closes the step (the post-step forcing projections).
The required core is `velocity_rhs!` and `velocity_integrating_factor`; `prepare!` and `finalize!`
always run, and do nothing observable only when the configured forcing's own hooks are the
`AbstractForcing` defaults. A scheme consumes the physics only through this protocol, so it can never assemble the
right-hand side from a mismatched intermediate — the class of the stage-ordering bug that motivated the
reification (§11 decisions 29, 31).

### 4.3 `Observables` — the measured functions of the state

`Observables` realizes the Mori–Zwanzig observables: the functions of the state that are measured. Each
states the physical quantity first, then the reduction that computes it:

- ``\texttt{kinetic\_energy} \equiv k = \tfrac{1}{2}\langle\lvert\boldsymbol{u}\rvert^2\rangle``
  and ``\texttt{dissipation} \equiv \varepsilon = \nu\langle\lvert\boldsymbol{\omega}\rvert^2\rangle``;
- ``\texttt{scalar\_variance} \equiv \langle\varphi^2\rangle`` and
  ``\texttt{scalar\_dissipation} \equiv \varepsilon_\varphi = 2\varkappa\langle\lvert\nabla\varphi\rvert^2\rangle``;
- `max_speed`, which sets the advective-CFL (one generic shared with `Cache`, where the cached read
  lives — the reduction is homed here, decision 46);
- ``\texttt{vorticity\_physical!} \equiv \boldsymbol{\omega} = \nabla\times\boldsymbol{u}``, the field-valued
  observable — the vorticity recovered in physical representation, whose cached read is
  `Cache.vorticity_physical` (decision 47);
- `derivative_skewness`, the classical marker ``S \approx -0.5`` of developed turbulence (an
  empirical, weakly Reynolds-number-dependent value — K41 implies a constant skewness but fixes no
  number), computed
  coordinate-free as the normalized third invariant of the strain rate ``\boldsymbol{S}``,
  ``3C_S\langle\det\boldsymbol{S}\rangle/\langle\boldsymbol{S}:\boldsymbol{S}\rangle^{3/2}`` with the exact
  isotropy constant ``C_S = \tfrac{4}{7}\sqrt{15/2}`` (Betchov 1956; reproduces the classical longitudinal
  skewness);
- ``\texttt{energy\_spectrum} \equiv E_n``, the halved `GBGPeriodicFields` radial spectrum (a
  per-shell energy, not the density ``E(\kappa)`` a model law gives), and `integral_scale`
  derived from it.

These are not incidental: they are the **fitness functionals** the comparison machine of §3 evaluates,
and the stationarity signals `warmup!` watches. They are also the *measured* half of the validation
harness whose *predicted* half is `Phenomenology` (§4.8).

### 4.4 `Forcing` — the source

Forcing is the System's energy-injection strategy — the source term ``\boldsymbol{f}`` of §4.2, and the one
deliberately designed-in extension point. `AbstractForcing` is the supertype; a forcing enters the
step through a small interface whose four methods each default to doing nothing:

- `prepare_forcing!` — advance internal state once per step (a stochastic process);
- `set_forcing_rate!` — for a forcing *linear* in the field (``\boldsymbol{f} = A \boldsymbol{u}``): fill the
  per-mode rate ``A(\boldsymbol{\kappa})``, folded into the integrating factor (exact, order-preserving);
- `add_forcing_source!` — add an additive source at each Runge–Kutta stage;
- `apply_forcing!` — apply a post-step projection or rescale.

The four hooks form one per-step lifecycle with a fixed order — `prepare_forcing!` and
`set_forcing_rate!` before the stages, `add_forcing_source!` at every stage, `apply_forcing!` after the
completed step — and the rate and the source are two channels of *one* forcing term (the exactly linear
part folded into ``\mathcal{E}``, the remainder added at stages). A strategy owns whatever scratch its
hooks need; none receives the scheme's buffers (§11 decision 32).

`NoForcing` (free decay), `BandRescaling` (hold a band's *or* the total energy fixed — a deterministic
clamp, fit for spin-up and amplitude-holding but not a faithful stationary sampler; its docstring
carries the Berendsen-class caveat, Bussi, Donadio & Parrinello 2007), `Linear`
(fixed-rate negative damping, Lundgren 2003), and `ConstantPower` (its rate reset each step to hold the
injection rate) — the two linear forcings folded into ``\mathcal{E}`` — are provided; a stochastic Eswaran–Pope
Ornstein–Uhlenbeck forcing is archived (§7). **One implementation serves both** the velocity (a vector
field) and the scalar (a scalar field), because these four methods are written through tensor-order-generic field
operators; the only field-specific step a forcing can need is the solenoidal (Leray) projection of the
velocity, and none of the built strategies needs it — each preserves a divergence-free velocity by
construction (the archived `StochasticOU`, which draws unconstrained noise, is the one that projects). Each forcing has an operator-taking constructor and an operator-free keyword form
(`ConstantPower(injection_rate = 0.1)`, a `DeferredForcing`) materialized when `Simulation` builds the frame, so a case
can name its forcing before the grid exists.

### 4.5 `Propagator` — the map that advances the state in time

`Propagator` realizes the Mori–Zwanzig propagator: the map that carries the state forward in time, built
on the generator's reversible/irreversible seam. Its numerical schemes are the Model-fibered part of the
Method (§3).

- **`AbstractIntegrator`** is the family of integrating-factor schemes dispatched by **`step!`**, which
  advances the velocity ``\hat{\boldsymbol{u}}`` and scalar ``\hat\varphi``, both in spectral representation, **together** through
  the same Runge–Kutta stages. Coupled stepping is deliberate: the scalar is passive, so time-accuracy
  needs both nonlinear terms evaluated at each stage's state; advancing the velocity fully and the scalar
  afterward would drop the substage velocities and degrade the coupling to first order.
- **`IFLowStorageRK3`** (the Williamson 1980 2N / RKW3 workhorse) is third-order and imaginary-axis stable;
  **`IFRK2`** (Heun) is a cheaper two-stage option that is imaginary-axis unstable and leans on viscous
  damping. The [`recommended_cfl`](@ref) helper gives each scheme its conservative advective-CFL ceiling
  ``C_{\mathrm{CFL}}`` (for
  ``\Delta t = C_{\mathrm{CFL}} \Delta x/\max_{\boldsymbol{x}}\lvert\boldsymbol{u}\rvert``), which the run layer uses with `max_speed` to choose
  ``\Delta t``.
- **`IntegratorBuffers`** is the scheme's own per-step scratch — the Runge–Kutta stage registers,
  and nothing in physical representation (the substage recoveries write into the cache's slots,
  decision 40) — built by `allocate_buffers` dispatching on the
  concrete scheme, so each allocates exactly its working set. The right-hand-side *assembly* scratch
  lives with the generator on the `ResolvedGenerator` (§4.2), and the start-of-step physical fields are
  the observation cache's charts (§4.1): a `step!` is stage arithmetic over the generator protocol and
  the scheme's registers, nothing more. None of this scratch is state (§11 decisions 26, 30, 31).

### 4.6 `Particles` — Lagrangian instruments

Particles are **instruments** — probes of the turbulence — not a second physics. A particle is a
state-carrying trajectory object: today a tracer (position ``\boldsymbol{x}``); the deferred ladder is
inertial (``\boldsymbol{x}, \boldsymbol{v}``) and oriented (``\boldsymbol{x}, \boldsymbol{v}, \boldsymbol{L}``)
probes (§7). `Tracers` holds positions and a chosen interpolation scheme — trajectory **state** only,
with the trajectory scheme's registers held apart in a `ParticleIntegratorBuffers` allocated per
scheme, exactly as `ResolvedFields` is held apart from `IntegratorBuffers` on the field side
(decision 50). The default scheme, `EndpointHeun`, is Heun-in-time on
the velocity at the iteration's two endpoints: ``\boldsymbol{v}_1`` is the **trajectory
sample** ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` the previous closing deposit deposited — the genuine
Lagrangian velocity, held in `Tracers.particle_velocities` and recorded in the observables cache
(against BOTH epochs, since it is a function of the state and the positions together; read through
`particle_velocities`, §11 decision 42) — and ``\boldsymbol{v}_2`` interpolates the just-deposited
``\boldsymbol{u}(t_{n+1})`` at the Heun **predictor** positions, which no tracer ever occupies:
`ParticleIntegratorBuffers.predictor_velocity` is a stage register of the scheme, never a sample of the flow, and is
not readable. After the push, `record_trajectory_velocity!` records the new sample at the new
positions from the same deposited field, completing the iteration's deposits; `interpolate_at_particles!` reads any field along the
trajectories for Lagrangian statistics.

The two-verb split is what keeps an ``M``-point instrument at ``M``-point cost: recording the sample
onto the tracers stores ``M\times3`` values where retaining the endpoint field would cost an
``N^{3}\times3`` resident buffer and copy. Tracked and untracked runs therefore have identical
field-scale residency and per-step traffic — the zero both audits assert. (One tempting reuse is
recorded as **forbidden**: ``\boldsymbol{v}_2 \approx \boldsymbol{u}(t_{n+1},\boldsymbol{X}^*)``
differs from the next sample only at ``\mathcal{O}(\Delta t^{2})``, so reusing it as the next
``\boldsymbol{v}_1`` looks like a free interpolation saved — but it corrupts the recorded observable
the Lagrangian statistics accumulate. Never approximate the thing you measure.)

Their **numerics are first-class**, on the same footing as the field schemes — and pluggable in the
same way: `AbstractParticleIntegrator` is the family, `allocate_buffers(scheme, tracers)` builds its
registers. Two axes matter: the
trajectory scheme — today the single second-order `EndpointHeun`, with higher-order schemes the
studied future axis — and the sampling-consistency axis, the interpolation scheme's order relative to the field's
spectral accuracy (`CatmullRom` by default, higher-order `LalescuSpline` / `LagrangeSpline` available).
When the inertial and oriented probes arrive, the integrating-factor split carries over for the
*translational* stiff drag (field viscosity and a particle's linear or matrix drag are the same
linear-exact move), while **orientation dynamics on the rotation group is a distinct geometric
scheme** — the reversible generator of §8 again — so the split does not naively unify all of it.

### 4.7 `SimulationRun` — the front door

A `Simulation` value bundles what a case advances: the `FixedDomain`, the `ResolvedFields` state (the
fields ``\hat{\boldsymbol{u}}`` and ``\hat\varphi``, in spectral representation, the generator acts on), the `ObservablesCache`
observation cache, the `ResolvedGenerator` (carrying the `FlowConditions`), the `IntegratorBuffers`
scheme registers, the chosen `AbstractIntegrator`, any `Tracers`, a stored CFL ceiling, and a clock.
Over it:

- **`Simulation(...)`** — the assemble-with-defaults constructor: from a grid size and a forcing it
  builds every piece of §4.1–§4.6, seeds a divergence-free initial condition, and picks the default
  scheme. The viscosity is set from the grid by default — the highest Reynolds number consistent with the
  chosen resolution criterion `κ_max_η` (decision 20) — with an explicit `viscosity` the opt-in override.
  Setup is a few numbers.
- **`advance!(sim)`** owns one iteration: ``\Delta t`` from the scheme's CFL over the cached
  maximum speed (scalar arithmetic — the previous closing deposit measured it), `step!`, the closing `deposit!`,
  the tracer push on the sample and the deposited endpoint field, the new sample, and the deposit-
  completeness check. **`run!(callback, sim)`** is the observation-first loop over it: the callback
  observes the run after every iteration (and once at the seeded ``t_0``) and its `Bool` return decides continuation —
  stopping is the caller's decision on observables, never a run option (§11 decision 43).
- **`StationarityCriterion`** is the packaged spin-up observation — stationarity detection on the
  running dissipation ``\varepsilon(t)`` and the velocity-derivative skewness ``S(t)`` (a
  trailing-window flatness test that **gates** on ``\varepsilon`` rather than on the clampable
  ``k(t)``; ``k`` is still measured, to normalize the eddy-turnover clock ``\Delta t \varepsilon/k``.
  When the scalar is forced, ``\langle\varphi^2\rangle`` must settle too) — and **`warmup!(sim; ...)`**
  its one-line sugar. A fixed budget is a three-line callback, not a run option.
- **A `Simulation` is a container, not a reading surface** (decision 49). The state is read through
  `sim.state` and the deposited observables through `sim.cache`, each by the accessor that owns it —
  `kinetic_energy(sim.state.velocity_spectral)`, `velocity_physical(sim.cache)`,
  `particle_positions(sim.tracers)`. 
- **`current_time(sim)`** and **`current_step(sim)`** report the clock, and the observables applied to
  `sim.state` (e.g. `kinetic_energy(sim.state.velocity_spectral)`, `dissipation` on the recovered vorticity) the
  current-state diagnostics, for a callback to read.

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
`DealiasingStrategy`: **a law family is an abstract type, each parametrization a named preset** — usually a
concrete subtype carrying its fitted coefficients and provenance, or (for the composed velocity spectra)
an alias naming the `ModelSpectrum` specialization that carries its two roll-off factors, so `isa`
holds on the preset name either way (decision 55) — implementing one small interface: evaluate the law at its
argument (``\kappa``, ``r``, ``\mathrm{Re}_\lambda``) given a `FlowParameters` bundle; report its
`provenance` (the citation and validity range); and eventually `fit` itself to data. Choosing a law is
choosing the preset (`Pope2000` versus `VonKarman1948`) and optionally overriding its coefficients
(`Pope2000(; C_K = 1.6)`, the published fit being the default). Provenance is first-class — the comparison
needs a law's validity range to be fair, and it is the single source of the citation.

**Naming is a three-level handle**, because one author publishes many models across years and quantities:
the **quantity is the submodule** (`Spectra.Pope…` versus `StructureFunctions.Pope…`), the **paper is the
author-year handle** (`Pope2000`, first author's surname, the full list in `provenance`), and a **same
author-year-quantity collision takes a trailing letter** (`Pope2014a`, `Pope2014b`). The validating case
would be Kolmogorov 1941 across two submodules — `StructureFunctions.Kolmogorov1941` (the 2/3 and 4/5
laws) and a spectrum counterpart `Spectra.Kolmogorov1941`, were one added — separated by the submodule
alone. The full
handle `Phenomenology.Spectra.Pope2000` reads like a citation and is unique by construction.

**Submodules are cut by representation, so they stay few** while the models multiply as subtypes:

- **`Spectra`** — functions of ``\kappa`` (velocity ``E(\kappa)``, scalar ``E_\varphi(\kappa)``),
  **composed**: an inertial core ``C_K \varepsilon^{2/3}\kappa^{-5/3}`` times a swappable large-scale
  factor ``f_L(\kappa L_{11})`` and dissipation-range factor ``f_\eta(\kappa\eta)``, a named preset fixing a
  published triple.
- **`StructureFunctions`** — functions of ``r`` (the ``D_{L\dots}(r)`` laws and, sharing the
  representation, any two-point correlation law when one is added).
- **`Scalings`** — the dimensionless numbers and their ``\mathrm{Re}_\lambda`` trends: the Kolmogorov
  constant ``C_K`` (`Sreenivasan1995`), the normalized dissipation constant ``C_\varepsilon``
  (`Sreenivasan1998`), and the box-normalized dissipation group ``k/(L\varepsilon)^{2/3}`` (`Li2008`,
  which the run layer inverts to set the viscosity). The derivative skewness, the flatness, the
  Lagrangian ``C_0``, and the mechanical-to-scalar timescale ratio are forward-looking additions to the
  family, not yet built.

Three exist now — enough for the validation checklist — and the count caps near six: `PDFs`, `Decay` (``k \sim t^{-n}``),
and `Lagrangian` are named future seams, not owed — named here rather than in §7, which lists the
deferred *capabilities* rather than the submodules that would carry them. A single `FlowParameters` bundle carries the
quantities a law reads (``\varepsilon``, ``\nu``, ``L_{11}``, ``u'``, ``\mathrm{Sc}``, ``\varepsilon_\varphi``),
with the derived scales (``\eta``, ``\tau_\eta``, ``\lambda``, ``\mathrm{Re}_\lambda``, ``\varkappa``) as
helpers — the analogue of the `FlowConditions` and `FixedDomain` bundles.

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

`SimulationDomain → State → Observables → Cache → Forcing → Generator → Propagator → Particles →
SimulationRun`.
Cross-module access is through explicit `using ..Module: name` lists; `Phenomenology` (§4.8) leads this
order as the dependency-light leaf the initial-condition and validation consumers read.
Statistics live consumer-side of this package too: the sampling in `Particles` and the observables in
`Observables` produce the *samples*, and a statistics bridge that streams them to `GBGStreamingStatistics`
is deferred (§7).

---

## 5. The consumer boundary — what belongs here, and what does not

`GBGIsotropicTurbulence` owns the turbulence-specific glue and delegates everything domain-neutral. The
dividing line is **domain-neutrality**, not "thinness":

- **To `GBGPeriodicFields`** — every field operation: the transforms, `curl!` / `cross!` / `divergence!`,
  the Leray–Helmholtz projection `helmholtz_projection!` (``\mathbb{P}``), `convolve!` and the dealias/band kernels,
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

- **Both precisions are supported equally, with no privileged default.** `Float32` buys twice the
  grid per byte and roughly twice the throughput on a consumer GPU; `Float64` buys the accuracy
  margin a long integration or a sensitive diagnostic may need. Which one a run wants is a fitness
  question, settled by test rather than by a house default. The element type
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
  fidelity, scheme, precision, footprint, and closure; the *sufficiency frontier* (the cheapest
  realization that still passes) is a deliverable of the tool.

This is why the `GBGPeriodicFields` element-type genericity and GPU-first, allocation-free discipline are
load-bearing here: they are what make precision and backend free to vary, and they are what keep the state
a compile-time product of concretely-typed buffers (§9, invariant 4). "Low footprint" is the default
working point on a studied axis, not a universal law.

---

## 7. Deliberately deferred

These are **named so they are not precluded, and deliberately left un-abstracted**: no extension point or
generalization is built for them until a second concrete case forces the abstraction. None is a gap.

- **Stochastic (Eswaran–Pope OU) forcing** — `StochasticOU`, a band-limited Ornstein–Uhlenbeck process
  added to the RHS. *Built and validated, then archived* from the public surface — un-exported, and
  absent from the rendered API pages, though its docstring is intact — to be re-added; it owns its noise scratch (decision 32), and its host-side random
  increment is the one allocation-free exception
  (invariant 4), so the re-add is gated on a GPU-tuned generator (Eswaran & Pope 1988).
- **Inertial and oriented particles** — ``(\boldsymbol{x},\boldsymbol{v})`` with matrix drag, then
  ``(\boldsymbol{x},\boldsymbol{v},\boldsymbol{L})`` with torque. The translational drag reuses the
  integrating-factor split; orientation needs a geometric scheme (§4.6, §8).
- **The sheared frame (Rogallo), a `ShearedDomain`.** A uniform mean velocity gradient makes the
  wavenumbers time-dependent (``\mathrm{d}\boldsymbol{\kappa}/\mathrm{d}t = -\boldsymbol{A}^{\!\top}\boldsymbol{\kappa}``)
  and non-separable — the `SimulationDomain` counterpart to `FixedDomain` (§4.1). This is
  the one future with a concrete `GBGPeriodicFields` dependency: its separable per-axis multipliers cannot
  hold a sheared lattice, so it is a bounded extension *there* (rule 1 of §5), not a job here.
- **The Model ladder beyond DNS** — a large-eddy Model (filter the DNS, model the subgrid stress) and a
  filtered-density-function or moment Model (§8). Each is a coarser projection on the ladder of §3, and the
  four roles are already carved to receive it — but, per invariant 9, no generality is built until a second
  rung forces it. Each is discriminated from DNS by statistical commutation; the canonical acceptance test
  is the relaxation of a two-mode scalar distribution (a micromixing benchmark). The natural first
  *spectral* rung is a Chollet–Lesieur eddy viscosity ``\nu_e(\kappa \mid \kappa_c)`` at the truncation
  wavenumber ``\kappa_c`` (Chollet & Lesieur 1981) — architecturally a **per-mode linear rate**, a
  negative linear-forcing citizen folded into the integrating factor exactly as the armed forcing rate
  is, with the plateau–cusp profile resident and only its ``\sqrt{E(\kappa_c)/\kappa_c}`` scale updated
  per step from one shell reduction. The Hou–Li filter at ``\nu = 0`` is its crude implicit sibling
  (numerical-dissipation LES), with the known cutoff-bottleneck caveat.
- **The statistics bridge** — the sampling-to-`GBGStreamingStatistics` path (Eulerian field samples and
  Lagrangian trajectory samples in, streamed summaries out).
- **Alternative dealiasing and nonlinear forms (partly built).** `DealiasingStrategy` now *owns the
  dealiased nonlinear assembly* — ``\hat{\boldsymbol{u}}`` (and ``\hat\varphi``) in, the dealiased term
  out — so a strategy may restructure *how* the product is computed, not merely filter its output. The
  sharp ``2/3`` rule and the smooth Hou–Li filter kernel-multiply the single realization; **`PhaseShift`**
  (decision 27) averages a half-cell-displaced evaluation to cancel aliasing and truncates spherically to
  ``\tfrac{\sqrt{2}}{3}N\cdot\tfrac{2\pi}{L}``, at ``2\times`` the transforms. Still deferred siblings of the same assembly:
  ``3/2`` zero-padding, and the **skew-symmetric** momentum form (which reorganizes the quadratic product
  to conserve energy in the discrete equations). The assembly touches only the `Generator` and its
  scratch, never the State (§4.1); the rotational form + spherical ``2/3`` stays the lean default.
- **A temporal-accuracy step control.** The step is set today by the advective **CFL** — a
  stability-calibrated, conservative ceiling with a manual `cfl` override — and nothing adapts it to a
  target *temporal* accuracy. An embedded-error or PI step controller, distinct in purpose from the
  stability CFL, would make temporal accuracy a studied fitness axis beside precision and footprint (§5).
  Deferred: HIT runs are typically stability-limited near the CFL ceiling, so a fixed step at the CFL is
  rarely the accuracy bottleneck.
- **User-selectable FFT planner effort.** `GBGPeriodicFields` lets each transform plan carry a backend
  planner flag and time limit — the `fft_flags` and `fft_timelimit` keywords of `FieldTransformPlans` —
  yet `FixedDomain` (§4.1) builds its velocity, scalar, and tensor plans without them, so every run takes
  the planner default (`FFTW.ESTIMATE` on the CPU path) and neither the domain nor the `Simulation` front
  door exposes an override. Closing it is a two-keyword passthrough, deferred on cost/benefit: the
  transform is the dominant per-step cost, so a one-time `FFTW.MEASURE` / `FFTW.PATIENT` planning search
  is a genuine performance lever beside the precision and footprint axes (§5) — but that search is an
  FFTW planning concept that pays off on the **CPU** path, IT's development-and-small-run platform, not
  the GPU-primary production target (invariant 4), where the plan is effectively fixed. It is wired when a
  long CPU campaign makes the search worth the added front-door surface — named for the planning-effort
  choice a user makes, not the raw backend flag.
- **The ``\nu = 0`` truncated-Euler experiment — an scheme and dealiasing oracle.** At zero
  viscosity (accepted today; the integrating factor degenerates to the identity) the sharp-masked
  assembly is the exact Galerkin truncation of the Euler equations, which conserves kinetic energy in
  continuous time — so measured energy drift isolates the time scheme alone: a per-scheme
  conservation and order-of-accuracy test (the drift must scale with the scheme's order), a second
  witness that the sharp strategies are exactly Galerkin (an alias residue breaks the detailed
  conservation of the retained triads), and a direct measurement of the Hou–Li filter's effective
  dissipation (the one deliberately non-conservative strategy). The long run is a validation target of
  its own: the truncated system thermalizes toward absolute equilibrium — an equipartition
  ``E(\kappa) \propto \kappa^{2}`` tail growing from the cutoff, the thermalized tail acting on the
  large scales like an eddy viscosity while it grows (Cichowlas et al. 2005). It is not a turbulence
  run — the dissipation-based diagnostics degenerate (``\varepsilon \to 0``, ``\mathrm{Re}_\lambda``
  undefined) — and it is deferred as a *test*, not a capability.

---

## 8. Lenses and prior art

The package makes real theory legible. One framework — **Mori–Zwanzig — is its foundation** (§3); the rest
are lenses read through it. Nothing in the *numerics* is load-bearing on the subordinate lenses — the
arithmetic would be identical had they never been named — but the *architecture* is founded on the
Mori–Zwanzig decomposition, which is exact and so can carry that weight. The lenses organize
*understanding* and set what the tool is built to *investigate*, not assume.

- **Mori–Zwanzig — the foundation, elaborated.** §3 states the decomposition; here is its machinery. A
  projection ``\mathcal{P}`` splits the full state into a resolved part and the rest, and applying it to the
  exact dynamics gives the resolved variables a **generalized Langevin equation** (Mori 1965;
  Zwanzig 1973): a streaming term (the
  projected drift), a **memory integral** over a kernel ``K(t-s)`` carrying the history the projection
  discarded, and a **colored-noise** term living in the unresolved subspace. A Model is a choice of
  ``\mathcal{P}`` and a closure that approximates that kernel and that noise; DNS is the identity
  projection, for which both vanish, so it needs no closure. The memory kernel ``K`` is the precise content
  of the tendency a coarse state cannot supply on its own (§3), and modeling it is the closure problem the
  tool exists to test.
- **Open systems / non-equilibrium — a reading of the projection.** The Mori–Zwanzig cut *is* the
  open-system system/environment split: the **resolved** variables are the system, the projected-out
  variables the environment, which survives only as the memory + noise above. A driven-dissipative flow is
  an open system in a non-equilibrium steady state — energy injected by the forcing (an energy *reservoir*,
  the source of §4.2), dissipated to the unmodeled viscous *bath* (the sink), balanced at stationarity. The
  lens carries its own caveat: whatever a model *retains* of the environment — a stochastic forcing's
  internal state, a closure's subgrid degrees of freedom — is not the environment but the finite
  **Markovian surrogate** kept on the system's own side, a *modeled* degree of freedom; so it homes, when
  built, as a modeled slot on the one `State`, never a separate "environment state".
- **The commuting square — the modeling ideal.** With ``\Pi`` a coarse-graining and ``S`` a flow map, one
  would like ``\Pi\circ S_{\mathrm{fine}} = S_{\mathrm{coarse}}\circ\Pi``. It cannot hold pathwise: the coarse
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
  has no genuine entropy (§4.2). The term is Morrison's (1986; metric + symplectic); Öttinger's (2005) GENERIC
  is the same structure.
- **Renormalization / scale invariance — a hypothesis, never a foundation.** Small-scale universality is
  what would make closure constants transferable, but it is approximate (intermittency), it fails for
  scalar small scales (persistent gradient anisotropy), and the unclosed terms are *conditional* quantities
  that re-import the large scales. So the tool is built to *test* how universal a closure is, per regime,
  not to assume it. This is the general charter: **the architecture investigates the physics; it must not
  assume it** — the same discipline as the model-free statistics it consumes.
- **The skew-product tower — what a `Simulation` is.** The composite system factors as a tower
  ``t \to`` forcing noise ``\to`` fields ``\to`` particles: the generator is block lower-triangular
  (each row reads only itself and the rows above — the fields never read the tracer positions, the
  clock reads nothing), so the flow is a skew product and `advance!` is its Gauss–Seidel sweep in
  topological order (step the fields, refresh the observation, push the tracers, tick the clock).
  Triangularity is what licenses the composed propagator — splitting error cannot propagate *up* the
  triangle — and it gives every state slot a litmus: **the restart record holds exactly what the flow
  map needs** (``\hat{\boldsymbol{u}}``, ``\hat\varphi``; the tracer positions; a stochastic
  forcing's internal state — the extended-phase-space discipline of molecular dynamics' thermostats);
  the observation cache holds spent compute, reconstructable from the record (delete it and the
  trajectory is unchanged); and the clock and output cursors are the experimenter's logbook. The
  `ObservablesCache` charts are the tower's *algebraic* variables — solved, never integrated — and their
  per-factor epochs inherit the triangle: a chart is stale against exactly the factors it reads.

---

## 9. Invariants — the deliberate absences

The public surface and these absences are the spec. Do not add a capability "for completeness"; a missing
one usually encodes a decision.

1. **No physical units.** Quantities are in box units; control is by ``\mathrm{Re}`` (through ``\nu``)
   and ``\mathrm{Sc}``, and the reference constants a run is judged against (``C_K``, ``C_\varepsilon``,
   ``G``) are dimensionless groups.
2. **No field or statistics machinery reimplemented.** Field operations come from `GBGPeriodicFields`,
   estimators from `GBGStreamingStatistics` (§5).
3. **No privileged precision or backend.** ``T`` and the array type flow from the frame; both precisions
   and CPU/GPU are first-class (§6).
4. **Allocation-free stepping over a compile-time state — with an audited footprint.** A time step allocates no field-sized memory over
   the preallocated `IntegratorBuffers` — load-bearing for GPU hot loops. The evolving state is a **compile-time
   product of concretely-typed buffers** (a parametrized record the compiler specializes), never a
   runtime-heterogeneous container — the discipline that keeps the step type-stable and device-generic, and
   that lets the state grow (a scalar today, a coarser Model's extra fields tomorrow) to more slots at no
   runtime cost. **Each scheme allocates exactly its working set:** `allocate_buffers` dispatches on the
   concrete scheme and builds only the registers that scheme writes — there is no over-allocating
   `::AbstractIntegrator` fallback, so a scheme with no method is a hard error, never a silent superset
   (an `IFLowStorageRK3` run does not carry `IFRK2`'s two predictor registers).
5. **GPU-first, single-node, backend-agnostic.** Shared-memory only; no distributed or multi-GPU scope
   (inherited from `GBGPeriodicFields`).
6. **No baked-in physical model, closure, or universality assumption.** The tool investigates these; it
   does not assume them (§8). The Mori–Zwanzig foundation is exempt because it is *exact*, not a model — a
   projection is an identity, and what remains modeled is the closure the tool is built to test (§3).
7. **A library, not a framework.** The run layer is a convenience over exposed pieces (§2, §4.7), never a
   mandatory shell.
8. **The scalar is denoted ``\varphi``**, never ``\theta`` — in code, mathematics, and prose.
9. **Deferred futures are accounted for, not owed** (§7); no speculative extension points.

---

## 10. Conventions

- **Docstrings are operator-first, then scheme.** State the continuous operator or PDE term and its
  exact/ideal form, *then* the discrete realization — as `velocity_integrating_factor` leads with
  ``\partial_t f = D\nabla^{2} f`` before ``\mathcal{E}(\boldsymbol{\kappa})``, and `velocity_rhs!` with
  the Lamb-vector identity before the pseudospectral product. This is the turbulence analogue of the
  siblings' physical-form-first / estimand-first rules.
- **Coordinate-free where a coordinate-free form exists.** Homogeneous isotropic turbulence is
  statistically isotropic — no preferred direction — so a diagnostic or computation that picks a coordinate
  axis imports a spurious direction-dependence; state the **rotation-invariant** form, not an axis
  projection. The reference is `derivative_skewness`: the normalized third invariant of the strain rate
  ``\boldsymbol{S}``, not the axis-picking longitudinal velocity-derivative skewness (decision 17).
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
  nontrivial claims are *dynamical* — the exactness of ``\mathcal{E}``, the order of the scheme,
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
  field; ``k`` vs the spectrum ``E(\kappa)``); an operator with its parameter (``\mathcal{E}`` vs ``\nu``;
  ``\mathbb{P}`` vs ``\mathcal{P}``); a rate with its time-integral; a spectral density ``E(\kappa)`` with an
  energy. Type each object from the code and expand the statement — the physics mirror of the sibling
  backends' type-error guard (`GBGStreamingStatistics`' density-vs-measure, estimator-vs-estimand).
- **The `/check-docs` battery.** Documentation quality is enforced by a full matrix — (Correct /
  Self-contained / Notation / Formatted / Current / Cited / variant-pairs) × (every surface:
  `ARCHITECTURE.md`, every `src/*.jl` docstring, every `docs/src` page) — run to completion in one pass
  (`.claude/commands/check-docs.md`). *Correct* extends to physical-formula and normalization checking
  (the ``1/N``, the ``2\varkappa``, the ``\tfrac{1}{2}`` in the energy, Parseval factors) and to the
  category/type-error class above. Two build lints (`lint_inline_math`, `lint_notation_variants`) and
  `checkdocs = :exports` are the mechanical backstop.
- **Citations** follow author–year; the full references are §References. Never cite an inaccessible source;
  the material under `inspiration/` is private and never referenced. A reference *block* of two or more
  citations is a bullet list — one citation per line — never a semicolon-joined paragraph.

---

## 11. Decision log

Append-only; each entry stands on its own. Dates in `YYYY-MM`.

1. **(2026-06) Integrating-factor split with exact diffusion.** The stiff viscous/diffusive part is
   integrated exactly by ``\mathcal{E}(\boldsymbol{\kappa})``; only the advection is explicit. Removes the
   diffusive stability limit and preserves scheme order under linear forcing.
2. **(2026-06) Rotational (Lamb-vector) form for the advection.** Cheap spectral advection; the
   reversible generator of the geometric lens. *(The energy conservation this entry originally
   credited to the form is really the sharp mask's: under a truncating band the truncation is exactly
   Galerkin, so the discrete advection conserves kinetic energy — `HouLi`, which tapers rather than
   truncates, is deliberately non-conservative. §4.2.)*
3. **(2026-06) `IFLowStorageRK3` (Williamson 2N / RKW3) is the default; per-scheme CFL.** Third-order,
   imaginary-axis stable, two registers per field; `IFRK2` kept as a cheaper, viscously-stabilized
   option.
4. **(2026-06) One passive scalar ``\varphi``, coupled in-stage.** Velocity and scalar advance through
   the same RK stages to keep the passive coupling time-accurate.
5. **(2026-06) Lagrangian tracers by Heun-in-time; interpolation scheme is the accuracy axis.** The
   scheme uses the start- and end-of-step velocities the solver already produces.
6. **(2026-07) Statistics extracted to `GBGStreamingStatistics`.** The conditional/transition-density
   machinery is domain-neutral and shared across turbulence, cloud microphysics, and molecular
   dynamics; it is consumed, not owned (§5).
7. **(2026-07) Organising frame is specification × realization, not three co-equal axes.** Method is
   fibered over Model; the two research disciplines (method-independence, statistical commutation) map
   onto the two kinds of variation (§3). *(Revised from an earlier "System × Model × Method" framing
   after an adversarial review.)*
8. **(2026-07) Mori–Zwanzig is the central lens, not a foundation.** The code does not depend on it;
   it organizes understanding and is demonstrated, not assumed. The other lenses (GENERIC, the
   commuting square, RG) are read through it, and RG/universality is a hypothesis to test (§8).
9. **(2026-07) Precision and footprint are studied axes.** Both precisions supported equally, the
   working point chosen by fitness test; the sufficiency frontier is a deliverable (§6).
10. **(2026-07) Particles are instruments with first-class numerics.** The role is a probe; the
    trajectory scheme and sampling-consistency are fitness-tested Method work (§4.6).
11. **(2026-07) The run + warm-up layer is a first-class, present concern.** Ease of setup and running
    is the primary quality metric, so the ergonomic front door is built now, not deferred (§2, §4.7).
12. **(2026-07) Single `ARCHITECTURE.md` (consumer archetype) + `docs/src/notation.md`; no
    `FORMALIZATION.md`.** IT is an operator consumer; its claims are dynamical and pinned by tests
    (§10).
13. **(2026-07) `warmup!` detects stationarity on the dissipation ``\varepsilon`` and the
    velocity-derivative skewness, not the kinetic energy.** ``\varepsilon(t)`` (the small scales, which
    settle last) must stop drifting over a trailing window; ``k(t)`` is avoided because a constant-energy
    forcing clamps it and a fixed-injection forcing makes it ring. The skewness ``S(t)``
    (`derivative_skewness`) must also have plateaued with ``\lvert S\rvert`` above a floor — the
    "real turbulence yet" gate, whose default floor is a permissive one to be raised toward the
    developed ``\lvert S\rvert \approx 0.5`` when the run must be strict (``S`` runs from ``0`` toward ``\approx -0.5``). When the scalar is
    forced, ``\langle\varphi^2\rangle`` must flatten too — the scalar reaches stationarity after the
    velocity. A fixed turnover/time/step budget is the explicit alternative. *(Follows the warm-up
    literature.)*
14. **(2026-07) Operator-free forcing construction.** `ConstantPower(injection_rate = 0.1)` (and the other banded
    forcings) return a `DeferredForcing` capturing the parameters, materialized into the concrete
    `AbstractForcing` once `Simulation` builds the domain — so a case names its forcing before the grid
    exists. The operator-taking constructor is unchanged. *(Originally the keyword was `power` and the
    return type `ForcingSpec`; both since renamed — `power` → `target`, `ForcingSpec` → `DeferredForcing`
    — decision 25.)*
15. **(2026-07) `BandRescaling` can hold the band *or* the total energy (`over = :band | :total`).**
    `:band` fixes the forced band's energy and lets the total float; `:total` rescales the band
    to pin the whole-field energy — hence the r.m.s. velocity ``u'``, setting the scale of
    ``\mathrm{Re}_\lambda`` (whose value still fluctuates with ``\varepsilon``) — the
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
    `combine!` (axpby), `weighted_inner`, `symmetric_gradient`, `det` — and wired in. The `combine!` op replaces
    the hand-rolled RK/OU `field_data` broadcasts (charter invariant 2). The `weighted_inner` op fuses the
    per-step band energy in the forcings and expresses `scalar_dissipation` as the Dirichlet energy, with
    no ``\nabla\varphi`` materialized. And `derivative_skewness` becomes the normalized third invariant of
    the strain rate ``\boldsymbol{S}``, ``3C_S\langle\det\boldsymbol{S}\rangle/\langle\boldsymbol{S}:\boldsymbol{S}\rangle^{3/2}``,
    with the exact isotropy constant ``C_S = \tfrac{4}{7}\sqrt{15/2}\approx 1.5649`` reproducing the classical
    ``S\approx-0.5`` — the axis-picking longitudinal form was coordinate-dependent, the invariant is the
    honest object, and `symmetric_gradient` forms the strain without the full velocity-gradient tensor.
    The physical strain tensor is unavoidable (cubic ⇒ non-Parseval), so this diagnostic allocates its
    rank-2 buffers per call (sampling cadence) rather than keeping them resident — footprint over compute.
18. **(2026-07) `Phenomenology` — a reference-law library, author-year naming, extraction-bound.** A new
    submodule (§4.8) collecting the established turbulence phenomenology — model spectra, structure-function
    laws, dimensionless-constant fits — as one strategy family per quantity: each law family an abstract
    type, each parametrization an author-year preset (`Spectra.Pope2000`), disambiguated on three axes
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
    `Simulation` to a `Phenomenology` `FlowParameters` (``\nu``, ``\varepsilon``, ``u'``, ``L_{11}`` from the
    measured state), and `validate_spectrum(sim, model)` compares the measured spectrum against a model
    spectrum evaluated at that state, returning a named tuple of the measured and predicted spectra and
    their relative ``L^2`` discrepancy. This realizes the
    comparison-machine path of §3 for spectra — the measured half is a `GBGPeriodicFields` reduction, so
    no `GBGStreamingStatistics` bridge is needed for it. The structure-function and scaling-constant
    paths (via `radial_correlation` and the scalar diagnostics) share the shape and are deferred.
20. **(2026-07) Resolution-based `viscosity` — the run layer *consumes* a `Phenomenology` law to build a
    run.** `Simulation` now sets ``\nu`` from the grid by default (no `viscosity`): it reads the
    dissipation the box sustains from the box-normalized dissipation law `Scalings.Li2008`
    (``k/(L\varepsilon)^{2/3} \approx 0.9``, a box-normalized group — distinct from the classical dissipation anomaly ``C_\varepsilon = \varepsilon L_{11}/u'^3`` on the integral scale, related only on a common length by ``G = \tfrac{3}{2} C_\varepsilon^{-2/3}`` — calibrated to
    JHTDB), then sets ``\nu`` so the resolution criterion ``\kappa_{\max}\eta`` equals the `κ_max_η`
    option (default `2`) — the highest Reynolds number consistent with that resolution criterion. This is the
    **construction** half of the consume-and-fit loop (§4.7): laws are read to *build* runs, not only to
    validate them.
    The run is forced-and-stationary by default (a `BandRescaling` holds the total energy at the value
    given by the `kinetic_energy` keyword,
    default `1.5`, i.e. ``u'=1``); an explicit `viscosity` opts back into direct control. It does **not**
    breach the extraction boundary — `Li2008` stays a pure scalar law with no `GBGPeriodicFields` /
    `GBGStreamingStatistics` / dynamics dependency; only the run layer (never `Phenomenology`) knows both
    sides. The accuracy target is ``\kappa_{\max}\eta`` (spectral content at the highest *evolved*
    wavenumber), not ``\eta/\Delta x`` (geometric): the former is dealiasing-aware through
    ``\kappa_{\max} = f \tfrac{N}{2}\tfrac{2\pi}{L}`` ([`max_wavenumber`](@ref)), which is correct because
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
    state-realization discipline now folded into invariant 4.
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
    **`FlowConditions`** and folded into **`Generator`**, the right-hand side it parametrizes; this adds the
    honest `Generator → Forcing` dependency (the RHS includes the forcing source). A six-perspective naming
    panel chose `FlowConditions` over `System` (the bundle is a proper *subset* of the §3 System axis — it
    lacks the initial condition and the domain — so a type named for the axis while holding less is ambiguous
    and imprecise) and over `GeneratorParameters` (relational, and imprecise once a coarser rung's generator
    gains closure coefficients). (b) The `AbstractForcing` protocol methods are made grammatically uniform,
    verb-first: `set_forcing_rate!`, `add_forcing_source!`, `prepare_forcing!`, `apply_forcing!`. (c) The
    open-systems / non-equilibrium reading is recorded as a **sub-lens under Mori–Zwanzig** (§8), not new
    state types: a six-tradition panel (unanimous) confirmed the system/environment split *is* the
    Mori–Zwanzig resolved/modeled cut, but that whatever a model retains of the environment is a finite
    **Markovian surrogate on the system's own side** — a `modeled` slot on the one `State`, never a separate
    'environment state' — so a stateful forcing's internal state homes there when `StochasticOU` is
    de-archived, and no type is minted now (invariant 9).
24. **(2026-07) The domain module is `SimulationDomain`, its concrete type `FixedDomain`.** Decision 22
    split the frame into a `SimulationDomain` module; naming its concrete type took one more cut, because
    Julia will not let a module cleanly re-export a type of its *own* name — `using ..SimulationDomain:
    SimulationDomain` binds the module and shadows the type, so a bare `SimulationDomain(...)` constructor
    call stops resolving (verified empirically). The module keeps the user-facing concern name
    `SimulationDomain` (the discretized box a run lives on); its type takes a name for *what it is among the
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
    and materialized once it does — rather than the `spec` abbreviation (superseding the name minted in
    decision 14). (c) **`random_scalar_spectral!` gains a `spectrum` keyword** mirroring
    `random_solenoidal_velocity_spectral!`, seeding the scalar from a target radial scalar-variance spectrum (an
    Obukhov–Corrsin form from `Phenomenology`) for spectrum-matched initial conditions and faster
    warm-up. (d) **`HouLi`'s `strength` defaults to `nothing`, meaning auto**: resolved at kernel-build
    time to ``-\log`` of the element type's machine epsilon (``\approx 36`` for `Float64`,
    ``\approx 16`` for `Float32`), so the Nyquist mode always damps to that precision's epsilon —
    precision as a studied axis (invariant 4); an explicit `strength` overrides.
26. **(2026-07) The state reified as `ResolvedFields`; the per-step scratch relocated to `Propagator`.**
    The DNS state — the evolving velocity ``\hat{\boldsymbol{u}}`` and optional scalar
    ``\hat\varphi`` — is made first-class as **`ResolvedFields`** (module `State`), completing the
    Mori–Zwanzig triad whose State leg had been missing: the fields were scattered across the `Simulation`
    value while the diagnostics read the physical *scratch* as if it were state (`kinetic_energy(sim)` read
    `buffers.velocity`). It is a **bare, inert record with every operation external** — the panel's ruling,
    which adopts the category lens's guardrail (arrows primary, no methods on the carrier) and rejects its
    dissolution. **`ResolvedFields` holds only the spectral truth** (``\hat{\boldsymbol{u}}``,
    ``\hat\varphi``); the physical velocity, vorticity, and scalar are a Method-side derived view, never
    stored, so the state cannot go stale — and because the physical chart is rung-specific (EDQNM has no
    phases to invert), keeping it out of the state keeps the record fit to lift, unchanged, to one slot of
    the future product-of-slots `State` (§7, abstraction-ready, not built). The observables become **thin
    functions of the natural representation** with no `State` dependency:
    `kinetic_energy`/`scalar_variance`/`derivative_skewness`/`energy_spectrum` are Parseval reductions of
    ``\hat{\boldsymbol{u}}``/``\hat\varphi``, `dissipation` curls into scratch and reduces, and the run layer
    prepares what each needs — the mirror of the generator, both now thin externals over bare fields.
    Consequently the monolithic `FieldBuffers` is dissolved: the generator's operators take their
    **individual scratch fields** (naming no bundle), so the scratch is free to live with the scheme
    that owns it as **`IntegratorBuffers`** (module `Propagator`), built by `allocate_buffers` dispatching
    on the concrete scheme; `ScalarBuffers` stays a nested optional sub-bundle. The name `ResolvedFields`
    (over `ResolvedState` / `DNSState` / `FieldState`) follows the `FixedDomain` axis-lesson taken to the
    slot level: the module `State` carries the level-agnostic role, so the concrete slot is named for its
    representation — the *resolved fields* — with `FilteredFields` (LES/FDF) and a spectrum record (EDQNM)
    its eventual siblings in the product. A six-lens naming panel with an adversarial pass fixed the slate
    (`IntegratorBuffers`, and the scratch-field names `product_physical`/`product_spectral` over the
    velocity-only `lamb`). *(Amended by decisions 30–31: the physical chart the diagnostics read is now
    typed — the `ObservablesCache` in `State` — the recoveries live with the state, the assembly
    scratch on the `ResolvedGenerator`, and `IntegratorBuffers` holds only the scheme's registers; the
    individual-scratch-arguments discipline this entry set applies unchanged to the internals.)*
27. **(2026-07) Phase-shift dealiasing, on `GBGPeriodicFields`' `translation_kernel`.** Adds
    [`PhaseShift`](@ref) as an opt-in `DealiasingStrategy` (the default stays the rotational form +
    spherical ``2/3``). Each quadratic nonlinear term is assembled twice — on the grid and on a grid
    displaced half a cell — and averaged, cancelling the aliasing images that wrap in an *odd* number of
    axes; a spherical truncation at
    ``\kappa_{\max} = \tfrac{\sqrt{2}}{3}N\cdot\tfrac{2\pi}{L} \approx 0.94 \kappa_{\mathrm{Ny}}`` removes the
    surviving *two-axis* images (a single half-cell shift is exact only in 1-D; Patterson & Orszag 1971,
    Rogallo 1981). It keeps a ``\sqrt{2}`` wider band than the ``2/3`` rule (``\approx 2.8\times`` the modes
    in the retained sphere) at ``2\times`` the nonlinear-term transforms and a displaced-evaluation scratch
    field. This realizes the deferred D6 assembly generalization (§7) for this sibling: `DealiasingStrategy`
    now dispatches the whole ``\hat{\boldsymbol{u}}\to`` dealiased-term computation, not only a post-multiply
    kernel. The displacement is built once as two `translation_kernel`s (the shift theorem's phase, a
    `GBGPeriodicFields` translation primitive whose Nyquist even/odd split makes the kernel a real
    field); because the cutoff is
    sub-Nyquist the Nyquist-attenuation caveat never bites. Verified against a zero-padded oracle — exact to
    machine precision across the retained band on a field whose raw product is 44 % aliased.
28. **(2026-07) Defaults live only at the `Simulation` front door; observables read the state; buffers are
    per-scheme.** A round of API tightening after a fresh docs read.
    - **Defaults only in `SimulationRun`.** The low-level types carry no convenience defaults —
      `FixedDomain`, `FlowConditions`, the initial-condition seeders, and `Tracers` require their
      arguments; the `Simulation` front door supplies the run-layer values. Model/preset types
      (`Pope2000`, `HouLi`, …) keep their canonical parameters; `rng` may default anywhere. (This removed a
      laundered smell — an IC seeder that defaulted `kinetic_energy = 0.5` while the front door supplied
      `1.5`, once documented "by design" rather than fixed.)
    - **`scalar_type` → `element_type`** (the keyword names the array element type, not the passive
      scalar's type); **`Tracers(domain; positions)`**, so backend and precision flow from the domain
      (all-keyword past `domain` since decision 52).
    - **`step!` advances the `State`** (`ResolvedFields`), not loose ``\hat{\boldsymbol{u}}`` / ``\hat\varphi``.
    - **Observables are functions of the state, not the `Simulation`.** No `f(sim)` form: an observable
      taking a `Simulation` reached across `state` / `buffers` / `conditions`, smearing the single source of
      truth (decision 26); the run layer supplies the explicit state variables.
    - **`allocate_buffers` is per-scheme and exact** (invariant 4): each scheme allocates only the
      registers it uses; over-allocation is a hard error. The friction of the now-explicit `FlowConditions`
      is the standing argument for a reified `Generator` operator (§7). *(Realized: decision 31.)*
29. **(2026-07) The RK3 stage ordering: both right-hand sides before either update; the
    dealiasing × scheme convergence matrix.** The `IFLowStorageRK3` stage loop updated and rotated
    ``\hat{\boldsymbol{u}}`` *before* assembling the scalar's advection. A mask strategy never reads
    ``\hat{\boldsymbol{u}}`` there, but `PhaseShift`'s displaced evaluation does (decision 27) — so the
    displaced flux paired the *next* stage's velocity with *this* stage's scalar, breaking the odd-axis
    alias cancellation at ``\mathcal{O}(\Delta t)`` and degrading the scalar from third to **first** order
    (measured self-convergence ratios 2.02 against 7.97 for the velocity; `IFRK2`'s call sites were
    consistent, and the term-level padding oracle cannot see a call-site mismatch — it checks the
    assembly with matched inputs). The comment that had licensed the old order ("`u` and `φ̂` are
    untouched above") was written before `PhaseShift` made the assembly read ``\hat{\boldsymbol{u}}``
    — an invalidated premise, not a wrong derivation. Both right-hand sides are now evaluated at the
    stage state before either field is updated (bit-identical for the mask strategies), and the suite
    carries the **dealiasing × scheme convergence matrix**: both fields must converge at scheme order
    under every strategy. The bug is the motivating instance for decision 31's seam — a stage that
    reads a mid-update intermediate is a malformed factorization, which a reified right-hand side makes
    unrepresentable.
30. **(2026-07) The observation layer: `ObservablesCache` — epoch-dated, memoized charts over the state; the
    recoveries move to `State`.** The physical recoveries are the **chart map** of the state — they
    read only ``(\hat{\boldsymbol{u}}, \hat\varphi)`` and the frame — so they home in `State`
    (`Generator` imports them for its displaced evaluations; the new `Generator → State` edge respects
    the include order). `ObservablesCache` memoizes their values: preallocated slots (`:velocity`,
    `:vorticity`), each carrying the **fields epoch** it was computed at; an accessor
    (`physical_velocity`, `physical_vorticity`) returns the stored field when current and recomputes it
    first otherwise — the deposit-or-recompute contract — and `step!` advances the epoch as it
    completes. An out-of-band mutation is declared through **`fields_modified!`** — named for
    *what was changed*, the resolved fields, which is the plain reading and the one the code follows.
    *(Two corrections to this entry's original text, both recorded rather than made silently. The verb
    was named `resolved_fields_modified!` when the decision was taken; decision 24 shortened it, and
    the sweep updated the log to the current name as decisions 48 and 53 did for their vocabulary.
    And the entry credited the name to SciML's `u_modified!` → `derivative_discontinuity!` lesson,
    "name the verb for the violated invariant, not the mutated slot" — a rationale that is backwards
    for this verb: `fields_modified!` names the mutated slot, and it earns its place by
    saying plainly what a caller did, not by describing a downstream consequence the caller would
    have to reason about.)* the sanctioned mutators call it themselves, and the seeders' docstrings direct hand-run
    loops to it. This kills the `step!` silent-precondition footgun — there is no caller prefill left
    to forget. **Epoch granularity is deliberately coarse**: one counter per dynamical factor of the
    tower (fields, particles), no finer — every production memoization precedent surveyed (LAMMPS
    computes' timestep tags, OpenFOAM's registry event numbers, Fluidsim's iteration counters) uses a
    single counter, within-step consistency is the seam's job (decision 31), and an over-fine epoch
    system is itself a silent-staleness surface. Observables are **opt-in** (an undeclared one errors —
    resident GPU memory is a choice), and the cache's shared spectral scratch replaces two
    `IntegratorBuffers` slots — net one resident spectral vector *fewer* than before the layer.
    Naming: **`ObservablesCache`** was fixed by a six-lens panel (5–1 over `DerivedQuantities`, upheld by
    an adversarial pass) with a license clause the docstring carries — each slot holds *a derived
    field's values*, on the grid lattice or at the tracer positions; particle content never enters —
    a recorded rename trigger (the first particle-*sourced* slot, e.g. a number density, reopens the
    name), and a recorded guard: ``\varepsilon``, ``k``, ``E(\kappa)`` never become resident slots
    (statistics belong to `GBGStreamingStatistics`; occasional diagnostics allocate per call). Kills,
    not to be re-proposed: `Observations` (collides with `Observables`), `DerivedViews`/`StateViews`
    (a Julia view cannot be stale), `Charts` (these are non-invertible functionals, not manifold
    observables), `Diagnostics` (the community word for scalar time series), `Snapshot` (asserts
    restart-copy structure), `DerivedQuantities` (indiscriminate extension).
31. **(2026-07) The generator reified: `ResolvedGenerator` and the six-verb protocol; schemes shrink
    to stage arithmetic.** Closes §7's deferred item on its own terms — the reification now carries
    what the loose functions could not: the assembly scratch (the quadratic products, the `PhaseShift`
    buffers, the forcing-rate arrays), the conditions, and the step lifecycle. The protocol:
    `prepare!` (open the step — advance forcing state, arm linear rates), `velocity_rhs!` /
    `scalar_rhs!` (each field's explicit right-hand side at a stage state: the dealiased nonlinear
    term plus the additive forcing source), `velocity_integrating_factor!` / `scalar_integrating_factor!` (each field's exact
    linear subflow — the generator is the semilinear split ``\partial_t \hat q = A\hat q + N(\hat q)``
    with a *diagonal, exact* linear operator, the exponential-scheme family's special case), and
    `finalize!` (close the step — the post-step forcing projections). The rhs/factor pairs are the
    required core; `prepare!`/`finalize!` default to no-ops (a two-tier required/optional protocol).
    **`finalize!` on the generator is a recorded deviation** from the solver-library precedent (the
    SciML/PETSc/SUNDIALS right-hand-side objects are pure evaluators, with post-step action in
    callback layers), adopted because the projection is part of the *step's* contract, not of
    observation: the observables, the diagnostics, and the tracer push must see the forced end-of-step
    state, and molecular-dynamics practice places exactly this operation inside the step (a
    constraint's velocity-projection stage, a thermostat's end-of-step rescale, the trailing factor of
    a symmetric splitting). The signature becomes `step!(scheme, state, generator, domain,
    buffers, derived, dt)`: both schemes now contain no physics — no viscosity, no forcing calls, no
    conditions — and `Propagator` drops its `Forcing` dependency. The old public assembly trio
    (`velocity_nonlinear!`, `scalar_nonlinear!`, `integrating_factor!`) demotes to internals behind
    the protocol, retiring the eight-argument assembly signatures. The name extends the axis
    convention — `ResolvedFields` ↔ `ResolvedGenerator`, resolved against filtered, with
    `FilteredGenerator` (carrying its closure) the eventual LES sibling — and the run layer's
    `_resolve_forcing` was renamed `_materialize_forcing`, reserving *resolved* for that axis against
    `DeferredForcing`'s materialization vocabulary. Every migration stage was verified
    **bit-identical** on fixed-seed trajectories (all three dealiasing strategies and the
    `StochasticOU`-forced case) against the pre-migration code.
32. **(2026-07) Forcing hooks own their scratch; the lifecycle order is contract.** The four-hook
    interface no longer receives the scheme's buffer bundle ("for interface uniformity" — the
    smell decision 26's discipline predicted): `set_forcing_rate!`, `apply_forcing!`,
    `prepare_forcing!`, and `add_forcing_source!` take only what they act on, and `StochasticOU` owns
    its noise scratch (one field in physical and one in spectral representation, allocated on first
    use like its ``\hat{\boldsymbol{f}}`` state) instead of reaching into `buffers.product_*` by
    field name — at the recorded price of two resident fields for a velocity-forcing instance,
    accepted to sever the one cross-component reach-in (the extended-system discipline: a thermostat
    never touches the scheme's registers; the OU re-add stays gated on a GPU-tuned generator
    either way). The hook lifecycle — prepare and rate before the stages, source at every stage,
    projection after the completed step — is documented as part of the `AbstractForcing` contract,
    with the rate and the source recorded as two channels of *one* forcing term (the exactly linear
    part in the factor, the remainder at stages). This stage deliberately ran *before* the generator
    reification, against the migration plan's original order: the borrow had to be severed before the
    borrowed scratch could move homes. `BandRescaling` carries the Berendsen-class caveat — a
    deterministic clamp has no conserved quantity and no well-defined ensemble except in limiting
    cases (Bussi, Donadio & Parrinello 2007) — a spin-up and amplitude-holding tool, with stochastic
    rescaling the recorded upgrade path when faithful fluctuations of the held quantity matter.
33. **(2026-07) The memory audit: a frozen buffer ledger and a liveness lower bound, in the standard
    suite.** "Minimal footprint" becomes a checked property instead of an aspiration
    (`test/memory_audit.jl`, run by `Pkg.test()`). Two instruments. (a) **The ledger**: a reflective
    walk over every resident field-sized buffer a run owns (state, observation cache, generator,
    scheme registers, forcing-owned state and kernels, the tracer buffers), counted per shape
    class over the full **five-axis** combination space — scheme × dealiasing × scalar ×
    (velocity forcing × scalar forcing) × tracers. The frozen spec is **compositional**: twelve
    unforced, tracer-free base cells plus a per-forcing delta table and a tracer delta, and an
    exhaustive sweep over the whole product (~360 combinations) asserts measured = base + deltas,
    cell by cell — a cross-term (a buffer whose existence depends on two axes at once) fails the
    sweep and must be recorded. The observation cache's **charts axis** (resident charts are
    opt-in) is audited at the API level with its own delta; for any *stepping* run it is pinned by
    the physics — the rotational generator's declared working set requires both charts — and becomes
    a live run axis when per-component chart declarations or further charts land. Adding or removing
    a buffer anywhere fails the suite, so a footprint change must be a conscious, recorded decision.
    The particle-scheme axis has one point today (the Heun scheme), entering as on/off with the
    per-tracer ``(M, 3)`` arrays audited in their own units; precision, backend, and the
    interpolation scheme change bytes, never counts, so they are outside a count ledger. Two scope
    boundaries are deliberate: the ledger audits the **resident** working set — construction-time
    seeding transients and the recorded per-call diagnostic allocations (invariant 4's exception,
    e.g. the derivative-skewness tensors) are *peak*-memory events a separate instrument would
    cover — and the **frame** (the domain's plans, multipliers, kernels) is excluded as shared,
    combination-independent infrastructure, a constant offset rather than an axis. *(That second
    boundary was withdrawn by decision 36: constant in the combination space is not the same as
    small, and the frame now carries a ledger of its own.)* (c) **The episode
    ledger** closes the resident-vs-peak gap: the hot loop is allocation-free (the step guards), so
    the stepping-phase peak *is* the resident ledger; outside it the transient episodes are few,
    sequential, and frozen in units of ``N^3`` reals with mechanical `@allocated` drift guards —
    seeding ``\approx 10.3`` (construction only; includes a ``3.2``-unit transient from the *aliased*
    Leray projection, raised to `GBGPeriodicFields`), the energy spectrum ``\approx 1.6`` (the
    backend's radial-spectrum staging), and the **velocity-derivative skewness ``\approx 19.6`` — the
    dominant episode, about half again the default resident set, and on by default in `warmup!`'s
    skewness gate**: the binding device peak of a default warm-up at the largest fitting ``N``.
    This prices invariant 4's per-call-diagnostic trade (resident traded into episodic peak) and
    names its reduction paths: symmetric six-component tensor storage at the backend (the tensors are
    stored with all nine components today), or gating the skewness off when memory binds. The
    archived `StochasticOU`'s prepare phase also projects its noise aliased — an OU-forced step is
    not allocation-free today (``\approx 3`` units per step), recorded on its de-archival gate. The
    allocator-level high-water mark (GC and pool timing) remains an empirical measurement on the
    benchmark hosts, a fitness number rather than a test invariant. (b) **The
    liveness audit**: each `step!` body is a straight-line program, so its op list (reads and writes
    per primitive field operation) gives every value a live range, and the peak number of
    simultaneously live values per shape class is the *lower bound* on the buffers the implemented
    operation order needs — the classical register-allocation argument. The audit asserts achieved ≥
    bound and that **every nonzero gap carries a named holder**; an unclaimed gap fails the test.
    Current verdicts: the physical-vector count sits *exactly at its bound* under the chart contract
    (the charts are contract-live across the step; the epoch-at-start chart-reuse that would release
    two registers during the stages is the recorded candidate); one spectral-vector gap is held by
    the State/Generator **ownership boundary** (the cache's recovery scratch and the generator's
    product registers could alias in the implemented schedule but live on opposite sides of a
    deliberately kept seam); the spectral-scalar gaps are held by the **shared factor register**
    (deletable by a fused exponential-multiply convolution — raised to `GBGPeriodicFields` as a
    request, with an in-place transform mode for disposable sources as the second request, which
    would halve the archived `StochasticOU`'s noise scratch on de-archival) and by the scalar's
    transient registers (`copy`/`nonlinear`/factor could share one slot). Bounds are relative to the
    typed-field reuse model; the byte-level refinement (a spectral and a physical field have equal
    byte size under the rfft padding) is recorded as a `GBGPeriodicFields`-level question, not chased
    here. The op lists are re-derived whenever a `step!` body or the generator protocol changes — the
    ledger failing is the reminder.

34. **(2026-07) The compute audit: frozen transform and pass ledgers with fusion bounds, in the
    standard suite.** The compute twin of decision 33 (`test/compute_audit.jl`): the same
    straight-line op lists — extracted to `test/audit_ops.jl` as the single source of truth both
    audits project, and upgraded to pass-exact fidelity to `step!` (stage 1 *seeds* the low-storage
    accumulator, the last stage skips its rotation) — priced in the two compute currencies of a
    pseudospectral step on a GPU. (a) **The transform ledger**: scalar-equivalent FFT counts (c2r,
    r2c) per step, frozen per scheme × dealiasing × scalar cell with the chart recomputes amortized
    in (each chart is recovered once per fields epoch, wherever first read — which is also why the
    **tracer transform delta is zero**: the Heun endpoints ride the epoch cache, the observation
    layer's compute dividend). Transforms carry the flops — ``\tfrac{5}{2} N^3\log_2 N^3`` per scalar
    transform against O(1–20) flops per point for every pointwise kernel, far under the roofline
    machine balance — so **flops are derived from the count, never an independent frozen axis**.
    The counts are per-evaluation × evaluations (asserted structurally), the mask evaluation is
    ``(6, 3)`` for the velocity and ``(1, 3)`` for the scalar, and `PhaseShift` doubles the velocity
    transforms exactly — the dealiasing axis's memory↔compute trade now priced on both sides.
    Verdicts: every cell sits **at its lower bound** (each physical component field consumed costs
    one c2r, each spectral product component one r2c, for the algorithms as chosen) except
    `PhaseShift` × scalar, where `scalar_rhs!` re-shifts and re-recovers the displaced velocity that
    `velocity_rhs!` left fresh at the same stage state — 3 c2r per evaluation, held by the named
    **shifted-velocity reuse** gap (the fix is a same-stage freshness contract on the generator's
    displaced scratch across two protocol verbs — a seam question, recorded, not chased). (b) **The
    pass ledger**: full-field memory passes per shape class for everything between transforms —
    pointwise kernels are bandwidth-bound, so what fusion buys is passes, and the **fusion bound**
    is the liveness argument transplanted to traffic: per between-barriers segment, a perfectly
    fused kernel reads each live-in once, writes each live-out once, reads each field-scale
    configuration array once, and a pure intermediate costs nothing. Verdicts: the physical-side
    and configuration classes sit *at* the fused ideal in every cell; every gap lives in the two
    spectral classes and is held by **PF kernel granularity** (the numpy model's op-per-kernel
    boundaries) plus the **factor materialization** the open `GBGPeriodicFields`
    fused-exponential request would delete. Forcing enters as frozen per-hook deltas (only the
    stochastic forcing transforms — its noise pipeline; the OU-velocity column is cross-checked
    against its op list). Both ledgers are static projections; their currency is anchored by the
    shared op lists (decision 33's re-derive obligation) and regenerated for review by the
    `AUDIT_PRINT` aid. Kernel-launch counts and achieved bandwidth on the GPU hosts remain
    benchmark-side empirics, outside the suite.

35. **(2026-07) A recorded cost is not a minimal one: every audited cell is held against a physical
    floor, and the residual distance must be claimed.** Decisions 33 and 34 built ledgers that
    *record* what a run costs and fail when the number drifts. That certifies stability, not
    minimality: a frozen cell measures what **is**, never what **should be**, and a cost with no
    lower bound held against it is unexamined rather than optimal. The correction is to give every
    cell a **floor** — the cost the quantity cannot go below on physical grounds — and to require
    that `achieved − floor > 0` carry a **named holder**, split into `FIX`-then-retire (a local win,
    removed when taken) and `PF-RAISE` (a recorded backend request). An unclaimed gap fails the
    suite. This inverts enforcement from *did the number change* to *is there residual distance to
    the floor, and is it accounted for*, and it subsumes a third axis the two ledgers could not see:
    **form** — not how well a fixed expression is scheduled, but which of the mathematically
    equivalent expressions is evaluated at all (Parseval for a quadratic reduction, the Dirichlet
    form for a gradient energy, the solenoidal identity for enstrophy, a spectrum that already
    integrates to the energy). Cubic and nonlinear invariants are floors, not gaps: the Lamb vector,
    the scalar flux, and ``\det\boldsymbol{S}`` have no quadratic shortcut.

    Two structural consequences beyond the ledgers. The op model must extend **past `step!`** to
    every surface a run touches — the initial-condition seeders, the observables, the run-loop
    accounting, the tracer push, the forcing hooks — since a cost outside the stepped region is
    invisible, not absent. And an **eighth axis** joins the seven: **host–device synchronization**.
    On GPU-primary code every reduction that returns a Julia scalar is a blocking device-to-host
    transfer that drains the pipeline, and no footprint or traffic count can see a barrier; the
    floor is one such readback per step under an adaptive CFL (only the speed bound gates the next
    launch) and none under a fixed step. Decision 34 had placed synchronization outside the suite as
    a benchmark empiric — correct for *achieved* bandwidth, wrong for the *count*, which is a static
    property of the schedule and belongs with the other ledgers.

    The instrument is `test/optimality_audit.jl`, projecting the same op model the two ledgers do.
    It carries the **holder register** — every named holder, its cause, and its disposition — and
    enforces the discipline in both directions: an unclaimed gap fails, and so does a **stale
    holder**, one whose gap has been closed everywhere, so retiring it is part of taking the win. It
    also splits the pass gap into its two tiers, which have different owners: *achieved − bound* is
    unused fusion (kernel granularity), while *bound − floor* is the traffic that exists only
    because the per-mode symbols are materialized as ``N^{3}`` arrays. The split is diagnostic — the
    spectral-vector class is entirely the first tier (its bound already sits at its floor), and the
    real-spectral-scalar class entirely the second (already perfectly fused, yet every unit of it is
    ``\lvert\boldsymbol{\kappa}\rvert^{2}`` swept once per integrating-factor build), so a lazy
    per-mode symbol apply would delete that class outright and do nothing for the other.

    On the synchronization axis the default configuration issues **three** blocking readbacks per
    step — the CFL speed bound, and `BandRescaling`'s band and whole-field observables — against a
    floor of **one**. Only the timestep's is irreducible; a forcing's scalar is consumed by the very
    next kernel and visits the host only because it is written as a Julia number.

    First fruits, each verified and each retiring its holder rather than recording it: the tracer
    push no longer retains a start-of-step velocity **field** (§4.6) — an ``N^{3}\times3`` resident
    buffer and per-step copy serving an ``M\times3`` interpolation, which the ledgers had faithfully
    recorded as a tracer delta and never challenged, in plain conflict with invariant 4's *footprint
    over compute*; the run layer measures ``\varepsilon`` through the Dirichlet form rather than
    building a vorticity to square away; and `IFRK2` builds each integrating factor once per step
    instead of twice. Where a residual is deliberately **not** taken it is named and its premise
    tested, not asserted — the coincident integrating factors at ``\mathrm{Sc} = 1`` are left
    unexploited because the guard would make the hot loop's schedule depend on a runtime value, and
    because the sound condition is *equal diffusivities and both linear rates unarmed*, never
    ``\mathrm{Sc} = 1`` alone.

36. **(2026-07) The frame is ledgered too, and the two ledgers must jointly account for every
    field-scale array.** Decision 33's ledger walked what a run **evolves** — the state, the
    observation cache, the generator's assembly scratch, the scheme registers, the tracers. It
    never walked the `FixedDomain`, the read-only **frame** the run lives on, so that storage was
    outside every instrument: the audit claimed to bound residency while measuring only part of it.
    The frame is not small. It holds three field-scale arrays — ``\lvert\boldsymbol{\kappa}\rvert^{2}``
    as a real array, the same ``\lvert\boldsymbol{\kappa}\rvert^{2}`` again as the `weighted_inner`
    weight, and the dealiasing kernel — 322.5 MiB at ``256^{3}`` in double precision, some 8 % on top
    of the default working set, and 2.52 GiB at ``512^{3}``.

    What made the omission urgent rather than untidy is where the incoming lazy per-mode symbol work
    lands. The phase-shift translation kernels hang off the generator and were therefore *inside* the
    old ledger, while the dealias mask and both copies of ``\lvert\boldsymbol{\kappa}\rvert^{2}`` sit
    in the frame and were outside it — so of the materialized symbols a ``256^{3}`` `PhaseShift` run
    carries, the instrument could see 44 %. It would have confirmed the smaller half of the win and
    been structurally blind to the larger.

    The two ledgers are kept **apart** because they answer different questions — the working set is
    what the schedule needs live, the frame is what the discretization costs to have precomputed —
    and are joined by a **completeness invariant**: their sum must account for every field-scale
    array reachable from a live `Simulation`, cell by cell. That invariant, not the frame table, is
    what keeps the hole shut, since it fails on new residency wherever it hangs. One exclusion is
    **named** rather than left absent: a backend FFT plan's work area is owned by the vendor library,
    reachable from no Julia field, and observable only by a device query, so it stays a benchmark-side
    empiric.

    The frame's floor is **zero** field-scale arrays — every entry is a closed-form function of the
    ``O(N)`` per-axis multipliers — and here the floor is *demonstrated* rather than argued: the
    audit reconstructs ``\lvert\boldsymbol{\kappa}\rvert^{2}`` as the outer sum of three axis
    vectors, checks the Dirichlet weight against it exactly, and checks that each strategy's kernel
    is constant on the level sets of ``\lvert\boldsymbol{\kappa}\rvert^{2}`` — sharp, smooth, and
    spherical alike. A future frame entry carrying genuine ``N^{3}`` information will fail those
    reconstructions and move the floor.

    Two findings the ledger surfaced the first time it ran, both claimed by the existing symbol
    holder and retiring with it: ``\lvert\boldsymbol{\kappa}\rvert^{2}`` is resident **twice** in two
    element types, because `weighted_inner` takes a spectral-scalar-typed weight while the envelope
    and integrating-factor broadcasts want the real array; and both spectral-scalar frame entries are
    real-valued symbols held in **complex** containers, at twice their information content. The audit
    op model's fifth shape class was renamed in the same step — a class holding
    ``\lvert\boldsymbol{\kappa}\rvert^{2}`` and the dealias mask cannot be called `rate` for one of
    its occupants, and the frame table would have reported a nonzero rate cell for a domain that
    carries no forcing at all.

37. **(2026-07) An assumption may never be an input to the bound it is measured against.** The
    liveness projection of decision 33 extends some values' live range across the whole step, and it
    did so for two different reasons under one name. The evolving state
    (``\hat{\boldsymbol{u}}``, ``\hat\varphi``, a stochastic forcing's internal state) is live because
    the **dynamics** says so — every stage reads and writes it, and no schedule exists in which it is
    not live — so extending it is a statement of fact and belongs in a lower bound. The observation
    cache's charts are live because a **design choice** says so: the epoch-at-end contract requires
    them to survive the step, and a different design does not. Extending *those* and then reporting
    the result as the bound made the physical-vector cell a tautology — the ledger carries exactly
    those observables, so `achieved == bound` held by construction, and the suite positively asserted the
    equality.

    Measured on the same operation lists: the honest liveness floor is **three** physical vectors —
    the two substage recoveries plus the product register — against a ledger of **five**. The audit
    reported a gap of zero where there are **two physical vectors, 768 MiB at ``256^{3}`` in double
    precision**, the largest single residency item the optimality campaign has surfaced. The holder
    that should have claimed it, `CHART CONTRACT`, had been *written down* in the register's own
    comment from the start and never bound to a cell, because the assumption was consumed by the
    bound instead.

    This is decision 35's failure mode occurring inside the instrument decision 35 depends on.
    Decision 35 corrected *a recorded cost is not a minimal one*; the residue it left is sharper — a
    **bound built out of the very thing it should test** is worse than a loose bound, because a loose
    bound at least fails honestly. The correction splits the set in two, admits only the dynamics half
    to the projection, and makes the chart contract a holder with a `FIX` disposition, so the gap is
    claimed and retires when the closing-refresh design closes it.

    Two details keep the fix honest. The traffic model of decision 34 keeps the **union**, because a
    value that outlives a fusion segment must reach memory whatever the reason it survives — so the
    compute ledger is untouched. And a guard test now asserts the assumption is **load-bearing**:
    adding the chart extension back must raise the count, and raise it exactly onto the ledger, so
    re-merging the two sets fails the suite rather than silently re-certifying the tautology. The
    same test pins that the split is confined to its class — excluding the charts changes neither
    spectral class, confirming the state's extension was never the defect.
38. **(2026-08) The frame compresses to zero field-scale arrays: every per-mode symbol is lazy.** The
    `GBGPeriodicFields` pin moved to a master that ships compressed kernel classes (its decisions
    50/51/60), and the `FixedDomain` adopted them: the de-alias mask of every strategy is a
    `RadialKernel` (`TwoThirds`/`PhaseShift` via `spectral_cutoff`, `HouLi` as its own radial symbol),
    the Dirichlet-energy weight is `radial_kernel(identity, …)`, the stored real ``|\kappa|^2`` array
    is gone (its consumers — the initial-condition envelopes, now composed radial kernels folded with
    the truncation; the integrating-factor builds, a transitional lazy broadcast; the backend/eltype
    template, now the multipliers' axis arrays), and the phase-shift translation kernels are per-axis
    `SeparableKernel`s. Decision 36's frame floor of zero is thereby **achieved** — 322.5 MiB retired
    at ``256^3``/`Float64`, ``|\kappa|^2`` no longer resident twice — and the optimality audit's
    reconstruction demonstration inverted into a correctness pin: the lazy symbols, materialized on
    demand, must equal the explicit axis-vector reconstruction. Knock-on residency wins recorded in
    the same re-freeze: every band forcing's kernel is lazy (`BandRescaling` and `StochasticOU` store
    none; `Linear` and `ConstantPower` keep one materialized *real* indicator each for the rate fill),
    and the seed/spectrum episodes shrank because `GBGPeriodicFields` delivered the guard-free aliased
    projection and fused its `radial_spectrum` staging. The bare `ScalarFieldSpectral` integrating
    factor is wrapped in `StoredKernel` at its apply sites — a transitional form; the fused
    exponential adoption that deletes the factor machinery is the recorded next step, and the
    `MATERIALIZED_SYMBOLS` holder narrows to exactly that remaining traffic.
39. **(2026-08) The integrating factor is never materialized: the factor verbs supply parameters, and
    the stage update is one fused exponential pass.** The protocol's factor half changed shape:
    `velocity_integrating_factor` / `scalar_integrating_factor` (the `!` is gone — nothing is mutated) return the exponential's
    parameters — ``\texttt{coefficient} = -D\tau``, ``\texttt{offset\_scale} = \tau``,
    ``\texttt{offset} = \hat A`` or `nothing` — and the schemes apply ``\mathcal{E}`` through `GBGPeriodicFields`'
    `exponential_convolve!`, which evaluates ``\exp(c\lvert\boldsymbol{\kappa}\rvert^2 + s\hat A)`` per
    mode from the ``O(N)`` wavenumber arrays. Three consequences, each landed in the same re-freeze:
    (1) the `IntegratorBuffers.integrating_factor` register and every per-stage factor build are gone —
    the stage update ``\hat{\boldsymbol{u}} \leftarrow \mathcal{E}(\hat{\boldsymbol{u}} + B_i h)`` is
    the backend's **two-operand** exponential form, one pass where combine-build-rotate were three, and
    a velocity-only working set now holds *nothing scalar-shaped at all*; (2) an armed linear forcing
    rate became a scalar field in spectral representation holding real values (the fused exponential's
    per-mode offset), read once per application instead of once per build; (3) the de-alias/truncation
    passes folded into their producers — a mask strategy's kernel rides the projection's own pass (the
    kernel-composed ``\mathbb{P}`` and ``\nabla\cdot`` arities, the latter absorbing the ``-\nabla\cdot``
    sign in ``\alpha``), and the phase-shift chain's final convolve applies shift-back, average, and truncation in one
    convolve through a `back ∘ truncation` kernel composed once at construction. Three audit holders
    retired in the same commit, each because its gap **closed**: `SHARED FACTOR` (the register it
    priced no longer exists), `MATERIALIZED_SYMBOLS` (both its residency and traffic claims delivered —
    the pass ledger's fused bound now *equals* the physical floor, asserted as an equality), and the
    `COINCIDENT INTEGRATING FACTORS` residual (nothing is built for the ``\mathrm{Sc} = 1`` coincidence
    to save; its guard lesson — key any dedup on the full ``(D, \tau, \mathrm{rate})`` tuple, never
    ``\mathrm{Sc}`` alone — survives as the armed-rate pin in the factor-verb test). The
    `derivative_skewness` diagnostic also stopped materializing its determinant field
    (``\langle\det\boldsymbol{S}\rangle`` is the fused mapped mean), and transforms are untouched
    everywhere — this decision moves passes and residency only.

40. **(2026-08) The observables cache is deposit-driven, and a slot is its producer's register.** The
    cache moves to its own module (`Cache`, between `State` and `Forcing`) and is rebuilt to the
    design of `docs/src/observables_cache.md`: the schedule is fixed at construction and identical on
    every iteration; **everything is deposited at the end of the iteration** (`deposit!` — the next
    iteration's first-stage recoveries relocated, plus the maximum-speed reduction the next timestep
    choice reads); a read serves the current-epoch value or **throws** — there is no path, internal or on
    request, by which reading causes a computation (the recompute-on-staleness accessors of
    decision 30 are retired; `fields_modified!` now opens an interval in which reads throw,
    closed by an explicit `deposit!`). Contents are **automatic** — the constructor derives them from
    the configuration (the `observables` declaration keyword is gone); the three-valued slot epoch
    (deposited value / producer's scratch / never deposited) polices the mid-iteration window, and
    the deposit-completeness check refuses to close an iteration with an undeposited slot. The
    storage consequence is the **slot=register merge**: the step's substage recovery registers ARE
    the cache's chart arrays (taken at stage 2, re-deposited at the iteration's end), which deletes
    `IntegratorBuffers`' two physical vectors — precisely the honest gap decision 37 uncovered,
    768 MiB at ``256^3``/Float64 — along with the cache's spectral scratch and the scalar's copy
    register (the closing and substage recoveries write through a stage register that is dead at that
    point of the schedule). Every unforced ledger cell now sits **at** its liveness bound in every
    class, so three holders retire in this commit (`CHART CONTRACT` — by exactly the closing
    refresh its text prescribed — `OWNERSHIP`, and `SCALAR REGISTERS`), and `DYNAMICS_LIVE` absorbs
    the charts as facts of the deposit-persistence contract (the `charts_live` choice parameter is
    gone; the falsifiability guard now pins the closing-deposit structure instead). The audited op model
    widens from the step to the **iteration** (step + closing deposit), which surfaces the once-per-iteration
    maximum-speed readback in the pass and synchronization ledgers (+1 physical-vector pass in every
    cell; a hand-fixed-``\Delta t`` iteration still pays it — held by the new `UNIFORM DEPOSIT
    SCHEDULE` design holder, the price of a schedule that never varies with how the run is driven).
    Read that against decision 35's synchronization floor — one readback per step under an adaptive
    CFL, none under a fixed step — and note the two are speaking about different things: 35 states
    the **floor**, this states what is **achieved**, and on the fixed-step axis they deliberately
    differ. That gap is exactly what a named holder is for;
    transforms froze **identical** in every cell. Public-surface consequences: the accessors are the
    noun-first checked reads `velocity_physical` / `vorticity_physical` / `scalar_physical` and the
    cached `max_speed` (one generic with the `Observables` reduction), `physical_velocity` /
    `physical_vorticity` / `spectral_scratch` are gone, and the allocator family was renamed so the
    allocators and the physics-named observables accessors cannot collide — settled (user, 2026-08)
    as the constructor form `new_<Type>` after the PF field types: `new_vector_field_spectral`,
    `new_vector_field_physical`, `new_scalar_field_spectral`, `new_scalar_field_physical`,
    `new_tensor_field_spectral`, `new_tensor_field_physical` — the allocation verb explicit and the
    returned type readable straight off the name.

41. **(2026-08) The quadratic products form in place over an operand's register: `product_physical`
    is deleted.** The backend's index-shuffling kernels are alias-safe by construction (each output
    element's whole fiber is read before anything is written — the PF sweep that retired its
    aliasing guard), so `cross!(ω, u, ω)` lands the Lamb vector in the vorticity's own register, and
    the flux ``\boldsymbol{u}\varphi`` lands in the velocity's through the backend's pointwise
    `multiply!` — which also replaces the raw broadcast `_scalar_flux!` had carried, a
    reimplementation of a shipped PF operation (invariant 2). The displaced PhaseShift evaluations
    reuse their own shifted registers the same way. The verb `velocity_rhs!` therefore **consumes** its `ω`
    argument and `scalar_rhs!` its `u` (documented in both docstrings; `step!` takes the
    corresponding cache slots before the stage-1 assembly), and `ResolvedGenerator` keeps only the
    spectral product image: one physical vector retired from **every** configuration — 384 MiB at
    ``256^3``/Float64 — bringing the physical-vector floor to **two** registers (the chart slots,
    now serving as recovery registers *and* product targets), with the archived OU's physical
    ownership gap closing as a side effect (no product register remains for its noise to alias).
    This is the reuse §2.3 of the design page recorded as blocked before the backend's alias-safe
    kernels landed; passes and transforms are untouched — the decision moves residency only.

42. **(2026-08) The trajectory sample is a cache slot, and the tracer velocity registers are named
    for what they are.** `Tracers.velocity1` / `velocity2` were categorically different objects
    wearing sequence numbers: the first is the **trajectory sample**
    ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` — a genuine Lagrangian observable between iterations —
    the second the velocity at the Heun *predictor* position, which no tracer ever occupies: a stage
    register, substage on the position argument alone. They are renamed `particle_velocities` /
    `predictor_velocity`, and the sample becomes the observables cache's first trajectory-bound
    slot — the class decision 30 reserved and never used — wired to the tracer set's own point-value
    storage (the slot IS the register, as everywhere else) and dated against **both** epochs,
    since the sample is a function of the state and the positions together. The push's schedule
    moves fully onto the iteration ends: `advance!` checks the sample at the start (the previous
    closing deposit recorded ``\boldsymbol{v}_1``), pushes after the closing field deposits
    (``\boldsymbol{v}_2`` from the deposited ``\boldsymbol{u}(t_{n+1})``), then records at the new epoch
    the new sample at the new positions — so `advect!`'s prose-only staleness contract is retired in
    favor of the slot epoch, and the sample is read through the checked `particle_velocities`
    (`tracer_velocities` is gone; `tracer_positions` is renamed `particle_positions`, the
    user-settled accessor prefix). The register `predictor_velocity` is deliberately **not** readable — an
    off-trajectory value must not be servable as a plausible-looking Lagrangian velocity — and the
    tempting ``\boldsymbol{v}_2``-as-next-``\boldsymbol{v}_1`` reuse is recorded as forbidden (it
    would approximate the measured observable at ``\mathcal{O}(\Delta t^{2})``; never approximate the thing you
    measure).

43. **(2026-08) The loop is observation-first, and stopping is the caller's decision on
    observables.** `run!(callback, sim)` observes the run after every iteration and once at the seeded ``t_0`` —
    ``n`` iterations, ``n+1`` observations (the instant a validation run most wants was
    previously never observed) — and the callback's `Bool` return decides continuation; a non-`Bool`
    return throws, so the decision cannot be left implicit. The stopping vocabulary
    (`turnovers | time | steps | stop`, and the `every` cadence) leaves `run!` entirely: a budget is
    a callback that accumulates what it budgets, a cadence is the callback's own business, and with
    them go the loop's internal ``\varepsilon``/``k`` measurements — the iteration is closed
    (everything it computes is a function of configuration and state, decision 40's automatic
    contents depend on it). The one packaged observation is `StationarityCriterion` — the
    researched spin-up judgment (``\varepsilon``-flatness with the skewness and scalar-variance
    gates, the give-up cap) as a callable carrying its own observation state — with `warmup!` kept
    as its one-line sugar. The uniform read surface completes the redesign: `velocity_spectral` /
    `scalar_spectral` read the state itself, the cache accessors the deposited observables, and
    `particle_positions` the probes' state — a **function names what the run holds, wherever it
    lives** (reading needs no knowledge of the state/cache split), while writing stays on the dot
    path, where the danger demands the knowledge. An accessor exists exactly for what the run holds:
    `vorticity_spectral(sim)` deliberately does not exist (``\hat{\boldsymbol{\omega}}`` is
    materialized nowhere), and a `MethodError` is the honest answer.

44. **(2026-08) The closing-deposit relocation stops at the recoveries: the nonlinear terms are not cached.**
    The cache design's full relocation — assembling the dealiased
    ``\mathbb{P}(\boldsymbol{u}\times\boldsymbol{\omega})`` and
    ``-\nabla\cdot(\boldsymbol{u}\varphi)`` at the iteration's end, so the next first stage reads them — was
    written in the third-array world and is **incompatible with decision 41**: the products now form
    in place over the velocity and vorticity slots, so an end-of-iteration assembly would destroy the deposited
    charts the observation exists to serve, and keeping both would re-add the product array
    (one physical vector, 384 MiB at ``256^3``/Float64). Minimal footprint trumps compute
    (invariant 4), and the relocation buys no compute — transform counts are identical either way —
    so the products stay in the first stage and the design page's §2.4 rows go to *no* by the
    design's own survival test (contents are a property of the solver's storage decisions). The
    `PhaseShift` transform saving that motivated the relocation (the scalar assembly's re-recovery
    of the displaced velocity the velocity assembly left fresh) does not need it: the two
    assemblies are adjacent *within every stage*, so a same-stage freshness contract on the
    displaced scratch recovers all nine inverse transforms — stage 1's three included — which is
    the roadmap's next step.

45. **(2026-08) The displaced velocity is reused within the stage: `PhaseShift` costs exactly twice
    a mask, scalar included.** The last transform gap — `scalar_rhs!` re-shifting and re-recovering
    the displaced velocity that `velocity_rhs!` had left fresh at the same stage state (3 c2r per
    evaluation, the `SHIFTED-VELOCITY REUSE` holder) — closes by the same-stage freshness contract
    the holder prescribed: `velocity_rhs!` marks the generator's `u_shifted` fresh after its
    displaced recovery (its displaced Lamb consumes only `ω_shifted`, decision 41), the same
    stage's `scalar_rhs!` consumes the mark and reads the register directly (its flux is
    `u_shifted`'s last consumer), and `prepare!` opens every step with the mark cleared. The
    contract is opportunistic, not load-bearing for correctness: a bare `scalar_rhs!` with no
    preceding velocity evaluation finds the mark cleared and rebuilds the displaced velocity
    itself, value-identically. The transform ledger now sits **at its lower bound in every cell**
    — `TRANSFORM_GAP_HOLDERS` is empty, `PhaseShift` is exactly ``2\times`` its mask cell for
    velocity and scalar alike (RK3 ``51 \to 42`` c2r, RK2 ``34 \to 28``), and the `PhaseShift`
    scalar pass cells drop the deleted shift and recovery passes with it. This completes the
    dealiasing axis's memory↔compute pricing: a mask spends a per-mode multiplication, `PhaseShift`
    spends exactly one extra evaluation of each term, and nothing else.
46. **(2026-08, user-directed) `Observables` precedes `Cache`: the measurement functions are the
    generics the cached reads extend.** The include order becomes `State → Observables → Cache`, and
    an observable with both a measurement and a cached value is **one generic with two method
    families** — the field-argument reduction computes ("measure now"), the `ObservablesCache`
    method serves the deposited value or throws — with the bare binding and the docstring homed in
    `Observables` and `Cache` extending it (`max_speed` today; the pattern is the rule for any
    future cached observable). Dispatch by argument type is the mode selector: a considered
    `observable(state, cache, compute::Bool)` form was rejected — the flag conflates an ``O(1)``
    read with an ``O(N^3)`` measurement, and "return it if stored in the state" is empty, since the
    state stores no observables. Two contracts survive unchanged: reads never compute (decision 40's
    no-recompute contract), and ``\varepsilon``, ``k``, ``E(\kappa)`` still never become resident
    slots. The recorded homing rationale is also corrected here: the placement criterion for what
    lives upstream of `Generator` is **consumption inside `step!`** (the assembly's per-stage
    inputs), *not* a "measurement never feeds the dynamics" principle — that principle is false in
    mechanics (the Hamiltonian, an observable, generates the flow) and false in this package
    (`max_speed` sets the adaptive ``\Delta t``; `BandRescaling` holds a measured band energy);
    measured values steer the loop *between* steps, and nothing hard forbids this order — it is a
    design choice for a diagnostics module that stays optional per slot while its generics stand
    upstream.
47. **(2026-08, user-directed) The chart recoveries are not package verbs; the vorticity recovery is
    an observable.** The two chart recoveries `velocity_to_physical!` and `scalar_to_physical!` are deleted: each was the
    same two lines — copy the coefficients to scratch, transform — differing only in which of the
    domain's plan sets it bound, and once that composition deserved a *name*, invariant 2 sent it to
    the backend rather than keeping a physics-suffixed local copy. The general operation now lives
    in `GBGPeriodicFields` as the four-argument form `to_physical!(physical, spectral, plans,
    spectral_scratch)` (PF decision 64, raised as IT's round-3 request), and the call sites bind the
    plans themselves — `to_physical!(u, û, domain.velocity_plans, scratch)` at the closing deposit, the
    substage recoveries, and the displaced (`PhaseShift`) evaluations, where the preservation is
    load-bearing: the displaced velocity in spectral representation is read twice (velocity, then vorticity). The
    supersession also retires decision 28's `X_to_physical!` naming convention and narrows
    decision 30's "chart map homed in `State`" — the chart map is PF's operation; `State` keeps only
    the state and its seeders. What remains a package verb is the one recovery that is *not* a chart:
    **`vorticity_physical!`** — curl in scratch, then transform; no preservation copy, since the curl
    only reads its source — homed in `Observables` as the field-valued observable whose cached read
    is `Cache.vorticity_physical` — an f/`f!` **pair**, not decision 46's single dispatched generic, and
    the difference is structural rather than a drift: `max_speed` is a pure reduction, so one name can
    dispatch on whether it is handed a field or the cache, while a recovery *writes a field* and a
    checked read *returns one*, which no single name can carry. Decision 46's one-generic rule
    therefore governs reductions; a field-valued observable takes the pair, with the `!` form the home. Two consequences delimit the change: the two recovery regimes are now explicit —
    a consumable source calls the three-argument (destructive) form, as the strain diagnostic always
    has; a source of truth calls the four-argument form — and no `to_spectral!` twin exists or is wanted,
    because every forward transform in the package reads a consumable source by design (IC and
    forcing noise, quadratic products formed in place over registers the closing deposit refreshes). The umbrella
    re-exports no `GBGPeriodicFields` name, this operation included — the recovery is reached
    through the backend, as every other field operation is. Bit-identical: that form performs
    exactly the copy-then-transform the deleted wrappers performed, so the transform and pass
    ledgers and the memory audit are unchanged.
48. **(2026-08, user-directed) The iteration vocabulary: "closing deposit", not "tail"; no
    "boundary" for the instant between iterations.** Two informal house terms are retired from
    every surface, prose and code alike, after the user's documentation read-through flagged both
    as unclear ("tail" is not a standard term for the end of a loop body; "boundary" invites the
    spatial reading — on a triple-periodic box, of all packages). The **closing deposit** is the
    `deposit!` that ends an iteration ("tail deposit", "the tail", "at its tail" before); the
    instant between iterations is named plainly — *between iterations*, *the iteration's end*,
    *the instant* ``t_n`` — and the cache values carry the adjective **deposited** (the deposited
    velocity, the deposited observables) where "boundary velocity/observables" stood.
    `check_boundary` is renamed **`check_deposits`** (the deposit-completeness check), and the op
    model's `_tail_deposit`/`tail` become `_closing_deposit`/`closing`. Untouched, being different
    senses of the same words: the spatial box boundary, an ownership or kernel-granularity
    boundary, a spectrum's ``\kappa^{2}`` tail, and the phase-shift chain's final convolve
    (formerly "the phase-shift tail", now named for what it is). The rename swept the decision-log
    prose as well, so the log reads in the current vocabulary; this entry is the record that the
    older entries originally said "tail deposit" and "boundary".

49. **(2026-08, user-directed) A `Simulation` is a container, not a reading surface.** The run layer
    carried eight forwarding reads — `velocity_spectral(sim)`, `scalar_spectral(sim)`,
    `particle_positions(sim)`, `velocity_physical(sim)`, `vorticity_physical(sim)`,
    `scalar_physical(sim)`, `max_speed(sim)`, `particle_velocities(sim)` — plus
    `resolved_fields_modified!(sim)`. Every one is now removed. A quantity has exactly one route:
    the state through `sim.state`, a deposited observable through `sim.cache`, each read by the
    accessor that owns it. The forwarders bought a shorter call at the price of a second docstring
    per quantity to drift from the first, and of teaching the user a surface instead of the two
    objects the package is actually built from. The clock accessors `current_time` / `current_step`
    stay: the clock is the run layer's own state, not a forwarded read. The bundle `flow_parameters(sim)` stays
    for the same reason — it assembles a bundle from several owners rather than forwarding to one.
    `validate_spectrum` leaves the package altogether, to `test/validation.jl` as `compare_to_model`:
    comparing a run against a model spectrum answers "does this reproduce the literature", which is
    what a validation suite asks and a solver never does.

50. **(2026-08, user-directed) `Tracers` holds trajectory state; the trajectory scheme's registers
    are allocated per scheme, as on the field side.** Three of `Tracers`' seven fields —
    `predictor`, `predictor_points`, `predictor_velocity` — were one scheme's scratch, as its own
    docstring conceded in calling `predictor_velocity` "a stage register of the push". The field
    side had held the state/scratch line from the start (`ResolvedFields` versus `IntegratorBuffers`,
    built by `allocate_buffers` dispatching per scheme); the Lagrangian side did not follow it, so
    changing the scheme meant editing the state type. Now `AbstractParticleIntegrator` is the scheme
    family, `EndpointHeun` its one member, and `allocate_buffers(scheme, tracers)` builds a
    `ParticleIntegratorBuffers` — one generic across both sides, because it is one concept. The axis
    is recorded as planned in §7, and the scratch genuinely varies along it: a higher-order
    Runge–Kutta scheme wants several stage velocities, a multistep scheme wants a velocity *history*
    and no predictor at all, and an inertial particle wants ``\boldsymbol{v}`` as **state** rather
    than scratch. The split also disentangles `particle_velocities`'s two roles — the measured
    Lagrangian observable, and "the first half of the next push" — so a history-based scheme would
    not disturb the observable. Storage is unchanged, only reassigned: the memory audit now pins two
    ``(M, 3)`` arrays on each side rather than four on one.

51. **(2026-08, user-directed) *Particle* is the category, *tracer* the kind.** The public surface
    used three nouns for one set of objects — `particle_positions` beside `number_of_tracers` in a
    single export line, plus `particle_velocities` — with no convention stated anywhere. The rule is
    now: **name by what the operation is true of.** Anything true of the whole deferred ladder of §7
    takes *particle* — the positions, the count, the cache slot, interpolation at positions;
    only what is specific to the massless, internal-degree-of-freedom-free kind takes *tracer* — the
    `Tracers` type and its construction. Hence `number_of_tracers` becomes `number_of_particles` (a
    count is true of any kind) and `sample!` becomes `interpolate_at_particles!` (an inertial
    particle needs the same interpolation for its drag term, so the name survives the ladder
    unchanged). The verb `advect!` stays generic and dispatches per kind, its `EndpointHeun` method
    carrying the tracer-specific assumption that the particle velocity *is* the fluid velocity.

52. **(2026-08, user-directed) Constructor arguments: the object a value is derived from is
    positional, its settings are keyword.** Asked twice across two documentation read-throughs why
    some arguments were named and others not, and the honest first answer was that no rule was
    written down. The rule is the one the code had already half-adopted: a `FixedDomain` (or a
    `Tracers`, or the `FlowConditions` a generator wraps) is *what the value is built from* and
    stays positional; everything that configures the result is keyword. Round 1 applied "make them
    all named" to `FixedDomain` alone; the sweep now covers the class, and `Tracers` was its one
    remaining violator — `number_of_particles` and `positions` are settings, not source objects.
    One consequence is worth recording because it is not a free choice: keyword arguments do not
    participate in dispatch, so two all-keyword forms cannot be two methods. `Tracers` is therefore
    a single method requiring exactly one of `positions` or `number_of_particles`, with an
    `ArgumentError` naming the choice — a better error than a missing-keyword one, but a merge
    forced by the language rather than preferred.

53. **(2026-08, user-directed) "Stamp" is retired; a slot carries an **epoch**, and an epoch is not
    an iteration number.** The cache described itself as "stamped storage" and gave each slot a
    `*_stamp` field, while the two counters those fields were compared against were called *epochs* —
    two names for one integer, related only in a `#` comment. Asked whether "stamped storage" was a
    clear and standard term, the honest answer was that it is a house coinage, and that it never said
    stamped *with what*. One noun now serves both roles: the counters are epochs, and a slot's own
    epoch is the one its value belongs to; a slot is readable exactly when the two agree. The
    `*_stamp` fields become `*_epoch`, and the verb goes with the noun — a deposit *fills a slot and
    sets its epoch* rather than "stamping" it.

    The merge creates one hazard, so the `Cache` docstring now states it outright: **an epoch counts
    changes to the state, not advances of the run.** A completed `step!` advances the fields epoch,
    but so does any announced out-of-band mutation, so the two counts diverge: after two steps and one
    announced mutation the clock reads step 2 and the fields epoch reads 4 — measured, not assumed. The epoch answers "is this value still the right one?"; `current_step` answers "how
    far has the run gone?". As with decision 48, the sweep covered the decision log too, so the log
    reads in the current vocabulary; this entry records that the older entries originally said
    "stamp".

54. **(2026-08, user-directed) `BandRescaling`'s `over` is required, and the front door's `:total` is
    a calibration constraint rather than a preference.** *(The read-through pile recorded this as
    "not decided" and listed three options; the owner settled it in the review that followed, asking
    for the required form with the front door passing `:total`. The entry is written from that
    decision, not from the pile's open question.)* Decision 15 called `over` "a modeling choice
    with two defensible answers, so it is a selectable option rather than a fixed default" — and then
    defaulted it to `:band`, contradicting itself inside one sentence. It is now required, which the
    package's own defaults test (decision 28: method-canonical defaults, run-specific is required)
    demanded all along: *what does your run hold fixed?* is not a property of the method.

    The reason it matters more than an ergonomic slip: a deterministic clamp destroys the physical
    fluctuation of whatever it holds, so `over` decides **which quantity the run may no longer
    measure**. Under `:total` the kinetic energy is an artifact of the forcing and the band is free;
    under `:band` the band is the artifact and ``k`` is a measurable of the flow. A default silently
    made that choice for a user who might be measuring exactly the clamped quantity.

    The two surfaces had also disagreed — the constructor defaulted to `:band`, the `Simulation` front
    door overrode to `:total` — and investigating why settled the design. The override is **load
    bearing**: in grid mode the front door chooses ``\nu`` from the *assumed* kinetic energy through
    the box-normalized dissipation law, so the resolution criterion ``\kappa_{\max}\eta`` is
    self-consistent only if the run really holds ``k`` at that value, which is precisely what
    `:total` guarantees and `:band` does not. A hand-built forcing that nothing downstream calibrates
    against carries no such constraint, and `:band` is then the gentler clamp. The right answer
    genuinely differs by context — the strongest argument that no single default was right.

    Recorded alongside: `:total` zeroes the band when the out-of-band energy alone exceeds `target`.
    The docstring states what that is — the most violent intervention the strategy can make, not the
    absence of one.

55. **(2026-08, user-directed) `integrator` → `scheme` on the binding; the composite spectrum presets
    are types, not factory functions.** Two naming defects the panel found, both of the same kind: a
    name that reads as a promise the code does not keep.

    **The SciML false cognate.** In `DifferentialEquations.jl` an `integrator` is a *stateful* object
    — you hold it, step it, read `integrator.u`. Here `IFLowStorageRK3()` is a zero-field dispatch
    tag: the state lives in `ResolvedFields`, the scratch in `IntegratorBuffers`, and nothing is
    readable off the value. The internal evidence was decisive: `Propagator`'s own prose said
    *scheme* thirty times while the code said `integrator` at eighty-three sites. The binding is now
    `scheme` everywhere — the argument, the `Simulation` field, the front-door keyword — while the
    supertype keeps the name `AbstractIntegrator`, which is accurate for the *family*. One
    consequence had to be settled first: `Tracers` used `scheme` for its *interpolation* scheme, so
    two constructors would have taken one keyword for two concepts; it is now
    `interpolation_scheme`, which is the more precise name regardless. The parameter `pusher` becomes `scheme` too,
    so one word names the same role on both sides of the run.

    **The presets.** `Pope2000`, `VonKarman1948` and `Pao1965` were PascalCase *functions* returning
    a `ModelSpectrum`, so `spec isa Pope2000` failed and the phenomenology page carried a standing
    workaround telling readers to test the returned value instead. A workaround in user docs is
    interest paid on a naming decision. They are now type aliases —
    `const Pope2000 = ModelSpectrum{PopeLargeScale, PopeDissipation}` — which required no wrapper and
    no forwarding, because `ModelSpectrum` was already parameterized on exactly the two factors that
    distinguish a preset. Both `spec isa Pope2000` and `spec isa EnergySpectrum` now hold, every
    preset is a type, and the note is deleted. A preset therefore names a functional *form*; the
    fitted coefficients and the citation remain in the value.

56. **(2026-08, user-directed) The consumed operand is named for it: `ω_consumed`, `u_consumed`.**
    The `velocity_rhs!` assembly reads the vorticity and overwrites it; `scalar_rhs!` reads the
    velocity and overwrites it. Julia's convention is that a `!` verb mutates its *first* argument, so a caller
    reading either signature had no way to know a second one was destroyed — the fact lived only in
    the docstring notes.

    The behaviour stays, and the reason is invariant 4: the Lamb vector is formed in place over the
    vorticity's array and the scalar flux over the velocity's, which is exactly what keeps a product
    field in physical representation from existing anywhere. Passing a copy instead would buy
    signature purity for a resident ``N^{3}`` vector — the trade the footprint rule forbids. So the
    only available improvement was to move the warning from the prose into the signature, where a
    caller meets it.

    Which operand is consumed follows the **physics** rather than the argument position (the Lamb
    vector forms over the vorticity, the scalar flux over the velocity), which is why naming beats
    any positional convention here: there is no position rule to state, and a reader who looked for
    one would find a coincidence — both sit fifth — that does not generalize.

---

## References

Cited author–year above; full entries here, each with its DOI where the work has one. Three do not,
and the reason is stated with the entry rather than left to the reader to wonder about: a 1941
*Doklady* note, a NASA technical memorandum, and a CTR research brief predate or sit outside the DOI
system. A DOI here has been resolved against the registry, never recalled — an unverified identifier
is worse than none, since it silently sends the reader somewhere else.

The extraction-bound `Phenomenology` leaf (§4.8) is exempt: each reference law carries its own
self-contained citation in a `Reference` value, so this list need not duplicate the ~two dozen it
cites.

- Kolmogorov, A. N. (1941). The local structure of turbulence in incompressible viscous fluid for very
  large Reynolds numbers. *Dokl. Akad. Nauk SSSR* **30**, 301–305. *(No DOI: the 1941 Doklady notes predate the system.)*
- Betchov, R. (1956). An inequality concerning the production of vorticity in isotropic turbulence.
  *J. Fluid Mech.* **1**(5), 497–504. <https://doi.org/10.1017/S0022112056000317> *(The isotropy
  relations behind the strain-skewness constant, §4.3.)*
- Patterson, G. S. & Orszag, S. A. (1971). Spectral calculations of isotropic turbulence: efficient
  removal of aliasing interactions. *Phys. Fluids* **14**, 2538–2541. <https://doi.org/10.1063/1.1693365> *(Phase-shift dealiasing; the
  `PhaseShift` strategy, §7, decision 27.)*
- Orszag, S. A. (1971). On the elimination of aliasing in finite-difference schemes by filtering
  high-wavenumber components. *J. Atmos. Sci.* **28**, 1074. <https://doi.org/10.1175/1520-0469(1971)028%3C1074:OTEOAI%3E2.0.CO;2> *(The ``2/3`` truncation rule.)*
- Orszag, S. A. & Patterson, G. S. (1972). Numerical simulation of three-dimensional homogeneous
  isotropic turbulence. *Phys. Rev. Lett.* **28**, 76–79. <https://doi.org/10.1103/PhysRevLett.28.76> *(The pseudospectral method.)*
- Rogallo, R. S. (1981). Numerical experiments in homogeneous turbulence. *NASA TM-81315.* *(No DOI;
  a NASA technical memorandum. The sheared-frame scheme, §7; the spherical-truncation dealiasing of
  the `PhaseShift` strategy, decision 27.)*
- Hou, T. Y. & Li, R. (2007). Computing nearly singular solutions using pseudo-spectral methods.
  *J. Comput. Phys.* **226**, 379–397. <https://doi.org/10.1016/j.jcp.2007.04.014> *(The smooth spectral filter; the `HouLi` dealiasing strategy.)*
- Cichowlas, C., Bonaïti, P., Debbasch, F. & Brachet, M. (2005). Effective dissipation and turbulence
  in spectrally truncated Euler flows. *Phys. Rev. Lett.* **95**, 264502. <https://doi.org/10.1103/PhysRevLett.95.264502> *(Thermalization of the
  Galerkin-truncated conservative system; the ``\nu = 0`` oracle, §7.)*
- Chollet, J.-P. & Lesieur, M. (1981). Parameterization of small scales of three-dimensional isotropic
  turbulence utilizing spectral closures. *J. Atmos. Sci.* **38**, 2747–2757. <https://doi.org/10.1175/1520-0469(1981)038%3C2747:POSSOT%3E2.0.CO;2> *(The spectral eddy
  viscosity ``\nu_e(\kappa \mid \kappa_c)``; the deferred spectral large-eddy rung, §7.)*
- Eswaran, V. & Pope, S. B. (1988). An examination of forcing in direct numerical simulations of
  turbulence. *Computers & Fluids* **16**, 257–278. <https://doi.org/10.1016/0045-7930(88)90013-8> *(The stochastic Ornstein–Uhlenbeck forcing.)*
- Li, Y., Perlman, E., Wan, M., Yang, Y., Meneveau, C., Burns, R., Chen, S., Szalay, A. & Eyink, G.
  (2008). A public turbulence database cluster and applications to study Lagrangian evolution of
  velocity increments in turbulence. *J. Turbulence* **9**, N31.
  <https://doi.org/10.1080/14685240802376389> *(The box-normalized dissipation law `Li2008`, which
  sets ``\nu`` in the run layer's grid mode.)*
- Lundgren, T. S. (2003). Linearly forced isotropic turbulence. *CTR Annual Research Briefs*, 461–473. *(No DOI; a Center for Turbulence Research brief.)*
  *(The linear negative-damping forcing.)*
- Bussi, G., Donadio, D. & Parrinello, M. (2007). Canonical sampling through velocity rescaling.
  *J. Chem. Phys.* **126**, 014101. <https://doi.org/10.1063/1.2408420> *(Stochastic velocity rescaling; its deterministic limit is the
  Berendsen thermostat — no conserved quantity, no well-defined ensemble except in limiting cases —
  the caveat `BandRescaling` carries.)*
- Williamson, J. H. (1980). Low-storage Runge–Kutta schemes. *J. Comput. Phys.* **35**, 48–56. <https://doi.org/10.1016/0021-9991(80)90033-9> *(The
  2N low-storage family; the package's third-order coefficients are the low-storage set later adopted for spectral DNS and
  popularly named "RKW3"; it is also attributed to an unpublished 1986 note of Wray's, so this entry
  cites the family rather than a numbered case.)*
- Pope, S. B. (2000). *Turbulent Flows.* Cambridge University Press. <https://doi.org/10.1017/CBO9780511840531> *(Notation; the
  filtered-density-function Model and mixing models, §7–§8.)*
- Mori, H. (1965). Transport, collective motion, and Brownian motion. *Prog. Theor. Phys.* **33**,
  423–455. <https://doi.org/10.1143/PTP.33.423> *(The projection formalism, the foundation of §3 and §8.)*
- Zwanzig, R. (1973). Nonlinear generalized Langevin equations. *J. Stat. Phys.* **9**, 215–220. <https://doi.org/10.1007/BF01008729> *(The projection formalism, with Mori 1965.)*
- Morrison, P. J. (1986). A paradigm for joined Hamiltonian and dissipative systems. *Physica D* **18**,
  410–419. <https://doi.org/10.1016/0167-2789(86)90209-5> *(The metriplectic bracket formulation; the reversible/irreversible split, §4.2, §8.)*
- Öttinger, H. C. (2005). *Beyond Equilibrium Thermodynamics.* Wiley. <https://doi.org/10.1002/0471727903> *(GENERIC; the
  reversible/irreversible split, §8.)*
