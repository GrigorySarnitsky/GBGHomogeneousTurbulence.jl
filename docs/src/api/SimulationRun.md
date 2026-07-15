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

Advance one step, run to a stopping condition (with an optional per-interval callback), then spin up
to statistical stationarity.

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

## Flow parameters and spectrum validation

Bridge the run's measured state to a [`Phenomenology`](../phenomenology.md) `FlowParameters`, and
compare the measured energy spectrum against a model spectrum.

```@docs
flow_parameters
validate_spectrum
```
