# Witness r6-test-critic-01: VarianceController's scalar (variance, factor 1) branch of
# Bassenne's Eq. 20.
#
# The claim under test: `add_forcing_source!(::VarianceController, N̂, field, domain, diffusivity)`
# folds `_target_factor(field)` (1 for a scalar, ½ for the velocity) into ALL THREE of its
# reductions — the whole-field variance (the restoring term), the band variance (the amplitude's
# normalization), and the dissipation — and no test exercises the scalar branch, so a dropped or
# misplaced factor in exactly one of the three would pass every existing (velocity-only) test.
#
# This test asserts the CORRECT scalar-convention behaviour: with N̂ = A·band·φ̂, the amplitude is
#   A = (χ − G·(⟨φ²⟩ − target)/t_ℓ) / (2·⟨φ̂, band φ̂⟩),   χ = 2κ⟨φ̂, |κ|² φ̂⟩,
# factor 1 throughout (the variance convention: ⟨φ²⟩, never ½⟨φ²⟩). The discriminating half checks
# the velocity-convention (½) contamination gives a DIFFERENT number here, so the test cannot be
# satisfied by a formula that quietly applies the kinetic-energy factor to the scalar.

using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data, convolve!, inner, weighted_inner
using Random
using Test


@testset "VarianceController honours the scalar (variance, factor 1) convention in all three reductions" begin
  T = Float64
  N = 24
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_family = Array)

  φ̂ = new_scalar_field_spectral(domain)
  random_scalar_spectral!(φ̂, domain; scalar_variance = 0.4, envelope_wavenumber = 2.0,
                          rng = MersenneTwister(7))
  truncate_to_band!(φ̂, domain)

  target = 0.25
  κ = 0.05
  forcing = VarianceController(domain; target, gain = 1.0)

  N̂ = new_scalar_field_spectral(domain)
  field_data(N̂) .= 0
  add_forcing_source!(forcing, nothing, N̂, φ̂, domain, κ)

  # The three reductions, computed independently of the hook's fused route, at factor 1:
  whole = real(inner(φ̂, φ̂))                                   # ⟨φ²⟩, the quantity held
  probe = new_scalar_field_spectral(domain)
  copyto!(field_data(probe), field_data(φ̂))
  convolve!(probe, probe, forcing.band, one(T), zero(T))       # band-projected φ̂
  band_variance = real(inner(φ̂, probe))                        # ⟨φ̂, band φ̂⟩
  dirichlet = real(weighted_inner(φ̂, domain.squared_wavenumber_kernel))
  χ = 2 * κ * dirichlet                                        # the variance dissipation rate

  expected = (χ - forcing.gain * (whole - target) / forcing.turnover_time) / (2 * band_variance)

  # Recover the amplitude the hook applied: N̂ = A·band·φ̂, so project onto the band-projected φ̂.
  applied = real(inner(N̂, probe)) / real(inner(probe, probe))
  @test isapprox(applied, expected; rtol = 1e-10)

  # The discriminating half: the velocity convention (factor ½ in any or all of the three places)
  # gives a DIFFERENT amplitude on this field, so the assertion above genuinely pins factor 1.
  half_everywhere = (2 * 0.5 * κ * dirichlet -
                     forcing.gain * (0.5 * whole - target) / forcing.turnover_time) /
                    (2 * 0.5 * band_variance)
  half_dissipation_only = (2 * 0.5 * κ * dirichlet -
                           forcing.gain * (whole - target) / forcing.turnover_time) /
                          (2 * band_variance)
  half_restoring_only = (χ - forcing.gain * (0.5 * whole - target) / forcing.turnover_time) /
                        (2 * band_variance)
  half_band_only = (χ - forcing.gain * (whole - target) / forcing.turnover_time) /
                   (2 * 0.5 * band_variance)
  for wrong in (half_everywhere, half_dissipation_only, half_restoring_only, half_band_only)
    @test !isapprox(applied, wrong; rtol = 1e-3)
  end
end
