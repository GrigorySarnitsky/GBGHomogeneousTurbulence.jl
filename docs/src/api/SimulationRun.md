# SimulationRun

```@autodocs
Modules = [GBGIsotropicTurbulence.SimulationRun]
Order   = [:module]
```

## The simulation

The assembled, ready-to-run case — the front-door `Simulation(; resolution, viscosity, …)` and the
operators-taking `Simulation(ops; …)` constructors. The observables `kinetic_energy`, `dissipation`,
and `scalar_variance` also accept a `Simulation` directly.

```@docs
Simulation
```

## Driving the run

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
