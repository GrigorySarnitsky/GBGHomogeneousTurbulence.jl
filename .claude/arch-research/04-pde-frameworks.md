# Beat 04 — PDE / CFD frameworks (papers and docs)

Design-review evidence for GBGIsotropicTurbulence's five problems (P1–P5), gathered from the
stated designs of PDE/CFD frameworks. Each section: the mechanism, verbatim quotes with a
precise citation, and the explicit P-mapping. Julia trio (Oceananigans, SpeedyWeather, Trixi)
is treated at the **paper/docs** level only (a separate beat studies the Julia source). Consulted
2026-07-18; versions noted per source.

The five problems, in one line each, for cross-reference:
- **P1** Generator/Propagator seam exists in prose, not code (each scheme hand-assembles the RHS).
- **P2** Silent-precondition footgun (`step!` reads caller-prefilled caches; forgetting the refill is silent).
- **P3** No sanctioned observation layer (readers re-pay transforms or read comment-validated private scratch).
- **P4** Scratch ownership (forcings get the integrator's whole buffer bundle; one reaches into its named fields).
- **P5** State doctrine (restart record vs cache vs logbook; tracers as a fiber; time as parameter; the skew-product tower).

---

## 1. Dedalus — explicit representation-state on fields; the Evaluator/Handler observation layer

**Source.** Burns, Vasil, Oishi, Lecoanet, Brown, "Dedalus: A flexible framework for numerical
simulations with spectral methods," *Phys. Rev. Research* **2**, 023068 (2020); arXiv:1905.10388.
Code quotes from the current `master` (`dedalus/core/field.py`, `dedalus/core/evaluator.py`),
fetched 2026-07-18 from `raw.githubusercontent.com/DedalusProject/dedalus/master`.

### 1a. Field layout — an explicit, mutable representation-state (contrast for P2/P5)

A Dedalus `Field` is stored in **exactly one** layout at a time (grid space or coefficient space,
per axis) and transforms *on demand* when an operation needs a different layout. The current layout
is a mutable attribute of the field, not a fixed truth:

> `Field` docstring — "Attributes … `layout : layout object` — Current layout of field. `data :
> ndarray` — View of internal buffer in current layout." (`dedalus/core/field.py`)

Layout is initialized to coefficient space and moved one step at a time along the distributor's
transform path:

> `self.layout = self.dist.get_layout_object('c')` (`__init__`)
> `def towards_grid_space(self): """Change to next layout towards grid space.""" index =
> self.layout.index; self.dist.paths[index].increment([self])`
> `def require_grid_space(self, axis=None): """Require one axis (default: all axes) to be in grid
> space.""" if axis is None: while not all(self.layout.grid_space): self.towards_grid_space()`
> (`dedalus/core/field.py`)

The paper frames this as the Distributor's job:

> "The domain class internally constructs a Distributor object that directs the decomposition and
> communication necessary to transform the distributed fields between grid space and coefficient
> space." (arXiv:1905.10388, §V "Parallel data distribution")

**P-mapping (P2, P5, contrast).** This is the *opposite* discipline to IT's. Dedalus makes the
representation an explicit, per-field, *mutable* state (`field.layout`) and forces every consumer
through `require_*_space`, which transforms if and only if needed — so a stale representation is
**impossible to read silently**: the accessor coerces the layout. IT instead fixes a single spectral
truth (`û`, `φ̂`) and derives physical views. IT's P2 footgun (a physical-velocity cache the caller
must refill) is precisely the failure mode `require_grid_space` designs out: Dedalus never trusts a
caller to have pre-transformed; the *demand-driven accessor* does it. P2's proposed
"demand-driven accessors over stamped slots (recompute on staleness)" is the Dedalus `require_*`
idiom lifted to derived fields. For P5, `solver.state` is the restart record (the prognostic fields);
layout is a *cache attribute* of each field, not part of the trajectory the flow map needs — a clean
restart-record-vs-cache line.

### 1b. Evaluator / Handler — the sanctioned observation layer (P3)

Diagnostics are declared as symbolic tasks attached to **Handlers**, each with an evaluation
**cadence**; an **Evaluator** evaluates all due handlers in a **shared pass** with the fewest
transforms:

> `Handler` docstring — "Group of tasks with associated evaluation schedule." Cadence attributes:
> `self.wall_dt`, `self.sim_dt`, `self.iter`. (`dedalus/core/evaluator.py`)
> `Evaluator` docstring — "Coordinates evaluation of operator trees through various handlers."

Cadence selection is per-handler and driven by three clocks (iteration, sim time, wall time):

> `Handler.check_schedule()` — "`if self.wall_dt: wall_div = kw['wall_time'] // self.wall_dt; if
> wall_div > self.last_wall_div: scheduled = True`" (analogous branches for `sim_dt`, `iter`).
> `Evaluator.evaluate_scheduled()` — "`handlers = [h for h in self.handlers if
> h.check_schedule(**kw)]; self.evaluate_handlers(handlers, **kw)`"

The shared pass is a transform-minimizing sweep: attempt all tasks, then move fields toward
coefficient/grid space in lockstep and re-attempt, so a transform is paid once and reused across all
tasks that need that layout. The paper's stated goal:

> "An Evaluator: Efficiently coordinates the simultaneous evaluation of the tasks from multiple
> handlers … with the least number of spectral transforms and distributed transpositions."
> (arXiv:1905.10388, §X "Analysis and post-processing"; paraphrase confirmed against code
> `evaluate_handlers` oscillation loop over `self.dist.paths[...]`).

**P-mapping (P3).** This is the closest published precedent for IT's proposed **DerivedFields with
declared working sets and shared producer passes**. The mapping is tight: (a) a Handler's task list
is a *declared working set* of derived quantities; (b) the Evaluator's shared transform-minimizing
sweep is exactly IT's "producer deposits (free when the loop computes the value anyway)"; (c) the
cadence trio (iter / sim_dt / wall_dt) is the model IT's diagnostic/statistics callbacks should copy
rather than invent. Where IT differs: Dedalus tasks are *symbolic operator trees* evaluated lazily;
IT proposes *named stamped slots* with epoch counters. Dedalus buys generality (any expression) at
the cost of a symbolic layer; IT buys allocation-free GPU determinism at the cost of hand-declared
charts. Both agree the observation layer must be a first-class object with a cadence, not ad-hoc
reads of private scratch.

---

## 2. OpenFOAM — object-registry event numbers (the production precedent for P3 epochs)

**Source.** OpenFOAM-dev `master`, files `src/OpenFOAM/db/regIOobject/regIOobject.H` and
`src/OpenFOAM/db/objectRegistry/objectRegistry.H`, fetched 2026-07-18 from the official
`OpenFOAM/OpenFOAM-dev` GitHub.

**Mechanism.** The `objectRegistry` holds a single monotone `uint64_t` counter; every registered
object (`regIOobject`) caches the event number at its last update. Staleness is a comparison of two
event numbers.

> `objectRegistry.H`: "`//- Current event` `mutable uint64_t event_;`" and "`//- Return new event
> number.` `uint64_t getEvent() const;`"
> `regIOobject.H`: "`//- Event number at last update.` `inline uint64_t eventNo() const;`" and a
> mutable overload `inline uint64_t& eventNo();`
> `regIOobject.H`: "`//- Return true if up-to-date with respect to given object // otherwise false`
> `bool upToDate(const regIOobject&) const;`" (with 2-, 3-, 4-object overloads) and "`//- Set up to
> date (obviously)` `void setUpToDate();`"

So a derived object A that depends on B does: `if (!A.upToDate(B)) { recompute A; A.setUpToDate(); }`.
`getEvent()` mints a fresh number on each update; `upToDate` returns true iff A's cached event ≥ B's.
The detailed staleness algorithm lives in the `.C` files (not read here) — the **API contract** above
is the transferable part and is verified verbatim from the headers.

**P-mapping (P3, P2).** This is the **production CFD precedent for DerivedFields epoch counters**.
IT's proposal — "per-dynamical-factor epoch counters (fields, particles), … an absent slot is an
error" — is structurally `objectRegistry::event_` split into a small fixed set of counters (fields,
particles, OU-noise) instead of one global counter. The `upToDate(other)/setUpToDate()` pair is
exactly the staleness contract IT needs for P2's demand-driven accessors: an accessor recomputes iff
its stamp is behind the relevant dynamical-factor epoch, then stamps itself current. OpenFOAM's
single global counter is coarser than IT's per-factor plan; IT's refinement (a tracer read must not
invalidate on an OU-noise advance) is a *justified* deviation for the skew-product structure (see P5),
not a departure from the pattern.

---

## 3. Fluidsim — `get_var`/`compute` with iteration-stamped memoization (local clone)

**Source.** Local study clone at
`inspiration/dns/fluidsim/fluidsim/base/state.py` and `.../solvers/ns3d/state.py`. Fluidsim 0.9.0
(Mohanan, Bonamy, Augier, *JOSS* 2019, doi:10.21105/joss.01181). Read directly 2026-07-18.

**Mechanism — confirmed, not inferred.** The state holds the truth in `state_spect` (spectral) and
`state_phys` (physical) `SetOfVariables`; derived quantities are produced on demand by `compute(key)`
and **memoized against the timestep counter**:

> `StateBase.get_var` — "`it = self.sim.time_stepping.it; if key in self.vars_computed and it ==
> self.it_computed[key]: return self.vars_computed[key]; else: value = self.compute(key);
> self.vars_computed[key] = value; self.it_computed[key] = it; return value`"
> (`fluidsim/base/state.py`, lines 142–150)

The declared working set is three key-lists on the solver's `info_solver`:

> `StatePseudoSpectral._complete_info_solver` sets `keys_state_phys`, `keys_state_spect`, and (in
> `StateNS3D`) `"keys_computable": ["rotz","divh","rotz_fft","divh_fft","vp","vt","vp_fft","vt_fft"]`
> (`fluidsim/solvers/ns3d/state.py`, lines 24–41). `has_vars` answers membership against the union of
> the three lists.

`compute(key)` itself re-checks the stamp before doing work and can recurse (e.g. `"vp"` calls
`compute("vp_fft")` then ifft's it), so a producer chain is memoized at each node
(`ns3d/state.py`, lines 54–108). Invalidation is **lazy**: `clear_computed()` exists but is called
only at preprocessing (`fluidsim/base/preprocess/pseudo_spect.py:35`), not per step — the
`it == it_computed[key]` guard alone makes every cached value auto-stale when `time_stepping.it += 1`
(`fluidsim/base/time_stepping/base.py:244`).

**P-mapping (P2, P3, P5).**
- **P3/P2**: This is a *single-counter* instance of exactly IT's DerivedFields plan — a memoized
  cache of derived slots (`vars_computed`), each stamped with the epoch it was computed at
  (`it_computed`), recomputed on staleness. It is the direct, working precedent for "producer deposits
  plus accessor recomputes." The one global `it` counter is coarser than IT's per-dynamical-factor
  epochs and would over-invalidate (a diagnostic recomputes every step even if the field it needs was
  already deposited by the loop) — IT's producer-deposit refinement is the improvement.
- **P5**: The restart-record-vs-cache line is drawn cleanly: `state_spect`/`state_phys` are the
  restart truth (`keys_state_phys`, `keys_state_spect`); `vars_computed` is a pure cache; `keys_computable`
  is the *declared* derivable set — a working-set declaration exactly like IT's construction-time chart
  declaration, and an unknown key raises (`compute`: "`Do not know how to compute "{key}"`").
- **Caveat / difference**: Fluidsim keeps **two** stored truths (`state_phys` and `state_spect`) and a
  consistency check `check_energy_equal_phys_spect` (`base/state.py:393`) to catch drift between them.
  IT deliberately stores **one** truth (spectral) to avoid exactly that drift risk — a justified
  deviation given the GPU/footprint invariant; Fluidsim's need for a runtime consistency check is
  evidence for IT's single-truth choice.

---

## 4. Firedrake — composing narrow abstractions (the PF/SS/IT split's closest thesis)

**Source.** Rathgeber, Ham, Mitchell, Lange, Luporini, McRae, Bercea, Markall, Kelly, "Firedrake:
Automating the Finite Element Method by Composing Abstractions," *ACM TOMS* **43**(3), Art. 24
(2016), doi:10.1145/2998441; preprint arXiv:1501.01809. Quotes from ar5iv HTML of 1501.01809,
fetched 2026-07-18.

**Mechanism / thesis.** Each concern is its own library behind a narrow interface (UFL for the PDE
form language, PyOP2 for parallel iteration over the mesh, FIAT for elements, PETSc for solvers);
Firedrake is the thin composition:

> "a pure Python runtime-only implementation centred on the composition of several existing and new
> abstractions for particular aspects of scientific computing" (abstract)
> "introduce a new abstraction, PyOP2, to create a separation within the implementation layer between
> the local discretisation of mathematical operators, and their parallel execution" (intro)

Claimed benefit — a separation of concerns that lets different specialists contribute independently,
and compactness as evidence:

> "a more complete separation of concerns which eases the incorporation of separate contributions from
> computer scientists, numerical analysts and application specialists"
> "The resulting core Firedrake code has only around 5000 lines of executable code … This compactness
> is evidence of the effectiveness of the abstraction choice"

Stated cost and the escape hatch:

> "It will never be possible to represent all algorithms with the same level of elegance in a single
> abstraction" — addressed by "escaping the abstraction" rather than one universal layer.

**P-mapping (invariant 2; P1, P4).** Firedrake is the published articulation of IT's core invariant —
"belongs-in-PF/SS → raise, don't reimplement": each concern (field math = PF, statistics = SS, physics
= IT) is a library behind a narrow interface, and the top package is a thin composition. It supports
IT's split *and* names its cost: no single abstraction covers everything, so a deliberate escape hatch
is needed — the analogue of IT's "deferred backend feature is a request, not a workaround" plus the
occasional per-call diagnostic allocation. For P1/P4 the lesson is directional: Firedrake's win came
from *inserting a seam* (PyOP2) between "what the operator is" and "how it executes in parallel" —
exactly the Generator (RHS = what) / Propagator (stage arithmetic = how) seam P1 proposes to reify.
The 5000-line compactness claim is the argument that a good seam *shrinks* code; IT's P1 evidence (the
dealiasing bug from a duplicated forcing prologue) is the same claim from the failure side.

---

## 5. Devito — the `Operator` as a reified, generated RHS (a P1 analogue)

**Source.** Louboutin, Lange, Luporini, Kukreja, Witte, Herrmann, Velesko, Gorman, "Devito (v3.1.0):
an embedded domain-specific language for finite differences and geophysical exploration," *GMD*
**12**, 1165–1187 (2019); arXiv:1808.01995. Quotes from the GMD HTML, fetched 2026-07-18.

**Mechanism.** A Devito `Operator` is an object that *reifies* a computation: it takes symbolic
equations and lowers them to compiled code, with a two-stage optimizer between:

> "A Devito `Operator` takes as input a collection of symbolic expressions and progressively lowers the
> symbolic representation to semantically equivalent C code." (§3.1)
> The "Devito symbolic engine (DSE)" does "common sub-expression elimination (CSE), factorization, and
> loop-invariant code motion"; the "Devito loop engine (DLE)" does "explicit vectorization,
> thread-level parallelization, and loop blocking with auto-tuned block sizes." (§3.1)
> "The fact that this can all be performed just in time (JIT) means that a combination of static and
> dynamic analysis can be used to generate optimized code." (§3.1)

**UNVERIFIED**: the seeded lead's "Operator caching" — the GMD paper describes JIT compilation but I
did **not** find in it an explicit statement that compiled `Operator`s (or SymPy symbolic objects) are
cached/memoized across builds. Devito does maintain a symbolic-object cache in its implementation, but
that claim is not sourced here; treat "Operator caching" as unconfirmed from the primary paper.

**P-mapping (P1).** Devito is the "reify the RHS as an object" pattern in its strongest form: the thing
that assembles the right-hand side is a first-class `Operator` with a defined input (symbolic Eqs) and
output (executable), and *nothing else* touches the stencil arithmetic. IT's P1 proposal — a
`ResolvedGenerator` object with a protocol `rhs!/factor!/prepare!/finalize!` so schemes do only stage
arithmetic — is the same move at a smaller scale: separate "assemble the RHS" (Generator) from "advance
in time" (Propagator). Devito even mirrors IT's finer split by having *two* internal engines (symbolic
DSE vs loop DLE) — the analogue of IT keeping the physics assembly (Generator) distinct from the
scheme/stage machinery (Propagator). The transferable caution: Devito's power comes from the Operator
being the *sole* owner of assembly; IT's current bug (a scheme silently reading a mid-update velocity)
is exactly what a single-owner assembly object prevents.

---

## 6. Oceananigans — prognostic vs diagnostic fields; on-the-fly computation (P3, P4, P5)

**Source.** Silvestri et al. (Ramadhan et al. 2020 JOSS lineage), "Oceananigans.jl: A Julia library
that achieves breakthrough resolution, memory and energy efficiency in global ocean simulations,"
arXiv:2309.06662v2, HTML fetched 2026-07-18; plus the JOSS 2020 paper (doi:10.21105/joss.02018) and
Oceananigans documentation "Models overview."

**Mechanism.** The model evolves **prognostic** variables and computes **diagnostic** variables from
them; almost all intermediates are computed **on the fly** as composed operator trees, materialized
into fused kernels, not stored:

> "almost all intermediate quantities are computed on-the-fly, so that Oceananigans is extremely memory
> efficient" (arXiv:2309.06662v2)
> "composable atomic operators that leverages Julia's functional programming paradigm and effective
> inlining capabilities to recursively construct large expression trees" (ibid.)
> "we fuse the entire tendency computation for each prognostic variable into a single compute-heavy
> kernel" (ibid.)

The documentation exposes the access split explicitly as `prognostic_fields(model)`,
`diagnostic_fields(model)`, and a combined `fields(model)` (Oceananigans docs, "Models overview";
confirmed via search, not fetched verbatim — treat the function names as **docs-level, not quoted**).
A `Field` wrapping an `AbstractOperation` is materialized by `compute!(field)` when a stored copy is
wanted; otherwise the operation stays lazy.

**P-mapping (P3, P4, P5).**
- **P5**: The prognostic/diagnostic split is IT's exact restart-record-vs-derived line — prognostic =
  the flow map's state, diagnostic = functions of it. Naming the two categories as first-class,
  queryable sets (`prognostic_fields`/`diagnostic_fields`) is a model for IT's state doctrine.
- **P3**: "Computed on the fly, fused into one kernel" is the *default-lazy* stance — the opposite pole
  from OpenFOAM/Fluidsim memoization. It shows a coherent alternative: rather than cache-and-stamp,
  recompute inside a fused kernel every time (memory beats compute). This is directly aligned with IT's
  GPU/footprint invariant ("minimal memory footprint trumps compute cost") and validates IT's plan to
  make resident derived-field storage **opt-in** rather than default. Oceananigans is the strongest
  external endorsement of P3's "an absent slot is an error; resident GPU memory is opt-in."
- **P4**: Fusing each tendency into one kernel means the assembly scratch is *inside* the kernel, owned
  by the tendency computation — the analogue of P4's "nonlinear-assembly scratch moves into the
  generator," not shared out to consumers.

---

## 7. SpeedyWeather — PrognosticVariables / DiagnosticVariables + read-only diagnostic callbacks (P3, P5)

**Source.** Klöwer et al., "SpeedyWeather.jl: Reinventing atmospheric general circulation models
towards interactivity and extensibility," *JOSS* 2024 (doi:10.21105/joss.06323); documentation
"Callbacks" page (SpeedyWeather.jl v0.10.0), fetched 2026-07-18.

**Mechanism.** State is split into two typed containers — `PrognosticVariables` (the evolved state) and
`DiagnosticVariables` (derived/intermediate quantities). Observation is done through **callbacks** in
the time loop, which are explicitly **read-only** and diagnostic:

> "Callbacks are mainly introduced for diagnostic purposes, meaning that they do not influence the
> simulation, and access the prognostic variables and the model components in a read-only fashion."
> (Callbacks docs)

The callback interface is three extended methods with a fixed signature that hands the observer both
containers plus the model:

> "`function SpeedyWeather.initialize!(callback::CustomCallback, progn::PrognosticVariables,
> diagn::DiagnosticVariables, model::ModelSetup)`" and likewise `SpeedyWeather.callback!(...)` and
> `SpeedyWeather.finish!(callback, args...)` (Callbacks docs)

Diagnostic access reads derived slots (e.g. `diagn.layers[…].grid_variables` for wind speed) — i.e.
`DiagnosticVariables` is the sanctioned home for computed intermediates that observers may read.

**P-mapping (P3, P5).**
- **P5**: The two-container typing (`PrognosticVariables` vs `DiagnosticVariables`) is IT's state
  doctrine made into types — the restart record and the derived cache as separate objects. This is a
  concrete blueprint for IT's `State` (ResolvedFields = prognostic) vs `DerivedFields` (diagnostic).
- **P3**: The callback lifecycle (`initialize!` → `callback!` per step → `finish!`) with a **read-only**
  contract and a fixed signature that passes the whole diagnostic container is exactly the sanctioned
  observation layer P3 wants, and its read-only guarantee is the discipline IT's statistics/particle
  callbacks need (a callback must not mutate `DerivedFields` producer slots). SpeedyWeather also
  supplies derived quantities *through* `DiagnosticVariables` so a callback never re-pays a transform —
  the same producer-deposit principle as IT's DerivedFields.

---

## 8. Trixi — the propagator fully outsourced to OrdinaryDiffEq; analysis via callbacks (P1, P3)

**Source.** Ranocha, Schlottke-Lakemper, Winters, Faulhaber, Chan, Gassner, "Adaptive numerical
simulations with Trixi.jl," arXiv:2108.06476 (2021), and Schlottke-Lakemper et al. (*The SMAI Journal
of Computational Mathematics*, 2021, "A purely hyperbolic discontinuous Galerkin approach"); Trixi.jl
docs `docs/src/time_integration.md`, fetched 2026-07-18.

**Mechanism.** Trixi builds a **semidiscretization** (space only; the RHS is `rhs!`), then `semidiscretize`
converts it to a standard SciML `ODEProblem` handed to `OrdinaryDiffEq.jl`'s `solve`. The time
integrator is entirely external:

> "Trixi.jl is compatible with the SciML ecosystem for ordinary differential equations. In particular,
> explicit Runge-Kutta methods from OrdinaryDiffEq.jl …" (time_integration.md)
> "The `semidiscretize` function is used to create the ODE problem from the simulation setup." →
> "`Trixi.solve(ode, ode_algorithm; dt = 1, ode_default_options()..., callback = callbacks)`" (ibid.)

Analysis/observation is done with the shared SciML **callback** interface (`AnalysisCallback` with an
interval and extra integrals such as entropy/energy):

> "Since Trixi.jl is compatible with OrdinaryDiffEq.jl, both packages share the same callback
> interface" (Trixi docs, callbacks). The `AnalysisCallback` "can be initialized with a
> semidiscretization, an interval for analysis frequency, and extra analysis integrals."

**P-mapping (P1, P3).**
- **P1 (the extreme case)**: Trixi is the maximal version of IT's proposed Generator/Propagator seam —
  the seam is a *package boundary*. `rhs!` (the Generator) is the only thing Trixi owns; the Propagator
  is a third-party library. This proves the seam is real and load-bearing: a clean `rhs!(du, u, p, t)`
  signature lets *any* RK scheme drive it, and none of them hand-assemble the RHS. IT's P1 (a
  `ResolvedGenerator` with `rhs!/factor!/prepare!/finalize!`) is a domesticated version — IT keeps the
  propagator in-house because its integrating-factor schemes are not standard `ODEProblem`s (the exact
  viscous factor `exp(-ν κ² dt)` is folded per-stage, not a black-box `f(u,t)`), and because the GPU
  allocation-free, low-storage requirement rules out the general SciML machinery. That is a **justified
  deviation**: IT's integrating-factor structure is the specific reason it cannot simply outsource to
  OrdinaryDiffEq — but the *shape* of the seam (RHS object ⟂ stage arithmetic) is exactly Trixi's.
- **P3**: The `AnalysisCallback(interval, extra_integrals=…)` is a cadence-driven observation layer with
  a declared task set (the integrals) — the same pattern as Dedalus Handlers and SpeedyWeather
  callbacks, and a model for IT's diagnostic cadence.

---

## 9. Halide — algorithm ⟂ schedule: the theoretical precedent for P3's three axes

**Source.** Ragan-Kelley, Barnes, Adams, Paris, Durand, Amarasinghe, "Halide: A Language and Compiler
for Optimizing Parallelism, Locality, and Recomputation in Image Processing Pipelines," *PLDI* 2013,
doi:10.1145/2491956.2462176; halide-lang.org (project site), fetched 2026-07-18.

**Mechanism.** Halide separates *what is computed* (the algorithm) from *where values are stored and
when they are (re)computed* (the schedule):

> Publication title: "Halide: decoupling algorithms from schedules for high-performance image
> processing."
> Project site's own framing: "**The algorithm — no storage or order**" versus "**The schedule —
> defines order, locality; implies storage**." (halide-lang.org)

A schedule's decisions are precisely: computation order, what is stored vs recomputed (caching vs
recomputation), and locality/parallelism — the same three levers, chosen independently of the
algorithm.

**P-mapping (P3).** Halide is the theoretical charter for P3's three-axis split, which IT states as
*what to compute* (the chart's producer) vs *where stored* (the declared working set / resident-GPU
opt-in) vs *when recomputed* (epoch-stamp staleness). Halide's thesis is that these three must be
*separable and independently chosen* — which is exactly why IT's DerivedFields should not hard-wire
"this quantity is always resident" or "always recomputed": the storage axis (opt-in residency) and the
recomputation axis (producer-deposit vs accessor-recompute) are *distinct schedule choices* over the
same *algorithm* (the physical formula for the derived field). Halide's "recomputation" being a
first-class schedule choice legitimizes IT's stance that recompute-on-staleness and deposit-when-free
are two schedules of one derived quantity, and that memory-vs-compute is a tunable, not a fixed
property — the software-engineering twin of IT's "minimal footprint trumps compute cost."

---

## Transferable ideas for IT (ranked)

1. **Adopt the OpenFOAM `upToDate(other)/setUpToDate()` epoch contract for DerivedFields (P2, P3).**
   It is the exact, production-proven staleness API: each derived slot caches the epoch of the
   dynamical factor it depends on; an accessor recomputes iff behind, then stamps current. IT's
   per-dynamical-factor refinement (fields / particles / OU-noise counters) is a principled
   generalization of OpenFOAM's single `event_`. This is the single most directly liftable mechanism.

2. **Model the observation layer on Handlers/callbacks with a cadence and a declared task set
   (P3).** Dedalus (Handler `iter`/`sim_dt`/`wall_dt` + shared transform-minimizing pass),
   SpeedyWeather (`initialize!`/`callback!`/`finish!`, read-only), and Trixi (`AnalysisCallback(interval,
   extra_integrals)`) independently converge on: a first-class observer object, a cadence, a declared set
   of quantities, and a read-only contract. IT should copy the *convergent* shape, not invent one.

3. **Keep the demand-driven accessor as the sole path to a derived view (P2), per Dedalus
   `require_grid_space`.** The accessor coerces validity; no consumer ever trusts a caller-prefilled
   cache. This is the direct fix for IT's P2 footgun, and it is the same idiom Fluidsim's `get_var`
   uses. Producer deposits are an *optimization under* the accessor, never a replacement for it.

4. **Draw the prognostic/diagnostic line as typed containers (P5), per SpeedyWeather and
   Oceananigans.** `State`/`ResolvedFields` = prognostic = restart record; `DerivedFields` = diagnostic =
   cache. A queryable split (`prognostic_fields`/`diagnostic_fields`) makes the state doctrine
   enforceable, not just documented.

5. **Reify the RHS as a single-owner object (P1), per Devito's `Operator` and Trixi's `rhs!`.**
   The RHS assembly must have exactly one owner so a scheme cannot hand-assemble (and silently misread)
   it. IT's `ResolvedGenerator` protocol is this pattern; the dealiasing bug is the cost of not having
   it.

6. **Treat storage-residency and recompute-policy as independent schedule axes (P3), per Halide.**
   Do not hard-wire residency or recomputation into a chart's definition; make each an opt-in choice over
   one physical formula. This keeps memory-vs-compute a studied fitness axis.

7. **Fuse assembly scratch into the producer, not shared out (P4), per Oceananigans kernel fusion.**
   Nonlinear-assembly scratch belongs inside the Generator's kernel; consumers get *values*, not the
   generator's buffers. This is the design-level argument for P4's scratch-ownership rule.

---

## Where IT's proposal differs from this beat's practice — risk or justified deviation

- **Single spectral truth vs Dedalus's mutable per-field layout / Fluidsim's dual store.**
  IT stores one truth (`û`, `φ̂`) and derives physical views; Dedalus lets each field's representation
  *be* mutable state; Fluidsim keeps both `state_spect` and `state_phys` and runs a runtime consistency
  check. IT's choice is a **justified deviation**: it eliminates the drift Fluidsim must police
  (`check_energy_equal_phys_spect`) and the "which layout am I in?" ambiguity, at the cost that every
  physical read is a derived-field access — which is precisely why the P2/P3 accessor+epoch machinery is
  load-bearing, not optional. Risk only if IT ships the derived-view accessors *without* the staleness
  contract (the current P2 footgun); with the contract, the single-truth design is strictly cleaner.

- **In-house integrating-factor Propagator vs Trixi's fully outsourced OrdinaryDiffEq.**
  Trixi proves a clean `rhs!` seam permits outsourcing the whole integrator. IT cannot follow, because
  its exact viscous integrating factor `exp(-ν κ² dt)` is folded *per stage* (not a black-box
  `f(u,t)`), and the GPU allocation-free / low-storage invariant rules out generic SciML machinery. This
  is a **justified deviation** — but it *raises the bar* on P1: since IT owns the propagator, the
  Generator/Propagator seam must be reified *within* the package (the `ResolvedGenerator` protocol),
  because there is no external boundary enforcing it. Risk: if P1 is left in prose, IT gets the cost of
  in-housing (no enforced seam) with none of Trixi's benefit.

- **Default-lazy recompute (Oceananigans) vs IT's memoize-and-deposit (OpenFOAM/Fluidsim).**
  Oceananigans recomputes intermediates inside fused kernels every time (memory beats compute);
  OpenFOAM/Fluidsim memoize with stamps. IT proposes a hybrid — producer deposits when free, accessor
  recomputes otherwise, residency opt-in. This is **not a risk** but the correct synthesis under IT's
  footprint invariant, and Halide's algorithm/schedule thesis legitimizes carrying *both* schedules for
  one quantity. The only risk is complexity: three axes (produce/store/recompute) per chart is more
  machinery than any single system here uses; keep the default (recompute, non-resident) matching
  Oceananigans and make deposit/residency the deliberate exception.

- **Per-dynamical-factor epochs vs a single global counter.**
  Every memoization precedent here (OpenFOAM `event_`, Fluidsim `it`) uses **one** global counter. IT's
  per-factor counters (fields / particles / OU-noise) are a **deviation** motivated by the skew-product
  tower (P5): a tracer read should not invalidate on an OU-noise advance. This is justified by the state
  structure, but it is *unprecedented* in the studied systems — so it carries an implementation risk
  (getting the dependency graph among factors right). Mitigation: start with the single global counter
  (Fluidsim's `it`), which is known-correct if coarse, and split counters only where a measured
  over-invalidation cost justifies it — argue the split from a first-principle cost, not "for symmetry."

- **Forcing scratch ownership (P4) has no direct external contrast here.**
  None of the paper-level systems document handing an integrator's whole private buffer bundle to a
  forcing strategy; the convergent practice (Oceananigans kernel fusion, Firedrake narrow interfaces) is
  that each concern owns its scratch behind an interface. IT's current arrangement (forcings receive the
  integrator bundle "for uniformity", one reaches into named fields) is the *anti-pattern* these systems
  avoid; P4's proposal (forcings own scratch; assembly scratch into the generator; only RK registers with
  the integrator) is the alignment. No deviation — IT is proposing to move *toward* the beat's practice.

---

## Sources

- Burns, Vasil, Oishi, Lecoanet, Brown, "Dedalus: A flexible framework for numerical simulations with
  spectral methods," *Phys. Rev. Research* 2, 023068 (2020); arXiv:1905.10388.
  Code: `raw.githubusercontent.com/DedalusProject/dedalus/master/dedalus/core/{field.py,evaluator.py}`
  (fetched 2026-07-18).
- OpenFOAM-dev `master`: `src/OpenFOAM/db/regIOobject/regIOobject.H`,
  `src/OpenFOAM/db/objectRegistry/objectRegistry.H` (github.com/OpenFOAM/OpenFOAM-dev, fetched
  2026-07-18).
- Mohanan, Bonamy, Augier, "FluidSim: modular, object-oriented Python package for high-performance CFD
  simulations," *JOSS* 4(39), 1181 (2019), doi:10.21105/joss.01181. Local clone (v0.9.0):
  `inspiration/dns/fluidsim/fluidsim/base/state.py`, `.../solvers/ns3d/state.py`,
  `.../base/time_stepping/base.py`, `.../base/preprocess/pseudo_spect.py` (read 2026-07-18).
- Rathgeber et al., "Firedrake: Automating the Finite Element Method by Composing Abstractions," *ACM
  TOMS* 43(3):24 (2016), doi:10.1145/2998441; arXiv:1501.01809 (ar5iv, fetched 2026-07-18).
- Louboutin et al., "Devito (v3.1.0): an embedded domain-specific language for finite differences and
  geophysical exploration," *GMD* 12, 1165–1187 (2019), doi:10.5194/gmd-12-1165-2019; arXiv:1808.01995
  (GMD HTML, fetched 2026-07-18). [Operator-caching claim UNVERIFIED from this source.]
- Ramadhan et al., "Oceananigans.jl: Fast and friendly geophysical fluid dynamics on GPUs," *JOSS* 5(53),
  2018 (2020), doi:10.21105/joss.02018; Silvestri et al., arXiv:2309.06662v2 (fetched 2026-07-18);
  Oceananigans documentation "Models overview" (docs-level, not quoted verbatim).
- Klöwer et al., "SpeedyWeather.jl," *JOSS* (2024), doi:10.21105/joss.06323; SpeedyWeather.jl v0.10.0
  documentation, "Callbacks" (fetched 2026-07-18).
- Schlottke-Lakemper, Ranocha et al., Trixi.jl: arXiv:2108.06476 (2021); Trixi.jl docs
  `docs/src/time_integration.md` and callbacks page (fetched 2026-07-18).
- Ragan-Kelley, Barnes, Adams, Paris, Durand, Amarasinghe, "Halide," *PLDI* 2013,
  doi:10.1145/2491956.2462176; halide-lang.org project site (fetched 2026-07-18).
