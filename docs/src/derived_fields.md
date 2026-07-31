# Derived fields

## What this page covers

A run integrates two fields in time and computes many more from them along the way. This page states
which of those computed quantities the package keeps in memory from one time step to the next, which
it recomputes when asked, and why the division falls where it does.

It is written for someone who wants to read fields out of a running simulation — for a diagnostic, a
statistic, or a figure — and needs to know what is available, at which instant it is valid, and what
requesting it costs. The rules below are stated first in general terms, then applied to the equations
this package solves.

!!! note "This page states a design; §5 records what is built"
    Sections 1–4 describe the arrangement the package is converging on. Several parts are not in place
    yet, and §5 lists exactly which. Every claim that does not yet hold is marked **(designed)** where
    it appears, so nothing here should be read as a description of the current behaviour unless it is
    unmarked.

Throughout, *time level* means one of the instants ``t_0, t_1, t_2, \dots`` at which time steps begin
and end, in the usual finite-difference sense; a run of ``S`` steps passes through ``S+1`` time levels.
The *state* means the two fields the package integrates in time — not a thermodynamic state. A
*derived quantity* is anything computed from the state rather than integrated: usually a field on the
grid, sometimes a set of values at particle positions.

---

## 1. Principles

### 1.1 The state, and everything else

Exactly two fields are integrated in time: the velocity ``\boldsymbol{u}`` and the passive scalar
``\varphi``, both held in spectral representation as ``\hat{\boldsymbol{u}}`` and ``\hat\varphi``.
These are the state, and every other *field* in the run is a function of them. (A restart needs a
little more than the state: the tracer positions, which follow their own equation, and the internal
variables of a stochastic forcing.)

Derived quantities are reproducible: the physical velocity, the vorticity, and the nonlinear term
``\mathbb P(\boldsymbol{u}\times\boldsymbol{\omega})`` can all be rebuilt from the state at any time.
Keeping one is therefore a choice about time and memory, never about information.

### 1.2 A change of state is what makes a derived quantity obsolete

Nothing makes a derived quantity obsolete except a change of the state — normally a time step, but
also reseeding an initial condition or applying a filter (§4). Between two time levels the velocity in
physical representation is a fixed object; once the state advances, everything derived from the old
state is out of date simultaneously.

This is why time levels, rather than steps, are the natural instants for observation: a derived
quantity is meaningful *at* ``t_n``, and a run offers one such instant per completed step plus the
initial condition.

### 1.3 What may be kept: three necessary conditions

A quantity can be kept from one time level to the next only if all three of the following hold. Each
excludes something real, and dropping any one admits a value that is either wrong or expensive.

1. **It is a function of the state at a time level, and of nothing else.** Every argument must be
   evaluated at that instant — not at an intermediate stage of the time-stepping scheme, and for a
   quantity carried along a particle trajectory, not at an intermediate particle position either. The
   quantity may not depend on the step size ``\Delta t``, on a forcing's internal variables, or on the
   coefficients of the integration scheme.

2. **The step that begins at that time level computes it anyway.** The package does not do extra work
   so that a quantity can be stored. If the solver would not compute it, storing it would mean paying
   for it, and you are better served computing it yourself at the moment you need it.

3. **The solver writes it to an array.** Some intermediate results are consumed inside a single pass
   over the grid and never exist as a complete field in memory. Handing such a quantity to a reader
   would mean restructuring the arithmetic to write it out, and paying for the array it is written to.

Condition 1 is about meaning; condition 2 is about cost; condition 3 is about the shape of the
arithmetic. The three are **necessary, not sufficient**: among the quantities that satisfy them, one
further question decides the matter, and §3.3 takes it up — whether the array a quantity would occupy
is one the step needs back for something else.

### 1.4 *When* a quantity is computed is a choice, not a property

A quantity satisfying conditions 1 and 2 can be evaluated as soon as the state exists — that is, at
the end of the step that produced it — instead of at the start of the step that consumes it. The two
give identical values, because nothing between them alters the state, and they cost the same, because
the work happens once either way.

**(designed)** Every kept derived quantity is evaluated at the **end** of a step, from the
just-advanced state. A diagnostic running between steps therefore finds current values without
triggering any computation, and the following step reads what is already there instead of building it
again. The particle push makes the same arrangement natural for a second reason: it needs the velocity
in physical representation at the end of the step in any case, to sample it along the trajectories.

The consequence worth stating plainly is that *"this quantity is not available at a time level"* is
almost never a fact about the quantity. It is a statement about where in the code the computation
happens to sit, and that placement can be moved.

### 1.5 What crosses a time level is kept; what lives inside a step is passed along

A quantity that must survive from one time level to the next is kept and read by name. A quantity used
only within a single step is handed directly from the routine that computes it to the routine that
consumes it.

The reason is not tidiness. Within a step a Runge–Kutta scheme evaluates the right-hand side at
several intermediate stages, and a diagnostic that asked for "the velocity" during a step would
silently receive a stage value — which is not the velocity at any instant of the simulated flow. The
kept quantities therefore have no name for a stage value at all, so such a request cannot be
expressed.

### 1.6 Storage is requested, and the list of what may be requested is fixed by the solver

Storing a field costs memory proportional to the grid, so no derived quantity is kept unless the run
is configured to keep it. Conditions 1–3 make the list of *requestable* quantities finite and
enumerable in advance: it is drawn from the quantities the solver already evaluates at a time level
and writes to an array. Anything outside that list stays available by computing it directly from the
state.

### 1.7 Each stored value records when it was computed

A stored quantity carries a counter recording the state it was computed from, and a read compares that
counter with the run's current one. The counter advances on every change of state — a completed step,
or an announced change made outside the time loop (§4). This is what makes an out-of-date value
impossible to obtain: a quantity whose counter is behind the run's is recomputed before it is
returned, rather than handed back as though it were current.

**(designed)** Recording a counter rather than a yes-or-no flag also lets a scheme keep several time
levels of the same quantity, each labelled with the instant it belongs to. A multi-step particle
integrator would hold the velocity along the trajectory at ``t_n``, ``t_{n-1}``, and so on; the
two-stage scheme in use today keeps one.

### 1.8 Kept quantities are defined at time levels, and only there

**(designed)** Between time levels — that is, while a step is in progress — the arrays holding kept
quantities serve as the solver's working storage for stage values. This is what lets a kept quantity
and the solver's own working array be one array rather than two.

The rule is therefore: **a kept quantity is defined at every time level, and during a step its array
holds stage values instead.** A read from inside a step, which is possible only from code the run
calls during one — a user-supplied forcing, or a user-written scheme — is reported as an error rather
than answered with a stage value.

---

## 2. How the solver works

The rules above refer to the arithmetic of a step, so this section sets out what a step does. Only the
structure matters here; the schemes themselves are documented with the
[`Propagator`](api/Propagator.md) module.

### 2.1 The equations

The package advances the incompressible Navier–Stokes equations in **rotational form** on a
triple-periodic box, together with a passive scalar and a set of tracer particles. Writing the
convective term through the identity

```math
(\boldsymbol{u}\cdot\nabla)\boldsymbol{u}
  = \nabla\big(\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}\big) - \boldsymbol{u}\times\boldsymbol{\omega}
```

and letting the Leray–Helmholtz projection ``\mathbb P`` onto divergence-free fields absorb both the
pressure and the gradient ``\nabla(\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2})``,

```math
\begin{aligned}
\partial_t \boldsymbol{u} &= \mathbb P\,(\boldsymbol{u}\times\boldsymbol{\omega})
                             \;+\; \nu\nabla^{2}\boldsymbol{u} \;+\; \boldsymbol{f},
&\qquad \nabla\cdot\boldsymbol{u} &= 0, \\[2pt]
\partial_t \varphi &= -\nabla\cdot(\boldsymbol{u}\varphi)
                      \;+\; \varkappa\nabla^{2}\varphi \;+\; f_\varphi, \\[2pt]
\frac{\mathrm d\boldsymbol{X}}{\mathrm d t} &= \boldsymbol{u}(t, \boldsymbol{X}(t)),
\end{aligned}
```

with ``\boldsymbol{\omega} = \nabla\times\boldsymbol{u}`` the vorticity, ``\nu`` the kinematic
viscosity, ``\varkappa = \nu/\mathrm{Sc}`` the scalar diffusivity, ``\boldsymbol{f}`` and ``f_\varphi``
the forcings, and ``\boldsymbol{X}(t)`` the position of a tracer particle. The momentum equation is
written without a projection on ``\boldsymbol{f}`` because every velocity forcing the package provides
is divergence-free by construction: a forcing proportional to the field scales an already
divergence-free field mode by mode, and a stochastic source is projected as it is drawn.

The scalar advection is written in conservative form. It equals ``-\boldsymbol{u}\cdot\nabla\varphi``
in the continuum, because the velocity is divergence-free; the two are no longer equivalent once the
product is dealiased, and the conservative form is the one that keeps the ``\boldsymbol{\kappa} = 0``
tendency exactly zero, so the scalar mean is conserved to machine precision.

### 2.2 Which terms are evaluated, and which are not

The three terms on each right-hand side are treated differently:

- **The quadratic terms** ``\mathbb P(\boldsymbol{u}\times\boldsymbol{\omega})`` and
  ``-\nabla\cdot(\boldsymbol{u}\varphi)`` are evaluated explicitly as fields, and doing so is
  essentially the entire cost of a step.
- **The viscous terms** ``\nu\nabla^{2}\boldsymbol{u}`` and ``\varkappa\nabla^{2}\varphi`` are never
  formed. They are diagonal in the spectral representation, so they are integrated exactly by
  multiplying the field by the integrating factor
  ``\mathcal E(\boldsymbol{\kappa}) = \exp\big((A(\boldsymbol{\kappa}) - D\lvert\boldsymbol{\kappa}\rvert^{2})\tau\big)``,
  with ``D = \nu`` or ``\varkappa``, ``A(\boldsymbol{\kappa})`` the rate of a forcing proportional to
  the field, and ``\tau`` the sub-interval a Runge–Kutta stage advances. No array holding a viscous
  term exists at any point in the calculation.
- **The forcings** enter by any of three routes. A forcing proportional to the field folds its rate
  ``A(\boldsymbol{\kappa})`` into that same exponential; an additive source is added to the
  right-hand side at each stage; and a rescaling or projection is applied once to the completed step.
  The default velocity forcing takes the third route, holding the kinetic energy fixed by rescaling a
  band of modes after the step.

### 2.3 Where the Fourier transforms happen

The state is held in spectral representation, where derivatives are multiplications and the projection
is a per-wavenumber operation. A product of two fields, however, is a convolution in that
representation. So each evaluation of a quadratic term follows the pseudospectral route: transform to
physical representation, multiply pointwise, transform back, and remove the aliasing error the
pointwise product introduced.

How the last step is done is a choice of *dealiasing rule*, and it changes the transform count. The
mask rules ([`TwoThirds`](@ref) and [`HouLi`](@ref)) discard or taper the aliased wavenumbers with a
single per-wavenumber multiplication. [`PhaseShift`](@ref) instead evaluates the term a second time on
a half-cell-displaced grid and averages the two, which cancels the aliases rather than filtering them
— at twice the transforms.

Under a mask rule, one evaluation of the velocity term is:

1. recover ``\boldsymbol{u}`` in physical representation from ``\hat{\boldsymbol{u}}`` — **3 inverse
   transforms**;
2. form ``\hat{\boldsymbol{\omega}} = \mathrm i\boldsymbol{\kappa}\times\hat{\boldsymbol{u}}`` and
   recover ``\boldsymbol{\omega}`` in physical representation — **3 inverse transforms**;
3. multiply pointwise to obtain the Lamb vector ``\boldsymbol{u}\times\boldsymbol{\omega}`` on the grid;
4. transform the product back — **3 forward transforms**;
5. apply the projection ``\mathbb P`` and the mask, both per-wavenumber multiplications.

Each evaluation therefore costs six inverse and three forward transforms; the scalar adds one inverse
transform to recover ``\varphi`` and three forward transforms for the flux ``\boldsymbol{u}\varphi``.

These transforms carry essentially all of the arithmetic. One scalar transform costs
``\mathcal O(N^{3}\log N^{3})`` operations — of order ``10^{2}`` per grid point, rising only from 45 at
``64^{3}`` to 90 at ``4096^{3}`` — whereas each pointwise operation in the list costs of order ten. A
step performs a few dozen transforms, so the transform count is the meaningful measure of its cost,
and the meaningful question about storage is whether keeping a quantity changes that count.

Per step, for a three-stage Runge–Kutta scheme evaluating each right-hand side three times:

| | velocity only | with the scalar |
|---|---|---|
| mask rule (`TwoThirds`, `HouLi`) | 18 inverse, 9 forward | 21 inverse, 18 forward |
| `PhaseShift` | 36 inverse, 18 forward | 51 inverse, 36 forward |

Evaluating the kept quantities at the end of a step rather than the start of the next, as in §1.4,
leaves every one of these numbers unchanged: the same recoveries happen, one step earlier. A run of
``S`` steps performs one extra evaluation at its final time level, which nothing consumes.

### 2.4 Where the particles fit

Tracer positions are advanced by a two-stage scheme requiring the velocity at the start of the step,
sampled at the particle positions, and the velocity at the end of the step, sampled at an intermediate
predicted position. Both samples are ``M\times3`` arrays for ``M`` particles, obtained by interpolating
the physical velocity field with the tracer set's chosen scheme — a Catmull–Rom spline by default, so
the sampled velocity is continuously differentiable along a trajectory. The particles consume a derived
field and produce values at points, never a field of their own.

Sampling needs the physical velocity at both ends of the step. **(designed)** Under §1.4 both are
already present, so tracking costs no transforms; today the end-of-step sample rebuilds the field, at
three further inverse transforms per step.

---

## 3. Applying the principles

### 3.1 Term by term

Every quantity a step forms or applies, with its disposition and the condition of §1.3 that decides it.

| Quantity | Representation | Kept | Reason |
|---|---|---|---|
| ``\hat{\boldsymbol{u}}``, ``\hat\varphi`` | spectral, grid | always | the state: integrated in time, not derived |
| ``\boldsymbol{u}`` | physical, grid | on request | evaluated at ``t_n`` by the step and written to an array |
| ``\boldsymbol{\omega}`` | physical, grid | on request | the same, at the cost of one vector field (§3.3) |
| ``\varphi`` | physical, grid | **(designed)** | the same, in a run carrying a scalar |
| ``\mathbb P(\boldsymbol{u}\times\boldsymbol{\omega})``, dealiased | spectral, grid | **(designed)** | a function of the state alone |
| ``-\nabla\cdot(\boldsymbol{u}\varphi)``, dealiased | spectral, grid | **(designed)** | a function of the state alone |
| ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` | ``M\times3`` values at points | yes | the velocity along the trajectory; what a Lagrangian statistic accumulates |
| ``\boldsymbol{u}\times\boldsymbol{\omega}`` | physical, grid | no | satisfies all three conditions, but its array is reused twice more within the same evaluation (§3.3) |
| ``\nu\nabla^{2}\boldsymbol{u}``, ``\varkappa\nabla^{2}\varphi`` | — | never formed | applied as a per-wavenumber multiplier; no such array exists (condition 3) |
| ``\boldsymbol{f}``, ``f_\varphi`` | spectral, grid | no | of the forcings provided, one is folded into ``\mathcal E`` and never formed, one is applied after the step, and the additive sources depend on a forcing's internal variables (condition 1) |
| stage values of ``\boldsymbol{u}``, ``\boldsymbol{\omega}`` | physical, grid | no | evaluated at a Runge–Kutta stage, not at a time level (condition 1) |
| velocity at the predicted particle position | ``M\times3`` values at points | no | evaluated at a position no particle occupies (condition 1, on the position argument) |

### 3.2 Reading the table

**The pressure never appears.** The projection ``\mathbb P`` absorbs it, and it is not computed at any
stage. Recovering it means solving its Poisson equation separately — and what the rotational form
suppresses is the total head ``p + \tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}`` (per unit density), so
a solve returns that combination, from which ``\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}`` must be
subtracted.

**The viscous term is not a field, but the dissipation is.** No array holding
``\nu\nabla^{2}\boldsymbol{u}`` is ever built, since it is integrated as a multiplier. That says
nothing about the local dissipation ``\nu\lvert\boldsymbol{\omega}\rvert^{2}(\boldsymbol{x})``, which
is a perfectly ordinary field and can be formed pointwise from a kept vorticity. The dissipation
*rate* ``\varepsilon = \nu\langle\lvert\boldsymbol{\omega}\rvert^{2}\rangle`` is a third object again —
a single number, obtained by summing over wavenumbers without forming any field — and is available at
any time through [`dissipation`](@ref).

**The two velocity samples along a trajectory are not the same kind of object.** The start-of-step
sample ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` is the velocity at a position the particle occupies
at an instant it occupies it, and is what a Lagrangian velocity statistic accumulates. The second
sample is taken at a predicted position the particle never reaches — it differs from the endpoint
position by ``\mathcal O(\Delta t^{2})`` — and exists only to give the position update its
second-order accuracy. It is an intermediate quantity of the integration scheme that happens to carry
the units of a velocity, and it is not available for reading.

### 3.3 What keeping a quantity costs

**(designed)** Because a kept quantity and the solver's own working array can be the same array
(§1.8), requesting one does not necessarily allocate anything new. What it costs is the freedom to
overwrite that array — and this, rather than conditions 1–3, is what decides the remaining rows of
§3.1.

The vorticity is the clearest case. When ``\boldsymbol{\omega}`` is not requested, the array holding it
can receive the product ``\boldsymbol{u}\times\boldsymbol{\omega}`` as that product is formed, since
the vorticity is not read again afterwards. When it *is* requested it must survive, and the product
needs an array of its own. Requesting the vorticity therefore costs one vector field on the grid —
384 MiB at ``256^{3}`` in double precision, 192 MiB in single — against a working set of five such
fields for a velocity-only run under a mask rule.

The bare Lamb vector ``\boldsymbol{u}\times\boldsymbol{\omega}`` is the same argument twice over: its
array is reused for the displaced velocity under `PhaseShift` and again for the scalar flux, so keeping
it forfeits both reuses. That is why it is excluded from §3.1 despite satisfying every condition of
§1.3.

The number of Fourier transforms is unchanged in every case.

---

## 4. Reading derived quantities from a run

The two grid quantities available today are read straight from a simulation:

```julia
using GBGIsotropicTurbulence

sim = Simulation(grid_points_per_axis = 64, viscosity = 0.005)
advance!(sim; dt = 1e-3)

u = physical_velocity(sim)      # the velocity in physical representation at the new time level
ω = physical_vorticity(sim)     # the vorticity, likewise
```

[`physical_velocity`](@ref) and [`physical_vorticity`](@ref) return the kept field when it is current
for the present state and rebuild it first otherwise, so an out-of-date value cannot be obtained.
Values along the trajectories are read with [`tracer_velocities`](@ref), and any physical field can be
sampled at the particle positions with [`sample!`](@ref).

Which quantities a run keeps is fixed when its [`DerivedFields`](@ref) is built, and reading one that
was not requested is an error rather than a quiet rebuild — so the memory a run occupies can be read
off the line that set it up, instead of depending on which diagnostic happened to be called:

```julia
domain  = FixedDomain(64, 2π; dealiasing = TwoThirds(), element_type = Float64, array_type = Array)
derived = DerivedFields(domain; charts = (:velocity,))   # the vorticity is not kept
```

The `charts` argument names the quantities to keep; `:velocity` and `:vorticity` are the two the
package accepts today.

If a run changes the state outside the time-stepping routine — reseeding an initial condition, say, or
applying a filter — it must announce that through [`resolved_fields_modified!`](@ref) (the *resolved
fields* are the two integrated fields ``\hat{\boldsymbol{u}}`` and ``\hat\varphi``, not a
filtered subset of the scales). The announcement advances the counter of §1.7, so every kept quantity
is rebuilt on its next read. The routines that change the state as part of their normal operation
announce it themselves.

Quantities outside the list of §3.1 are computed directly from the state when they are wanted, using
the same operations the solver uses. This is the intended route for anything an individual study
needs: it costs the transforms that quantity requires and no resident memory, which is the right trade
for something read occasionally rather than every step.

---

## 5. What is built, and what is not

Already in place: the requested-storage rule, the recorded counter with a rebuild on an out-of-date
read, the velocity and vorticity as requestable quantities, and the velocity along the trajectory.

Not yet, each marked **(designed)** above:

- Kept quantities are evaluated when first read rather than at the end of the preceding step, so a
  diagnostic running between steps may trigger a rebuild that the arrangement of §1.4 avoids, and the
  particle push pays three inverse transforms per step that it would otherwise not.
- A kept quantity and the solver's working array are separate arrays, so the saving described in §1.8
  and §3.3 is not yet taken, and reading a quantity from inside a step is not yet reported as an
  error.
- The scalar in physical representation and the two dealiased advective terms are not yet
  requestable; `:velocity` and `:vorticity` are the whole list.
- The velocity along the trajectory is held with the particle set rather than among the kept
  quantities, and whether it is current is stated in its documentation and left to the caller to
  ensure, instead of being checked against a recorded counter.
- [`Simulation`](@ref) does not pass a `charts` argument through, so a run built through it keeps both
  grid quantities; requesting a narrower set means assembling the run's pieces directly.

The reasoning behind each choice, and the record of what changed when, is in the
[architecture notes](architecture.md).
