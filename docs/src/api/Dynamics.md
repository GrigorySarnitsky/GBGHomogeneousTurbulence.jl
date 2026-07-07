# Dynamics

```@autodocs
Modules = [GBGIsotropicTurbulence.Dynamics]
Order   = [:module]
```

## Physical-field evaluation

Inverse-transform the spectral state to the physical velocity and vorticity, and the physical scalar φ,
that the nonlinear terms consume (the spectral sources are preserved).

```@docs
velocity_vorticity!
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
