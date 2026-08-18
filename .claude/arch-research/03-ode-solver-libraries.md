# Beat 03 — ODE / time-integration libraries: the reified-generator precedent

**Scope.** How the mature ODE/DAE solver ecosystems reify the right-hand side as an object, expose a
sanctioned mid-run access surface, provide an out-of-band-mutation invalidation verb, allocate
per-scheme scratch by dispatch, and layer observation on top — mapped onto IT's five design problems:

- **P1** generator/propagator seam reified as an RHS object with a protocol (`rhs!`/`factor!`/`prepare!`(/`finalize!`)).
- **P2** an explicit staleness / invalidation verb for out-of-band state mutation.
- **P3** a sanctioned observation layer over derived quantities.
- **P4** scratch ownership (who allocates the per-scheme registers).
- **P5** the state doctrine (what is in the restart record vs a cache).

Verification discipline: every load-bearing claim below is quoted from a primary source (paper PDF, the
package's own docs, or its master-branch source) with the source named. Seeded leads are marked
**CONFIRMED**, **REFUTED**, **REFINED**, or **PARTIALLY VERIFIED**.

---

## 1. DifferentialEquations.jl / SciML — the direct P1/P2/P4 precedent

### 1.1 `ODEFunction` — the reified RHS bundle (P1) — CONFIRMED

SciML reifies the RHS as a first-class object that carries the numerical function **plus** its associated
analytic data. From the ODE-types docs (`docs.sciml.ai/DiffEqDocs/stable/types/ode_types/`, consulted
2026-07-18), `ODEFunction(f; ...)` accepts, among others:

- `mass_matrix`: *"the mass matrix `M` represented in the ODE function. Can be used to determine that the
  equation is actually a differential-algebraic equation (DAE) if `M` is singular."*
- `jac`: *"returns df/du"*; `tgrad`: *"returns ∂f(u,p,t)/∂t"*; `jvp`: *"returns the directional
  derivative df/du·v"*; `vjp`: *"returns the adjoint derivative (df/du)*·v"*.
- `jac_prototype`: *"a prototype matrix matching the type that matches the Jacobian … an appropriately
  sized `Tridiagonal` matrix can be used as the prototype."*
- `paramjac`, `colorvec`, `sparsity`, `analytic` (*"only used for testing and development"*), `sys`.

The SciMLBase interface docs (`docs.sciml.ai/SciMLBase/stable/interfaces/SciMLFunctions/`) frame *why*
the bundle exists: *"The SciML ecosystem provides an extensive interface for declaring extra functions
associated with the differential equation's data"* — where a traditional solver has *"one option (the
Jacobian)"*, this lets *"a large array of pre-computed functions to speed up the calculations"* travel
with the RHS.

**Map to P1.** `ODEFunction` is IT's proposed `ResolvedGenerator` in miniature: a struct binding the
evaluator to the metadata a scheme needs, so the scheme dispatches on the object rather than
hand-assembling. The crucial difference from IT's protocol: `ODEFunction`'s extra slots are all
*evaluators of the same dynamics* (Jacobian, time-gradient, mass matrix) — there is **no lifecycle
verb** (`prepare!`, `finalize!`) on the function object. Post-step action lives in a *separate* layer
(callbacks, §1.6), not on the generator. IT folding a per-step `prepare!`/`finalize!` onto the generator
is a deviation from this precedent (see §4).

### 1.2 `SplitFunction` / `SplitODEProblem` — where the exact viscous factor sits (P1) — CONFIRMED + REFINED

SciML expresses semilinear and IMEX dynamics as a two-part function. From the split-ODE-types docs:

> "du/dt = f₁(u,p,t) + f₂(u,p,t)" … "the f₁ portion should be considered the 'stiff portion of the
> model' … while the f₂ portion should be considered the 'non-stiff portion'." … "directly used in
> integrators like IMEX (implicit-explicit integrators) and exponential integrators."

For the **exact-operator** case the docs specialize this to the *semilinear* form (split-ODE solvers
page, `solvers/split_ode_solve/`):

> "The Semilinear ODE is a `SplitODEProblem` with one linear operator and one nonlinear function:
> du/dt = Au + f(t,u)."

The exponential and integrating-factor methods — **LawsonEuler, NorsettEuler, ETD2, ETDRK2/3/4,
HochOst4** — are documented under this semilinear section and consume the `A + f(t,u)` structure. IMEX
methods (KenCarp, ARKODE) consume the general two-function split *"where the first function is the stiff
part"* (both parts functions, no linearity required). The linear operator is built through **SciMLOperators**:
*"See the documentation page for SciMLOperators for details about how to define linear operators from a
matrix or finite difference discretization of derivative operators."*

**Answer to the seeded question — "where would IT's exact viscous factor sit in their taxonomy?"** IT's
integrating factor `exp(-ν κ² Δt)` is exactly the semilinear case with **A = -ν κ²** — a *diagonal*
linear operator in the spectral representation. In SciML's taxonomy IT is an **exponential /
integrating-factor scheme with an exact, diagonal, precomputed operator**: the Generator is a
`SplitFunction` whose linear slot `A` is exact-exponentiated (as LawsonEuler/ETDRK would, but IT's `A`
is diagonal so `exp(AΔt)` is elementwise and *exact*, not Krylov-approximated) and whose `f₂` is the
rotational nonlinear term. This also answers **P4's `set_forcing_rate!`**: a *linear* per-mode forcing
rate is, in SciML's grammar, part of the linear operator `A` — folding a linear forcing rate into the
factor is precisely what putting it in `A` means, so IT's design agrees with the precedent.

*PARTIALLY VERIFIED:* the seeded names `ExponentialUtilities` / `LinearExponential` / `ETDRK` — ETDRK
and the exponential family are confirmed above; `LinearExponential` (solver for the purely-linear
`du/dt = Au`) and `ExponentialUtilities` (the Krylov `expv`/`phiv` backend) are referenced in-context
but I did not open their own pages, so treat those two names as PARTIALLY VERIFIED. The load-bearing
fact — the linear operator is carried by the `f₁`/`A` slot and consumed by exponential/IF methods — is
CONFIRMED.

### 1.3 The integrator interface — sanctioned mid-run access (P2, P3) — CONFIRMED

`init` / `step!` / `solve!` produce a live, inspectable integrator object. From the integrator-interface
docs, the sanctioned read fields are:

- `t` *"time of the proposed step"*, `u` *"value at the proposed step"*, `uprev` *"the value at the last
  timepoint"*, `tprev`, `f` *"the function being solved"*, `p` *"user-provided data"*, `sol` *"the
  current state of the solution"*.

This is the sanctioned analog of IT's `Simulation` + `advance!`: a stateful object you `step!` and then
read `integrator.u` / `integrator.t` from. The critical contract:

> "Be cautious: one should not directly mutate the `t` and `u` fields of the integrator. Doing so will
> destroy the accuracy of the interpolator and can harm certain algorithms."

`get_du(i)` is the sanctioned accessor for the derivative — the P3-relevant point:
`docs/basics/integrator.md` (master) and the SciMLBase source say `get_du` *"Return the derivative
represented by the integrator at its current `(u, p, t)`. An implementation may return an internal
derivative cache or evaluate the problem function when no valid cache exists."* This is **exactly IT's
P3 producer-deposit-plus-accessor-recompute pattern**: return the cached derivative if valid, else
recompute — one verb, two mechanisms, correctness guaranteed.

### 1.4 `u_modified!` / `derivative_discontinuity!` — the explicit invalidation verb (P2) — CONFIRMED + REFINED (important)

This is the verb IT's P2 accessor design is missing, and the survey turned up a **live rename** worth
recording. In the current **stable release** the verb is `u_modified!`. From the stable integrator docs
(via the SciML docs, consulted 2026-07-18): `u_modified!(integrator, bool)` is *"a Bool which states
whether a change to u occurred, allowing the solver to handle the discontinuity"*; and *"If
`continuous_modification` is true (or unspecified), this should also recalculate interpolation data.
Otherwise the integrator is allowed to skip recalculating the interpolation."* Combined with the
"do not directly mutate `u`" caution (§1.3), the contract is: **mutate `u` out of band → you must call
`u_modified!(integrator, true)` so the integrator invalidates its interpolation/derivative cache.**

On **master** (SciMLBase.jl `src/integrator_interface.jl`, fetched 2026-07-18) the verb has been
**renamed** to `derivative_discontinuity!`, with `u_modified!` retained only as a deprecated alias:

```julia
"""
    u_modified!(integrator, modified)
Deprecated alias for [`derivative_discontinuity!`](@ref).
"""
function u_modified!(i::DEIntegrator, bool)
    Base.depwarn("`u_modified!(i::DEIntegrator, bool)` is deprecated, use " *
                 "`derivative_discontinuity!(i, bool)` instead.", :u_modified!)
    return derivative_discontinuity!(i, bool)
end
```

`derivative_discontinuity!(i, bool)` — *"Record whether a callback or direct integrator mutation
introduced a derivative discontinuity."* The rename is itself a lesson for IT: the community found
`u_modified!` under-named — the verb is not really "u changed" but "a discontinuity in `f(u,p,t)` was
introduced" (a change to `u`, `p`, `t`, **or `f` itself**). The two mutation setters carry the same
semantics automatically: `set_u!(integrator, sym, val)` *"writes `val` into `integrator.u` and marks a
derivative discontinuity"* and internally calls `derivative_discontinuity!(integrator, true)`.

**Map to P2.** IT's demand-driven accessors "recompute on staleness" solve the *read* side. SciML shows
the *write* side needs a peer: an explicit verb the mutator calls to signal "I changed the state out of
band; invalidate what depends on it." IT's P2 has the recompute-on-read half; the SciML precedent argues
for pairing it with an explicit invalidation call (or a stamped epoch bump that a mutator is *required*
to perform) so a producer that writes a slot cannot silently leave a stale downstream cache — the same
footgun `u_modified!` exists to close. Note also the naming lesson: name the verb for the *invariant it
guards* (a discontinuity in the dynamics), not the *slot that changed*.

### 1.5 `alg_cache` / `perform_step!` — per-scheme registers by dispatch (P1, P4) — CONFIRMED

The JORS 2017 paper (Rackauckas & Nie, *DifferentialEquations.jl*, J. Open Res. Softw. 5:15,
doi:10.5334/jors.151), §1.6.1, states the pattern verbatim:

> "The ODE solver works by setting up options and fixing types, and then builds the `integrator` type
> and enters the internal loop. All dispatches on loop functions are done by the algorithm/cache type.
> Thus to define a new algorithm, one defines a new algorithm type which subtypes the
> `OrdinaryDiffEqAlgorithm` type … a new dispatch for `perform_step!` needs to be added which performs
> the algorithm's update from uₙ to uₙ₊₁. For example, the Midpoint Method steps as follows:"

```julia
@inline function perform_step!(integrator, cache::MidpointConstantCache, f=integrator.f)
  @unpack t,dt,uprev,u,k = integrator
  halfdt = dt/2
  k = integrator.fsalfirst
  k = f(t+halfdt, uprev+halfdt*k)
  u = uprev + dt*k
  integrator.fsallast = f(t+dt,u) # For interpolation, then FSAL'd
  ...
end
```

> "Additionally a new `cache` type must be developed for holding the cache variables. By doing this, all
> of the functionality of OrdinaryDiffEq.jl will be automatically applied to the algorithm."

Two P-mappings in one quote:

- **P1.** `perform_step!` does *only stage arithmetic* — it receives the reified RHS as an argument
  (`f=integrator.f`) and calls `f(...)`; it does not hand-assemble the RHS. This is precisely IT's target
  end state: schemes do stage arithmetic over a passed-in generator. Note the RHS `f` is a *default
  argument* — the generator is a parameter of the step, not baked into the loop.
- **P4.** *"a new cache type must be developed for holding the cache variables"* — allocated by
  `alg_cache` dispatching on the algorithm type. This is IT's `allocate_buffers` dispatch, **confirmed as
  the same pattern**: each scheme owns and declares exactly its own registers; the framework allocates
  them once. (In modern OrdinaryDiffEq the constructor is `OrdinaryDiffEq.alg_cache(alg, ...)`,
  dispatching on `alg`; the JORS text describes it as "a new cache type must be developed". The
  `…ConstantCache` vs mutable-cache split is the out-of-place vs in-place distinction — IT is always the
  in-place mutable-cache side.)

**Scratch-ownership reading for P4.** SciML draws the boundary IT proposes: stage registers live in the
algorithm's cache (owned by the integrator/scheme). It does **not** hand a forcing or a sub-model the
integrator's private cache bundle — the RHS `f` is a separate object with its own captured data (§1.7).
So SciML endorses IT's P4 split: RK registers with the integrator, model/forcing scratch with the model.

### 1.6 Callbacks — the sanctioned observation layer (P3) — CONFIRMED

Observation and out-of-band action are a *separate* subsystem from the RHS. From the callback docs:

- `DiscreteCallback(condition, affect!)`: `condition(u,t,integrator)` returns `true` to fire; `affect!(integrator)` mutates.
- `ContinuousCallback(condition, affect!, affect_neg!)`: fires when `condition` *"hits `0` within the
  time interval"*; separate up/down-crossing effects.
- `SavingCallback` (DiffEqCallbacks): saves user-computed observables along the trajectory. (Named in the
  ecosystem docs; I did not open its own page — treat the *name* as PARTIALLY VERIFIED, the *existence of
  a saving-observation callback* as CONFIRMED via the callbacks catalogue.)

Inside `affect!`, mutating `u` is legal *precisely because* the callback machinery calls the invalidation
verb for you — this is why `u_modified!`/`derivative_discontinuity!` exists (§1.4). `savevalues!(integrator, force_save=false) -> (saved, savedexactly)` is the sanctioned save hook.

**Map to P3.** SciML's observation layer is a *push/pull hook system distinct from the generator*:
diagnostics (`SavingCallback`), events (`Discrete`/`ContinuousCallback`), and derived-quantity reads
(`get_du`) all sit *outside* `ODEFunction`. This is the strongest external endorsement of IT's P3
`DerivedFields` being a *sanctioned separate layer* rather than "read the loop's private scratch" — and
of IT keeping post-step projection/rescale in that layer rather than on the generator (§4).

### 1.7 Problem/solver separation and the "confederated" API (P5) — CONFIRMED + citation correction

JORS 2017 §1.1: the user *"follows the steps: 1. Define a problem. 2. Solve the problem. 3. Plot the
solution."* — the `ODEProblem` (dynamics + `u₀` + timespan) is separated from the algorithm, and
§1.3.1: *"`solve(prob, Algorithm())` calls a different 'method' depending on the type of `Algorithm`.
This function is called the 'common solve interface'."* §1.2.2 ("Explicit Parameters") reifies the
parameter record into the function type: parameters *"are built into the function type itself … still
accessible via the type fields, for example `f.a`."*

**Map to P5.** The clean line SciML draws — *problem specification* (the thing to be advanced: dynamics +
initial condition + parameters) vs *solver state* (the integrator's caches and step registers) — is
IT's P5 litmus in another vocabulary: what the flow map needs (the `ODEProblem`) vs the solver's private
scratch (the integrator cache). The `ODEProblem`/`ODEFunction` is IT's restart record; the integrator
cache is disposable. The parameter record living *inside* the function type is IT's `ResolvedGenerator`
= "parameter record + assembly scratch".

**Citation correction (seeded lead).** The seeded phrase *"confederated modular API design paper
(Rackauckas & Nie 2017, JORS)"* conflates two papers. The 2017 JORS paper is titled *"DifferentialEquations.jl
— A Performant and Feature-Rich Ecosystem for Solving Differential Equations in Julia"* (it does not use
the word "confederated"). The **"confederated modular"** phrase is the title of a *separate* 2019 paper:
Rackauckas & Nie, *"Confederated modular differential equation APIs for accelerated algorithm development
and benchmarking,"* Advances in Engineering Software 132 (2019). If IT cites the "confederated" framing,
cite the 2019 AES paper; if it cites the ecosystem/common-solve design, cite JORS 2017. Do not cite
JORS 2017 for the word "confederated".

---

## 2. PETSc TS — a reified *split* generator in C (P1, P3, P4)

### 2.1 The two-part generator: `TSSetIFunction` + `TSSetRHSFunction` (P1) — CONFIRMED

PETSc's time-stepping component (PETSc manual, `petsc.org/release/manual/ts/`, consulted 2026-07-18)
expresses the problem in the general split form and registers each part separately:

> "F(t,u,u̇) = G(t,u), u(t₀) = u₀"

- The **implicit / stiff** part `F(t,u,u̇)` is supplied through `TSSetIFunction`, with its Jacobian
  `σ F_u̇ + F_u` through `TSSetIJacobian`.
- The **explicit / non-stiff** part: *"Function G(t,u), if it is nonzero, is provided with the function
  `TSSetRHSFunction`,"* with an *"appropriate (approximate) Jacobian matrix of G()"* via `TSSetRHSJacobian`.

**Map to P1.** PETSc reifies the generator as **two registered callbacks plus their Jacobians** — a
split generator object, in C, with an explicit protocol (`IFunction`/`IJacobian`/`RHSFunction`/`RHSJacobian`).
For IT this is the IMEX reading of the viscous/advection split: the viscous term is the `IFunction`
(implicit/stiff), the rotational advection the `RHSFunction` (explicit). The difference from IT: PETSc
solves the stiff part *implicitly* (a nonlinear solve per step), whereas IT exploits the fact that its
stiff part is *diagonal and linear*, so it uses an **exact integrating factor** instead of an implicit
solve. IT's generator is therefore the *specialized* case PETSc's IFunction generalizes — IT can afford
a `factor!` verb (elementwise exact `exp`) where PETSc needs a `SNES` solve. The protocol shape (a
handful of registered residual/operator callbacks) is the shared idea.

**Post-step verb question.** PETSc's residual callbacks (`IFunction`/`RHSFunction`) are *pure
evaluators* — no post-step verb lives on them. Post-step/post-stage actions are separate hooks
(`TSSetPostStep`/`TSSetPostStage`, and the monitors in §2.2). CONFIRMED that the *residual* functions are
pure; the specific post-step hook names I did not open (treat `TSSetPostStep`/`TSSetPostStage` names as
PARTIALLY VERIFIED). The load-bearing point stands: PETSc, like SciML, keeps the generator a pure
evaluator and puts lifecycle elsewhere.

### 2.2 `TSMonitorSet` — the observation hook (P3) — CONFIRMED

From `petsc.org/release/manualpages/TS/TSMonitorSet/`:

> "Sets an ADDITIONAL function that is to be used at every timestep to display the iteration's progress."

Prototype and callback signature:

```c
PetscErrorCode TSMonitorSet(TS ts,
    PetscErrorCode (*monitor)(TS ts, PetscInt steps, PetscReal time, Vec u, PetscCtx ctx),
    PetscCtx mctx, PetscCtxDestroyFn *mdestroy)
```

The monitor receives `(ts, steps, time, u, ctx)` — the step index, the time, and the current iterate
`u`, plus a user context. *"This routine appends a monitor to existing monitors rather than replacing
them"* — an ordered, stackable list of observation callbacks.

**Map to P3.** `TSMonitorSet` is IT's sanctioned observation surface in C: readers register a callback
receiving `(step, t, u)` and derive whatever they need, *without reaching into TS's private step
scratch*. The monitor gets the state and a context to stash its own accumulators — the same "observers
own their scratch, the loop hands them the state" contract IT's `DerivedFields` wants. The stackable-list
design is worth noting for IT: multiple observers (diagnostics, particle pusher, statistics) coexist as
an ordered registry rather than one monolithic callback.

### 2.3 `DMGetWorkArray` / `DMRestoreWorkArray` — a checkout/checkin scratch *pool* (P4) — CONFIRMED

A genuine *alternative* to IT's P4 "each component owns its scratch". From
`petsc.org/release/manualpages/DM/DMGetWorkArray/`:

> "Gets a work array guaranteed to be at least the input size, restore with `DMRestoreWorkArray()`."

```c
PetscErrorCode DMGetWorkArray(DM dm, PetscInt count, MPI_Datatype dtype, void *mem)
```

> "A `DM` may stash the array between instantiations so using this routine may be more efficient than
> calling `PetscMalloc()`." … "The array may contain nonzero values" (i.e. checkout gives you dirty
> memory — you must initialize).

**Map to P4 — the alternative IT did not choose.** PETSc centralizes scratch in a **pool owned by the
mesh object (`DM`)**; any routine that needs scratch *checks out* a right-sized buffer and *checks it
in* when done. This is the opposite pole from IT's proposal (each component *owns named, resident*
scratch): a pool trades named-slot clarity and always-resident GPU buffers for peak-memory savings
(buffers are shared across non-overlapping lifetimes) at the cost of "the array may contain nonzero
values" (no validity guarantee — the caller must treat every checkout as garbage). For IT this is a
**deliberate contrast worth recording**: IT's GPU-primary, allocation-free hot loop wants
*resident, named, stamped* slots (P3's charts) so it can *deposit-and-memoize* rather than
checkout-and-reinitialize. A pool defeats the producer-deposit optimization (a checked-in buffer carries
no epoch stamp, so a later reader cannot trust it). IT's choice is justified by the deposit/memoize
requirement; PETSc's pool is the right answer for the *different* problem of transient, one-shot scratch
in a solve where nothing is memoized across steps.

---

## 3. SUNDIALS — object-oriented redesign: strategy objects and a backend-agnostic vector (P1, P3, P5)

Source: Gardner, Reynolds, Woodward & Balos, *"Enabling New Flexibility in the SUNDIALS Suite of
Nonlinear and Differential/Algebraic Equation Solvers,"* ACM TOMS 48(3), 2022, doi:10.1145/3539801
(read from the arXiv:2011.10073 PDF, v2, pages 1–8).

### 3.1 The four base classes as swappable strategy objects (P1) — CONFIRMED

§3: to integrate ODEs/DAEs or solve nonlinear systems one must (1) do vector operations, (2) solve the
nonlinear systems in implicit methods, (3) solve the linear systems, (4) do matrix operations. These
*"lead directly to the SUNDIALS `N_Vector`, `SUNMatrix`, `SUNLinearSolver`, and `SUNNonlinearSolver`
classes … that define abstract interfaces for performing vector and matrix operations as well as solving
linear and nonlinear systems."* The design intent:

> "This object-oriented design encapsulates implementation-specific details behind a set of well defined
> abstract interfaces for performing mathematical operations. This encapsulation enables writing the
> SUNDIALS packages purely in terms of generic operations on objects, making them agnostic to the user's
> particular choice of data structures/layout, method of parallelization, algebraic solvers, etc."

Mechanism (§3.2): each base class is *"a C structure containing a `void` pointer to the derived class
member data and a virtual method table (VMT) implemented as a C structure of function pointers"*:

```c
struct _generic_SUNLinearSolver {
  void *content;          // pointer to member data
  SUNLinearSolver_Ops ops;  // virtual method table
};
```

> "the base class VMT includes pure virtual functions for which a derived class must provide an
> implementation, virtual functions the derived class may override, and optional functions that, if
> non-NULL, the SUNDIALS packages will utilize to improve performance. Thus, the base class pure virtual
> functions define the required minimum set of operations for derived classes."

**Map to P1.** This is IT's `rhs!`/`factor!`/`prepare!` protocol expressed as a C VMT: a *required
minimum set of operations* every implementation must provide, plus *optional* fast-path operations that
the framework uses if present and falls back on a default if absent. For IT's protocol design this
argues for a **two-tier protocol**: a mandatory core (`rhs!`, `factor!`) that every generator/forcing
must implement, and *optional* hooks (`prepare!`, `finalize!`) that default to no-ops — so a forcing
that needs no internal-state advance simply doesn't implement `prepare!`, exactly as a SUNDIALS derived
class leaves an optional VMT slot NULL. (See §4 for the "optional-hook-defaults-to-noop" design.)

### 3.2 The private-data-access anti-pattern — the P3 motivation, stated (P3) — CONFIRMED

The redesign's *motivation* is IT's P3 problem, named exactly. §3.1, on the *old* SUNDIALS:

> "providing the interface functions and performing some computations required directly accessing
> private data within the packages, which hindered the ability of the packages to evolve without
> breaking user code."

> "While the integrator-specific nonlinear systems could be written in a generic form, the nonlinear
> solvers were embedded within the integrators. As such, each package implemented its own nonlinear
> solvers … leading to duplicated code and inconsistent solver options between the packages."

**Map to P3 (and P1).** "Readers reaching into private scratch whose validity is comment-enforced" is
IT's P3 in one sentence; SUNDIALS names the *cost* — it *"hindered the ability of the packages to evolve
without breaking user code."* And "each scheme's `step!` hand-assembles the RHS, the forcing prologue
duplicated verbatim across schemes" (IT's P1) is the same *"duplicated code … embedded within the
integrators"* SUNDIALS eliminated by lifting the embedded logic into a shared strategy object. SUNDIALS
is the strongest external evidence that IT's P1+P3 are *the same class of debt* and that the fix is a
sanctioned interface object, not tighter comments.

### 3.3 `N_Vector` — the backend-agnostic array (P5, and the PF analog) — CONFIRMED

§4: the vector encapsulation *"allow[s] existing codes to rapidly utilize SUNDIALS integrators and
solvers, since users needed only to provide an implementation of the `N_Vector` class to wrap and
operate on their application-specific data structures."* Implementations exist *"based on OpenMP,
Pthreads, CUDA, HIP, SYCL, and RAJA for various forms of on-node parallelism"* plus wrappers for PETSc,
hypre, Trilinos.

**Map.** `N_Vector` is the exact analog of IT's reliance on GBGPeriodicFields for backend-agnostic
`AbstractArray` storage (CPU/CUDA/ROCm): the physics/solver is written *"purely in terms of generic
operations"* on a vector abstraction, and the backend (including GPU) is swapped underneath. This
validates IT's "belongs-in-PF → raise, don't reimplement" invariant against the leading HPC ODE suite:
the vector operations are a *separate class* the solver depends on, never reimplemented per integrator.

### 3.4 Fused vector operations — the PF fused-ops precedent (cross-cut with IT's PF request) — CONFIRMED

§4.1: SUNDIALS added *"a set of 'fused' operations that each combine a specific sequence of operations
into a single routine … reducing overhead"* — `N_VLinearCombination` (z = Σ cᵢ Xᵢ), `N_VScaleAddMulti`,
`N_VDotProdMulti`, `N_VLinearSumVectorArray` — motivated because on accelerators *"each vector operation
requires a separate kernel launch, and for MPI-based parallel vectors each dot product or norm-like
operation requires one `MPI_Allreduce` call."* Critically:

> "all of these new operations are *optional* as the base class implementation calls the pre-existing
> sequence of *required* operations to achieve the same result. Thus, the operations can be enabled or
> disabled at runtime by setting the VMT function pointer to the implementation defined function or to
> NULL."

**Map.** This is the direct precedent for IT's own PF fused-operations request (`combine!`, `det`,
`symmetric_gradient`, `weighted_inner`): fuse a sequence to cut kernel launches on GPU, and make the
fused op *optional* with a correct scalar-sequence fallback. It reinforces IT's "raise a fused reduction
to PF" discipline — SUNDIALS did exactly this at the vector layer, and the *optional-with-fallback*
contract is the safe way to add them (a missing fused op degrades performance, never correctness).

### 3.5 ARKODE additive Runge–Kutta / ImEx splitting (P1) — CONFIRMED

§2.3: ARKODE targets *"ODE IVPs in the linearly-implicit form M(t) ẏ = f(t,y)"* where `M(t)` is a
*"nonsingular linear operator"*, and:

> "The right-hand side function may be additively partitioned as f(t,y) = f₁(t,y) + f₂(t,y). For stiff,
> nonstiff, and mixed stiff/nonstiff problems, where f₁ = fᴱ may contain the nonstiff (explicit)
> components and f₂ = fᴵ the stiff (implicit) components of the system respectively, ARKODE provides
> explicit, implicit, and implicit-explicit (IMEX) additive Runge-Kutta methods."

The general ARK stage form (§2.3) has the internal stages `zᵢ` built from separate explicit (`Aᴱ`) and
implicit (`Aᴵ`) Butcher tables, with `f̂ᴱ = M⁻¹fᴱ` and `f̂ᴵ = M⁻¹fᴵ` *"convert[ing] the IVP from
linearly implicit to explicit form."*

**Map to P1.** ARKODE is the mature form of IT's Propagator × Generator seam: a *single* ARK stepper
consumes a *split* RHS (`fᴱ` + `fᴵ`) and a mass operator `M`, and *the same stepper* serves explicit,
implicit, and IMEX methods by which tables are populated. For IT: one `step!` family parameterized by a
reified split generator is the target; the ARK "internal stages `zᵢ`" are IT's RK stage registers (the
P4 integrator-owned cache); `fᴱ`/`fᴵ` are the reified evaluators (P1). The mass operator `M` is a further
generalization IT does not need (its `M = I`), but the *shape* — stepper consumes a split reified
generator plus operator metadata — is the canonical answer to P1.

---

## Transferable ideas for IT (ranked)

1. **Reify the RHS as an object the scheme dispatches on; schemes do only stage arithmetic.** Confirmed
   across all three suites (`ODEFunction`+`perform_step!(…, f)`, PETSc `IFunction`/`RHSFunction`,
   ARKODE `fᴱ`/`fᴵ`). IT's `ResolvedGenerator` is squarely in the mainstream; the JORS `perform_step!`
   example is a near-perfect template (RHS passed as an argument, stage arithmetic only).

2. **Pair the demand-driven accessor (P2 read side) with an explicit invalidation verb (write side).**
   SciML's `u_modified!`→`derivative_discontinuity!` is the missing peer to IT's recompute-on-staleness:
   a mutator that writes state out of band must *signal* it (bump the epoch / call the verb) or a
   downstream cache goes silently stale — the very footgun P2 targets. Adopt an explicit, *named-for-the-
   invariant* invalidation call (or a mandatory epoch bump on every producer write).

3. **Name the invalidation verb for the invariant, not the slot.** The community *renamed* `u_modified!`
   to `derivative_discontinuity!` because the guarded invariant is "a discontinuity in `f(u,p,t)`", not
   "u changed". IT should name its P2/P3 verbs for the *dynamical-factor epoch* they guard, matching its
   own "per-dynamical-factor epoch counters" design.

4. **Two-tier protocol: required core + optional hooks that default to no-ops.** SUNDIALS' VMT (pure
   virtual required + optional NULL-able) is the pattern for IT's `rhs!`/`factor!` (required) vs
   `prepare!`/`finalize!` (optional, no-op default) — a forcing with no internal state simply omits
   `prepare!`, no ceremony.

5. **Keep the observation layer separate from the generator (P3).** SciML callbacks, PETSc
   `TSMonitorSet`, SUNDIALS' redesign all put diagnostics/events *outside* the RHS object. IT's
   `DerivedFields` as a sanctioned separate layer is well-precedented; the stackable-registry shape
   (PETSc "appends a monitor") suits IT's several independent observers (diagnostics, particle pusher,
   statistics).

6. **`get_du` semantics = deposit-if-valid-else-recompute.** SciML's `get_du` ("return the internal
   derivative cache or evaluate when no valid cache exists") *is* IT's P3 producer-deposit + accessor-
   recompute in one verb. Adopt that contract verbatim for each chart accessor.

7. **Per-scheme cache allocated by dispatch (P4).** `alg_cache(alg,…)` = IT's `allocate_buffers`.
   Confirmed identical. Keep RK registers in the scheme's cache; keep model/forcing scratch out of it.

8. **Linear terms (viscous factor, linear forcing rate) belong in the linear-operator slot.** SciML's
   semilinear `Au + f` places the exact operator in `A`; IT folding the viscous factor and a linear
   `set_forcing_rate!` into the integrating factor is the same placement — principled, not ad hoc.

9. **Optional fused GPU ops with a correct scalar fallback (cross-cut).** SUNDIALS' optional fused
   `N_Vector` ops reinforce IT's PF fused-operations discipline: fuse to cut kernel launches, keep the
   fused op optional with a sequence fallback so a gap degrades speed, never correctness.

---

## Where IT's proposal differs from this beat's practice — risk or justified deviation

**(a) A post-step (`finalize!`) verb ON the generator.** *Deviation.* None of the three suites put a
post-step lifecycle verb on the reified RHS/generator — `ODEFunction`, PETSc `IFunction`/`RHSFunction`,
and ARKODE `fᴱ`/`fᴵ` are all *pure evaluators*; post-step action lives in a *separate* hook layer
(callbacks, `TSMonitorSet`/`TSSetPostStep`, ARKODE post-processing). IT proposing `finalize!` on the
generator, plus a forcing `apply_forcing!` post-step projection/rescale, blends evaluation with
lifecycle. **Assessment: a mild risk, but likely justified for IT.** IT's post-step forcing projection
(constant-energy rescale, Leray re-projection) is *dynamically coupled to the step* in a way a generic
solver's callbacks are not, and IT is not building a general solver library where the purity buys
third-party extensibility. Still, the precedent argues for *routing `finalize!` through the same
observation/hook layer as P3* rather than making it a generator method — that keeps the generator a pure
evaluator (aiding testability and the P1 seam) and unifies "things that run after a step" in one place.
Recommend: reconsider whether `finalize!`/`apply_forcing!` are *hooks in the observation layer* rather
than *methods on the generator*.

**(b) Resident, named, stamped scratch vs a checkout/checkin pool.** *Deviation from PETSc, agreement
with SciML.* PETSc's `DMGetWorkArray` pool is the memory-frugal alternative IT rejected. IT's
resident-named-slot choice (P3 charts, P4 owned scratch) is **justified**: IT's producer-deposit +
memoize optimization *requires* a stamped, persistent slot (a pooled buffer "may contain nonzero values"
and carries no epoch, defeating memoization), and IT's allocation-free GPU hot loop wants buffers
allocated once, not churned through a pool. The trade is higher peak memory — which collides with IT's
"minimal footprint trumps compute" invariant. **Assessment: justified, but the tension with the
footprint invariant should be recorded**: IT's "construction-time declared working sets, merged and
allocated once, resident GPU memory *opt-in*" is precisely the mitigation (opt-in residency recovers the
pool's peak-memory benefit for charts a run doesn't need). Keep the opt-in-residency knob prominent.

**(c) Exact diagonal integrating factor vs implicit stiff solve.** *Specialization, not a risk.* PETSc's
`IFunction` and ARKODE's `fᴵ` solve the stiff part *implicitly* (a nonlinear solve per step); IT's stiff
part is diagonal-linear, so its `factor!` is an exact elementwise `exp` — no solve. IT sits in SciML's
*exponential/integrating-factor* branch (LawsonEuler/ETDRK), specialized to a diagonal, precomputed,
*exact* operator. **Assessment: a clean specialization** — IT should frame its Generator as "the
semilinear split with an exact diagonal linear operator", which both names its place in the taxonomy and
justifies why it has a `factor!` verb the general suites replace with a `SNES`/Newton solve.

**(d) Scope: a physics package, not a solver library.** SUNDIALS/SciML/PETSc reify strategy objects to
serve *third-party* solvers/data-structures/algebraic backends. IT's reification (P1) serves *internal*
scheme uniformity and bug-prevention (the P1 3rd→1st-order scalar bug). **Assessment: justified reduced
ambition** — IT needs the *seam and the protocol* (to stop hand-assembly and duplicated prologues), not
the full runtime-pluggable VMT/registration machinery. IT should take the *two-tier required/optional
protocol* idea (§3.1) without the C-style function-pointer indirection; Julia multiple dispatch on the
generator type already gives the `perform_step!(…, generator)` specialization for free (JORS §1.6.1).

---

## Sources

- **DifferentialEquations.jl / SciML docs** (consulted 2026-07-18):
  - Integrator interface — `https://docs.sciml.ai/DiffEqDocs/stable/basics/integrator/` and master
    source `https://raw.githubusercontent.com/SciML/DiffEqDocs.jl/master/docs/src/basics/integrator.md`
    ("do not directly mutate `t` and `u`"; `set_u!`/`set_t!`/`set_ut!`; `get_du`).
  - `SciMLBase.jl` master — `src/integrator_interface.jl`
    (`https://github.com/SciML/SciMLBase.jl/blob/master/src/integrator_interface.jl`): `u_modified!`
    deprecated alias for `derivative_discontinuity!`; `set_u!`, `get_du`, `savevalues!`, `reinit!`
    docstrings.
  - Callback functions — `https://docs.sciml.ai/DiffEqDocs/stable/features/callback_functions/`
    (`DiscreteCallback`/`ContinuousCallback` structure).
  - SciMLFunctions interface — `https://docs.sciml.ai/SciMLBase/stable/interfaces/SciMLFunctions/`;
    ODE types / ODEFunction fields — `https://docs.sciml.ai/DiffEqDocs/stable/types/ode_types/`.
  - Split ODE types & solvers —
    `https://docs.sciml.ai/DiffEqDocs/stable/types/split_ode_types/` and
    `https://docs.sciml.ai/DiffEqDocs/stable/solvers/split_ode_solve/` (semilinear `Au + f`;
    LawsonEuler/NorsettEuler/ETDRK; SciMLOperators).
- **Rackauckas, C. & Nie, Q. (2017).** *DifferentialEquations.jl — A Performant and Feature-Rich
  Ecosystem for Solving Differential Equations in Julia.* J. Open Res. Softw. 5(1):15,
  doi:10.5334/jors.151. PDF read pp. 1–6 (§1.1 problem/solve/plot; §1.3.1 common solve interface;
  §1.6.1 `perform_step!` + per-algorithm cache). Distinct from **Rackauckas & Nie (2019)**, *Confederated
  modular differential equation APIs…*, Advances in Engineering Software 132 — the source of the
  "confederated" phrase.
- **PETSc manual** (release, consulted 2026-07-18): TS component `https://petsc.org/release/manual/ts/`
  (F(t,u,u̇)=G(t,u); `TSSetIFunction`/`TSSetIJacobian`/`TSSetRHSFunction`/`TSSetRHSJacobian`);
  `https://petsc.org/release/manualpages/TS/TSMonitorSet/`;
  `https://petsc.org/release/manualpages/DM/DMGetWorkArray/`.
- **Gardner, D. J., Reynolds, D. R., Woodward, C. S. & Balos, C. J. (2022).** *Enabling New Flexibility
  in the SUNDIALS Suite of Nonlinear and Differential/Algebraic Equation Solvers.* ACM Trans. Math.
  Softw. 48(3), doi:10.1145/3539801. Read from arXiv:2011.10073 v2 PDF, pp. 1–8 (§2.3 ARKODE ARK/ImEx;
  §3 four base classes; §3.1 private-data anti-pattern; §3.2 VMT `void*content`+`ops`; §4 `N_Vector`
  backends; §4.1 fused operations).

### Verification ledger (seeded leads)

- ODEFunction as reified RHS — **CONFIRMED**.
- SplitFunction/SplitODEProblem for IMEX & integrating-factor/exponential; linear operator in `f₁`/`A`;
  IT's viscous factor = exact diagonal `A` — **CONFIRMED / REFINED**. `ExponentialUtilities` /
  `LinearExponential` names — **PARTIALLY VERIFIED** (referenced, pages not opened).
- init/solve!/integrator.u/.t/step! sanctioned mid-run access — **CONFIRMED**.
- `u_modified!(integrator, true)` as the explicit invalidation verb; semantics (recalculate
  interpolation) — **CONFIRMED**; plus **REFINED**: renamed to `derivative_discontinuity!` on master,
  `u_modified!` now a deprecated alias.
- `alg_cache` dispatching on algorithm type = IT's `allocate_buffers` — **CONFIRMED**.
- Callback system as observation layer — **CONFIRMED** (`DiscreteCallback`/`ContinuousCallback`);
  `SavingCallback` name — **PARTIALLY VERIFIED**.
- "confederated modular API paper (Rackauckas & Nie 2017, JORS)" — **REFUTED as stated**: the JORS 2017
  paper has a different title; "confederated" is the 2019 Adv. Eng. Software paper. Cite accordingly.
- PETSc `TSSetIFunction`/`TSSetRHSFunction` split; `TSMonitor`; `DMGetWorkArray`/`DMRestoreWorkArray`
  pool — all **CONFIRMED**. `TSSetPostStep`/`TSSetPostStage` post-step hook names — **PARTIALLY
  VERIFIED**.
- SUNDIALS Gardner 2022; `N_Vector`; `SUNLinearSolver`/`SUNNonlinearSolver` strategy objects; ARKODE
  ARK splitting — all **CONFIRMED**.
- **Cross-cut finding (post-step verb question):** none of the three reify a post-step verb *on* the
  generator/RHS object; all keep the generator a pure evaluator and place post-step action in a separate
  hook/callback layer. Bears directly on IT's proposed `finalize!`.
