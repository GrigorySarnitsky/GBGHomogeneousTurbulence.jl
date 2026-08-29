# Propagator

```@autodocs
Modules = [GBGIsotropicTurbulence.Propagator]
Order   = [:module]
```

## Integrator schemes

The integrating-factor scheme supertype and its concretes — the third-order low-storage RK3; the
third-order Shu–Osher SSPRK3 in TurTLE's stage arrangement, for code-to-code comparison at the same
cost; then the second-order Heun, imaginary-axis unstable and cheaper in transforms but dearer in
memory.

```@docs
AbstractIntegrator
IFLowStorageRK3
IFLowStorageRK4
IFSSPRK3
IFHeun
```

## Step scratch

The preallocated per-step working set the scheme writes into — built per concrete scheme, sized so
a step allocates no field-sized memory.

```@docs
IntegratorBuffers
```

```@docs
allocate_buffers
```

## Time stepping

One in-place step of the coupled velocity and passive scalar together through the shared RK stages,
and the closing deposit that closes the iteration.

```@docs
step!
deposit!
```

## Timestep ceiling

A scheme's advective-CFL ceiling.

```@docs
recommended_cfl
```
