# API overview

The package is an umbrella module (`GBGHomogeneousTurbulence`) assembled from submodules, which
build on one another in the order `SimulationDomain` → `Observables` → `State` → `Cache` → `Forcing` →
`Generator` → `Propagator` → `Particles` → `SimulationRun`. The pages below follow reading order instead:
`SimulationRun` comes first because a run is what a user builds first, and
the pieces it composes follow. The umbrella re-exports the public surface of every submodule, so
`using GBGHomogeneousTurbulence` brings the whole of it into scope.

- [GBGHomogeneousTurbulence](api/GBGHomogeneousTurbulence.md): the top-level module and public re-export surface.
- [SimulationRun](api/SimulationRun.md): the ergonomic run layer — [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation), and the Courant–Friedrichs–Lewy (CFL) adaptive loop ([`advance!`](@ref GBGHomogeneousTurbulence.SimulationRun.advance!), [`run!`](@ref GBGHomogeneousTurbulence.SimulationRun.run!), [`warmup!`](@ref GBGHomogeneousTurbulence.SimulationRun.warmup!)) that drives it. Read a run's state through `sim.state` and the observables the last iteration stored through `sim.cache`.
- [SimulationDomain](api/SimulationDomain.md): the discretized periodic box a run lives on — the [`FixedDomain`](@ref GBGHomogeneousTurbulence.SimulationDomain.FixedDomain) (with its choice of [`DealiasingStrategy`](@ref GBGHomogeneousTurbulence.SimulationDomain.DealiasingStrategy)), the scratch-field allocators, and the two cutoffs, [`max_retained_wavenumber`](@ref GBGHomogeneousTurbulence.SimulationDomain.max_retained_wavenumber) (the highest wavenumber kept) and [`max_resolved_wavenumber`](@ref GBGHomogeneousTurbulence.SimulationDomain.max_resolved_wavenumber) (the highest with genuine Navier–Stokes dynamics).
- [State](api/State.md): the evolving state ([`ResolvedFields`](@ref GBGHomogeneousTurbulence.State.ResolvedFields) — the velocity and scalar in spectral representation, from which every other representation is recovered) and the random initial conditions that seed it — a divergence-free velocity and a mean-zero scalar.
- [Observables](api/Observables.md): the measured functions of state — the energy and dissipation diagnostics of the flow and the scalar (including [`kinetic_energy_and_dissipation`](@ref GBGHomogeneousTurbulence.Observables.kinetic_energy_and_dissipation), both in one pass), the developed-turbulence marker ([`derivative_skewness`](@ref GBGHomogeneousTurbulence.Observables.derivative_skewness)), the spectrum-derived scales, the CFL speed bound ([`max_speed`](@ref GBGHomogeneousTurbulence.Observables.max_speed)), and the one field-valued observable, the vorticity recovery.
- [Cache](api/Cache.md): the [`ObservablesCache`](@ref GBGHomogeneousTurbulence.Cache.ObservablesCache) — where each iteration leaves the observables it produced, read through checked reads that serve the deposited value, never recomputed, or throw.
- [Forcing](api/Forcing.md): the interchangeable energy-injection strategies under [`AbstractForcing`](@ref GBGHomogeneousTurbulence.Forcing.AbstractForcing), chosen independently for the velocity and the scalar.
- [Generator](api/Generator.md): the flow's equations of motion — the rotational-form Navier–Stokes right-hand side, the passive-scalar advection, and the exact viscous integrating factor — gathered into one object, the [`ResolvedGenerator`](@ref GBGHomogeneousTurbulence.Generator.ResolvedGenerator), which a scheme consumes through a fixed set of functions.
- [Propagator](api/Propagator.md): the integrating-factor time-stepping schemes under [`AbstractIntegrator`](@ref GBGHomogeneousTurbulence.Propagator.AbstractIntegrator) — the low-storage [`IFLowStorageRK3`](@ref GBGHomogeneousTurbulence.Propagator.IFLowStorageRK3) and [`IFLowStorageRK4`](@ref GBGHomogeneousTurbulence.Propagator.IFLowStorageRK4), the Shu–Osher [`IFSSPRK3`](@ref GBGHomogeneousTurbulence.Propagator.IFSSPRK3), and [`IFHeun`](@ref GBGHomogeneousTurbulence.Propagator.IFHeun) (Heun).
- [Particles](api/Particles.md): Lagrangian tracking of massless [`Tracers`](@ref GBGHomogeneousTurbulence.Particles.Tracers): [`advect!`](@ref GBGHomogeneousTurbulence.Particles.advect!) moves them under a selectable scheme ([`Heun`](@ref GBGHomogeneousTurbulence.Particles.Heun) by default, or [`AdamsBashforth`](@ref GBGHomogeneousTurbulence.Particles.AdamsBashforth)), and [`interpolate_at_particles!`](@ref GBGHomogeneousTurbulence.Particles.interpolate_at_particles!) samples fields at their positions.

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
