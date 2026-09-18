# The two remaining owner-ruled guards of 2026-08-24 (the panel escalation list): the seeders warn
# when the envelope's spectrum peak reaches the dealias cutoff (the forcing-band warning's sibling
# — most of the pre-rescale seed would land in masked shells), and the empty-band floor names
# itself once (maxlog = 1) when it clamps a forcing to inert, instead of going silent forever.
using Test, Random, Logging
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Forcing: add_forcing_source!
using GBGPeriodicFields: field_data, convolve!, to_physical, to_spectral


@testset "owner-ruled guards: envelope-vs-cutoff and the floor's one-time signal" begin
  domain = FixedDomain(grid_points_per_axis = 16, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_type = Array)
  # κ_max = (2/3)·(N/2)·(2π/L) = 16/3 ≈ 5.33 here; κ_p = 8 puts the peak 8/√2 ≈ 5.66 beyond it.
  û = new_vector_field_spectral(domain)
  @test_logs (:warn, r"dealias cutoff") match_mode=:any random_solenoidal_velocity_spectral!(
      û, domain; kinetic_energy = 0.5, envelope_wavenumber = 8.0, rng = MersenneTwister(1))
  φ̂ = new_scalar_field_spectral(domain)
  @test_logs (:warn, r"dealias cutoff") match_mode=:any random_scalar_spectral!(
      φ̂, domain; scalar_variance = 1.0, envelope_wavenumber = 8.0, rng = MersenneTwister(2))
  # The default κ_p = 2 stays silent.
  @test_logs min_level=Logging.Warn random_solenoidal_velocity_spectral!(
      û, domain; kinetic_energy = 0.5, envelope_wavenumber = 2.0, rng = MersenneTwister(3))

  # The floor's signal: empty the forced band (subtract + transform round trip leaves positive
  # roundoff), then the first clamped stage warns; the run stays usable (no throw, zero source).
  forcing = ConstantPower(domain; injection_rate = 0.1)
  random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                       envelope_wavenumber = 2.0, rng = MersenneTwister(5))
  convolve!(û, û, forcing.band, -1.0, 1.0)
  field_data(û) .= field_data(to_spectral(to_physical(û, domain.transform_plans),
                                          domain.transform_plans))
  N̂ = new_vector_field_spectral(domain); fill!(field_data(N̂), 0)
  @test_logs (:warn, r"band is empty") match_mode=:any add_forcing_source!(
      forcing, nothing, N̂, û, domain, 0.05)
  @test all(iszero, field_data(N̂))
end
