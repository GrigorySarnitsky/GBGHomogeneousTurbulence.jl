# The observables cache

## 1. The design

### 1.1 What it is for

A run integrates two fields and no others: the velocity ``\boldsymbol{u}`` and the passive scalar
``\varphi``. The two of them at one instant of time make up the **state**, held in spectral
representation as ``\hat{\boldsymbol{u}}`` and ``\hat\varphi``. A run has the state at discrete times
``t_0, t_1, t_2, \ldots, t_n, \ldots``, and between those times the run has no state.

Everything else a run computes is an **observable** — a function of the state at one ``t_n``, and
therefore rebuildable from the state exactly. Some observables are fields in either representation,
some are values at particle positions, and some are single numbers.

Components of a run need the same observable within one iteration. The velocity in physical
representation is the clearest case: at ``t_n`` the timestep control needs its maximum for the
advective CFL, the tracer set interpolates it onto the particles to start their push, and the
generator's first stage assembles the Lamb vector from it. Left to themselves they would each recover
it from ``\hat{\boldsymbol{u}}`` and keep a copy — three recoveries and three resident fields where
one of each suffices.

The **observables cache** is where a component puts a value another component will read, instead of
holding it privately. To **cache** an observable is to keep its value at ``t_n`` there until something
reads it; the storage one cached observable occupies is its **slot**. An external consumer — a
callback, a statistics accumulator — reads through the same door, but the cache exists for the run's
own components, not for the consumer.

An **iteration** is everything a run does to advance from ``t_n`` to ``t_{n+1}``: the timestep
choice, the step, the particle push, and the deposits at its end. It strictly
contains the **step**, which advances ``(\hat{\boldsymbol{u}}, \hat\varphi)`` and which is itself
divided into the **stages** of the time scheme; the particle push and the deposits sit in the
iteration but outside the step. At each instant ``t_n`` between iterations, before any iteration
runs, sits the **observation**: the caller's callback reads the state and the cache, records what it wants, and
decides whether the run continues. Every rule of the cache architecture below
follows from one design choice, stated here rather than derived:

> **Caching an observable adds nothing to what an iteration computes, moves, or stores.**

To **compute** is to do arithmetic; to **move** is to carry bytes between memory and the processor;
to **store** is to keep bytes resident. The first two are the halves of an iteration's cost in time,
and on the GPU this package targets, the second usually dominates: a pointwise multiplication over a
grid costs one arithmetic operation per point against twenty-four bytes moved in double precision (twelve in single). Traffic here
comes in whole-array sweeps, so the unit of movement is one **pass** over the grid — a traversal
touching every grid point once. Storing is the cost in memory, the axis this package minimizes
first.

The choice therefore closes every cost axis at once: an iteration's arithmetic, traffic, and
residency all follow from the configuration, never from what is read afterwards. The opposite choice
is defensible — an iteration could do extra work, or keep extra arrays, so that a later read finds
more — but this package caches only what the iteration produces anyway. What the choice gives up is
control over the contents: since nothing may be added on any axis, what the cache holds is decided by
the solver's own schedule, not by the reader — §1.2 derives the contents and §1.4 states that price.

Where this page says *the state*, it means the fluid's — the resolved fields, the velocity and, when
the run carries one, the scalar. Tracer particles are instruments rather than a second physics:
probes of the flow, each carrying a state of its own — its position — which its own equation
advances.

### 1.2 What the cache holds

Nothing is cached by request, and there is no vocabulary to declare: the contents are derived from
the configuration. An observable is cached exactly when it passes four tests — the
first a matter of kind, the other three the design choice read along its three axes.

**Is the quantity an observable?** It must be determined by the state at a single ``t_n`` — by the
state alone, in every argument. A quantity carrying anything else fails: the step size ``\Delta t``, a
forcing's internal variables (the Ornstein–Uhlenbeck state of a stochastic source, say), the
coefficients of the time scheme. For a quantity along a trajectory the probe's position counts as an
argument and is bound by the same rule.

This is where the artifacts of the discretization fall out, and they are worth naming because they
look observable and are not. A Runge–Kutta stage value
``\boldsymbol{u}^{*} = \boldsymbol{u}_n + a \Delta t \boldsymbol{f}(\boldsymbol{u}_n)`` carries
``\Delta t`` and the scheme's coefficient ``a``; change the coefficients and it changes while the
trajectory does not, so it is the flow at no time at all. The velocity a tracer scheme evaluates at a
*predicted* position is the same failure in different clothes: the field value is genuine, but the
position is one the probe never occupies, so as a quantity along the trajectory it belongs to no
``t_n`` either.

**Computed — some component must produce it anyway.** This is the arithmetic axis: the iteration
fills the cache as it produces the values, and an observable no component computes
could enter only by making the iteration compute it, which the choice forbids. This test is where
``\varepsilon`` and ``k`` fall out: each is one reduction away from the cached fields, but no
component of the iteration performs that reduction *for the cache*, so it cannot hold them — whoever
wants one computes it at an observation (§2.4).

One case looks like a counterexample and is worth stating. The default `VarianceController` *does*
form the whole-field ``k``, and forms it at every stage, to size its own amplitude. Those values are
**mid-step** ones — each measured at a Runge–Kutta stage's own state and discarded — not the
observable at the iteration's end, which is what a slot must hold, so the case fails the surviving
test below rather than this one. A `VarianceRescaling(over = :total)` forms the same quantity once
per step and is the same story, its value taken before the rescale it sizes.

**Materialized — some component must hold it whole.** This is the traffic axis: writing out a value
that exists only piecewise inside one traversal costs a pass the iteration does not already perform.
The [`max_speed`](@ref) reduction is the boundary case. It sweeps ``\boldsymbol{u}`` once and keeps
only the largest speed ``\max_{\boldsymbol{x}}\lvert\boldsymbol{u}\rvert`` — the advective-CFL
bound — so the *maximum* is materialized — one number — while the per-point
speed field is never whole anywhere; there is nothing to cache.

**Surviving — the schedule must leave it at the iteration's end, in a *register* the iteration already
owns.** This is the memory axis: a cached value occupies no array of its own, because its slot *is*
the register its producer computed it in — a **register** being storage a component computes one
value into and overwrites at the next, holding nothing a reader should trust between times. An
observable is therefore cached exactly
when the iteration's schedule still holds it whole as the iteration ends, and register reuse is
what removes one: a register overwritten before the iteration's end has nothing left to deposit. The contents
are consequently a property of the solver's storage decisions, not a promise. §2.3's in-place product
reuse is the case that shows how narrow the dependence is: it takes the vorticity slot as the Lamb
vector's scratch mid-iteration, yet the vorticity is deposited at the iteration's end either way, so
the reuse moved the run's residency and left the contents untouched (§1.4).

### 1.3 When a cached value is valid

**Nothing in the cache is ever recomputed.** The schedule is fixed when the cache is built and runs
identically on every iteration: the same observables are deposited, at the same point, by the same
components. A read either finds the value that the schedule left, or throws. There is no path —
internal or on request — by which reading causes a computation.

That is what makes the rules below refusals rather than inconveniences. A cache that quietly rebuilt
a stale value could never report a scheduling error; it would convert one into a doubled transform
count that no ledger catches, since a ledger freezes the intended schedule. Because the schedule is
fixed, an iteration's transform and traffic counts are exact constants of the configuration rather
than averages over a run, and the frozen ledgers report the true cost.

**Everything is deposited at the end of the iteration, from the state it has just produced.**
For a field the deposit is the next iteration's first-stage recovery moved earlier,
so it costs nothing: the next iteration reads instead of recovering. The move stops at the
recoveries by a storage decision, not a value obstruction: the quadratic products and their
projection are state-only too, and would relocate value-identically at an unchanged transform
count — but they form in place over the velocity and vorticity slots (§2.3), so running them at the
iteration's end would destroy the deposited velocity and vorticity, and keeping both would cost the product array the
minimal-memory schedule deliberately does not carry. The nonlinear terms therefore stay in the next
step's first stage, and §2.4 lists them as not cached — the survival test deciding, as always. The numbers and the particle sample ride the same
schedule: the maximum speed is reduced from the just-deposited velocity for the next iteration's
timestep choice, and the particle velocities are interpolated from that velocity at each particle's new
position for the next advance's predictor.

**The loop observes, then advances.** The callback reads what it wants and answers whether the run
continues; only then does the next iteration run. Read from the callback's side it runs *after* each
iteration, which is how [`run!`](@ref) describes it — the same loop, named from the two ends. Stopping
is thereby the caller's decision on observables, not a run option — a budget in turnovers, for
instance, is a callback that accumulates ``\Delta t \varepsilon/k`` — the eddy-turnover clock — and says stop. Every instant a run
reaches is observed exactly once: the first because a deposit seeding the initial state is made when
the cache is built, the last because the observation that stops the run has already
read the state and the cache there. A run of ``n`` iterations has ``n+1`` observations. Only the last
closing deposit has no following iteration to fold into; it serves the final observation instead.
Relative to a cacheless solver serving only its own dynamics, the run therefore pays **one** extra
closing deposit per run: the state-only share of one first-stage evaluation, one reduction, and one
interpolation.
That is the cache's *added* cost. The reduction inside every other closing deposit recurs per
iteration, and is work the following first stage would have done anyway (§1.4).

**A slot's epoch says what it holds**, and takes three values: the observable at a
named ``t_n``, or the producer's scratch, or nothing yet deposited. (In the code the named time is
an **epoch** — a counter of state changes, one per dynamical factor: the fields' epoch advances with
every step or announced mutation, the particles' with every push, and a slot's epoch is current when
it equals its factor's epoch. An epoch is therefore **not** an iteration number: it counts changes to
the state rather than advances of the run.) A read is served only in the
first case, and only when the named time is the current one; otherwise it throws. What a stale read
reports is that the schedule is wrong — the caller asked at a moment the schedule does not fill — and
the only repair is to fix the schedule.

**A slot belongs to the component that produces it**; that component owes a correct
value at every iteration's end. Any component may take the array as scratch mid-iteration, and taking it
marks its epoch as scratch; this is what lets the Lamb vector be assembled into the vorticity's own slot,
with no product array of its own (§2.3). While the slot holds the Lamb vector its epoch says
*scratch*, so a read throws rather than returning a mislabelled field. Taking a slot costs no
transform, since the owner deposits at the iteration's end from the state it has just produced, which it would
recover anyway. What it costs is reads: a slot taken before the last reader of that observable makes
that read throw, so the schedule must order the two.

**Every slot is deposited on every iteration**, and the completeness check throws if a slot is still
with its epoch cleared. No caller can cause this — a slot exists only because the schedule fills it
— so the check guards the solver against itself: a slot nobody refilled would hold scratch for the
rest of the run and throw on every later read, and the completeness check names the fault where it
happened.

Code that writes the state outside an iteration — a reseed, a filter — must announce the change by
calling [`fields_modified!`](@ref), which advances the fields counter past every slot, so that reads
throw
until the next deposit. That interval belongs to whoever made the change: the recoveries are
exported, so a caller who mutates the state mid-run computes what they need themselves, in their own
buffer.

**The numbers follow the same rule on the same schedule.** The maximum speed is a cache entry like
any other — deposited at the iteration's end, at that epoch, and read by the next iteration's timestep choice,
which does scalar arithmetic on it and measures nothing. It is the only number the iteration
produces *and still holds at its end*, so it is the only number the cache holds; ``\varepsilon``,
``k``, or a variance is each one reduction away from the cached fields, performed by the observation
that wants it (§2.4). A constant-energy forcing does form ``k`` mid-step, but discards it before the
end — the qualification §1.2 draws.

### 1.4 What caching costs

It costs nothing on the memory axis, nothing on the transform axis, and — with one exception — nothing on the traffic axis: the closing deposit's maximum-speed reduction is one physical-vector pass every iteration, paid even by a hand-fixed-``\Delta t`` run that never reads the number, the price of a schedule that never varies with how the run is driven. Each clause of that is an accounting statement: every slot is a
register the iteration fills anyway (§1.2), every deposit is work the next first stage was about to do
(§1.3), and no
read computes. The cache is otherwise a naming-and-dating layer over storage the run already owns:
removing it would free no array, and the only work it *adds* over a cacheless solver is §1.3's final
closing deposit, paid once per run.

What the design pays instead is control over the contents. Since nothing may be added, what the cache
holds is decided by the solver's minimal-memory schedule, and it changes when the solver's storage
decisions change. A storage change removes an observable only when it stops the iteration *holding*
that value whole at its end — §2.3's in-place reuse does not, which is why it left
``\boldsymbol{\omega}`` in the cache. §2.4's table is therefore a consequence of the configuration
and the package version, not an interface a reader chooses from.

A reader who needs an absent observable computes it at an observation, from the state or the cached
fields, with the exported recoveries and reductions — in storage they own. The sizes say when that is
a real decision: a vector field on the grid is ``3N^{3}`` reals, 384 MiB at ``N = 256`` in double
precision and 192 MiB in single, so a callback materializing a field-sized diagnostic is buying a
third of a gigabyte; a number costs nothing worth counting.

For scale: a velocity-only run under `TwoThirds` or `HouLi` carries six vector-shaped fields — four
in spectral representation and two in physical — about 2.3 GiB at ``256^{3}`` in double precision,
before the scalar-shaped registers. It carried ten before this design landed: two physical vectors
existed only because a slot and its producer's register were separate arrays, a spectral one was the
cache's private recovery scratch, and a fourth held the quadratic products that now form in place
over the slots (§2.3) — all four are gone, and the ledger sits at the schedule's own lower bound in
every class.

---

## 2. The system

One configuration fixes the system: a mask dealiasing rule (`TwoThirds` or `HouLi`, each removing the
aliased wavenumbers by a per-wavenumber multiplication), a three-stage scheme, the default controller
velocity forcing, an adaptive timestep. Those axes fix the whole of an iteration's work — stopping belongs
to the observation (§1.3), and nothing a reader does changes what an iteration computes.

### 2.1 The equations

The system is incompressible Navier–Stokes in **rotational form** on a triple-periodic box, with a
passive scalar and tracer particles. The convective term is written through

```math
(\boldsymbol{u}\cdot\nabla)\boldsymbol{u}
  = \nabla\bigl(\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}\bigr) - \boldsymbol{u}\times\boldsymbol{\omega}
```

and the Leray–Helmholtz projection ``\mathbb{P}`` onto divergence-free fields absorbs both the pressure
and the gradient ``\nabla(\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2})``; the system then reads

```math
\begin{aligned}
\partial_t \boldsymbol{u}
  &= \mathbb{P}(\boldsymbol{u}\times\boldsymbol{\omega}) + \nu\nabla^{2}\boldsymbol{u} + \boldsymbol{f},
&\qquad \nabla\cdot\boldsymbol{u} &= 0, \\[4pt]
\partial_t \varphi
  &= -\nabla\cdot(\boldsymbol{u}\varphi) + \varkappa\nabla^{2}\varphi + f_\varphi, \\[4pt]
\frac{\mathrm{d}\boldsymbol{X}}{\mathrm{d}t} &= \boldsymbol{u}(t, \boldsymbol{X}(t)),
\end{aligned}
```

with ``\boldsymbol{\omega} = \nabla\times\boldsymbol{u}`` the vorticity, ``\nu`` the kinematic
viscosity, ``\varkappa = \nu/\mathrm{Sc}`` the scalar diffusivity, ``\boldsymbol{f}`` and ``f_\varphi``
the forcings, and ``\boldsymbol{X}(t)`` a tracer position. No projection acts on ``\boldsymbol{f}``:
every velocity forcing the package provides is already divergence-free, since a field-proportional one
scales a divergence-free field mode by mode and a stochastic source is projected as it is drawn. The
conservative scalar form holds the ``\boldsymbol{\kappa} = 0`` tendency at zero and fixes the split of
transforms below.

### 2.2 How a step treats each term

- **The quadratic terms** ``\mathbb{P}(\boldsymbol{u}\times\boldsymbol{\omega})`` and
  ``-\nabla\cdot(\boldsymbol{u}\varphi)``: evaluated as fields.
- **The viscous terms**: never formed. Diagonal in the spectral representation, they integrate
  exactly, and the step multiplies by
  ``\mathcal{E}(\boldsymbol{\kappa}) = \exp\!\bigl((A(\boldsymbol{\kappa}) - D\lvert\boldsymbol{\kappa}\rvert^{2})\tau\bigr)``
  instead, with ``D = \nu`` or ``\varkappa``, ``A(\boldsymbol{\kappa})`` a field-proportional forcing's
  rate, and ``\tau`` the sub-interval a stage advances.
- **A forcing** takes one of three routes. A field-proportional one folds its rate into that
  exponential; the rate array exists, the product ``A(\boldsymbol{\kappa})\hat{\boldsymbol{u}}`` never
  does. An additive source enters the right-hand side at each stage. An additive source is what a
  state-dependent rate takes, the default velocity forcing among them, because a rate frozen for the
  whole step would cost the scheme its order. A rescaling applies to the completed step as a map on
  the state, with no forcing field at all.

### 2.3 Transforms and arrays

The state lives in spectral representation, where derivatives are multiplications and the projection
acts wavenumber by wavenumber. A product of two fields is a convolution there, so a step evaluates
each quadratic term pseudospectrally, then removes the aliasing that the evaluation introduces,
according to its **dealiasing rule**. [`TwoThirds`](@ref) and [`HouLi`](@ref) are **mask rules**,
discarding or tapering the aliased wavenumbers in one per-wavenumber multiplication.
[`PhaseShift`](@ref) evaluates the term a second time on a half-cell-displaced grid and averages,
cancelling the aliases rather than filtering them, at exactly twice the transforms — for the
velocity and the scalar alike, since the scalar term reads the displaced velocity its stage's
velocity term has just built.

Under a mask rule one **evaluation** of the velocity term proceeds as follows: recover
``\boldsymbol{u}`` (3 inverse transforms); form
``\hat{\boldsymbol{\omega}} = \mathrm{i}\boldsymbol{\kappa}\times\hat{\boldsymbol{u}}`` and recover
``\boldsymbol{\omega}`` (3 inverse); multiply pointwise — the Lamb vector forming in place over the
vorticity's own array, as below — and transform it back (3 forward); apply ``\mathbb{P}`` and the
mask, both per-wavenumber multiplications.

Counts are per step of a three-stage scheme (`IFLowStorageRK3`); a scheme with a different stage
count scales them by its own.

| dealiasing rule | velocity only | with the scalar |
|:---|:---|:---|
| `TwoThirds`, `HouLi` | 18 inverse, 9 forward | 21 inverse, 18 forward |
| `PhaseShift` | 36 inverse, 18 forward | 42 inverse, 36 forward |

**No count depends on what the cache holds.** The deposit replaces the next iteration's first-stage
work rather than adding to it, so an iteration recovers a field once whether or not it is cached.
These transforms carry essentially all of the arithmetic: a scalar transform costs of order ``10^{1}``–``10^{2}``
floating-point operations per grid point, a pointwise multiplication of order one.

The pointwise product writes into one of its own operands: the backend's cross product reads each
grid point's whole fiber before writing, so the Lamb vector is assembled into the vorticity's own
array — the slot, taken as the producer's scratch exactly as §1.3 describes — and the scalar flux
into the velocity's. No third array exists, and the evaluation holds two vector arrays in physical
representation at once. The vorticity is deposited at the iteration's end either way, so the reuse changes the
run's residency, not the cache's contents.

The tracer scheme consumes two velocity samples per push. The first — the **particle velocities**
``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))``, the velocity sampled along the trajectories — is the
cache's deposit from the previous closing deposit; the
second is evaluated at ``t_{n+1}``, at a predicted position the particle never
reaches. Both are ``M\times3`` arrays, interpolated with the tracer set's scheme — a Catmull–Rom
spline by default, so the sampled velocity is continuously differentiable along a trajectory.

A multistep trajectory scheme looks further back, and the cache is where that history lives: built
with `history_depth` ``> 1`` it keeps a bounded ring of **past** particle-velocity samples —
`history_depth` ``- 1`` further ``M\times3`` arrays beyond the current slot — which `AdamsBashforth`
integrates over and an out-of-band reposition discards (`particles_modified!`). The history rides
the same epoch bookkeeping as the current sample; it is the one place the cache holds more than the
latest deposit, and it exists here rather than in the scheme's registers because the object that
owns the epoch owns the invalidation.

### 2.4 What it caches

Both states are always present — the fluid's and the probes'. Tracers consume a field and produce
values at points; they hold no field. The table below lists the observables of this system, one row
each. Its **Cached** column takes four values: *yes*, the schedule leaves the observable deposited
between iterations; *depends*, the observable survives in some configurations and not in others; *no*, a
genuine observable this schedule does not surface — the value at ``t_n`` is well-defined, and an
observation builds it itself in one act; and *never*, not an observable at all (§1.2's kind test) —
there is no moment to date it to, so no act at an observation builds it either. Its **Built** column says
whether the package holds the observable today, and reads `—` wherever *Cached* is not *yes*.

| Observable | Where it lives | Cached | Built | Producer, or reason |
|:---|:---|:---|:---|:---|
| ``\boldsymbol{u}`` | physical, grid | yes | yes | the closing recovery; read by the timestep choice, the tracer advance, the Lamb assembly, and observations |
| ``\boldsymbol{\omega}`` | physical, grid | yes | yes | the closing recovery; read by the Lamb assembly |
| ``\varphi`` | physical, grid | yes | yes | the closing recovery; read by the flux assembly |
| ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))``, the particle velocities | ``M\times3`` at points | yes | yes | the closing interpolation from the cached velocity; read by the next push and by Lagrangian statistics |
| the sample history, ``\boldsymbol{u}(t_{n-j}, \boldsymbol{X}(t_{n-j}))``, ``j = 1..\texttt{history\_depth}-1`` | ``M\times3`` each, a bounded ring | depends | yes | kept only when a multistep trajectory scheme asks for depth; rotated at each sample deposit, discarded by an out-of-band reposition |
| the maximum speed ``\max_{\boldsymbol{x}}\lvert\boldsymbol{u}\rvert`` | one number | yes | yes | the closing reduction over the cached velocity; read by the next timestep choice |
| ``\mathbb{P}(\boldsymbol{u}\times\boldsymbol{\omega})``, dealiased | spectral, grid | no | — | not surviving: since the products form in place over the velocity and vorticity slots (§2.3), assembling the term at the iteration's end would destroy the deposited velocity and vorticity — keeping both needs a product array the minimal-memory schedule does not carry |
| ``-\nabla\cdot(\boldsymbol{u}\varphi)``, dealiased | spectral, grid | no | — | not surviving, for the same reason as the row above |
| ``\boldsymbol{u}\times\boldsymbol{\omega}`` | physical, grid | no | — | not materialized as its own array: it forms in place over the vorticity slot and is consumed by the projection's transform (§2.3) |
| ``\varepsilon``, ``k``, ``\langle\varphi^{2}\rangle``, the derivative skewness | one number | no | — | not surviving: no component of the iteration holds one at its end; each is one reduction at an observation (a constant-energy forcing forms ``k`` mid-step and discards it) |
| ``E_n``, the per-shell energy | per shell | no | — | not computed: no iteration forms it, and it needs its own binning pass |
| the integral scale | one number | no | — | not computed: no iteration forms it |
| ``\boldsymbol{S}``, ``\det\boldsymbol{S}`` | physical, grid | no | — | not computed in an iteration; the skewness gate of `warmup!` materializes ``\boldsymbol{S}`` and discards it, while ``\det\boldsymbol{S}`` is formed per point in registers by a fused mapped mean and never materialized at all, at its own cadence |
| the speed ``\lvert\boldsymbol{u}\rvert`` | physical, grid | no | — | not computed as a field: [`max_speed`](@ref) forms the magnitude per grid point in registers and consumes it immediately, so it is never whole anywhere; materializing it would cost a pass the iteration does not perform (§1.2) |
| ``\nu\nabla^{2}\boldsymbol{u}``, ``\varkappa\nabla^{2}\varphi`` | — | no | — | not computed: the step multiplies by the integrating factor instead of forming the term (§2.2) |
| ``A(\boldsymbol{\kappa})\hat{\boldsymbol{u}}`` | — | no | — | not computed: the rate is folded into the integrating factor and the product never exists (§2.2) |
| a rescaling forcing's equivalent field | — | never | — | not an observable: defined only through the step it rescales, so it carries ``\Delta t`` |
| an additive stochastic ``\boldsymbol{f}`` | spectral, grid | never | — | not an observable: depends on the forcing's internal variables |
| stage values of ``\boldsymbol{u}``, ``\boldsymbol{\omega}``, ``\varphi`` | physical, grid | never | — | not an observable: carries ``\Delta t`` and the scheme's coefficients |
| velocity at the predicted particle position | ``M\times3`` at points | never | — | not an observable: the probe occupies no such position |

### 2.5 Three points the table alone does not settle

**The pressure never appears.** The projection absorbs it and no stage computes it. Recovering it
means solving its Poisson equation separately; what the rotational form suppresses is the total head
``p + \tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}`` per unit density, so such a solve returns that
combination, from which ``\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}`` must be subtracted.

**Three objects are called dissipation.** The viscous term is the first, and §2.2 shows why no array
holds it. A local dissipation field is the second, and it comes in two forms: the true one
``2\nu S_{ij}S_{ij}(\boldsymbol{x})``, and the vorticity-based
``\nu\lvert\boldsymbol{\omega}\rvert^{2}(\boldsymbol{x})``, formable pointwise from the cached
vorticity. The two differ by a divergence, so they agree only in the mean and are not interchangeable
pointwise. The rate ``\varepsilon = \nu\langle\lvert\boldsymbol{\omega}\rvert^{2}\rangle`` is the
third — a number, obtained by summing over wavenumbers without building any field, and what
[`dissipation`](@ref) returns when an observation applies it to the state. It may be written with
either form precisely because they agree in the mean.

**Only one tracer sample reflects the flow.** The particle velocities
``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` give the velocity at each particle's own position and
moment, and are what a Lagrangian statistic accumulates. The second, at a predicted position differing
from the endpoint by ``\mathcal{O}(\Delta t^{2})``, exists only to give the position update its
second-order accuracy; it belongs to no instant along the trajectory.

---

## 3. The code

!!! note "Provisional"
    How a run is assembled and driven is not settled, so the calls listed below may change. Nothing in
    §§1–2 depends on them.

### 3.1 The calls

The [`run!`](@ref) driver is the observation-first loop: after every iteration (and once at the seeded state) the callback reads the run and its
return decides continuation. The accessors [`velocity_physical`](@ref), [`vorticity_physical`](@ref),
and [`scalar_physical`](@ref) return the
deposited field, and [`max_speed`](@ref) the deposited number — each a checked read that throws when
no deposit is current. The closing [`deposit!`](@ref) ends an iteration (the run layer's `advance!` calls it
after every step; the `Simulation` constructor makes the seeding deposit), and
[`fields_modified!`](@ref) announces a change made outside an iteration — the *resolved
fields* being the two integrated fields — after which reads
throw until an explicit `deposit!`. The accessor [`particle_velocities`](@ref) returns the particle velocities —
a cached read like the fields' — and [`interpolate_at_particles!`](@ref) interpolates any physical field at the
particle positions.

```julia
domain = FixedDomain(; grid_points_per_axis = 64, side_length = 2π, dealiasing = TwoThirds(), element_type = Float64, array_type = Array)
cache  = ObservablesCache(domain; scalar = true)   # the slots follow the configuration

# With tracers, the particle-velocities slot is the tracer set's own storage, passed in.
# The interpolation scheme comes from the field library, not from this package:
using GBGPeriodicFields: CatmullRom
tracers = Tracers(domain; number_of_particles = 1024, interpolation_scheme = CatmullRom)
cache   = ObservablesCache(domain; scalar = true, particle_velocities = tracers.particle_velocities)
```

### 3.2 Coverage — the page against the code

The cache itself is built as §§1–2 describe: automatic contents, closing deposits recorded at the new
epoch — the particle velocities included, against both epochs — three-valued slot epochs that
throw on a stale, taken, or never-deposited read, the seeding deposit at construction, the
deposit-completeness check, and the slot=register merge. The loop is the observation-first loop of §1.3:
`run!(callback, sim)` observes the run after every iteration and once before the first — ``n`` iterations, ``n + 1``
observations, the seeded ``t_0`` included — and the callback's return decides continuation, so
stopping is the caller's decision on observables and the budget vocabulary is gone. What §1.3
records as the storage decision — the nonlinear terms stay in the first stage because the in-place
products would otherwise destroy the deposited fields — closes the list: every mechanism this page describes exists in the code, and none exists that this
page omits. The decision record is in the [architecture notes](architecture.md).
