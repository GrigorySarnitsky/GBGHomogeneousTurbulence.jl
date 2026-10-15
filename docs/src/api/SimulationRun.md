# SimulationRun

```@autodocs
Modules = [GBGHomogeneousTurbulence.SimulationRun]
Order   = [:module]
```

## The simulation

This section documents the assembled, ready-to-run simulation and its two constructors, the
domain-building `Simulation(; grid_points_per_axis, viscosity, …)` and the domain-taking
`Simulation(domain; …)`. Read its measured state by applying the
[`Observables`](Observables.md) to `sim.state` — for example `kinetic_energy(sim.state.velocity_spectral)` in a
`run!` callback.

```@docs
Simulation
PassiveScalar
ParticleTracking
```

## The predicted stationary state

This section predicts the state a forced run is set up for — ``k``, ``\varepsilon``, the band's
energy, ``\nu`` and the two Reynolds numbers — before the run is built, as `Simulation` predicts it.

```@docs
predicted_stationary_state
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

These accessors read the elapsed simulation time and the step count.

```@docs
current_time
current_step
```

## Cadence predicates

These callback helpers fire on a schedule — every ``n`` steps, or once per crossed multiple of a
simulation-time period — for the periodic actions a `run!` callback drives (a diagnostic, a
checkpoint, a `rebuild_traversal!` on a manual cadence).

```@docs
every_steps
every_time
```

## Persistence

These functions checkpoint and restore the restartable run as one self-describing group, available once `HDF5` is loaded.

```@docs
write_simulation
read_simulation
```
