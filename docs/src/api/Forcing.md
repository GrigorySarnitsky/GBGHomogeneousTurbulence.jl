# Forcing

```@autodocs
Modules = [GBGHomogeneousTurbulence.Forcing]
Order   = [:module]
```

## Forcing strategies

The forcing supertype and its concrete strategies, grouped by the route each takes through the step —
which is what decides whether it preserves the scheme's order. [`Linear`](@ref GBGHomogeneousTurbulence.Forcing.Linear) supplies a steady rate folded
into the integrating factor, exactly and for free. [`ConstantPower`](@ref GBGHomogeneousTurbulence.Forcing.ConstantPower) and [`VarianceController`](@ref GBGHomogeneousTurbulence.Forcing.VarianceController) supply
rates that track the state, so they enter the right-hand side at every Runge–Kutta stage. [`VarianceRescaling`](@ref GBGHomogeneousTurbulence.Forcing.VarianceRescaling)
rescales after the step, which is operator splitting and first-order by construction.
At every stage [`StochasticOU`](@ref GBGHomogeneousTurbulence.Forcing.StochasticOU) adds a random force that does not depend on the flow. One
implementation serves either the velocity or the scalar.

```@docs
AbstractForcing
NoForcing
Linear
ConstantPower
VarianceController
VarianceRescaling
StochasticOU
```

## Forcing state

What a strategy evolves lives in the run's state rather than in the strategy, so saving the state
saves it too. `StochasticOU` is the only strategy here that carries such a state.

```@docs
StochasticOUState
```

## The stationary-state model

Two functions predict the stationary state a forcing drives: the kinetic energy in box units
``\tilde{k}`` (scaled by the box side and the dissipation rate) and the forced band's share of it,
both provisional placeholders until they are measured.

```@docs
kinetic_energy_in_box_units
band_energy_fraction
```

## Deferred forcing

This section documents the domain-free deferred form a strategy's constructor returns, which is
materialized into a concrete forcing once the domain exists.

```@docs
DeferredForcing
```

## Forcing methods

This section documents the method that creates a strategy's evolving state, then the four methods a
strategy may define, each doing nothing by default, in the order a run calls them:
[`steady_linear_rate`](@ref GBGHomogeneousTurbulence.Forcing.steady_linear_rate), once, when the
generator is built; [`prepare_forcing!`](@ref GBGHomogeneousTurbulence.Forcing.prepare_forcing!),
once per step; [`add_forcing_source!`](@ref GBGHomogeneousTurbulence.Forcing.add_forcing_source!), at
every Runge–Kutta stage; and [`project_forcing!`](@ref GBGHomogeneousTurbulence.Forcing.project_forcing!),
after the step.

```@docs
initial_forcing_state
steady_linear_rate
prepare_forcing!
add_forcing_source!
project_forcing!
```

## Persistence

This section documents a strategy's HDF5 persistence: its defining parameters as one self-describing
group, available once `HDF5` is loaded.

```@docs
write_forcing
read_forcing
```
