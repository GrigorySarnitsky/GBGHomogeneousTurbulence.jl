# SimulationRun

```@autodocs
Modules = [GBGIsotropicTurbulence.SimulationRun]
Order   = [:module]
```

## The simulation

The assembled, ready-to-run simulation — the domain-building `Simulation(; grid_points_per_axis, viscosity, …)` and the
domain-taking `Simulation(domain; …)` constructors. Read its measured state by applying the
[`Observables`](Observables.md) to `sim.state` — for example `kinetic_energy(sim.state.velocity_spectral)` in a
`run!` callback.

```@docs
Simulation
```

## Advancing the run

Advance one iteration, or observe-and-advance until the callback stops the run; the packaged
stationarity observation and its one-line shorthand spin a fresh run up to measurement readiness.

```@docs
StationarityCriterion
```

```@docs
advance!
run!
warmup!
```

## Clock accessors

The elapsed simulation time and the step count.

```@docs
current_time
current_step
```

## Flow parameters

Bridge the run's measured state to a [`Phenomenology`](../phenomenology.md) `FlowParameters`, so any
reference law can be evaluated at the run's measured state.

```@docs
flow_parameters
```

## Persistence

Checkpoint and restore — the restartable run as one self-describing group, available once `HDF5` is loaded.

```@docs
write_simulation
read_simulation
```
