# SimulationRun

```@autodocs
Modules = [GBGIsotropicTurbulence.SimulationRun]
Order   = [:module]
```

## The simulation

The assembled, ready-to-run case — the front-door `Simulation(; grid_points_per_axis, viscosity, …)` and the
domain-taking `Simulation(domain; …)` constructors. Read its measured state by applying the
[`Observables`](Observables.md) to `sim.state` — for example `kinetic_energy(sim.state.velocity)` in a
`run!` callback.

```@docs
Simulation
```

## Advancing the run

Advance one iteration, or observe-and-advance until the callback stops the run; the packaged
stationarity observation and its sugar spin a fresh run up to measurement readiness.

```@docs
advance!
run!
StationarityCriterion
warmup!
```

## The state's uniform reads

The evolving state itself, read as functions of the run — *uniform* because they are always
serveable: the state is always current, so unlike a cached boundary read these never throw (the
cached observables — `velocity_physical`, `particle_velocities`, … — live on the
[Cache](Cache.md) page).

```@docs
velocity_spectral
scalar_spectral
```

## Clock accessors

The elapsed simulation time and the step count.

```@docs
current_time
current_step
```

## Flow parameters and spectrum validation

Bridge the run's measured state to a [`Phenomenology`](../phenomenology.md) `FlowParameters`, and
compare the measured energy spectrum against a model spectrum.

```@docs
flow_parameters
validate_spectrum
```
