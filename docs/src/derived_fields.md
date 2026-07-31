# Derived Fields

## What this page covers

A run integrates two fields in time and computes many more from them along the way. This page states
which of those computed quantities the package keeps in memory from one time step to the next, which
it recomputes when asked, and why the division falls where it does.

It is written for someone who wants to read fields out of a running simulation — for a diagnostic, a
statistic, or a figure — and needs to know what is available, at which instant it is valid, and what
requesting it costs. The rules below are stated first in general terms, then applied to the equations
this package solves.

Throughout, *time level* means one of the instants ``t_0, t_1, t_2, \dots`` at which time steps begin
and end, in the usual finite-difference sense. A run of ``n`` steps passes through ``n+1`` time
levels. A *derived field* is any field computed from the state rather than integrated in time.

---

## 1. Principles

### 1.1 The state, and everything else

Exactly two fields are integrated in time: the velocity ``\boldsymbol{u}`` and the passive scalar
``\varphi``, both held in spectral representation as ``\hat{\boldsymbol{u}}`` and ``\hat\varphi``.
These are the state. They are the only thing a restart needs, and every other field in the run is a
function of them.

Derived fields are not lesser objects — the physical velocity, the vorticity, and the advective
tendency are what most diagnostics actually want — but they are **reproducible**. Keeping one is
therefore a choice about time and memory, never about information.

### 1.2 A time step is what makes a derived field obsolete

Nothing invalidates a derived field except an advance of the state. Between two time levels, the
velocity in physical representation is a fixed object; once a step completes, every field derived
from the old state is obsolete simultaneously.

This is why time levels, rather than steps, are the natural instants for observation: a derived field
is meaningful *at* ``t_n``, and a run of ``n`` steps offers ``n+1`` such instants, including the
initial condition.

### 1.3 What may be kept: three conditions

A derived quantity is kept from one time level to the next only when all three of the following hold.
Each excludes something real, and dropping any one of them admits a value that is either wrong or
expensive.

1. **It is a function of the state at a time level, and of nothing else.** Every argument must be
   evaluated at that instant — not at an intermediate stage of the time-stepping scheme, and for a
   quantity carried along a particle trajectory, not at an intermediate particle position either. The
   quantity may not depend on the step size ``\Delta t``, on a forcing's internal variables, or on the
   coefficients of the integration scheme.

2. **The step that begins at that time level computes it anyway.** The package does not perform extra
   work so that a quantity can be stored. If the solver would not compute it, storing it would mean
   paying for it, and the user is better served by computing it themselves at the moment they need it.

3. **The solver writes it to an array.** Some intermediate results are consumed inside a single pass
   over the grid and never exist as a complete field in memory. Such a quantity cannot be handed to a
   reader without first restructuring the computation to write it out, which costs both memory and a
   pass over the grid.

Condition 1 is about meaning, condition 2 about cost, condition 3 about the shape of the arithmetic.

### 1.4 *When* a quantity is computed is a choice, not a property

A quantity satisfying conditions 1 and 2 can be evaluated as soon as the state exists — that is, at
the end of the step that produced it — instead of at the start of the step that consumes it. The two
give identical values, because nothing between them alters the state, and they cost the same, because
the work happens once either way.

The package uses this: every kept derived field is evaluated at the **end** of a step, from the
just-advanced state. A diagnostic reading between steps therefore finds current values without
triggering any computation, and the following step reads what is already there instead of building it
again. The total number of Fourier transforms per step is unchanged by this arrangement.

The consequence worth stating plainly is that *"this quantity is not available at a time level"* is
almost never a fact about the quantity. It is a statement about where the code happens to place the
computation, and that placement can be moved.

### 1.5 Values that cross a time level are shared through the record; values inside a step are not

A quantity that must survive from one time level to the next is held in the derived-field record and
read from it. A quantity used only within a single step is passed directly from the routine that
computes it to the routine that consumes it.

This division is not stylistic. Within a step, a Runge–Kutta scheme evaluates the right-hand side at
several intermediate states, and a routine that fetched the velocity *by name* could not tell which
of those states it was being handed. Passing intermediate values explicitly makes such a mismatch
impossible to express. The record deliberately has no vocabulary for intermediate states.

### 1.6 Storage is requested, and the list of what may be requested is fixed by the solver

Storing a field costs memory proportional to the grid, so no derived field is kept unless the run is
configured to keep it. Conditions 1–3 make the list of *requestable* quantities finite and derivable:
it is exactly the set of quantities the solver already evaluates at a time level and writes to an
array. Anything outside that set remains available by computing it directly from the state.

### 1.7 Each stored value records the time level it belongs to

A stored field carries the index of the time level at which it was computed, and a read compares that
index with the run's current one. This is what makes a stale value impossible to obtain: a field
whose recorded index is behind the run's is recomputed before it is returned, rather than handed back
as though it were current.

Recording the index, rather than a validity flag, is also what allows a scheme to keep several time
levels of the same quantity — a multi-step particle integrator holds the velocity along the trajectory
at ``t_n``, ``t_{n-1}``, and so on, each labelled with the instant it belongs to.

### 1.8 Derived fields are defined at time levels, and only there

Between time levels — that is, while a step is in progress — the arrays holding derived fields serve
as the solver's working storage for intermediate states. This is what allows a stored field and the
solver's own intermediate register to be one array rather than two.

The contract is therefore: **a derived field is defined at every time level and undefined during a
step.** Reading one from inside a step is an error, and is reported as one.

---

## 2. How the solver works

The rules above refer to the arithmetic of a step, so this section sets out what a step does. Only the
structure matters here; the schemes themselves are documented with the [`Propagator`](@ref) module.

### 2.1 The equations

The package advances the incompressible Navier–Stokes equations in **rotational form** on a
triple-periodic box, together with a passive scalar and a set of tracer particles. Writing the
convective term through the identity
``(\boldsymbol{u}\cdot\nabla)\boldsymbol{u} = \nabla(\tfrac12\lvert\boldsymbol{u}\rvert^2) - \boldsymbol{u}\times\boldsymbol{\omega}``
and letting the Leray–Helmholtz projection ``\mathbb P`` onto divergence-free fields absorb both the
pressure and the kinetic-energy gradient,

```math
\begin{aligned}
\partial_t \boldsymbol{u} &= \mathbb P\,(\boldsymbol{u}\times\boldsymbol{\omega})
                             \;+\; \nu\nabla^{2}\boldsymbol{u} \;+\; \boldsymbol{f},
&\qquad \nabla\cdot\boldsymbol{u} &= 0, \\[2pt]
\partial_t \varphi &= -\nabla\cdot(\boldsymbol{u}\varphi)
                      \;+\; \varkappa\nabla^{2}\varphi \;+\; f_\varphi, \\[2pt]
\frac{\mathrm d\boldsymbol{X}}{\mathrm d t} &= \boldsymbol{u}(\boldsymbol{X}(t), t),
\end{aligned}
```

with ``\boldsymbol{\omega} = \nabla\times\boldsymbol{u}`` the vorticity, ``\nu`` the kinematic
viscosity, ``\varkappa = \nu/\mathrm{Sc}`` the scalar diffusivity, ``\boldsymbol{f}`` and ``f_\varphi``
the forcings, and ``\boldsymbol{X}(t)`` the position of a tracer particle. The scalar advection is
written in conservative form, which equals ``-\boldsymbol{u}\cdot\nabla\varphi`` because the velocity
is divergence-free, and which conserves the scalar mean exactly under the dealiasing rule.

### 2.2 Which terms are evaluated, and which are not

The three terms on each right-hand side are treated differently, and only one of them is ever
*evaluated* as a field:

- **The quadratic terms** ``\mathbb P(\boldsymbol{u}\times\boldsymbol{\omega})`` and
  ``-\nabla\cdot(\boldsymbol{u}\varphi)`` are evaluated explicitly, and doing so is essentially the
  entire cost of a step.
- **The diffusion terms** ``\nu\nabla^{2}\boldsymbol{u}`` and ``\varkappa\nabla^{2}\varphi`` are never
  formed. They are diagonal in the spectral representation, so they are integrated exactly by
  multiplying the field by the integrating factor
  ``\mathcal E(\boldsymbol{\kappa}) = \exp(-D\lvert\boldsymbol{\kappa}\rvert^{2}\Delta t)`` with
  ``D = \nu`` or ``\varkappa``. No dissipation field exists at any point in the calculation.
- **The forcings** enter through one of two paths. A forcing linear in the field folds its rate into
  the same exponential ``\mathcal E``; any remaining part is added to the right-hand side at each
  stage.

### 2.3 Where the Fourier transforms happen

The state is held in spectral representation, where derivatives are multiplications and the
projection is a per-wavenumber operation. A product of two fields, however, is a convolution in that
representation, and evaluating it directly would cost far more than transforming. So each evaluation
of a quadratic term follows the pseudospectral route: transform to physical representation, multiply
pointwise, transform back, and remove the aliasing error the pointwise product introduced.

For the velocity, one evaluation is:

1. recover ``\boldsymbol{u}`` in physical representation from ``\hat{\boldsymbol{u}}`` — **3 inverse
   transforms**;
2. form ``\hat{\boldsymbol{\omega}} = \mathrm i\boldsymbol{\kappa}\times\hat{\boldsymbol{u}}`` and
   recover ``\boldsymbol{\omega}`` in physical representation — **3 inverse transforms**;
3. multiply pointwise to obtain the Lamb vector
   ``\boldsymbol{u}\times\boldsymbol{\omega}`` on the grid;
4. transform the product back — **3 forward transforms**;
5. apply the projection ``\mathbb P`` and the dealiasing rule, both per-wavenumber multiplications.

Six inverse and three forward transforms per evaluation. The scalar adds one inverse transform to
recover ``\varphi`` and three forward transforms for the flux ``\boldsymbol{u}\varphi``.

These transforms carry essentially all of the arithmetic: one scalar transform costs
``\mathcal O(N^{3}\log N^{3})`` operations, some ``10^{2}``–``10^{3}`` per grid point, whereas every
pointwise operation in the list costs of order ten. Consequently the meaningful measure of a step's
cost is its transform count, and the meaningful question about storage is whether keeping a field
changes that count. Arranging for kept fields to be evaluated at the end of a step, as in §1.4, does
not.

A three-stage Runge–Kutta step evaluates each right-hand side three times, giving **18 inverse and 9
forward** transforms per step for velocity alone, and **21 inverse and 18 forward** with the scalar.

### 2.4 Where the particles fit

Tracer positions are advanced by a two-stage scheme requiring the velocity at the start of the step,
sampled at the particle positions, and the velocity at the end of the step, sampled at an intermediate
predicted position. Both samples are ``M\times3`` arrays for ``M`` particles, obtained by interpolating
the physical velocity field — so the particles consume a derived field and produce point values, never
a field of their own.

---

## 3. Applying the principles

### 3.1 Term by term

Every quantity appearing in §2.1, with its disposition and the condition of §1.3 that decides it.

| Quantity | Representation | Kept at a time level | Reason |
|---|---|---|---|
| ``\hat{\boldsymbol{u}}``, ``\hat\varphi`` | spectral | always — this is the state | integrated in time, not derived |
| ``\boldsymbol{u}`` | physical, grid | yes | evaluated at ``t_n`` by the step, and written to an array |
| ``\boldsymbol{\omega}`` | physical, grid | on request | same, but costs one vector field to keep |
| ``\varphi`` | physical, grid | on request | same, when the run carries a scalar |
| ``\mathbb P(\boldsymbol{u}\times\boldsymbol{\omega})``, dealiased | spectral | on request | a function of the state alone |
| ``-\nabla\cdot(\boldsymbol{u}\varphi)``, dealiased | spectral | on request | a function of the state alone |
| ``\boldsymbol{u}(\boldsymbol{X}(t_n), t_n)`` | ``M\times3`` point values | yes | the velocity along the trajectory; the quantity Lagrangian statistics accumulate |
| ``\boldsymbol{u}\times\boldsymbol{\omega}`` | physical, grid | no | the step carries the *projected* form forward, so keeping the bare product would cost an extra field (condition 2) |
| ``\nu\nabla^{2}\boldsymbol{u}``, ``\varkappa\nabla^{2}\varphi`` | — | never formed | applied as a spectral multiplier; no such field exists (condition 3) |
| ``\boldsymbol{f}``, ``f_\varphi`` | spectral | no | depends on ``\Delta t`` and on a forcing's internal variables, so not a function of the state alone (condition 1) |
| intermediate ``\boldsymbol{u}``, ``\boldsymbol{\omega}`` | physical, grid | no | evaluated at an intermediate stage, not at a time level (condition 1) |
| velocity at the predicted particle position | ``M\times3`` point values | no | evaluated at a position no particle occupies (condition 1, on the position argument) |

### 3.2 Reading the table

Three observations are worth drawing out.

**The pressure never appears.** It is absorbed by the projection ``\mathbb P`` and is not computed at
any stage, so it is not a derived field that could be requested. Obtaining it requires solving its
Poisson equation separately.

**The dissipation term is not a field.** ``\nu\nabla^{2}\boldsymbol{u}`` is integrated as a
multiplier, so no array holding it ever exists. The dissipation *rate*
``\varepsilon = \nu\langle\lvert\boldsymbol{\omega}\rvert^{2}\rangle`` is a different object — a single
number, obtained by a reduction over the state — and is available at any time through
[`dissipation`](@ref).

**The two velocity samples along a trajectory are not the same kind of object.** The start-of-step
sample ``\boldsymbol{u}(\boldsymbol{X}(t_n), t_n)`` is the velocity at a position the particle occupies
at an instant it occupies it, and is the quantity a Lagrangian velocity statistic accumulates. The
second sample is taken at a predicted position that the particle never reaches — it differs from the
endpoint position by ``\mathcal O(\Delta t^{2})`` — and exists only to give the position update its
second-order accuracy. It is an intermediate quantity of the integration scheme that happens to have
the units of a velocity, and it is not available for reading.

### 3.3 What keeping a field costs

Because a stored field and the solver's own intermediate register can be the same array (§1.8),
requesting a derived field does not necessarily allocate anything new. What it costs is the freedom
to overwrite that array.

The vorticity is the clearest case. When ``\boldsymbol{\omega}`` is not requested, the array holding it
can receive the product ``\boldsymbol{u}\times\boldsymbol{\omega}`` as it is formed, since the
vorticity is not read again afterwards. When it *is* requested, it must survive, and the product needs
an array of its own. Requesting the vorticity therefore costs one vector field on the grid — 384 MiB
at ``256^{3}`` in double precision — paid as an overwrite that can no longer be performed, rather than
as a new allocation.

The number of Fourier transforms is unchanged either way.

---

## 4. Reading derived fields from a run

Storage is requested when the observation layer is built, and reading a field that was not requested
is an error rather than a silent recomputation, so that the memory a run occupies is a stated
property of its configuration:

```julia
derived = DerivedFields(domain; charts = (:velocity, :vorticity))
```

The accessors [`physical_velocity`](@ref) and [`physical_vorticity`](@ref) return the stored field when
it is current for the present state and recompute it first otherwise, so a stale value cannot be
obtained. Tracer point values are read with [`tracer_velocities`](@ref).

If a run changes the state outside the time-stepping routine — reseeding an initial condition, say, or
applying a filter — it must announce that through [`resolved_fields_modified!`](@ref), which marks every
stored field as belonging to a superseded time level. The routines that mutate the state as part of
their normal operation do this themselves.

Quantities outside the list of §3.1 are computed directly from the state at the moment they are
wanted. This is the intended route for anything an individual study needs: it costs the transforms
that quantity requires and no resident memory, which is the correct trade for something read
occasionally rather than every step.

---

## 5. Current state of the implementation

This page states the design. The parts already in place are the observation layer itself, the
requested-storage rule, the recorded time level with recomputation on a stale read, and the tracer
velocity along the trajectory. The following differ today and are being brought into line:

- Stored fields are evaluated when first read rather than at the end of the preceding step, so a
  diagnostic running between steps may trigger a recomputation that the arrangement of §1.4 avoids.
- A stored field and the solver's intermediate register are separate arrays, so the saving described
  in §1.8 and §3.3 is not yet taken.
- The velocity along the trajectory is held with the particle set rather than in the derived-field
  record, and its currency is a documented precondition rather than a recorded time level.
- The two advective terms of §3.1 are not yet requestable.

The rationale for each, and the record of what changed when, is in the
[architecture notes](architecture.md).
