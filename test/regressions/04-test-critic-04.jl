# Witness 04 (lane test-critic): the scalar branch of Forcing._target_factor.
#
# The claim under test: ConstantPower and VarianceRescaling are never exercised with a SCALAR field
# anywhere in test/, so the `tensor_order == 0 ⇒ factor 1.0` branch of `_target_factor` is
# unverified — a wrong factor there (½ instead of 1) would silently halve the scalar injection
# rate and √2-scale the held scalar variance.
#
# These tests assert the CORRECT scalar-convention behaviour:
#   * ConstantPower:  A · 2 · ⟨φ²⟩_band = injection_rate   (variance convention, NO ½)
#   * VarianceRescaling:  after the post-step rescale, ⟨φ²⟩_band = target  (over = :band)
#   * VarianceRescaling:  after the post-step rescale, ⟨φ²⟩_total = target (over = :total)

using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data, spectral_band, convolve!, inner
using Random
using Test


@testset "ConstantPower / VarianceRescaling honour the scalar (variance, factor 1) convention" begin
  T = Float64
  N = 24
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_family = Array)

  k0 = 2π / L
  band = spectral_band(domain.multipliers, 0.5 * k0, 2.5 * k0)  # shells 1–2
  # ⟨φ²⟩ restricted to the band: the band indicator is idempotent, so ⟨bφ̂, bφ̂⟩ = ⟨φ̂, b φ̂⟩.
  band_variance(φ̂) = (tmp = new_scalar_field_spectral(domain); convolve!(tmp, φ̂, band); inner(tmp, tmp))

  φ̂0 = new_scalar_field_spectral(domain)
  random_scalar_spectral!(φ̂0, domain; scalar_variance = 0.4, envelope_wavenumber = 2.0,
                          rng = MersenneTwister(11))
  truncate_to_band!(φ̂0, domain)

  fresh() = (φ̂ = new_scalar_field_spectral(domain); copyto!(field_data(φ̂), field_data(φ̂0)); φ̂)

  @testset "ConstantPower on a scalar sets injection rate = power" begin
    # UPDATED 2026-08-22. The property is unchanged — d⟨φ²⟩/dt = ε_target — but the route is.
    # `ConstantPower`'s rate tracks the band variance and so is NOT steady in time; folded into the
    # integrating factor it integrated ∫A dt by a left-endpoint rectangle rule and cost the scheme
    # its order. It goes through the per-stage source now, which receives the STAGE field.
    power = 0.3
    forcing = ConstantPower(domain; injection_rate = power, lowest_shell = 1, highest_shell = 2)
    φ̂ = fresh()
    N̂ = new_scalar_field_spectral(domain)
    field_data(N̂) .= 0
    add_forcing_source!(forcing, nothing, N̂, φ̂, domain, 0.05)   # ConstantPower ignores it
    # ⟨φ, f⟩ with f the source just added is the injected rate, at the same convention `target` uses.
    @test 2 * real(inner(φ̂, N̂)) ≈ power  rtol = 1e-8
  end

  @testset "VarianceRescaling(:band) on a scalar holds the band variance" begin
    target = 0.25
    forcing = VarianceRescaling(domain; target = target, over = :band,
                            lowest_shell = 1, highest_shell = 2)
    φ̂ = fresh()
    project_forcing!(forcing, φ̂, domain)
    @test band_variance(φ̂) ≈ target
  end

  @testset "VarianceRescaling(:total) on a scalar holds the whole-field variance" begin
    target = 0.6
    forcing = VarianceRescaling(domain; target = target, over = :total,
                            lowest_shell = 1, highest_shell = 2)
    φ̂ = fresh()
    project_forcing!(forcing, φ̂, domain)
    @test scalar_variance(φ̂) ≈ target
  end
end
