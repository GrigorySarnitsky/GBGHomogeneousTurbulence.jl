# API overview

The package is an umbrella module (`GBGHomogeneousTurbulence`) assembled from submodules. Its
**re-exported** submodules build on one another in the order `SimulationDomain` → `Observables` →
`State` → `Cache` → `Forcing` → `Generator` → `Propagator` → `Particles` → `SimulationRun`; the
`Phenomenology` module, kept self-contained so it can become its own package, is loaded first but is **not** re-exported (load it with
`using GBGHomogeneousTurbulence.Phenomenology`). **The pages below are ordered for reading, not by that dependency**: `SimulationRun` comes
first because a run is what a user builds first, and the pieces it composes follow. The umbrella re-exports the public
surface of the listed submodules, so `using GBGHomogeneousTurbulence` brings that surface into scope.

- [GBGHomogeneousTurbulence](api/GBGHomogeneousTurbulence.md): the top-level module and public re-export surface.
- [SimulationRun](api/SimulationRun.md): the ergonomic run layer — `Simulation`, and the Courant–Friedrichs–Lewy (CFL) adaptive loop (`advance!`, `run!`, `warmup!`) that drives it. Read a run's state through `sim.state` and the observables the last iteration stored through `sim.cache`.
- [SimulationDomain](api/SimulationDomain.md): the discretized periodic box a run lives on — the `FixedDomain` (with its choice of `DealiasingStrategy`), the scratch-field allocators, and the two cutoffs, `max_retained_wavenumber` (the highest wavenumber kept) and `max_resolved_wavenumber` (the highest with genuine Navier–Stokes dynamics).
- [State](api/State.md): the evolving state (`ResolvedFields` — the velocity and scalar in spectral representation, from which every other representation is recovered) and the random initial conditions that seed it — a divergence-free velocity and a mean-zero scalar.
- [Observables](api/Observables.md): the measured functions of state — the energy and dissipation diagnostics of the flow and the scalar (including `kinetic_energy_and_dissipation`, both in one pass), the developed-turbulence marker (`derivative_skewness`), the spectrum-derived scales, the CFL speed bound (`max_speed`), and the one field-valued observable, the vorticity recovery.
- [Cache](api/Cache.md): the `ObservablesCache` — where each iteration leaves the observables it produced, read through checked reads that serve the deposited value, never recomputed, or throw.
- [Forcing](api/Forcing.md): the interchangeable energy-injection strategies under `AbstractForcing`, chosen independently for the velocity and the scalar.
- [Generator](api/Generator.md): the flow's equations of motion — the rotational-form Navier–Stokes right-hand side, the passive-scalar advection, and the exact viscous integrating factor — gathered into one object, the `ResolvedGenerator`, which a scheme consumes through a fixed set of functions.
- [Propagator](api/Propagator.md): the integrating-factor time-stepping schemes under `AbstractIntegrator` — the low-storage `IFLowStorageRK3` and `IFLowStorageRK4`, the Shu–Osher `IFSSPRK3`, and `IFHeun` (Heun).
- [Particles](api/Particles.md): Lagrangian tracking of massless `Tracers`: `advect!` moves them under a selectable scheme (`Heun` by default, or `AdamsBashforth`), and `interpolate_at_particles!` samples fields at their positions.
- [Phenomenology](phenomenology.md): the reference turbulence laws — model spectra, structure-function laws, and scaling constants — to validate a run against. It is opt-in: the umbrella does not re-export it, and it is designed to become a standalone package.

```@contents
Pages = [
  "api/GBGHomogeneousTurbulence.md",
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
