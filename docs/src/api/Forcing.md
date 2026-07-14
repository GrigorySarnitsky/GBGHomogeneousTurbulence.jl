# Forcing

```@autodocs
Modules = [GBGIsotropicTurbulence.Forcing]
Order   = [:module]
```

## Forcing strategies

The forcing supertype and its concrete strategies: the unforced baseline, deterministic band rescaling,
and the two linear-rate forcings. One implementation serves
either the velocity or the scalar.

```@docs
AbstractForcing
NoForcing
BandRescaling
Linear
ConstantPower
```

## Deferred forcing

The operator-free deferred form a strategy's constructor returns, materialized into a concrete forcing
once the domain exists.

```@docs
DeferredForcing
```

## Forcing methods

The four step methods a strategy may implement (each a no-op by default), listed in the order `step!`
fires them.

```@docs
prepare_forcing!
set_forcing_rate!
add_forcing_source!
apply_forcing!
```
