# API overview

The package is an umbrella module (`GBGIsotropicTurbulence`) assembled from submodules. Its
**re-exported** submodules build on one another in the order `SimulationDomain` → `Observables` →
`State` → `Cache` → `Forcing` → `Generator` → `Propagator` → `Particles` → `SimulationRun`; the
extraction-bound `Phenomenology` leaf leads the include order but is **not** re-exported (reach it
opt-in). **The pages below are ordered for reading, not by that dependency**: `SimulationRun` comes
first because a run is what a user builds first, and the pieces it composes follow. The umbrella re-exports the public
surface of the listed submodules, so `using GBGIsotropicTurbulence` brings everything into scope.

- [GBGIsotropicTurbulence](api/GBGIsotropicTurbulence.md): the top-level module and public re-export surface.
- [SimulationRun](api/SimulationRun.md): the ergonomic run layer — `Simulation`, and the Courant–Friedrichs–Lewy (CFL) adaptive loop (`advance!`, `run!`, `warmup!`) that drives it. Read a run's state through `sim.state` and its deposited observables through `sim.cache`.
- [SimulationDomain](api/SimulationDomain.md): the discretized periodic box a run lives on — the `FixedDomain` (with its choice of `DealiasingStrategy`), the scratch-field allocators, and `max_wavenumber`, the dealiasing cutoff.
- [State](api/State.md): the evolving state (`ResolvedFields` — the velocity and scalar in spectral representation, the single source of truth) and the random initial conditions that seed it — a divergence-free velocity and a mean-zero scalar.
- [Observables](api/Observables.md): the measured functions of state — the energy and dissipation diagnostics of the flow and the scalar, the developed-turbulence marker (`derivative_skewness`), the spectrum-derived scales, and the one field-valued observable, the vorticity recovery.
- [Cache](api/Cache.md): the `ObservablesCache` — where each iteration leaves the observables it produced, read through checked reads that serve the deposited value or throw. Nothing is ever recomputed on a read.
- [Forcing](api/Forcing.md): the interchangeable energy-injection strategies under `AbstractForcing`, chosen independently for the velocity and the scalar.
- [Generator](api/Generator.md): the flow's equations of motion — the rotational-form Navier–Stokes right-hand side, the passive-scalar advection, and the exact viscous integrating factor — gathered into one object, the `ResolvedGenerator`, which a scheme consumes through a fixed set of verbs.
- [Propagator](api/Propagator.md): the integrating-factor time-stepping schemes under `AbstractIntegrator` — `IFRK2` (Heun) and the low-storage `IFLowStorageRK3`.
- [Particles](api/Particles.md): Lagrangian tracer tracking — `Tracers`, second-order `advect!` (Heun-in-time), and `interpolate_at_particles!` for the Lagrangian statistics.
- [Phenomenology](phenomenology.md): the reference turbulence laws — model spectra, structure-function laws, and scaling constants — to validate a run against. A separate, opt-in group: not re-exported by the umbrella, and designed to be extractable into a standalone package.

```@contents
Pages = [
  "api/GBGIsotropicTurbulence.md",
  "api/SimulationRun.md",
  "api/SimulationDomain.md",
  "api/State.md",
  "api/Observables.md",
  "api/Cache.md",
  "api/Forcing.md",
  "api/Generator.md",
  "api/Propagator.md",
  "api/Particles.md",
]
Depth = 2
```
