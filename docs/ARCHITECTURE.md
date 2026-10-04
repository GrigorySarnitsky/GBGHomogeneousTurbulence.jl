# Architecture

!!! info "Written by AI, not regularly reviewed"
    This page is written by AI and is not reviewed regularly by a human.

This is the design document for `GBGHomogeneousTurbulence` — what the package is, how it is organized,
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

> `GBGHomogeneousTurbulence` **is** a small, focused pseudospectral direct numerical simulation (DNS) of
> homogeneous isotropic turbulence: one incompressible velocity field ``\boldsymbol{u}`` and one passive
> scalar ``\varphi`` on a triple-periodic box, advanced by interchangeable integrating-factor
> time-stepping, with Lagrangian particle probes and field sampling along their trajectories. It is a **library
> of composable pieces with a thin ergonomic run layer on top**, built as a *consumer* of
> [`GBGPeriodicFields`](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl) (the field and spectral
> machinery) and
> [`GBGStreamingStatistics`](https://grigorysarnitsky.github.io/GBGStreamingStatistics.jl) (the
> statistics — the division is settled and the bridge to it is deferred, §4.9).
>
> It **is not** a general PDE or CFD framework, and not multi-physics: the physics is a **thin, fixed
> core** — Navier–Stokes plus one passive scalar, no chemistry, phases, or processes. It is **not
> dimensional** — control is by Reynolds and Schmidt number, never units. It is **not** a field library
> (that is `GBGPeriodicFields`) or a statistics library (that is `GBGStreamingStatistics`), and it builds
> **no** speculative extension points — no generality ahead of a concrete need (§9).

The package inverts the richness of its sibling consumer
[`GBGCloudPhysics`](https://grigorysarnitsky.github.io/GBGCloudPhysics.jl): where Cloud carries a rich
constitutive physics over a thin numerical core, `GBGHomogeneousTurbulence` carries a **thin fixed physics
over rich, interchangeable numerics and statistics**. That inversion is the single fact that explains most
of what follows.

**The first scientific goal** is to measure the kinetic energy in box units
``\tilde{k} = k/(\varepsilon L)^{2/3}`` as a law ``\tilde{k}(\text{forcing}, \mathrm{Re}, \text{band})``,
integrate it so that a run's derived viscosity is calibrated for the forcing it actually uses, and
publish it (decisions 94 and 101). This ``\tilde{k}`` is the constant by which the run layer turns a requested
resolution into a viscosity, and the package's first sweep showed it is not universal. Until the law
exists, the run layer predicts with provisional values per forcing band (0.72 for shells 1–2, 0.56
for 1–4, 0.47 for every mode), flat in the Reynolds number.

---

## 2. Running a simulation

The primary measure of this library's quality is how easily one sets up and runs a case — including
**warm-up** to a statistically stationary state before any measurement. The headline interface is
therefore a thin run layer that assembles the machinery with sensible defaults and owns the time loop:

```julia
using GBGHomogeneousTurbulence

# Assemble a forced case. Everything the run needs — the domain, buffers, physics,
# scheme, state, and initial condition — is built with defaults from a few numbers.
sim = Simulation(grid_points_per_axis = 128, viscosity = 1e-2;
                 velocity_forcing = ConstantPower(injection_rate = 0.1),
                 scalar = true, schmidt = 1.0)

# Spin past the transient: advance until the running dissipation ε(t) stops drifting
# (k(t) is deliberately not used — a fixed-injection forcing like this makes it ring).
warmup!(sim)

# Observe and advance. The callback fires after every iteration (and once at the
# start); it records what it wants and its return decides continuation — stopping
# is the caller's decision.
energies = Float64[]
t_end = current_time(sim) + 20.0
run!(sim) do s
    push!(energies, kinetic_energy(s.state.velocity_spectral))
    current_time(s) < t_end
end
```

The run layer holds the pieces of §4 in one `Simulation` value. Each iteration it chooses a stable
timestep from the advective-CFL condition over the cached maximum speed (§4.5) and serves the
deposited observables from the deposit-driven `ObservablesCache` (§4.1). It runs the
**observation-first loop**: after every iteration, and once at the seeded ``t_0`` — ``n``
iterations, ``n+1`` observations — the callback reads the run and decides whether it continues
(§11 decision 43).
Spin-up is the packaged `StationarityCriterion` observation, `warmup!` its one-line sugar: it
advances until the flow is statistically stationary, watching the running dissipation
``\varepsilon(t)`` — a small-scale signal that settles late — rather than the kinetic energy a
constant-energy forcing clamps flat, with the velocity-derivative skewness ``S(t)`` an opt-in
second gate (`gate_skewness`, off by default since decision 78); §4.7 gives the exact stopping
test. A forced flow must reach statistical stationarity before a structure function
or a PDF taken over it means anything.

The composable pieces stay fully exposed: a study that needs to run the loop by hand, swap a stage, or
interleave a bespoke measurement drops straight to §4. The run layer is a convenience over that machinery,
never a wall in front of it.

> **Status.** The run layer is implemented (module `SimulationRun`) and covered by tests; the example
> above runs as written — a forcing can be named before its domain exists (`ConstantPower(injection_rate = 0.1)`, a
> `DeferredForcing`) and `warmup!` detects stationarity. The API may still evolve, since setup ergonomics is
> the package's primary quality target.

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
  turbulence, and — each deferred, §7 — uniform-mean-gradient scalar mixing (its source term is not
  yet built) and homogeneous shear (its frame is not). A System
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
pointed at different axes. Those functionals are exactly the Observables of §4.3. The machine is a
discipline the caller runs, not a component the package ships: the package provides the two sides —
the measured observables and the reference laws — and no public comparer (its own test suite
practices the comparison internally).

---

## 4. Modules

Each concern is its own module, included in dependency order by the umbrella
`src/GBGHomogeneousTurbulence.jl`. The four Mori–Zwanzig roles carry their role names — `State`, `Generator`,
`Observables`, `Propagator`; the System's forcing, the discretized frame, the Lagrangian instruments, the
run layer, and the reference laws are named by their job. The rule is that **a role recurring at every
rung of the ladder wears its role name, while a concrete mechanism wears its job** — so the load-bearing
structure is legible at a glance, and no piece of plain machinery is dressed in theory it does not carry.

### 4.1 `State` and `SimulationDomain` — the field and the frame it lives on

Two modules separate *what evolves* from the *frame it evolves on*.

- **`SimulationDomain`** provides the discretized periodic box the run lives on — the reusable,
  read-only frame. Its concrete type is the **`FixedDomain`**, the fixed, unsheared cube. It bundles the
  grid, the real–Fourier layout, and the real-to-complex transform plans — one rank-blind pair
  shared by every field, the velocity, the scalar, and the rank-2 strain tensor of the skewness
  diagnostic alike (decision 81), planned under the caller's `fft_flags` / `fft_timelimit` request,
  forwarded verbatim to the field library (a CPU lever — FFTW's default heuristic mis-plans
  single-precision transforms; the GPU libraries take no flag). On top of those
  sit the per-mode symbols: the spectral multipliers;
  ``\lvert\boldsymbol{\kappa}\rvert^2`` as a lazy radial kernel, never materialized (in spectral
  space ``-\nabla^{2}`` is multiplication by it, evaluated per mode — decision 38); the constant-1
  `unit_kernel` in the same lazy form, so a plain variance can join a fused multi-weight reduction
  (decision 63); and the dealias
  kernel of the run's chosen strategy (the sharp ``2/3`` rule by default), likewise a compressed
  symbol. The name marks what can vary: a `FixedDomain` has time-independent,
  separable wavenumbers, unlike the deferred sheared frame (`ShearedDomain`, §7). **Precision and backend enter here and flow everywhere
  from here**: `element_type` fixes the real element type
  ([`Float32`](@extref Julia Core.Float32) or `Float64`)
  and `array_type` the storage ([`Array`](@extref Julia Core.Array), `CuArray`, `ROCArray`), and every buffer is allocated `similar`
  to this frame, so a run is CPU/GPU-agnostic and single- or double-precision by construction.
- **`State`** owns the DNS realization of the Mori–Zwanzig State role. **`ResolvedFields`** is the
  record of the evolving fields in spectral representation — the velocity ``\hat{\boldsymbol{u}}`` and, when the run carries
  one, the scalar ``\hat\varphi`` — together with the `modeled` slot holding any forcing's evolving state
  (§8), and the *single source of truth*: the physical velocity, vorticity, and
  scalar are functions of it, never independent state. No operation hangs
  on it; the generator advances it and the observables read it, both as external functions of
  ``(\hat{\boldsymbol{u}}, \hat\varphi)`` — the reification the Mori–Zwanzig lens demands, kept a bare
  carrier so the operations acting on it, not the record itself, carry the design (§11 decision 26).

  The **chart map** — the recovery of the physical representations — is not a package verb. The
  velocity and scalar are recovered by the source-preserving four-argument form of
  `GBGPeriodicFields`' `to_physical!`, whose extra argument is a scratch field the transform consumes
  in the state's place, at the sites that consume them; the derived vorticity comes from
  `Observables.vorticity_physical!` (decision 47).

  The recovered values land in the **`ObservablesCache`** — its own module, `Cache`, included after
  `Observables`. That is the storage each iteration fills at its end with its observables: the
  physical velocity, vorticity and scalar, the maximum speed, and, when tracers ride the run, the
  velocity at the particles ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))``. It fills them under the
  no-recompute rule (`docs/src/observables_cache.md` is the design page; §11 decision 40).

  A slot IS its producer's register: the step takes the chart arrays as its
  substage recovery registers mid-iteration (their epochs go to *scratch*, so a mid-iteration read
  throws instead of serving a stage intermediate), and the closing `deposit!` re-fills them at the new epoch
  from the state the step just produced. An accessor (`velocity_physical`, `vorticity_physical`,
  `scalar_physical`, the cached `max_speed`) serves the deposited value or throws; no read ever
  causes a computation.

  Freshness is tracked by one epoch counter per dynamical factor of the run — fields, particles.
  A completed `step!` advances the fields epoch. An out-of-band mutation of the state's spectral representation is
  the one freshness event the cache cannot detect itself, so it is declared through
  `fields_modified!` — or, for an out-of-band edit of the tracer positions, through the particle-side
  twin `particles_modified!` — and followed by a `deposit!` before the run advances again (§11
  decision 30). The `State` module's initial conditions seed the state:
  `random_solenoidal_velocity_spectral!` fills a divergence-free velocity with a large-scale spectral envelope,
  rescaled to a target ``k``, and `random_scalar_spectral!` fills a mean-zero scalar to a target variance. The
  per-step scratch is **not** state: the scheme's registers live with the scheme (`IntegratorBuffers`
  in `Propagator`, §4.5) and the assembly scratch with the generator (`ResolvedGenerator`, §4.2).
  Each is preallocated, so a step allocates no field-sized memory (§9, invariant 4), and sized to
  the run — no scalar buffers when the run carries no scalar; GPU memory is tight. A `Simulation`
  composes the `ResolvedFields` and its `ObservablesCache`, and the time loop advances the state in
  place — each iteration a `step!` closed by the closing `deposit!`. Every concrete type of the
  package — the frame, the state, the cache, the forcings, the generator and its scratch, the
  register sets, the tracers and their scheme, the run, the stationarity records, the
  `Phenomenology` parameter records — carries a display in the field library's convention: one
  self-delimiting line carrying what the package refuses on, a REPL form where that line
  abbreviates, nothing reading an element (decision 87; the derived gate is `test/display.jl`).

### 4.2 `Generator` — the evolution, split reversible and irreversible

`Generator` realizes the Mori–Zwanzig generator: the right-hand side the propagator advances. Its physical
inputs are bundled in `FlowConditions` — the viscosity ``\nu`` (``\mathrm{Re} = u'L/\nu``:
``2\pi/\nu`` on the shipped defaults ``u' = 1``, ``L = 2\pi``, and ``1/\nu`` with the box side as the unit of length), the Schmidt number
``\mathrm{Sc}`` (scalar diffusivity ``\varkappa = \nu/\mathrm{Sc}``), and the two forcings; ``\nu`` and
``\mathrm{Sc}`` set the diffusion, the forcings the source, and folding this bundle into `Generator` is what
adds the `Generator → Forcing` dependency. It carries a
**metriplectic seam** — a reversible part that conserves energy and an irreversible part that dissipates
it (§8) — and the numerical split is built to honor it. The incompressible momentum equation is
advanced in **rotational (Lamb-vector) form**: writing the convective term through the identity
``(\boldsymbol{u}\cdot\nabla)\boldsymbol{u} = \nabla(\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^2) + \boldsymbol{\omega}\times\boldsymbol{u}``
(with vorticity ``\boldsymbol{\omega} = \nabla\times\boldsymbol{u}`` and the Lamb vector
``\boldsymbol{\omega}\times\boldsymbol{u}``, the literature's sign, decision 93) and letting the Leray–Helmholtz
projection ``\mathbb{P}`` onto divergence-free fields absorb the pressure and the kinetic-energy gradient,
the equation becomes

```math
\partial_t\boldsymbol{u} = -\mathbb{P} (\boldsymbol{\omega}\times\boldsymbol{u}) + \nu\nabla^{2}\boldsymbol{u} + \boldsymbol{f}.
```

Its three terms are the seam made explicit, and the time-stepping treats each according to its nature:

- **The reversible term.** The recoveries — the source-preserving four-argument `to_physical!` and
  the vorticity observable `vorticity_physical!` (decision 47) — produce the physical velocity and
  vorticity from ``\hat{\boldsymbol{u}}``; `velocity_rhs!` then assembles
  ``-\mathbb{P} (\boldsymbol{\omega}\times\boldsymbol{u})``, dealiased by the ``2/3`` rule to remove the
  aliasing of the quadratic product (the pseudospectral method; Orszag & Patterson 1972, the ``2/3`` rule
  Orszag 1971). Rotational form is the cheap way to compute the advection spectrally, and under a sharp mask the
  truncation is exactly Galerkin, so the discrete advection conserves kinetic energy (`HouLi`, which
  only damps, is the deliberately non-conservative strategy),
  and incompressible Euler is genuinely Hamiltonian — so this term is the flow's *reversible*,
  energy-conserving generator, stepped explicitly.
- **The irreversible term.** The diffusion ``\nu\nabla^{2}\boldsymbol{u}`` is the flow's *irreversible*,
  net-dissipative generator. Being diagonal in Fourier, it is integrated *exactly* through the flow map
  ``\mathcal{E}(\boldsymbol{\kappa}) = \exp\bigl((A(\boldsymbol{\kappa}) - D\lvert\boldsymbol{\kappa}\rvert^2) \tau\bigr)``
  — the exact propagator of the linear part over an interval ``\tau`` (a Runge–Kutta stage substep
  ``d_i\Delta t``, or the whole step ``\Delta t``), with diffusivity ``D = \nu`` for the velocity and
  ``D = \varkappa = \nu/\mathrm{Sc}`` for the scalar, and ``A(\boldsymbol{\kappa})`` an optional linear
  forcing rate (the source, below). ``\mathcal{E}`` is **never materialized** (decision 39): the factor
  pair `velocity_integrating_factor` / `scalar_integrating_factor` supplies its *parameters* — the coefficient on
  ``\lvert\boldsymbol{\kappa}\rvert^2`` and any steady forcing rate, fixed when the generator is built — and the backend's
  fused exponential convolution evaluates ``\mathcal{E}`` per mode as it applies it, advancing the
  diffusion with no stability restriction and no kernel field built or stored. ``\mathcal{E}`` is a *propagator*, a flow map over a step, not a generator;
  keeping the two apart is exactly the Generator/Propagator distinction of §4.5.
- **The source.** ``\boldsymbol{f}`` is the forcing, an external drive that is neither seam half (§4.4).
  When a forcing is *linear* in the field (``\boldsymbol{f} = A \boldsymbol{u}``) with a steady rate, that rate
  ``A(\boldsymbol{\kappa})`` is diagonal and linear like the diffusion, so it folds into the same
  exponential ``\mathcal{E}`` for exactness — and there it *injects* energy, ``\mathcal{E} > 1`` wherever
  ``A > D\lvert\boldsymbol{\kappa}\rvert^2``. So ``\mathcal{E}`` cross-cuts the seam: it carries the
  irreversible diffusion and, when the drive is linear and steady, the source. The seam is a decomposition of the
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
displaced-evaluation buffers, any steady forcing rate — in physical representation each
quadratic product forms in place over an operand's own register, §11 decision 41), behind a six-verb
protocol —
`prepare!` opens the step (advances each forcing's evolving state),
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
- ``\texttt{energy\_spectrum} \equiv E(\kappa)``, the halved `GBGPeriodicFields` radial spectrum
  over the shell width — the **density**, the same object a model law gives — and `integral_scale`
  derived from it;
- `kinetic_energy_and_dissipation_below_scale`, the kinetic energy ``k(l)`` and dissipation
  ``\varepsilon(l)`` held in scales below each box side ``l`` the grid offers — what a box of side ``l``
  measures once its own mean velocity (or vorticity) is removed, averaged over its positions — as the
  weighted reductions ``\tfrac{1}{2}\sum(1 - W_l^2)\lvert\hat{\boldsymbol{u}}\rvert^2`` and
  ``\nu\sum\lvert\boldsymbol{\kappa}\rvert^2(1 - W_l^2)\lvert\hat{\boldsymbol{u}}\rvert^2`` over
  `GBGPeriodicFields`' top-hat window (decision 96).

These are not incidental: they are the **fitness functionals** the comparison machine of §3 evaluates,
and the stationarity signals `warmup!` watches. They are also the *measured* half of the validation
harness whose *predicted* half is `Phenomenology` (§4.8).

### 4.4 `Forcing` — the source

Forcing is the System's energy-injection strategy — the source term ``\boldsymbol{f}`` of §4.2, and the one
deliberately designed-in extension point. `AbstractForcing` is the supertype; a forcing enters the
step through a small interface of four methods, plus `initial_forcing_state`, which starts
the state the first of them advances; each defaults to doing nothing:

- `prepare_forcing!` — advance the forcing's evolving state once per step (a stochastic process),
  a state `initial_forcing_state` starts and the run's `ResolvedFields` keeps;
- `steady_linear_rate` — for a forcing *linear* in the field (``\boldsymbol{f} = A \boldsymbol{u}``) and steady in
  time: return the rate ``A(\boldsymbol{\kappa})``, folded into the integrating factor; handed no field,
  it is steady by construction;
- `add_forcing_source!` — add an additive source at each Runge–Kutta stage;
- `project_forcing!` — apply a post-step projection or rescale.

The hooks form one lifecycle with a fixed order — `steady_linear_rate` once, when the generator is
built; then per step `prepare_forcing!` before the stages, `add_forcing_source!` at every stage,
`project_forcing!` after the completed step — and the rate and the source are two channels of *one* forcing term (the exactly linear
part folded into ``\mathcal{E}``, the remainder added at stages). A strategy owns whatever scratch its
hooks need; none receives the scheme's buffers (§11 decision 32). What a strategy *evolves* is not
scratch: it lives in the `modeled` slot of `ResolvedFields`, so that one record is the whole
evolving state of the run (§8's open-systems reading; §11 decisions 23 and 90).

Which hook a strategy uses is not an implementation detail: it decides whether the strategy preserves
the scheme's order in time. A rate folded into ``\mathcal{E}`` is integrated **exactly**, but only a
*steady* rate can be — freezing a state-dependent one at the step's start is the left-endpoint
rectangle rule on ``\int A\,\mathrm dt``, which is first-order however good the scheme is, and a
post-step projection is Lie–Trotter splitting, first-order by construction. So a state-dependent
forcing belongs in the source, where the scheme's own stages integrate it. Measured on the
third-order `IFLowStorageRK3`: every source-routed forcing converges at 3.01, the projection at 1.02.

Six strategies are provided. `NoForcing` (free decay) and `Linear` (fixed-rate negative damping,
Lundgren 2003) — the latter the one steady rate, folded into ``\mathcal{E}`` and therefore exact and
free. `ConstantPower` (holding the injection rate) and `VarianceController` (holding the field's
``L^2`` observable: the kinetic energy for the velocity, the scalar variance for the scalar; the
constant-``k`` controller of Bassenne et al. 2016, Eq. 20) both carry state-dependent rates and enter
through the source at every stage; the controller's proportional restoring term makes its target a
stable attractor rather than a clamp. `ConstantPower` is the **default velocity forcing**, chosen
because it has no gain or settling time to choose (decision 95).
`VarianceRescaling` (rescaling a band to hold the same observable — `over = :band | :total`) is the
one post-step projection, kept as the reference implementation of a published method (Sullivan,
Mahalingam & Kerr 1994) with its first-order caveat and its Berendsen-class caveat (Bussi, Donadio &
Parrinello 2007) documented rather than hidden. `StochasticOU` (Eswaran & Pope 1988) is the one
strategy independent of the flow it drives: an exact Ornstein–Uhlenbeck process on the band's conjugate
mode pairs, drawn on the host, advanced on the run's backend and added at every stage, holding nothing field-sized. **One
implementation serves both** the velocity (a vector field) and the scalar (a scalar field), because
these methods are written through tensor-order-generic field operators; the only field-specific step a
forcing can need is the solenoidal projection of the velocity, which the field-proportional strategies
never need (each preserves a divergence-free velocity by construction) and `StochasticOU` applies per
mode, drawing each amplitude perpendicular to its wavevector. Each forcing has a constructor taking the `FixedDomain` and a keyword form taking none; `NoForcing`,
taking no domain, has only the one. The keyword form — `ConstantPower(injection_rate = 0.1)` —
returns a `DeferredForcing`, materialized when `Simulation` builds the frame, so a case can name its
forcing before the grid exists. A velocity forcing named so may also leave its strength out, and
`Simulation` fills it from the run's predicted stationary state: the pair ``(k, \varepsilon)``, stated
once — by `kinetic_energy`, `dissipation`, or a forcing's own target — with the other member, and the
band's energy ``k_{\mathrm{band}}``, predicted by `predicted_stationary_state` through the forcing's
``\tilde{k}`` and ``k_{\mathrm{band}}/k`` (decisions 95, 105). That fills `Linear`'s rate
``\varepsilon/(2k_{\mathrm{band}})`` and `VarianceRescaling(over = :band)`'s target ``k_{\mathrm{band}}``
too. A scalar forcing states its target, since no scalar state is modelled.

### 4.5 `Propagator` — the map that advances the state in time

`Propagator` realizes the Mori–Zwanzig propagator: the map that carries the state forward in time, built
on the generator's reversible/irreversible seam. Its numerical schemes are the Model-fibered part of the
Method (§3).

- **`AbstractIntegrator`** is the family of integrating-factor schemes dispatched by **`step!`**, which
  advances the velocity ``\hat{\boldsymbol{u}}`` and scalar ``\hat\varphi``, both in spectral representation, **together** through
  the same Runge–Kutta stages. Coupled stepping is deliberate: the scalar is passive, so time-accuracy
  needs both nonlinear terms evaluated at each stage's state; advancing the velocity fully and the scalar
  afterward would drop the substage velocities and degrade the coupling to first order.
- **`IFLowStorageRK3`** (the Williamson 1980 2N-storage / RKW3 workhorse) is third-order and imaginary-axis stable;
  **`IFHeun`** (Heun) is a two-stage option, cheaper in transforms (two nonlinear evaluations against
  three) but *dearer* in memory and imaginary-axis unstable, leaning on viscous damping. The memory
  comparison counts the solver's scratch registers per field: `IFHeun` carries three (a predictor
  plus two stage registers that double as its assemblies) against `IFLowStorageRK3`'s two (an
  accumulator plus the assembly register). Williamson's own "2N" label counts differently — the
  state's array plus the accumulator, the assembly excluded as the solver's, not the scheme's (the
  `IFLowStorageRK3` docstring keeps that ledger); the two bookkeepings agree on the point that
  matters, one register in `IFHeun`'s disfavor. Two more schemes share `IFLowStorageRK3`'s two
  registers: **`IFLowStorageRK4`** (Carpenter & Kennedy 1994) is fourth-order in five stages of the
  same 2N-storage form, its ``1.93\times`` wider imaginary-axis stability limit buying fewer transforms per
  unit time on a stability-limited run (decision 85); **`IFSSPRK3`** is the Shu–Osher third-order
  SSP scheme in TurTLE's stage arrangement, kept for code-to-code validation against that
  reference (decision 80). The [`recommended_cfl`](@ref) helper gives each scheme its conservative advective-CFL ceiling
  ``C_{\mathrm{CFL}}`` (for
  ``\Delta t = C_{\mathrm{CFL}} \Delta x/\max_{\boldsymbol{x}}\lvert\boldsymbol{u}\rvert``), which the run layer uses with `max_speed` to choose
  ``\Delta t``.
- **Two linear constraints are re-imposed on the advanced state at every step's exit**, after the
  forcing's post-step hook: the divergence-free condition, by the field library's
  `helmholtz_projection!` (decision 61), and the reality condition on the real-to-complex layout's
  self-conjugate planes, by its `reality_projection!` (decision 88). Neither is held by the
  discretisation by construction; both are seeded at round-off and, for the reality condition,
  amplified by any forcing proportional to the field, so each is pinned at round-off — the reality
  one at exactly zero — once per step rather than left to compound.
- **`IntegratorBuffers`** is the scheme's own per-step scratch — the Runge–Kutta stage registers,
  and nothing in physical representation (the substage recoveries write into the cache's slots,
  decision 40) — built by `allocate_buffers` dispatching on the
  concrete scheme, so each allocates exactly its working set. The right-hand-side *assembly* scratch
  lives with the generator on the `ResolvedGenerator` (§4.2), and the start-of-step physical fields are
  the observables cache's charts (§4.1): a `step!` is stage arithmetic over the generator protocol and
  the scheme's registers, nothing more. None of this scratch is state (§11 decisions 26, 30, 31).

### 4.6 `Particles` — Lagrangian instruments

Particles are **instruments** — probes of the turbulence — not a second physics. A particle is a
state-carrying trajectory object: today a tracer (position ``\boldsymbol{x}``); the deferred ladder is
inertial (``\boldsymbol{x}, \boldsymbol{v}``) and oriented (``\boldsymbol{x}, \boldsymbol{v}, \boldsymbol{L}``)
probes (§7). `Tracers` holds positions and a chosen interpolation scheme — trajectory **state** only,
with the particle integration scheme's registers held apart in a `ParticleIntegratorBuffers` allocated per
scheme, exactly as `ResolvedFields` is held apart from `IntegratorBuffers` on the field side
(decision 50). The default scheme, `Heun`, is Heun-in-time on
the velocity at the iteration's two endpoints. The first, ``\boldsymbol{v}_1``, is the **trajectory
sample** ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` recorded by the previous closing deposit — the genuine
Lagrangian velocity, held in the observables cache's own `velocity_at_particles` slot and dated
against BOTH epochs, since it is a function of the state and the positions together (read through
`velocity_at_particles`, §11 decisions 42 and 67). The second, ``\boldsymbol{v}_2``, interpolates the just-deposited
``\boldsymbol{u}(t_{n+1})`` at the Heun **predictor** positions, which no tracer ever occupies:
`ParticleIntegratorBuffers.velocity_predictor` is a stage register of the scheme. After the push, the particle form of
`deposit!` interpolates the new sample at the new positions from the same deposited field and
stamps it at the current epochs — one closing act per dynamical factor, `step!` then `deposit!`,
`advect!` then `deposit!` — completing the iteration's deposits; `interpolate_at_particles!` reads
any field along the trajectories for Lagrangian statistics.

The sample deposit is what keeps an ``M``-point instrument at ``M``-point cost: depositing the sample
at the particles stores ``M\times3`` values where retaining the endpoint field would cost an
``N^{3}\times3`` resident buffer and copy. Tracked and untracked runs therefore have identical
field-scale residency and per-step traffic — the zero both audits assert. (One tempting reuse is
recorded as **forbidden**: ``\boldsymbol{v}_2 \approx \boldsymbol{u}(t_{n+1},\boldsymbol{X}^*)``
differs from the next sample only at ``\mathcal{O}(\Delta t^{2})``, so reusing it as the next
``\boldsymbol{v}_1`` looks like a free interpolation saved — but it corrupts the recorded observable
the Lagrangian statistics accumulate. Never approximate the thing you measure.)

Their **numerics are first-class**, on the same footing as the field schemes — and pluggable in the
same way: `AbstractParticleIntegrator` is the family, `allocate_buffers(scheme, tracers, cache)` builds its
registers. Two axes matter: the particle integration scheme — the default second-order `Heun`, and the
variable-step `AdamsBashforth` (order 4 by default, its sample history held in the observables cache
and its weight scratch in the shared `ParticleIntegratorBuffers`; decisions 57 and 70) for a run whose trajectory accuracy in
time limits a measurement — and the sampling-consistency axis, the interpolation scheme's order
relative to the field's spectral accuracy (`CatmullRom` by default, higher-order `LalescuSpline` /
`LagrangeSpline` available).
The gathers themselves visit the tracers in a memory-locality order, the `ParticleTraversal` — a
value-preserving accelerator (the interpolated values are bit-identical with or without it) that
`Simulation` owns beside the tracer set and rebuilds every iteration by default, the
`ordered_interpolation` setting choosing a manual cadence instead (decision 86).
When the inertial and oriented probes arrive, the integrating-factor split carries over for the
*translational* stiff drag (field viscosity and a particle's linear or matrix drag are the same
linear-exact move), while **orientation dynamics on the rotation group is a distinct geometric
scheme** — the reversible generator of §8 again — so the split does not naively unify all of it.

### 4.7 `SimulationRun` — the front door

A `Simulation` value bundles what one iteration advances and reads — the present instant (the one
bounded look-back is the cache's Lagrangian sample history, which a multistep particle scheme
needs): the `FixedDomain`, the `ResolvedFields` state (the
fields ``\hat{\boldsymbol{u}}`` and ``\hat\varphi``, in spectral representation, the generator acts on), the `ObservablesCache`
observables cache, the `ResolvedGenerator` (carrying the `FlowConditions`), the `IntegratorBuffers`
scheme registers, the chosen `AbstractIntegrator`, any `Tracers` with its own
`AbstractParticleIntegrator`, `ParticleIntegratorBuffers` and gather-order `ParticleTraversal`
(decision 86), a stored CFL ceiling and step ceiling, and a clock.
Over it:

- **`Simulation(...)`** — the assemble-with-defaults constructor: from a grid size and a forcing it
  builds every piece of §4.1–§4.6, seeds a divergence-free initial condition — or adopts an
  existing state and tracer set outright (the injection door, decision 83) — and picks the default
  scheme. The viscosity is derived from the grid by default — the highest Reynolds number consistent with the
  chosen resolution criterion `κ_max_η` (decision 20; measured against the resolved cutoff, decision
  82), solved from the ε of the run's predicted stationary state (decisions 95, 105) — with a supplied
  `viscosity` the opt-in override. A forcing holding ε, the default, meets `κ_max_η` in the stationary
  mean; one holding k leaves the resolution predicted through ``\tilde{k}``. A forcing the model does not
  cover — an unforced run, a band not starting at shell 1 — has nothing to derive ν from and must
  supply it.
  Setup is a few numbers.
- **`advance!(sim)`** owns one iteration: ``\Delta t`` from the scheme's CFL over the cached
  maximum speed (scalar arithmetic — the previous closing deposit measured it), `step!`, the closing `deposit!`,
  the tracer advance on the sample and the deposited endpoint field, the new sample, and the
  deposit-completeness check. **`run!(callback, sim)`** is the observation-first loop over it: the callback
  observes the run after every iteration (and once at the seeded ``t_0``) and its `Bool` return decides continuation —
  stopping is the caller's decision on observables, never a run option (§11 decision 43).
- **`StationarityCriterion`** is the packaged spin-up observation, and **`warmup!(sim; ...)`** its
  one-line sugar: stationarity detection on the running dissipation ``\varepsilon(t)`` — a
  trailing-window flatness test that **gates** on ``\varepsilon`` rather than on the clampable
  ``k(t)``, though ``k`` is still measured, to normalize the eddy-turnover clock
  ``\Delta t \varepsilon/k``. The velocity-derivative skewness ``S(t)`` is an opt-in second gate
  (`gate_skewness = true`; off by default since decision 78, its rank-2 transforms being a per-call
  cost the default path does not pay). When the scalar is forced, ``\langle\varphi^2\rangle`` must
  settle too (`gate_scalar`, on by default). A fixed budget is a three-line callback, not a run option.
- **A `Simulation` is a container, not a reading surface** (decision 49). The state is read through
  `sim.state` and the deposited observables through `sim.cache`, each by the accessor that owns it —
  `kinetic_energy(sim.state.velocity_spectral)`, `velocity_physical(sim.cache)`,
  `point_positions(sim.tracers.positions)` (decision 72: the raw view is `GBGPeriodicFields`'
  own accessor, not a forwarding method of this package). 
- **`write_simulation` / `read_simulation`** — the HDF5 checkpoint (decision 75): one
  self-describing group fully restores the run, recursively composed of the per-object pairs
  (`write_domain`, `write_state`, `write_tracers`, `write_forcing`) with the field library's
  `write_field`/`write_points`/`write_scheme` groups as the leaves. Nothing derivable is stored —
  the reader rebuilds through the constructor and replays the seeding deposits — and the methods
  live in the `GBGHomogeneousTurbulenceHDF5Ext` weak-dependency extension, so the surface exists
  only when `HDF5` is loaded.
- **`current_time(sim)`** and **`current_step(sim)`** report the run's time and step count, and the observables applied to
  `sim.state` (e.g. `kinetic_energy(sim.state.velocity_spectral)`, `dissipation` on the recovered vorticity) are
  the current-state diagnostics, for a callback to read.

The layer wires §4.1–§4.6 together and holds no physics or numerics of its own.

### 4.8 `Phenomenology` — the reference laws (extraction-bound)

`Phenomenology` is the library of **reference turbulence phenomenology**: the fitted scalings, model
spectra, structure-function laws, and dimensionless constants that theory and experiment have established.
It is the **symmetric counterpart to `Observables`** — those are the *measured* functions of the DNS
state; these are the *predicted* values of the same functions. The DNS measures, the laws predict, and the
comparison machine of §3 sets them side by side. Two properties follow, both instances of the charter
*investigate the physics, do not assume it*:

- **A provider, not a comparer.** A law evaluates itself from the flow parameters; it knows nothing of the
  DNS. The comparison lives consumer-side — the caller's own analysis, or a test suite — reading
  both; the package ships no comparer.
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
handle `Phenomenology.Spectra.Pope2000` reads like a citation and is unique by construction — and
where a preset's value is *not* read off its name's paper (`Sreenivasan1995`'s as-quoted value), the
docstring says so at the value.

**Submodules are cut by representation, so they stay few** while the models multiply as subtypes:

- **`Spectra`** — functions of ``\kappa`` (velocity ``E(\kappa)``, scalar ``E_\varphi(\kappa)``),
  **composed**: an inertial core ``C_K \varepsilon^{2/3}\kappa^{-5/3}`` times a swappable large-scale
  factor ``f_L(\kappa \ell)`` — each form evaluated at the length its own coefficient was fitted against — and dissipation-range factor ``f_\eta(\kappa\eta)``, a named preset fixing a
  published triple.
- **`StructureFunctions`** — functions of ``r`` (the ``D_{L\dots}(r)`` laws and, sharing the
  representation, any two-point correlation law when one is added).
- **`Scalings`** — the dimensionless numbers and their ``\mathrm{Re}_\lambda`` trends: the Kolmogorov
  constant ``C_K`` (`Sreenivasan1995`) and the normalized dissipation constant ``C_\varepsilon``
  (`Sreenivasan1998`). The derivative skewness, the flatness, the
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
**self-contained namespace**: the umbrella does *not* re-export it (`using GBGHomogeneousTurbulence` brings
the DNS API only; the laws are reached opt-in through `Phenomenology`), and its notation and API pages form
their own group, separable from the DNS surface. Extract when a second consumer appears; until then the
seam is real but uncrossed (decision 18).

### 4.9 Layout summary

`SimulationDomain → Observables → State → Cache → Forcing → Generator → Propagator → Particles →
SimulationRun`.
Cross-module access is through explicit `using ..Module: name` lists; `Phenomenology` (§4.8) leads this
order as the dependency-light leaf the initial-condition and validation consumers read.
Statistics live consumer-side of this package too: the sampling in `Particles` and the observables in
`Observables` produce the *samples*, and a statistics bridge that streams them to `GBGStreamingStatistics`
is deferred (§7).

---

## 5. The consumer boundary — what belongs here, and what does not

`GBGHomogeneousTurbulence` owns the turbulence-specific glue and delegates everything domain-neutral. The
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

- **Both precisions are supported equally, and no kernel privileges either.** (The `Simulation`
  constructor must start somewhere and starts at `Float64` / `Array`; that is a convenience
  constructor's choice, not a property of the library, and `FixedDomain` takes both from the caller.) `Float32` buys twice the
  grid per byte and roughly twice the throughput on a consumer GPU; `Float64` buys the accuracy
  margin a long integration or a sensitive diagnostic may need. Which one a run wants is a fitness
  question, settled by test rather than by a house default. The element type
  ``T`` flows from the frame (§4.1): no kernel silently fixes the arithmetic. (The `FlowConditions` scalar
  parameters are stored `Float64` and converted to ``T`` at use — a scalar convenience, not a field
  commitment.) Field reductions do **not** break this: every observable returns the field's own element
  type, so a `Float32` run measures in `Float32` — the `Observables` module docstring states it and
  `test/validation.jl` pins it over every exported observable. Accuracy is bought there by
  *summation order*, not by a wider accumulator: the backend's reductions sum pairwise, whose error grows as
``O(\log n)`` against naive accumulation's ``O(n)``, so a reduction over an ``N^3`` grid stays
faithful in the field's own precision and needs no `Float64` accumulator to rescue it. Whether the online statistics of a
  future `GBGStreamingStatistics` bridge should accumulate in `Float64` regardless is a question for
  that backend, not a property of this one.
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

- **The uniform-mean-gradient scalar source** — the standard scalar-injection route
  (``-u_i \partial_{x_i}\langle\varphi\rangle`` with an imposed mean gradient), the missing piece of the
  mean-gradient mixing System named in §3. A forcing-strategy slice, not a frame change.
- **Stochastic (Eswaran–Pope OU) forcing — DELIVERED (decision 90).** Archived while its dense form
  drew a field of noise on the host every step; returned as a coarse companion field, with its process
  in the run's state.
- **Checkpoint / exact restart to HDF5 — DELIVERED (decisions 75, 90).** Five writer/reader pairs,
  composed recursively on the field library's persistence groups, restore a run that continues
  bitwise (§4.7), a stochastically forced run included: its process and its position in the stream
  are part of the stored state.
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
  negative linear-forcing citizen folded into the integrating factor as the steady rate of a `Linear` forcing
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
- **The ``\nu = 0`` truncated-Euler experiment — a scheme and dealiasing oracle.** At zero
  viscosity (accepted today; the integrating factor degenerates to the identity) the sharp-masked
  assembly is the exact Galerkin truncation of the Euler equations, which conserves kinetic energy in
  continuous time — so measured energy drift isolates the time scheme alone: a
  conservation and order-of-accuracy test on `IFLowStorageRK3` (the drift must scale with the
  scheme's order; at ``\nu = 0`` `IFHeun` is excluded — its stability rests entirely on viscous
  damping, which the oracle removes, so it would measure an instability, not an order), a second
  witness that the sharp-cutoff strategies (`TwoThirds`, `PhaseShift`) are exactly Galerkin (an alias residue breaks the detailed
  conservation of the retained triads), and a direct measurement of the Hou–Li filter's effective
  dissipation (the one deliberately non-conservative strategy). The long run is a validation target of
  its own: the truncated system thermalizes toward absolute equilibrium — an equipartition
  ``E(\kappa) \propto \kappa^{2}`` tail growing from the cutoff, the thermalized tail acting on the
  large scales like an eddy viscosity while it grows (Cichowlas et al. 2005). It is not a turbulence
  run — the dissipation-based diagnostics degenerate (``\varepsilon \to 0``, ``\mathrm{Re}_\lambda``
  undefined) — and it is deferred as a *test*, not a capability.

---

## 8. Lenses and prior art

**One piece of prior art is excluded outright: the previous generation of this work** (the private
`OldCode` archive among the study-only clones). It is *not* among the lenses below and is not a
source of design. It is retained
only as a record to interrogate: what was done before, and what came of it. The direction of the GBG
packages is to replace it entirely, because it was problematic, and this architecture is the
replacement rather than a refinement of it. It follows that nothing here is justified by continuity
with it — an arrangement it shared is neither evidence for nor against the arrangement here, and must
stand on the reasoning in this document (the same rule §11 applies to a recorded decision: legacy is
not evidence of correctness). Where it is consulted, the product is a diagnosis, not a pattern.

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
  **Markovian surrogate** kept on the system's own side, a *modeled* degree of freedom; so it homes as
  the `modeled` slot on the one `State`, never a separate "environment state" — built for the
  stochastic forcing's process (§11 decision 90).
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
  Triangularity is what licenses the composed propagator: splitting error cannot propagate *up* the
  triangle. It also gives every state slot a litmus. **The restart record holds exactly what the
  flow map needs** — ``\hat{\boldsymbol{u}}``, ``\hat\varphi``, the tracer positions, and a
  stochastic forcing's internal state (the extended-phase-space discipline of molecular dynamics'
  thermostats). The observables cache holds spent compute, reconstructable from the record —
  delete it and the trajectory is unchanged. The clock and what a run records are the
  experimenter's logbook rather than physics. The
  `ObservablesCache` charts are the tower's *algebraic* variables — solved, never integrated — and their
  per-factor epochs inherit the triangle: a chart is stale against exactly the factors it reads.

---

## 9. Invariants — the deliberate absences

The public surface and these absences are the spec. Do not add a capability "for completeness"; a missing
one usually encodes a decision.

1. **No physical units.** Quantities are dimensionless, on the box's order-one reference scales;
   control is by ``\mathrm{Re}`` (through ``\nu``) and ``\mathrm{Sc}``, and the reference constants a run
   is judged against — ``C_K``, ``C_\varepsilon``, and the kinetic energy in box units
   ``\tilde{k} = k/(\varepsilon L)^{2/3}`` — are dimensionless groups.
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
   (an `IFLowStorageRK3` run carries neither of the two registers `IFHeun` adds — its corrector stage
   and its velocity predictor).
5. **GPU-first, single-node, backend-agnostic.** Shared-memory only; no distributed or multi-GPU scope
   (inherited from `GBGPeriodicFields`).
6. **No baked-in physical model, closure, or universality assumption.** The tool investigates these; it
   does not assume them (§8). The Mori–Zwanzig foundation is exempt because it is *exact*, not a model — a
   projection is an identity, and what remains modeled is the closure the tool is built to test (§3).
7. **A library, not a framework.** The run layer is a convenience over exposed pieces (§2, §4.7), never a
   mandatory shell.
8. **The scalar is denoted ``\varphi``**, never ``\theta`` — in code, mathematics, and prose.
   And it is an **``\mathrm{Sc} = O(1)`` scalar**: no Batchelor-range machinery exists, the derived
   viscosity resolves the velocity's cutoff rather than ``\eta_B = \eta/\sqrt{\mathrm{Sc}}``, and the
   constructor warns — never refuses — when the scalar is clearly under-resolved. High-Schmidt
   support is a deliberate absence, not an oversight.
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
  category/type-error class above. The rulebook's programs and `checkdocs = :exports` are the
  mechanical backstop.
- **Citations** follow author–year; the full references are §References. Never cite an inaccessible source;
  the material under `inspiration/` is private and never referenced. A reference *block* of two or more
  citations is a bullet list — one citation per line — never a semicolon-joined paragraph.

---

## 11. Decision log

The log is append-only, and each entry stands on its own. Dates are given as `YYYY-MM`.

1. **(2026-06) Integrating-factor split with exact diffusion.** The stiff viscous/diffusive part is
   integrated exactly by ``\mathcal{E}(\boldsymbol{\kappa})``; only the advection is explicit. Removes the
   diffusive stability limit and preserves scheme order under linear forcing.
2. **(2026-06) Rotational (Lamb-vector) form for the advection.** Cheap spectral advection; the
   reversible generator of the geometric lens. *(The energy conservation this entry originally
   credited to the form is really the sharp mask's: under a truncating band the truncation is exactly
   Galerkin, so the discrete advection conserves kinetic energy — `HouLi`, which tapers rather than
   truncates, is deliberately non-conservative. §4.2.)*
3. **(2026-06) `IFLowStorageRK3` (Williamson 2N-storage / RKW3) is the default; per-scheme CFL.** Third-order,
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
    "real turbulence yet" gate, whose default floor is a permissive one: raise it to ``0.4`` when the
    run must be strict, against the ``\lvert S\rvert \approx 0.5`` of a developed cascade (``S`` runs from ``0`` toward ``\approx -0.5``). When the scalar is
    forced, ``\langle\varphi^2\rangle`` must flatten too — the scalar reaches stationarity after the
    velocity. A fixed turnover/time/step budget is the explicit alternative. *(Follows the warm-up
    literature.)*
14. **(2026-07) Operator-free forcing construction.** `ConstantPower(injection_rate = 0.1)` (and the other banded
    forcings) return a `DeferredForcing` capturing the parameters, materialized into the concrete
    `AbstractForcing` once `Simulation` builds the domain — so a case names its forcing before the grid
    exists. The operator-taking constructor is unchanged. *(Originally the keyword was `power` and the
    return type `ForcingSpec`; both since renamed — `power` → `target`, `ForcingSpec` → `DeferredForcing`
    — decision 25.)*
15. **(2026-07) `VarianceRescaling` can hold the band *or* the total energy (`over = :band | :total`).**
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
    their relative ``L^2`` discrepancy. The two sides are not the same kind of object and the
    comparison must convert: `energy_spectrum` returns the per-shell energy ``E_n``, a model returns
    the density ``E(\kappa)``, and ``E_n \approx E(\kappa_n) \Delta\kappa`` with
    ``\Delta\kappa = 2\pi/L``. The factor is invisible on the default ``L = 2\pi`` box, where it is
    ``1``, and silently wrong on any other. *(Superseded 2026-08-23, owner-directed:
    `energy_spectrum` now returns the **density** — the shell energy over ``\Delta\kappa`` — so the
    conversion seam this entry documents is gone; measured and modeled spectra are the same kind of
    object and compare directly. The bin-sum convention had survived precisely because the factor
    is 1 on the default box.)* This realizes the
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
    The run is forced-and-stationary by default (a `VarianceRescaling` holds the total energy at the value
    given by the `kinetic_energy` keyword,
    default `1.5`, i.e. ``u'=1``); an explicit `viscosity` opts back into direct control. *(Superseded
    in the holder, not in the substance: decision 58 made `VarianceController` the default. The
    calibration constraint — the run must really hold ``k`` at the assumed value — is unchanged, and
    the controller holds it to a tolerance rather than exactly.)* It does **not**
    breach the extraction boundary — `Li2008` stays a pure scalar law with no `GBGPeriodicFields` /
    `GBGStreamingStatistics` / dynamics dependency; only the run layer (never `Phenomenology`) knows both
    sides. The accuracy target is ``\kappa_{\max}\eta`` (spectral content at the highest *evolved*
    wavenumber), not ``\eta/\Delta x`` (geometric): the former is dealiasing-aware through
    ``\kappa_{\max} = f \tfrac{N}{2}\tfrac{2\pi}{L}`` (then `max_wavenumber`), which is correct because
    accuracy itself depends on the dealiasing. *(Refined by decision 82: the criterion's
    ``\kappa_{\max}`` is now the **resolved** cutoff `max_resolved_wavenumber` — under `HouLi` the
    ``4/5``-of-Nyquist crossover, not the retained Nyquist this entry's ``f`` implied.)*
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
    verb-first: `set_forcing_rate!`, `add_forcing_source!`, `prepare_forcing!`, `project_forcing!`. (c) The
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
    observation: the observables, the diagnostics, and the tracer advance must see the forced end-of-step
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
    smell decision 26's discipline predicted): `set_forcing_rate!`, `project_forcing!`,
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
    borrowed scratch could move homes. `VarianceRescaling` carries the Berendsen-class caveat — a
    deterministic clamp has no conserved quantity and no well-defined ensemble except in limiting
    cases (Bussi, Donadio & Parrinello 2007) — a spin-up and amplitude-holding tool, with stochastic
    rescaling the recorded upgrade path when faithful fluctuations of the held quantity matter.
33. **(2026-07) The memory audit: a frozen buffer ledger and a liveness lower bound, in the standard
    suite.** "Minimal footprint" becomes a checked property instead of an aspiration
    (`test/memory_audit.jl`, run by `Pkg.test()`). Two instruments. (a) **The ledger**: a reflective
    walk over every resident field-sized buffer a run owns (state, observables cache, generator,
    scheme registers, forcing-owned state and kernels, the tracer buffers), counted per shape
    class over the full **five-axis** combination space — scheme × dealiasing × scalar ×
    (velocity forcing × scalar forcing) × tracers. The frozen spec is **compositional**: twelve
    unforced, tracer-free base cells plus a per-forcing delta table and a tracer delta, and an
    exhaustive sweep over the whole product (~360 combinations) asserts measured = base + deltas,
    cell by cell — a cross-term (a buffer whose existence depends on two axes at once) fails the
    sweep and must be recorded. The observables cache's **charts axis** (resident charts are
    opt-in) is audited at the API level with its own delta; for any *stepping* run it is pinned by
    the physics — the rotational generator's declared working set requires both charts — and becomes
    a live run axis when per-component chart declarations or further charts land. Adding or removing
    a buffer anywhere fails the suite, so a footprint change must be a conscious, recorded decision.
    The particle-scheme axis has one point today (the Heun scheme) *(two since decision 57 —
    `AdamsBashforth` joined, its registers audited the same way)*, entering as on/off with the
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
    accounting, the tracer advance, the forcing hooks — since a cost outside the stepped region is
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

    On the synchronization axis the default configuration issued **three** blocking readbacks per
    step against a floor of **one** — the CFL speed bound plus `VarianceRescaling`'s two observables.
    Only the timestep's is irreducible; a forcing's scalar is consumed by the very next kernel and
    visits the host only because it is written as a Julia number. *(Superseded by decision 58, which
    made `VarianceController` the default and the count **ten** — the speed bound plus three
    reductions at each of three stages. That decision bought temporal order at this axis's expense;
    the gap is held, not accepted — the three per-stage reductions differ only in their weight, and
    one fused multi-weight reduction collapses them.)*

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
    observables cache, the generator's assembly scratch, the scheme registers, the tracers. It
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
    the Dirichlet-energy weight is `radial_kernel(identity, …)`, the stored real ``\lvert\boldsymbol{\kappa}\rvert^{2}`` array
    is gone (its consumers — the initial-condition envelopes, now composed radial kernels folded with
    the truncation; the integrating-factor builds, a transitional lazy broadcast; the backend/eltype
    template, now the multipliers' axis arrays), and the phase-shift translation kernels are per-axis
    `SeparableKernel`s. Decision 36's frame floor of zero is thereby **achieved** — 322.5 MiB retired
    at ``256^3``/`Float64`, ``\lvert\boldsymbol{\kappa}\rvert^{2}`` no longer resident twice — and the optimality audit's
    reconstruction demonstration inverted into a correctness pin: the lazy symbols, materialized on
    demand, must equal the explicit axis-vector reconstruction. Knock-on residency wins recorded in
    the same re-freeze: every band forcing's kernel is lazy (`VarianceRescaling` and `StochasticOU` store
    none; `Linear` and `ConstantPower` keep one materialized *real* indicator each for the rate fill
    — *superseded for `ConstantPower` by decision 58, which moved it off the rate route: its band is
    lazy now and only `Linear`, the one remaining rate-route strategy, keeps an indicator; since
    decision 99 `Linear` keeps none either*),
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
    the stage update ``\hat{\boldsymbol{u}} \leftarrow \mathcal{E}(\hat{\boldsymbol{u}} + B_i \boldsymbol{h})`` is
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
    for what they are.** *[The storage wiring — the slot as the tracer set's own array under two
    names — is superseded by decision 67: the cache allocates and owns the slot. The sample's slot
    status, its two epochs, the iteration-end schedule, the unserved predictor register, and the
    forbidden reuse all stand.]* `Tracers.velocity1` / `velocity2` were categorically different objects
    wearing sequence numbers: the first is the **trajectory sample**
    ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` — a genuine Lagrangian observable between iterations —
    the second the velocity at the Heun *predictor* position, which no tracer ever occupies: a stage
    register, substage on the position argument alone. They are renamed `particle_velocities` /
    `velocity_predictor`, and the sample becomes the observables cache's first trajectory-bound
    slot — the class decision 30 reserved and never used — wired to the tracer set's own point-value
    storage (the slot IS the register, as everywhere else) and dated against **both** epochs,
    since the sample is a function of the state and the positions together. The push's schedule
    moves fully onto the iteration ends: `advance!` checks the sample at the start (the previous
    closing deposit recorded ``\boldsymbol{v}_1``), pushes after the closing field deposits
    (``\boldsymbol{v}_2`` from the deposited ``\boldsymbol{u}(t_{n+1})``), then records at the new epoch
    the new sample at the new positions — so `advect!`'s prose-only staleness contract is retired in
    favor of the slot epoch, and the sample is read through the checked `particle_velocities`
    (`tracer_velocities` is gone; `tracer_positions` is renamed `particle_positions`, the
    user-settled accessor prefix). The register `velocity_predictor` is deliberately **not served** as an
    observable — an off-trajectory value must not be offered as a plausible-looking Lagrangian
    velocity, though it remains an ordinary reachable field of its buffers type — and the
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
    generics the cached reads extend.** The include order becomes `State → Observables → Cache` *(misrecorded here: the order has been
    `Observables → State` since the module split — the entry's substance, `Observables` before
    `Cache`, is unaffected)*, and
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
    (`max_speed` sets the adaptive ``\Delta t``; `VarianceRescaling` holds a measured band energy);
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
    the state and its seeders. What remains a package verb is the one recovery that is *not* a bare chart map (its slot is still a
    chart — a physical-representation view — but its recovery computes an observable, the curl):
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
    The `check_boundary` verb is renamed **`check_deposits`** (the deposit-completeness check), and the op
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
    The `validate_spectrum` helper leaves the package altogether, to `test/validation.jl` as `compare_to_model`:
    comparing a run against a model spectrum answers "does this reproduce the literature", which is
    what a validation suite asks and a solver never does.

50. **(2026-08, user-directed) `Tracers` holds trajectory state; the trajectory scheme's registers
    are allocated per scheme, as on the field side.** Three of `Tracers`' seven fields —
    `predictor`, `predictor_points`, `velocity_predictor` — were one scheme's scratch, as its own
    docstring conceded in calling `velocity_predictor` "a stage register of the push". The field
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

53. **(2026-08, user-directed) "Stamp" is retired; a slot carries an *epoch*, and an epoch is not
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
    but so does any announced out-of-band mutation, so the two counts diverge: the constructor's
    seeding deposit leaves the fields epoch at 1, so after two steps and one announced mutation the
    clock reads step 2 and the fields epoch reads 4 — measured, not assumed. The epoch answers "is this value still the right one?"; `current_step` answers "how
    far has the run gone?". As with decision 48, the sweep covered the decision log too, so the log
    reads in the current vocabulary; this entry records that the older entries originally said
    "stamp".

54. **(2026-08, user-directed) `VarianceRescaling`'s `over` is required, and the front door's `:total` is
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
    absence of one. *(Superseded in part by decision 58: the front door now passes a
    `VarianceController`, not a `VarianceRescaling`, so `over` is no longer a front-door choice at
    all. The calibration argument survives intact and is what the controller had to be checked
    against — it holds the whole-field ``k``, which is the quantity grid mode assumes.)*

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
    so one word names the same role on both sides of the run. *(Refined 2026-08-23, decision 62:
    the `Simulation` keyword and field are now the qualified `integration_scheme`; bare `scheme`
    survives as the positional-argument name inside the protocol.)*

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

57. **(2026-08, user-requested) A second trajectory scheme: variable-step Adams–Bashforth.** The
    Lagrangian right-hand side is a *deposited observable* — every iteration produces it whether or
    not a scheme wants it — so a multistep method buys order out of storage the run already fills, at
    no extra field evaluation and no extra interpolation, where `EndpointHeun` pays one interpolation
    per step. Same reasoning as TurTLE's tracers (Adams–Bashforth, orders 1–5, default 4).

    Two departures, both forced here. **Steps are not uniform** — the advective-CFL loop changes
    ``\Delta t`` every iteration, so the weights are recomputed per step as the integral of the
    Lagrange polynomial through the stored sample times, verified to reduce to the classical
    constants at uniform step. **The startup bounds the order** — TurTLE ramps AB1→AB4, but AB1 is
    Euler and measurement gave ``\approx 2.0`` for the ramp against ``\approx 3.0`` for an
    `EndpointHeun` bootstrap, so the bootstrap shipped. Fourth order over a fixed window would need a
    start of matching order, unavailable because it wants the velocity between step endpoints.

    **The interpolation caveat was corrected the same day**, having first read "raising the time order
    past the interpolation's *smoothness* buys nothing." That misattributes the mechanism. The
    interpolant perturbs the field by a ``\Delta t``-independent ``\epsilon``, so Grönwall gives a
    trajectory-error floor no timestep can cross — and the floor is set by the interpolant's
    **reproduction degree**, not its smoothness. Measured on a frozen ABC flow at ``64^3``, ``T = 1``:
    `CatmullRom` (``C^1``, degree 2) floors at ``1.2\times10^{-5}``; `LalescuSpline(3, 1)` (same
    ``C^1``, degree 3) at ``2.6\times10^{-7}``; `LagrangeSpline(3)` (``C^0``, degree 7) at
    ``1.2\times10^{-11}``. At fixed degree 7, ``C^0`` and ``C^3`` gave identical time convergence, so
    smoothness caps nothing here — it earns its keep in readouts that *differentiate* the interpolant.

58. **(2026-08, user-directed) A state-dependent forcing rate belongs in the source, not in the
    integrating factor: `VarianceController` is the new default, and `VarianceRescaling` is kept as a
    documented first-order reference.** The audit that followed the bug hunt found the default
    `Simulation` integrating at **first order** on a third-order scheme, and the cause was routing
    rather than any error in the schemes or the forcing protocol. Both are worth separating, because
    only one of them was a defect.

    The genuine defect: `ConstantPower` published a *rate* that it recomputed every step from the
    current state. A rate folded into ``\mathcal{E}`` is integrated exactly — but exactness is a
    statement about a *steady* ``A``. Freezing a state-dependent one at the step's start makes the
    step a left-endpoint rectangle rule on ``\int A\,\mathrm dt``: local error ``O(\Delta t^2)``,
    global order 1, and the collapse is silent because nothing about the code looks wrong. Moving it
    to `add_forcing_source!`, where the scheme's own stages evaluate it, restored 3.01 from 1.02.
    The protocol needed no change — the four hooks were already the right four. The fix was to stop
    claiming exactness the strategy could not deliver, which is why `uses_linear_rate` is now
    `uses_steady_linear_rate`: the old name asserted linearity in the *field*, and the load-bearing
    property is steadiness in *time*.

    Not a defect, and kept: `VarianceRescaling`'s first order. A post-step rescale is Lie–Trotter
    operator splitting, so it is first-order by construction and no routing can save it. It is a
    published method (Sullivan, Mahalingam & Kerr 1994) a reader may need to reproduce, and holding a
    band's value *exactly* is occasionally what is wanted. It stays, with the caveat stated in its own
    docstring rather than discovered by a convergence study, and a test pins its order below 1.5 so
    the caveat cannot rot into a claim.

    The replacement is `VarianceController`, the constant-``k`` controller of Bassenne et al.
    (2016, Eq. 20): ``A = [\varepsilon - G(k - k_\infty)/t_\ell]/(2k_f)`` — the whole field's
    variance ``k`` in the restoring term, the forced band's ``k_f`` normalizing, and the two are not
    interchangeable (see the postscript). Its marginal term
    ``\varepsilon/2k_f`` reinjects exactly what dissipation removes, and its proportional term gives
    ``\mathrm dk/\mathrm dt = -G(k - k_\infty)/t_\ell`` — exponential relaxation to a **stable
    attractor**. That is the structural difference from the rescale, not a numerical refinement: the
    clamp *imposes* the target and destroys the fluctuation of the quantity it holds, while the
    controller *restores* toward it and leaves the fluctuation to the flow. Molecular dynamics settled
    the same question the same way — naive velocity rescaling versus a thermostat that extends the
    dynamics with feedback — and the analogy is recorded in the docstrings because a reader arriving
    from that literature will recognize the pair immediately.

    The naming is deliberate: `Variance`, not `Energy`, because one implementation serves both fields
    and the held quantity is each field's ``L^2`` observable — the kinetic energy for the velocity,
    the scalar variance for the scalar. Naming it for the velocity's case would have made the scalar's
    the exception. Measured after the change: unforced, `Linear`, `ConstantPower`,
    `VarianceController` and the default `Simulation` all converge at 3.01; `VarianceRescaling` at
    1.02. The controller was verified to converge on its target from both sides (``k_0 = 0.4`` and
    ``k_0 = 2.6`` toward ``1.5``), which a clamp cannot be said to do at all.

    **A postscript, because the round nearly shipped the wrong physics.** The first implementation
    put the *band* variance in both places of that formula — normalizing by ``k_f`` (right) and
    restoring toward ``k_f`` (wrong). Both readings are dimensionally sound and the code looked
    symmetric, which is what made it survive review: it is a category error, not an arithmetic one,
    between the quantity a forcing *acts on* and the quantity it *holds*. The consequence was
    precise and invisible from the test suite — the run held the band at ``1.5`` and let ``k`` settle
    about 30% above it, silently breaking the grid-mode ``\nu`` calibration that decision 15 had
    made conditional on the run really holding ``k``. The `/audit-changes` run over this very commit
    caught it, by *executing* the default configuration and measuring ``k`` rather than reading the
    diff. Two things now hold it: the whole-field and band reductions are separated and commented at
    the point of use, and a witness compares the applied amplitude against both candidate formulas,
    asserting it matches one and not the other — a steady state cannot satisfy it by luck.

59. **(2026-08, user-directed) `gain = 0` is admitted: the bare marginal law is a valid forcing,
    and its physics is now stated correctly.** The constructor had refused it while the docstring
    described exactly that limit — and described it wrongly: "the variance random-walks" is false.
    Expanded and then measured: with ``A = \varepsilon/2k_f`` the injection equals the instantaneous
    dissipation identically, so ``\mathrm dk/\mathrm dt = 0`` and ``k`` is *conserved at its initial
    value* (`target` never enters the rate). The subtlety is stability, not conservation: the exact
    reinjection cancels the cascade's own restoring response — the physical feedback `ConstantPower`'s
    *fixed* injection retains — so every level is a **neutral** equilibrium, and discrete integration
    bias accumulates uncorrected (measured: ``k`` drifting monotonically ~1% per 1000 steps at
    ``24^3``, against a G = 1 controller holding 1.498 flat). The guard is now finite-and-non-negative;
    a negative gain stays refused (anti-restoring). The witness is the discriminating experiment, not
    a construction test: seeded at ``k = 0.5`` against `target = 1.5`, the marginal law must stay at
    0.5 — conservation *and* the absence of restoration, which no drift could fake.

60. **(2026-08) The advective term's ``\kappa = 0`` mode is pinned to zero exactly; the forcing
    source is added after the pin.** Found by a `/bug-hunt` witness: the mean mode is exactly
    conserved by the continuous equations (``\langle\boldsymbol{u}\times\boldsymbol{\omega}\rangle = 0``
    on a periodic box; ``\langle\nabla\cdot(\boldsymbol{u}\varphi)\rangle = 0``), but discretely the
    identity holds only to roundoff, the Leray projection legitimately keeps constants
    (``\mathbb P(0) = I``), and the integrating factor is ``\exp(0) = 1`` there — so the FFT residual
    at ``\kappa = 0`` was integrated with no restoring term and, the flow being chaotic, grew at the
    Lyapunov rate: measured 3% of ``u'`` after 3000 Float32 steps, a phantom uniform wind under every
    Lagrangian statistic. The pin is an O(1) masked write in `velocity_rhs!` / `scalar_rhs!`, placed
    **between** the nonlinear assembly and the forcing source: the exact law covers the advective
    term alone, so a forcing that deliberately drives a mean stays expressible. The zeroing is
    physics (a conservation law), not field machinery, which is why it lives here and is not a
    `GBGPeriodicFields` raise — defining ``\mathbb P(0) = 0`` at the backend would encode momentum
    conservation into a linear-algebra operator whose constant component genuinely belongs to its
    divergence-free subspace. After the pin the witness's Float32 forced run holds
    ``\langle\boldsymbol{u}\rangle = 0`` exactly for 1000 steps.

61. **(2026-08, user-directed) The advanced state is re-projected every step, unconditionally.**
    From the reference-practice audit (five lanes over TurTLE / GHOST / hit3d / Fluidsim / the
    textbooks): every stage *tendency* is Leray-projected, but nothing projected the advanced
    *state*, whose divergence — injected at roundoff by the stage combinations — is damped only by
    ``\exp(-\nu\kappa^{2}\Delta t)``, nearly nothing at the largest scales. Measured in Float32 at
    ``32^3``: ``\lvert\nabla\cdot\boldsymbol{u}\rvert`` grew ×120 per 1500 steps, reaching
    ``800 \varepsilon_{\mathrm{mach}}`` by step 2000 and compounding; Float64 sat harmlessly at
    ``\sim 10 \varepsilon_{\mathrm{mach}}``. Since precision is a studied fitness axis, the Float32
    behaviour is a defect, not a curiosity. The pin is one in-place pointwise pass
    (`helmholtz_projection!(û, û, …)` — the backend's projection may alias destination and source)
    at the END of `step!`, after `finalize!`, so a post-step forcing's writes are covered too.
    Measured after: Float32 divergence flat at ``0.3 \varepsilon_{\mathrm{mach}}`` over 2000 steps.
    The compute ledger re-froze at +2 `spectral_vector` per cell in the same commit; the witness
    injects an O(1) pure-gradient corruption through the `fields_modified!` escape hatch and
    requires one step to scrub it to ``10^{-12}``, which no viscous decay could fake.

62. **(2026-08, user-directed) The `Simulation` keyword and field `scheme` → `integration_scheme`.**
    A refinement of decision 55, proposed by the user from the parallel with `interpolation_scheme`.
    Bare `scheme` underdetermined its role on the run's front door, where it sat beside the other
    pluggable strategies (`dealiasing`, `velocity_forcing`, `interpolation_scheme`,
    `trajectory_scheme`) — "scheme of *what*?" is a fair question there. The keyword family is now
    uniformly `<role>_scheme`: `integration_scheme` (the fields in time), `trajectory_scheme` (the
    particles in time), `interpolation_scheme` (space) — each self-describing under one pattern. The
    noun form is deliberate: English compounds these with a noun attribute (an *integration* scheme,
    like an *interpolation* scheme), and the participle alternative `integrating_scheme` would sit
    one word from the *integrating factor* ``\mathcal{E}`` and invite conflating the discrete scheme
    with the exact operator. The qualified name also narrows decision 55's binding-vs-type residue
    without renaming any exported type: `integration_scheme::AbstractIntegrator` shares its morpheme
    with the family. Scope: the `Simulation` keyword and struct field only — bare `scheme` remains
    the positional-argument name in the protocol (`step!`, `allocate_buffers`, `recommended_cfl`),
    where dispatch already types it. *(Refined 2026-08-24, decision 68: the two time-integration
    members are now `field_integration_scheme` / `particle_integration_scheme`, naming the system
    half each one advances.)*

63. **(2026-08) The three-item PF request of 2026-08-23 was delivered in full and is wired in.**
    Raised under invariant 2 (field machinery is requested, never reimplemented here), shipped by
    PF the same day (their decisions 71–72 and the radial-symbol allocation fix), integrated here:

    - **Allocation-free radial symbols** (item 1). The 144-byte-per-call reshape wrappers behind
      every ``\lvert\boldsymbol{\kappa}\rvert^{2}`` evaluation are gone; the acceptance
      reproduction prints `0` for both `exponential_convolve!` and `laplacian!`, and IT's side
      needed no change — the hot loop's last external allocation closed from the backend.
    - **The multi-weight fused reduction** (item 2, PF decision 72; their measurement on this
      host's card: 2.14× at ``128^3`` over three separate passes, before counting the retired
      synchronizations). The fused `weighted_inner(f, (w_1, \ldots, w_n))` answers ``n`` weighted sums from
      one traversal and one readback, bitwise identical to the separate calls. Wired at every
      same-field multi-reduction site: `VarianceController` (three weights per stage — the unit,
      the band, ``\lvert\boldsymbol{\kappa}\rvert^{2}``), `VarianceRescaling`'s `:total` pair,
      and the new public observable `kinetic_energy_and_dissipation` — the eddy-turnover clock's
      ``(k, \varepsilon)`` pair, used by `StationarityCriterion` every iteration. The `FixedDomain`
      gained `unit_kernel` (the constant-``1`` weight in the same lazy form, so a plain variance can
      join a fused traversal). The synchronization ledger re-froze: the default row fell **10 → 4**
      crossings (one fused reduction per stage plus the ``\Delta t`` choice), the
      `VarianceRescaling` and warm-up rows each by their fused share; the compute ledger's
      controller delta fell 6 → 4 passes per evaluation. `UNFUSED QUADRATIC REDUCTIONS` was
      rewritten down to its residue — the stationarity gate's scalar variance sweeps ``\hat\varphi``
      where the pair sweeps ``\hat{\boldsymbol{u}}``, and fusing across *fields* is a further,
      smaller ask, deliberately not yet raised. The witness pins the wiring bitwise: swapping the
      tuple's weights would exchange ``k``'s and ``\varepsilon``'s operands, which only an exact
      comparison catches.
    - **`reality_residual`** (item 3, PF decision 71 — a checker by their design: report, never
      repair; Nyquist content named, never zeroed). Wired at the escape hatch: `fields_modified!` on
      a run now measures the conjugate-symmetry residual of the announced state and throws beyond a
      scale-aware roundoff tolerance, closing the documented "it is not checked" hole; the `cache`
      form cannot see the fields and still trusts the caller. The witness hand-corrupts one member
      of a stored conjugate pair and requires the violation named, then repairs it by the physical
      round trip and requires acceptance.

64. **(2026-08) The Points-layer requests of 2026-08-24 were delivered and are wired in.** Raised
    under invariant 2 after the owner's particles review; shipped by PF as their decisions 73–74:

    - **Base-space motion** (`displace!` — "the exp map of the flat torus" — and `wrap!`). Every
      trajectory update now crosses the package boundary as a *named PF operation*: the Heun push
      is two fused displacements (predictor and corrector), the Adams–Bashforth push is **one**
      fused ``K``-term displacement where a loop once made ``K`` broadcast passes over the
      positions, and the periodic wrap rides the same traversal via the `grid` form. IT's
      `advect!` bodies contain no `point_values` unwraps and no raw-array arithmetic on positions.
      `_wrap!` is **deleted**: its hard-won contract — the excluded-endpoint fold (floating-point
      ``\operatorname{mod}`` can return exactly ``L``) and non-finite transparency (an order test
      would launder a diverged trajectory into a tidy in-box position) — was adopted verbatim into
      PF's `wrap!`, and IT's witness now pins that contract at the boundary `advect!` actually
      calls, so a PF regression on either half fails here too.
    - **Allocation from context** (the six field constructors accept a storage *family* —
      `Array` / `CuArray` / `ROCArray` — and produce the storage themselves, element type from the
      grid). `_reference`/`_blank` are **deleted**: the frame no longer borrows a multipliers axis
      vector as a backend-and-element-type witness for raw `Base.similar`. `FixedDomain` now
      stores the constructor's own `storage_family` (a type, zero array bytes — the frame ledger
      is untouched), the six `new_<Type>` allocators are thin wrappers over the family
      constructors (the zero-fill contract stays IT's), and tracer position storage comes off the
      same family. No IT code reads a multipliers field for any purpose other than wavenumbers.

65. **(2026-08, user-directed) Wrapped dynamics, plus an opt-in unwrapped record in the tracer
    state.** A user wants both trajectories: wrapped for the dynamics, unwrapped — winding kept —
    for the dispersion diagnostics. The accuracy analysis fixes which is which, not a flag: the
    absolute floating-point resolution at a coordinate grows with the coordinate, so an unwrapped
    position that winds ``n`` boxes is known ever more coarsely — feeding it back into
    interpolation would degrade the dynamics, `Float32` fastest. The dynamics therefore **always**
    advance wrapped. The unwrapped record only ever feeds *differences*
    ``\boldsymbol{X}(t) - \boldsymbol{X}(0)`` — mean-square displacement, dispersion — whose
    relative accuracy the coordinate growth does not touch, so it needs no wrap and must not have
    one. Implementation: `Tracers(…; unwrapped = true)` (forwarded by `Simulation`) carries a
    fourth state field, a `PointSet` starting equal to the seeded positions; every push applies
    the **same displacement terms** to both records — the wrapped positions through `displace!`'s
    grid form, the record through the grid-free universal-cover lift (the two cannot disagree on a
    step, only on the winding the wrap discards). Read through `unwrapped_positions`; an untracked
    set throws. An announced `particles_modified!` on a run restarts the record at the new positions — winding
    is a property of the trajectory just abandoned. Accumulating statistics over the record is the
    caller's analysis, per the charter.

66. **(2026-08, user-directed) The particle boundary is PF-typed: coordinates and sampled values
    cross into the package only as `PointSet` / `PointValues`, never as raw arrays.** The ruling
    generalizes what decision 64 made possible: with `displace!` owning the motion and
    `point_coordinates` extracting the matrix view, the `positions`/`position_points` pair in
    `Tracers` had lost its reason (the raw field existed for the axpy-and-wrap arithmetic decision
    64 deleted, and the new unwrapped record already used the single-`PointSet` pattern). `Tracers`
    now carries **one** position storage — `position_points::PointSet` — and one type parameter
    fewer; `particle_positions` serves the `(M, 3)` view through `point_coordinates`, the count
    comes from `npoints`, and the point-value allocators are thin wrappers over
    `similar_pointvalues`. The constructor's `positions` keyword takes a **`PointSet`**, and a raw
    array is refused with the rule stated in the error: raw arrays cross the boundary only through
    the `GBGPeriodicFields` point types, and a caller who needs the bare array back extracts it
    with that package's accessors. (A malformed shape is refused one layer down, by `PointSet`'s
    own constructor — the guard lives with the type that owns the invariant.)

67. **(2026-08, user-directed) The velocity sample is cache-owned, and named for what it measures:
    `velocity_at_particles`.** Decision 42 made the trajectory sample a cache slot but wired the
    slot to the tracer set's own point-value storage — one array under two names. That aliasing was
    the last seam in the observable/state split: the sample
    ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` is an observable of the **flow** — a tracer has no
    velocity of its own — so `Tracers` now carries positions and the interpolation scheme only,
    and the `ObservablesCache` allocates the slot itself (a `number_of_particles` keyword sizes an
    ``M \times 3`` array of point values on the domain's backend, plus the multistep history)
    exactly as it allocates the field charts. The write moved with it:
    `record_velocity_at_particles!(cache, tracers, u)`
    writes into the cache it is handed; `allocate_buffers(scheme, tracers, cache)` takes the cache
    whose slot and history the scheme's registers ride; the checked read is unchanged in contract.
    The name changed with the ownership, on the user's ruling: *particle velocities* would name
    particle **state** — the inertial ladder's own ``\boldsymbol{v}`` — while this slot holds the
    flow's velocity sampled at the particle positions. The old names `particle_velocities` /
    `record_particle_velocities!` became `velocity_at_particles` / `record_velocity_at_particles!`
    (the `at_particles` morpheme from `interpolate_at_particles!`), and prose everywhere says "the
    velocity at the particles", never "the particle velocities". Ownership and naming landed in one
    commit, so each affected doc surface was written once.

68. **(2026-08, user-directed) The two time-integration keywords name the system half each
    advances: `integration_scheme` → `field_integration_scheme`, `trajectory_scheme` →
    `particle_integration_scheme`.** Decision 62's `<role>_scheme` family named its two
    time-integration members asymmetrically: `integration_scheme` claimed the unqualified word for
    the fields, and `trajectory_scheme` named the particles' scheme by the object it produces
    rather than the thing it advances. The user weighed the frame vocabulary (Eulerian /
    Lagrangian) and chose the system vocabulary: the run advances **fields** and **particles** —
    decision 51's umbrella word — so the keywords are `field_integration_scheme` /
    `particle_integration_scheme` / `interpolation_scheme`, and the two renamed keywords' morphemes
    now align with their supertypes (`AbstractIntegrator` / `AbstractParticleIntegrator`). Prose
    follows the keywords: "the particle integration scheme", with "trajectory scheme" retired
    outside this log. Scope, as in decision 62: the `Simulation` keywords and struct fields only —
    bare `scheme` remains the protocol's positional name, where dispatch already types it.

69. **(2026-08, user-directed) The scheme names keep the method, not the qualifier: `EndpointHeun`
    → `Heun`, `IFRK2` → `IFHeun`.** The `Endpoint` qualifier stated an architecture invariant, not
    a property of one scheme: the decoupled design deposits fields only at iteration ends, so
    *every* particle integration scheme consumes endpoint data — `AdamsBashforth` was never
    qualified, and mathematically Heun's method *is* the two-endpoint explicit trapezoidal RK2, so
    the qualifier was redundant against the textbook as well. The invariant is stated once, in
    §4.6 and the scheme docstrings. No cross-family prefix pair (`FieldHeun` / `ParticleHeun`) was
    adopted: the field family's `IF` prefix already does that work by naming the property that
    makes them field schemes — the exact integrating factor — so the families stay lexically
    disjoint, and the particle side needs no prefix the keyword
    `particle_integration_scheme` and the supertype `AbstractParticleIntegrator` already carry
    (decision 68). The field member gains the same method-first courtesy: `IFRK2` — verified to be
    exactly integrating-factor Heun (full Euler predictor, trapezoidal corrector, both stages on
    the endpoint nodes) — is renamed `IFHeun`, naming the method rather than its stage count.

70. **(2026-08, user-directed) One particle buffers type: `MultistepBuffers` is folded into
    `ParticleIntegratorBuffers`.** The two-type split had a real reason once — `MultistepBuffers`
    owned the multistep sample history, a genuinely different register set — but decision 67 moved
    the history into the observables cache, and what remained was a wrapper: a `cache` reference
    duplicating `startup.cache`, the one-step registers wrapped as `startup`, and two
    ``\mathcal{O}(\texttt{order})`` host vectors for the variable-step weight solve. The register
    sets now nest — a multistep scheme uses the predictor registers for its `Heun` starting steps
    only, and adds the two host vectors (empty for a one-step scheme) — so one type serves every
    scheme with **zero** dead device storage for either, which is tighter than the field side's
    `IntegratorBuffers` manages with its `nothing` slots. This mirrors the field side's one-type
    pattern: `advect!` and `restart!` keep dispatching on the scheme, exactly as `step!` does, and
    `allocate_buffers(scheme, tracers, cache)` is the one particle form (the two-argument form died
    with decision 67, which every scheme's registers now reference the cache through). The fold
    deletes one public type, the doubled cache reference, and the order-mismatch hazard of handing
    one scheme another's wrapper — `advect!` now checks the weight scratch's length against the
    scheme's order outright.

71. **(2026-08, user-directed) One deposit verb: `record_velocity_at_particles!` /
    `deposit_sample!` are folded into `deposit!`.** A deposit is one concept — *compute the
    observables from the state you were handed, write them into the cache, stamp them with the
    current counters* — and the field `deposit!` already was exactly that. The particle side's
    write/stamp pair was decision 42's residue: with the slot borrowed from the tracer set, the
    cache genuinely could not stamp what it neither owned nor saw written. Decision 67 removed that
    constraint, and the one justification left ("only the writer knows when it has finished") is an
    argument for the *writer stamping in the same call*, not for the caller sequencing two calls.
    `deposit!` is now one generic with three methods: the field form (after `step!`), the particle
    form `deposit!(cache, tracers, u)` — added by `Particles` exactly as it extends
    `allocate_buffers`, interpolating and stamping **both** epochs in one act (the stamping half
    lives on in `Cache` as the private `deposit_velocity_at_particles!`, beside its field-slot
    siblings) — and the `sim` form, which performs every deposit the configuration carries. The
    dependency chain still forces two deposit *moments* per iteration — the push consumes the field
    deposit and the trajectory observable exists only at the new positions — but the iteration now
    reads as the model itself: advance a factor, bank what it made measurable, twice. The
    glossary's *deposit* entry loses its exception clause; the two-verb ritual's failure mode
    (write without stamp → a stale-read throw far from its cause) is gone by construction; and the
    internal names shed the bare "sample" the user flagged as undescriptive (`sample_steps` →
    `history_steps`, the slot's epoch pair → `velocity_at_particles_fields_epoch` /
    `velocity_at_particles_particles_epoch`).

72. **(2026-08, user-directed) The container principle reaches the tracer set: the forwarding
    accessors are retired, and the position fields are named for their content.**
    `particle_positions` and `number_of_particles` were pure forwarding — one-line compositions of
    `GBGPeriodicFields`' `point_coordinates` / `npoints` over the position storage — surviving from
    the era when `Tracers` held raw arrays. They contradicted two recorded rulings at once:
    decision 66's *"if one needs pure arrays, he calls PF machinery"* (each baked a raw-array
    extraction into this package's surface) and decision 49's container-not-reading-surface
    principle, under which an accessor earns its place only by enforcing a contract. Both are
    deleted; a caller reads `tracers.positions` and applies the field library's own accessors.
    `unwrapped_positions` stays as the one guarded read — the opt-in slot with the named
    `ArgumentError` — and now returns the **`PointSet`**, keeping the PF-typed boundary on output
    exactly as decision 66 fixed it on input; the raw view is one `point_coordinates` away. The
    fields shed the `_points` suffix, a fossil of the pre-66 dual-field era in which
    `position_points` disambiguated the `PointSet` wrapper from its raw `positions` sibling: with
    one storage per concept the fields are `positions` / `unwrapped_positions`, named for content,
    not for type.

73. **(2026-08, user-directed) The viscosity modes name the mechanism: *derived* / *supplied*, not
    *grid* / *explicit*.** The old pair failed the dichotomy test the user applied: *grid* and
    *explicit* are not opposing terms, so the two labels never said they exhaust the choice — and
    "(no `viscosity`)" under-specified the trigger, which is the keyword *not being passed
    explicitly*. The new pair is exhaustive by construction — ``\nu`` is either **supplied**
    (`viscosity = …`, used directly) or, absent, **derived** (from the grid, as the highest
    Reynolds number consistent with `κ_max_η`; decision 20's solve, now called *the viscosity
    derivation* everywhere it is named). Swept across the `Simulation` docstring (bullets,
    examples, keyword entries), the five `@warn` prefixes (`"Simulation (derived viscosity): …"`),
    the `Forcing` / `Scalings` cross-references to the solve, §4.7, the `Li2008` reference
    annotation, and the test comments and names — including the one `@test_logs` regex that
    matched the old warn text. Verbatim historical quotes in witness headers and the decision log
    keep the old words.

74. **(2026-08, user-directed) The `Simulation` constructor forms name their mechanism —
    *domain-building* / *domain-taking* — and the argument list is grouped the same way.**
    "Front door" as the name of the no-`domain` form said nothing about what distinguishes it (it
    builds the `FixedDomain` for you), so the form dichotomy is now mechanism-named and exhaustive:
    the domain is either built from keywords or taken pre-built. The `# Arguments` section splits
    into the **domain group** (consumed by the domain-building form; the domain-taking form
    replaces the whole group with its one positional argument) and the **run group** (accepted by
    both), retiring the per-bullet *(front door only)* markers the grouping now carries
    structurally. *Front door* survives in its sanctioned entry-point sense (§4.7's heading, the
    decision log) and the glossary row now marks it historical, resolving to *domain-building*.

75. **(2026-08, user-directed) HDF5 checkpointing: one self-describing group fully restores the
    run, recursively composed, with nothing derivable stored.** The persistence surface is five
    writer/reader pairs, one per user-meaningful object — `write_simulation`/`read_simulation`,
    `write_domain`/`read_domain`, `write_state`/`read_state`, `write_tracers`/`read_tracers`,
    `write_forcing`/`read_forcing` — with the field library's `write_field`/`write_points`/
    `write_scheme` groups as the leaves (its transfer-scheme pair was raised for exactly this and
    delivered as PF decision 75, same day). The methods live in the `GBGIsotropicTurbulenceHDF5Ext`
    weak-dependency extension; the bare generics and docstrings stay in the owning modules, so the
    REPL and docs work without HDF5. The file is opened and closed by the caller; each group
    carries a type tag and a schema version, checked on read; and the storage backend is the
    *reader's* keyword, never taken from the file — a checkpoint written on one backend loads on
    any other, with the element type file-bound. Not stored, recomputed on read: every physical
    chart, the current velocity sample, kernels, plans, and all scratch — the reader rebuilds the
    `Simulation` through its own constructor and replays the seeding deposits over the loaded
    state. Stored because irreplaceable: the spectral state, the positions and the opt-in
    unwrapped record, the clock, and the **Lagrangian sample history** (ring, step sizes, fill
    count), restored fill-aware after the epoch announcements — the order is load-bearing, since
    `particles_modified!` discards the history and restarts the unwrapped record, so both are
    written after it. Ruled non-persistent: a stochastic forcing's evolving force and stream — a
    reloaded `StochasticOU` resumes on a fresh stream (parameters only), so continuation is exact
    (bitwise, pinned by test) for deterministic forcings. The forcing structs now **store their
    shell bounds** — the parameters their band kernels are derived from, previously dropped at
    construction — the "an object is its parameters" lesson applied one layer up.

76. **(2026-08, user-directed) The push announces itself: `advect!` advances the particles
    epoch.** The 2026-08-24 panel's logician showed the two-epoch guard on `velocity_at_particles`
    was vacuous on the documented hand-run path: the history-keeping counter advance was an
    internal function only `advance!` called, and the one public announcement
    (`particles_modified!`) discards the history — so a hand loop either froze the counter (the
    staleness guard could never fire across its pushes) or wiped the multistep history every step.
    Decision 71's principle — the mutator announces — applied to the counter: `advect!` now
    advances the particles epoch itself at the end of every push (the Adams–Bashforth bootstrap
    announces through the Heun push it delegates to), the run layer's separate internal call is
    gone, and `particles_modified!` remains the out-of-band verb, discarding history exactly as
    before. A hand-run loop gets the same staleness protection as a run, with no new verb to
    remember. The same panel round also completed the citation architecture (T9): every inline
    docstring citation now carries the full reference — the linked title plus journal, volume,
    pages, verbatim against §References — the PF rule adopted whole, closing the compact-inline
    narrowing the 2026-08-24 title-as-link sweep had introduced undecided.

77. **(2026-08, user-directed) A defaulted controller settling time never drives the scalar.**
    `VarianceController`'s default ``t_\ell = 2k_\infty/(3\varepsilon_\infty)`` is Bassenne's
    kinetic-energy law — valid only when `target` *is* a kinetic energy. Bound as a
    `scalar_forcing`, the derived value would scale as ``L/\sqrt{\langle\varphi^2\rangle}`` with
    the scalar's arbitrary amplitude unit, breaking the scalar equation's exact linearity in
    ``\varphi`` (witnessed by the round-6 hunt: a ``1.5\times10^{-6}`` covariance violation in
    five steps under the default, exactly zero with an explicit equal turnover time). The owner
    ruled option (a): the struct records whether its turnover time was derived
    (`turnover_time_derived`), and `FlowConditions`' inner constructor — the one seam every
    construction path crosses — refuses a derived-``t_\ell`` controller in the scalar slot with an
    `ArgumentError` naming the remedy (pass the flow's ``2k/(3\varepsilon)`` explicitly). The
    velocity slot keeps the derived default; the regression is
    `test/regressions/r6-free-hot-path-01-variance-controller-scalar-amplitude-covariance.jl`.

78. **(2026-08, user-directed) The rank-2 transform plans are built on first use, and the skewness
    gate is off by default.** A transform plan is not free on a GPU backend: CUDA.jl gives each one
    a spectral-sized device buffer per direction, so a run's plan residency is
    ``2 \times`` (velocity 3 + scalar 1 + tensor 9) spectral fields — measured to within 0.05% on
    five configurations across two grids, two dealiasing strategies, two precisions and two vendor
    libraries. The rank-2 family is 9 of those 13 components, and its only consumer is
    `derivative_skewness`: **3.81 GiB at ``384^3`` / `Float32`** held for the life of a run to serve
    one occasional diagnostic. `FixedDomain` now stores a memo cell and `tensor_plans` builds on the
    first rank-2 transform. The velocity and scalar plans stay eager — the time loop transforms both
    every step, so there is nothing to defer.
    Deferral alone would have bought nothing on the default path, because `StationarityCriterion`
    gated on the skewness by default and so built the plans during every warm-up; that default is
    now `false`. The cost is real and stated rather than hidden: the ``\varepsilon``-plateau gate
    can be satisfied by a field whose cascade is not yet developed, so `gate_skewness = true` is the
    stricter spin-up and a run whose measurement depends on the small scales should set it.
    `test/simulation_run.jl` asserts two things, not one: that nothing is built until something
    asks, and that asking twice builds once — an accessor rebuilding on every call would pass the
    first while replacing the resident cost with per-call churn.


79. **(2026-08, blind-panel confirmed) The memory audit measures a device backend, and the frame is
    not zero there.** Every ledger in `test/memory_audit.jl` was built with `array_type = Array`, so
    the all-zero frame table was a *CPU fact frozen as a backend-invariant claim* — in a package
    whose primary target is the GPU. What escapes on a device backend is the transform plans'
    staging buffers: one spectral-shaped device array per plan, allocated eagerly by the backend's
    plan constructor, giving
    ``\texttt{DEVICE\_FRAME} = (\text{spectral vector } 2, \text{ spectral scalar } 2)`` — 65.0,
    218.25 and 516.0 MiB at ``128^3``, ``192^3`` and ``256^3`` in `Float32`, invariant under
    dealiasing strategy, integrator and the scalar axis. This is not decision 36's failure mode
    (storage on an unwalked owner): the reflective walk reaches these buffers and counts them
    correctly. The owner was simply never instantiated on the backend where it holds anything.

    The device leg now runs the frame ledger and the completeness invariant whenever a functional
    CUDA or AMDGPU backend is present, and **records a visibly unfulfilled test when it is not** —
    a conditional that passed quietly on a CPU-only runner would rebuild the same blindness in a
    new form. The register is bidirectional as everywhere else in that file: when the backend stops
    allocating eagerly, `DEVICE_FRAME` must fall in the same commit.

    Half of the cell is dead weight and is recorded as such: the *forward* plans' buffers exist for
    an inverse route this package never takes, and a sentinel written into them survives complete
    forward and inverse transforms untouched. Removing that half is an upstream request, not a
    local change — reaching into a dependency's private field would trade a memory cost for silent
    numerical corruption.

    Diagnosed independently by seven blind agents over a scrubbed copy of the tree, after three
    successive wrong mechanisms had been recorded here from inference; all seven converged on the
    same cause, the same closed form and the same allocation sites.


80. **(2026-08, user-directed) `IFSSPRK3` — TurTLE's tableau, at the low-storage scheme's cost.**
    For the code-to-code validation against TurTLE the owner wants the time discretization shared,
    so the third scheme is the Shu–Osher SSPRK3 (Shu & Osher 1988) in exactly TurTLE's stage
    arrangement: forward a full step, back to the midpoint, forward again
    (abscissae ``c = (0, 1, \tfrac{1}{2})``), each convex-combination term transported by the exact
    integrating factor. Every three-stage third-order explicit RK shares the stability function
    ``R(z) = 1 + z + z^{2}/2 + z^{3}/6``, so the advective ceiling is `IFLowStorageRK3`'s 0.5 —
    the two differ only in nonlinear error constants, which is precisely what makes the pair a
    convergence-test discriminator (same limit, different finite-``\Delta t`` states; pinned in
    `test/integrators.jl`).
    The implementation was designed into RK3's register shape — the stage state and the
    right-hand-side register, with the accumulator's role played by the state itself, which holds
    ``t_n`` until the final combination — so the memory cells equal `:RK3`'s in every configuration
    and the optimality audit holds the new cells AT their liveness bounds with no new holder.
    Transforms are identical to RK3 (same recovery schedule); pointwise passes are two fewer per
    field (no accumulator rotations, against stage 2's three-pass two-factor combination). The one
    scheme-specific caveat is stage 2's backward transport ``\mathcal{E}(-\Delta t/2)`` — a growing
    exponential, exact but amplifying high-``\kappa`` roundoff when ``\nu\kappa^{2}\Delta t`` is
    large; under an advective CFL step the exponent is small, and the docstring says so.

81. **(2026-08, user-directed) One rank-blind plan pair; decision 78's memo retired.** PF's decision
    76 — prompted by this package's residency measurement — removed the tensor order from
    `FieldTransformPlans`: the plans transform one component and are applied per component, so a
    plan pair is a property of the *box*, not of a field's rank. `FixedDomain` accordingly holds a
    single `transform_plans` where it held `velocity_plans`, `scalar_plans` and a lazily-built
    rank-2 memo — three copies of what is now the same object. Decision 78's laziness is retired
    outright: it existed to avoid multiplying per-plan GPU buffers by the rank, and upstream deleted
    the multiplication itself (its skewness-gate default, the other half of 78, stands — that cost
    is transforms and a per-call episode, not plan residency). The GPU frame cell fell from 8
    spectral-scalar equivalents to 2 (`DEVICE_FRAME` re-frozen in the same commit), and the first
    pull of 76 was refused before being taken: it broke the invariant-4 witness at 896 B/step
    (upstream `reshape` wrappers, constant in rank and grid), was reported, fixed by PF the same
    day, and the bump landed only when the witness read zero.
82. **(2026-08, user-directed) Retained vs resolved: two named band edges, and the resolution
    criterion measures the resolved one.** A dealiasing strategy fixes two distinct wavenumbers that
    decision 20's single `max_wavenumber` conflated: the **retained** cutoff (the highest mode kept
    energetic — what the advective-CFL, the random-seed spectrum, and the empty-shell warnings must
    see) and the **resolved** cutoff (the highest mode whose dynamics is genuine Navier–Stokes —
    what the resolution criterion ``\kappa_{\max}\eta`` and the viscosity solve must see). For the
    sharp-cutoff strategies the two coincide; under `HouLi` they diverge, because the per-step filter is an
    extra damping rate ``\mathrm{strength} (\kappa/\kappa_{\mathrm{Ny}})^{36}/\Delta t`` that
    overtakes ``\nu\kappa^{2}`` at
    ``\kappa/\kappa_{\mathrm{Ny}} = (\nu\kappa_{\mathrm{Ny}}^{2}\Delta t/\mathrm{strength})^{1/34} \approx 0.8``
    — a crossover the
    ``1/34`` power pins near ``0.8`` for any practical ``\nu``, ``\Delta t``, and strength, hence a
    constant ``4/5`` convention (TurTLE's Python side uses the same ``0.8``) rather than a per-run
    solve. Before this decision the criterion consumed the retained cutoff, so a `HouLi` run
    requested at `κ_max_η = 1.5` effectively resolved only ``\approx 1.2`` — the criterion
    over-credited the smooth filter by exactly the retained/resolved gap (surfaced by the TurTLE
    comparison work, 2026-08-28). Now `max_retained_wavenumber` and `max_resolved_wavenumber`
    replace `max_wavenumber` (no compatibility shim), the user's naming ruling being that the
    distinction must live in the names; the viscosity solve and the scalar-resolution check consume
    the resolved cutoff, everything energetic-band-facing the retained one, and `recommended_cfl`
    keeps its retained-fraction pricing unchanged. Derived-``\nu`` `HouLi` runs get more viscous by
    ``(5/4)^{4/3}`` accordingly; sharp-strategy runs are bit-identical.
83. **(2026-08, user-directed) The injection door: `Simulation` adopts an existing state and
    tracer set.** `Simulation` is immutable by design — reconfiguration is *rebuild around the
    shared `FixedDomain`*, never mutation — but the constructor could until now only seed fresh
    randomness, so "continue this evolved field under a new configuration" (a different scheme,
    particles added after a warm-up, an externally imported state — the TurTLE comparison's exact
    need) had no sanctioned path short of hand-overwriting arrays. Two keywords close it: `state`
    (a `ResolvedFields`) and `tracers` (a `Tracers`) are ADOPTED — the arrays become the run's
    own, no copy — skipping the seeding while the guards refuse, by name, every setting the
    adoption overrides (`initial_spectrum` with `state`; `number_of_particles`,
    `interpolation_scheme`, `unwrapped` with `tracers`), a `scalar` flag disagreeing with the
    state's contents, and a grid or storage-backend mismatch with the domain. A derived ``\nu``
    measures the adopted state's kinetic energy and warns when it voids the `kinetic_energy`
    calibration — the adopted-state sibling of the hand-built-forcing check. The sample history of
    a multistep particle scheme is deliberately NOT a constructor keyword: restoring it belongs to
    `read_simulation` (which already does it fill-aware), and the state importer for external
    checkpoints reuses that path. Pinned by a bitwise test: three steps, a `write_state` /
    `write_tracers` round trip adopted into a fresh `Simulation`, three more steps — equal to the
    uninterrupted run.
84. **(2026-08, user-directed) `HouLi(materialized = …)` — the filter's memory-for-compute axis
    becomes the user's choice.** A GPU kernel census (rocprofv3, 2026-08-29) priced the
    allocation-free radial-symbol design at the smooth filter: re-evaluating the
    ``\exp``-and-power chain per mode in every fused pass costs ``\approx 14\%`` of a ``128^3``
    `Float64` step (the fused dealias+projection kernel runs ``0.485`` ms where the identical
    traversal without the symbol runs ``0.136``). That cost was the *deliberate* price of frame
    floor 0 (decisions 36/63) — but a priced tradeoff with two defensible sides belongs to the
    user, not to a default. `HouLi` now carries `materialized::Bool = false`: the default keeps
    the closed-form symbol (zero resident storage, the minimal-footprint invariant's side);
    `true` evaluates the same closure once into a `StoredKernel` (one resident complex spectral
    scalar — ``\approx 17`` MiB at ``128^3`` `Float64`) that every pass then reads. Measured
    payoff: ``0.96`` ms/step = ``7\%`` at ``128^3`` GPU — half the census's ``14\%``, because
    materialization replaces only the *filter factor*: the integrating factor's own per-mode
    exponential remains in the fused kernels, and the stored coefficients add read traffic. PF's uniform kernel protocol makes
    the swap one branch in `_build_dealias`; every fused site (the `ProductKernel` compositions
    with the integrating factor and the translation kernels) consumes either form unchanged.
    Bit-identity between the two settings is pinned by test (same closure, evaluated once vs per
    mode — five steps, `==` on the coefficients); the checkpoint schema writes the flag only when
    set, so pre-flag files read back unchanged as the default. The frame ledger is untouched at
    the default; a `materialized` domain adds exactly the one declared array.
85. **(2026-08, user-directed) `IFLowStorageRK4` — Carpenter & Kennedy's fourth order at RK3's two
    registers, for stability-limited runs.** The time-integration report's storage taxonomy
    corrected a mis-belief this log should record being corrected: fourth order does NOT cost more
    registers — Carpenter & Kennedy (1994, NASA TM-109112) reach it in five stages of the same
    Williamson 2N-storage form. The scheme's stability function was derived exactly from the published
    rationals (the fifth coefficient collapses to ``z^{5}/200``), giving the imaginary-axis limit
    ``y_s = \sqrt{5(\sqrt{2041}-5)/18} \approx 3.3407``, ``1.93\times`` RK3's ``\sqrt{3}`` at
    ``5/3`` the evaluations. That gives ``\approx 16\%`` fewer transforms per unit time at the
    stability limit, and the gain was MEASURED at exactly that: step cost ``\times 1.665`` (vs ``5/3``
    analytic) on a ``128^3`` `Float64` GPU run, throughput ``\times 1.159`` vs the
    ``\times 1.157`` transform-only projection; the per-stage non-transform costs scale with the stages
    just as the transforms do, so nothing is eaten. Implementation: `step!`'s 2N-storage loop was factored into one shared
    `_low_storage_2n_step!` both schemes instantiate with their coefficient tuples — the S = 3
    op sequence is bit-identical to the pre-refactor body — and the audit op model mirrors the
    same factoring (`rk4_ops` = the RK3 iteration at five stages). All three audits extended:
    memory cells equal :RK3's in every configuration (stages, not registers — the equality is
    the claim), transform/pass cells AUDIT_PRINT-generated and frozen, the optimality floors
    reflective. Fourth-order convergence pinned by test (ratio ≈ 16); `recommended_cfl` prices
    the larger ceiling (base 0.96, rounded down from ``0.5 \cdot y_s/\sqrt{3}``); checkpoint
    round-trips bitwise. A side effect worth naming: under a fourth-order field the existing
    `AdamsBashforth(order = 4)` tracers deliver genuine fourth-order trajectories, closing the
    order mismatch the particle suite's own test documents. *(Amended 2026-09-04: overstated.
    The third-order cap that test measures is the tracer's own `Heun` bootstrap, on an analytic
    velocity with no field scheme in play — a fourth-order field removes the field's time error
    as a limit on the tracer, not the bootstrap's.)*
86. **(2026-09, user-directed) The particle traversal order — a value-preserving accelerator the
    run owns, rebuilt every iteration by default, with cadence predicates for the run's
    callback.** PF's `point_traversal_order` sorts the tracers into a tile-major visiting order so
    the interpolation gathers read the field with memory locality: the gather at ``256^3`` /
    ``10^6`` tracers fell from ``7.7`` to ``1.9`` ms on the device, while the result is
    **bit-identical** to the unordered gather (PF visits the same points with the same stencil;
    only the order changes). Three placements were weighed. The order is not trajectory *state*
    (`Tracers`), because it carries no physics and nothing of it is persisted — a checkpoint
    restores the tracers and the run rebuilds the order from their positions. It is not a
    scheme register (`ParticleIntegratorBuffers`), because one order serves every gather of the
    step — the closing deposit, the predictor and the corrector — and PF accepts any
    same-length order, so the predictor points inherit the tracers' order without a second one.
    It is not a cache slot, because it is never *read* as an observable. Hence a fourth owner,
    `ParticleTraversal` (the order plus PF's rebuild scratch plus the automatic flag), held in
    `Simulation.particle_traversal`. **Cadence:** the order decays as the tracers move — measured
    good for ``60``–``175`` steps — and a rebuild costs ``\approx 0.27`` ms on the device against
    a break-even of two to six steps, so the every-iteration rebuild sits within ``0.3\%`` of the
    optimum, and that is the default (`ordered_interpolation = nothing` resolves to `true`
    whenever the run carries tracers). A stale order is never wrong, only progressively less
    useful, which is what makes a user-chosen cadence safe: `ordered_interpolation = :manual`
    keeps the order resident and rebuilds it only through `rebuild_traversal!(sim)`, `false`
    allocates nothing, and naming the setting on a tracer-free run is refused (the by-name
    guard of decision 83, extended to one more setting). The verbs a caller drives directly take the same order
    through `traversal = nothing` (`advect!`, `deposit!`, `interpolate_at_particles!`), so the
    run layer and a hand-driven loop cannot diverge. **Cadence predicates:** the manual mode
    needs a clean way to say *every* ``n`` *steps* or *every* ``\Delta T`` in a `run!` callback,
    and the `Clock` holds only `time` and `step`, so `every_steps(n)` is a pure closure on the
    step count and `every_time(period)` a stateful predicate (a mutable `next` threshold — one
    firing per crossed multiple, a step jumping several multiples fires once); both fire at the
    seeded state, matching `run!`'s step-0 callback. **Ledgers:** the traversal is ``O(M)`` plus
    ``O(\text{tiles})`` — three vectors of the tracer count and two of the tile count — so the
    tracer delta of the memory audit stays at zero; a new M-scale testset pins the exact
    multiset and that no other owner shares the arrays. The step's allocation is a constant
    ``\approx 1.2`` KiB of launch bookkeeping, independent of ``M`` (pinned by test). Nothing of
    the traversal enters the checkpoint schema; `read_simulation` takes the same
    `ordered_interpolation` keyword and rebuilds. Bit-identity of the on / off / manual runs is
    pinned for both particle schemes, positions and Lagrangian samples alike.

87. **(2026-09, user-directed) Every concrete struct type displays, in the field library's
    convention — and the convention is the field library's decision 82, adopted whole.** Julia's
    default struct display prints every field, and this package's objects are built of
    field-sized arrays: the positions of a ``2\times 10^4``-tracer set print as ``1.13\times 10^6``
    characters, the coefficients of one ``16^3`` velocity as ``1.16\times 10^5``, and a
    `Simulation` holds a dozen such arrays. The visible half is the REPL flood; the half that
    bites harder is what an exception carries once it interpolates such an object. PF closed the same hole on its side
    the same day (decision 82 there), and its rules bind here unchanged, so that a nested PF
    object — a field, a point set, a kernel, an interpolation scheme — prints through its own
    `show` and the two packages spell one fact one way. **Two forms:** the two-argument `show` is
    one self-delimiting line, `Type(body)`, for a container, a `$(...)` and an error message;
    the three-argument `MIME"text/plain"` form is the REPL's and exists only where the line
    abbreviates something — the cache's per-slot standing, read off the epochs exactly as the
    checked reads decide it (`current`, `stale (deposited at fields epoch n)`, `never deposited`,
    a producer's scratch; the particle slot names whichever of its two counters moved on, or
    both), the domain's resolved wavenumber, the run's parts each at the path a callback types
    (`sim.generator.conditions.viscosity`, …) followed by what the callback may read without
    computing — the state, the cache's deposited reads, the tracer positions — with no row for a
    scalar or particles a run does not carry and no observable that would compute *(amended
    2026-09-05 from "one row per constructor keyword", owner-directed: a display that offered
    `flow_parameters(sim)` beside the cache reads blurred what is served from what is measured)*. **The body carries what the package
    REFUSES on**, asserted over the refused pairs: a state on another grid, element type, or
    storage family, or a box differing in the ninth decimal (`Simulation(domain; state)`); a
    scalar state against a cache or buffers without a scalar (the closing `deposit!`); a
    generator without the displaced-scalar scratch under `PhaseShift` (`scalar_rhs!`); a
    particle scheme against buffers of another order or a cache of another history depth
    (`allocate_buffers`, `advect!`); a tracer set without the unwrapped record
    (`unwrapped_positions`). **One vocabulary for an optional part:** present, it prints through
    its own display under its field name (`scalar_physical …`, `phase_shift …`,
    `unwrapped_positions …`); absent, it prints as `no scalar`, `no particles`, `no phase-shift
    scratch`, `no unwrapped positions` — a review of the first draft found the one fact "holds a
    scalar companion" spelled four ways across four sibling containers (`no scalar` / `no scalar
    slot` / `with scalar` / `scalar scratch`), and the run's REPL header, written a day earlier,
    spelling the grid a third way (`16³ grid of side …`) beside the corpus's `16×16×16`. A REPL
    row for an absent part reads `nothing (no scalar)`: the parenthesis is the aside that says
    why, the ` — ` the cache's standing, and neither is used for the other. `name = value` is
    reserved for a display that IS a constructor call and round-trips through the parser —
    `HouLi(order = 24)`, `AdamsBashforth(order = 3)`, `FlowParameters(viscosity = …)`, the
    `Phenomenology` presets `Pope2000(C_K = 1.6)` — printing only what departs from the defaults.
    **Nothing reads an element**, measured on a ``32^3`` run with ``2\times 10^4`` tracers
    against a floor of half a scalar field: the tracer count is chosen so the particle arrays sit
    above the floor too, since a display copying a dozen tracers' positions would allocate a few
    hundred bytes and pass a field-scale floor. **The gate is derived** in the field library's
    shape: every concrete struct type of the fourteen modules must carry a package-owned `show` or
    a cited exemption, checked both ways so a stale exemption fails. An empty *parametric* struct
    is enumerated — its content lives in the type parameter (`AdamsBashforth{K}`), so the default
    would print `Module.Name{3}()` — and only the true singletons are skipped; a planted
    empty-but-parametric struct is shown to be caught, since the first draft skipped every empty
    struct and covered `AdamsBashforth` by a hand-written line that no future type of the same
    shape would inherit. Nine flat records are exempt: the private `Clock` and `EveryTime`, and
    the `Phenomenology` records of numbers whose default is already their positional constructor
    call, module-qualified when the name is not in scope and round-tripping either way. A record
    *nesting* another package type is not exempt — the default qualifies every nested name, and
    ran a `Pope2000` to 157 characters — so the model-spectrum family prints as its preset's
    keyword call when its factors are that preset's and as the three-argument `ModelSpectrum`
    call otherwise, the factors spelling their own positional constructors unqualified. Two
    readings the review offered were declined with a reason: the tracer count reads `8 points`
    inside a nested PF point set and `8 particles` nowhere in this package's own text any more —
    the PF noun stays PF's, and this package's is *particle* (decision 51) — and the domain's REPL
    form keeps `max_resolved_wavenumber` beside the grid and strategy it derives from, because it
    is the one number the resolution checks (``\kappa_{\max}\eta``) read a strategy through,
    and the REPL form's purpose is to carry what the line abbreviates. The private two-line copy
    of PF's shape and storage-family helpers (`_show_shape`, `_storage_family_name`) is this
    package's own: PF's are unexported, and the channel for a request is closed.

88. **(2026-09-05, user-directed) The advanced state is projected onto real-field spectra every
    step — decision 61's twin for the second linear constraint the discretisation does not hold.**
    An owner's ``96^3`` `Float32` run under the default `VarianceController` died at ``t \approx 65``:
    the spectral kinetic energy held its target while ``\varepsilon``, the maximum speed and the
    physical field's own ``\tfrac{1}{2}\langle\lvert\boldsymbol{u}\rvert^2\rangle`` collapsed,
    the dead state's ``\varepsilon = 0.027`` being exactly ``2\nu\kappa^2 k`` at ``\kappa = 1`` — all of
    ``k`` sitting in the forced shells in a form the physical field cannot see. **Mechanism.** The
    real-to-complex layout stores both members of a conjugate pair on the folded axis's zero plane
    (and its Nyquist plane for an even axis). Their anti-Hermitian combination is invisible to the
    inverse real transform, so the nonlinear term — formed from the physical fields — neither sees
    nor feeds it; viscosity damps it at ``\nu\kappa^2``, next to nothing at ``\kappa \approx 1``;
    and every forcing of the form ``\hat{\boldsymbol{N}} \mathrel{+}= A \chi_{\text{band}} \hat{\boldsymbol{u}}``, with ``\chi_{\text{band}}`` the band indicator,
    (`VarianceController`, `ConstantPower`, `Linear` through the integrating factor, `VarianceRescaling`
    through its rescale) amplifies it with the same ``A`` as the physical modes, which ``A`` must hold
    positive on average to balance ``\varepsilon``. Net growth ``A - \nu\kappa^2 \approx 0.26`` per
    time unit, seeded by the transform's own round-off on that plane — FFTW exactly Hermitian at
    ``32^3``, ``64^3`` and ``128^3`` but ``1.5\times10^{-7}`` (`Float32`) at ``96^3`` and ``256^3``;
    cuFFT and rocFFT at round-off everywhere — so the death time is seed-independent: six seeds at
    ``t = 66``–``71``, RK3 and RK4, `TwoThirds` and `PhaseShift` alike, `Float64` at ``t = 142``
    (a floor ``10^{-9}`` smaller, ``\ln 10^9/0.26 \approx 80`` time units later, as the rate
    predicts). `reality_residual` traces it from ``4\times10^{-2}`` at ``t = 0`` to
    ``1.3\times10^{6}`` at saturation. `StochasticOU` (additive) and decaying runs are unaffected —
    and a ``32^3`` CPU run is unaffected by luck, FFTW being exact there, which is why the suite had
    never seen it. Two consequences were the worst of it: every Parseval diagnostic (``k``,
    ``\varepsilon``, the spectrum, `flow_parameters`) reported the ghost as energy, and the
    stationarity criterion, reading those, would have certified a dead run as stationary.

    **Prior art.** TurTLE's `symmetrize()` (the pair's arithmetic mean, after every step and every
    forcing); Dedalus's `enforce_real_cadence` (a grid round trip every 100 steps, "decrease under
    strong linear instabilities"); FFTW++'s `HermitianSymmetrizeX` (never evolve the redundant
    half); and Wang & Rosa (2009), *A spurious evolution of turbulence originated from round-off
    error in pseudo-spectral simulation*, Computers & Fluids **38**, 1943–1949 — the same shape on
    the divergence-free constraint, round-off amplified over ``\approx 50`` turnovers, re-projection
    per step as the remedy, which is decision 61 here. GHOST is immune by an additive forcing and
    pair-aware operations; hit3d and Fluidsim carry the same multiplicative forcing unprotected and
    survive only on the host transform's exactness.

    **The fix.** PF's `reality_projection!` (its decision 83, requested with this evidence and shipped
    the same day; decision 71's "by construction" clause corrected on it): on the stored
    self-conjugate planes each pair becomes ``\tfrac{1}{2}(\hat f(k) + \overline{\hat f(-k)})`` and its
    conjugate — the orthogonal projector onto real-field spectra, idempotent, commuting with every
    per-mode multiplier ``m`` with ``m(-k) = \overline{m(k)}``, ``O(N^2)``, in place, nothing else
    touched. Called once per step at each scheme's exit beside `helmholtz_projection!`, after
    `finalize!`, for ``\hat{\boldsymbol{u}}`` and ``\hat\varphi``. Once per step, not per stage: the
    anti-Hermitian part is decoupled from the nonlinear term, so a stage-wise pass buys nothing.
    Settled with the request and worth keeping settled: projection only (no Nyquist zeroing, a
    dealiasing policy the truncation already enforces), no residual returned (`reality_residual`
    stays the checker), nothing folded into the transforms. The physical round trip was measured
    and rejected as the repair: it resets the residual only to the transform's floor, since the
    forward transform reseeds it, and perturbs every mode by round-off; a time-cadenced round trip
    did keep the ``96^3`` run alive to ``t = 100`` and stands recorded as the stopgap it was.

    **Ledgers.** The pass touches one or two planes per component, ``1/N`` of a field pass, and the
    compute ledger counts traffic in ``N^3`` units at leading order in ``1/N``; the op is in every
    scheme's op list (a real in-place read and write of the state, which the liveness model sees,
    and a renamed op fails the price table) and priced below the ledger's resolution, as the O(1)
    mean-mode pin and the tracers' ``M \times 3`` reads are. Its pass count is pinned at the ideal
    in the field library's pass audit. No memory. **Witness** (`test/regressions/r7-reality-projection-forced-run.jl`):
    a planted ``2\times10^{-6}`` anti-Hermitian perturbation on the pair ``(0,\pm1,0)`` — planted,
    because a witness waiting for the library's own seed passes vacuously wherever FFTW is exact —
    is removed exactly by the next step, velocity and scalar; under the controller the residual is
    exactly zero at every step and the spectral ``k`` equals ``\tfrac{1}{2}\langle\lvert\boldsymbol{u}\rvert^2\rangle``
    on the grid to round-off; `Float32` at ``48^3``, where the transform seeds, likewise. The
    `fields_modified!` refusal now names `reality_projection!` as the repair.

89. **(2026-09-17, user-directed) CUDA unified memory is inherited, not implemented; what a run needs
    on a card is a page, and the suite holds that page to the code.** The field library made CUDA.jl's
    `default_memory = "unified"` preference a supported configuration (its decision 84), prompted by
    this package at ``768^3`` `Float64` on a 96 GiB GH200. **Inheritance.** The package allocates only
    through `array_type{S}(undef, dims...)` in the domain's allocators and `similar` in the particle
    code, and names no memory kind, so every array a run holds follows the preference with no code
    change. Checked on the RTX 5070 Ti in two environments differing only in the preference: 29 of 29
    arrays unified for a bare run, 36 of 36 with the scalar, 45 of 45 with the scalar and ``10^4``
    tracers, 45 of 45 for a run restored by `read_simulation` — and none in the device-memory control.
    **Placement.** A page (`docs/src/gpu.md`), linked from the landing page and from the `array_type`
    bullets of `FixedDomain` and `Simulation`. The mechanism — the call, the two entries it writes, the
    `[CUDACore]` spelling that leaves it silently off — stays on the field library's page and is linked,
    never restated: belongs-in-PF holds for documentation too. What is this package's own is the
    storage a run holds, that the preference reaches all of it, and the caveats. A docstring was
    rejected as the table's home (it depends on four settings, none of them `array_type`), and so was
    this log, which cannot correct a number in place. **The table is derived, not typed.** Storage is a
    cubic polynomial in ``N`` for even ``N``, so `test/gpu_memory_page.jl` reads the table out of the page, fits each
    row exactly at four sizes, requires a fifth to match byte for byte, and compares the leading
    coefficient and the ``512^3``/``768^3``/``1024^3`` values; it classifies every exported integrator,
    forcing and dealiasing strategy as leaving the table unchanged or adding storage, so a new one
    fails until the page places it; and it pins the bytes per tracer. The device-side excess (the
    transform workspace and the allocator's rounding, 5–38 bytes per point) is stated as measured
    once, and marked unchecked. The derivation corrected the sizing behind the field library's
    decision: ``768^3`` `Float64` holds 91.3 GiB under `PhaseShift` without the scalar (hence "short by
    a few GiB" with the workspace and context on 96 GiB) and 114.9 GiB with it. The memory audit is
    unaffected: its ledgers are static and never read `CUDA.used_memory`, which does not count unified
    allocations. **Open, stated on the page rather than assumed away:** the package has no GPU test
    lane of its own; unified arrays ignore `allowscalar(false)`, so a unified run cannot catch a stray
    scalar index; and the cost of a time step in unified memory is unmeasured everywhere, GH200
    included — no GH200 figure is written until one is measured on this package's step.

90. **(2026-09-18, user-directed) `StochasticOU` returns as a coarse companion field, with its
    process in the state record — decision 23(c) built, decision 75's non-persistence ruling
    superseded, and the field library's `embed_modes!` the one thing it needed.** The owner asked for
    the Eswaran–Pope forcing as a full option. It had been archived (§7) because its dense form drew
    white noise on the whole grid every step, transformed, band-limited, projected and normalized it,
    and held three field-scale arrays to drive shells 1–2. Measured on the RTX 5070 Ti at ``128^3``
    `Float32`: 17.6 ms per step against the default forcing's 3.2 ms, and 25 MB of host allocation per
    step — the noise was drawn on the host and copied over, 5 GB per step at ``768^3``.

    **The design, and how it was reached.** A first implementation kept the process on a host-side list
    of the band's conjugate mode pairs and asked the field library for an O(M) write at those modes.
    Two adversarial rounds passed it, and the owner then rejected it on the ground the rounds had been
    briefed away from: that form has this package hand-writing the per-mode transverse projection, the
    ±``\boldsymbol{\kappa}`` and self-conjugate-plane bookkeeping, the per-mode variance accounting, and
    bespoke persistence and display — four pieces of machinery the field library owns, against
    invariant 2. The defence of it rested on the code already being written and measured, which is the
    circular justification this file's own self-guards name. The request was withdrawn mid-ruling.

    **What ships.** The process is an ordinary field in spectral representation on a **companion grid
    over the same box** — the smallest even grid whose modes cover the band, ``6^3`` for the default
    shells 1–2. Two grids over one box resolve the same physical wavenumbers where they overlap, so the
    companion's modes are exactly a subset of the run's. Each step: a host Gaussian draw into a
    companion physical field (the stream stays the seed's, and the draw is real, so its spectrum
    satisfies the reality condition by construction), `to_spectral!`, the band kernel, and — for the
    velocity — `helmholtz_projection!`, then `combine!` for the exact transition
    ``\boldsymbol{a} \leftarrow \alpha\boldsymbol{a} + \sqrt{\sigma^{2}(1-\alpha^{2})} \boldsymbol{\xi}``,
    ``\alpha = e^{-\Delta t/T_L}``, starting from a stationary draw. Every stage adds the process into
    the assembled term with the library's `embed_modes!` (its decision 85, requested and shipped
    2026-09-17/18), which writes only the shared modes, carries physical amplitudes across the
    resolution ratio, and never traverses the run's own field.

    The increment's scale is the **expected** variance of the masked, projected draw —
    ``2M/N_c^{3}`` per unit variance for the velocity, ``M/N_c^{3}`` for the scalar, with ``M`` the
    band's lattice modes counted once at construction. The archived form divided by each draw's
    *realized* norm, which fixes every increment's size — not the independent Gaussian modes the method
    defines — and cost a device-to-host reduction every step. Measured at ``32^3``: the stationary mean
    square within 0.5 %, the lag-one correlation equal to ``\alpha`` to ``10^{-3}``, the mean square
    fluctuating as ``\chi^{2}`` over the retained degrees of freedom (the realized-norm form is pinned
    against), every mode's share equal within sampling error, and the mean injection rate 0.024 and
    0.047 against the docstring's ``\sigma^{2} T_L`` of 0.025 and 0.050 (``T_L = 0.05, 0.1``), with
    ``2\sigma^{2}T_L`` confirmed for the scalar variance.

    **Cost, measured on the RTX 5070 Ti at ``128^3`` `Float32`.** 2.68 ms per step — *faster* than the
    default `VarianceController`'s 3.22 ms, because the controller reads its band observable back to the
    host every stage and this forcing reads nothing back. Host allocation per step is the run's own;
    the forcing adds none. Nothing it holds scales with the grid: at ``64^3`` the strategy and its state
    together are under 1 % of one spectral vector, pinned in the memory audit, and the audits' reflective
    walk now classifies residency by the run's own field shapes rather than by a threshold, so a
    companion grid is never miscounted as residency (it was, at the audits' tiny ``N``).

    **Where it lives.** The process and its draw count are a `StochasticOUState` in the new `modeled`
    slot of `ResolvedFields`, one entry per forced field — decision 23(c)'s Markovian surrogate, built.
    The strategy holds parameters and the scratch of one draw, is immutable, and may drive both fields.
    The protocol gained `initial_forcing_state(forcing, field, domain)` (default `nothing`);
    `prepare_forcing!` gained the state as its second argument, and `add_forcing_source!` likewise, the
    generator carrying each forcing's state from the step `prepare!` opened, since the right-hand-side
    verbs are handed a stage field rather than the record it came from. The stale-hook guard now refuses
    either old arity, and `prepare_forcing!` on a `StochasticOU` refuses a missing state rather than
    leaving the run silently unforced. `Simulation` starts the states of a fresh record; an adopted
    record keeps one that fits its forcing and is refused by name when it does not.

    **Persistence — decision 75 superseded.** Decision 75 ruled a stochastic forcing's evolving force
    and stream non-persistent, when neither had a home in the record and the stream was a generator's
    internal state. Both reasons are gone, and the owner chose the state's home knowing a checkpoint
    would then carry it. The process is written through the library's own `write_field` and the draw
    count beside it (schema 2), so a restored run continues the same realization bitwise — pinned for
    both fields. A schema-1 file, which has no such group, restores with the forcing started afresh.
    The stream itself is a pure function of the seed, the draw count and the forced field, through a
    scratch generator reseeded from their 128-bit packing before every draw (widened before the shift,
    which at 64 bits would silently drop the seed), so a velocity and a scalar forcing given one seed
    draw independently and the draw count is the whole stream state.

    **The band must lie inside the dealias cutoff.** The source is added after the dealiasing mask, so
    an additive force past the cutoff would fill modes the nonlinear term assumes empty; construction
    throws where the multiplicative strategies only warn. The companion grid is sized so the band sits
    strictly below its Nyquist frequency, whose modes a transfer between resolutions cannot carry.

    **Ledgers.** Every audit cell of an OU-forced run is the unforced cell's: no field-scale residency
    (the dense form held two spectral and one physical vector), no transforms at the run's resolution
    (it had three per step), no passes at field scale, and the last memory-gap holder (OWNERSHIP, OU
    noise ↔ product) retired with the noise. The synchronization row falls from four crossings per step
    to two — one of which is the adaptive timestep's, the other the scalar run's NaN guard.
    **Not done:** no code-to-code comparison exists — TurTLE has no Ornstein–Uhlenbeck forcing — so the
    process rests on the statistical tests above.

91. **(2026-09-18, user-directed) The package is `GBGHomogeneousTurbulence`.** Renamed before the
    first release, when a rename is still cheap. **Why the old name was wrong.** A triple-periodic
    pseudospectral box enforces *homogeneity*; isotropy is only what the default forcing and initial
    condition choose — nothing in the domain, the generator, the propagator or the transforms knows
    about it. Naming the package for a property of its default configuration rather than for its
    invariant is the same category slip the doc policy warns about, and §7 already defers flows the
    old name excluded: the sheared frame (Rogallo) and the uniform-mean-gradient scalar source are
    homogeneous and anisotropic. Sagaut & Cambon's *Homogeneous Turbulence Dynamics* (2nd ed.) puts
    the scope plainly: chapter 4 is homogeneous isotropic turbulence, chapters 7–12 are rotation,
    strain, shear, buoyancy, coupled cases and MHD — every one homogeneous, every one reachable from
    this machinery with extra generator terms or a moving frame. The old name covered one chapter of
    the fourteen. **The boundary, stated rather than implied.** Their chapters 13–14 are compressible
    homogeneous turbulence, which this package does **not** reach: the incompressible Leray
    projection is structural here, not a setting. Compressible homogeneous turbulence is out of
    scope, as §3 records for the Model. **Mechanics.** Repository `GBGHomogeneousTurbulence.jl`,
    module and extension renamed, every current-state surface swept by hand — the sibling-link
    tooling cannot catch a rename, since a table keyed on a package's spelling goes quiet rather than
    failing. Two things deliberately keep the old spelling: this log, which records what the package
    was called when each decision was made, and the `type` attributes of checkpoints written before
    today — a stored tag is normalized to the current spelling on read, so those files still load and
    nothing rewrites them. **Fleet.** The three sibling sessions were told before the rename, since a
    Dropbox working copy and their `inspiration/` clones point at the old path; two of them held
    tables keyed on the old name that would degrade to silence rather than fail. *(Corrected the same
    day: this entry first said both had fixed the class. One of those fixes was made without its
    owner's authorization and was reverted, and the claim should not have been written here from
    another session's report. What is verified is the exposure, not any repair — and that GitHub
    redirects a renamed repository URL but not its Pages URL, so a stale link in a sibling's table
    breaks outright.)*
92. **(2026-09-24, user-directed) `highest_shell = Inf` is the band-free form of every
    field-multiplying forcing.** It forces every retained mode but the mean, on any grid. **Why.**
    The linear forcing a physical-space code applies acts on the whole field, and the only way to ask
    for it before was `highest_shell = N`, a number the user had to restate for every grid. With the
    band set to the whole field, `Linear` is Lundgren's forcing itself, `VarianceController` is
    Bassenne et al.'s scheme in the physical-space form their title names (``k_f = k``),
    `ConstantPower` is the constant-injection variant, and `VarianceRescaling` is the whole-field
    rescale ``\boldsymbol{u} \leftarrow \boldsymbol{u}\sqrt{\texttt{target}/k}`` — verified mode
    by mode to round-off, and identical under `over = :band` and `:total`, which then coincide
    (`over` stays required, one rule rather than a special case, and the docstring says they agree).
    **What is stored is `Inf`, not the shell it resolves to.** A strategy's shell bounds are what
    rebuild its band and what it displays, and `Inf` rebuilds the right band on any grid, where the
    resolved shell would read back as "every mode" only on the grid it came from. PF's
    `spectral_band` requires finite edges, so IT resolves `Inf` at construction to the stored grid's
    corner, ``\lceil\sqrt{3}N/2\rceil`` shells — past every mode the grid holds, retained or not,
    whatever the dealiasing mask's shape. That is the physics-side reading of an unbounded request
    mapped onto a finite-edge operation, not field machinery, so it is not a PF raise. **`Inf` is the
    only non-integer.** A lattice ``\lvert\boldsymbol{\kappa}\rvert^2/\kappa_0^2`` is always an
    integer and an integer shell's edge sits at ``(n + \tfrac{1}{2})^2``, which never is one, so no
    mode lies on an edge for roundoff to decide; `highest_shell = 2.5` would put the edge on
    ``\lvert\boldsymbol{\kappa}\rvert = 3\kappa_0``. **The mean stays out**, since `lowest_shell`
    is still at least 1: the band-free form is ``\boldsymbol{f} = A(\boldsymbol{u} - \langle\boldsymbol{u}\rangle)``,
    not the literal ``\boldsymbol{f} = A\boldsymbol{u}``, which would drive the mean at rate ``A`` with nothing to
    damp it and amplify its round-off exponentially — the class decision 88 closed for the
    self-conjugate planes. **`StochasticOU` refuses it**, by name: an additive source must stay below
    the dealias cutoff, and its coarse grid is sized from the top shell. **Rejected:**
    `highest_shell = nothing` (a physicist can read "no highest shell" as "no band"; `Inf` has one
    reading), a separate band argument such as `shells = 1:2` (Base has no infinite integer range, so
    "all" would need its own sentinel anyway), a named constant (an invented alias for a number
    everyone reads), and `typemax(Int)` (a workaround, not an interface). *(Amended the same day: the test is on the value, not the type.
    An integer-valued float such as `2.0` is accepted and stored as the integer, because a sweep
    written `[2, 4, Inf]` promotes its integers to `Float64`, and refusing `2.0` broke the natural
    way to vary the band. Only a fractional value such as `2.5` is refused.)*
93. **(2026-09-24, user-directed) The Lamb vector is ``\boldsymbol{\omega}\times\boldsymbol{u}``, vorticity
    first — the literature's sign — and the package follows it.** **Why.** A PF reviewer questioned an
    example calling ``\boldsymbol{u}\times\boldsymbol{\omega}`` "the Lamb vector", and this package did
    the same on its landing page, in §4.2 and in `velocity_rhs!`. The owner asked for a firm check
    rather than recall, so the definitions were read from primary texts. Lamb (1932), Art. 146, Eq. (5)
    (read from the page scan), writes the rotational form as
    ``\partial_t u - v\zeta + w\eta = -\partial_x\chi'``, whose middle terms are
    ``(\boldsymbol{\omega}\times\boldsymbol{u})_x``; he gives the vector no name. Every source found that
    does name it takes vorticity first: Hamman, Klewicki & Kirby (2008, p. 265, "l = ω × u … or Lamb
    vector"), Sagaut & Cambon (2018, p. 586, "the Lamb vector ω × u"), and eleven more, each read in its
    own text —
    turbulence theory, experiment, aerodynamic force theory and aeroacoustics, 1996–2022 — along with
    OpenFOAM's `LambVector` function object, which computes `fvc::curl(U)^U`. None defines the reversed
    order. Pope (2000) writes ``\boldsymbol{U}\times\boldsymbol{\omega}`` but never names it. Wikipedia
    defines the reversed order, and it contradicts itself: its divergence identities are Hamman et al.'s,
    which hold only for vorticity first, and its page citation to Lamb (1932) lands on the motion of two
    spheres. The reversed usage is a code-side habit of solvers that write the term on the right-hand
    side, not a definition anyone publishes. **The convention, applied.** The identity is
    ``(\boldsymbol{u}\cdot\nabla)\boldsymbol{u} = \nabla(\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^2) + \boldsymbol{\omega}\times\boldsymbol{u}``
    and the momentum equation is ``\partial_t\boldsymbol{u} = -\mathbb{P}(\boldsymbol{\omega}\times\boldsymbol{u}) + \nu\nabla^2\boldsymbol{u} + \boldsymbol{f}``
    on every current-state surface. **The arithmetic did not change.** The solver still forms the
    velocity-first product in place over the vorticity's array: reversing a cross product's operands
    negates it, so the minus sign is carried by the operand order and costs no pass, and the run is
    bit-identical. What changed is the name — that product is the *negated* Lamb vector wherever it
    is named — and the internal assembly function, now `_velocity_advective_term!`, which no longer
    claims to form the Lamb vector. The one term the package might have introduced, a Lamb-vector
    symbol, was not: ``\ell`` is `large_scale_length`, and a bold ``\boldsymbol{l}`` beside it invites
    the confusion the glossary exists to prevent, so the vector is written out. **Enforced**, not only
    stated: `docs/make.jl`'s `lint_lamb_vector_sign()` fails the build on a velocity-first cross product
    — in math, in Unicode or as the `cross!` call — within three lines of the word *Lamb* unless the
    window names it the negation. It fired on six sites of the tree it was written against (the
    landing page, §4.2 and four in the generator) before any was fixed. It cannot see a sentence that
    calls a register's contents the Lamb vector with no product written nearby; those were swept by
    hand, from a full enumeration of the word's occurrences and of every velocity-first product, and
    the glossary row is the reference. The decision log is exempt as history.
94. **(2026-09-24, user-directed) The package's first goal is the law ``G(\text{forcing}, \mathrm{Re}_\lambda,
    \text{band})``, and until it exists the run layer uses ``G = 0.7``.** **Why.** The run layer derives
    ``\nu`` from a requested ``\kappa_{\max}\eta`` through the stationary estimate
    ``\varepsilon = (k/G)^{3/2}/L``, and it used `Li2008`'s ``G = 0.9``, a JHTDB reduction at
    ``\mathrm{Re}_\lambda \approx 433``. The owner's first sweep, 96³ `VarianceRescaling(over = :total)`
    runs at ``k = 1.5`` across the three dealiasing strategies and ``\kappa_{\max}\eta = 1.5`` and 3,
    measured ``G = 0.59``–0.74 on shells 1–2, rising with ``\mathrm{Re}_\lambda`` over about 28–66;
    ``\approx 0.50``–0.59 on shells 1–4; and ``\approx 0.44``–0.48 on every mode. Plotted against the
    ``\mathrm{Re}_\lambda`` each run actually reached, the three strategies fall on one curve per band,
    so dealiasing enters only through the Reynolds number it buys. The consequence was practical, not
    only scientific: with 0.9 a requested ``\kappa_{\max}\eta = 1.5`` delivered about 1.37 on the
    default band and 1.18 on every mode, and the logged ``\mathrm{Re}_\lambda`` overstated the real one by
    15–40%. An earlier witness had seen the same bias at 32³, where the modelled ``\varepsilon`` fell
    about 2× short. ``G = 0.7`` is the default band's value at the upper end of the Reynolds numbers
    reached; it corrects the common case and is **not** a law — the band dependence alone moves ``G`` by
    a third. **Where the value lives.** `Li2008` keeps 0.9: it is the record of that paper's dataset, and
    relabelling a number the package measured as Li et al.'s would misattribute it. The provisional value
    is one constant in `Forcing`'s stationary estimate, which the `VarianceController`'s default clock
    already used and which the run layer now calls too. The two previously held separate copies pinned
    together by a test; they now share one function, so they cannot disagree. **What comes next** is
    the owner's: the sweep design (forcing type × band × ``\mathrm{Re}_\lambda``, resolution and
    dealiasing as convergence checks) and, once enough data exist, whether the law enters as an
    empirical fit, a theoretical form, or a ``\nu`` that recalibrates itself from the warm-up's measured
    ``\varepsilon``. *(Amended 2026-09-26, decision 97: `Li2008` was removed, so "Where the value lives"
    now records only the package's provisional constant.)*
95. **(2026-09-24, user-directed) A run is set up for a stationary state stated once, and the
    default forcing holds its dissipation rate.** **The state.** A forced run settles at a pair
    ``(k, \varepsilon)``. `Simulation` now takes it from exactly one source — `kinetic_energy`,
    `dissipation`, or the target of a velocity forcing that holds one of the two — and predicts the other
    member through ``G``, the only place ``G`` enters a run. Two sources are an `ArgumentError`, because
    the state would be stated twice; none gives ``k = 1.5``. Before, `kinetic_energy` and a forcing's
    target stated the same quantity separately and a mismatch only warned. The derived viscosity is
    solved from the state's ``\varepsilon``, the initial velocity is seeded at its ``k``, and a start
    from another energy is an adopted `state`. **Filling the forcing.** A deferred velocity forcing
    may leave its target out, and the run fills it from the state: `ConstantPower` its injection rate
    from ``\varepsilon``, `VarianceController` and `VarianceRescaling(over = :total)` their target from
    ``k``, `StochasticOU` its variance from ``\varepsilon/T_L``. `DeferredForcing` therefore holds its
    strategy and keywords rather than an opaque closure, so the run can see what was stated. Three
    stay required. `Linear`'s rate would need the band's own energy, a model the ``G`` study must
    supply (the open item for the paper). `VarianceRescaling(over = :band)` holds that energy. A
    scalar forcing's target stays required because the scalar has no modelled state, and the
    mechanical-to-scalar time scale is a project in itself (owner-ruled). **Why the state, and why
    ``\varepsilon``.** Resolution is a statement about ``\eta = (\nu^3/\varepsilon)^{1/4}``, so
    given ``\varepsilon`` the viscosity for a requested ``\kappa_{\max}\eta`` is exact, with no ``G``
    between request and outcome; given ``k`` instead, ``G``'s error lands on the resolution.
    Holding ``\varepsilon`` moves that error onto ``k``, which only rescales the velocity unit.
    Measured in the rewritten 32³ witness: `ConstantPower` at two injection rates reached
    ``\kappa_{\max}\eta = 2.016`` against 2, a `VarianceRescaling(over = :total)` holding ``k``
    reached 1.815. **The default is `ConstantPower()`**, and the owner's reason is not the guarantee
    but that it has no gain or settling time to choose — fewer parameters to get right. It enters
    every stage like the `VarianceController` it replaces, so default runs keep the scheme's order,
    and ``k`` now fluctuates freely rather than being restored. Tests that seeded one energy beside a
    target holding another now adopt a seeded `state`; the witness pinning the old "ν is
    forcing-independent" contract now pins the new one.
96. **(2026-09-26, user-directed) `kinetic_energy_and_dissipation_below_scale`: the energy and dissipation
    a sub-box of side ``l`` measures.** The owner's construction: cut a cube of side ``l``, remove its
    own mean, compute ``k`` there, and average over every position. That average is exactly
    ``k(l) = k - \tfrac{1}{2}\langle\lvert\langle\boldsymbol{u}\rangle_l\rvert^2\rangle =
    \tfrac{1}{2}\sum(1 - W_l^2)\lvert\hat{\boldsymbol{u}}\rvert^2``, the position average of Pope's
    residual kinetic energy of a top-hat filter (2000, Ex. 13.22); the vorticity analogue gives
    ``\varepsilon(l)``, because removing the mean *velocity* leaves every gradient and so a flat
    ``\varepsilon``. **Settled with the owner:** the cube, on principle (other window shapes may
    become an option later); one function returning `(; scales, kinetic_energy, dissipation)`, named
    after `kinetic_energy_and_dissipation` since it carries both; ``N`` domain-derived sides
    ``l = nL/N``; the glossary symbols ``l`` (free) and ``W_l`` (``G`` already wore two meanings).
    **The window is PF's** — requested 2026-09-22 with the full rationale and built as `tophat_window`
    (PF decision 87; `assignment_window` is now its square at the grid spacing), so no kernel machinery
    lives here. It is the continuum box mean of the band-limited field, not a mean of grid values.
    **The batch width is measured, not assumed:** on the RTX 5070 Ti two sides per traversal were the
    fastest or tied at 128³ and 256³ in both precisions, wider batches slower (the per-mode arithmetic
    of the lazy product kernels, not the saved field read, sets the cost), and 32 weights in one fused
    tuple fail to compile on CUDA (Julia's generic splat past its tuple limit), so ``B = 2``, ROCm still
    to be measured. **Precision:** each value is a whole-field reduction minus a retained part, so in
    `Float32` the smallest sides of a field with little small-scale energy lose digits — batch widths
    differed by up to ``6\times10^{-4}`` relative there at 256³; the docstring says to measure in
    `Float64` where those sides matter. **Tested** against two independent oracles: the exact spectral
    sums as plain host loops (``10^{-12}``), and the definition itself — boxes cut on an 8× zero-padded
    grid, each mean removed, averaged over positions — elementwise within its own ``1/q^2``
    discretization bound, which the tempting ``(1 - W_l)^2`` form misses by up to 97%. *(Amended
    2026-09-27, decision 98: the batch width and its padding are gone; the observable passes all its
    weights to one `weighted_inner` call, and the 32-weight compile failure was fixed in PF, its
    decision 88.)* *(Notation updated 2026-09-29: the box mean, written ``\bar{\boldsymbol{u}}_l`` when this
    entry was recorded, is ``\langle\boldsymbol{u}\rangle_l`` by decision 102.)*
97. **(2026-09-26, user-directed) `Li2008` and `stationary_dissipation` are removed from
    `Phenomenology.Scalings`.** **Why.** The law gave one number, ``G = 0.9``, the package's own reduction
    of one JHTDB dataset at ``\mathrm{Re}_\lambda \approx 433``. It is not a published
    ``G(\text{forcing}, \mathrm{Re}_\lambda, \text{band})`` or band energy fraction, and no published
    source provides them (decision 94 makes measuring them the package's first goal). A preset naming a
    paper that does not supply the quantity misattributes it, and the run layer had already stopped
    using it. `stationary_dissipation` had `Li2008` as its only method, so it goes too. The Li et al.
    (2008) entry leaves §References, which lists only works a current docstring cites. The provisional
    ``G = 0.7`` stays in `Forcing`'s stationary estimate. Its test now spells out
    ``(k/0.7)^{3/2}/L`` rather than evaluating a law. `Scalings` keeps `Sreenivasan1998` and
    `Sreenivasan1995`.
98. **(2026-09-27, user-directed) `kinetic_energy_and_dissipation_below_scale` uses PF's
    `weighted_inner` as documented, with no batching layer of its own.** **Why.** Decision 96 split the
    ``2N`` weights into batches of a width measured on one GPU, padded the last batch, and recorded
    the width as a tuning constant. That was a layer built over the backend to fit measurements that
    depend on Julia's compilation path, the backend and the hardware. How many weights one traversal
    answers is PF's concern, and PF now owns it: its tuple form takes any number of weights and groups
    them itself (PF decision 88, fixing the 32-weight compile failure reported from here). The
    observable now builds every side's two weights and makes one call. **Measured once, to confirm it
    works, not to tune it:** on the RTX 5070 Ti one call at 256³ takes 0.17 s in `Float32` and 0.26 s
    in `Float64`, after a first-call compilation of about 10 s for each grid size, since the weight
    tuple's length is ``2N``.
99. **(2026-09-28, user-directed) HT's calls into PF, reviewed by PF and corrected.** HT sent PF its
    audit of every place HT reached past PF's API. PF ruled on each and shipped two operations for it
    (PF decision 90): `mean_free_projection!` and `materialize_kernel!`. **Mean mode.** The velocity's
    advective term had its ``\kappa = 0`` coefficient zeroed by writing raw storage at the index PF
    keeps private. It now uses `mean_free_projection!`, exact and ``O(1)``, in the same place: between
    the assembly and the forcing source, since the Leray projection passes the mean through. The scalar
    path's zeroing is gone. The divergence's mean is exactly zero under all three dealiasing strategies,
    and a test pins it with `iszero`. **`Linear`'s rate.** `Linear` kept the materialized band as a raw
    real ``N^{3}`` array (1.69 GiB at 768³ `Float64`) and rewrote the rate from it by a raw broadcast at
    every step. The rate is steady, so the generator now fills it once, when it is built, from the
    steadiness probe's own fill. `Linear` keeps only its lazy band kernel, and the fill is
    `materialize_kernel!(StoredKernel(rate), band)` followed by `multiply!`, allocating nothing. The
    memory ledger drops the real array and the compute ledger the per-step write. **`max_speed`** keeps
    the fused `maximum` but maps the squared magnitude and takes one square root. The overflow-safe
    fiber `norm` it used costs several times more, and a velocity cannot overflow; the result is
    identical. **Raw-storage clean-ups.** In-place scalings use `multiply!`, and host-drawn random fields
    reach the run's storage through `adapt!`. The element type is read with `field_scalar_type`, and
    the CFL grid spacing from the grid. **Kept, on PF's ruling:** `StochasticOU`'s exact lattice mode
    count, `_check_reality`'s largest-stored-coefficient scale, and the zero fill in the allocators
    (PF's constructors return uninitialized memory). *(Verified the same day: 24 fixed-``\Delta t`` runs
    covering every changed path — `Linear` on its default band and on every mode, a `Linear`-forced
    scalar, `StochasticOU`, `ConstantPower` with a scalar — under the three dealiasing strategies in
    both precisions are bitwise identical to the pre-change tree on the CPU. `max_speed` matched at
    all 3600 sampled steps, because StaticArrays' `norm` returns the plain magnitude whenever it is
    finite and nonzero, so adaptive runs are unchanged too.)*
100. **(2026-09-28, user-directed) HT's remaining raw-storage sites, ruled by PF, and a test that
    keeps the list closed.** PF reviewed three sites the first audit missed and changed two things for
    them (PF decision 91): `adapt!` now refuses every mismatch by name, and fields compare by value
    with `==`. **Checkpoint loads.** A stored field, which `read_field` returns on the host, is moved into
    the run's field with `adapt!`, and so is `StochasticOU`'s process. HT's own size and element-type
    checks and the raw `copyto!` are gone; HT only puts the checkpoint's context in front of PF's
    message. One behaviour changed, correctly: `adapt!` compares the whole grid, so a checkpoint with
    the same point count but another box side or origin, which the size check let through, is now
    refused. **The steady-rate probe** keeps its two raw fills: the probe is a fixture, not a physical
    field, and PF has no operation for writing arbitrary coefficients. It compares the two rates with
    PF's `==` instead of their raw storage. **The check.** `test/pf_storage_access.jl` lists every
    `field_data` call in `src/` and `ext/` against an allowlist, each entry citing its ruling. A new
    site fails the suite until it is ruled on, and an entry whose site is gone fails until it is
    removed. It is falsified in the same test, against a planted site and a deleted one. It cannot see
    a layer built over a correct PF call, such as the batch width of decision 98; that remains a matter
    for review.
101. **(2026-09-29, user-directed) The box-normalized quantity is ``\tilde{k}``, the kinetic energy in box
    units, and a tilde means box units throughout.** Decisions 94 and 95 wrote it ``G = k/(L\varepsilon)^{2/3}``
    and called it the box-normalized dissipation group, a name taken from the `Li2008` law, which
    decision 97 removed. The literature has no name for it. ``G`` also names `VarianceController`'s
    gain, so the glyph meant two things. **The symbol:** ``\tilde{k} = k/(\varepsilon L)^{2/3}``, with
    the tilde marking a quantity in box units: the unit system built from the box side ``L`` and
    ``\varepsilon``, as Sagaut & Cambon mark nondimensional variables. The hat is taken by the spectral
    representation, and the asterisk by the complex conjugate. The tilde is free because averages and
    filters are written as brackets with an index, never with a tilde or an overbar (owner ruling,
    same day). Its physical reading is ``\tilde{k}^{3/2} = (k^{3/2}/\varepsilon)/L``, the large-eddy length
    as a fraction of the box side. The companion Reynolds number is
    ``\mathrm{Re}_{\mathrm{box}} = \varepsilon^{1/3}L^{4/3}/\nu = 1/\tilde{\nu}``, written with ``\mathrm{box}`` rather
    than ``L``, because Pope's ``\mathrm{Re}_L`` is ``k^{2}/(\varepsilon\nu)``. The band energy fraction
    is written ``k_f/k``, since ``f`` names the force. *(Superseded the same day by decision 103: the band
    energy is ``k_{\mathrm{band}}``, the fraction ``k_{\mathrm{band}}/k``.)* **Names, for the model to come:**
    `kinetic_energy_in_box_units` and `band_energy_fraction`, with the Reynolds keywords
    `reynolds_box` and `reynolds_taylor` (owner ruling; `Phenomenology` is not a precedent until it is
    extracted). `G` now names the gain alone, and the provisional constant is
    `_KINETIC_ENERGY_IN_BOX_UNITS`. Earlier log entries keep ``G`` as history.
102. **(2026-09-29, user-directed) Averages and filters are brackets with an index, never an overbar or
    a tilde.** The box mean of side ``l`` is ``\langle\boldsymbol{u}\rangle_l``, a field; the unindexed
    ``\langle\cdot\rangle`` is the average over the whole box; a time average over a window is
    ``\langle\cdot\rangle_T``, as in Pope's glossary. Converted: the ``k(l)`` docstring and its test, the
    validation page's window means, the mean scalar of the mean-gradient source in §7, and the box
    mean in decision 96 (with an in-entry note, at the owner's instruction).
    The complex conjugate's overline is a different operation and stays. The same pass fixed a silent
    rendering defect on the validation page: one passage carried doubled backslashes, pasted from a
    Julia string, so its math rendered as raw source.
103. **(2026-09-29, user-directed) The energy in the forced band is ``k_{\mathrm{band}}``.** It had two
    symbols: ``k_f`` in `VarianceController`'s docstring and ``E_{\mathrm{band}}`` in `ConstantPower`'s and on the
    validation page. Neither was sound: ``k_f`` is the literature's forcing wavenumber and its ``f``
    names the force, and ``E`` is the spectral density ``E(\kappa)``, not an energy. ``k_{\mathrm{band}}`` reads as
    the kinetic energy ``k`` restricted to the band, matches the code's `band` kernels and
    `band_energy_fraction`, and makes the fraction ``k_{\mathrm{band}}/k``. It has a glossary row, and the
    docstrings, comments, validation page and tests use it. Earlier log entries keep ``k_f`` as history.
104. **(2026-09-29, user-directed) The two Reynolds numbers as plain functions of three scalars.**
    `reynolds_box(side_length, dissipation, viscosity)` gives ``\varepsilon^{1/3}L^{4/3}/\nu`` and
    `reynolds_taylor(kinetic_energy, dissipation, viscosity)` gives ``\sqrt{20/3} k/\sqrt{\varepsilon\nu}``.
    **Why scalars, not a run or a field:** the owner's ruling. A study reduces a run to time means first,
    and the Reynolds number belongs to those means, not to an instantaneous state. The functions give
    that study the package's one definition, so no script carries its own copy. They live in
    `Observables` beside the reductions whose results they take. **Argument order, the owner's rule:**
    large scale first, then small — the energy-containing quantity (``L`` or ``k``), then the cascade
    rate ``\varepsilon``, then ``\nu``. **Positional, not keywords**, like every other observable. The same names serve as the keywords of
    the ``\tilde{k}`` model to come, as `kinetic_energy` is both a keyword and an observable.
105. **(2026-09-29, user-directed) The stationary-state model, and the run predicting from it.**
    `kinetic_energy_in_box_units(forcing; reynolds_box | reynolds_taylor)` and
    `band_energy_fraction(...)`, in `Forcing`, give ``\tilde{k}`` and ``k_{\mathrm{band}}/k`` for a forcing's
    strategy, band and `over`; exactly one Reynolds keyword, and the Taylor form is solved for
    ``\mathrm{Re}_{\mathrm{box}}`` by bisection. **Placeholders:** ``\tilde{k}`` flat in ``\mathrm{Re}`` (the keyword
    is checked and changes nothing until the dependence is measured) and the same for every strategy:
    0.72, 0.56 and 0.47 for shells 1–2, 1–4 and every mode, linear in ``1/h`` between; ``k_{\mathrm{band}}/k``
    the inertial-tail estimate, 1 for every mode. A band from shell 1 ending at shell 2 or above is
    covered. **The prediction** is one public function, `predicted_stationary_state`, which
    `Simulation` calls. A derived ν needs no fixed point: ``\kappa_{\max}\eta`` fixes ``\eta``, so
    ``\mathrm{Re}_{\mathrm{box}} = (L/\eta)^{4/3}``, then ``\tilde{k}``, then the unstated member, then
    ``\nu = \varepsilon^{1/3}\eta^{4/3}``. With a given ν and a stated ``k``, ``\varepsilon`` is solved by bisection.
    **Fills** (owner's rulings): `Linear`'s rate becomes optional, ``A = \varepsilon/(2k_{\mathrm{band}})``;
    `VarianceRescaling(over = :band)`'s target becomes optional, ``k_{\mathrm{band}}``, its fraction
    taken to be the one `over = :total` holds on the same band (a modelling assumption, testable by one
    run); the controller's omitted settling time is the predicted ``2k/(3\varepsilon)``; the deferred
    `StochasticOU` states `correlation_time_in_box_units`, converted once to ``T_L``. **Uncovered runs**
    (owner's rulings): a derived ν for an unforced run or an uncovered band is an `ArgumentError`
    (the unforced case was a warning); with a given ν nothing is predicted, the seed takes the stated
    ``k``, an unforced run may state both ``k`` and ``\varepsilon``, a `Phenomenology` initial spectrum
    without ``\varepsilon`` is refused, and the scalar-resolution check measures the seeded field's ``\varepsilon``.
    The single constant 0.7 and its two estimate functions are gone. The run layer's expected
    ``\mathrm{Re}_\lambda`` now comes from `reynolds_taylor`, not `Phenomenology`.
106. **(2026-10-01, user-directed) A steady linear rate is returned, not filled, and is a symbol.**
    The rate hook was `set_forcing_rate!(forcing, rate, field, domain)`: the generator allocated a
    scalar field in spectral representation, the hook filled it, and the declaration
    `uses_steady_linear_rate` gated both. So `Linear`'s rate, ``A`` on the band and zero elsewhere, was
    resident for the whole run — about 129 MiB at ``256^3`` / `Float64` per forced field — though it
    is a function of ``\lvert\boldsymbol{\kappa}\rvert^{2}`` alone, whose floor the optimality audit had
    shown to be zero. Steadiness was checked by filling it from two probe states, about 4 ``N^3``
    reals at construction.

    PF's decision 92, raised by HT the same day, lets `exponential_convolve!` take its offset as a
    radial kernel, bitwise identical to the stored form and measured 13–15% faster. The hook is now
    `steady_linear_rate(forcing, domain)`, returning a radial kernel, a stored field for a rate that
    is not radial, or `nothing`. Handed no field, a rate is steady by construction, so the probe is
    gone; and since a rate is present exactly when the hook returns one, the declaration is gone too.
    `Linear`'s symbol takes the band's edges from the one helper `_shell_edges` and equals the old
    stored rate value for value.

107. **(2026-10-01, user-directed) A seed determines the realization, whatever the backend.** A run
    on the CPU and one on a GPU, given the same seed, draw the same random numbers: the initial
    velocity and scalar fields, the tracers' initial positions, and `StochasticOU`'s forcing. Decision
    90 stated this for the forcing alone; the other two followed it only by comment. HT gets the
    property by drawing every random number on the host, from the `rng` the caller passes, and moving
    the numbers to the run's backend. No device generator is used.

    The mechanism fits HT's draw sizes: the initial fields once (3 or 4 ``N^3`` numbers), the
    positions once (``M \times 3``), and the forced band's few hundred modes per step. A package that
    draws per element at every step would want a counter-based generator instead, which gives the
    same stream on host and device; the property, not the mechanism, is what is fixed. It is checked
    by the memory plan's GPU leg, where a CPU and a GPU run with one seed must agree.

108. **(2026-10-01, user-directed) Two temporaries are kept, rather than built component by
    component.** `derivative_skewness` holds the full strain tensor while it reduces
    ``\langle\det\boldsymbol{S}\rangle`` (about 18 ``N^3`` reals per call), and seeding holds a full
    physical noise vector before transforming it (about 3, once per construction). Each could shrink
    by forming and transforming one component at a time inside HT, but that assembles a field outside
    PF's whole-field operations, against the division the package rests on: field mathematics is PF's.
    The owner ruled both stay. Both are occasional — the skewness gate is off by default — and the
    memory audit lists them as adopted costs, not open wins.

109. **(2026-10-02, user-directed) Transform planning's temporary is accepted as its floor.** Building
    a `FixedDomain` allocates about 3 ``N^3`` reals it does not keep, all of it planning: two
    one-component arrays PF's planner hands FFTW, and one inside FFTW.jl's inverse planner. PF ruled
    it what planning needs and beyond its reach (its decision 93). HT builds no template field of its
    own since PF decisions 93 and 94 (11.2 ``N^3`` reals on 2026-10-01). The cost is paid once per
    construction, and a plan cannot be made without arrays to plan on.

## References

Works are cited author–year above and given in full here, each with its DOI where the work has one. Four do not,
and the reason is stated with the entry rather than left to the reader to wonder about: two NASA
technical memoranda, a CTR research brief and a 1932 monograph sit outside the DOI system. A DOI here has been resolved against the registry, never recalled — an unverified identifier
is worse than none, since it silently sends the reader somewhere else.

The extraction-bound `Phenomenology` leaf (§4.8) is exempt: each reference law carries its own
self-contained citation in a `Reference` value, so this list need not duplicate the ~two dozen it
cites.

- Betchov, R. (1956). [*An inequality concerning the production of vorticity in isotropic turbulence*](https://doi.org/10.1017/S0022112056000317).
  *J. Fluid Mech.* **1**(5), 497–504. *(The isotropy
  relations behind the strain-skewness constant, §4.3.)*
- Patterson, G. S. & Orszag, S. A. (1971). [*Spectral calculations of isotropic turbulence: efficient removal of aliasing interactions*](https://doi.org/10.1063/1.1693365). *Phys. Fluids* **14**, 2538–2541. *(Phase-shift dealiasing; the
  `PhaseShift` strategy, §7, decision 27.)*
- Orszag, S. A. (1971). [*On the elimination of aliasing in finite-difference schemes by filtering high-wavenumber components*](https://doi.org/10.1175/1520-0469%281971%29028%3C1074:OTEOAI%3E2.0.CO;2). *J. Atmos. Sci.* **28**, 1074. *(The ``2/3`` truncation rule.)*
- Orszag, S. A. & Patterson, G. S. (1972). [*Numerical simulation of three-dimensional homogeneous isotropic turbulence*](https://doi.org/10.1103/PhysRevLett.28.76). *Phys. Rev. Lett.* **28**, 76–79. *(The pseudospectral method.)*
- Rogallo, R. S. (1981). [*Numerical experiments in homogeneous turbulence.*](https://ntrs.nasa.gov/citations/19810022965) NASA TM-81315. *(No DOI;
  a NASA technical memorandum. The sheared-frame scheme, §7; the spherical-truncation dealiasing of
  the `PhaseShift` strategy, decision 27.)*
- Hou, T. Y. & Li, R. (2007). [*Computing nearly singular solutions using pseudo-spectral methods*](https://doi.org/10.1016/j.jcp.2007.04.014).
  *J. Comput. Phys.* **226**, 379–397. *(The smooth spectral filter; the `HouLi` dealiasing strategy.)*
- Cichowlas, C., Bonaïti, P., Debbasch, F. & Brachet, M. (2005). [*Effective dissipation and turbulence in spectrally truncated Euler flows*](https://doi.org/10.1103/PhysRevLett.95.264502). *Phys. Rev. Lett.* **95**, 264502. *(Thermalization of the
  Galerkin-truncated conservative system; the ``\nu = 0`` oracle, §7.)*
- Chollet, J.-P. & Lesieur, M. (1981). [*Parameterization of small scales of three-dimensional isotropic turbulence utilizing spectral closures*](https://doi.org/10.1175/1520-0469%281981%29038%3C2747:POSSOT%3E2.0.CO;2). *J. Atmos. Sci.* **38**, 2747–2757. *(The spectral eddy
  viscosity ``\nu_e(\kappa \mid \kappa_c)``; the deferred spectral large-eddy rung, §7.)*
- Eswaran, V. & Pope, S. B. (1988). [*An examination of forcing in direct numerical simulations of turbulence*](https://doi.org/10.1016/0045-7930%2888%2990013-8). *Computers & Fluids* **16**, 257–278. *(The stochastic Ornstein–Uhlenbeck forcing.)*
- Lundgren, T. S. (2003). [*Linearly forced isotropic turbulence.*](https://web.stanford.edu/group/ctr/ResBriefs03/lundgren.pdf) *CTR Annual Research Briefs*, 461–473. *(No DOI; a Center for Turbulence Research brief.)*
  *(The linear negative-damping forcing.)*
- Lalescu, C. C., Teaca, B. & Carati, D. (2010). [*Implementation of high order spline interpolations for tracking test particles in discretized fields*](https://doi.org/10.1016/j.jcp.2010.04.006). *J. Comput. Phys.* **229**(17), 5862–5869.
  *(The interpolation family `LalescuSpline` implements,
  and the source for choosing interpolation order in particle tracking — decision 57's floor.)*
- Lalescu, C. C., Bramas, B., Rampp, M. & Wilczek, M. (2022). [*An efficient particle tracking algorithm for large-scale parallel pseudo-spectral simulations of turbulence*](https://doi.org/10.1016/j.cpc.2022.108406). *Comput. Phys.
  Commun.* **278**, 108406. *(TurTLE; the
  Adams–Bashforth tracer integration `AdamsBashforth` follows, decision 57.)*
- Sullivan, N. P., Mahalingam, S. & Kerr, R. M. (1994). [*Deterministic forcing of homogeneous, isotropic turbulence*](https://doi.org/10.1063/1.868274). *Phys. Fluids* **6**(4), 1612–1614.
  *(`VarianceRescaling`: the per-step rescaling of the low-``\kappa``
  modes to a fixed band energy. Kept as the reference implementation, with its first-order
  operator-splitting caveat documented rather than hidden.)*
- Nosé, S. (1984). [*A unified formulation of the constant temperature molecular dynamics methods*](https://doi.org/10.1063/1.447334).
  *J. Chem. Phys.* **81**(1), 511–519. *(the thermostat analogy
  `VarianceController` cites: feedback inside the equations rather than per-step rescaling.)*
- Hoover, W. G. (1985). [*Canonical dynamics: Equilibrium phase-space distributions*](https://doi.org/10.1103/PhysRevA.31.1695). *Phys. Rev. A*
  **31**(3), 1695–1697. *(the companion half of the
  Nosé–Hoover move.)*
- Bassenne, M., Urzay, J., Park, G. I. & Moin, P. (2016). [*Constant-energetics physical-space forcing methods for improved convergence to homogeneous-isotropic turbulence with application to particle-laden flows*](https://doi.org/10.1063/1.4944629). *Phys. Fluids* **28**, 035114.
  *(`VarianceController`: the constant-``k`` controller of their Eq. 20, the marginal law
  ``A = \varepsilon/2k_{\mathrm{band}}`` plus a proportional restoring term measuring the whole-field ``k``, giving exponential relaxation to a stable
  attractor. The smooth, gain-limited replacement for the discontinuous projection above.)*
- Berendsen, H. J. C., Postma, J. P. M., van Gunsteren, W. F., DiNola, A. & Haak, J. R. (1984).
  [*Molecular dynamics with coupling to an external bath*](https://doi.org/10.1063/1.448118). *J. Chem. Phys.* **81**, 3684–3690.
  *(The thermostat whose deterministic-rescaling limit
  `VarianceRescaling` is; named there and now cited.)*
- Bussi, G., Donadio, D. & Parrinello, M. (2007). [*Canonical sampling through velocity rescaling*](https://doi.org/10.1063/1.2408420).
  *J. Chem. Phys.* **126**, 014101. *(Stochastic velocity rescaling; its deterministic limit is the
  Berendsen thermostat — no conserved quantity, no well-defined ensemble except in limiting cases —
  the caveat `VarianceRescaling` carries.)*
- Williamson, J. H. (1980). [*Low-storage Runge–Kutta schemes*](https://doi.org/10.1016/0021-9991%2880%2990033-9). *J. Comput. Phys.* **35**, 48–56. *(The
  2N low-storage family; the package's third-order coefficients are the low-storage set later adopted for spectral DNS and
  popularly named "RKW3"; it is also attributed to an unpublished 1986 note of Wray's, so this entry
  cites the family rather than a numbered case.)*
- Carpenter, M. H. & Kennedy, C. A. (1994). [*Fourth-order 2N-storage Runge–Kutta schemes.*](https://ntrs.nasa.gov/citations/19940028444) NASA TM-109112. *(No DOI;
  a NASA technical memorandum. The five-stage, two-register fourth-order scheme `IFLowStorageRK4`
  implements.)*
- Shu, C.-W. & Osher, S. (1988). [*Efficient implementation of essentially non-oscillatory shock-capturing schemes*](https://doi.org/10.1016/0021-9991%2888%2990177-5). *J. Comput. Phys.* **77**, 439–471. *(The SSPRK3 tableau
  `IFSSPRK3` implements, in TurTLE's stage arrangement.)*
- Pope, S. B. (2000). [*Turbulent Flows.*](https://doi.org/10.1017/CBO9780511840531) Cambridge University Press. *(Notation; the
  filtered-density-function Model and mixing models, §7–§8.)*
- Mori, H. (1965). [*Transport, collective motion, and Brownian motion*](https://doi.org/10.1143/PTP.33.423). *Prog. Theor. Phys.* **33**,
  423–455. *(The projection formalism, the foundation of §3 and §8.)*
- Zwanzig, R. (1973). [*Nonlinear generalized Langevin equations*](https://doi.org/10.1007/BF01008729). *J. Stat. Phys.* **9**, 215–220. *(The projection formalism, with Mori 1965.)*
- Morrison, P. J. (1986). [*A paradigm for joined Hamiltonian and dissipative systems*](https://doi.org/10.1016/0167-2789%2886%2990209-5). *Physica D* **18**,
  410–419. *(The metriplectic bracket formulation; the reversible/irreversible split, §4.2, §8.)*
- Öttinger, H. C. (2005). [*Beyond Equilibrium Thermodynamics.*](https://doi.org/10.1002/0471727903) Wiley. *(GENERIC; the
  reversible/irreversible split, §8.)*
- Lamb, H. (1932). [*Hydrodynamics*](https://openlibrary.org/books/OL6287619M/Hydrodynamics), 6th ed. Cambridge University Press. *(No DOI; a 1932 monograph.
  Art. 146, Eq. (5): the rotational form of the equations of motion, decision 93.)*
- Hamman, C. W., Klewicki, J. C. & Kirby, R. M. (2008). [*On the Lamb vector divergence in Navier–Stokes flows*](https://doi.org/10.1017/S0022112008002760).
  *J. Fluid Mech.* **610**, 261–284. *(The Lamb vector defined as ω × u, p. 265; decision 93.)*
- Sagaut, P. & Cambon, C. (2018). [*Homogeneous Turbulence Dynamics*](https://doi.org/10.1007/978-3-319-73162-9), 2nd ed.
  Springer. *(The package's scope, decision 91; the Lamb vector named ω × u, p. 586, decision 93.)*
