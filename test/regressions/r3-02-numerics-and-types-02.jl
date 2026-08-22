# Witness: `_BAND_OBSERVABLE_FLOOR = 1e-12` (src/Forcing.jl:64) is an ABSOLUTE threshold compared
# against a band observable that carries the run's own (free) amplitude scale, so it decides
# "empty band" by magnitude rather than by numerical emptiness.
#
# The correctness principle used here needs no unit convention: the passive-scalar transport
# equation is EXACTLY LINEAR in φ, so φ → s·φ together with ε_φ → s²·ε_φ is an exact symmetry of
# the forced problem. Under it
#   * `ConstantPower`'s rate  A = ε_φ / (2·variance_band)  is exactly invariant, and
#   * `VarianceRescaling(over = :band)` with target → s²·target must reach the scaled target.
# Both must therefore be independent of the arbitrary amplitude s. They are not: below s ≈ 1e-6 the
# fixed floor fires and the forcing silently switches off, even though the band observable is still
# reproduced to ~15 significant digits (asserted below), i.e. is nowhere near numerically empty.
using Test
using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data, weighted_inner, spectral_band, inner
using Random

@testset "the empty-band floor must be a numerical test, not an amplitude test" begin
  N, L, T = 16, 2π, Float64
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_type = Array)
  k0 = 2π / L
  band = spectral_band(new_scalar_field_spectral(domain), domain.multipliers, 0.5 * k0, 2.5 * k0)

  φ0 = new_scalar_field_spectral(domain)
  random_scalar_spectral!(φ0, domain; scalar_variance = 1.0, envelope_wavenumber = 2.0,
                          rng = MersenneTwister(7))
  scaled(s) = (ψ = new_scalar_field_spectral(domain);
               copyto!(field_data(ψ), field_data(φ0)); field_data(ψ) .*= T(s); ψ)

  # The amplitude scale at which the fixed floor fires: variance_band(1) ≈ 0.909, so s = 1e-7 puts
  # the band observable at ≈ 9.1e-15, three orders below the floor — and a genuine, fully resolved
  # number in Float64, as the first assertion pins down.
  s = 1e-7
  reference_band = weighted_inner(φ0, band)
  scaled_band = weighted_inner(scaled(s), band)

  # (1) The scaled band observable is NOT numerically empty: it reproduces the reference to ~1e-15
  #     relative, so the guard cannot be defended as catching round-off.
  @test isapprox(scaled_band / s^2, reference_band; rtol = 1e-13)

  # (2) ConstantPower's rate is invariant under the exact scaling symmetry of the linear scalar.
  # UPDATED 2026-08-22: `ConstantPower` no longer supplies a rate to the integrating factor — its A
  # tracks the band variance and is not steady in time, so it goes through the per-stage source. The
  # amplitude is recovered from the source it adds: N̂ = A·𝟙_band·φ, hence A = ⟨φ,N̂⟩ / ⟨φ,𝟙_band φ⟩.
  rate_amplitude(φ, injection_rate) = begin
    forcing = ConstantPower(domain; injection_rate = injection_rate)
    N̂ = new_scalar_field_spectral(domain)
    field_data(N̂) .= 0
    add_forcing_source!(forcing, N̂, φ, domain, 0.05)     # ConstantPower ignores the diffusivity
    real(inner(φ, N̂)) / weighted_inner(φ, band)
  end
  A_reference = rate_amplitude(φ0, 0.1)
  A_scaled    = rate_amplitude(scaled(s), 0.1 * s^2)
  @test A_reference > 0                                   # the reference case forces at all
  @test isapprox(A_scaled, A_reference; rtol = 1e-10)      # the rate must not depend on the amplitude

  # (3) VarianceRescaling must reach its target at any amplitude, not silently return the field.
  held(φ, target) = (project_forcing!(VarianceRescaling(domain; target = target, over = :band), φ, domain);
                     weighted_inner(φ, band))
  @test isapprox(held(scaled(1.0), 2.0), 2.0; rtol = 1e-10)
  @test isapprox(held(scaled(s), 2.0 * s^2) / s^2, 2.0; rtol = 1e-10)
end
