# API overview

The package is an umbrella module (`GBGIsotropicTurbulence`) assembled from submodules, in dependency
order: `SimulationState` → `Dynamics` → `Observables` → `Forcing` → `TimeIntegration` → `Particles` → `SimulationRun`. The
umbrella re-exports their public surface, so `using GBGIsotropicTurbulence` brings everything into
scope.

- [GBGIsotropicTurbulence](api/GBGIsotropicTurbulence.md): the top-level module and public re-export surface.
- [SimulationState](api/SimulationState.md): the spectral machinery (`SimulationDomain`, incl. the pluggable `DealiasingStrategy`), the preallocated buffers (`Workspace`), the scratch allocators, and the random initial conditions — a divergence-free velocity and a mean-zero scalar ``\varphi``.
- [Dynamics](api/Dynamics.md): the flow's equations of motion — the rotational-form Navier–Stokes right-hand side (de-aliased, Leray-projected nonlinear term), the passive-scalar advection, and the exact viscous integrating factor.
- [Observables](api/Observables.md): the measured functions of state — kinetic energy, dissipation, the velocity-derivative skewness, the scalar variance and dissipation, the maximum velocity component that sets the CFL step (`max_speed`), and the measured energy spectrum and integral scale.
- [Forcing](api/Forcing.md): the pluggable energy-injection strategies under `AbstractForcing` (`NoForcing`, `BandRescaling`, `Linear`, `ConstantPower`, `StochasticOU`), chosen independently for the velocity and the scalar via `Physics(; velocity_forcing, scalar_forcing)` (each defaulting to `NoForcing()`, so a forced velocity with a freely-decaying scalar is just a `velocity_forcing`).
- [TimeIntegration](api/TimeIntegration.md): the pluggable integrating-factor time-stepping schemes under `AbstractIntegrator` (`IFRK2`, `IFLowStorageRK3`).
- [Particles](api/Particles.md): Lagrangian tracer tracking — `Tracers`, second-order `advect!` (Heun-in-time), and `sample!` for the Lagrangian statistics.
- [SimulationRun](api/SimulationRun.md): the ergonomic run layer — `Simulation` and the functions that advance it (`advance!`, `run!`, `warmup!`) and validate it against the reference laws (`flow_parameters`, `validate_spectrum`).

The reference turbulence laws (model spectra, structure-function laws, scaling constants) live in a
separate, opt-in [Phenomenology](phenomenology.md) group — not re-exported by the umbrella, and designed
to be extractable into a standalone package.

```@contents
Pages = [
  "api/GBGIsotropicTurbulence.md",
  "api/SimulationState.md",
  "api/Dynamics.md",
  "api/Observables.md",
  "api/Forcing.md",
  "api/TimeIntegration.md",
  "api/Particles.md",
  "api/SimulationRun.md",
]
Depth = 2
```
