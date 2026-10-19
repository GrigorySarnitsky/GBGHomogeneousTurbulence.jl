# GBGHomogeneousTurbulence.jl

`GBGHomogeneousTurbulence.jl` is a small, focused pseudospectral direct-numerical-simulation (DNS)
package for homogeneous isotropic turbulence on a three-dimensional periodic domain: an incompressible
velocity field ``\boldsymbol{u}`` together with a single passive scalar ``\varphi``, each optionally
forced, advanced by a choice of integrating-factor time-stepping scheme, with Lagrangian particle
tracking and field sampling.

It is built on [`GBGPeriodicFields`](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl), which
supplies every field operation — transforms, differential operators, convolution,
interpolation, and reductions. The GPU is the primary target, so each time step works in place over
preallocated buffers and allocates nothing that grows with the grid (occasional diagnostics allocate per call, and the threaded CPU path allocates a little per pass for its tasks).
[Memory footprint on a GPU](gpu.md) gives what a run needs on a card, and how CUDA's unified memory
lets a run outgrow one.

## Installation

This is a private, unregistered package. With repository access:

```julia
]add https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl
]add https://github.com/GrigorySarnitsky/GBGHomogeneousTurbulence.jl
```

Add the field-library backend first: both are unregistered, so Julia cannot resolve
`GBGPeriodicFields` on its own. Julia 1.12 or later is required.

or

```julia
using Pkg

Pkg.add(url="https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl")
Pkg.add(url="https://github.com/GrigorySarnitsky/GBGHomogeneousTurbulence.jl")
```

Then:

```julia
using GBGHomogeneousTurbulence
```

## Quick start

Build a case with the [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) constructor, spin it up to stationarity, and
advance it with [`run!`](@ref GBGHomogeneousTurbulence.SimulationRun.run!) and a
[`do` block](https://docs.julialang.org/en/v1/manual/functions/#Do-Block-Syntax-for-Function-Arguments):

```julia
using GBGHomogeneousTurbulence

sim = Simulation(grid_points_per_axis = 64)
# A forced run on a 64³ grid. The viscosity ν is chosen so that the grid
# resolves the dissipation scale.

warmup!(sim)
# Run until the flow is statistically stationary. The default forcing,
# ConstantPower, holds the energy injection rate fixed, so the kinetic
# energy k settles freely; read its docstring before measuring k.

t_end = current_time(sim) + 5.0
# Advance by 5 units of simulation time. The function given to run! is
# the stopping criterion: run! calls it at the start and after every
# iteration, and stops the run when it returns false.
run!(sim) do s
    current_time(s) < t_end
end

# The state is always current. The observables cache holds what the last
# iteration (one advance of the run) stored at its end; reading a value
# after a later change to the state throws an error.
kinetic_energy(sim.state.velocity_spectral)  # computed from the state
velocity_physical(sim.cache)                 # stored by the last iteration
```

## What it solves

With ``\boldsymbol{u}`` the velocity, ``\boldsymbol{\omega} = \nabla\times\boldsymbol{u}`` the vorticity,
``\nu`` the kinematic viscosity, ``\mathbb{P}`` the Leray–Helmholtz projection onto divergence-free
fields, and ``\boldsymbol{f}`` a forcing, the momentum equation is advanced in rotational form (its
advective term carried by the Lamb vector ``\boldsymbol{\omega}\times\boldsymbol{u}``),

```math
\begin{aligned}
\partial_t \boldsymbol{u} &= -\mathbb{P} (\boldsymbol{\omega}\times\boldsymbol{u})
  + \nu\nabla^{2}\boldsymbol{u} + \boldsymbol{f}, &
\nabla\cdot\boldsymbol{u} &= 0,
\end{aligned}
```

and the passive scalar ``\varphi`` by the advection–diffusion equation

```math
\partial_t \varphi = -\nabla\cdot(\boldsymbol{u} \varphi) + \varkappa\nabla^{2}\varphi + f_\varphi,
```

with ``\varkappa = \nu/\mathrm{Sc}`` the scalar diffusivity, ``\mathrm{Sc}`` the Schmidt number, and ``f_\varphi`` a forcing on the scalar. In both
equations the diffusive (stiff) term is integrated exactly through an integrating factor, the
nonlinear term explicitly by a Runge–Kutta stage combination, and the quadratic product is
dealiased by the default ``2/3`` rule (other strategies are available).

## Components

Listed in build order — each module uses the ones above it. The
[API overview](api.md) lists the same surface in *reading* order, leading with the run layer.

- [`SimulationDomain`](api/SimulationDomain.md): the discretized periodic box a run lives on — the
  [`FixedDomain`](@ref GBGHomogeneousTurbulence.SimulationDomain.FixedDomain), its choice of [`DealiasingStrategy`](@ref GBGHomogeneousTurbulence.SimulationDomain.DealiasingStrategy), and the scratch-field allocators.
- [`Observables`](api/Observables.md): the measured functions of state — the energy and dissipation
  diagnostics of the flow and the scalar (including
  [`kinetic_energy_and_dissipation`](@ref GBGHomogeneousTurbulence.Observables.kinetic_energy_and_dissipation), both in one pass), the developed-turbulence marker ([`derivative_skewness`](@ref GBGHomogeneousTurbulence.Observables.derivative_skewness)),
  the spectrum-derived scales, the CFL speed bound ([`max_speed`](@ref GBGHomogeneousTurbulence.Observables.max_speed)), and the one field-valued
  observable, the vorticity recovery.
- [`State`](api/State.md): the evolving state ([`ResolvedFields`](@ref GBGHomogeneousTurbulence.State.ResolvedFields), from which every other representation is recovered) a step
  advances, and the random initial conditions — a divergence-free velocity and a mean-zero scalar.
- [`Cache`](api/Cache.md): the [`ObservablesCache`](@ref GBGHomogeneousTurbulence.Cache.ObservablesCache) — where each *iteration* (one advance of the
  run; the notation page's vocabulary gives its full anatomy) leaves the observables it produced,
  read through checked reads that serve the deposited value or throw. Nothing is ever recomputed on
  a read.
- [`Forcing`](api/Forcing.md): the interchangeable energy-injection strategies under [`AbstractForcing`](@ref GBGHomogeneousTurbulence.Forcing.AbstractForcing),
  chosen independently for the velocity and the scalar.
- [`Generator`](api/Generator.md): the flow's equations of motion — the rotational-form Navier–Stokes
  right-hand side, the passive-scalar advection, and the exact viscous integrating factor — gathered
  into one object, the [`ResolvedGenerator`](@ref GBGHomogeneousTurbulence.Generator.ResolvedGenerator), which a scheme consumes through a fixed set of functions —
  [`prepare!`](@ref GBGHomogeneousTurbulence.Generator.prepare!), [`velocity_rhs!`](@ref GBGHomogeneousTurbulence.Generator.velocity_rhs!), [`scalar_rhs!`](@ref GBGHomogeneousTurbulence.Generator.scalar_rhs!), [`velocity_integrating_factor`](@ref GBGHomogeneousTurbulence.Generator.velocity_integrating_factor),
  [`scalar_integrating_factor`](@ref GBGHomogeneousTurbulence.Generator.scalar_integrating_factor) and [`finalize!`](@ref GBGHomogeneousTurbulence.Generator.finalize!) —
  rather than assembling the physics itself.
- [`Propagator`](api/Propagator.md): the interchangeable integrating-factor schemes under
  [`AbstractIntegrator`](@ref GBGHomogeneousTurbulence.Propagator.AbstractIntegrator).
- [`Particles`](api/Particles.md): Lagrangian particle tracking — today the massless tracer —
  advection along trajectories and field sampling there, with selectable interpolation and
  particle integration schemes.
- [`SimulationRun`](api/SimulationRun.md): the ergonomic run layer — `Simulation`, and the
  Courant–Friedrichs–Lewy (CFL) adaptive loop ([`advance!`](@ref GBGHomogeneousTurbulence.SimulationRun.advance!) / [`run!`](@ref GBGHomogeneousTurbulence.SimulationRun.run!) / [`warmup!`](@ref GBGHomogeneousTurbulence.SimulationRun.warmup!)) that drives it. Read the state through `sim.state`, the deposited observables through
  `sim.cache`.
