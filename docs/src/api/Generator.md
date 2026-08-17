# Generator

```@autodocs
Modules = [GBGIsotropicTurbulence.Generator]
Order   = [:module]
```

## Flow conditions

The physical conditions the generator is built from — viscosity, Schmidt number, and the velocity and
scalar forcings.

```@docs
FlowConditions
```

## The generator as one value

The right-hand side as one object — the conditions bundled with the assembly scratch its evaluations
write through. A time-marching scheme consumes it only through the protocol below.

```@docs
ResolvedGenerator
```

## The generator protocol

One step of the dynamics, as the scheme sees it: open with `prepare!`, evaluate the right-hand sides
and the exact linear factors at each stage, close with `finalize!`.

```@docs
prepare!
velocity_rhs!
scalar_rhs!
velocity_integrating_factor
scalar_integrating_factor
finalize!
```
