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
iteration but outside the step. At each boundary ``t_n``, before any iteration runs, sits the
**observation**: the caller's callback reads the state and the cache, records what it wants, and
decides whether the run continues `(not yet — §3.2)`. Every rule of the cache architecture below
follows from one design choice, stated here rather than derived:

> **Caching an observable adds nothing to what an iteration computes, moves, or stores.**

To **compute** is to do arithmetic; to **move** is to carry bytes between memory and the processor;
to **store** is to keep bytes resident. The first two are the halves of an iteration's cost in time,
and on the GPU this package targets, the second usually dominates: a pointwise multiplication over a
grid costs about ten arithmetic operations per point against twenty-four bytes moved. Traffic here
comes in whole-array sweeps, so the unit of movement is one **pass** over the grid — a traversal
touching every grid point once. Storing is the cost in memory, the axis this package minimizes
first.

The choice therefore closes every cost axis at once: an iteration's arithmetic, traffic, and
residency all follow from the configuration, never from what is read afterwards. The opposite choice
is defensible — an iteration could do extra work, or keep extra arrays, so that a later read finds
more — but this package caches only what the iteration produces anyway. What the choice gives up is
control over the contents: since nothing may be added on any axis, what the cache holds is decided by
the solver's own schedule, not by the reader — §1.2 derives the contents and §1.4 states that price.

Tracer particles are instruments rather than a second physics: probes of the flow, each carrying a
state of its own — its position — which its own equation advances. Where this page says *the state*, it
means the fluid's.

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
``\boldsymbol{u}^{*} = \boldsymbol{u}_n + a\,\Delta t\,\boldsymbol{f}(\boldsymbol{u}_n)`` carries
``\Delta t`` and the scheme's coefficient ``a``; change the coefficients and it changes while the
trajectory does not, so it is the flow at no time at all. The velocity a tracer scheme evaluates at a
*predicted* position is the same failure in different clothes: the field value is genuine, but the
position is one the probe never occupies, so as a quantity along the trajectory it belongs to no
``t_n`` either.

**Computed — some component must produce it anyway.** This is the arithmetic axis: the iteration
fills the cache as it produces the values, and an observable no component computes
could enter only by making the iteration compute it, which the choice forbids. This test is where
``\varepsilon`` and ``k`` fall out: each is one reduction away from the cached fields, but no
component of the iteration performs that reduction, so the cache cannot hold them — whoever wants one
computes it at an observation (§2.4).

**Materialized — some component must hold it whole.** This is the traffic axis: writing out a value
that exists only piecewise inside one traversal costs a pass the iteration does not already perform.
The maximum-speed reduction is the boundary case. It sweeps ``\boldsymbol{u}`` once, forming the
speed at every grid point and keeping only the largest, so the *maximum* is materialized — one number
— while the speed *field* is never whole anywhere and cannot be cached.

**Surviving — the schedule must leave it at the boundary, in a register the iteration already
owns.** This is the memory axis: a cached value occupies no array of its own, because its slot *is*
the register its producer computed it in. An observable is therefore cached exactly
when the iteration's schedule still holds it whole when the boundary arrives, and register reuse is
what removes one: a register overwritten before the boundary has nothing left to stamp. The contents
are consequently a property of the solver's storage decisions, not a promise — §2.3's blocked reuse
keeps the vorticity in the cache today, and landing that reuse will take it out (§1.4).

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

**Everything is deposited at the tail of the iteration, from the state it has just produced.**
For a field the deposit is the next iteration's first-stage recovery moved earlier,
so it costs nothing: the next iteration reads instead of recovering. The move is more general than
the recoveries. Everything in the next step's first stage that depends on the state alone — the
recoveries, the quadratic products, their dealiasing and projection — can run at the tail,
value-identical because nothing between the tail and the next first stage touches the state, and at
an unchanged transform count; only the forcing's contribution stays behind, since it needs the step
size the next iteration has not yet chosen. The numbers and the particle sample ride the same
schedule: the maximum speed is reduced from the just-deposited velocity for the next iteration's
timestep choice, and the trajectory sample is interpolated from that velocity at each particle's new
position for the next push's predictor.

**The observation comes before the iteration** `(not yet — §3.2)`. At each boundary the callback reads
what it wants and answers whether the run continues; only then does the next iteration run. Stopping
is thereby the caller's decision on observables, not a run option — a budget in turnovers, for
instance, is a callback that accumulates ``\Delta t/\tau`` and says stop. Every boundary a run
reaches is observed exactly once: the first because a deposit seeding the initial state is made when
the cache is built, the last because the observation that stops the run has already
read the state and the cache there. A run of ``n`` iterations has ``n+1`` observations. Only the last
tail has no following iteration to fold into — it serves the final observation instead — so, relative
to a solver with no cache serving only its own dynamics, the run pays one extra tail: the state-only
share of one first-stage evaluation, one reduction, and one interpolation, per run rather than per
iteration.

**A stamp says what a slot holds**, and takes three values: the observable at a
named ``t_n``, or the producer's scratch, or nothing yet deposited. A read is served only in the
first case, and only when the named time is the current one; otherwise it throws. What a stale read
reports is that the schedule is wrong — the caller asked at a moment the schedule does not fill — and
the only repair is to fix the schedule.

**A slot belongs to the component that produces it**; that component owes a correct
value and stamp at every boundary. Any component may take the array as scratch mid-iteration, and taking it
clears the stamp; this is what would let the Lamb vector be assembled into the vorticity's own slot
rather than the third array §2.3 accounts for. While the slot holds the Lamb vector its stamp says
*scratch*, so a read throws rather than returning a mislabelled field. Taking a slot costs no
transform, since the owner deposits at the tail from the state it has just produced, which it would
recover anyway. What it costs is reads: a slot taken before the last reader of that observable makes
that read throw, so the schedule must order the two.

**Every slot is deposited on every iteration**, and the boundary check throws if a slot is still
unstamped there. No caller can cause this — a slot exists only because the schedule fills it
— so the check guards the solver against itself: a slot nobody refilled would hold scratch for the
rest of the run and throw on every later read, and the boundary check names the fault where it
happened.

Code that writes the state outside an iteration — a reseed, a filter — must announce the change by
calling [`resolved_fields_modified!`](@ref), which clears every stamp, so that reads
throw
until the next deposit. That interval belongs to whoever made the change: the recoveries are
exported, so a caller who mutates the state mid-run computes what they need themselves, in their own
buffer.

**The numbers follow the same rule on the same schedule.** The maximum speed is a cache entry like
any other — deposited at the tail, stamped there, and read by the next iteration's timestep choice,
which does scalar arithmetic on it and measures nothing. It is the only number the
iteration produces, so it is the only number the cache holds; ``\varepsilon``, ``k``, or a variance
is each one reduction away from the cached fields, performed by the observation that wants it (§2.4).

### 1.4 What caching costs

It costs nothing, on any of the three axes. That is bookkeeping, not a slogan: every slot is a
register the iteration fills anyway (§1.2), every deposit is work the next first stage was about to do
(§1.3), and no
read computes. The cache is a naming-and-stamping layer over storage the run already owns: removing
it would free no array, and the only work it adds is §1.3's final tail — the one tail whose deposits no
iteration consumes, kept because it serves the final observation, and paid per run rather than per
iteration.

What the design pays instead is control over the contents. Since nothing may be added, what the cache
holds is decided by the solver's minimal-memory schedule, and it changes when the solver's storage
decisions change: §2.3's blocked reuse keeps ``\boldsymbol{\omega}`` in the cache today, and the
release that lands the reuse removes it. §2.4's table is therefore a consequence of the configuration
and the package version, not an interface a reader chooses from.

A reader who needs an absent observable computes it at an observation, from the state or the cached
fields, with the exported recoveries and reductions — in storage they own. The sizes say when that is
a real decision: a vector field on the grid is ``3N^{3}`` reals, 384 MiB at ``N = 256`` in double
precision and 192 MiB in single, so a callback materializing a field-sized diagnostic is buying a
third of a gigabyte; a number costs nothing worth counting.

For scale: a velocity-only run under `TwoThirds` or `HouLi` carries seven vector-shaped fields —
four in spectral representation and three in physical — about 2.8 GiB at ``256^{3}`` in double
precision, before the scalar-shaped registers. It carried ten before the slot-and-register merge
landed: two physical vectors existed only because a slot and its producer's register were separate
arrays, and a third, spectral one was the cache's private recovery scratch — all three are gone, and
the ledger now sits at the schedule's own lower bound. Landing §2.3's register reuse would remove
one more array.

---

## 2. The system

One configuration fixes the system: a mask dealiasing rule (`TwoThirds` or `HouLi`, each removing the
aliased wavenumbers by a per-wavenumber multiplication), a three-stage scheme, the default rescaling
velocity forcing, an adaptive timestep. Those axes fix the whole of an iteration's work — stopping belongs
to the observation (§1.3), and nothing a reader does changes what an iteration computes.

### 2.1 The equations

The system is incompressible Navier–Stokes in **rotational form** on a triple-periodic box, with a
passive scalar and tracer particles. The convective term is written through

```math
(\boldsymbol{u}\cdot\nabla)\boldsymbol{u}
  = \nabla\big(\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}\big) - \boldsymbol{u}\times\boldsymbol{\omega}
```

and the Leray–Helmholtz projection ``\mathbb P`` onto divergence-free fields absorbs both the pressure
and the gradient ``\nabla(\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2})``; the system then reads

```math
\begin{aligned}
\frac{\partial \boldsymbol{u}}{\partial t}
  &= \mathbb P\,(\boldsymbol{u}\times\boldsymbol{\omega}) + \nu\nabla^{2}\boldsymbol{u} + \boldsymbol{f},
&\qquad \nabla\cdot\boldsymbol{u} &= 0, \\[4pt]
\frac{\partial \varphi}{\partial t}
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

- **The quadratic terms** ``\mathbb P(\boldsymbol{u}\times\boldsymbol{\omega})`` and
  ``-\nabla\cdot(\boldsymbol{u}\varphi)``: evaluated as fields.
- **The viscous terms**: never formed. Diagonal in the spectral representation, they integrate
  exactly, and the step multiplies by
  ``\mathcal E(\boldsymbol{\kappa}) = \exp\big((A(\boldsymbol{\kappa}) - D\lvert\boldsymbol{\kappa}\rvert^{2})\tau\big)``
  instead, with ``D = \nu`` or ``\varkappa``, ``A(\boldsymbol{\kappa})`` a field-proportional forcing's
  rate, and ``\tau`` the sub-interval a stage advances.
- **A forcing** takes one of three routes. A field-proportional one folds its rate into that
  exponential; the rate array exists, the product ``A(\boldsymbol{\kappa})\hat{\boldsymbol{u}}`` never
  does. An additive source enters the right-hand side at each stage. A rescaling applies to the
  completed step as a map on the state, with no forcing field at all; the default velocity forcing is
  of this kind.

### 2.3 Transforms and arrays

The state lives in spectral representation, where derivatives are multiplications and the projection
acts wavenumber by wavenumber. A product of two fields is a convolution there, so a step evaluates
each quadratic term pseudospectrally, then removes the aliasing that the evaluation introduces,
according to its **dealiasing rule**. [`TwoThirds`](@ref) and [`HouLi`](@ref) are **mask rules**,
discarding or tapering the aliased wavenumbers in one per-wavenumber multiplication.
[`PhaseShift`](@ref) evaluates the term a second time on a half-cell-displaced grid and averages,
cancelling the aliases rather than filtering them, at twice the transforms — and, with the scalar,
nine inverse transforms more than twice, because the scalar term re-recovers a displaced velocity the
velocity term already built.

Under a mask rule one **evaluation** of the velocity term proceeds in five operations: recover
``\boldsymbol{u}`` (3 inverse transforms); form
``\hat{\boldsymbol{\omega}} = \mathrm i\boldsymbol{\kappa}\times\hat{\boldsymbol{u}}`` and recover
``\boldsymbol{\omega}`` (3 inverse); multiply pointwise into a third array, giving the Lamb vector;
transform it back (3 forward); apply ``\mathbb P`` and the mask, both per-wavenumber multiplications.

| dealiasing rule | velocity only | with the scalar |
|---|---|---|
| `TwoThirds`, `HouLi` | 18 inverse, 9 forward | 21 inverse, 18 forward |
| `PhaseShift` | 36 inverse, 18 forward | 51 inverse, 36 forward |

**No count depends on what the cache holds.** The deposit replaces the next iteration's first-stage
work rather than adding to it, so an iteration recovers a field once whether or not it is cached.
These transforms carry essentially all of the arithmetic: a scalar transform costs of order ``10^{2}``
floating-point operations per grid point, a pointwise multiplication of order ten.

Because the pointwise product writes into a third array, the vorticity survives the evaluation — three
vector arrays in physical representation at once. Assembling the Lamb vector into the vorticity's own
array, as §1.3 describes, would need two. The backend's cross product no longer blocks that: its
kernel reads each grid point's whole fiber before writing, so the destination may be one of its own
operands, and taking the reuse is now a scheduling change here rather than a backend request. It is
not yet taken `(not yet — §3.2)`; while the third array stands, the vorticity slot is untouched by
the assembly, and the vorticity is deposited at the tail either way — what the reuse changes is the
product array, not the cache's contents.

The tracer scheme consumes two velocity samples per push. The first, the **trajectory sample**
``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))``, is the cache's deposit from the previous tail
`(not yet — §3.2)`; the second is evaluated at ``t_{n+1}``, at a predicted position the particle never
reaches. Both are ``M\times3`` arrays, interpolated with the tracer set's scheme — a Catmull–Rom
spline by default, so the sampled velocity is continuously differentiable along a trajectory.

### 2.4 What it caches

Both states are always present — the fluid's and the probes'. Tracers consume a field and produce
values at points; they hold no field. The table below lists the observables of this system, one row
each. Its **Cached** column takes four values: *yes*, the schedule leaves the observable at the
boundary; *depends*, the observable survives in some configurations and not in others; *no*, a
genuine observable this schedule does not surface — the value at ``t_n`` is well-defined, and an
observation builds it itself in one act; and *never*, not an observable at all (§1.2's kind test) —
there is no time to stamp, so no act at an observation builds it either. Its **Built** column says
whether the package holds the observable today, and reads `—` wherever *Cached* is not *yes*.

| Observable | Where it lives | Cached | Built | Producer, or reason |
|---|---|---|---|---|
| ``\boldsymbol{u}`` | physical, grid | yes | yes | the tail recovery; read by the timestep choice, the tracer push, the Lamb assembly, and observations |
| ``\boldsymbol{\omega}`` | physical, grid | yes | yes | the tail recovery; read by the Lamb assembly |
| ``\varphi`` | physical, grid | yes | yes | the tail recovery; read by the flux assembly |
| ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))``, the trajectory sample | ``M\times3`` at points | yes | yes | the tail interpolation from the cached velocity; read by the next push and by Lagrangian statistics |
| the maximum speed | one number | yes | yes | the tail reduction over the cached velocity; read by the next timestep choice |
| ``\mathbb P(\boldsymbol{u}\times\boldsymbol{\omega})``, dealiased | spectral, grid | yes | no | the relocated first-stage evaluation (§1.3); read by the next step's first stage |
| ``-\nabla\cdot(\boldsymbol{u}\varphi)``, dealiased | spectral, grid | yes | no | the relocated first-stage evaluation (§1.3); read by the next step's first stage |
| ``\boldsymbol{u}\times\boldsymbol{\omega}`` | physical, grid | depends | — | survives the tail of a velocity-only run; with a scalar, the flux ``\boldsymbol{u}\varphi`` reuses its register and is the survivor instead |
| ``\varepsilon``, ``k``, ``\langle\varphi^{2}\rangle``, the derivative skewness | one number | no | — | not computed: no component of the iteration forms them; each is one reduction at an observation |
| ``E(\kappa)`` | per shell | no | — | not computed: no iteration forms it, and it needs its own binning pass |
| the integral scale | one number | no | — | not computed: no iteration forms it |
| ``\boldsymbol{S}``, ``\det\boldsymbol{S}`` | physical, grid | no | — | not computed in an iteration; the skewness gate of `warmup!` materializes and discards both, at its own cadence |
| the speed ``\lvert\boldsymbol{u}\rvert`` | physical, grid | no | — | not materialized: formed pointwise inside the maximum-speed reduction and kept nowhere; whole, it would cost a pass the iteration does not perform (§1.2) |
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

**Only one tracer sample reflects the flow.** The trajectory sample
``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` gives the velocity at the particle's own position and
moment, and is what a Lagrangian statistic accumulates. The second, at a predicted position differing
from the endpoint by ``\mathcal O(\Delta t^{2})``, exists only to give the position update its
second-order accuracy; it belongs to no instant along the trajectory and is not exposed.

---

## 3. The code

!!! note "Provisional"
    How a run is assembled and driven is not settled, so the calls listed below may change. Nothing in
    §§1–2 depends on them.

### 3.1 The calls

[`velocity_physical`](@ref), [`vorticity_physical`](@ref), and [`scalar_physical`](@ref) return the
deposited field, and [`max_speed`](@ref) the deposited number — each a checked read that throws when
no deposit is current. [`deposit!`](@ref) closes an iteration (the run layer's `advance!` calls it
after every step; the `Simulation` constructor makes the seeding deposit), and
[`resolved_fields_modified!`](@ref) announces a change made outside an iteration — the *resolved
fields* being the two integrated fields, not a filtered subset of the scales — after which reads
throw until an explicit `deposit!`. [`tracer_velocities`](@ref) returns the trajectory sample, and
[`sample!`](@ref) interpolates any physical field at the particle positions.

```julia
domain = FixedDomain(64, 2π; dealiasing = TwoThirds(), element_type = Float64, array_type = Array)
cache  = ObservablesCache(domain; scalar = true)   # the slots follow the configuration — nothing is declared
```

### 3.2 What is not built

The cache itself is built as §§1–2 describe: automatic contents, tail deposits stamped at the new
boundary, three-valued stamps that throw on a stale, taken, or never-deposited read, the seeding
deposit at construction, the boundary completeness check, and the slot=register merge. Three gaps
remain, each a piece of the run layer's redesign rather than of the cache:

- **Stopping belongs to `run!`, not to the observation.** The loop takes its budget and stopping
  condition as arguments (`turnovers`, `time`, `steps`, `stop`), measures ``\varepsilon`` and ``k``
  itself when the budget or the stopping condition needs them, and ignores the callback's return
  value, so a callback cannot stop the run.
- **The callback fires only after the step.** A run of ``n`` iterations offers ``n`` observations of
  its ``n+1`` boundaries; the initial state — the seeded spectrum a validation run most wants — is
  never observed. With it comes the relocated first-stage evaluation of §1.3: the two dealiased
  nonlinear terms are still assembled at the next step's first stage, not deposited at the tail.
- **The trajectory sample lives with the particle set.** The sample's values are the boundary values
  (it is interpolated from the deposited velocity chart), but it is stored on the tracers and its
  own documentation states whether it is current, rather than a stamp carrying that status; the
  register reuse of §2.3 travels with the same strand.

The decisions behind each are in the [architecture notes](architecture.md).
