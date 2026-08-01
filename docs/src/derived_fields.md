# Derived quantities

A run integrates two fields and no others: the velocity ``\boldsymbol{u}`` and the passive scalar
``\varphi``. The two of them at one instant make up the **state**, which a run holds in spectral
representation as ``\hat{\boldsymbol{u}}`` and ``\hat\varphi``. A run has the state at ``t_0``, then
at ``t_1``, and so on through the discrete times where its steps begin and end; between those times it
has no state at all. A run may also carry tracer particles. These are instruments
rather than a second physics — probes of the flow, each with a state of its own, its position,
advanced by its own equation. Where this page says *the state*, it means the fluid's.

Everything else a run computes is a **derived quantity**: something the state at one of those times
determines completely. The velocity in physical representation is one. So are the vorticity, the
advection terms, the velocity sampled along a particle trajectory, and the kinetic energy — a field in
either representation, a set of values at particle positions, or a single number. Because the state
determines them, a run can rebuild any of them exactly. Each has a value at each of those times. To
**hold** one means a run retains its value at ``t_n`` so you can read it, rather than discarding it
and rebuilding it on demand. You say which quantities a run holds when you configure it, and that is
a **request**.

This package makes one choice about what a request may cost: **a request adds nothing to what a run's
step cycle computes or moves.** The *cycle* is everything a run does to get from ``t_n`` to
``t_{n+1}``. It measures the timestep, records the tracer velocities, takes the step, advects the
particles, and measures whatever its stopping test needs. What it *moves* is counted in passes over
the grid. The opposite choice is defensible: a run could do
extra work in its cycle so that a request became free at the point of reading. This package does not, so
how you configured the run and the stopping condition you gave it fix what a cycle costs — never what
you later ask to see.

Holding a quantity therefore gains you no information, so this page answers only what is left of the
choice:

1. **Which** derived quantities may a run hold? (§1)
2. **What** guarantee does a held value carry? (§2)
3. **What** does holding one cost, and what do you choose? (§3)
4. **Which** does this package's cycle compute, and which does a run hold? (§4 establishes the
   system; §5 applies §§1 and 3 to it)
5. **How** do you read one, request one, and report a change you made? (§6)

Sections 1–5 describe the design. Where the package does not yet meet a claim it is marked
`(not yet — §7)`, and §7 says why each gap stands.

---

## 1. Which quantities a run may hold

Two questions decide it. The first asks whether a quantity is a derived quantity at all; the second
asks whether a run may hold one that is.

### Is it a derived quantity at all?

A derived quantity is fixed by the state at a single ``t_n``. Two ways to fall outside that:

- **It depends on more than the state.** A quantity that also depends on the step size ``\Delta t``,
  on a forcing's internal variables, or on the coefficients of the time-stepping scheme is not
  determined by the state, so no amount of state will rebuild it. A forcing's internal variables
  include, for instance, the Ornstein–Uhlenbeck state of a stochastic source.
- **It is fixed at some other instant.** A Runge–Kutta stage value is determined by the state *and*
  the discretization, so it is not the flow at any instant. A quantity carried along a trajectory
  takes the probe's position as an argument too, so the same test binds it: the velocity at a
  *predicted* position is a stage value of the probe's own integrator, at a position the probe never
  occupies.

A quantity failing the second way fails the first as well — a stage value depends on ``\Delta t`` — so
where both apply, this page gives the more specific reason.

### May a run hold it?

The opening's choice — that a request adds nothing to what a cycle computes or moves — answers this,
in two different currencies.

**In arithmetic: a run holds only what its cycle computes anyway.** A run rebuilds a held value from
its cycle, not from your read `(not yet — §7)`. So a quantity that nothing in the cycle computes could
be held only by making the cycle compute it — which is precisely the work a request may not add.

**In passes over the grid: a run holds only what its cycle already has whole.** This is the same
choice in the second currency, and §3 states it.

---

## 2. What a held value guarantees

Section 1 shows that holding **gains** you nothing. This section is the other half: holding **loses**
you nothing either, because a read never returns a value built from a superseded state.

**The cycle rebuilds a held field at its end**, from the state it has just produced `(not yet — §7)`.
That recovery is the next cycle's first-stage recovery, only moved earlier, so it costs nothing —
provided another cycle follows and its first stage reads what is there. At the end of a run the last
rebuild has no next cycle to fold into, so that one is not free.

**Only you can supersede a held value afterwards**, by changing the state outside a cycle — reseeding
an initial condition, applying a filter. You report that by calling
[`resolved_fields_modified!`](@ref), which advances the run's counter; a read compares that counter
against the stamp each held value carries and rebuilds when they differ. The routines that change the
state as part of their normal work report it themselves. Given the end-of-cycle rebuild above, a read
takes this path only after a change of your own.

**A read in mid-cycle is refused** `(not yet — §7)`. It asks for a value at a time that is not one of
the ``t_n``, and no such value exists. An array holding a quantity for you may be the array the cycle
is working in — §3 prices this. Mid-cycle that array carries stage values, which are barred from being
read for the same reason §1 bars them from being derived quantities at all.

**A held number is current at the instant its cycle measured it**, which is not always the instant you
read. Under `run!` the loop measures the maximum speed at ``t_n``, before the step, because the
timestep control needs it to choose ``\Delta t``. It measures ``\varepsilon`` and ``k`` there too when
the run is budgeted in turnovers or stopped on a condition, and not otherwise. Their order within the
iteration decides who reads them free: the stopping test runs after ``\varepsilon`` and before the
other two, so it reads ``\varepsilon`` at no cost and would rebuild the rest. A callback fires once
the step has completed, so it finds all three at a superseded state — a rebuild of one reduction
each, and for the maximum speed a velocity recovery the next cycle would have performed anyway.

---

## 3. What holding costs, and what you choose

Holding never changes the number of Fourier transforms a cycle performs (§4.3 establishes this), so
choosing to hold something is a memory decision and never a time decision. Memory is charged at one of
three levels:

| what the cycle does with the value | what holding it costs you |
|---|---|
| has it whole, and does not need that array again | nothing |
| has it whole, but needs that array again | one array, for the cycle to write its next result elsewhere |
| never has it whole | one array, **and** a grid-sized write the cycle does not already perform |

A vector field on the grid is ``3N^{3}`` reals — 384 MiB at ``N = 256`` in double precision, 192 MiB
in single. A velocity-only run under `TwoThirds` or `HouLi` already carries ten vector-shaped fields,
five in each representation, so it holds about 3.8 GiB at that size before any scalar-shaped
register.

**A run accepts the first two levels and refuses the third**, following the choice of the opening in
its second currency. A value the cycle forms only
piecewise, inside a single traversal, would have to be written out for you, and that write is a pass
the cycle does not already perform. Call a value **materialized** when the cycle has it whole
somewhere; that is the second half of §1's rule — *a run holds only what its cycle already
materializes.*

The clearest instance is the integrand of a fused reduction. Computing ``k`` sums
``\lvert\hat{\boldsymbol{u}}(\boldsymbol{\kappa})\rvert^{2}`` over wavenumbers in one traversal,
forming every value and keeping none. Written out, those values are twice the energy density mode by
mode — a field in its own right, and one an anisotropy study wants. Materializing it costs one
grid-sized write and no new arithmetic. The integrand is not the energy spectrum: ``E(\kappa)`` is
half its sum over each wavenumber shell, and computing ``E(\kappa)`` needs a further binning pass.

### What you choose

**You request the fields and trajectory samples you want held when you configure the run.** A quantity
you do not request is not held; reading it is an error, not a quiet rebuild. So the memory a run
occupies follows from the call that configured it, not from whichever diagnostic you happened to
write. The cycle fixes which level a field sits at, and you cannot know it in advance; §5 gives it
for the configuration §4 fixes.

**A number the cycle already computes is held without asking**, and stored where it is computed
rather than recomputed at the end. Keeping ``O(1)`` of storage is not worth a decision, so a run does
not make you take one. Which numbers a cycle computes depends on the run you asked for. A
turnover-budgeted or condition-stopped `run!` measures ``\varepsilon`` and ``k`` each iteration. An
adaptive timestep measures the maximum speed. A `warmup!` watching for stationarity measures the
derivative skewness at its sampling cadence, and the scalar variance too when the run carries a
forced scalar. `(not yet — §7)`

---

## 4. The system this package solves, and what its cycle does

The rules above turn on what a cycle computes, what it has whole, and what it costs. This section
establishes those three for one system in one configuration: a mask dealiasing rule, a three-stage
scheme, the default rescaling velocity forcing, and an adaptive timestep. Those are the axes that fix
a cycle's work — together with the stopping condition, which decides which reductions the loop
performs. A request is not among them.

### 4.1 The equations

The package advances the incompressible Navier–Stokes equations in **rotational form** on a
triple-periodic box, with a passive scalar and tracer particles. Write the convective term through

```math
(\boldsymbol{u}\cdot\nabla)\boldsymbol{u}
  = \nabla\big(\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}\big) - \boldsymbol{u}\times\boldsymbol{\omega}
```

and let the Leray–Helmholtz projection ``\mathbb P`` onto divergence-free fields absorb both the
pressure and the gradient ``\nabla(\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2})``; the system then
reads

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
the forcings, and ``\boldsymbol{X}(t)`` a tracer position. No projection acts on ``\boldsymbol{f}``
because every velocity forcing the package provides is already divergence-free. One proportional to
the field scales a divergence-free field mode by mode, and a stochastic source is projected as it is
drawn. The scalar advection is written in conservative form, which holds the
``\boldsymbol{\kappa} = 0`` tendency at exactly zero and fixes the split of transforms printed below.

### 4.2 How a step treats each term

- **The quadratic terms** ``\mathbb P(\boldsymbol{u}\times\boldsymbol{\omega})`` and
  ``-\nabla\cdot(\boldsymbol{u}\varphi)``: the step evaluates them as fields.
- **The viscous terms** ``\nu\nabla^{2}\boldsymbol{u}`` and ``\varkappa\nabla^{2}\varphi``: the step
  never forms them. Being diagonal in the spectral representation, they integrate exactly, and
  the step multiplies the field by
  ``\mathcal E(\boldsymbol{\kappa}) = \exp\big((A(\boldsymbol{\kappa}) - D\lvert\boldsymbol{\kappa}\rvert^{2})\tau\big)``
  instead, with ``D = \nu`` or ``\varkappa``, ``A(\boldsymbol{\kappa})`` the rate of a forcing
  proportional to the field, and ``\tau`` the sub-interval a stage advances.
- **A forcing** arrives by one of three routes. One proportional to the field folds its rate
  ``A(\boldsymbol{\kappa})`` into that exponential — the rate array exists, the product
  ``A(\boldsymbol{\kappa})\hat{\boldsymbol{u}}`` never does. An additive source enters the right-hand
  side at each stage. A rescaling applies to the completed step, as a map on the state rather than a
  term in any equation. The default velocity forcing is one: it holds the
  kinetic energy fixed by rescaling a band of modes.

### 4.3 What a cycle costs in transforms

The state lives in spectral representation, where derivatives are multiplications and the projection
acts wavenumber by wavenumber. A product of two fields is a convolution there, so each quadratic term
is evaluated the pseudospectral way. Under a mask rule, one **evaluation** of the velocity term takes
five **operations**. The evaluation

1. recovers ``\boldsymbol{u}`` in physical representation — **3 inverse transforms**;
2. forms ``\hat{\boldsymbol{\omega}} = \mathrm i\boldsymbol{\kappa}\times\hat{\boldsymbol{u}}`` and
   recovers ``\boldsymbol{\omega}`` — **3 inverse transforms**;
3. multiplies the two pointwise into a third array, giving the Lamb vector
   ``\boldsymbol{u}\times\boldsymbol{\omega}``;
4. transforms that array back — **3 forward transforms**;
5. applies ``\mathbb P`` and the mask, both per-wavenumber multiplications.

How a run removes the aliasing the pointwise product introduced is its **dealiasing rule**, and the
rule changes the count. [`TwoThirds`](@ref) and [`HouLi`](@ref) are **mask rules**: each discards or
tapers the aliased wavenumbers in one per-wavenumber multiplication. [`PhaseShift`](@ref) instead
evaluates the term a second time on a half-cell-displaced grid and averages the two, cancelling the
aliases rather than filtering them, at twice the transforms. With the scalar it costs nine inverse
transforms more than twice, because the scalar term re-recovers a displaced velocity the velocity
term has already built.

| dealiasing rule | velocity only | with the scalar |
|---|---|---|
| `TwoThirds`, `HouLi` | 18 inverse, 9 forward | 21 inverse, 18 forward |
| `PhaseShift` | 36 inverse, 18 forward | 51 inverse, 36 forward |

**None of these counts depends on what a run holds.** The end-of-cycle rebuild of §2 replaces the next
cycle's first-stage recovery rather than adding to it, so a field is recovered once per cycle
whether or not you hold it. These transforms carry essentially all of the arithmetic — one scalar
transform costs of order ``10^{2}`` operations per grid point, while each pointwise operation above
costs of order ten.

### 4.4 What a cycle needs at once, and what the tracers sample

Operation 3 writes the pointwise product into an array of its own, so the vorticity survives the
evaluation. A velocity-only evaluation under a mask rule needs **three** vector arrays in physical
representation at once: one carrying ``\boldsymbol{u}``, one carrying ``\boldsymbol{\omega}``, one
receiving their product. Writing the product over the vorticity instead would need two arrays — the
second cost level of §3, in the concrete. That saving is unavailable today: the backend's cross
product guards against writing into one of its own operands, allocating a temporary and copying back,
which costs more than the array it would save.

A cycle advances each tracer position with a two-stage scheme. The scheme samples the velocity at the start of
the step, at the particle's position, and at the end of the step, at a **predicted position the
particle never reaches**. Both samples are ``M\times3`` arrays for ``M`` particles, interpolated from
the physical velocity field with the tracer set's interpolation scheme — a Catmull–Rom spline by
default, so the sampled velocity is continuously differentiable along a trajectory.

---

## 5. What a run holds for this system

Both states are always present, the fluid's and the probes'. Tracers consume a derived field and
produce values at points; they never hold a field. The table below covers what a cycle computes from the
state.

**Held** takes the three values of §3: *on request*, *without asking*, *never*. Where a quantity is
never held, the reason names the question it fails — whether it is a derived quantity at all (§1's
first pair), or whether a run may hold one (§1's second pair). A dash in *Where it lives* means the
quantity is never formed anywhere.

| Quantity | Where it lives | Held | Why |
|---|---|---|---|
| ``\boldsymbol{u}`` | physical, grid | on request | costs one array |
| ``\boldsymbol{\omega}`` | physical, grid | on request | costs one array (§4.4) |
| ``\varphi`` | physical, grid | on request | costs one array `(not yet — §7)` |
| ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` | ``M\times3`` at points | on request | costs ``3M`` values |
| ``\mathbb P(\boldsymbol{u}\times\boldsymbol{\omega})``, dealiased | spectral, grid | on request | costs one array `(not yet — §7)` |
| ``-\nabla\cdot(\boldsymbol{u}\varphi)``, dealiased | spectral, grid | on request | costs one array `(not yet — §7)` |
| ``\boldsymbol{u}\times\boldsymbol{\omega}`` | physical, grid | on request | costs one array; each later stage reuses it, and a scalar reuses it again for the flux `(not yet — §7)` |
| ``\varepsilon``, ``k``, the maximum speed, ``\langle\varphi^{2}\rangle``, the derivative skewness | one number | without asking | held when the run you asked for measures it (§3) `(not yet — §7)` |
| the strain rate ``\boldsymbol{S}`` and ``\det\boldsymbol{S}`` | physical, grid | on request | the skewness gate of `warmup!` materializes both and discards them; no `run!` cycle forms them `(not yet — §7)` |
| ``\lvert\hat{\boldsymbol{u}}\rvert^{2}`` mode by mode | spectral, grid | never | not materialized: formed only inside a fused reduction (§3) |
| ``\nu\nabla^{2}\boldsymbol{u}``, ``\varkappa\nabla^{2}\varphi`` | — | never | not computed: applied as a multiplier, never formed (§4.2) |
| ``A(\boldsymbol{\kappa})\hat{\boldsymbol{u}}``; a rescaling forcing | — | never | not computed: a field-proportional forcing materializes its rate but never the product, and a rescaling has no rate at all |
| an additive stochastic ``\boldsymbol{f}`` | spectral, grid | never | not a derived quantity: depends on the forcing's internal variables |
| stage values of ``\boldsymbol{u}``, ``\boldsymbol{\omega}``, ``\varphi`` | physical, grid | never | not a derived quantity: fixed at a stage, not at a ``t_n`` |
| velocity at the predicted particle position | ``M\times3`` at points | never | not a derived quantity: a stage value of the probe's integrator, at a position it never occupies |
| ``E(\kappa)``, the integral scale | per shell | never | not computed: nothing in a cycle forms them |

### 5.1 The pressure is absent, *dissipation* names three objects, and only one tracer sample samples the flow

**The pressure never appears.** The projection absorbs it and no stage computes it. Recovering it
means solving its Poisson equation separately. What the rotational form suppresses is the total head
``p + \tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}`` per unit density, so such a solve returns that
combination — from which ``\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}`` must be subtracted.

**Three different objects are called dissipation.** The viscous term
``\nu\nabla^{2}\boldsymbol{u}`` is one, and §4.2 shows why no array holds it. The local dissipation
``\nu\lvert\boldsymbol{\omega}\rvert^{2}(\boldsymbol{x})`` is an ordinary field, which you can form
pointwise from a held vorticity. The dissipation rate
``\varepsilon = \nu\langle\lvert\boldsymbol{\omega}\rvert^{2}\rangle`` is a single number, which a run
obtains by summing over wavenumbers without building any field, and is what [`dissipation`](@ref)
returns.

**Only one of the two tracer velocity samples reflects the flow.** The start-of-step sample
``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` gives the velocity at the particle's own position and
moment — what a Lagrangian velocity statistic accumulates. The second is taken at a predicted position
the particle never reaches, differing from the endpoint by ``\mathcal O(\Delta t^{2})``, and exists
only to give the position update its second-order accuracy. That sample carries the units of a
velocity but is a stage value of the integrator, so a run does not expose it.

---

## 6. Reading a held quantity, requesting one, and reporting a change

!!! note "These calls are provisional"
    How you assemble and drive a run is not settled, so the calls below may change. The rules of
    §§1–5 hold whatever those calls become.

You read the two held fields that exist today from a run:

```julia
using GBGIsotropicTurbulence

sim = Simulation(grid_points_per_axis = 64, viscosity = 0.005)
advance!(sim; dt = 1e-3)

u = physical_velocity(sim)      # the velocity in physical representation, at the new time
ω = physical_vorticity(sim)     # the vorticity, likewise
```

[`physical_velocity`](@ref) and [`physical_vorticity`](@ref) return the held field when it matches the
present state and rebuild it first otherwise. The velocity along each trajectory comes from
[`tracer_velocities`](@ref), and [`sample!`](@ref) interpolates any physical field at the particle
positions.

You fix which quantities a run holds when you construct its [`DerivedFields`](@ref), through the
`charts` keyword — one `Symbol` per quantity:

```julia
domain  = FixedDomain(64, 2π; dealiasing = TwoThirds(), element_type = Float64, array_type = Array)
derived = DerivedFields(domain; charts = (:velocity, :vorticity))
```

`(not yet — §7)` A `Simulation` builds its own `DerivedFields` and takes no such argument, so this
choice cannot yet be made directly, and both fields are always held.

After you change the state outside the stepping routine — reseeding, filtering — call
[`resolved_fields_modified!`](@ref). The *resolved fields* are the two integrated fields of the
opening, not a filtered subset of the scales. The call advances the counter of §2, so a run rebuilds
every held field on the next read of it. The velocity along a trajectory is not checked against that
counter `(not yet — §7)`.

---

## 7. Where the package does not yet meet the design

Today a run holds the velocity, the vorticity, and the velocity along each trajectory. Every other
row of §5 is not yet built. The gaps, and why each stands:

- **A run builds a held field when you first read it, not at the end of the preceding cycle.** The
  transform count is the same either way, since the next cycle's first stage consumes what a read
  builds. The eager rebuild buys a read at ``t_n`` that computes nothing; the epoch bookkeeping is
  written for invalidation, not deposit.
- **A held field and the array a cycle works in are separate arrays**, so requesting a field costs a
  new allocation rather than a forgone overwrite. Sharing them requires refusing the mid-cycle read,
  which is not yet implemented.
- **A run holds no numbers**, so the reductions its loop already performs are discarded, and a
  diagnostic that wants a number repeats the reduction that produced it.
- **A `Simulation` passes no `charts` argument through**, so the requesting rule is reachable only by
  assembling a run's pieces directly. No narrower set can be requested today either: a step reads
  both fields at its first stage, so dropping either would stop the run.
- **The velocity along a trajectory is held with the particle set**, where the particle set's
  documentation states whether it is current, rather than the counter of §2 checking it.

The decisions behind each are in the [architecture notes](architecture.md).
