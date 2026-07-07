# GBGIsotropicTurbulence.jl

`GBGIsotropicTurbulence.jl` is a small, focused pseudospectral direct-numerical-simulation (DNS)
package for homogeneous isotropic turbulence on a three-dimensional periodic domain: an incompressible
velocity field ``\boldsymbol{u}`` together with a single passive scalar ``\varphi``, each optionally
forced, advanced by a choice of integrating-factor time-stepping scheme, with Lagrangian particle
tracking and Eulerian + Lagrangian statistics.

It is built on [`GBGPeriodicFields`](https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl), which
supplies every field operation — transforms, spectral differential operators, convolution,
interpolation, and reductions. `GBGPeriodicFields` is deliberately time- and particle-free; this
package is the consumer that owns time integration, forcing, the scalar transport, particle tracking,
and the statistics. The GPU is the primary target, so the time loop is in-place and allocation-free
over a preallocated workspace.

## Installation

This is a private, unregistered package. With repository access:

```julia
using Pkg

Pkg.add(url="https://github.com/GrigorySarnitsky/GBGIsotropicTurbulence.jl")
```

Then:

```julia
using GBGIsotropicTurbulence
```

## What it solves

With ``\boldsymbol{u}`` the velocity, ``\boldsymbol{\omega} = \nabla\times\boldsymbol{u}`` the vorticity,
``\nu`` the kinematic viscosity, ``\mathbb{P}`` the Leray–Helmholtz projection onto divergence-free
fields, and ``\boldsymbol{f}`` a forcing, the momentum equation is advanced in rotational form,

```math
\partial_t \boldsymbol{u} = \mathbb{P}\,(\boldsymbol{u}\times\boldsymbol{\omega}) + \nu\nabla^{2}\boldsymbol{u} + \boldsymbol{f},
\qquad \nabla\cdot\boldsymbol{u} = 0,
```

and the passive scalar ``\varphi`` by the advection–diffusion equation

```math
\partial_t \varphi = -\nabla\cdot(\boldsymbol{u}\,\varphi) + \frac{\nu}{\mathrm{Sc}}\nabla^{2}\varphi + f_\varphi,
```

with ``\mathrm{Sc}`` the Schmidt number. In both equations the diffusive (stiff) term is integrated
exactly through an integrating factor, the nonlinear term explicitly by a Runge–Kutta stage
combination, and the quadratic product is de-aliased by the ``2/3`` rule.

!!! note "Work in progress"
    The package is being built in vertical slices. The coupled velocity + passive-scalar solver is in
    place, advanced by the integrating-factor schemes ([`IFLowStorageRK3`](@ref) — the default — and
    [`IFRK2`](@ref)), with the full forcing menu `NoForcing`, `BandRescaling`, `Linear`,
    `ConstantPower`, and the stochastic `StochasticOU` (Eswaran–Pope), and Lagrangian particle
    tracking ([`Tracers`](@ref)). The Eulerian and Lagrangian statistics are being added.

## Components

- [`SimulationState`](api/SimulationState.md): the reusable spectral machinery (`SpectralOperators`),
  the preallocated buffers (`Workspace`), and the random divergence-free initial condition.
- [`Dynamics`](api/Dynamics.md): the flow's equations of motion — the rotational-form Navier–Stokes
  right-hand side, the passive-scalar advection, and the exact viscous integrating factor.
- [`Observables`](api/Observables.md): the measured functions of state (`kinetic_energy`,
  `dissipation`, `derivative_skewness`, `scalar_variance`, `scalar_dissipation`).
- [`Forcing`](api/Forcing.md): the pluggable energy-injection strategies under `AbstractForcing`.
- [`TimeIntegration`](api/TimeIntegration.md): the pluggable integrating-factor schemes under
  `AbstractIntegrator`.
- [`Particles`](api/Particles.md): Lagrangian tracer tracking — second-order advection and field
  sampling along trajectories, with a pluggable interpolation scheme.
