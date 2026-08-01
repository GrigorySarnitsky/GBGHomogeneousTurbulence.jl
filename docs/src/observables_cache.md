# The observables cache

## What it is for

A run integrates two fields and no others: the velocity ``\boldsymbol{u}`` and the passive scalar
``\varphi``. The two of them at one instant of time make up the **state**, held in spectral
representation as ``\hat{\boldsymbol{u}}`` and ``\hat\varphi``. A run has the state at discrete times
``t_0, t_1, t_2, \ldots, t_n, \ldots``, and between those times the run has no state.

Everything else a run computes is an **observable** — a function of the state at one ``t_n``, and
therefore rebuildable from the state exactly. Some are fields in either representation, some are
values at particle positions, and some are single numbers.

Components of a run need the same observable within one iteration. The velocity in physical
representation is the clearest case: at ``t_n`` the timestep control reduces it for the advective CFL,
the tracer set interpolates it onto the particles to start their push, and the generator's first stage
assembles the Lamb vector from it. Left to themselves they would each recover it from
``\hat{\boldsymbol{u}}`` and keep a copy — three recoveries and three resident fields where one of
each suffices.

The **observables cache** is where a component puts a value another component will read, instead of
holding it privately. To **cache** an observable is to keep its value at ``t_n`` there until something
reads it; the storage one cached observable occupies is its **slot**. An external consumer — a
callback, a statistics accumulator — reads through the same door, but the cache exists for the run's
own components, not for the consumer.

An **iteration** is everything a run does between ``t_n`` and ``t_{n+1}``: it measures the timestep,
records the tracer velocities, takes the step, advects the particles, and performs whatever reductions
its stopping test needs. It strictly contains the **step**, which advances
``(\hat{\boldsymbol{u}}, \hat\varphi)`` and is itself divided into the **stages** of the time scheme;
the timestep measurement and the tracer record sit in the iteration but outside the step. Every rule
below follows from one design choice, stated here rather than derived:

> **Caching an observable adds nothing to what an iteration computes or moves.**

To **compute** is to do arithmetic; to **move** is to carry bytes between memory and the processor.
The two are separate costs, and on the GPU this package targets, the second usually dominates: a
pointwise multiplication over a grid costs about ten arithmetic operations per point against
twenty-four bytes moved. Traffic here comes in whole-array sweeps, so the unit of movement is one
**pass** over the grid — a traversal touching every grid point once.

The choice therefore bounds an iteration's cost **in time**, both halves of it. It deliberately does
not bound cost in **memory**: a cached value occupies an array nothing else would need, and §3 is
about exactly that price. The opposite choice is defensible — an iteration could do extra work so that
a later read costs nothing — but this package caches only what some component computes anyway, so an
iteration's cost follows from the configuration and the stopping condition, never from what is read
afterwards.

Tracer particles are instruments rather than a second physics: probes of the flow, each carrying a
state of its own — its position — advanced by its own equation. Where this page says *the state*, it
means the fluid's.

---

## 1. What the cache may hold

Two questions settle the matter, in order.

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

**May the cache hold it?** The design choice says caching adds nothing to what an iteration computes
or moves, and that is two claims, one per half of the cost. Each becomes a test:

- **Arithmetic — some component must compute it anyway.** An iteration fills the cache as it produces
  the values `(not yet — §6)`. An observable no component computes could enter the cache only by
  making the iteration compute it, which the choice forbids.
- **Traffic — some component must already hold it whole.** Writing out a value that exists only
  piecewise inside one traversal costs a pass the iteration does not already perform. A value is
  **materialized** when a component has it whole somewhere; the cache holds nothing that is not
  materialized.

The second test excludes the integrand of a fused reduction. To compute ``k``, an iteration sums
``\lvert\hat{\boldsymbol{u}}(\boldsymbol{\kappa})\rvert^{2}`` over wavenumbers in one traversal,
forming every value and keeping none. Those values are twice the modal energy density, a field an
anisotropy study wants; writing it out would cost a grid-sized store, though no new arithmetic. It
is not ``E(\kappa)``, which is half the sum of those values over each wavenumber shell and needs a
binning pass.

---

## 2. When a cached value is valid

**Nothing in the cache is ever recomputed.** The schedule is fixed when the cache is built and runs
identically on every iteration: the same observables are deposited, at the same point, by the same
components. A read either finds the value that the schedule left, or fails. There is no path —
internal or on request — by which reading causes a computation.

That is what makes the rules below refusals rather than inconveniences. A cache that quietly rebuilt a
stale value could never report a scheduling error; it would convert one into a doubled transform count
that no ledger catches, since a ledger freezes the intended schedule. Because the schedule is fixed,
an iteration's transform and traffic counts are exact constants of the configuration rather than
averages over a run, and the frozen ledgers report the true cost.

**The iteration deposits at its end**, from the state it has just produced `(not yet — §6)`. That
recovery — the inverse transform producing the field in physical representation — is the next
iteration's first-stage recovery moved earlier, so it costs nothing: the next iteration reads instead
of recovering. The deposit seeding the initial state is free on the same terms, since the first
iteration reads it instead of recovering, but it must happen when the cache is built or the first read
at ``t_0`` finds nothing. Only the last deposit of a run has no successor to fold into, so a run of
``n`` iterations pays ``n+1`` recoveries where building on demand would pay ``n`` — one extra per run,
not per iteration.

**A stamp says what a slot holds** `(not yet — §6)`, and takes three values: the observable at a named
``t_n``, or the producer's scratch, or nothing yet deposited. A read is served only in the first case,
and only when the named time is the current one; otherwise it raises. What a stale read reports is
that the schedule is wrong — the caller asked at a moment the schedule does not fill — and the only
repair is to fix the schedule.

**A slot belongs to the component that produces it** `(not yet — §6)`, which owes a correct value and
stamp at every boundary. Any component may take the array as scratch mid-iteration, and taking it
clears the stamp; this is what would let the Lamb vector be assembled into the vorticity's own slot
rather than the third array §4.3 accounts for. While the slot holds the Lamb vector its stamp says
*scratch*, so a read raises rather than returning a mislabelled field. Taking a slot costs no
transform, since the owner deposits at the end of the iteration from the state it has just produced,
which it would recover anyway. What it costs is reads: a slot taken before the last reader of that
observable makes that read raise, so the schedule must order the two.

**Every declared slot is deposited every iteration**, and a boundary reached with one still unstamped
raises `(not yet — §6)`. A slot nobody fills would hold scratch for the rest of the run and raise on
every later read; checking at the boundary names the fault where it happened.

Code that writes the state outside an iteration — a reseed, a filter — must announce it by calling
[`resolved_fields_modified!`](@ref), which clears every stamp `(not yet — §6)`, so that reads raise
until the next deposit. That interval belongs to whoever made the change: the recoveries are exported,
so a caller who mutates the state mid-run computes what they need themselves, in their own buffer.

Numbers follow the same rule on a different schedule. Under `run!` the loop measures the maximum speed
at ``t_n`` because the timestep control needs it to choose ``\Delta t``, and measures ``\varepsilon``
and ``k`` there too when the run is budgeted in turnovers or stopped on a condition. They are stamped
at ``t_n`` like every other observable `(not yet — §6)`, so a stopping test called before the step
reads ``\varepsilon`` for free, and a read after the step raises rather than returning the previous
boundary's value.

---

## 3. What caching costs

Caching changes no transform an iteration performs (§4.3), so beyond the one extra recovery per run of
§2 it is a memory decision and never a time decision. It costs at one of three levels:

| what the producing component does with the value | cost of caching it |
|---|---|
| holds it whole and does not need that array again | nothing |
| holds it whole but needs that array again | one array, for the component to write its next result elsewhere |
| never holds it whole | one array **and** a grid-sized store — refused (§1) |

A vector field on the grid is ``3N^{3}`` reals: 384 MiB at ``N = 256`` in double precision, 192 MiB in
single. A velocity-only run under `TwoThirds` or `HouLi` carries ten vector-shaped fields, five in each
representation — about 3.8 GiB at that size, before the scalar-shaped registers.

Which observables a run caches is fixed when its [`ObservablesCache`](@ref) is constructed, and a run's
footprint follows from that declaration. Declaring an observable no configured component produces is
an error at construction rather than a failure at the first read `(not yet — §6)`, and one not
declared at all is absent, so reading it raises. Which level a field sits at is a property of the
configuration, so the cache can price a declaration when it is made and report what the declared set
added `(not yet — §6)`; §5 states the cost wherever it is not the first level. Over-declaring stays a
legitimate choice, paid knowingly.

Numbers are cached without declaration `(not yet — §6)`, because ``O(1)`` of storage is not worth a
decision. Which numbers an iteration computes depends on the run. A turnover-budgeted or
condition-stopped `run!` measures ``\varepsilon`` and ``k`` each iteration, and an adaptive timestep
measures the maximum speed; a `warmup!` watching for stationarity measures the derivative skewness at
its sampling cadence, and the scalar variance too when the run carries a forced scalar.

---

## 4. The system, and what its iteration computes

One configuration fixes the system: a mask dealiasing rule (`TwoThirds` or `HouLi`, each removing the
aliased wavenumbers by a per-wavenumber multiplication), a three-stage scheme, the default rescaling
velocity forcing, an adaptive timestep. Those axes and the stopping condition fix an iteration's work;
a declaration does not.

### 4.1 The equations

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

### 4.2 How a step treats each term

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

### 4.3 Transforms and arrays

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
recovery rather than adding to it, so an iteration recovers a field once whether or not it is cached.
These transforms carry essentially all of the arithmetic: a scalar transform costs of order ``10^{2}``
floating-point operations per grid point, a pointwise multiplication of order ten.

Because the pointwise product writes into a third array, the vorticity survives the evaluation — three
vector arrays in physical representation at once. Assembling the Lamb vector into the vorticity's own
array, as §2 describes, would need two. The backend's cross product blocks that today: it guards
against writing into one of its own operands by allocating a temporary and copying back, and the copy
costs more than the one array the reuse would save. Taking the reuse therefore waits on a backend path
that permits the in-place write, the kernel itself being safe — each output element reads only its own
grid point.

The tracer scheme samples the velocity twice. The first sample, the **trajectory sample**, is taken at
``t_n`` at the particle's own position; the second at ``t_{n+1}``, at a predicted position the particle
never reaches. Both are ``M\times3`` arrays, interpolated with the
tracer set's scheme — a Catmull–Rom spline by default, so the sampled velocity is continuously
differentiable along a trajectory.

---

## 5. What this system caches

Both states are always present — the fluid's and the probes'. Tracers consume a field and produce
values at points; they hold no field. **Cached** takes three values: *declared*, named when the cache
is constructed; *always*, cached without a declaration, as the numbers of §3 are; and *never*, refused
by §1. **Built** says whether the package holds it today; it is `—` where *Cached* is *never*.

| Observable | Where it lives | Cached | Built | Producer, or reason |
|---|---|---|---|---|
| ``\boldsymbol{u}`` | physical, grid | declared | yes | stage 1; read by the CFL, the tracers, the Lamb assembly |
| ``\boldsymbol{\omega}`` | physical, grid | declared | yes | stage 1; read by the Lamb assembly. Costs one array while §4.3's reuse is blocked |
| ``\varphi`` | physical, grid | declared | no | stage 1; read by the flux assembly |
| ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))``, the trajectory sample | ``M\times3`` at points | declared | yes | recorded before the step; read by `advect!` and by Lagrangian statistics |
| ``\mathbb P(\boldsymbol{u}\times\boldsymbol{\omega})``, dealiased | spectral, grid | declared | no | the generator; costs one array |
| ``-\nabla\cdot(\boldsymbol{u}\varphi)``, dealiased | spectral, grid | declared | no | the generator; costs one array |
| ``\boldsymbol{u}\times\boldsymbol{\omega}`` | physical, grid | declared | no | the generator; each later stage reuses the array, and a scalar reuses it for the flux |
| ``\varepsilon``, ``k``, max speed, ``\langle\varphi^{2}\rangle``, skewness | one number | always | no | the loop, when the run's options measure them (§3) |
| ``\boldsymbol{S}``, ``\det\boldsymbol{S}`` | physical, grid | declared | no | the skewness gate of `warmup!` materializes and discards both; no `run!` iteration forms them |
| ``\lvert\hat{\boldsymbol{u}}\rvert^{2}`` per mode | spectral, grid | never | — | not materialized: formed inside a fused reduction (§1) |
| ``\nu\nabla^{2}\boldsymbol{u}``, ``\varkappa\nabla^{2}\varphi`` | — | never | — | not computed: applied as a multiplier (§4.2) |
| ``A(\boldsymbol{\kappa})\hat{\boldsymbol{u}}``; a rescaling forcing | — | never | — | not computed: the rate exists, the product does not; a rescaling has no rate |
| an additive stochastic ``\boldsymbol{f}`` | spectral, grid | never | — | not an observable: depends on the forcing's internal variables |
| stage values of ``\boldsymbol{u}``, ``\boldsymbol{\omega}``, ``\varphi`` | physical, grid | never | — | not an observable: carries ``\Delta t`` and the scheme's coefficients |
| velocity at the predicted particle position | ``M\times3`` at points | never | — | not an observable: the probe occupies no such position |
| ``E(\kappa)`` | per shell | never | — | not computed: no iteration forms it |
| the integral scale | one number | never | — | not computed: no iteration forms it |

### 5.1 Three points the table alone does not settle

**The pressure never appears.** The projection absorbs it and no stage computes it. Recovering it
means solving its Poisson equation separately; what the rotational form suppresses is the total head
``p + \tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}`` per unit density, so such a solve returns that
combination, from which ``\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}`` must be subtracted.

**Three objects are called dissipation.** The viscous term is the first, and §4.2 shows why no array
holds it. A local dissipation field is the second, and it comes in two forms: the true one
``2\nu S_{ij}S_{ij}(\boldsymbol{x})``, and the vorticity-based
``\nu\lvert\boldsymbol{\omega}\rvert^{2}(\boldsymbol{x})``, formable pointwise from a cached vorticity.
The two differ by a divergence, so they agree only in the mean and are not interchangeable pointwise.
The rate ``\varepsilon = \nu\langle\lvert\boldsymbol{\omega}\rvert^{2}\rangle`` is the third — a
number, obtained by summing over wavenumbers without building any field, and what
[`dissipation`](@ref) returns. It may be written with either form precisely because they agree in the
mean.

**Only one tracer sample reflects the flow.** The trajectory sample
``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` gives the velocity at the particle's own position and
moment, and is what a Lagrangian statistic accumulates. The second, at a predicted position differing
from the endpoint by ``\mathcal O(\Delta t^{2})``, exists only to give the position update its
second-order accuracy; it belongs to no instant along the trajectory and is not exposed.

---

## 6. The calls, and what is not built

!!! note "Provisional"
    How a run is assembled and driven is not settled, so the calls listed below may change. Nothing in
    §§1–5 depends on them.

[`physical_velocity`](@ref) and [`physical_vorticity`](@ref) return the cached field;
[`tracer_velocities`](@ref) returns the trajectory sample, and [`sample!`](@ref) interpolates any
physical field at the particle positions. [`resolved_fields_modified!`](@ref) announces a change made
outside an iteration — the *resolved fields* being the two integrated fields, not a filtered subset of
the scales.

```julia
domain = FixedDomain(64, 2π; dealiasing = TwoThirds(), element_type = Float64, array_type = Array)
cache  = ObservablesCache(domain; observables = (:velocity, :vorticity))
```

Today the cache holds only the velocity and the vorticity; the trajectory sample is held by the
particle set. Every other row of §5 is design, and so is every claim §§1–3 mark `(not yet — §6)`.
Seven gaps remain, each for a reason:

- **A field is built when it is first read, and a stale read silently rebuilds it.** The transform
  count is the same either way, since the next iteration's first stage consumes what a read builds;
  what the deposit buys is a read at ``t_n`` that computes nothing and a stale read that raises. The
  stamp bookkeeping is written to trigger a rebuild, not to refuse one — a single epoch counter that
  [`resolved_fields_modified!`](@ref) advances, rather than a stamp per slot that it clears.
- **A slot and the array its producer works in are separate arrays.** There is no scratch reuse and so
  no stamp-clearing, and a declaration costs a new allocation rather than a forgone overwrite. Sharing
  them requires refusing the mid-iteration read, which follows from the schedule above and is not
  implemented.
- **Nothing checks that every declared slot was deposited**, and the initial state is not deposited at
  all. Callbacks also fire only after the step, so there is no read point at ``t_0`` for a deposit to
  serve: ``n`` iterations have ``n+1`` boundaries, and the loop offers ``n`` of them.
- **A declaration is not validated against the configured components and its price is not reported.**
  Declaring an observable nothing produces is accepted and fails later; the added residency is
  computable at construction but not shown.
- **No numbers are cached**, so the reductions a loop already performs are discarded and a later
  consumer repeats them.
- **`Simulation` passes no `observables` argument**, so a declaration is reachable only by assembling
  a run's pieces directly. No narrower set is legal today: a step recovers both the velocity and the
  vorticity at its first stage, whatever a declaration says.
- **The trajectory sample lives with the particle set**, and the sample's own documentation states
  whether it is current, rather than a stamp carrying that status.

The decisions behind each are in the [architecture notes](architecture.md).
