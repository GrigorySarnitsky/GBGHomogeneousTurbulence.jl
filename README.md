# GBGIsotropicTurbulence.jl

A small, focused pseudospectral DNS of homogeneous isotropic turbulence on three-dimensional periodic
domains: an incompressible velocity field and a single passive scalar, each optionally forced,
advanced by a choice of integrating-factor time-stepping scheme, with Lagrangian particle tracking
and Eulerian + Lagrangian statistics.

This package builds on [`GBGPeriodicFields.jl`](https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl),
which supplies the underlying field representations, FFT transforms, fiberwise algebra, spectral
differential operators, reductions, and grid↔point transfer.

The `GBG` part in the name comes from the city of Göteborg (Gothenburg, Sweden), where the primary
development took place.

## Installation

This is a private, unregistered package. To install it (you need access to the repository):

```julia
using Pkg

Pkg.add(url="https://github.com/GrigorySarnitsky/GBGIsotropicTurbulence.jl")
```

Then:

```julia
using GBGIsotropicTurbulence
```

## Documentation

Documentation with the full API reference is available at
[https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl/](https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl/).
