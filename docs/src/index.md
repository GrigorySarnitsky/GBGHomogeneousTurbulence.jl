# GBGIsotropicTurbulence.jl

`GBGIsotropicTurbulence.jl` is a small, focused pseudospectral direct-numerical-simulation (DNS)
package for homogeneous isotropic turbulence on a three-dimensional periodic domain: an incompressible
velocity field ``\boldsymbol{u}`` together with a single passive scalar ``\varphi``, each optionally
forced, advanced by a choice of integrating-factor time-stepping scheme, with Lagrangian particle
tracking and field sampling.

It is built on [`GBGPeriodicFields`](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl), which
supplies every field operation — transforms, differential operators, convolution,
interpolation, and reductions. The GPU is the primary target, so each time step is in-place and
allocation-free over preallocated buffers (occasional diagnostics allocate per call).

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

## Quick start

Build a case at the **front door** — the `Simulation` constructor that builds every component for
you — spin it up to stationarity, and advance it:

```julia
using GBGIsotropicTurbulence

sim = Simulation(grid_points_per_axis = 64)   # a 64³ forced-stationary run;
                                              # ν is chosen from the resolution criterion
warmup!(sim)                                  # spin up to statistical stationarity

t_end = current_time(sim) + 5.0               # observe and advance: the callback reads the run,
run!(sim) do s                                # records what it wants, and decides continuation
    current_time(s) < t_end
end

# One ITERATION is one advance: a step, then the deposit that closes it. The state is always
# current; the cache holds what the last deposit left, so its reads are valid between iterations.
kinetic_energy(sim.state.velocity_spectral)   # a measured observable, read off the state
velocity_physical(sim.cache)                  # what the last iteration's closing deposit left
flow_parameters(sim)                          # the run's measured flow state
```

## What it solves

With ``\boldsymbol{u}`` the velocity, ``\boldsymbol{\omega} = \nabla\times\boldsymbol{u}`` the vorticity,
``\nu`` the kinematic viscosity, ``\mathbb{P}`` the Leray–Helmholtz projection onto divergence-free
fields, and ``\boldsymbol{f}`` a forcing, the momentum equation is advanced in rotational form (its
advective term carried by the Lamb vector ``\boldsymbol{u}\times\boldsymbol{\omega}``),

```math
\partial_t \boldsymbol{u} = \mathbb{P} (\boldsymbol{u}\times\boldsymbol{\omega}) + \nu\nabla^{2}\boldsymbol{u} + \boldsymbol{f},
\qquad \nabla\cdot\boldsymbol{u} = 0,
```

and the passive scalar ``\varphi`` by the advection–diffusion equation

```math
\partial_t \varphi = -\nabla\cdot(\boldsymbol{u} \varphi) + \varkappa\nabla^{2}\varphi + f_\varphi,
```

with ``\varkappa = \nu/\mathrm{Sc}`` the scalar diffusivity, ``\mathrm{Sc}`` the Schmidt number, and ``f_\varphi`` a forcing on the scalar. In both
equations the diffusive (stiff) term is integrated exactly through an integrating factor, the
nonlinear term explicitly by a Runge–Kutta stage combination, and the quadratic product is
dealiased by the default ``2/3`` rule (other strategies are available).

!!! note "Work in progress"
    The package is being built in vertical slices. The coupled velocity + passive-scalar solver is in
    place, advanced by the integrating-factor schemes ([`IFLowStorageRK3`](@ref) and
    [`IFRK2`](@ref)), with the forcing menu `NoForcing`, `BandRescaling`, `Linear`, and
    `ConstantPower`, and Lagrangian particle
    tracking ([`Tracers`](@ref)). The reference turbulence laws ([`Phenomenology`](phenomenology.md))
    provide usable model spectra, structure-function laws, and scaling constants. Accumulating
    statistics over the fields and the sampled trajectories is the caller's own analysis:
    `GBGPeriodicFields` supplies the field reductions and `GBGStreamingStatistics` the online
    estimators.

## Components

- [`SimulationDomain`](api/SimulationDomain.md): the discretized periodic box a run lives on — the
  `FixedDomain`, its choice of `DealiasingStrategy`, and the scratch-field allocators.
- [`State`](api/State.md): the evolving state (`ResolvedFields`, the single source of truth) a step
  advances, and the random initial conditions — a divergence-free velocity and a mean-zero scalar.
- [`Observables`](api/Observables.md): the measured functions of state — the energy and dissipation
  diagnostics of the flow and the scalar, the developed-turbulence marker, the spectrum-derived
  scales, and the one field-valued observable, the vorticity recovery.
- [`Cache`](api/Cache.md): the `ObservablesCache` — where each **iteration** (one advance of the run:
  a step plus the deposit that closes it) leaves the observables it produced, read through checked
  accessors that serve the deposited value or throw. Nothing is ever recomputed on a read.
- [`Forcing`](api/Forcing.md): the interchangeable energy-injection strategies under `AbstractForcing`,
  chosen independently for the velocity and the scalar.
- [`Generator`](api/Generator.md): the flow's equations of motion — the rotational-form Navier–Stokes
  right-hand side, the passive-scalar advection, and the exact viscous integrating factor — gathered
  into one object, the `ResolvedGenerator`, which a scheme consumes through a fixed set of verbs
  rather than assembling the physics itself.
- [`Propagator`](api/Propagator.md): the interchangeable integrating-factor schemes under
  `AbstractIntegrator`.
- [`Particles`](api/Particles.md): Lagrangian tracer tracking — second-order advection and field
  sampling along trajectories, with a selectable interpolation scheme.
- [`SimulationRun`](api/SimulationRun.md): the ergonomic run layer — `Simulation`, and the
  CFL-adaptive loop (`advance!` / `run!` / `warmup!`) that drives it. A `Simulation` is a container,
  not a reading surface: the state is read through `sim.state`, the deposited observables through
  `sim.cache`.
- [`Phenomenology`](phenomenology.md): the reference turbulence laws — model spectra, structure-function
  laws, and scaling constants — to validate a run against. A separate, opt-in group (not re-exported by
  the umbrella), designed to be extractable into a standalone package.
