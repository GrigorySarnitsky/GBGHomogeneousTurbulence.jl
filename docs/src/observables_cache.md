# The observables cache

## What it is for

A run integrates two fields and no others: the velocity ``\boldsymbol{u}`` and the passive scalar
``\varphi``. The two of them at one instant make up the **state**, held in spectral representation as
``\hat{\boldsymbol{u}}`` and ``\hat\varphi``. A run has the state at ``t_0``, then at ``t_1``, and so
on through the discrete times where its steps begin and end; between those times it has no state.

Everything else a run computes is an **observable** — a function of the state at one ``t_n``, and
therefore rebuildable from it exactly. Some are fields in either representation, some are values at
particle positions, and some are single numbers.

Components of a run need the same observable within one step. The velocity in physical representation
is the clearest case: the timestep control reduces it for the advective CFL, the tracer set
interpolates it onto the particles before and after the step, and the generator's first stage
assembles the Lamb vector from it. Left to themselves they would each recover it from
``\hat{\boldsymbol{u}}`` and keep a copy — three recoveries and three resident fields where one of
each suffices.

The **observables cache** is where a component puts a value another will read, instead of holding it
privately. To **cache** an observable is to keep its value at ``t_n`` there until something reads it.
An external consumer — a callback, a statistics sink — reads through the same door, but the cache
exists for the run's own components, not for the consumer.

A run's **cycle** is everything it does between ``t_n`` and ``t_{n+1}``: it measures the timestep,
records the tracer velocities, takes the step, advects the particles, and performs whatever reductions
its stopping test needs. The unit of movement within a cycle is one pass over the grid. Every rule
below follows from one design choice, stated here rather than derived:

> **Caching an observable adds nothing to what a cycle computes or moves.**

The opposite choice is defensible — a cycle could do extra work so that a later read costs nothing —
but this package caches only what some component computes anyway, so a cycle's cost follows from the
configuration and the stopping condition, never from what is read afterwards.

Tracer particles are instruments rather than a second physics: probes of the flow, each carrying a
state of its own — its position — advanced by its own equation. Where this page says *the state*, it
means the fluid's.

---

## 1. What the cache may hold

Two questions settle the matter, in order.

**Is the quantity an observable?** It must be fixed by the state at a single ``t_n``, and can fail
that requirement in two ways:

- **It depends on more than the state** — on the step size ``\Delta t``, on a forcing's internal
  variables (the Ornstein–Uhlenbeck state of a stochastic source, say), or on the coefficients of the
  scheme. The state alone will not rebuild it.
- **It is fixed at another instant.** A Runge–Kutta stage value is determined by the state *and* the
  discretization, so it is the flow at no instant at all. A trajectory quantity takes the probe's
  position as a second argument, and the same test binds that argument: the velocity at a *predicted*
  position is a stage value of the probe's integrator, evaluated where the probe never is.

A quantity failing the second test fails the first as well, since a stage value depends on
``\Delta t``; where both apply, this page names the second.

**May the cache hold it?** Two tests apply the design choice above.

- **In arithmetic — some component must compute it anyway.** The cache is written from the cycle, not
  from a read `(not yet — §6)`. An observable no component computes could enter it only by making the
  cycle compute it, which the choice forbids.
- **In passes over the grid — some component must already hold it whole.** Writing out a value that
  exists only piecewise inside one traversal costs a pass the cycle does not already perform. Call a
  value **materialized** when a component has it whole somewhere; the cache holds nothing that is not
  materialized.

The second test excludes the integrand of a fused reduction. To compute ``k``, a cycle sums
``\lvert\hat{\boldsymbol{u}}(\boldsymbol{\kappa})\rvert^{2}`` over wavenumbers in one traversal,
forming every value and keeping none. Those values are twice the modal energy density, a field an
anisotropy study wants; writing it out would cost a grid-sized store, though no new arithmetic. It
is not ``E(\kappa)``, which is half the sum of those values over each wavenumber shell and needs a
binning pass.

---

## 2. The currency contract

A cached value is worth nothing unless a reader can trust it. Three rules govern it, and no other
party touches the cache.

**The cycle writes each cached value at the cycle's end**, from the state just produced
`(not yet — §6)`. That recovery — the inverse transform that produces a field in physical
representation — is the next cycle's first-stage recovery moved earlier, so it costs nothing, provided
a next cycle follows and its first stage reads what is there. The last write of a run has no successor
to fold into and is not free.

**A read repairs a stale value.** Each cached value carries the stamp of the state it was built from;
a read compares that stamp against the run's counter and rebuilds on a mismatch. Given the
end-of-cycle write, this path runs only after the state changed outside a cycle — a reseed, a filter.
A completed step advances the counter itself; any other code that writes the state directly must
announce the change by calling [`resolved_fields_modified!`](@ref), or the next read returns the field
the state no longer has.

**A mid-cycle read is refused** `(not yet — §6)`. It asks for a value at a time that is not one of the
``t_n``, and none exists: mid-cycle the cache's arrays carry stage values, barred from being read for
the same reason §1 bars them from being cached.

Numbers are a structural exception to the timing. Under `run!` the loop measures the maximum speed at
``t_n`` because the timestep control needs it to choose ``\Delta t``, and measures ``\varepsilon`` and
``k`` there too when the run is budgeted in turnovers or stopped on a condition. A stopping test,
called before the step, reads ``\varepsilon`` for free. Anything reading after the step finds all
three at a superseded state and pays one reduction each to rebuild.

---

## 3. What caching costs

Caching changes no transform a cycle performs (§4.3), so it is a memory decision and never a time
decision. It costs at one of three levels:

| what the producing component does with the value | cost of caching it |
|---|---|
| holds it whole and does not need that array again | nothing |
| holds it whole but needs that array again | one array, for the component to write its next result elsewhere |
| never holds it whole | one array **and** a grid-sized store — refused (§1) |

A vector field on the grid is ``3N^{3}`` reals: 384 MiB at ``N = 256`` in double precision, 192 MiB in
single. A velocity-only run under `TwoThirds` or `HouLi` carries ten vector-shaped fields, five in each
representation — about 3.8 GiB at that size, before the scalar-shaped registers.

Which observables a run caches is fixed when its [`ObservablesCache`](@ref) is constructed. One not
declared there is absent, and reading it raises an error rather than rebuilding silently, so a run's
footprint follows from its construction. Which level a field sits at is a property of the cycle, not
something a caller can know in advance; §5 states the cost wherever it is not the first level.

Numbers are cached without declaration `(not yet — §6)`, because ``O(1)`` of storage is not worth a
decision. Which numbers a cycle computes depends on the run. A turnover-budgeted or condition-stopped
`run!` measures ``\varepsilon`` and ``k`` each iteration, and an adaptive timestep measures the
maximum speed; a `warmup!` watching for stationarity measures the derivative skewness at its sampling
cadence, and the scalar variance too when the run carries a forced scalar.

---

## 4. The system, and what its cycle computes

One configuration fixes the system: a mask dealiasing rule (`TwoThirds` or `HouLi`, each removing the
aliased wavenumbers by a per-wavenumber multiplication), a three-stage scheme, the default rescaling
velocity forcing, an adaptive timestep. Those axes and the stopping condition fix a cycle's work; a
declaration does not.

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
acts wavenumber by wavenumber. A product of two fields is a convolution there, so a cycle evaluates
each quadratic term pseudospectrally, then removes the aliasing that evaluation introduces, according
to its **dealiasing rule**. [`TwoThirds`](@ref) and [`HouLi`](@ref) are **mask rules**, discarding or
tapering the aliased wavenumbers in one per-wavenumber multiplication. [`PhaseShift`](@ref) evaluates
the term a second time on a half-cell-displaced grid and averages, cancelling the aliases rather than
filtering them, at twice the transforms — and, with the scalar, nine inverse transforms more than
twice, because the scalar term re-recovers a displaced velocity the velocity term already built.

Under a mask rule one **evaluation** of the velocity term proceeds in five operations: recover
``\boldsymbol{u}`` (3 inverse transforms); form
``\hat{\boldsymbol{\omega}} = \mathrm i\boldsymbol{\kappa}\times\hat{\boldsymbol{u}}`` and recover
``\boldsymbol{\omega}`` (3 inverse); multiply pointwise into a third array, giving the Lamb vector;
transform it back (3 forward); apply ``\mathbb P`` and the mask, both per-wavenumber multiplications.

| dealiasing rule | velocity only | with the scalar |
|---|---|---|
| `TwoThirds`, `HouLi` | 18 inverse, 9 forward | 21 inverse, 18 forward |
| `PhaseShift` | 36 inverse, 18 forward | 51 inverse, 36 forward |

**No count depends on what the cache holds.** The end-of-cycle write replaces the next cycle's
first-stage recovery rather than adding to it, so a cycle recovers a field once whether or not it is
cached. These transforms carry essentially all of the arithmetic: a scalar transform costs of order
``10^{2}`` floating-point operations per grid point, a pointwise multiplication of order ten.

Because the pointwise product writes into a third array, the vorticity survives the evaluation — three
vector arrays in physical representation at once. Overwriting the vorticity would need two, the second
cost level of §3, but the backend's cross product guards against writing into one of its own operands
by allocating a temporary and copying back, which costs more than the array that overwriting would
save.

The tracer scheme samples the velocity twice. The first sample, the **trajectory sample**, is taken at
the start of the step at the particle's own position; the second at the end of the step, at a
predicted position the particle never reaches. Both are ``M\times3`` arrays, interpolated with the
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
| ``\boldsymbol{\omega}`` | physical, grid | declared | yes | stage 1; read by the Lamb assembly. Costs one array (§4.3) |
| ``\varphi`` | physical, grid | declared | no | stage 1; read by the flux assembly |
| ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))``, the trajectory sample | ``M\times3`` at points | declared | yes | recorded before the step; read by `advect!` and by Lagrangian statistics |
| ``\mathbb P(\boldsymbol{u}\times\boldsymbol{\omega})``, dealiased | spectral, grid | declared | no | the generator; costs one array |
| ``-\nabla\cdot(\boldsymbol{u}\varphi)``, dealiased | spectral, grid | declared | no | the generator; costs one array |
| ``\boldsymbol{u}\times\boldsymbol{\omega}`` | physical, grid | declared | no | the generator; each later stage reuses the array, and a scalar reuses it for the flux |
| ``\varepsilon``, ``k``, max speed, ``\langle\varphi^{2}\rangle``, skewness | one number | always | no | the loop, when the run's options measure them (§3) |
| ``\boldsymbol{S}``, ``\det\boldsymbol{S}`` | physical, grid | declared | no | the skewness gate of `warmup!` materializes and discards both; no `run!` cycle forms them |
| ``\lvert\hat{\boldsymbol{u}}\rvert^{2}`` per mode | spectral, grid | never | — | not materialized: formed inside a fused reduction (§1) |
| ``\nu\nabla^{2}\boldsymbol{u}``, ``\varkappa\nabla^{2}\varphi`` | — | never | — | not computed: applied as a multiplier (§4.2) |
| ``A(\boldsymbol{\kappa})\hat{\boldsymbol{u}}``; a rescaling forcing | — | never | — | not computed: the rate exists, the product does not; a rescaling has no rate |
| an additive stochastic ``\boldsymbol{f}`` | spectral, grid | never | — | not an observable: depends on the forcing's internal variables |
| stage values of ``\boldsymbol{u}``, ``\boldsymbol{\omega}``, ``\varphi`` | physical, grid | never | — | not an observable: fixed at a stage |
| velocity at the predicted particle position | ``M\times3`` at points | never | — | not an observable: a stage value of the probe's integrator |
| ``E(\kappa)`` | per shell | never | — | not computed: no cycle forms it |
| the integral scale | one number | never | — | not computed: no cycle forms it |

### 5.1 Three points the table alone does not settle

**The pressure never appears.** The projection absorbs it and no stage computes it. Recovering it
means solving its Poisson equation separately; what the rotational form suppresses is the total head
``p + \tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}`` per unit density, so such a solve returns that
combination, from which ``\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}`` must be subtracted.

**Three objects are called dissipation.** The viscous term is one, and §4.2 shows why no array holds
it. The local dissipation ``\nu\lvert\boldsymbol{\omega}\rvert^{2}(\boldsymbol{x})`` is an ordinary
field, formable pointwise from a cached vorticity. The rate
``\varepsilon = \nu\langle\lvert\boldsymbol{\omega}\rvert^{2}\rangle`` is a number, obtained by summing
over wavenumbers without building any field, and is what [`dissipation`](@ref) returns.

**Only one tracer sample reflects the flow.** The trajectory sample
``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` gives the velocity at the particle's own position and
moment, and is what a Lagrangian statistic accumulates. The second, at a predicted position differing
from the endpoint by ``\mathcal O(\Delta t^{2})``, exists only to give the position update its
second-order accuracy; it is a stage value of the integrator and is not exposed.

---

## 6. The calls, and what is not built

!!! note "Provisional"
    How a run is assembled and driven is not settled, so the calls listed below may change. Nothing in
    §§1–5 depends on them.

[`physical_velocity`](@ref) and [`physical_vorticity`](@ref) return a cached field when its stamp
matches the state, and rebuild it otherwise; [`tracer_velocities`](@ref) returns the trajectory sample,
and [`sample!`](@ref) interpolates any physical field at the particle positions.
[`resolved_fields_modified!`](@ref) announces a change made outside a cycle — the *resolved fields*
being the two integrated fields, not a filtered subset of the scales.

```julia
domain = FixedDomain(64, 2π; dealiasing = TwoThirds(), element_type = Float64, array_type = Array)
cache  = ObservablesCache(domain; observables = (:velocity, :vorticity))
```

Today the cache holds only the velocity and the vorticity; the trajectory sample is held by the
particle set, outside the contract of §2. Every other row of §5 is design. Five gaps remain, each for
a reason:

- **A cached field is built on first read, not at the end of the preceding cycle.** The transform
  count is the same either way, since the next cycle's first stage consumes what a read builds; the
  end-of-cycle write buys a read at ``t_n`` that computes nothing, and the stamp bookkeeping is
  written to catch a stale read later, not to record a fresh value now.
- **A cached field and the array its producer works in are separate arrays**, so a declaration costs a
  new allocation rather than a forgone overwrite. Sharing them requires refusing the mid-cycle read,
  which is not implemented.
- **No numbers are cached**, so the reductions a loop already performs are discarded and a later
  consumer repeats them.
- **`Simulation` passes no `observables` argument**, so a declaration is reachable only by assembling
  a run's pieces directly. No narrower set is legal today: a step recovers both the velocity and the
  vorticity at its first stage, whatever a declaration says.
- **The trajectory sample lives with the particle set**, and the sample's own documentation states
  whether it is current, rather than the counter of §2 checking it.

The decisions behind each are in the [architecture notes](architecture.md).
