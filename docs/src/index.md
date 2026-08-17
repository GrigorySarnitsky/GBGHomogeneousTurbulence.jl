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

kinetic_energy(sim.state.velocity_spectral)   # a measured observable, read off the state
velocity_physical(sim.cache)                  # an observable the iteration deposited at its end
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
    place, advanced by the integrating-factor schemes ([`IFLowStorageRK3`](@ref) — the default — and
    [`IFRK2`](@ref)), with the forcing menu `NoForcing`, `BandRescaling`, `Linear`, and
    `ConstantPower`, and Lagrangian particle
    tracking ([`Tracers`](@ref)). The reference turbulence laws ([`Phenomenology`](phenomenology.md))
    provide usable model spectra, structure-function laws, and scaling constants; the Eulerian and
    Lagrangian statistics are being added.

## Components

- [`SimulationDomain`](api/SimulationDomain.md): the discretized periodic box a run lives on — the
  `FixedDomain`, its choice of `DealiasingStrategy`, and the scratch-field allocators.
- [`State`](api/State.md): the evolving state (`ResolvedFields`, the single source of truth) a step
  advances, and the random initial conditions — a divergence-free velocity and a mean-zero scalar.
- [`Observables`](api/Observables.md): the measured functions of state — the energy and dissipation
  diagnostics of the flow and the scalar (`kinetic_energy`, `dissipation`, …), the spectrum-derived
  scales (`energy_spectrum`, `integral_scale`), the advective-CFL `max_speed`, and the field-valued
  vorticity recovery.
- [`Cache`](api/Cache.md): the `ObservablesCache` — the storage each **iteration** (one
  advance of the run: a step plus the deposit that closes it) fills at its
  end with the observables of the state it just produced; the checked accessors
  (`velocity_physical`, `max_speed`, …) serve the deposited value or throw, and nothing is
  recomputed on a read.
- [`Forcing`](api/Forcing.md): the interchangeable energy-injection strategies under `AbstractForcing`,
  chosen independently for the velocity and the scalar.
- [`Generator`](api/Generator.md): the flow's equations of motion — the rotational-form Navier–Stokes
  right-hand side, the passive-scalar advection, and the exact viscous integrating factor — reified as
  the `ResolvedGenerator` a scheme consumes through the generator protocol.
- [`Propagator`](api/Propagator.md): the interchangeable integrating-factor schemes under
  `AbstractIntegrator`.
- [`Particles`](api/Particles.md): Lagrangian tracer tracking — second-order advection and field
  sampling along trajectories, with a selectable interpolation scheme.
- [`SimulationRun`](api/SimulationRun.md): the ergonomic run layer — assembles a `Simulation` and
  runs it with `advance!` / `run!` / `warmup!` (the CFL-adaptive loop with automatic warm-up to
  stationarity) and reports the measured flow state as a `Phenomenology` `FlowParameters`
  (`flow_parameters`). A `Simulation` is a container rather than a reading surface: the state is read
  through `sim.state`, the deposited observables through `sim.cache`.
- [`Phenomenology`](phenomenology.md): the reference turbulence laws — model spectra, structure-function
  laws, and scaling constants — to validate a run against. A separate, opt-in group (not re-exported by
  the umbrella), designed to be extractable into a standalone package.
