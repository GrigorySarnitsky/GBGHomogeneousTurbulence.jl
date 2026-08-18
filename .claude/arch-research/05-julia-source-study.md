# Julia source study — Oceananigans, SpeedyWeather, Trixi

Beat: how three production Julia PDE codes structure the generator/propagator seam (P1), the
sanctioned-mutation / stale-cache contract (P2), a memoized derived-field layer (P3), scratch
ownership (P4), and the state-record doctrine (P5). All evidence is quoted from the study-only clones
under `inspiration/arch/…` with file paths and line numbers; nothing is copied into the package.

Clone versions consulted (from each `Project.toml`, read 2026-07-18):
- **Oceananigans.jl `0.110.11`**
- **Trixi.jl `0.16.27-DEV`**
- **SpeedyWeather.jl (`SpeedyWeather` subpackage) `0.21.1+DEV`**

A note on the SpeedyWeather seeded lead: the *published/stable* docs still describe a two-record
`PrognosticVariables` / `DiagnosticVariables` split (confirmed via JuliaHub stable docs — see Sources).
The **clone at `0.21.1+DEV` has already superseded that** with a single unified `Variables` struct of
seven groups; `prognostic` is the one state record and the other six groups are jointly "diagnostic".
The two-record *principle* survives verbatim; only the container shape generalized. I document the
clone (the newer, primary evidence) and flag the divergence from the published lead explicitly.

---

## 1. Oceananigans.jl — `FieldStatus` time-stamp memoization + `update_state!` as the one mutation gate

### 1a. P3 — `FieldStatus`: a single-time-stamp memoized derived field (the closest production analog of DerivedFields)

A `ComputedField` (a `Field` whose `operand` is an `AbstractOperation`) carries an optional
`status` slot that memoizes the last compute *time*:

`inspiration/arch/Oceananigans.jl/src/Fields/field.jl:494`
```
# Computation "status" for avoiding unnecessary recomputation
mutable struct FieldStatus{T}
    time :: T
end
FieldStatus() = FieldStatus(0.0)
```

The gate is `compute_at!`, which skips recomputation when the requested time equals the stamped time:

`inspiration/arch/Oceananigans.jl/src/AbstractOperations/computed_field.jl:522` (docstring) and `field.jl:527`
```
"""Computes `field.data` if `time != field.status.time`."""
function compute_at!(field::Field, time)
    if !(field.status isa FieldStatus) # then always compute:
        compute!(field, time)
    # Otherwise, compute only on initialization or if field.status.time is not current,
    elseif time == zero(time) || time != field.status.time
        compute!(field, time)
    end
    return field
end
```

`compute!` writes the result, fills halos, then stamps the status:

`computed_field.jl:80`
```
function compute!(comp::ComputedField, time=nothing)
    compute_at!(comp.operand, time)          # first recompute dependencies
    @apply_regionally compute_computed_field!(comp)
    fill_halo_regions!(comp)
    set_status!(comp.status, time)           # update status
    return comp
end
```

**Mechanism, mapped to P3.** This is exactly IT's "stamped, memoized cache … repeated reads at the same
simulation time skip recomputation." Two design details are directly transferable:

1. **The stamp is a single scalar time, not a per-dynamical-factor epoch vector.** Oceananigans keys
   validity on `model.clock.time`. That is coarser than IT's proposed per-factor epoch counters (fields
   vs particles); it works for Oceananigans because every derived field depends on the *same* clock and
   the whole model advances in lockstep. IT's finer epoching (a chart valid against the field epoch but
   not the particle epoch) has no analog here — Oceananigans would recompute both or neither.

2. **A safety fallback when the buffer is user-owned.** If you hand a `ComputedField` its own `data`
   buffer, the constructor sets `recompute_safely = false` → allocates a `FieldStatus` → memoization is
   ON. If `data` is *not* provided (nested inside another operation) it sets `status = nothing` →
   `compute_at!` always recomputes. Rationale in the docstring, `computed_field.jl:33`:
   ```
   `recompute_safely` (`Bool`): Whether or not to _always_ "recompute" `f` if `f` is
        nested within another computation … If `data` is not provided then
        `recompute_safely = false` and recomputation is _avoided_. If `data` is provided,
        then `recompute_safely = true` by default.
   ```
   The lesson for IT: **memoization is opt-in and defaults to "recompute" precisely where staleness is
   hard to prove** — the conservative default is the *un*-cached one. IT's DerivedFields ("absent slot is
   an error; resident GPU memory is opt-in") shares this instinct.

### 1b. P2 — `update_state!` is the single sanctioned place derived state is refreshed after a prognostic mutation

The RK3 time loop calls `update_state!` after *every* substep mutation, never inline:

`inspiration/arch/Oceananigans.jl/src/TimeSteppers/runge_kutta_3.jl:128`
```
rk3_substep!(model, Δt, γ¹, nothing, callbacks)
cache_previous_tendencies!(model)
tick_stage!(model.clock, first_stage_Δt)
step_closure_prognostics!(model, first_stage_Δt)
update_state!(model, callbacks)
step_lagrangian_particles!(model, first_stage_Δt)
```
(and identically after the second and third substeps).

`update_state!` is the canonical re-derivation: mask, refresh forcings, fill halos, recompute auxiliary
fields, recompute closure/pressure, then compute tendencies:

`inspiration/arch/Oceananigans.jl/src/Models/NonhydrostaticModels/update_nonhydrostatic_model_state.jl:22`
```
function update_state!(model::NonhydrostaticModel, callbacks=[])
    mask_immersed_field!(model.tracers)
    update_model_field_time_series!(model, model.clock)
    compute_forcing!(model.forcing)                       # refresh lazy/transformed forcings
    update_boundary_conditions!(fields(model), model)
    fill_halo_regions!(merge(model.velocities, model.tracers), …)
    for aux_field in model.auxiliary_fields; compute!(aux_field); end
    compute_auxiliaries!(model)                           # closure fields + hydrostatic pressure
    …
    compute_tendencies!(model, callbacks)
    return nothing
end
```

Crucially, **the same gate fires after a user `set!`** — so a hand-edited field can never be read stale:

`inspiration/arch/Oceananigans.jl/src/Models/NonhydrostaticModels/set_nonhydrostatic_model.jl:62`
```
velocities_are_set && initialize_closure_fields!(…)
update_state!(model)
if enforce_incompressibility
    compute_pressure_correction!(model, one(FT))
    make_pressure_correction!(model, one(FT))
    …
    update_state!(model)
end
```

**Mapped to P2.** IT's P2 footgun is "`step!` reads caller-prefilled physical-velocity/vorticity caches;
forgetting the refill silently produces a wrong step." Oceananigans structurally defuses this by making
**refill a callee responsibility invoked at exactly two callsites** (each substep of the stepper, and
`set!`), not a caller precondition. This is a *third* option beyond IT's two framings: rather than
"demand-driven accessors that recompute on staleness" (IT's proposal) or "comment-enforced caller
prefill" (IT's status quo), Oceananigans uses **an eager, ordered, once-per-mutation refresh with a
fixed callsite**. It is the same discipline SpeedyWeather uses (§2). The tradeoff: eager refresh always
pays for every derived field whether or not a reader wants it; demand-driven accessors pay only on read.
IT's GPU-footprint priority may favor the demand-driven side, but the *single-callsite* idea — one
function that owns all re-derivation — is transferable regardless.

### 1c. P4 — the RK3 tendency registers live *in the timestepper struct*, nowhere else

`inspiration/arch/Oceananigans.jl/src/TimeSteppers/runge_kutta_3.jl:15`
```
struct RungeKutta3TimeStepper{FT, TG, TI} <: AbstractTimeStepper
    γ¹ :: FT; γ² :: FT; γ³ :: FT; ζ² :: FT; ζ³ :: FT
    Gⁿ :: TG          # current-stage tendencies
    G⁻ :: TG          # previous-stage tendencies
    implicit_solver :: TI
end
```
The registers are allocated by the stepper's own constructor, one per prognostic field:
`Gⁿ = map(similar, prognostic_fields)` (`runge_kutta_3.jl:63`). The model struct keeps these in a
dedicated `timestepper` slot, disjoint from `velocities`, `tracers`, `pressures`, `closure_fields`,
`pressure_solver`, `auxiliary_fields`, `forcing`:

`inspiration/arch/Oceananigans.jl/src/Models/NonhydrostaticModels/nonhydrostatic_model.jl:48`
```
       velocities :: U        # velocity fields
          tracers :: C        # tracer fields
        pressures :: Φ        # hydrostatic + nonhydrostatic pressure
   closure_fields :: K        # closure auxiliary fields
      timestepper :: TS       # timestepper fields and parameters
  pressure_solver :: S        # Pressure/Poisson solver
 auxiliary_fields :: AF       # user auxiliary fields for forcing & BCs
```

**Mapped to P4.** This is precisely IT's target end-state: "only the RK stage registers stay with the
integrator; the pressure solver homes its own scratch." Oceananigans already partitions scratch by
owner — stage registers in `timestepper`, Poisson scratch in `pressure_solver`, closure scratch in
`closure_fields`. No component reaches into another's named slots.

### 1d. P4 — forcings are self-contained callables that own their parameters/scratch

A `ContinuousForcing` bundles its own `func`, `parameters`, and declared `field_dependencies`:

`inspiration/arch/Oceananigans.jl/src/Forcings/continuous_forcing.jl:12`
```
struct ContinuousForcing{LX, LY, LZ, P, F, D, I, ℑ}
    func :: F
    parameters :: P
    field_dependencies :: D
    …
end
```
It enters the tendency as a pure additive source evaluated pointwise inside the kernel:

`inspiration/arch/Oceananigans.jl/src/Models/NonhydrostaticModels/nonhydrostatic_tendency_kernel_functions.jl:104`
```
… + forcing(i, j, k, grid, clock, model_fields)
```

**Mapped to P4 and the forcing-hook lifecycle (P1/P4 boundary).** The forcing never receives the
integrator's buffer bundle; it receives read-only `(grid, clock, model_fields)` and carries its own
mutable state. This is the exact discipline IT's P4 proposes ("forcings own their scratch"). It also maps
to IT's `add_forcing_source!` hook — a per-stage additive term. Oceananigans has no analog of IT's
`set_forcing_rate!` (folding a linear rate into the integrating factor) because it uses no integrating
factor; its viscous term is an ordinary tendency contribution, not an exponential multiplier.

### 1e. Observation cadence (context for P3 readers) — schedules are first-class objects

`inspiration/arch/Oceananigans.jl/src/Utils/schedules.jl:32`
```
mutable struct TimeInterval{IT, TT} <: AbstractSchedule
    interval :: IT
    first_actuation_time :: TT
    actuations :: Int
end
```
`IterationInterval` (`schedules.jl:136`) and `WallTimeInterval` (`schedules.jl:166`) are siblings.
A `Callback` pairs a schedule with a function; the callback is called `(model)` when
`schedule(model)` returns true (`schedules.jl:81`). This is the sanctioned observation layer — readers
(diagnostics, output writers) hook in through a schedule, and inside `update_state!` those with
`callback.callsite isa UpdateStateCallsite` fire at the derived-state-fresh point
(`update_nonhydrostatic_model_state.jl:53`). For IT's P3, the takeaway is that **the observation
callsite is bound to the freshness point**: readers run right after `update_state!` has re-derived
everything, so they never see a half-updated cache.

---

## 2. SpeedyWeather.jl — the unified `Variables` record and the *ordering* (not stamping) validity contract

### 2a. P5 / P3 — one `Variables` struct; `prognostic` is the state record, six groups are diagnostic

`inspiration/arch/SpeedyWeather.jl/SpeedyWeather/src/variables/variables.jl:64`
```
"""… All non-prognostic groups are considered to be diagnostic with no memory
between time steps."""
@kwdef struct Variables{Po, G, T, D, Pm, Pt, S, F} <: AbstractVariables
    prognostic::Po = NamedTuple()          # subject to time stepping (the restart record)
    grid::G = NamedTuple()                  # grid-point copies of spectral prognostics
    tendencies::T = NamedTuple()            # time derivatives
    dynamics::D = NamedTuple()              # dynamical-core working arrays
    parameterizations::Pm = NamedTuple()    # physics working arrays
    particles::Pt = NamedTuple()            # particle advection
    scratch::S = NamedTuple()               # write-before-read temporaries
    fused::F = NamedTuple()                 # contiguous parents for batched transforms
end
```

**Mapped to P5 (state doctrine).** The litmus IT proposes — "what the flow map needs" — is expressed here
as the single boolean split between `prognostic` and everything else. The docstring line *"no memory
between time steps"* **is** IT's cache-vs-restart litmus, made a documented invariant. Corroborated by the
clone's own CLAUDE.md: "`prognostic` — State variables subject to time stepping … `grid` — grid-point
copies of spectral prognostic variables … `scratch` — Temporary storage (write-before-read)."

`copy!` on `Variables` **skips `scratch` entirely** because it never needs to survive a sync — a direct
encoding of "scratch is not state":

`variables.jl:119`
```
function Base.copy!(dest::Variables, src::Variables)
    for group in propertynames(dest)
        group === :scratch && continue     # write-before-read; never needs to survive a sync
        copy_variables!(getfield(dest, group), getfield(src, group))
    end
end
```

### 2b. P5 — a stochastic forcing's Markov state IS a prognostic variable (the "Markovian surrogate slot")

The AR(1) random process registers its pattern as a **`PrognosticVariable`** (carried between steps, part
of the restart record) and its grid copy as a **`GridVariable`** (diagnostic):

`inspiration/arch/SpeedyWeather.jl/SpeedyWeather/src/dynamics/random_process.jl:73`
```
function variables(::SpectralAR1Process)
    return (
        PrognosticVariable(:random_pattern, Spectral2D(), desc = "Random pattern …"),
        GridVariable(:random_pattern, Grid2D(),  desc = "Random pattern …"),
    )
end
```
The process is genuinely Markovian — one autoregressive factor precomputed from the time step:

`random_process.jl:84`
```
process.autoregressive_factor[] = exp(-dt / Second(process.time_scale).value)
```

**Mapped to P5.** This is a precise, shipped instance of IT's P5 clause "a stochastic forcing's internal
state as a Markovian surrogate slot." SpeedyWeather's decision: **the surrogate slot lives in the
prognostic (restart) record, not in a cache** — because the AR(1) state is exactly what the (extended)
flow map needs to reproduce the trajectory. IT should follow this: an OU/AR forcing's internal state
belongs in the restart record next to the fields, not in DerivedFields. The "skew-product tower
(time → OU noise → fields → particles)" IT describes is *literally* how SpeedyWeather lays it out —
`random_pattern` (noise) and the fields both prognostic, particles a separate group.

### 2c. P4 / P3 — components declare their own variables; the constructor merges and allocates once

Every model component implements `variables(component)` returning typed variable declarations; the
`Variables(model)` constructor collects the union and allocates each group exactly once:

`inspiration/arch/SpeedyWeather.jl/SpeedyWeather/src/variables/variables.jl:237`
```
function Variables(model::AbstractModel)
    all_vars = all_variables(model)   # one long tuple of every required variable of model + components
    fuse_parents = build_fuse_parents(all_vars, model)
    prognostic        = allocate(filter_variables(all_vars, PrognosticVariable),        model, fuse_parents)
    grid              = allocate(filter_variables(all_vars, GridVariable),              model, fuse_parents)
    tendencies        = allocate(filter_variables(all_vars, TendencyVariable),          model, fuse_parents)
    dynamics          = allocate(filter_variables(all_vars, DynamicsVariable),          model, fuse_parents)
    parameterizations = allocate(filter_variables(all_vars, ParameterizationVariable),  model, fuse_parents)
    particles         = allocate(filter_variables(all_vars, ParticleVariable),          model, fuse_parents)
    scratch           = allocate(filter_variables(all_vars, ScratchVariable),           model, fuse_parents)
    …
end
```

**Mapped to P3 and P4.** This is *exactly* IT's proposed P3 mechanism: "each component declares the charts
it needs; the merged set is allocated once." SpeedyWeather demonstrates the pattern at production scale —
a component (a forcing, a parameterization, a random process) declares typed slots (`PrognosticVariable`,
`GridVariable`, `DynamicsVariable`, `ScratchVariable`, …), and the container constructor filters by type
and allocates. It also settles P4: a component's working arrays are declared as `DynamicsVariable` /
`ParameterizationVariable` / `ScratchVariable` and merged into the shared, once-allocated pool — no
component reaches into the integrator's or another component's private buffers. The `fused` group is a
GPU-footprint optimization worth noting for IT's GPU-primary target: variables sharing a `fuse` symbol
share one contiguous parent buffer so transforms can be batched (`variables.jl:90`, `:234`).

### 2d. P2 / P3 — the validity contract is an ORDERING contract, recomputed every step; there is no staleness stamp

The single time step recomputes the diagnostic grid variables unconditionally via `transform!` at a
fixed position in the loop — there is no per-field validity flag:

`inspiration/arch/SpeedyWeather.jl/SpeedyWeather/src/time_stepping/time_integration.jl:68`
```
function time_step!(vars, time_stepping, model::PrimitiveEquation)
    reset_tendencies!(vars, time_stepping)          # zero for accumulation
    … parameterization_tendencies!(vars, model) …
    dynamics_tendencies!(vars, model)               # dynamical core → tendencies
    diffusion_and_implicit!(vars, model)
    update_prognostic!(vars, model)                 # the actual time step (spectral)
    transform!(vars, model)                         # spectral prognostics → grid diagnostics
    particle_advection!(vars, model)
end
```
`transform!` writes `vars.grid.*` from `vars.prognostic.*` every step, unconditionally:

`inspiration/arch/SpeedyWeather.jl/SpeedyWeather/src/time_stepping/transform.jl:20`
```
vor_grid = get_prognostic_step(vars.grid.vorticity, time_stepping, S, model)
vor      = get_prognostic_step(vars.prognostic.vorticity, time_stepping, S)
…
transform!(vor_grid, vor, scratch_memory, S)        # grid vorticity from spectral
```

**Mapped honestly against IT's epoch design (P3).** This is the sharpest contrast in the beat.
SpeedyWeather's contract is **positional/ordering**: "the grid variables are valid *after* `transform!`
has run at the end of the step, which is precisely when the next step's tendency calculation reads them."
No stamp, no epoch counter, no staleness check — the loop structure *is* the guarantee. The docstring
codifies it: diagnostics have "no memory between time steps." IT's proposed epoch-counter design is
**strictly more machinery** than SpeedyWeather (and Oceananigans, §1a) use. That extra machinery buys IT
two things SpeedyWeather deliberately forgoes:
- **Producer-deposit + accessor-recompute duality** — a reader outside the loop (a diagnostic callback, a
  particle push at a sub-step) can *ask* for a derived field and get a correct recompute-on-staleness,
  whereas SpeedyWeather readers must run at the one blessed position. If IT genuinely needs
  observation at arbitrary points in the sub-step schedule (it does — particle pushers read mid-stage
  velocity), the ordering contract alone is insufficient and the epoch stamp earns its keep.
- **Fine-grained epochs** — SpeedyWeather recomputes *all* grid diagnostics every step; it cannot skip an
  unchanged one. IT's per-dynamical-factor epochs let a reader skip a chart that its factor did not touch.

The risk direction for IT: epoch counters are a correctness surface of their own (an off-by-one epoch is a
silent-staleness bug of exactly the class P2 is trying to kill). SpeedyWeather's ordering contract has no
such surface — it is impossible to read a stale grid variable because there is only one place they are
read and it is after the one place they are written. **Recommendation for IT: keep the epoch design only
where out-of-loop / mid-stage observation actually requires it, and fall back to SpeedyWeather's ordering
contract for everything read exclusively inside `step!`.**

---

## 3. Trixi.jl — the reified generator (`semi` + `cache`), the delegated propagator, and native low-storage integrators

### 3a. P1 — `SemidiscretizationHyperbolic` reifies the RHS; `rhs!(du, u, semi, t)` is the hard protocol

The generator is a struct bundling geometry, physics, method, and scratch:

`inspiration/arch/Trixi.jl/src/semidiscretization/semidiscretization_hyperbolic.jl:14`
```
mutable struct SemidiscretizationHyperbolic{Mesh, Equations, InitialCondition, …}
    mesh::Mesh
    equations::Equations
    const initial_condition::InitialCondition
    const boundary_conditions::BoundaryConditions
    const source_terms::SourceTerms
    const solver::Solver
    cache::Cache
    …
end
```

The RHS is a single protocol function; the reified generator is passed as the ODE parameter `p`:

`semidiscretization_hyperbolic.jl:578`
```
function rhs!(du_ode, u_ode, semi::SemidiscretizationHyperbolic, t)
    @unpack mesh, equations, boundary_conditions, source_terms, solver, cache = semi
    u  = wrap_array(u_ode, mesh, equations, solver, cache)
    du = wrap_array(du_ode, mesh, equations, solver, cache)
    …
    rhs!(du, u, t, mesh, equations, boundary_conditions, source_terms, solver, cache)
    …
end
```

The design rationale is stated in the docs — method-of-lines, spatial semidiscretization *separated*
from time integration:

`inspiration/arch/Trixi.jl/docs/src/overview.md:11`
```
Trixi.jl uses the method of lines, i.e., the full space-time discretization is separated into two steps;
the spatial semidiscretization is performed at first and the resulting ODE system is solved numerically …
```
`overview.md:37`
```
When a semidiscretization is constructed, it will create an internal `cache`, i.e., a collection of
setup-specific data structures, that is usually passed to all lower level functions.
```

**Mapped to P1.** This is the strongest external validation of IT's P1 proposal ("reify the RHS as a
ResolvedGenerator object … so schemes do only stage arithmetic"). Trixi's `semi` *is* the
ResolvedGenerator: a parameter record (mesh/equations/solver) + assembly scratch (`cache`) + a protocol
(`rhs!`). The time steppers do only stage arithmetic and never re-assemble the RHS. The bug IT cites (the
scalar dropping from 3rd to 1st order because a stage hand-assembled the RHS from a mid-update velocity)
is structurally impossible in Trixi: there is exactly one `rhs!` and every stage calls it with a
consistent `(u, t)` pair.

### 3b. P4 — the `cache` is assembly scratch, created by dispatch on `(mesh, equations, solver)`, homed with the generator

`inspiration/arch/Trixi.jl/src/solvers/dgsem_tree/dg_2d.jl:14`
```
function create_cache(mesh::Union{TreeMesh{2}, TreeMesh{3}}, equations, dg::DG, RealT, uEltype)
    …
    cache = (; elements, interfaces, boundaries, mortars)
    cache = (; cache..., create_cache(mesh, equations, dg.volume_integral, dg, cache, uEltype)...)
    cache = (; cache..., create_cache(mesh, equations, dg.mortar, uEltype)...)
    return cache
end
```
The cache is a `NamedTuple` built *compositionally* — each layer (containers, volume-integral, mortar)
contributes its own sub-NamedTuple, merged. It is created once at construction
(`semidiscretization_hyperbolic.jl:58`, `cache = create_cache(mesh, equations, solver, RealT, uEltype)`)
and stored on `semi`.

**Mapped to P4.** This is the assembly-scratch precedent IT's P4 wants: "nonlinear-assembly scratch moves
into the generator." Trixi's per-flux thread-local buffers, interface/boundary containers, and
volume-integral temporaries all live in `cache`, *inside the generator*, never in the integrator. The
integrator holds only its stage registers (§3c). The `create_cache` dispatch pattern
(`create_cache(mesh, equations, solver, …)`) is directly transferable to IT's `allocate_buffers` idea,
but pointed at the *generator's* scratch rather than the integrator's.

### 3c. P1 (strategic) — the propagator is delegated to SciML, AND Trixi keeps native low-storage integrators; both consume the SAME `rhs!`

`semidiscretize` wraps the reified generator into an `ODEProblem` whose parameter is `semi`:

`inspiration/arch/Trixi.jl/src/semidiscretization/semidiscretization.jl:128`
```
u0_ode = compute_coefficients(first(tspan), semi)   # initial condition → flat state vector
rhs_semi! = default_rhs(semi)
…
return ODEProblem{iip, specialize}(rhs_semi!, u0_ode, tspan, semi)
```
`overview.md:78`
```
a spatial semidiscretization can be wrapped in an ODE problem using `semidiscretize`, which returns an
`ODEProblem`. This `ODEProblem` is a wrapper of `Trixi.rhs!(du_ode, u_ode, semi, t)`, which gets called
in ODE solvers.
```

**But Trixi also ships its own low-storage integrators** — precisely for the memory reason that drives
IT. `src/time_integration/` contains `methods_2N.jl` (2N-storage), `methods_3Sstar.jl` (3S* storage),
`methods_SSP.jl`, and `paired_explicit_runge_kutta/` (PERK). The docs give the reason:

`inspiration/arch/Trixi.jl/docs/src/time_integration.md:75`
```
Trixi.jl implements the Paired-Explicit Runge-Kutta (PERK) method, a low-storage, multirate-ready method
with optimized domain of absolute stability.
```
The native 2N integrator holds only two registers and consumes `rhs!` identically to OrdinaryDiffEq:

`inspiration/arch/Trixi.jl/src/time_integration/methods_2N.jl:95`
```
mutable struct SimpleIntegrator2N{RealT, uType, …}
    u::uType
    du::uType          # register 1
    u_tmp::uType       # register 2
    …
    const f::F         # `rhs!` of the semidiscretization
    …
end
```
`methods_2N.jl:148`
```
integrator.f(integrator.du, integrator.u, prob.p, t_stage)   # prob.p === semi (the reified generator)
```

**Mapped to P1 — this is the decisive datapoint for IT's "keep our own propagators" choice.** Trixi
proves the two decisions are *orthogonal*: (i) reify the generator behind `rhs!`, and (ii) choose a
propagator. Trixi reifies once and then uses *both* OrdinaryDiffEq's schemes *and* its own hand-rolled
2N / 3S* / PERK low-storage integrators — all consuming the identical `rhs!(du, u, p, t)` protocol.
IT keeping its own integrating-factor RK schemes (for the exact `exp(-νκ²Δt)` multiplier and GPU
allocation discipline) is therefore **fully justified and mirrors Trixi's own reasoning** for its native
low-storage integrators — the memory-footprint priority IT and Trixi share. The transferable structural
lesson: **reify the generator behind a `rhs!`-style protocol regardless of who owns the propagator**;
the protocol is what makes the propagator swappable and what kills the P1 bug class, not the choice of a
specific stepper. (One genuine mismatch: SciML's `rhs!(du, u, p, t)` is a *plain additive* RHS on a flat
state vector; it has no natural slot for IT's exact integrating factor, which is a spectral multiplier
applied *around* the stage, not a term *inside* du. IT's protocol therefore needs the extra `factor!`
hook the P1 proposal names — Trixi has no analog because it uses no integrating factor. This is a
justified deviation, not a risk: IT's exact viscous treatment is a deliberate, footprint-motivated choice
the SciML additive-RHS contract cannot express.)

### 3d. Observation + step control (P3 readers, P2 step control) — callbacks over the SciML integrator

`AnalysisCallback` and `StepsizeCallback` are `DiscreteCallback`s that read the live integrator state:

`inspiration/arch/Trixi.jl/src/callbacks_step/analysis.jl:230` — `u_ode = integrator.u` (re-wrapped via
`wrap_array` using the same `cache`). `StepsizeCallback` (`callbacks_step/stepsize.jl:31`) carries a CFL
number and sets the next `dt`. They are combined into a `CallbackSet` called *after* a complete step
(`callbacks_step/callbacks_step.jl:48`: "when combining them into a `CallbackSet` which is called *after*
a complete step").

**Mapped to P3.** Trixi's readers get their derived quantities by re-wrapping `integrator.u` with the
generator's `cache` — i.e. the observation layer reuses the *generator's* scratch, not a separate cache.
This is a leaner alternative to IT's DerivedFields: because the state is a flat vector and the cache is
already sized for one RHS evaluation, a reader recomputes on demand into cache scratch. It works because
Trixi observes only *after a complete step* (a fixed freshness point, like SpeedyWeather §2d). IT wants
mid-step observation (particle pushers), which is the reason IT needs a memoized layer that Trixi does
not.

---

## Transferable ideas for IT (ranked)

1. **Reify the generator behind a `rhs!`-style protocol independently of the propagator (P1).** Trixi's
   `semi` + `rhs!(du, u, semi, t)` is the proven pattern; its native 2N/3S*/PERK integrators *and*
   OrdinaryDiffEq both consume it unchanged. This directly validates IT's `ResolvedGenerator` +
   `rhs!/factor!/prepare!/finalize!` and confirms IT is right to keep its own integrating-factor schemes.
   The seam is a protocol, not a base class. (§3a, §3c)

2. **Let each component declare its own typed slots; merge and allocate once (P3, P4).** SpeedyWeather's
   `variables(component)` → `Variables(model)` collect-filter-allocate is IT's DerivedFields
   "declared working sets" at production scale, with the typed-category refinement
   (`PrognosticVariable` / `GridVariable` / `DynamicsVariable` / `ScratchVariable`). Adopt the *typed*
   declaration so the state/cache/scratch split is enforced by the type of the declaration. (§2c)

3. **Home the assembly scratch with the generator via a `create_cache(system, model, method)` dispatch
   (P4).** Trixi's compositional `cache` NamedTuple is the model for IT's "nonlinear-assembly scratch
   moves into the generator." (§3b)

4. **Put a stochastic forcing's Markov state in the restart record, not a cache (P5).** SpeedyWeather
   registers the AR(1) `random_pattern` as a `PrognosticVariable`. IT's OU state passes the same
   flow-map litmus and belongs beside the fields. The skew-product tower IT describes is literally
   SpeedyWeather's layout. (§2b)

5. **Bind one function to "re-derive all diagnostics" and call it at every mutation callsite (P2).**
   Oceananigans' `update_state!` (called after every substep *and* after `set!`) makes stale-cache reads
   structurally impossible for anything read inside the loop. Even if IT keeps demand-driven accessors,
   having one canonical refresh function is worth it. (§1b)

6. **Default memoization to "recompute" where staleness is hard to prove (P3).** Oceananigans'
   `recompute_safely` turns memoization OFF for nested/aliased buffers. IT's "absent slot is an error;
   resident memory is opt-in" shares the instinct; extend it to "opt-in staleness-skipping too." (§1a)

7. **Bind the observation callsite to the freshness point (P3).** Both Oceananigans (callbacks inside
   `update_state!`) and Trixi (`CallbackSet` after a complete step) run readers exactly when derived
   state is fresh. Where IT can, prefer scheduling readers at a fixed fresh point over per-read staleness
   checks. (§1e, §3d)

8. **Skip scratch on state copy/restart (P5).** SpeedyWeather's `copy!` explicitly skips the `scratch`
   group ("write-before-read; never needs to survive a sync"). IT's restart record should mechanically
   exclude anything typed as cache/scratch. (§2a)

---

## Where IT's proposal differs from this beat's practice — risk or justified deviation?

- **Per-dynamical-factor epoch counters vs an ordering contract (P3). — Partly a risk, partly justified.**
  Neither SpeedyWeather nor Oceananigans uses per-factor epochs. SpeedyWeather recomputes all diagnostics
  every step at a fixed loop position (no stamp at all); Oceananigans uses a single clock-time stamp.
  IT's finer epoching is *more machinery and a new silent-staleness surface* (a wrong epoch is exactly the
  P2 bug class). **Justified only for the readers IT truly cannot serve with an ordering contract** —
  mid-stage particle pushers and out-of-loop diagnostics. For anything read solely inside `step!`, the
  ordering contract is safer and simpler. Recommendation: scope the epoch design to the out-of-loop /
  mid-stage readers and use ordering elsewhere.

- **Demand-driven recompute-on-read accessors vs eager once-per-mutation refresh (P2/P3). — Justified for
  IT's footprint priority.** Oceananigans/SpeedyWeather refresh eagerly (compute every derived field every
  step whether or not read). IT's GPU-primary, minimal-footprint mandate favors lazy recompute so an
  unwanted chart is never materialized. This is a defensible deviation *provided* IT keeps a single
  canonical refresh entry point so the "forgot to refill" footgun cannot return through the back door.

- **Keeping bespoke integrating-factor propagators vs delegating to SciML (P1). — Justified, and mirrored
  by Trixi.** Trixi delegates *and* keeps native low-storage integrators for the memory reason IT shares.
  SciML's additive `rhs!(du, u, p, t)` has no slot for IT's exact `exp(-νκ²Δt)` spectral multiplier, so
  IT's `factor!` hook is a real, necessary extension of the protocol, not gold-plating. Delegation would
  cost IT the exact viscous treatment and the allocation-free-over-preallocated-buffers discipline.

- **A memoized derived-field cache (DerivedFields) at all vs Trixi's recompute-into-generator-cache
  (P3). — Justified by IT's mid-step observation need.** Trixi avoids a separate derived cache because it
  observes only after a complete step and re-wraps the flat state with the generator's `cache`. IT reads
  derived fields *mid-sub-step* (particle pushers read mid-stage velocity) — the exact hazard behind the
  P1 dealiasing bug — so a stamped memoized layer earns its place where Trixi's post-step-only model does
  not need one.

- **Typed variable categories: IT's "charts" vs SpeedyWeather's `PrognosticVariable`/`GridVariable`/… —
  Convergent, adopt the typing.** IT's proposal describes charts by *content* (physical velocity,
  vorticity, RHS, acceleration, pressure gradient). SpeedyWeather additionally types them by *role*
  (prognostic vs grid-diagnostic vs dynamics-scratch). IT would gain the state/cache/scratch enforcement
  of P5 for free by carrying the *role* in the declaration type, not just the content. Low-risk
  improvement.

---

## Sources

Primary (study-only clones; file:line quoted inline above):
- Oceananigans.jl `0.110.11` — `src/Fields/field.jl`, `src/AbstractOperations/computed_field.jl`,
  `src/TimeSteppers/runge_kutta_3.jl`, `src/Models/NonhydrostaticModels/{nonhydrostatic_model.jl,
  update_nonhydrostatic_model_state.jl, set_nonhydrostatic_model.jl, nonhydrostatic_tendency_kernel_functions.jl}`,
  `src/Forcings/continuous_forcing.jl`, `src/Utils/schedules.jl`.
- SpeedyWeather.jl `SpeedyWeather 0.21.1+DEV` — `src/variables/variables.jl`,
  `src/dynamics/random_process.jl`, `src/time_stepping/{time_integration.jl, transform.jl}`,
  and the clone's `CLAUDE.md` (Variables-group table).
- Trixi.jl `0.16.27-DEV` — `src/semidiscretization/{semidiscretization_hyperbolic.jl,
  semidiscretization.jl}`, `src/solvers/dgsem_tree/dg_2d.jl`, `src/time_integration/methods_2N.jl`,
  `src/callbacks_step/{analysis.jl, stepsize.jl, callbacks_step.jl}`, `docs/src/{overview.md,
  time_integration.md}`.

Web (version/lead characterization):
- [SpeedyWeather.jl stable docs — Analysis (PrognosticVariables/DiagnosticVariables)](https://speedyweather.github.io/SpeedyWeather.jl/stable/analysis/)
- [SpeedyWeather.jl stable docs, JuliaHub (two-record model, published API)](https://docs.juliahub.com/SpeedyWeather/S62uU/0.10.0/callbacks/)
- [SpeedyWeather/SpeedyWeather.jl releases](https://github.com/SpeedyWeather/SpeedyWeather.jl/releases)

Verification note: the SpeedyWeather *seeded lead* (two-record `PrognosticVariables`/`DiagnosticVariables`
split) is **CONFIRMED as the published/stable API** but **SUPERSEDED in the `0.21.1+DEV` clone** by the
unified seven-group `Variables` struct; the two-record *principle* (one state record, the rest diagnostic
with no memory between steps) survives verbatim. All Oceananigans and Trixi seeded leads (FieldStatus
time-stamp memoization; `update_state!` as the mutation gate; per-scheme registers in the timestepper
struct; `SemidiscretizationHyperbolic` bundling mesh/equations/solver/cache; `create_cache` dispatch;
`semidiscretize` → `ODEProblem`; delegated propagator with native low-storage integrators) are
**CONFIRMED against source** with the lines quoted above.
