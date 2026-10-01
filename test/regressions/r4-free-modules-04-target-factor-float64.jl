# Witness r4-free-modules-04 — `Forcing._target_factor` must return the FIELD's own real element
# type, not a `Float64` literal.
#
# The `Observables` module docstring states the contract explicitly: "Each returns the field's own
# real element type rather than a fixed `Float64`, so a `Float32` run measures in `Float32`."
# `VarianceRescaling`'s docstring names `kinetic_energy` / `scalar_variance` as the observable it holds,
# and the `#` comment above `_target_factor` says the ½ / 1 factor exists "matching
# `Observables.kinetic_energy` / `Observables.scalar_variance`".  A `Float64` literal breaks that
# match on a `Float32` run: every band observable in `Forcing` is promoted to `Float64`, so the
# rescale factor α handed to `convolve!` is `Float64` on a `ComplexF32` field, and
# `_band_is_empty`'s element-type-adaptive first clause — written, per the comment at lines 61–71,
# for "Float32, where 1e-12 is already near the representable noise" — can never engage.

using Test
using Random
using GBGHomogeneousTurbulence
using GBGPeriodicFields

const SD = GBGHomogeneousTurbulence.SimulationDomain
const F  = GBGHomogeneousTurbulence.Forcing
const O  = GBGHomogeneousTurbulence.Observables

@testset "Forcing._target_factor measures in the field's own element type on a Float32 run" begin
  domain = SD.FixedDomain(; grid_points_per_axis = 16, side_length = 2π,
                            dealiasing = SD.TwoThirds(),
                            element_type = Float32, array_type = Array)

  û = SD.new_vector_field_spectral(domain)
  rng = MersenneTwister(1234)
  d = field_data(û)
  d .= ComplexF32.(randn(rng, Float32, size(d)), randn(rng, Float32, size(d)))

  φ̂ = SD.new_scalar_field_spectral(domain)
  dφ = field_data(φ̂)
  dφ .= ComplexF32.(randn(rng, Float32, size(dφ)), randn(rng, Float32, size(dφ)))

  # (0) the contract the Observables module docstring states, for reference.
  @test typeof(O.kinetic_energy(û)) === Float32

  # (1) the ½ / 1 convention factor must carry the field's element type, both tensor orders.
  band = F._shell_band(domain, 1, 2)
  # CORRECTED 2026-08-21. These asserted that the FACTOR is the field's element type. The defect was
  # that the factor's `Float64` literals PROMOTED the band observable off it, and the observable is
  # what the rest of the surface is pinned to preserve — so that is what is asserted below. The fix
  # returns exact types (`1` and `1//2`), which multiply through without promoting AND without asking
  # the field what its element type is; the latter matters because a caller may substitute a
  # field-like value that implements the reduction protocol but not the element-type accessor, which
  # a sibling witness in this same round does.
  @test typeof(F._target_factor(û) * weighted_inner(û, band)) === Float32
  @test typeof(F._target_factor(φ̂) * weighted_inner(φ̂, band)) === Float32

  # (2) the band observable `VarianceRescaling.project_forcing!` / `ConstantPower.add_forcing_source!`
  #     compute must be the same kind of number as the diagnostic they are documented to match.
  forcing = F.VarianceRescaling(domain; target = 1.0f0, over = :band)
  band_observable = F._target_factor(û) * weighted_inner(û, forcing.band)
  @test typeof(band_observable) === typeof(O.kinetic_energy(û))

  # (3) hence `_band_is_empty`'s first clause is element-type adaptive at the call site: on a
  #     Float32 run it must see Float32's eps, which is what makes it distinguishable from the
  #     absolute 1e-12 clause on the next line.
  @test eps(typeof(band_observable)) === eps(Float32)

  # (4) and the whole-field observable the guard scales against, likewise.
  @test typeof(F._target_factor(û) * inner(û, û)) === Float32
end
