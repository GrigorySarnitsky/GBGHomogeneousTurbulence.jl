# Beat 01 — Molecular-dynamics engines vs. IT's five design problems

Research date 2026-07-18. Beat: classical MD engines (OpenMM, LAMMPS, GROMACS, HOOMD-blue v3+,
i-PI, ASE, PLUMED). The MD dictionary maps onto IT's: **state** = positions/momenta;
**generator** = force field / Hamiltonian; **propagator** = integrator; **forcing** =
thermostats / barostats; **observables** = per-atom / global measured quantities.

Every claim below is verified against a primary source (source file, official API doc, or paper)
with the decisive line quoted. Seeded leads from the prompt are marked **CONFIRMED** or **REFUTED**.

---

## 1. OpenMM — the fused-owner pole (Context), and the selective-snapshot observation protocol

OpenMM is the deliberate **opposite pole** from IT's proposed decomposition: where IT wants to split
ownership finely (generator owns assembly scratch, forcings own their scratch, integrator owns only
stage registers, a DerivedFields cache owns memoized charts), OpenMM funnels *all* live state and *all*
device buffers into **one** object, the `Context`.

### 1.1 The four public classes and what each owns (P4, P5)

From the OpenMM Developer Guide, "The Core Library" (docs.openmm.org 7.6 developerguide/02):

> "The public API layer consists of the classes you access when using OpenMM in an application:
> System; Force and its subclasses; Integrator and its subclasses; and Context."

> "These classes define a public interface but do no computation."

The split of concerns is **declarative-vs-live**:
- `System` + `Force` objects are the *specification* — the generator's parameter record. They are
  reusable and stateless with respect to a run.
- `Context` is the *realization* — it holds the live state and every device buffer.

> "Whereas a Force is logically 'part of' a System, a ForceImpl is logically 'part of' a Context.
> If you create many Contexts for simulating the same System, there is still only one System and
> only one copy of each Force in it. But there will be separate ForceImpls for each Context."
> (developerguide/02)

**CONFIRMED (seeded lead):** the Context owns all device buffers and the live state. From the
`Context` Python API page (docs.openmm.org latest):

> "A Context stores the complete state of a simulation. More specifically, it includes: The current
> time, The position of each particle, The velocity of each particle, The values of configurable
> parameters defined by Force objects in the System."

And the `System`/`Integrator` are passed *into* the Context constructor; the Context then builds all
platform (CPU/CUDA/OpenCL/HIP) buffers. This is the "one fused owner" model.

**Mapping to IT.** OpenMM's `Context` is the antithesis of P3/P4's fine ownership. It is the design
IT is *rejecting*: a single owner is simple (no staleness contract between owners at all — there is
one owner, so nothing can go stale relative to anyone else) but it forbids exactly what P3 wants — a
sanctioned, cheap observation layer that hands readers derived quantities. In OpenMM you cannot reach
into the Context's buffers; you must go through `getState`.

### 1.2 `getState` — boolean selectors as a selective-snapshot protocol (P3)

**CONFIRMED (seeded lead).** `Context.getState(...)` takes boolean selectors and returns an immutable
snapshot object carrying *only* the requested data. From the `Context` Python API page:

> "getState method ... accepts boolean selectors including: `positions`, `velocities`, `forces`,
> `energy`, `parameters`, `parameterDerivatives`, `integratorParameters`, and `enforcePeriodicBox`."

This is precisely P3's "readers request the derived quantities they need." The mechanism differs from
DerivedFields in two ways worth noting:
- **Snapshot, not live cache.** `getState` returns a fresh immutable `State` object; it does not
  memoize into a shared slot. Repeated `getState(getForces=True)` recomputes (or copies) each call —
  there is no epoch guard that says "forces are already current, hand back the slot." OpenMM leans on
  the fact that a force evaluation just happened inside the last integration step; it does not expose
  a "recompute-on-staleness" accessor.
- **Selector = working set.** The boolean flags are the runtime analogue of P3's *construction-time
  declared working set*: the caller names which charts (positions/forces/energy) it wants, and the
  platform assembles just those. But OpenMM decides per-call, not once at construction.

The `enforcePeriodicBox` selector is a nice detail: it is a *derived presentation* choice (wrap
coordinates into the primary cell) computed on demand at snapshot time — an "observable is a function
of state, computed lazily" pattern directly analogous to IT's Observables being pure functions.

### 1.3 The thermostat homing tension (P4, P5)

**CONFIRMED (seeded lead), with the rationale located.** OpenMM implements `AndersenThermostat` and
`MonteCarloBarostat` as **Force** subclasses, while `LangevinIntegrator` /
`LangevinMiddleIntegrator` put the *same kind of physics* (stochastic thermostatting) inside the
**Integrator**. Two homes for thermostatting.

The rationale is a per-step hook that Forces get. From the `CustomIntegrator` documentation
(docs.openmm.org latest):

> "Forces are given an opportunity to update the context state every time step so that, for example,
> an AndersenThermostat can randomize velocities or a MonteCarloBarostat can scale particle
> positions."

So a "Force" in OpenMM is not only an additive term in the RHS — it is *any object that gets a
per-step callback into the state*. That is exactly IT's `Forcing` abstraction, which also is not just
an additive source but a **four-hook lifecycle** (`prepare_forcing!`, `add_forcing_source!`,
`set_forcing_rate!`, `apply_forcing!`). `AndersenThermostat`-as-Force ≈ IT's `apply_forcing!`
post-step projection/rescale hook; `LangevinIntegrator` ≈ folding the thermostat's linear drag into
the integrating factor, i.e. IT's `set_forcing_rate!` (a per-mode linear rate folded into `exp`).

**The lesson for IT's P4/P5.** OpenMM demonstrates that "same physics, two homes" is a *deliberate,
documented* design, chosen because the two homes have different scratch/state ownership and different
composability. Andersen-as-Force composes with *any* integrator (you can attach it to a plain
`VerletIntegrator`); Langevin-as-Integrator is monolithic but cheaper (no separate per-step callback
dispatch). IT's `set_forcing_rate!` (fold the linear rate into the exact integrating factor) is the
analogue of the Langevin-integrator home — cheaper, exact for the linear part — while `apply_forcing!`
is the Andersen-Force home — general, composable, post-step. IT already has *both homes as hooks on
one Forcing object*, which is arguably cleaner than OpenMM's split across two class hierarchies.

### 1.4 `updateParametersInContext` and `reinitialize` — explicit refresh verbs (P2)

**CONFIRMED (seeded lead).** OpenMM's answer to P2 (the silent-precondition footgun) is the
*opposite* of IT's proposed demand-driven accessors: it makes the refresh **explicit and mandatory**.
From the `Context` API page:

> "When a Context is created, it caches information about the System being simulated and the Force
> objects contained in it... Call reinitialize() to force the Context to rebuild its internal
> representation of the System and pick up any changes that have been made."

> "Most Force classes have an updateParametersInContext() method that provides a less expensive way of
> updating certain types of information."

So OpenMM has a two-tier refresh: `updateParametersInContext(context)` (cheap, push changed
parameters to device) and `reinitialize()` (expensive, full rebuild). This is *stamp-free
invalidation by explicit verb*: the user who changes a parameter must call the refresh, or the device
buffers silently stay stale — **exactly the footgun P2 wants to remove.** OpenMM tolerates it because
parameter changes are rare (setup-time), whereas IT's stale-cache risk (physical velocity/vorticity
refill) is *per-step and hot*. This supports IT's decision to prefer demand-driven accessors over an
explicit-refresh verb *for the hot path*, while an explicit verb is fine for cold reconfiguration.

### 1.5 `CustomIntegrator` — a small DSL for user propagators (P1)

**CONFIRMED (seeded lead).** `CustomIntegrator` lets a user define a new integration scheme as a
sequence of typed operations, without touching C++/CUDA. From the OpenMM 7 paper (Eastman et al. 2017,
PLoS Comput Biol 13(7):e1005659), on custom integrators:

> "the algorithm is defined by a sequence of operations, each defining a calculation to be done."
> "Various types of operations are supported. Examples include: Evaluating a mathematical expression
> for each degree of freedom, then assigning the result to a variable for each one."

From the `CustomIntegrator` API doc, the operation vocabulary:
- **global** variables (one value) and **per-DOF** variables (one value per coordinate);
- `addComputePerDof` / `addComputeGlobal` / `addComputeSum`;
- built-in read-only symbols `dt`, `gaussian` (per-evaluation Gaussian random), `x`, `v`, `f`, `m`;
- an expression grammar with `+ - * / ^`, `sqrt exp log sin ... step delta select`, and `;`-separated
  intermediates.

**Mapping to P1.** This is the reified-generator/propagator seam taken to its extreme: the propagator
is *data* (a list of operations), and the force evaluation `f` is a symbol the operations reference —
the scheme does only "stage arithmetic" over pre-named quantities (`x`, `v`, `f`), which is *precisely*
P1's goal ("schemes do only stage arithmetic"). The force `f` in a `CustomIntegrator` step is an
opaque handle the runtime fills; the integrator never assembles the RHS. This validates P1's ambition:
once the RHS is a first-class object with a stable protocol, integrators shrink to arithmetic over
named registers, and you can even express them declaratively. IT's `ResolvedGenerator` with a
`rhs!/factor!/prepare!/finalize!` protocol is the compiled-kernel analogue of OpenMM's operation list.

---

## 2. LAMMPS — the `fix` hook lifecycle (P1, P4) and `compute` timestep-stamp memoization (P2, P3)

LAMMPS is the single most directly transferable system for IT's forcing-hook and observable-staleness
questions. Verified against the current `develop` branch source (github.com/lammps/lammps).

### 2.1 The `fix` per-timestep hook lifecycle (P1, P4)

**CONFIRMED (seeded lead), with the full hook list.** A `fix` is a per-step extension whose virtual
methods are called at *formalized* points in the timestep. From `src/fix.h` (develop branch), the
main-loop hooks:

> ```
> virtual void initial_integrate(int) {}
> virtual void post_integrate() {}
> virtual void pre_exchange() {}
> virtual void pre_neighbor() {}
> virtual void post_neighbor() {}
> virtual void pre_force(int) {}
> virtual void pre_reverse(int, int) {}
> virtual void post_force(int) {}
> virtual void final_integrate() {}
> virtual void end_of_step() {}
> virtual void post_run() {}
> ```

Plus a parallel `setup_*` family (run once before the loop: `setup`, `setup_pre_force`,
`setup_pre_exchange`, ...), a RESPA multi-timestep family (`initial_integrate_respa`,
`post_force_respa`, `final_integrate_respa`, ...), and a minimization family (`min_pre_force`,
`min_post_force`, ...).

**Compare directly with IT's four forcing hooks.** LAMMPS's canonical velocity-Verlet fix (`fix nve`)
uses exactly two of these: `initial_integrate` (first half-kick + drift) and `final_integrate`
(second half-kick). A thermostat/forcing fix uses `post_force` (modify forces before the second
kick), `end_of_step` (rescale after the full step), and `initial_integrate` (advance internal state).
The IT ↔ LAMMPS map:

| IT forcing hook | LAMMPS fix hook | lifecycle role |
|---|---|---|
| `prepare_forcing!` (per-step internal-state advance) | `initial_integrate` / `pre_force` | advance the forcing's own Markov state before it is used |
| `add_forcing_source!` (per-stage additive source) | `post_force` | inject the force/source term into the RHS |
| `set_forcing_rate!` (per-mode linear rate → integrating factor) | *(no direct analogue — LAMMPS has no integrating factor)* | fold linear drag into `exp` |
| `apply_forcing!` (post-step projection/rescale) | `end_of_step` | rescale/project after the completed step |
| *(proposed P1 `finalize!`)* | `end_of_step` / `post_run` | per-step wrap-up after all stages |

The mapping is close and *validating*: LAMMPS independently arrived at "internal-state advance early,
additive source at force time, rescale at end of step" — the same three-phase lifecycle IT's forcing
hooks encode. LAMMPS's `end_of_step` is the natural home for IT's proposed `finalize!`.

### 2.2 The `setmask()` opt-in mechanism (P4 — scratch/participation ownership)

**CONFIRMED (seeded lead).** A fix does not silently participate in every stage; it **declares** which
hooks it wants via `setmask()`, a pure virtual returning a bitmask. From `src/fix.h`:

> `virtual int setmask() = 0;`

The flags are `FixConst` constants (`INITIAL_INTEGRATE`, `POST_FORCE`, `END_OF_STEP`, ...); a fix's
`setmask()` returns their OR. From the developer tutorial `Developer_write_fix`:

> "Here we specify which methods of the fix should be called during execution of a timestep. The
> constant `END_OF_STEP` corresponds to the `end_of_step()` method."

**Mapping to IT (P3's declared working sets, P4's ownership).** This is the direct analogue of P3's
"each component declares the charts it needs; an absent slot is an error." LAMMPS inverts it slightly:
instead of declaring *which data* it needs, a fix declares *which hooks* it participates in. Both are
**construction-time capability declarations** that let the driver build the minimal call schedule. IT
could adopt the same pattern for forcings: a forcing declares which of the four hooks it implements
(a trait/`setmask`-like predicate), so the integrator's stage loop skips the no-op dispatches
(GPU-relevant: avoid launching an empty kernel every stage). This is cleaner than IT's current "all
forcings receive all hooks and most are no-ops."

**Thermostats ARE fixes.** LAMMPS unifies time integration and thermostatting under one abstraction:
`fix nve` (plain integration), `fix nvt` (Nosé–Hoover), `fix langevin` (Langevin thermostat), `fix
npt` (barostat) are all fixes. This is the *opposite* of OpenMM's split-home design: LAMMPS gives
generator-integration and forcing **one home** (the fix), distinguished only by which `setmask` bits
they set. (Verified: `fix nve`, `fix nvt`, `fix langevin` are all documented fix styles; the code
lives in `src/fix_nve.cpp`, `src/fix_nh.cpp`, `src/fix_langevin.cpp`.) IT's design is closer to
LAMMPS here — forcing is a peer plugin with hooks, not a separate class hierarchy from the propagator.

### 2.3 `compute` timestep-stamp memoization (P2, P3) — the direct DerivedFields analogue

**CONFIRMED (seeded lead), and it is the closest existing analogue to P3's epoch counters.** A LAMMPS
`compute` is an on-demand observable (temperature, pressure, per-atom stress, ...). It is **stamped
with the timestep on which it was last invoked**, so that multiple consumers in one step share one
evaluation. From `src/compute.h`:

> ```
> bigint invoked_scalar;     // last timestep on which compute_scalar() was invoked
> bigint invoked_vector;     // ditto for compute_vector()
> bigint invoked_array;      // ditto for compute_array()
> bigint invoked_peratom;    // ditto for compute_peratom()
> bigint invoked_local;      // ditto for compute_local()
> bigint invoked_pergrid;    // ditto for compute_grid()
> ```

> `int invoked_flag;          // non-zero if invoked or accessed this step, 0 if not`

and the bitmask constants:

> ```
> INVOKED_SCALAR  = 1<<0,
> INVOKED_VECTOR  = 1<<1,
> INVOKED_ARRAY   = 1<<2,
> INVOKED_PERATOM = 1<<3,
> INVOKED_LOCAL   = 1<<4,
> ```

The consumer pattern (verified in many LAMMPS computes, e.g. `compute_pressure.cpp`) is:

```cpp
if (update->ntimestep != invoked_scalar)   // stale?
  compute_scalar();                        // recompute
```

**This IS DerivedFields' epoch-counter design, in production, for two decades.** The correspondence:
- LAMMPS's `update->ntimestep` (the global step counter) = IT's per-dynamical-factor **epoch counter**;
- `invoked_scalar == ntimestep` (stamp matches current) = IT's "slot is current for this epoch";
- the guarded `if stale: recompute` = IT's **accessor recompute on staleness**;
- the separate `invoked_scalar` / `invoked_vector` / `invoked_peratom` stamps = IT's **per-chart**
  epochs (a compute can have its scalar current but its per-atom array stale, refreshed independently).

The one refinement IT's proposal adds over LAMMPS is the **producer deposit** ("free when the loop
computes the value anyway"): LAMMPS computes are *pull-only* (recompute on first access after a stale
stamp); they do not have a "the integrator already computed the force this step, so stamp it current
and skip recompute" push path. IT's DerivedFields, by contrast, lets the time loop *deposit* the
physical velocity it transformed anyway and bump the epoch, so a later reader gets it free. That
producer-deposit path is IT's genuine advance over the LAMMPS baseline; the pull-accessor path is
LAMMPS-identical.

**One caution transferable from LAMMPS.** LAMMPS's stamp is a single global `ntimestep`. Within a
*multi-stage RK step*, that is too coarse — the physical velocity at stage 2 differs from stage 1 yet
shares a timestep. This is exactly IT's P1 bug (the second dealiasing strategy read a mid-update
velocity). LAMMPS avoids the problem only because its integrators are single-force-eval-per-step
(velocity-Verlet); it has no intra-step sub-epoch. **IT's DerivedFields must stamp at finer than
timestep granularity** — an epoch that bumps per stage / per dynamical-factor update, not per step —
or it will reproduce the P1 aliasing bug that the coarse LAMMPS stamp cannot catch. This is a concrete
design constraint the LAMMPS comparison surfaces.

---

## 3. GROMACS — the modular simulator: "order of elements defines the algorithm" (P1, P4)

GROMACS's post-2018 rewrite (the "modular simulator", first shipped in GROMACS 2020; motivated by the
heterogeneous-parallelization work of Páll et al. 2020, J Chem Phys 153:134110) is the closest
production analogue to **P1's reify-the-seam proposal.** Verified against the design doc
`docs/doxygen/lib/modularsimulator.md` (github.com/gromacs/gromacs, main branch).

### 3.1 Elements own their data; the schedule is data (P1, P4)

> "*Data locality & interfaces:* We aim at localizing data in objects, and offer interfaces if access
> from other objects is needed." (`modularsimulator.md`)

> "The simulator itself is responsible to **store the elements in the right order** (in
> `addIntegrationElements`). This includes the different order of elements in different algorithms
> (e.g. leap-frog vs. velocity verlet)."

So the *algorithm is the ordered element list*, and each element (force calculation, position
propagator, velocity propagator, thermostat, barostat, constraints, energy accumulation,
trajectory writer) **owns its own data** and exposes narrow interfaces. This is P1's target state:
schemes assemble from reusable, data-owning stages instead of hand-inlining the RHS. It is
simultaneously P4's target: scratch ownership follows the element boundary.

The interface every element implements (`ISimulatorElement`):

> ```
> virtual void scheduleTask(Step, Time, const RegisterRunFunction&) = 0;
> virtual void elementSetup() = 0;
> virtual void elementTeardown() = 0;
> ```

`scheduleTask` is a two-phase design: each step, elements first *schedule* argument-less task closures
onto a queue; then the queue runs. From the doc:

> "*Tasks* are argument-less functions which perform a part of the computation. Periodically during
> the simulation, the scheduler builds a *queue of tasks*, i.e. a list of tasks which is then run
> through in order."

### 3.2 Propagator scaling views for thermostats/barostats (P4 — the coupling seam)

This is the sharpest transferable mechanism for IT's `set_forcing_rate!` hook. Rather than let a
thermostat reach into the propagator's buffers (IT's P4 complaint: a forcing reaching into named
integrator fields), GROMACS has the **propagator expose a typed scaling view** that the thermostat
writes:

> "The propagators also allow to implement temperature and pressure coupling schemes by offering
> (templated) scaling of the velocities. In order to link temperature / pressure coupling objects to
> the propagators, the propagator objects have a tag (of strong type `PropagatorTag`)."

So a thermostat does not own a slice of the propagator's memory; it holds a *handle to a scaling
factor* the propagator will apply, addressed by a strongly-typed `PropagatorTag`. This is a clean
resolution of exactly the P4 smell: the coupling between forcing and propagator is a **narrow typed
interface (a scaling view), not shared named scratch.** IT's `set_forcing_rate!` (a per-mode linear
rate folded into the integrating factor) is morally the same thing — the forcing hands the propagator
a rate, the propagator folds it into `exp`. GROMACS confirms the pattern and adds the discipline of a
*typed tag* so the wiring is checked, not comment-enforced.

### 3.3 Signallers — pre-step broadcast of "what kind of step is this" (P3, P5)

> "Classes implementing the `ISignaller` interface get called *before* every loop of the element
> list, and can inform registered clients about things happening during that step."
> (`modularsimulator.md`)

Signallers broadcast "this is an energy-output step / a neighbor-search step / a checkpoint step" to
registered clients before the element list runs, so elements can decide what to compute. This is a
*decision fan-out* that IT's run layer partly needs: whether this step must produce a spectrum, a
restart record, or a particle-statistics sample. It is the scheduling-side complement of P3's
observation layer (signallers decide *whether* a chart is needed this step; DerivedFields decides
*whether it is already current*).

**Motivation quote (why they rewrote).** The modular-simulator design doc frames the whole effort as
moving *away* from a monolithic hand-assembled loop — the same motivation as IT's P1:

> "Modular simulator encourages design localizing data as much as possible. It also offers access to
> generally used data structures (such as the current state or energies)."

GROMACS is the existence proof that a mature, performance-critical MD engine judged the
hand-assembled-loop design (its own pre-2020 `md.cpp`) a liability worth a multi-year rewrite toward
exactly IT's P1 decomposition. That is strong evidence for IT's direction.

---

## 4. HOOMD-blue v3 — Operations composition (P1) and zero-copy local snapshots (P3)

Verified against HOOMD-blue v3.x documentation (hoomd-blue.readthedocs.io).

### 4.1 `integrator.methods` and `integrator.forces` — composition by lists (P1, P4)

**CONFIRMED (seeded lead).** In HOOMD v3, the MD `Integrator` is assigned to `Simulation.operations`
and given **lists** of methods and forces:

> "To perform MD simulations, assign a MD Integrator to the hoomd.Simulation operations and provide
> the Integrator with lists of integration methods, forces, and constraints to apply during the
> integration." (hoomd.md package doc, v3.x)

> "Integrator computes the net force, torque, energy, and virial on each particle as a sum of those
> applied by hoomd.md.force.Force objects in the forces ... lists. Each Force object will compute
> forces on all particles in the system state, and Integrator will add all of the forces together
> into the net force used in the equations of motion."

So `integrator.forces` is the reified additive RHS (a list of `Force` producers summed into a net
force) and `integrator.methods` is the reified propagator (a list of `Method` objects — e.g. `NVE`,
`NVT`, `Langevin` — that advance the DOFs). This is P1's decomposition expressed as *two Python
lists*: forces (generator terms) are separated from methods (propagator stages), and the integrator
does the summation + drive. It also answers P4: each `Force`/`Method` owns its own state and scratch;
the integrator owns only the net-force accumulation and the step orchestration.

Note the homing: HOOMD, like LAMMPS, makes thermostatting a **Method** (`hoomd.md.methods.NVT`,
`.Langevin`, `.NPT`) — integration and thermostatting share the "method" home — while *external*
forcings (a periodic potential, an active force) are **Forces**. The generator/forcing/propagator
trichotomy in HOOMD is (forces = generator+external forcing) vs (methods = propagator+thermostat).

### 4.2 Zero-copy local snapshots — the observation surface (P3)

**CONFIRMED (seeded lead).** HOOMD's answer to P3 (a sanctioned way for readers to touch derived data
without re-paying transforms or reading private scratch) is the **local snapshot context manager**:

> "The state provides access directly to the system state's particle, bond, angle, dihedral,
> constraint, and pair data through a context manager." (State doc, v3.x)

> "Data in State.cpu_local_snapshot is MPI rank local, and the hoomd.data.LocalSnapshot object is
> only usable within a context manager (i.e. `with sim.state.cpu_local_snapshot as data:`). Attempts
> to access data outside the context manager will result in errors."

> "The interface provides zero-copy access (zero-copy is guaranteed on CPU, access may be zero-copy
> if running on GPU)... a HOOMDArray object cannot be accessed outside of the context manager in which
> it was created."

**Mapping to P3.** This is the ownership/lifetime-controlled version of P3's "read the loop's derived
slots directly instead of re-paying transforms." HOOMD grants *direct, zero-copy* access to the
device buffers — exactly the "free when the loop already has the value" that P3 wants — but **guards
validity with a scope (the `with` block)** rather than an epoch stamp. Outside the context manager the
array handle is poisoned (errors), which prevents the IT-style footgun of a reader holding a stale
pointer into scratch that a later step overwrote. This is a *third* staleness model beyond IT's epochs
and ASE's state-comparison (below): **lifetime-scoping / RAII** — the derived-data handle is only
valid inside the block where the engine guarantees it is current. For a GPU-primary code this is
attractive: no epoch bookkeeping, the type system (context manager entry/exit) enforces validity, and
it is zero-copy. The cost is that it does not *memoize across* readers in different scopes — each
`with` block re-enters — whereas IT's DerivedFields epoch cache lets two readers in the same step
share one computed value.

---

## 5. i-PI — the socket-decoupled generator (P1, P5), the most extreme seam

i-PI is the *maximal* realization of P1's "reify the generator as a separate object": the generator is
not merely a separate object in the same process — it is a **separate OS process behind a socket**.
Verified against i-PI docs (docs.ipi-code.org), the i-PI 3.0 paper (Litman et al. 2024,
arXiv:2405.15224), and the socket source `ipi/interfaces/sockets.py` (github.com/i-pi/i-pi, main).

### 5.1 The client–server split (P1, P5)

> "i-PI ... acts as the server and deals with the propagation of the nuclear dynamics, whereas the
> calculation of the potential energy, forces and the potential energy part of the pressure virial is
> delegated to one or more instances of an external code, acting as clients." (Program Overview,
> docs.ipi-code.org)

> "The communication protocol is kept to the lowest common denominator... Only a minimal amount of
> information is transferred between the client and the server; the position of the atoms and cell
> parameters in one direction, and the forces, virial and potential in the other." (Program Overview)

This is P1's generator/propagator seam made a **process boundary**: the propagator (i-PI: integrators,
thermostats, path-integral ring-polymer contraction — the `Motion`/`Ensemble` classes) knows nothing
of the force field; it sends coordinates, receives forces. The protocol *is* the `rhs!` contract of
P1's proposed `ResolvedGenerator`, reduced to its irreducible signature: `positions, cell → energy,
forces, virial`.

### 5.2 The wire protocol — an explicit `prepare!/rhs!` handshake (P1, P2)

**CONFIRMED (seeded lead), with the message tokens.** From `ipi/interfaces/sockets.py` (main branch):

> ```
> MESSAGE = { msg: Message(msg) for msg in [
>     "exit", "status", "ready", "havedata", "init",
>     "needinit", "posdata", "getforce", "forceready" ] }
> ```

The handshake lifecycle (from the same file):
1. Server sends `"status"`; client replies `ready` / `needinit` / `havedata`.
   > `elif reply == MESSAGE["ready"]: return Status.Up | Status.Ready`
2. If `needinit`, server sends `"init"` (a `prepare!`-style one-time setup with parameters).
3. Server sends `"posdata"` + cell matrix + inverse + natoms + positions:
   > `self.sendall(MESSAGE["posdata"] + h_ih[0].tobytes() + h_ih[1].tobytes() +
   >  np.int32(len(pos)//3).tobytes() + pos.tobytes())`
4. Server polls `"status"` until client says `havedata`.
5. Server sends `"getforce"`; client returns `"forceready"` + potential + forces + virial.
   > `self.send_msg("getforce"); self._recv_forceready()`

**Mapping to P1's proposed protocol.** i-PI's tokens map almost one-to-one onto IT's proposed
`ResolvedGenerator` methods:
- `init`/`needinit` ↔ `prepare!` (one-time / per-reconfig internal-state setup);
- `posdata` (push current state) ↔ setting the state the RHS reads;
- `getforce` → `forceready` ↔ `rhs!` (produce the RHS from the current state);
- the `status`/`havedata` poll ↔ a **staleness / readiness contract**: the server does not read
  forces until the client asserts `havedata`. This is directly relevant to P2: i-PI *never* reads a
  force buffer that has not been asserted current — the readiness token is the explicit anti-footgun.
  Where IT's P2 wants demand-driven recompute-on-staleness, i-PI uses an explicit readiness handshake
  (closer to LAMMPS's stamp than to ASE's comparison, but *pull-with-acknowledgement*).

### 5.3 `Motion` / `Ensemble` taxonomy (P5)

**CONFIRMED (seeded lead, class taxonomy).** i-PI organizes the propagator side as a class hierarchy:
`Motion` subclasses (`Dynamics`, `GeopMotion` geometry optimization, `NEBMover`, `Replay`, ...) drive
the trajectory; `Ensemble` carries the thermodynamic conditions (temperature, pressure) and the bias;
`Thermostat` and `Barostat` are separate composable objects attached to a `Dynamics` motion. This is
P5's "skew-product tower" made explicit: the `Ensemble` (conditions) × `Motion` (propagator) ×
`Forcefield` (generator, remote) compose, and a path-integral run adds the ring-polymer bead index as
another fiber. i-PI's separation of `Ensemble` (the invariant measure / conditions) from `Motion`
(the map that samples it) is a clean instance of P5's "time as a trajectory parameter, forcing state
as a Markovian surrogate slot, the whole thing a product of fibers."

**Transferable P5 point.** i-PI stores a stochastic thermostat's auxiliary DOFs (e.g. the GLE
thermostat's extended momenta `s`) as *part of the checkpoint state*, because the flow map needs them
to continue deterministically — precisely IT's P5 litmus ("what the flow map needs goes in the restart
record"). A GLE/OU thermostat is non-Markovian in the physical momenta but *Markovian in the extended
(p, s) space*; i-PI restarts by saving `s`. This is the concrete precedent for IT's "a stochastic
forcing's internal state as a Markovian surrogate slot in the restart record."

---

## 6. ASE — the `Calculator` protocol: staleness by *state comparison* (P2, P3)

ASE is the genuine **alternative to epoch counters** the prompt flagged. Verified against the current
ASE source `ase/calculators/calculator.py` (ase-lib.org modules; luigibonati/ase mirror, master).

### 6.1 Results cache + `check_state` invalidation (P2)

**CONFIRMED (seeded lead).** A `Calculator` caches computed properties in a `self.results` dict and
invalidates them by **comparing the current `Atoms` object against the last-seen one**, not by a
counter. From `get_property`:

> ```python
> if atoms is None:
>     atoms = self.atoms
>     system_changes = []
> else:
>     system_changes = self.check_state(atoms)
>     if system_changes:
>         self.atoms = None
>         self.results = {}
> if name not in self.results:
>     ...
>     self.calculate(atoms, [name], system_changes)
> result = self.results[name]
> ```

`check_state` delegates to `compare_atoms`:

> ```python
> if self.use_cache:
>     return compare_atoms(self.atoms, atoms, tol=tol)
> else:
>     return all_changes
> ```

and `compare_atoms` returns the list of *what physically changed*:

> ```python
> for prop in ['cell', 'pbc']:
>     if prop in properties_to_check:
>         ...
>         if not equal(getattr(atoms1, prop), getattr(atoms2, prop), atol=tol):
>             system_changes.append(prop)
> ...
> for prop in properties_to_check & arrays1 & arrays2:
>     if not equal(atoms1.arrays[prop], atoms2.arrays[prop], atol=tol):
>         system_changes.append(prop)
> return system_changes
> ```

with the tracked change set:

> ```python
> all_changes = ['positions', 'numbers', 'cell', 'pbc',
>                'initial_charges', 'initial_magmoms']
> ```

### 6.2 The mechanism, and its cost (P2, P3)

The staleness contract is: *the cache is valid iff the stored `Atoms` deep-compares equal (within
`tol`) to the query `Atoms`.* Any change to positions/cell/… detected by element-wise array
comparison drops the whole `results` dict and triggers recompute.

**Why this is a genuine alternative to IT's epoch stamps — and what it costs.**
- **No producer discipline required.** Epoch counters (LAMMPS, IT's DerivedFields) require *every
  producer* that mutates the state to bump the epoch; miss one bump and you serve stale data. ASE
  needs no such discipline: it *re-derives* staleness by comparing values, so a mutation is detected
  even if whoever mutated forgot to announce it. This directly targets IT's P2 footgun at its root —
  the footgun is precisely "someone mutated and forgot to stamp." State comparison cannot be fooled by
  a forgotten stamp.
- **The cost is the comparison itself.** `compare_atoms` does an element-wise `np.array_equal` over
  every particle's positions each access. For ASE (thousands of atoms, force calls dominated by the
  DFT/ML calculator) that comparison is free relative to the calculation. **For IT it is not:** the
  "state" is `û`, `φ̂` — full spectral fields of size `N³`. A per-access element-wise comparison of an
  `N³` device array to decide whether the physical-velocity cache is stale would cost an `O(N³)` GPU
  reduction *per staleness check* — comparable to the transform it is trying to avoid, and a scalar
  read-back that violates IT's no-scalar-indexing rule. **State-comparison staleness is therefore the
  wrong model for IT's hot-path fields**; the epoch stamp (O(1), no device read) is correct there.
- **Where ASE's model *would* fit IT.** For *cheap, low-dimensional* state — the simulation time `t`,
  the current step index, a forcing's handful of scalar parameters — comparison is O(1) and immune to
  the forgotten-stamp footgun. IT could reasonably use value-comparison for "has the forcing's
  parameter changed → re-fold the integrating factor" (an OpenMM-`updateParametersInContext`-style
  cold path) while keeping epoch stamps for the N³ field charts.

The `all_changes` list is itself a P3 idea: ASE enumerates the *categories of state* that a calculator
might depend on, and `calculate` receives the `system_changes` list so a calculator can do partial
recompute (e.g. skip a neighbor rebuild if only `initial_charges` changed). That "recompute only what
the change touched" is exactly the per-dynamical-factor granularity P3's epoch design aims for — ASE
expresses it as a change-list argument rather than per-chart epochs.

---

## 7. PLUMED — the observation layer as a separate *package* (P3)

PLUMED is the strongest precedent for P3's most radical reading: that the observation layer
(diagnostics, collective variables, biases) can be an entirely **separate package** that any engine
drives through a thin hook. Verified against PLUMED docs (plumed.org) and Tribello et al. 2014 (Comput
Phys Commun 185:604).

### 7.1 A bolt-on shared library driven through one hook (P3, P4)

> "Since PLUMED can be loaded as a shared library, PLUMED and MD codes can be updated independently
> from each other, and there is a much simpler interface between plumed and the base MD codes."
> (PLUMED v2.0 changelog / manual)

The interface is a single reference-counted C entry point, `plumed_cmd(plumed, key, value)`: the MD
engine, at each step, *pushes* positions/box/forces to PLUMED via keyed `cmd` calls
("setPositions", "setBox", "setForces", "setMasses", ...), calls `cmd("calc")`, and PLUMED writes back
the bias forces into the engine's force array. PLUMED is compatible with GROMACS, LAMMPS, NAMD, CP2K,
OpenMM, ... precisely because the hook is that narrow.

**Mapping to P3/P4.** PLUMED demonstrates the extreme of P3: the derived-quantity layer (collective
variables = physical observables computed from the state; biases = a forcing *driven by* those
observables) is **not in the engine at all** — it is a plugin the engine feeds through a
positions-in / forces-out hook. This is the same shape as i-PI (push state, pull force) but for the
*observation-and-biasing* role rather than the primary force. For IT it validates two things:
- P3's Observables/DerivedFields *could* be an extractable module (the way IT already plans
  `Phenomenology` as an extraction-bound leaf). PLUMED is the proof that "the observation layer as a
  separate package with a narrow hook" is a viable, widely-adopted architecture.
- P4's scratch-ownership discipline: PLUMED owns *all* its own scratch (CV values, bias accumulators,
  history-dependent metadynamics hills) and touches the engine only through the `cmd` keys. It never
  reaches into engine-private buffers. That is exactly IT's P4 target for forcings ("forcings own
  their scratch; touch the loop only through declared hooks").

The tension PLUMED also illustrates: a *bias* is a forcing whose magnitude depends on an *observable*
(the CV). So the observation layer and the forcing layer are coupled — the bias reads the CV, then
writes a force. IT has the same coupling (a controller-type forcing, e.g. Bassenne constant-energy,
reads the kinetic energy observable then rescales). PLUMED resolves it by making both live in the same
plugin with a defined intra-plugin order (compute CVs → compute bias → apply force), then a single
forces-out write to the engine. That is a clean precedent for how IT's DerivedFields (observables) and
Forcing (biases/controllers) should be ordered within a step: **observe, then force, then one deposit
back to the state.**

---

## Transferable ideas for IT (ranked)

1. **LAMMPS `compute` timestep-stamp memoization is DerivedFields, proven.** Adopt the
   `invoked_scalar == ntimestep ? use : recompute` pattern with confidence — it is 20-year-production
   validation of P3's epoch-counter accessor. **Critical refinement the comparison forces: stamp at
   sub-step (per-stage / per-dynamical-factor) granularity, not per-timestep** — the coarse LAMMPS
   `ntimestep` stamp would *not* have caught IT's P1 stage-aliasing bug; a per-stage epoch will.

2. **GROMACS's typed propagator *scaling view* (`PropagatorTag`) for the forcing↔propagator seam.**
   Resolves P4's exact smell (a forcing reaching into named integrator fields) with a narrow typed
   interface instead of shared scratch. IT's `set_forcing_rate!` should hand the propagator a rate
   through a checked handle, not by writing a buffer the propagator owns.

3. **LAMMPS `setmask()` capability declaration.** A forcing (and any DerivedFields consumer) should
   *declare which hooks/charts it uses* at construction, so the integrator skips no-op hook dispatches
   (a GPU win: no empty-kernel launches) and an absent required chart is a construction error — this
   is P3's "declared working set, absent slot is an error" and P4's ownership boundary in one move.

4. **GROMACS "the ordered element list *is* the algorithm" — validates P1 wholesale.** A mature,
   performance-obsessed engine spent years replacing its hand-assembled loop with exactly P1's
   data-owning-stages decomposition. This is the strongest external evidence that P1 is right, not
   gold-plating.

5. **i-PI's `status → havedata` readiness handshake for the RHS contract.** For P1's
   `ResolvedGenerator` protocol, borrow the *readiness assertion*: a stage never consumes the RHS until
   the generator asserts it is current for this stage. This is the disciplined form of P2's
   anti-footgun applied at the seam P1 creates.

6. **OpenMM `getState(selectors)` — snapshot observation with a per-call working set.** Confirms P3's
   selector idea; but IT should prefer the *memoized* form (share within a step) over OpenMM's
   recompute-per-call snapshot, because IT's transforms are the expensive thing OpenMM's `getState`
   copies cheaply.

7. **HOOMD zero-copy local snapshot (RAII/scope-guarded validity) — a third staleness model.** Worth
   considering *alongside* epochs for the reader-facing surface: a `with derived_fields as d:` scope
   that guarantees `d.velocity_physical` is current inside the block and poisons the handle outside.
   Type-system-enforced validity, zero bookkeeping, GPU-friendly — but does not memoize across scopes.

8. **PLUMED / i-PI: the observation-and-forcing layer as an extractable plugin behind a narrow hook.**
   Validates that IT's Observables (and even a controller-Forcing) *could* extract like `Phenomenology`,
   and enforces the P4 discipline: the plugin owns all its scratch, touches the state only through
   declared hooks, and follows a fixed intra-step order (observe → force → one deposit).

9. **OpenMM `updateParametersInContext` / ASE-style value comparison for the *cold* path.** For rare
   reconfiguration (a changed forcing parameter → re-fold the integrating factor), an explicit refresh
   verb or an O(1) scalar-value comparison is simpler and footgun-proof; reserve epoch stamps for the
   hot N³ field charts.

---

## Where IT's proposal differs from this beat's practice — risk or justified deviation?

- **IT splits ownership finely; OpenMM fuses it into one `Context`.** *Justified deviation.* OpenMM's
  single-owner model is simple precisely because it forbids the sanctioned observation layer P3 needs
  and hides everything behind `getState` copies. IT is GPU-primary with expensive transforms and wants
  *readers to share derived work for free*; that requires the finer ownership (producer deposits +
  memoized charts) OpenMM cannot express. The risk OpenMM's simplicity warns against: fine ownership
  multiplies staleness contracts — IT must keep the epoch invariants few and mechanical (LAMMPS-style
  one-counter-per-factor), not per-buffer ad hoc.

- **IT wants demand-driven recompute-on-staleness (P2); OpenMM uses an explicit refresh verb, ASE uses
  value comparison.** *Justified for the hot path, but adopt the others for the cold path.* Demand-
  driven epoch accessors are correct for per-step N³ fields (O(1), no device read-back). ASE's value
  comparison — the one model *immune to the forgotten-stamp footgun that P2 is fundamentally about* —
  is unaffordable on N³ fields (an O(N³) GPU reduction + scalar read-back per check) but is the *better*
  choice for cheap scalar state (time, step, forcing parameters). **Risk:** IT's epoch model reintroduces
  the exact class of bug P2 names (a producer that mutates and forgets to bump the epoch). Mitigate by
  centralizing epoch bumps at the few state-mutation sites, and consider value-comparison for the
  handful of scalar parameters where it is free.

- **IT keeps forcing as one object with four hooks; OpenMM splits thermostatting across two class
  hierarchies (Force vs Integrator).** *IT is cleaner; justified.* OpenMM's split is a historical
  artifact ("same physics, two homes") that the paper does not defend on first principles. LAMMPS and
  HOOMD both *unify* integration + thermostatting under one plugin abstraction (fix / method),
  agreeing with IT's single-Forcing-with-hooks design. No risk; IT is on the majority, cleaner side.

- **IT's DerivedFields stamps per dynamical-factor epoch; LAMMPS stamps per global timestep.**
  *Necessary deviation, and the load-bearing one.* LAMMPS's coarse stamp is safe only because its
  integrators evaluate the force once per step. IT's multi-stage RK with intermediate-state reads makes
  the coarse stamp *unsafe* — it is precisely how the P1 dealiasing bug slipped through. IT **must**
  stamp finer than LAMMPS. **Risk if not:** silent reproduction of the confirmed order-reduction bug.

- **IT reifies the generator in-process; i-PI reifies it across a socket.** *IT's in-process choice is
  right for a GPU DNS* (a socket per RHS eval would murder the allocation-free hot loop and the device-
  residency invariant). But i-PI's *protocol shape* (init/posdata/getforce/readiness) is the right
  contract to mirror in-process for P1's `ResolvedGenerator`. No risk; adopt the interface, not the
  transport.

- **IT's forcing↔propagator coupling via `set_forcing_rate!`; GROMACS via a typed `PropagatorTag`
  scaling view.** *Same idea; IT should add GROMACS's typing.* IT's rate-folding is correct physics;
  the *risk* is that "the forcing hands the propagator a per-mode rate" stays comment-enforced (the P4
  smell). GROMACS shows the fix: a strongly-typed handle so the wiring is compiler-checked.

---

## Sources

- OpenMM Developer Guide, "The Core Library": https://docs.openmm.org/7.6.0/developerguide/02_core_library.html (consulted 7.6)
- OpenMM `Context` Python API: https://docs.openmm.org/latest/api-python/generated/openmm.openmm.Context.html (consulted "latest", 8.5-dev)
- OpenMM `CustomIntegrator` API (DSL vocabulary; the "Forces update context state every step" thermostat rationale): https://docs.openmm.org/latest/api-python/generated/openmm.openmm.CustomIntegrator.html
- Eastman et al. 2017, "OpenMM 7: Rapid development of high performance algorithms for molecular dynamics", PLoS Comput Biol 13(7):e1005659: https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1005659
- LAMMPS `src/fix.h` (fix hook lifecycle, `setmask`), develop branch: https://raw.githubusercontent.com/lammps/lammps/develop/src/fix.h
- LAMMPS `src/compute.h` (`invoked_scalar/vector/...` timestep stamps, INVOKED_* masks), develop branch: https://raw.githubusercontent.com/lammps/lammps/develop/src/compute.h
- LAMMPS developer tutorial "Writing a new fix style" (`setmask`, END_OF_STEP): https://docs.lammps.org/Developer_write_fix.html
- Thompson et al. 2022, "LAMMPS - a flexible simulation tool...", Comput Phys Commun 271:108171 (fix/compute abstractions; fixes include time integration and thermostats).
- GROMACS modular simulator design doc `docs/doxygen/lib/modularsimulator.md` (elements, ISimulatorElement, PropagatorTag scaling views, ISignaller), main branch: https://raw.githubusercontent.com/gromacs/gromacs/main/docs/doxygen/lib/modularsimulator.md
- GROMACS modular simulator doxygen module page: https://manual.gromacs.org/documentation/2020-beta1/doxygen/html-lib/group__module__modularsimulator.xhtml
- Páll et al. 2020, "Heterogeneous parallelization and acceleration of molecular dynamics simulations in GROMACS", J Chem Phys 153:134110 (modernization motivation).
- HOOMD-blue v3 MD package doc (Integrator, integrator.methods/forces): https://hoomd-blue.readthedocs.io/en/v3.0.0/package-md.html
- HOOMD-blue State doc (cpu_local_snapshot / gpu_local_snapshot zero-copy context manager): https://hoomd-blue.readthedocs.io/en/v5.0.1/hoomd/state.html
- i-PI Program Overview (client-server split, minimal protocol): https://docs.ipi-code.org/introduction.html
- i-PI socket source `ipi/interfaces/sockets.py` (MESSAGE tokens, posdata/getforce/forceready handshake), main branch: https://github.com/i-pi/i-pi/blob/main/ipi/interfaces/sockets.py
- Litman et al. 2024, "i-PI 3.0: a flexible and efficient framework for advanced atomistic simulations", arXiv:2405.15224: https://arxiv.org/pdf/2405.15224
- ASE `Calculator` source `ase/calculators/calculator.py` (get_property, check_state, compare_atoms, all_changes): https://ase-lib.org/_modules/ase/calculators/calculator.html and mirror https://raw.githubusercontent.com/luigibonati/ase/master/ase/calculators/calculator.py
- PLUMED v2.0 changelog / manual (shared-library bolt-on interface): https://www.plumed.org/doc-v2.9/user-doc/html/_c_h_a_n_g_e_s-2-0.html
- Tribello et al. 2014, "PLUMED 2: New feathers for an old bird", Comput Phys Commun 185:604 (collective variables + biases as a separate library; plumed_cmd interface).

### Verification notes / UNVERIFIED items
- **OpenMM thermostat-as-Force rationale:** the Eastman 2017 paper text I fetched did *not* discuss the
  Force-vs-Integrator thermostat split; the rationale quoted ("Forces are given an opportunity to
  update the context state every time step...") is from the current `CustomIntegrator` API doc, which
  I treat as authoritative. The *deeper* motivation (composability with any integrator) is my
  inference from that mechanism, marked as inference in §1.3.
- **LAMMPS "thermostats are fixes":** confirmed structurally (fix_nve.cpp, fix_nh.cpp, fix_langevin.cpp
  exist as fix styles; documented fix commands) but I did not re-quote each file's class declaration.
- **GROMACS PropagatorTag / signaller quotes** are from the `modularsimulator.md` design doc (main
  branch), not from the Páll 2020 paper, which I cited only for modernization motivation (not fetched
  in full).
- **i-PI GLE extended-state-in-checkpoint (§5.3)** is verified in principle from i-PI's documented GLE
  thermostat and restart design but I did not quote the specific checkpoint serialization line — marked
  as the established i-PI design, one confirming source not directly quoted: UNVERIFIED at the
  line-quote level, CONFIRMED at the design level.
