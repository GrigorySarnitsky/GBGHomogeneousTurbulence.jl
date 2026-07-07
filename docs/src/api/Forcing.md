# Forcing

```@autodocs
Modules = [GBGIsotropicTurbulence.Forcing]
Order   = [:module]
```

## Forcing strategies

The forcing supertype and its concrete strategies: the unforced baseline, deterministic band rescaling,
the two linear-rate forcings, and the stochastic Ornstein–Uhlenbeck injection. One implementation serves
either the velocity or the scalar.

```@docs
AbstractForcing
NoForcing
BandRescaling
Linear
ConstantPower
StochasticOU
```

## Deferred forcing spec

The operator-free deferred form a strategy's constructor returns, materialised into a concrete forcing
once the operators exist.

```@docs
ForcingSpec
```

## Forcing hooks

The four step hooks a strategy may implement (each a no-op by default), listed in the order `step!`
fires them.

```@docs
prepare_forcing!
forcing_rate!
forcing_source!
apply_forcing!
```
