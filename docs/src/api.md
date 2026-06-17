# API overview

The package is an umbrella module (`GBGIsotropicTurbulence`) assembled from submodules, in dependency
order: `SimulationState` → `Equations` → `Forcing` → `TimeIntegration`. The umbrella re-exports their
public surface, so `using GBGIsotropicTurbulence` brings everything into scope.

- [GBGIsotropicTurbulence](api/GBGIsotropicTurbulence.md): the top-level module and public re-export surface.
- [SimulationState](api/SimulationState.md): the spectral machinery (`SpectralOperators`), the preallocated buffers (`VelocityWorkspace`), the scratch allocators, and the random divergence-free initial condition.
- [Equations](api/Equations.md): the rotational-form Navier–Stokes right-hand side (the de-aliased, Leray-projected nonlinear term and the exact viscous integrating factor) and the velocity diagnostics.
- [Forcing](api/Forcing.md): the pluggable energy-injection strategies under `AbstractForcing` (`NoForcing`, `BandRescaling`, `Linear`, `ConstantPower`, `StochasticOU`).
- [TimeIntegration](api/TimeIntegration.md): the pluggable integrating-factor time-stepping schemes under `AbstractIntegrator` (`IFRK2`).

```@contents
Pages = [
  "api/GBGIsotropicTurbulence.md",
  "api/SimulationState.md",
  "api/Equations.md",
  "api/Forcing.md",
  "api/TimeIntegration.md",
]
Depth = 2
```
