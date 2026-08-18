# Beat 06 — Python source study: Dedalus & JAX-MD

Source study of two Python clones under
`inspiration/arch/{dedalus,jax-md}`. Study-only; Dedalus is GPL (never copy). Every claim below is
cited to a file path and line range in the local clone, with the decisive line quoted. The seeded
leads were confirmed against source; deviations from the memory-hypotheses are flagged explicitly.

Mapping at a glance:

| System | P1 seam | P2 stale-cache | P3 observation | P4 scratch | P5 state doctrine |
|---|---|---|---|---|---|
| Dedalus | **reified** (Evaluator/state/F) | representation state-machine | **scheduled batch** (Handler/Task) | strict (timestepper/evaluator/field) | state = variables; time-as-field |
| JAX-MD | pure fn (force_fn + integrator) | — | **no-cache** pure fns | closure-owned | **extended state in the type** |

---

## 1. Dedalus — the reified RHS seam and the scheduled observation layer

Dedalus v3 (the clone is the current `core/` tree; module headers give no version string, but the
API — `Distributor`, `dist.layouts`, `register_dataclass`-free — is the v3 line, post-2022 rewrite).
Its spectral-IVP architecture is the single most direct analogue to IT's proposed changes, because
Dedalus already *has* the seam IT's P1 wants to build, and already *has* an observation layer (IT's
P3) — but one with **scheduling**, not just demand-driven freshness.

### 1.1 P1 — the Generator/Propagator seam is reified, not hand-assembled

In IT today each `step!` hand-assembles the RHS. In Dedalus the RHS is a first-class object the
solver owns, and the timestepper does *only* stage arithmetic. The discretisation the timesteppers
target is stated in the class docstring
(`dedalus/dedalus/core/timesteppers.py:509-524`):

> These timesteppers discretize the system
>     `M.dt(X) + L.X = F`
> by constructing s stages
>     `M.X(n,i) - M.X(n,0) + k Hij L.X(n,j) = k Aij F(n,j)`

`M` and `L` are the linear (implicit) operators, `F` the explicit nonlinear right-hand side. The
seam is three named handles the timestepper reads off the solver
(`timesteppers.py:556-560`):

```
solver = self.solver
evaluator = solver.evaluator
state_fields = solver.state
F_fields = solver.F
```

The solver builds `F` once at construction as a dedicated handler
(`dedalus/dedalus/core/solvers.py:569-574`):

```
# Create RHS handler
F_handler = self.evaluator.add_system_handler(iter=1, group='F')
for eq in problem.eqs:
    F_handler.add_task(eq['F'])
F_handler.build_system()
self.F = F_handler.fields
```

The RK stage loop then contains **no** RHS assembly of its own — it *asks* the evaluator for the RHS
and does pure Butcher-tableau arithmetic (`timesteppers.py:606-623`):

```
# Compute F(n,i-1), only doing output on first evaluation
if i == 1:
    evaluator.evaluate_scheduled(...)
else:
    evaluator.evaluate_group('F')
Fi = F[i-1]
for sp in subproblems:
    sp.gather_outputs(F_fields, out=Fi.get_subdata(sp))
# Construct RHS(n,i)
if RHS.data.size:
    np.copyto(RHS.data, MX0.data)
    for j in range(0, i):
        axpy(a=(k*A[i,j]), x=F[j].data, y=RHS.data)      # + k A_ij F_j
        axpy(a=-(k*H[i,j]), x=LX[j].data, y=RHS.data)     # - k H_ij L X_j
```

This is *exactly* the shape of IT's P1 proposal: a protocol (`rhs!` ≙ `evaluate_group('F')`;
`factor!`/implicit ≙ the `M`/`L` matrix solve; `prepare!` ≙ the `evaluate_scheduled` prologue that
also fires output) with the scheme reduced to "stage arithmetic only". Two transferable specifics:

- **The implicit/explicit split is the integrating-factor analogue.** Dedalus folds the linear term
  `L` into the LHS matrix `(M + k Hii L)` and solves it (`timesteppers.py:626-642`); the explicit
  `F` is assembled by the evaluator. IT's exact viscous integrating factor `exp(-ν κ² dt)` plays the
  role of Dedalus's `L`-solve: it is the *linear, per-mode* part, and IT's P1 proposal to add a
  `factor!` to the generator protocol is the direct counterpart of Dedalus keeping `L` on the solver
  and out of the scheme. The category is the same — the scheme never *knows* the viscous operator, it
  only knows tableau coefficients.
- **The forcing prologue is fired exactly once per step, on the first stage.** The `if i == 1`
  branch is where output-side scheduling happens; later stages call the cheaper `evaluate_group('F')`.
  This answers a design question latent in IT's P1 ("where does `prepare!`/`finalize!` sit relative to
  the stage loop?"): Dedalus's answer is *the per-step internal-state advance is bound to stage 1's
  evaluation*, and the diagnostic/output pass is bolted onto that same first evaluation so it never
  double-computes. IT's four-hook forcing lifecycle (`prepare_forcing!` per step, `add_forcing_source!`
  per stage, `set_forcing_rate!` folded into the factor, `apply_forcing!` post-step) is *finer*-grained
  than Dedalus's, but Dedalus validates the coarse skeleton: one prologue, per-stage source, one epilogue.

The multistep base class (`timesteppers.py:95-150`) has the identical structure — it reads
`solver.state` / `solver.F` and only combines history with coefficients — confirming the seam is a
solver-level contract, not a per-scheme convention. **Confirmed lead.**

### 1.2 P3 — an observation layer *with scheduling* (Evaluator / Handler / Task)

This is the richest contrast with IT's DerivedFields, which is purely demand-driven (recompute on
staleness, no calendar). Dedalus's observation layer adds a *scheduler* on top.

**Tasks are declared, not called.** A handler owns a list of task dicts; each task is an operator
expression plus an output layout, name, and scales (`evaluator.py:278-308`):

```
def add_task(self, task, layout='g', name=None, scales=None):
    ...
    task = dict()
    task['operator'] = op
    task['layout'] = self.dist.get_layout_object(layout)
    task['name'] = name
    task['scales'] = scales
```

**Cadences trigger by iteration, sim time, or wall time — plus a custom predicate.** The scheduler
lives in `Handler.check_schedule` (`evaluator.py:246-276`). Each cadence keeps a "last divisor" and
fires when the divisor advances:

```
if self.wall_dt:
    wall_div = kw['wall_time'] // self.wall_dt
    if wall_div > self.last_wall_div: scheduled = True; self.last_wall_div = wall_div
if self.sim_dt:
    ... closest_sim_div = int(np.round(t / self.sim_dt)) ...
if self.iter:
    iter_div = kw['iteration'] // self.iter
    if iter_div > self.last_iter_div: scheduled = True
if self.custom_schedule:
    if self.custom_schedule(**kw): scheduled = True
```

The sim-time branch is subtle and worth transferring verbatim to IT's diagnostic-cadence design: it
fires the output closest to a target time *only if the next step would not land closer*
(`evaluator.py:256-265`), so a fixed-`sim_dt` output series is emitted at the nearest available step
without drift. IT currently has no such "nearest-step" logic for its statistics callbacks.

**One evaluation pass batches many tasks and shares transforms.** `evaluate_scheduled` selects the
handlers whose schedule fired and hands them all to `evaluate_handlers`
(`evaluator.py:90-93`):

```
def evaluate_scheduled(self, **kw):
    handlers = [h for h in self.handlers if h.check_schedule(**kw)]
    self.evaluate_handlers(handlers, **kw)
```

`evaluate_handlers` (`evaluator.py:95-146`) flattens *all* tasks from *all* fired handlers, then
drives them to completion by oscillating every shared field through layouts together
(`evaluator.py:114-129`):

```
# Oscillate through layouts until all tasks are evaluated
oscillate_indices = oscillate(range(n_layouts), max_passes=10)
...
while tasks:
    fields = self.get_fields(tasks)         # shared atom set across all tasks
    if current_index < next_index: self.dist.paths[current_index].increment(fields)
    else:                          self.dist.paths[next_index].decrement(fields)
    tasks = self.attempt_tasks(tasks, id=id)
```

The transform sharing is real and load-bearing: `get_fields` gathers the *union* of leaf fields over
all tasks (`evaluator.py:182-192`), so a forward/backward FFT paid once serves every diagnostic that
reads that field. This is the concrete "shared transform" cost argument the beat asks about — it is
the whole reason Dedalus batches rather than evaluating diagnostics one-by-one.

**Sub-expression memoization within a pass — the closest analogue to IT's epoch stamp.** Each
evaluation pass gets a fresh uuid, and operators cache their output against it
(`evaluator.py:98-100`, `dedalus/dedalus/core/future.py:163-220`):

```
# Default to uuid to cache within evaluation, but not across evaluations
if id is None:  id = uuid.uuid4()
```
```
if self.store_last and (id is not None):
    if id == self.last_id:
        return self.last_out
```

This is precisely a **stamp-based validity contract**, but the stamp is a *per-evaluation-pass uuid*,
deliberately invalidated between passes ("cache within evaluation, but not across evaluations"). IT's
DerivedFields proposes *per-dynamical-factor epoch counters* that persist across the step and are
bumped when a factor (fields, particles) advances — a strictly more ambitious contract, because it
must survive between passes and correctly express "the velocity chart is fresh but the particle
positions moved". Dedalus sidesteps that whole problem by throwing the cache away each pass; IT keeps
it, and therefore must get epoch bookkeeping exactly right. **This is the sharpest lesson for P3:**
the uuid-per-pass discipline is *cheap and safe* precisely because it never claims cross-pass
freshness. IT's persistent epochs buy producer-deposit reuse (the loop already computed the value)
at the cost of a genuine cache-coherence obligation.

**Cost accounting (the beat's explicit ask).** Dedalus's contract vs IT's:
- Dedalus pays: a Python-object expression tree, per-pass output-field allocation
  (`future.py:201-207` allocates `out` each pass), and uuid hashing. It is a CPU/host-oriented design;
  the allocation-per-pass alone disqualifies it from IT's allocation-free GPU hot loop.
- Dedalus buys: automatic transform sharing across arbitrarily many diagnostics, and correctness by
  construction (a diagnostic can never read a stale layout — the evaluator *drives* the layout).
- IT's DerivedFields buys: zero allocation (preallocated declared working sets), producer deposits
  for free when the loop computes a value anyway, GPU residency. It pays: hand-maintained epoch
  counters and a construction-time working-set declaration that must be complete (an undeclared chart
  is an error, not a silent recompute).

The transferable idea: **adopt Dedalus's "nearest-step, divisor-advance" cadence logic** for IT's
diagnostic/statistics scheduling, and **adopt the batch-and-share-transforms pass** as the shape of
IT's occasional-diagnostic path — but keep IT's stamped preallocated slots instead of Dedalus's
allocate-per-pass. **Confirmed lead**, with the added finding that Dedalus's stamp is a throwaway
uuid, not a persistent epoch.

### 1.3 P2 — the representation state machine (a field whose layout floats)

IT fixes truth in the spectral representation and derives physical fields on demand. Dedalus takes
the opposite stance: a `Field` carries a *current* layout and *changes it stepwise*, with bookkeeping
(`dedalus/dedalus/core/field.py:540-596, 661-700`):

```
class Field(Current):
    # Attributes: layout (current layout), data (view of buffer in current layout)
    def change_layout(self, layout):
        if self.layout.index < layout.index:
            while self.layout.index < layout.index: self.towards_grid_space()
        elif self.layout.index > layout.index:
            while self.layout.index > layout.index: self.towards_coeff_space()
```

Each `towards_grid_space` / `towards_coeff_space` advances exactly one transform/transpose path
(`field.py:674-682`), and `require_coeff_space` / `require_grid_space` walk to a target
(`field.py:684-700`). Operators declare the layout they need via `check_conditions` /
`enforce_conditions` (`future.py:242-251`), and the evaluator satisfies them by walking the state
machine.

The **cost/benefit relative to IT** (the beat's explicit ask):
- *Dedalus's floating representation buys*: no redundant transforms (a field already in grid space is
  not re-transformed), and every operator can state its required layout declaratively rather than the
  caller pre-arranging it. It is the direct antidote to IT's **P2 footgun** — Dedalus's `step!`
  analogue cannot "forget to refill the physical cache" because the *field itself* records whether it
  is in grid space, and any consumer calls `require_grid_space()` which is idempotent. The staleness is
  impossible to misread because the layout is a property of the datum, not a comment-enforced
  convention on a shared scratch buffer.
- *It costs*: every datum carries a mutable `layout` and a re-derived `data` view (`preset_layout`,
  `field.py:527-537` rebuilds the ndarray view on each layout change); operations must branch on
  layout; and there is no single "source of truth" representation — the truth is wherever the field
  currently is. That mutability is exactly what IT's GPU-primary, in-place, allocation-free discipline
  rejects: IT wants a fixed spectral truth so the buffer layout is static and kernels are branch-free.

The synthesis for IT's P2: Dedalus shows that the *robust* fix for the silent-precondition footgun is
to **make representation/freshness a property of the datum, not of a comment**. IT's proposed
demand-driven accessors over *stamped slots* are the GPU-compatible version of exactly this — a stamp
is the static-layout analogue of Dedalus's mutable `.layout`. The `LockedField`
(`field.py:1013-1052`) is a further transferable idea: a field that *refuses* to change to
disallowed layouts (`"Cannot change locked layout."`) — the enforcement counterpart of IT's "an
absent declared chart is an error".

### 1.4 P4 — scratch ownership is strictly partitioned

Dedalus already practises what IT's P4 proposes. Ownership is clean and layered:
- **The timestepper owns the RK/history registers.** `RungeKuttaIMEX.__init__`
  (`timesteppers.py:539-550`) allocates its own `CoeffSystem` scratch — `RHS`, `MX0`, and the
  per-stage lists `LX`, `F`:
  ```
  self.RHS = CoeffSystem(...); self.MX0 = CoeffSystem(...)
  self.LX = [CoeffSystem(...) for i in range(self.stages)]
  self.F  = [CoeffSystem(...) for i in range(self.stages)]
  ```
  These are exactly IT's "RK stage registers stay with the integrator".
- **The evaluator/fields own transform buffers.** Field buffers are FFTW-aligned and owned by the
  field (`field.py:486-506, 508-525`); the evaluator owns the layout-walk scratch.
- **The RHS (forcing/nonlinear) lives in its own handler**, not in the timestepper's bundle
  (`solvers.py:569-574`). A forcing term is an operator expression in `eq['F']`; it does not reach
  into the integrator's registers.

So Dedalus is a positive existence proof for P4's target arrangement — nonlinear/forcing assembly
owns its scratch (the `F` handler + operator temporaries), stage registers stay with the scheme, and
nothing shares a "whole private bundle for interface uniformity". **Confirmed lead.**

### 1.5 P5 — state doctrine (what is the restart record)

`solver.state = problem.variables` (`solvers.py:65`) — the restart record is exactly the problem
variables, and `load_state` restores *only* those fields from HDF5 (`solvers.py:666-672`):

```
for field in self.state:
    if field.name in file['tasks']:
        field.load_from_hdf5(file, index)
```

Everything else — the diagnostic tasks in the file handlers — is the **logbook**, written but never
part of the flow map. This matches IT's P5 litmus ("what the flow map needs" = the restart record).

One *instructive divergence* from IT's P5: Dedalus treats **time as a field**, not merely a trajectory
parameter. `sim_time` is a property whose setter writes into a genuine problem field
(`solvers.py:597-600`):

```
@sim_time.setter
def sim_time(self, t):
    self._sim_time = t
    self.problem.time['g'] = t
```

This lets time appear symbolically inside RHS expressions (time-dependent forcing/boundary terms).
IT's P5 deliberately reads time as a *trajectory parameter, not a phase-space coordinate*. The
Dedalus choice is the pragmatic opposite, motivated by symbolic-expression forcing; it is a
**justified deviation for IT to keep its stance**, since IT has no symbolic-expression layer and its
forcing reads time through the run layer, not through a field. The lesson is only that "time-as-field"
is a real, coherent alternative when the RHS is symbolic — which IT's is not.

---

## 2. JAX-MD — the pure-function propagator and the extended state made visible in the type

JAX-MD (clone is the current tree using `jax.tree_util.register_dataclass`, i.e. the 2024+ line).
It is the functional-programming pole: the propagator is a *pure function* `state -> state`, the state
is a typed dataclass registered as a JAX pytree, and — the finding that most directly informs P5 — the
thermostat and the RNG live *inside the state type*.

### 2.1 P5 — extended-state doctrine made visible in the type system

This is the headline transfer. Each ensemble's state is a dataclass, and the *extra degrees of freedom
the integrator needs* are fields of that dataclass, not hidden scratch.

Baseline NVE (`jax-md/jax_md/simulate.py:249-271`): just the phase-space coordinates plus mass.

```
@dataclasses.dataclass
class NVEState:
  position: Array
  momentum: Array
  force: Array
  mass: Array | float
```

Nose–Hoover thermostat: the state *carries the thermostat chain*
(`simulate.py:538-558`):

```
@dataclasses.dataclass
class NVTNoseHooverState:
  position: Array
  momentum: Array
  force: Array
  mass: Array
  chain: NoseHooverChain      # <- thermostat degrees of freedom, IN the state
```

and the chain is itself a state dataclass with its own position/momentum/mass/kinetic-energy
(`simulate.py:350-374`):

```
@dataclasses.dataclass
class NoseHooverChain:
  position: Array
  momentum: Array
  mass: Array
  tau: Array | float
  kinetic_energy: Array
  degrees_of_freedom: int = dataclasses.static_field()
```

Langevin dynamics: the state *carries the RNG* (`simulate.py:1073-1093`):

```
@dataclasses.dataclass
class NVTLangevinState:
  position: Array
  momentum: Array
  force: Array
  mass: Array
  rng: Array                  # <- the stochastic state, IN the state
```

and NPT adds barostat DOF `box_position`/`box_momentum`/`box_mass`/`dUdV`
(`simulate.py:704-744`).

This is P5's doctrine realised in a type system: **a stochastic forcing's internal state is a
Markovian surrogate slot carried in the state record**, and **an auxiliary controller (thermostat/
barostat) is extended phase space, not hidden scratch**. The direct IT mapping:
- IT's OU/stochastic forcing internal state → an explicit slot in the restart record, exactly like
  `NVTLangevinState.rng` and `NoseHooverChain`. If IT carries the OU state as a first-class state
  field, a restart is bit-reproducible; if it hides it as forcing scratch, restart drifts.
- IT's skew-product tower reading (time → OU noise → fields → particles) is *literally* the JAX-MD
  nesting: `NVTNoseHooverState` contains a `NoseHooverChain` contains its own coordinates — a nested
  state tower advanced by a per-step sweep (half-step chain, then Verlet, then half-step chain; see
  §2.2). JAX-MD is the concrete precedent for IT's "skew-product tower advanced by a Gauss–Seidel
  sweep per step".

**The static/dynamic split is the formal "what belongs in the flow map" discipline**
(`jax-md/jax_md/dataclasses.py:37-48, 91-101`):

```
def static_field(...):
    combined_metadata['static'] = True
    combined_metadata['pytree_node'] = False
    return _field(metadata=combined_metadata, ...)
```

A `static_field` is *not* a pytree leaf — it is not traced/differentiated and it triggers
recompilation when it changes; everything else is dynamic state. `degrees_of_freedom` (an int),
`max_occupancy`, `format` are static; `position`, `momentum`, `chain`, `rng` are dynamic. This is
exactly IT's P5 litmus expressed as a type annotation: **dynamic = "what the flow map advances"
(restart record); static = shape/config (the experimenter's setup, causes recompile)**. IT has no
compiler to enforce this, but the discipline transfers directly: a slot is either advanced by the
step (state) or it is fixed configuration (domain) — and JAX-MD proves the two-way partition is
sufficient (there is no third "cache" category in the state type; caches like neighbor lists live
*outside* the state — see §2.4). **Confirmed lead**, with the strong added finding that the
static/dynamic pytree split *is* the machine-checked P5 doctrine.

### 2.2 P1 — the propagator as a pure function `state -> state`

`init_fn`/`apply_fn` (or `step_fn`) pairs are the propagator contract. The generator (the force) is a
*closure captured at construction*, and the integrator is a pure function that does only arithmetic
(`simulate.py:227-243`):

```
def velocity_verlet(force_fn, shift_fn, dt, state, **kwargs):
  state = momentum_step(state, dt_2)
  state = position_step(state, shift_fn, dt, **kwargs)
  state = state.set(force=force_fn(state.position, **kwargs))
  state = momentum_step(state, dt_2)
  return state
```

`nve` returns the pair; the force is baked in (`simulate.py:297-317`):

```
force_fn = quantity.canonicalize_force(energy_or_force_fn)
def step_fn(state, **kwargs):
    return velocity_verlet(force_fn, shift_fn, _dt, state, **kwargs)
return init_fn, step_fn
```

This is IT's P1 taken to the functional extreme: the scheme is a pure `state -> state` map, the
generator is an injected `force_fn`, and *all* stage arithmetic is expressed as functional updates
`state.set(force=...)`. The Nose–Hoover `apply_fn` shows the Gauss–Seidel tower sweep explicitly
(`simulate.py:649-667`):

```
def apply_fn(state, **kwargs):
    chain = state.chain
    chain = thermostat.update_mass(chain, _kT)
    p, chain = thermostat.half_step(state.momentum, chain, _kT)   # advance chain (half)
    state = state.set(momentum=p)
    state = velocity_verlet(force_fn, shift_fn, dt, state, **kwargs)  # advance fields
    chain = chain.set(kinetic_energy=kinetic_energy(state))
    p, chain = thermostat.half_step(state.momentum, chain, _kT)   # advance chain (half)
    return state.set(momentum=p, chain=chain)
```

This is a per-step Gauss–Seidel sweep over the state tower: half-advance the outer fiber (chain),
advance the inner (fields), half-advance the outer again — the Strang-split skew-product IT's P5
describes, written as pure composition.

**The functional-purity trade-off against IT's in-place GPU discipline** (the beat's explicit ask):
- JAX-MD writes `state = state.set(force=force_fn(...))` — a *functional* update returning a new
  dataclass. This appears allocating, but XLA fuses the whole `jit`-compiled `step_fn` and reuses
  buffers via donation/aliasing, so the *compiled* kernel is effectively in-place. The purity is a
  *source-level* property the compiler discharges.
- IT has no such compiler pass; it must *manually* keep `step!` in-place and allocation-free over
  preallocated buffers. So IT cannot adopt JAX-MD's `state.set(...)` literally without paying real
  allocations. What IT *can* adopt is the *contract*: a scheme is a map from a state record to a state
  record, with the generator injected — implemented in IT as in-place mutation of the preallocated
  state buffers rather than functional replacement. IT's `ResolvedGenerator` object (P1) is the
  imperative twin of JAX-MD's captured `force_fn` closure; IT's `IntegratorBuffers` is the manual
  stand-in for XLA's automatic buffer reuse.
- The deeper lesson: JAX-MD's purity makes the *state boundary* unambiguous — anything the step reads
  or writes is *in* the `state` argument or the captured closure, nothing else. IT's in-place design
  blurs this (the P2 footgun, the P4 shared bundle) precisely because mutation lets a step reach
  outside its declared inputs. IT's P1–P5 program is, in effect, *recovering JAX-MD's explicit state
  boundary without giving up in-place GPU mutation* — the working-set declarations (P3), the
  scratch-ownership rules (P4), and the state-record doctrine (P5) are the manual enforcement of what
  JAX-MD's pytree/closure boundary gives for free.

**Confirmed lead.**

### 2.3 P3 — observables at the no-cache pole

`quantity.py` observables are pure functions of state with *no cache at all* — the opposite pole from
Dedalus's scheduled cache and IT's memoized DerivedFields. `kinetic_energy`
(`jax-md/jax_md/quantity.py:124-159`) recomputes from momentum/velocity every call:

```
def kinetic_energy(*unused_args, momentum=None, velocity=None, mass=1.0):
    ...
    ke = tree_map(lambda m, q: 0.5 * util.high_precision_sum(k(q, m)), mass, q)
    return tree_reduce(operator.add, ke, 0.0)
```

`temperature`, `pressure`, `stress` (`quantity.py:162, 202, 238`) are likewise pure. Forces are
derived, not stored, via autodiff (`quantity.py:58-62`):

```
def force(energy_fn):
    return grad(lambda R, *a, **kw: -energy_fn(R, *a, **kw))
```

The trade-off for P3: JAX-MD pays full recomputation for every observable (acceptable because XLA
fuses and because MD observables are cheap relative to the force evaluation), and buys *zero*
cache-coherence obligation — an observable can never be stale because it is a pure function of the
current state. This is the design IT explicitly rejects for the hot-loop derived fields (velocity/
vorticity/RHS transforms are *not* cheap — a full FFT — so recomputing per reader is the very cost
P3 exists to avoid). But it is the right design for IT's *occasional* diagnostics, and it matches
CLAUDE.md invariant 4 ("per-call allocation of an occasional diagnostic over resident scratch"). The
transferable boundary: **cheap observables → pure recompute (JAX-MD/no-cache); expensive shared
derived fields the loop already computes → deposit+memoize (IT's DerivedFields); many diagnostics at
once → batch and share transforms (Dedalus)**. IT's P3 sits in the middle and should *not* collapse
to either pole.

### 2.4 P2/P3 — the capacity-based validity contract (a third alternative beside stamps and
state-comparison)

`partition.py`'s neighbor list is the beat's promised "third alternative". A `NeighborList` carries a
capacity and an error code, and its validity is checked by **capacity overflow**, not by a freshness
stamp (`jax-md/jax_md/partition.py:684-729`):

```
@dataclasses.dataclass
class NeighborList:
  idx: Array
  reference_position: Array
  error: PartitionError
  max_occupancy: int = dataclasses.static_field()
  ...
  @property
  def did_buffer_overflow(self) -> Array:
      return self.error.code & (PEC.NEIGHBOR_LIST_OVERFLOW | PEC.CELL_LIST_OVERFLOW)
```

The `allocate`/`update` split is the crux, and it is a *jit-boundary* contract
(`partition.py:824-829`):

> allocation of a new neighbor list cannot be jit compiled since it uses the positions to infer the
> maximum number of neighbors ... Updating the neighbor list can be jit compiled; if the neighbor
> list capacity is not sufficient ... the `did_buffer_overflow` bit will be set to `True` and a new
> neighbor list will need to be reallocated.

So the loop runs `update` (fixed capacity, jittable, in-place-friendly) inside the hot path, and only
falls back to the un-jittable, shape-inferring `allocate` when the overflow bit trips
(`partition.py:838-853`):

```
nbrs = nbrs.update(state.position)
state = apply_fn(state, neighbor_idx=nbrs.idx)
...
if nbrs.did_buffer_overflow:
    nbrs = neighbor_fn.allocate(state.position)   # rare, recompiles/reshapes
```

Critically, `partition.py` demonstrates **two** validity contracts at once:
1. **Capacity overflow** (the third alternative): `overflow = overflow | (max_occupancy > cell_capacity)`
   (`partition.py:459-460`) — a *bit flag*, checked outside jit, triggering reallocation.
2. **State-comparison rebuild** (the classic): the list is rebuilt only when a particle has moved past
   a threshold since the `reference_position` (`partition.py:1146-1154`):
   ```
   return lax.cond(
     jnp.any(d(position, nbrs.reference_position) > threshold_sq),
     ... partial(neighbor_fn, ...), nbrs, lambda x: x)
   ```

The `PartitionError` is a monotone OR-accumulator of typed error bits (`partition.py:523-538`),
readable after the fact — a *deferred* validity report rather than an eager assertion.

**Relevance to IT's P2/P3.** IT's proposal offers two validity contracts (demand-driven staleness
stamps for P2; per-dynamical-factor epochs for P3). JAX-MD adds a *third and fourth*:
- **Capacity/overflow bit** for anything whose *size* can outgrow its preallocation. IT's Lagrangian
  tracers are the natural fit: if IT ever needs a per-tracer neighbor/interpolation-stencil buffer,
  the `did_buffer_overflow` pattern (a device-side bit checked host-side, triggering a rare
  reallocation outside the hot loop) is the GPU-idiomatic contract — it keeps the hot path
  allocation-free and shape-static (IT's exact requirement) while still tolerating growth.
- **The allocate/update jit-boundary split** is directly transferable to IT's `allocate_buffers`
  dispatch: allocation is a *cold*, shape-inferring, per-scheme operation done once; the step is a
  *hot*, fixed-shape, allocation-free update. IT already separates these (per-scheme `IntegratorBuffers`
  built by `allocate_buffers`); JAX-MD confirms the pattern and adds the discipline that the hot
  `update` must *detect* rather than *prevent* capacity failure, reporting it through a state bit.

**Confirmed lead**, with the finding that `partition.py` actually exhibits *both* capacity-overflow
and state-comparison contracts, and that the deeper transferable idea is the **allocate/update
jit-boundary** (cold shape-inference vs hot fixed-capacity update), which maps onto IT's cold
`allocate_buffers` vs hot `step!`.

---

## Transferable ideas for IT (ranked)

1. **Reify the seam exactly as Dedalus does (P1).** Make the generator own the RHS assembly and the
   linear/integrating-factor operator; make each scheme read three handles (state, generator, buffers)
   and do *only* tableau arithmetic. Dedalus's `M.dt(X)+L.X=F` with `L` folded into the LHS is the
   proven template for IT's `exp(-ν κ² dt)`-as-`factor!`. Bind the per-step forcing prologue to the
   first stage's evaluation, as Dedalus binds output to stage 1.

2. **Carry auxiliary/stochastic state as first-class slots in the state record (P5).** Follow
   `NVTLangevinState.rng` and `NoseHooverChain`: IT's OU-forcing internal state and any controller
   state belong *in* the restart record, not in forcing scratch, so restarts are bit-reproducible.
   The nested `NVTNoseHooverState ⊃ NoseHooverChain` is IT's skew-product tower precedent.

3. **Adopt the static/dynamic partition as the P5 litmus.** JAX-MD's `static_field` (config/shape,
   recompile-triggering) vs pytree-leaf (advanced by the step) is the machine-checked form of "what
   the flow map needs". IT should classify every slot as domain-config (static) or state (advanced) —
   with *no* third "cache" category *inside* the state; caches live outside it (as neighbor lists do).

4. **Use the allocate/update jit-boundary for buffers, with capacity as a validity contract (P2/P3).**
   Cold, shape-inferring `allocate_buffers` once; hot, fixed-shape, allocation-free `step!`. For any
   growable per-tracer buffer, adopt the `did_buffer_overflow` device-bit-checked-host-side pattern
   rather than preventing overflow in the hot loop.

5. **Adopt Dedalus's cadence scheduler for diagnostics/statistics.** The divisor-advance triggers for
   iteration/sim-time/wall-time, and especially the "nearest-step, no-drift" sim-time logic
   (`evaluator.py:256-265`), are a clean, transferable design for IT's observation callbacks — which
   today have no calendar.

6. **Batch-and-share-transforms for the occasional multi-diagnostic pass (P3).** When several
   diagnostics need the same transform, gather the union of required derived fields and pay the FFT
   once (Dedalus's `get_fields` + oscillate). Keep IT's preallocated stamped slots rather than
   Dedalus's allocate-per-pass.

7. **Make representation/freshness a property of the datum, not a comment (P2).** Dedalus's mutable
   `.layout` and `LockedField` are the robust cure for the silent-precondition footgun; IT's stamped
   slots are the static-layout, GPU-compatible version of the same idea — and an undeclared/absent
   chart should *error* (LockedField's "Cannot change locked layout"), never silently recompute.

8. **Keep expensive derived fields in the deposit+memoize middle, not at either pole (P3).** JAX-MD
   proves cheap observables want pure recompute; Dedalus proves many-at-once wants batching; IT's
   FFT-priced velocity/vorticity/RHS want producer-deposit memoization. Don't collapse P3 to one pole.

---

## Where IT's proposal differs from this beat's practice — risk or justified deviation

- **IT's persistent per-factor epochs vs Dedalus's throwaway per-pass uuid (P3).** Dedalus
  deliberately invalidates its cache every pass ("cache within evaluation, but not across
  evaluations"); IT proposes epochs that persist and are bumped per dynamical factor. This is a
  *genuine added obligation* — IT takes on cross-pass cache coherence that Dedalus refuses. **Risk,
  mitigable:** it is justified by IT's producer-deposit goal (reuse a value the loop already computed),
  but IT must test epoch bookkeeping hard (an under-bumped epoch = a silent stale read, the very class
  of bug P3 exists to kill). The safe fallback is Dedalus's discipline: within a single diagnostic
  pass, a uuid-style stamp is provably safe; reserve persistent epochs for the deposits the hot loop
  actually produces.

- **IT keeps in-place GPU mutation; JAX-MD is pure-functional (P1/P4).** IT cannot adopt
  `state.set(...)` literally without allocating. **Justified deviation:** IT has no XLA to discharge
  purity into buffer reuse, and GPU-primary/allocation-free is a hard invariant. The cost is that IT
  must *manually* enforce the state boundary (P3 working sets, P4 scratch ownership, P5 record
  doctrine) that JAX-MD's pytree/closure boundary gives for free — which is precisely what the P1–P5
  program does. The risk is under-enforcement (the P2 footgun and P4 shared bundle are symptoms);
  the deviation is justified only *if* P3–P5 are carried through completely.

- **IT reads time as a trajectory parameter; Dedalus makes time a field (P5).** **Justified
  deviation.** Dedalus needs time-as-field for symbolic time-dependent RHS terms; IT has no symbolic
  layer and forces through the run layer. Keeping time out of phase space is correct for IT and costs
  nothing it needs.

- **IT's DerivedFields has scheduling absent; Dedalus's observation layer has a scheduler (P3).**
  IT's proposal is *demand-driven only*. This is not wrong, but it is *incomplete* relative to
  Dedalus: IT will still need a cadence layer for statistics/output, and building it ad hoc invites
  the drift Dedalus's nearest-step logic already solves. **Low risk, recommend importing** the
  divisor-advance scheduler rather than reinventing it.

- **IT allows a "cache" conceptually between restart-record and logbook (P5); JAX-MD's state type has
  no cache category (caches live outside the state).** IT's three-way "restart / cache / logbook"
  split is finer than JAX-MD's two-way "dynamic-state / static-config" (with caches strictly outside
  state). **Not a risk, a clarification:** JAX-MD's practice suggests IT should keep caches (derived
  fields, neighbor-like buffers) *outside* the restart record entirely — reconstructable from state —
  so the litmus stays binary at the state boundary. IT's DerivedFields being *derived* (reconstructable)
  already respects this; the doctrine should state it explicitly.

---

## Sources

All paths relative to
`inspiration/arch/` in the repo (study-only clones; Dedalus GPL, never copied).

- **Dedalus** (v3 `core/` tree):
  - `dedalus/dedalus/core/evaluator.py` — Evaluator/Handler/Task; `check_schedule` (L246–276),
    `evaluate_scheduled`/`evaluate_handlers` (L90–146), `get_fields` union (L182–192), `add_task`
    (L278–308), per-pass uuid caching (L98–100).
  - `dedalus/dedalus/core/future.py` — `evaluate`/`store_last`/`id` memoization (L163–220),
    `check_conditions`/`enforce_conditions` (L242–251).
  - `dedalus/dedalus/core/field.py` — representation state machine: `change_layout`,
    `towards_grid_space`/`towards_coeff_space` (L661–700), `preset_layout` (L527–537), buffer
    ownership (L486–525), `LockedField` (L1013–1052).
  - `dedalus/dedalus/core/timesteppers.py` — `M.dt(X)+L.X=F` (L509–524), `RungeKuttaIMEX` seam and
    stage arithmetic (L539–644), scratch ownership (L539–550), `MultistepIMEX` (L95–150).
  - `dedalus/dedalus/core/solvers.py` — `state = problem.variables` (L65), F handler build
    (L569–574), `load_state` (L632–673), `sim_time`-as-field setter (L597–600), `step` (L683–711).
  - `dedalus/dedalus/core/distributor.py` — layout list and increment/decrement paths (L138–186,
    L601–657) [structure confirmed by grep].
- **JAX-MD** (2024+ `register_dataclass` tree):
  - `jax-md/jax_md/simulate.py` — `velocity_verlet` pure map (L227–243); `NVEState` (L249–271); `nve`
    init/step pair (L279–317); `NoseHooverChain` (L350–374); `NVTNoseHooverState` (L538–558);
    `nvt_nose_hoover` init/apply Gauss–Seidel sweep (L631–669); `NVTLangevinState` with `rng`
    (L1073–1093) and its `step_fn` (L1172–1187); `NPTNoseHooverState` barostat DOF (L704–744).
  - `jax-md/jax_md/dataclasses.py` — `static_field` static/dynamic pytree split (L37–48),
    `register_dataclass` + `set` (L91–106).
  - `jax-md/jax_md/quantity.py` — pure observables `kinetic_energy` (L124–159), `force` via autodiff
    (L58–62), `temperature`/`pressure`/`stress` (L162, 202, 238).
  - `jax-md/jax_md/partition.py` — `PartitionErrorCode`/`PartitionError` (L494–538); `NeighborList`
    with `did_buffer_overflow` (L684–729); allocate/update jit-boundary docstring (L818–853);
    capacity overflow (L459–460); state-comparison rebuild via `lax.cond` on `reference_position`
    (L1146–1154).
