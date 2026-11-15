# ParticlePropagator

```@autodocs
Modules = [GBGHomogeneousTurbulence.ParticlePropagator]
Order   = [:module]
```


## The particle integration scheme

How the positions are advanced over one step — the Lagrangian counterpart of the field schemes.
[`AB`](@ref GBGHomogeneousTurbulence.ParticlePropagator.AB) integrates over the Lagrangian samples
already deposited, at one interpolation per step; [`ABM`](@ref GBGHomogeneousTurbulence.ParticlePropagator.ABM)
corrects that step with a second interpolation, and [`Heun`](@ref GBGHomogeneousTurbulence.ParticlePropagator.Heun)
is its one-step member. A scheme owns no storage: it works on the positions and on the samples the
observables cache keeps.

```@docs
AbstractParticleIntegrator
Heun
ABM
AB
```

## The particle step

Advance the tracers once the fields have moved. The step is closed by the particle form of
[`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!), which records the flow velocity where
each tracer now sits: the next step integrates over it.

```@docs
advect!
```
