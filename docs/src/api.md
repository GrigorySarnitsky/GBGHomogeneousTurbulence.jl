# API overview

The package is an umbrella module (`GBGIsotropicTurbulence`) assembled from submodules. Its **re-exported**
submodules, in dependency order, are `SimulationDomain` → `State` → `Forcing` → `Generator` →
`Observables` → `Propagator` → `Particles` → `SimulationRun`; the extraction-bound `Phenomenology` leaf
leads the include order but is **not** re-exported (reach it opt-in). The umbrella re-exports the public
surface of the listed submodules, so `using GBGIsotropicTurbulence` brings everything into scope.

- [GBGIsotropicTurbulence](api/GBGIsotropicTurbulence.md): the top-level module and public re-export surface.
- [SimulationDomain](api/SimulationDomain.md): the discretized periodic box a run lives on — the `FixedDomain` (with its choice of `DealiasingStrategy`), the scratch-field allocators, and the resolved-wavenumber ceiling `max_wavenumber`.
- [State](api/State.md): the evolving state (`ResolvedFields` — the velocity and scalar in spectral representation, the single source of truth), the physical-representation recoveries, and the random initial conditions that seed it — a divergence-free velocity and a mean-zero scalar.
- [Cache](api/Cache.md): the `ObservablesCache` — the stamped boundary storage the iteration deposits its observables into (the physical velocity, vorticity, and scalar, and the maximum speed), read through checked accessors that serve the deposited value or throw; nothing is ever recomputed on a read.
- [Forcing](api/Forcing.md): the interchangeable energy-injection strategies under `AbstractForcing`, chosen independently for the velocity and the scalar.
- [Generator](api/Generator.md): the flow's equations of motion — the rotational-form Navier–Stokes right-hand side (dealiased, Leray-projected nonlinear term), the passive-scalar advection, the exact viscous integrating factor, and the reified `ResolvedGenerator` — the `FlowConditions` (``\nu``, the Schmidt number, the forcings) bundled with the assembly scratch behind the protocol a scheme consumes. The physical-representation recoveries it consumes live with the [State](api/State.md).
- [Observables](api/Observables.md): the measured functions of state — kinetic energy, dissipation, the velocity-derivative skewness, the scalar variance and dissipation, the maximum velocity component that sets the CFL step, and the measured energy spectrum and integral scale.
- [Propagator](api/Propagator.md): the integrating-factor time-stepping schemes under `AbstractIntegrator` — `IFRK2` (Heun) and the low-storage `IFLowStorageRK3`.
- [Particles](api/Particles.md): Lagrangian tracer tracking — `Tracers`, second-order `advect!` (Heun-in-time), and `sample!` for the Lagrangian statistics.
- [SimulationRun](api/SimulationRun.md): the ergonomic run layer — `Simulation` and the functions that advance it (`advance!`, `run!`, `warmup!`), report its measured flow state (`flow_parameters`), and compare its measured energy spectrum to a `Phenomenology` model (`validate_spectrum`).

The reference turbulence laws (model spectra, structure-function laws, scaling constants) live in a
separate, opt-in [Phenomenology](phenomenology.md) group — not re-exported by the umbrella, and designed
to be extractable into a standalone package.

```@contents
Pages = [
  "api/GBGIsotropicTurbulence.md",
  "api/SimulationDomain.md",
  "api/State.md",
  "api/Forcing.md",
  "api/Generator.md",
  "api/Observables.md",
  "api/Propagator.md",
  "api/Particles.md",
  "api/SimulationRun.md",
]
Depth = 2
```
