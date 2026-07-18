# Generator

```@autodocs
Modules = [GBGIsotropicTurbulence.Generator]
Order   = [:module]
```

## Flow conditions

The physical conditions the generator is built from — viscosity, Schmidt number, and the velocity and
scalar forcings — that `step!` consumes.

```@docs
FlowConditions
```

## Nonlinear-term assembly

The dealiased, Leray-projected rotational-form momentum term, and the conservative scalar-advection
term.

```@docs
velocity_nonlinear!
scalar_nonlinear!
```

## Integrating factor

The exact per-mode diffusive propagator — ν for the velocity, ν/Sc for the scalar — optionally folding
in a linear forcing rate.

```@docs
integrating_factor!
```
