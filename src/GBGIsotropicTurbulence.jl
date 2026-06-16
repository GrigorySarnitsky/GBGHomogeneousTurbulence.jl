# GBGIsotropicTurbulence — umbrella module: it sets the include order and assembles the public API.
#
# This package builds on GBGPeriodicFields (field representations, spectral operators, reductions,
# interpolation) to provide isotropic-turbulence tooling. As the package grows, each concern gets
# its own file `include`d here, with its public names re-exported below — mirroring the layout of
# GBGPeriodicFields.


"""
    GBGIsotropicTurbulence

Tools for simulating and analysing isotropic turbulence on three-dimensional periodic domains.

Built on top of [`GBGPeriodicFields`](https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl), which
supplies the underlying field representations, FFT transforms, fiberwise algebra, spectral differential
operators, reductions, and grid↔point transfer.

The `GBG` part in the name comes from the city of Göteborg (Gothenburg, Sweden), where the primary
development took place.
"""
module GBGIsotropicTurbulence

using GBGPeriodicFields

# Module contents are added incrementally; `include`s and re-exports go here.

end # module GBGIsotropicTurbulence
