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

## Physical-field evaluation

Recover the velocity, vorticity, and scalar in physical representation that the nonlinear terms consume,
from the state in spectral representation (the sources are preserved).

```@docs
velocity_to_physical!
vorticity_to_physical!
scalar_to_physical!
```

## Nonlinear-term assembly

The de-aliased, Leray-projected rotational-form momentum term, and the conservative scalar-advection
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
