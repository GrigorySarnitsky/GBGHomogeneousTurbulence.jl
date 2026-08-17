# API overview

The package is an umbrella module (`GBGIsotropicTurbulence`) assembled from submodules. Its **re-exported**
submodules, in dependency order, are `SimulationDomain` → `State` → `Observables` → `Cache` → `Forcing` →
`Generator` → `Propagator` → `Particles` → `SimulationRun`; the extraction-bound `Phenomenology` leaf
leads the include order but is **not** re-exported (reach it opt-in). The umbrella re-exports the public
surface of the listed submodules, so `using GBGIsotropicTurbulence` brings everything into scope.

- [GBGIsotropicTurbulence](api/GBGIsotropicTurbulence.md): the top-level module and public re-export surface.
- [SimulationDomain](api/SimulationDomain.md): the discretized periodic box a run lives on — the `FixedDomain` (with its choice of `DealiasingStrategy`), the scratch-field allocators, and the resolved-wavenumber ceiling `max_wavenumber`.
- [State](api/State.md): the evolving state (`ResolvedFields` — the velocity and scalar in spectral representation, the single source of truth) and the random initial conditions that seed it — a divergence-free velocity and a mean-zero scalar.
- [Observables](api/Observables.md): the measured functions of state — the energy and dissipation diagnostics of the flow and the scalar (the kinetic energy and its dissipation rate among them), the developed-turbulence markers, the spectrum-derived scales, the maximum speed that sets the CFL step, and the field-valued vorticity recovery.
- [Cache](api/Cache.md): the `ObservablesCache` — the storage the iteration fills at its end with the observables of the state it just produced (the physical velocity, vorticity, and scalar, the maximum speed, and, with tracers, the particle velocities), read through checked accessors that serve the deposited value or throw; nothing is ever recomputed on a read.
- [Forcing](api/Forcing.md): the interchangeable energy-injection strategies under `AbstractForcing`, chosen independently for the velocity and the scalar.
- [Generator](api/Generator.md): the flow's equations of motion — the rotational-form Navier–Stokes right-hand side (dealiased, Leray-projected nonlinear term), the passive-scalar advection, the exact viscous integrating factor, and the `ResolvedGenerator` that gathers them into one value — the `FlowConditions` (``\nu``, the Schmidt number, the forcings) bundled with the assembly scratch behind the protocol a scheme consumes. The physical fields its assembly consumes — the velocity, vorticity, and scalar in physical representation — are recovered by the source-preserving four-argument `to_physical!` of `GBGPeriodicFields` (the extra argument is a scratch field the transform consumes in the state's place) and by [`vorticity_physical!`](api/Observables.md).
- [Propagator](api/Propagator.md): the integrating-factor time-stepping schemes under `AbstractIntegrator` — `IFRK2` (Heun) and the low-storage `IFLowStorageRK3`.
- [Particles](api/Particles.md): Lagrangian tracer tracking — `Tracers`, second-order `advect!` (Heun-in-time), and `interpolate_at_particles!` for the Lagrangian statistics.
- [SimulationRun](api/SimulationRun.md): the ergonomic run layer — `Simulation` and the functions that advance it (`advance!`, `run!`, `warmup!`), and report its measured flow state (`flow_parameters`). A `Simulation` is a container rather than a reading surface: the state is read through `sim.state` and the deposited observables through `sim.cache`.
- [Phenomenology](phenomenology.md): the reference turbulence laws — model spectra, structure-function laws, and scaling constants — to validate a run against. A separate, opt-in group: not re-exported by the umbrella, and designed to be extractable into a standalone package.

```@contents
Pages = [
  "api/GBGIsotropicTurbulence.md",
  "api/SimulationDomain.md",
  "api/State.md",
  "api/Observables.md",
  "api/Cache.md",
  "api/Forcing.md",
  "api/Generator.md",
  "api/Propagator.md",
  "api/Particles.md",
  "api/SimulationRun.md",
]
Depth = 2
```
