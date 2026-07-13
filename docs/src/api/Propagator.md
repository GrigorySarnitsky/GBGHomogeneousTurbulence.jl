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

## Step scratch

The preallocated per-step working set the integrator writes into — built per concrete scheme, sized so
a step allocates no field-sized memory.

```@docs
IntegratorBuffers
allocate_buffers
```

## Time stepping

One in-place step of the coupled velocity and passive scalar together through the shared RK stages.

```@docs
step!
```

## Timestep ceiling

A scheme's advective-CFL ceiling.

```@docs
recommended_cfl
```
