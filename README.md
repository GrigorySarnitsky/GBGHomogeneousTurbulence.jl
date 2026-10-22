# GBGHomogeneousTurbulence.jl

A small, focused pseudospectral DNS of homogeneous isotropic turbulence on three-dimensional periodic
domains: an incompressible velocity field and a single passive scalar, each optionally forced,
advanced by a choice of integrating-factor time-stepping scheme, with Lagrangian particle tracking
and field sampling along the trajectories. Accumulating statistics over the fields and the sampled
values is the caller's own analysis:
[`GBGPeriodicFields.jl`](https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl) supplies the field reductions and
[`GBGStreamingStatistics.jl`](https://github.com/GrigorySarnitsky/GBGStreamingStatistics.jl) the
online estimators.

This package builds on [`GBGPeriodicFields.jl`](https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl),
which supplies the underlying field representations, FFT transforms, fiberwise algebra, differential
operators, reductions, and grid↔point transfer.

The `GBG` part in the name comes from the city of Göteborg (Gothenburg, Sweden), where the primary
development took place.

## Installation

Install it by name from the GBG packages' own registry,
[GBGRegistry](https://github.com/GrigorySarnitsky/GBGRegistry), added after `General`:

```julia
using Pkg
Pkg.Registry.add("General")
Pkg.Registry.add(url = "https://github.com/GrigorySarnitsky/GBGRegistry")
Pkg.add("GBGHomogeneousTurbulence")
```

or at the package prompt:

```
pkg> registry add General https://github.com/GrigorySarnitsky/GBGRegistry
pkg> add GBGHomogeneousTurbulence
```

GBGPeriodicFields comes with it. Julia 1.12 or later is required.

Then:

```julia
using GBGHomogeneousTurbulence
```

## Documentation

Documentation with the full API reference is available at
[https://grigorysarnitsky.github.io/GBGHomogeneousTurbulence.jl/](https://grigorysarnitsky.github.io/GBGHomogeneousTurbulence.jl/).
