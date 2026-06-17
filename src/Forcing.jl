# Forcing — the pluggable energy-injection strategies, as concrete `AbstractForcing` subtypes
# dispatched by `force!`. Each strategy acts on a field in spectral representation; because the
# methods are written through GBGPeriodicFields operators that are generic over tensor order, one
# implementation serves both the velocity (a vector field) and the scalar φ (a scalar field) — for
# velocity the caller composes the projection that keeps it solenoidal (the forcings here that only
# rescale existing modes preserve `∇·u = 0` automatically).
#
# Slice 1 ships `NoForcing` and `BandRescaling`; the stochastic (Eswaran–Pope), linear (Lundgren),
# and constant-power strategies are added in a later slice under the same interface.

module Forcing

using GBGPeriodicFields
using ..SimulationState: SpectralOperators, scalar_spectral

export AbstractForcing, NoForcing, BandRescaling, force!


"""
    AbstractForcing

Supertype of the energy-injection strategies. A strategy implements
`force!(forcing, field, ops, scratch)`, modifying `field` (a vector or scalar field in spectral
representation) in place; `scratch` is a caller-provided spectral buffer of matching tensor order.
"""
abstract type AbstractForcing end


"""
    NoForcing()

The unforced case: `force!` is a no-op (a freely decaying field).
"""
struct NoForcing <: AbstractForcing end

force!(::NoForcing, field, ops::SpectralOperators, scratch) = field


"""
    BandRescaling(ops; energy, lowest_shell = 1, highest_shell = 2)

Deterministic constant-energy forcing: each step, rescale the in-band Fourier modes
(`lowest_shell ≤ |k| ≤ highest_shell`, in integer shells of `2π/L`) so the band holds the fixed
energy `½⟨|·|²_band⟩ = energy`. Rescaling preserves the divergence-free constraint, so it needs no
projection. This is the forcing of the `GBGPeriodicFields` `HIST_CPU` demo.
"""
struct BandRescaling{K, T} <: AbstractForcing
  band::K              # annular band-pass kernel (ScalarFieldSpectral)
  target_energy::T     # the energy ½⟨|·|²⟩ held in the band
end


function BandRescaling(ops::SpectralOperators; energy::Real,
                       lowest_shell::Integer = 1, highest_shell::Integer = 2)
  k0 = 2π / ops.grid.domain_size[1]
  reference = scalar_spectral(ops)
  band = spectral_band(reference, ops.multipliers,
                       (lowest_shell - 0.5) * k0, (highest_shell + 0.5) * k0)
  return BandRescaling(band, float(energy))
end


function force!(forcing::BandRescaling, field, ops::SpectralOperators, scratch)
  convolve!(scratch, field, forcing.band)              # band-pass copy into scratch
  band_energy = 0.5 * inner(scratch, scratch)          # ½⟨|·|²_band⟩
  band_energy < 1e-12 && return field                  # nothing in the band yet (guard)
  scale = sqrt(forcing.target_energy / band_energy)
  convolve!(field, field, forcing.band, scale - 1, 1)  # rescale in-band modes (α/β accumulate)
  return field
end


end # module Forcing
