# Propagator

```@autodocs
Modules = [GBGIsotropicTurbulence.Propagator]
Order   = [:module]
```

## Integrator schemes

The integrating-factor scheme supertype and its concretes — the default third-order low-storage RK3,
then the cheaper, marginally-stable second-order Heun.

```@docs
AbstractIntegrator
IFLowStorageRK3
IFRK2
```

## Time stepping

One in-place step of the coupled velocity and passive scalar together through the shared RK stages.

```@docs
step!
```

## Scheme and timestep defaults

The default-scheme factory, and a scheme's advective-CFL ceiling.

```@docs
default_integrator
recommended_cfl
```
