# Derived fields

A run integrates the velocity ``\boldsymbol{u}`` and the passive scalar ``\varphi``, and nothing else.
It holds them in spectral representation as ``\hat{\boldsymbol{u}}`` and ``\hat\varphi``, and it knows
their values only at the discrete times ``t_0, t_1, t_2, \dots`` at which its steps begin and end.
Together they are the **state**.

Everything else a run computes is a **derived quantity** — a function of the state, which a run can
rebuild from the state whenever you want it. The velocity in physical representation is one. So are
the vorticity, the two advection terms, the velocity sampled along a particle trajectory, and the
kinetic energy. Some are fields on the grid, some are values at particle positions, some are single
numbers.

Because a run can always rebuild a derived quantity, holding on to one is a choice about time and
memory and never about information. The choice is constrained three ways, and those constraints are
this page's argument: only some derived quantities can be held at all; whatever a run holds, something
must keep current; and holding one costs memory but never costs time. What that means for the
equations this package solves then follows.

A derived quantity goes out of date when the state changes — when a step completes, and also when you
reseed the initial condition or apply a filter.

This page answers five questions:

1. **Which** derived quantities may a run hold between steps? (§1)
2. **Who** keeps a held quantity current, and when? (§2)
3. **What** do you name, and what does naming it cost? (§3)
4. **Which** does this package's system compute, and which does a run hold? (§4 describes the system,
   §5 applies §§1–3 to it)
5. **How** do you read one, name one, and announce a change? (§6)

Sections 1–5 describe the design. Four points where the package does not yet meet it are collected in
§7, and each is flagged where it arises.

Throughout, a **run** owns the state and the quantities held with it, a **step** advances the state
once, and **you** drive the run.

---

## 1. Which derived quantities a run may hold between steps

A run may hold a derived quantity only if all three of the following are true.

1. **It is a function of the state at one of the times ``t_n``, and of nothing else.** The step must
   evaluate every argument at that instant — not at an intermediate stage of the time-stepping
   scheme, and for a quantity carried along a particle trajectory, not at an intermediate particle
   position either. It must not depend on the step size ``\Delta t``, on a forcing's internal
   variables, or on the coefficients of the time-stepping scheme.

2. **The step computes it anyway.** A run performs no extra arithmetic so that a quantity can be held.
   If the step would not compute it, a run will not compute it for you; compute it yourself when you
   want it.

3. **The step materializes it** — the value exists somewhere, complete, at some instant of the
   calculation. An array holding a field qualifies, and so does the single number a reduction
   returns. What fails is a value that only ever exists piecewise inside one pass over the grid,
   because writing it out means restructuring the arithmetic and paying for another pass.

Condition 1 rules out stage values and forcing state; condition 2 rules out arithmetic performed only
for storage; condition 3 rules out values that never exist whole.

These three decide **eligibility** and nothing more. What an eligible quantity then costs depends on
whether the step wants its array back, which §3 prices.

---

## 2. Who keeps a held quantity current

Three parties, and nothing inside a step.

- **The step** writes them, at its end, from the state it has just produced. *(§7: today a run writes
  them when they are first read instead.)*
- **A read** repairs them: if the state has changed since a held value was built, the read rebuilds it
  before returning, so you cannot obtain an out-of-date value.
- **You** trigger that repair by calling [`resolved_fields_modified!`](@ref) after you change the state
  yourself — reseeding, filtering. The routines that change the state as part of their normal work
  call it themselves.

Nothing inside a step keeps them current, because during a step there is nothing to keep: the arrays
behind a held quantity carry Runge–Kutta stage values, which are not the flow at any instant. A run
therefore refuses a read from inside a step rather than answering it with a stage value. *(§7: not yet
refused.)*

Each held quantity carries a counter recording the state it was built from, and a read compares that
counter against the run's. The run's counter advances on every change of state, whether the change
came from a step or from you — which is why you cannot read it as a step number.

---

## 3. What you name, and what it costs you

**When you build a run, you name the grid fields and trajectory samples you want held.** A quantity
you do not name is not held, and asking for it later is an error rather than a quiet rebuild — so the
memory a run occupies follows from the constructor call that built it. A run holds them in a
[`DerivedFields`](@ref), and you name them when you construct it. **A single number the step already
computes is held without your asking**, because holding it costs nothing.

You may name only the quantities §1 admits — a short, fixed list, given in §5. Anything else you
compute from the state at the moment you want it.

### What a held quantity costs in memory

Holding a quantity never changes the number of Fourier transforms a step performs (§4.3). It is
therefore a memory decision and never a time decision. A held quantity costs memory at one of three
levels:

| the quantity | extra memory |
|---|---|
| materialized, and the step does not want its array back | nothing at all |
| materialized, but the step reuses that array | one array, for the step to write elsewhere |
| never materialized | one array **and** another pass over the grid, to write the value out |

A run accepts the first two levels and refuses the third: it will forgo an overwrite, but it will not
restructure a pass over the grid. The package may add the third level later. Until it does,
condition 3 of §1 marks the limit — a run holds nothing the step does not already materialize.

---

## 4. One system: incompressible flow, a passive scalar, and tracers

This section describes the system §5 applies §§1–3 to: the equations, how a step treats each term, the
transforms it performs, and the arrays it needs at once. It is one system in one configuration — a
mask dealiasing rule, a three-stage scheme, and the default rescaling velocity forcing.

### 4.1 The equations

The package advances the incompressible Navier–Stokes equations in **rotational form** on a
triple-periodic box, with a passive scalar and tracer particles. Writing the convective term through

```math
(\boldsymbol{u}\cdot\nabla)\boldsymbol{u}
  = \nabla\big(\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}\big) - \boldsymbol{u}\times\boldsymbol{\omega}
```

and letting the Leray–Helmholtz projection ``\mathbb P`` onto divergence-free fields absorb both the
pressure and the gradient ``\nabla(\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2})``, the system becomes

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
because every velocity forcing the package provides is already divergence-free: a forcing
proportional to the field scales a divergence-free field mode by mode, and the package projects a
stochastic source as it draws it.

The package writes the scalar advection in conservative form. It equals
``-\boldsymbol{u}\cdot\nabla\varphi`` in the continuum, the velocity being divergence-free; once the
step dealiases the product the two forms differ, and this one holds the ``\boldsymbol{\kappa} = 0``
tendency at exactly zero, so the scalar mean survives to machine precision.

### 4.2 How a step treats each term

- **The quadratic terms** ``\mathbb P(\boldsymbol{u}\times\boldsymbol{\omega})`` and
  ``-\nabla\cdot(\boldsymbol{u}\varphi)``: the step evaluates them as fields, and doing so is
  essentially its whole cost.
- **The viscous terms** ``\nu\nabla^{2}\boldsymbol{u}`` and ``\varkappa\nabla^{2}\varphi``: the step
  never forms them. Being diagonal in the spectral representation they integrate exactly, and the step
  multiplies the field by
  ``\mathcal E(\boldsymbol{\kappa}) = \exp\big((A(\boldsymbol{\kappa}) - D\lvert\boldsymbol{\kappa}\rvert^{2})\tau\big)``
  instead, with ``D = \nu`` or ``\varkappa``, ``A(\boldsymbol{\kappa})`` the rate of a forcing
  proportional to the field, and ``\tau`` the sub-interval a stage advances. No array holding a
  viscous term ever exists.
- **A forcing** takes one of three routes: if it is proportional to the field, it folds its rate
  ``A(\boldsymbol{\kappa})`` into that same exponential; if it is additive, each stage adds it to the
  right-hand side; if it is a rescaling, the step applies it once to the completed result. The default
  velocity forcing takes the third route, holding the kinetic energy fixed by rescaling a band of
  modes.

### 4.3 What a step costs in transforms

The state lives in spectral representation, where derivatives are multiplications and the projection
acts wavenumber by wavenumber. A product of two fields is a convolution there, so a step evaluates
each quadratic term the pseudospectral way: transform to physical representation, multiply pointwise,
transform back, and remove the aliasing the pointwise product introduced.

How a run removes that aliasing is its **dealiasing rule**, and the rule changes the number of
transforms. [`TwoThirds`](@ref) and [`HouLi`](@ref) discard or taper the aliased wavenumbers with one
per-wavenumber multiplication. [`PhaseShift`](@ref) instead evaluates the term a second time on a
half-cell-displaced grid and averages, cancelling the aliases rather than filtering them — at twice
the number of transforms.

Under a mask rule, one evaluation of the velocity term takes five steps. The step

1. recovers ``\boldsymbol{u}`` in physical representation — **3 inverse transforms**;
2. forms ``\hat{\boldsymbol{\omega}} = \mathrm i\boldsymbol{\kappa}\times\hat{\boldsymbol{u}}`` and
   recovers ``\boldsymbol{\omega}`` — **3 inverse transforms**;
3. multiplies the two pointwise into a third array, giving the Lamb vector
   ``\boldsymbol{u}\times\boldsymbol{\omega}``;
4. transforms that array back — **3 forward transforms**;
5. applies ``\mathbb P`` and the mask, both per-wavenumber multiplications.

Per step, for a three-stage scheme evaluating each right-hand side three times:

| dealiasing rule | velocity only | with the scalar |
|---|---|---|
| `TwoThirds`, `HouLi` | 18 inverse, 9 forward | 21 inverse, 18 forward |
| `PhaseShift` | 36 inverse, 18 forward | 51 inverse, 36 forward |

These transforms carry essentially all of the arithmetic. One scalar transform costs
``\mathcal O(N^{3}\log N^{3})`` operations — of order ``10^{2}`` per grid point, rising from 45 at
``64^{3}`` to 90 at ``4096^{3}`` — while each pointwise operation above costs of order ten.

### 4.4 How many arrays the velocity term needs at once

Step 3 writes the pointwise product into an array of its own, so the vorticity survives the
evaluation. A velocity-only step under a mask rule therefore holds **three** physical vector arrays at
once: one carrying ``\boldsymbol{u}``, one carrying ``\boldsymbol{\omega}``, one receiving their
product. If nothing needed the vorticity afterwards, the step could write the product over it and hold
two. Holding the vorticity costs one array — §3's second level, in the concrete.

A vector array on the grid is ``3N^{3}`` reals: 384 MiB at ``N = 256`` in double precision, 192 MiB in
single.

### 4.5 What the tracers sample, and what they hold

A run advances each tracer position with a two-stage scheme that needs the velocity at the start of the
step, sampled at the particle's position, and the velocity at the end of the step, sampled at a
predicted position. Both samples are ``M\times3`` arrays for ``M`` particles, interpolated from the
physical velocity field with the tracer set's interpolation scheme — a Catmull–Rom spline by default,
so the sampled velocity is continuously differentiable along a trajectory. Tracers consume a derived
field and produce values at points; they never hold a field.

---

## 5. What that system holds

### 5.1 Every quantity a step computes, and whether a run holds it

The state ``\hat{\boldsymbol{u}}``, ``\hat\varphi`` is always present — it is what the rest is derived
from. The table lists every quantity a step computes from the state, and whether a run holds it.

**Stored** takes the three values of §3: *on request*, *without asking*, *no*. **In place** says
whether the package behaves as the row says today; it is `—` where *Stored* is `no`, since there is
nothing to build. In **Where it lives**, `—` means the quantity is never formed anywhere.

| Quantity | Where it lives | Stored | In place | Why |
|---|---|---|---|---|
| ``\boldsymbol{u}`` | physical, grid | on request | yes | eligible; costs one array |
| ``\boldsymbol{\omega}`` | physical, grid | on request | yes | eligible; costs one array (§4.4) |
| ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` | ``M\times3`` at points | on request | yes | eligible; costs ``3M`` values |
| ``\varphi`` | physical, grid | on request | no | eligible; costs one array |
| ``\mathbb P(\boldsymbol{u}\times\boldsymbol{\omega})``, dealiased | spectral, grid | on request | no | eligible; costs one array |
| ``-\nabla\cdot(\boldsymbol{u}\varphi)``, dealiased | spectral, grid | on request | no | eligible; costs one array |
| ``\boldsymbol{u}\times\boldsymbol{\omega}`` | physical, grid | on request | no | eligible; costs one array, since stages 2 and 3 reuse it |
| ``k``, ``\varepsilon``, the maximum speed | one number | without asking | no | eligible; costs nothing |
| ``\nu\nabla^{2}\boldsymbol{u}``, ``\varkappa\nabla^{2}\varphi`` | — | no | — | condition 3 fails: applied as a multiplier, never materialized |
| ``\boldsymbol{f}``, ``f_\varphi`` | spectral, grid | no | — | condition 1 fails: not a function of the state alone |
| stage values of ``\boldsymbol{u}``, ``\boldsymbol{\omega}`` | physical, grid | no | — | condition 1 fails: evaluated at a stage, not at a ``t_n`` |
| velocity at the predicted particle position | ``M\times3`` at points | no | — | condition 1 fails: evaluated where no particle is |

### 5.2 Three quantities the table cannot settle

Each of the following is a quantity you will look for in the table and not find plainly: one the
formulation removes, one whose name covers three objects, and one that appears twice under nearly the
same description.

**The pressure never appears.** The projection absorbs it and no stage computes it. Recovering it
means solving its Poisson equation separately — and what the rotational form suppresses is the total
head ``p + \tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}`` per unit density, so such a solve returns that
combination, from which ``\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}`` must be subtracted.

**Three different objects are called dissipation.** The viscous term is one, and §4.2 shows why no
array holds it. The local dissipation ``\nu\lvert\boldsymbol{\omega}\rvert^{2}(\boldsymbol{x})`` is an
ordinary field, which you can form pointwise from a held vorticity. The dissipation rate
``\varepsilon = \nu\langle\lvert\boldsymbol{\omega}\rvert^{2}\rangle`` is a single number, which a run
obtains by summing over wavenumbers without building any field, and is what [`dissipation`](@ref)
returns.

**Only one of the two tracer velocity samples is a sample of the flow.** The start-of-step sample
``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` is the velocity where the particle is, when it is there,
and is what a Lagrangian velocity statistic accumulates. The second is taken at a predicted position
the particle never reaches — it differs from the endpoint by ``\mathcal O(\Delta t^{2})`` — and exists
only to give the position update its second-order accuracy. It carries the units of a velocity and is
a stage value of the integrator, so a run does not expose it.

---

## 6. The calls: reading a held quantity, naming what to keep, announcing a change

!!! note "This section is provisional"
    How you assemble and drive a run is not settled, so the calls below may change. The rules of
    §§1–5 hold whatever these calls become.

You read the two held fields that exist today, ``\boldsymbol{u}`` and ``\boldsymbol{\omega}``, from a
run:

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

You name what to keep through the `charts` keyword, one symbol per quantity, when you construct the
[`DerivedFields`](@ref) a run holds them in:

```julia
domain  = FixedDomain(64, 2π; dealiasing = TwoThirds(), element_type = Float64, array_type = Array)
derived = DerivedFields(domain; charts = (:velocity,))   # the vorticity is not held
```

After you change the state outside the stepping routine, by reseeding or filtering, call
[`resolved_fields_modified!`](@ref) — *resolved fields* being the two integrated fields, not a
filtered subset of the scales. That advances the counter of §2, so a run rebuilds every held quantity
on its next read.

---

## 7. Where the package does not yet meet the design

Four things are in place today: the naming rule, the counter with a rebuild on a mismatched read,
``\boldsymbol{u}`` and ``\boldsymbol{\omega}`` as held fields, and the velocity along the trajectory.
Four things differ from §§1–5:

- A run builds a held quantity when you first read it, rather than at the end of the preceding step,
  so a diagnostic between steps triggers work that the end-of-step write of §2 would already have
  done.
- A held quantity and the step's own working array are separate arrays, so naming a quantity costs a
  new allocation rather than a forgone overwrite, and a run does not yet refuse a read from inside a
  step.
- ``\varphi``, the two advection terms and the Lamb vector are not nameable, and a run keeps no
  reductions at all; ``\boldsymbol{u}`` and ``\boldsymbol{\omega}`` are the whole list.
- A run holds the velocity along the trajectory with the particle set, and whether it is current is
  stated in its documentation rather than checked against a counter.

The reasoning behind each choice is in the [architecture notes](architecture.md).
