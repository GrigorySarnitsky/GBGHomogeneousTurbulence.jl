# Propagator

```@autodocs
Modules = [GBGHomogeneousTurbulence.Propagator]
Order   = [:module]
```

## Integrator schemes

This section documents the integrating-factor schemes: the third-order low-storage RK3; the
fourth-order low-storage RK4 of Carpenter and Kennedy, five stages in the same two field-sized
registers with a wider imaginary-axis stability limit; the third-order Shu–Osher SSPRK3 arranged as
in the reference DNS code TurTLE, for code-to-code comparison at the same cost; then the
second-order Heun, imaginary-axis unstable and cheaper in transforms but dearer in memory.

```@docs
AbstractIntegrator
IFLowStorageRK3
IFLowStorageRK4
IFSSPRK3
IFHeun
```

## Step scratch

This section documents the preallocated per-step working set the scheme writes into, which is built
per concrete scheme and sized so a step allocates no field-sized memory.

```@docs
IntegratorBuffers
```

```@docs
allocate_buffers
```

## Time stepping

This section documents one in-place step of the coupled velocity and passive scalar together through the shared RK stages,
and the deposit that closes the iteration.

```@docs
step!
deposit!
```

## Timestep ceiling

This section documents a scheme's advective-CFL ceiling.

```@docs
recommended_cfl
```
