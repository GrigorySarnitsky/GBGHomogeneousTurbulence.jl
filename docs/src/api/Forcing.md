# Forcing

```@autodocs
Modules = [GBGIsotropicTurbulence.Forcing]
Order   = [:module]
```

## Forcing strategies

The forcing supertype and its concrete strategies, grouped by the route each takes through the step —
which is what decides whether it preserves the scheme's order. `Linear` supplies a steady rate folded
into the integrating factor, exactly and for free. `ConstantPower` and `VarianceController` supply
rates that track the state, so they enter the right-hand side at every stage. `VarianceRescaling`
rescales after the step, which is operator splitting and first-order by construction.
At every stage `StochasticOU` adds a random force that does not depend on the flow. One
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

What a strategy evolves lives in the run's state record rather than in the strategy, so saving the
record saves it. `StochasticOU` is the only strategy here that carries such a state.

```@docs
StochasticOUState
```

## Deferred forcing

The operator-free deferred form a strategy's constructor returns, materialized into a concrete forcing
once the domain exists.

```@docs
DeferredForcing
```

## Forcing methods

The method that starts a strategy's evolving state, then the four step methods a strategy may
implement (each a no-op by default) in the order `step!` fires them, followed by the trait that
declares a strategy supplies a linear rate — part of implementing `set_forcing_rate!`, since the
generator allocates a rate array only where one is declared.

```@docs
initial_forcing_state
prepare_forcing!
set_forcing_rate!
add_forcing_source!
project_forcing!
uses_steady_linear_rate
```

## Persistence

A strategy's HDF5 persistence — its defining parameters as one self-describing group, available once `HDF5` is loaded.

```@docs
write_forcing
read_forcing
```
