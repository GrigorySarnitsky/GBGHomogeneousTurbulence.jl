# Generator

```@autodocs
Modules = [GBGHomogeneousTurbulence.Generator]
Order   = [:module]
```

## Flow conditions

These are the physical conditions the generator is built from: viscosity, Schmidt number, and the
velocity and scalar forcings.

```@docs
FlowConditions
```

## The generator as one value

The right-hand side is held as one object, which bundles the conditions with the assembly scratch
its evaluations write through. A time-marching scheme consumes it only through the protocol below.

```@docs
ResolvedGenerator
```

## The generator protocol

A scheme sees one step of the dynamics this way: it opens with `prepare!`, evaluates the right-hand
sides and the exact linear factors at each stage, and closes with `finalize!`.

```@docs
prepare!
velocity_rhs!
scalar_rhs!
velocity_integrating_factor
scalar_integrating_factor
finalize!
```
