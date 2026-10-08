# Witness: VarianceRescaling(over = :band) must leave the band's own observable AT `target`.
#
# The `:band` branch of `project_forcing!` (src/Forcing.jl) is the default and the simpler of the two
# paths, yet no test measures its post-condition; `test/simulation_run.jl` only checks that the
# whole-field energy is finite and positive after one step. The band observable is measured here
# INDEPENDENTLY of the code under test: the field is band-filtered into a copy with `convolve!`
# and reduced with `kinetic_energy` / `scalar_variance` — never with the `weighted_inner` fused
# route `project_forcing!` itself uses — so a wrong ½-vs-1 `_target_factor`, a wrong `scale`
# formula, or a `convolve!` α/β misuse would show up as a band value away from `target`.

using Test
using GBGHomogeneousTurbulence
using GBGPeriodicFields: convolve!, field_data
using Random


# Band observable measured the long way: filter into a scratch field, then reduce it.
band_kinetic_energy(field, band, scratch) = kinetic_energy(convolve!(scratch, field, band))

band_scalar_variance(field, band, scratch) = scalar_variance(convolve!(scratch, field, band))


# The band's complement, (1 - band) ⊙ field, formed without a second kernel.
outside_band(field, band, scratch) = begin
  convolve!(scratch, field, band, -1, 0)
  field_data(scratch) .+= field_data(field)
  return copy(field_data(scratch))
end


@testset "VarianceRescaling(over = :band) drives the band observable to `target`" begin
  N, L, T = 24, 2π, Float64
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_family = Array)

  @testset "velocity: the band kinetic energy equals `target`" begin
    for target in (0.3, 1.7)
      û = new_vector_field_spectral(domain)
      random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                           envelope_wavenumber = 2.0, rng = MersenneTwister(11))
      forcing = VarianceRescaling(domain; target = target, over = :band)

      scratch = new_vector_field_spectral(domain)
      before = band_kinetic_energy(û, forcing.band, scratch)
      @test before > 0                                  # the band is seeded, so the clamp applies

      project_forcing!(forcing, û, domain)
      @test band_kinetic_energy(û, forcing.band, scratch) ≈ target rtol = 1e-10
    end
  end

  @testset "velocity: modes outside the band are untouched" begin
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                         envelope_wavenumber = 2.0, rng = MersenneTwister(12))
    forcing = VarianceRescaling(domain; target = 0.9, over = :band)

    scratch = new_vector_field_spectral(domain)
    before = outside_band(û, forcing.band, scratch)     # the complement, before the rescale
    project_forcing!(forcing, û, domain)
    @test outside_band(û, forcing.band, scratch) ≈ before
  end

  @testset "scalar: the band variance equals `target` (the factor-1 dispatch)" begin
    for target in (0.4, 2.5)
      φ̂ = new_scalar_field_spectral(domain)
      random_scalar_spectral!(φ̂, domain; scalar_variance = 1.0, envelope_wavenumber = 2.0,
                              rng = MersenneTwister(13))
      forcing = VarianceRescaling(domain; target = target, over = :band)

      scratch = new_scalar_field_spectral(domain)
      @test band_scalar_variance(φ̂, forcing.band, scratch) > 0
      project_forcing!(forcing, φ̂, domain)
      @test band_scalar_variance(φ̂, forcing.band, scratch) ≈ target rtol = 1e-10
    end
  end

  @testset "idempotence: a second application is a no-op" begin
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                         envelope_wavenumber = 2.0, rng = MersenneTwister(14))
    forcing = VarianceRescaling(domain; target = 0.6, over = :band)

    project_forcing!(forcing, û, domain)
    once = copy(field_data(û))
    project_forcing!(forcing, û, domain)
    @test field_data(û) ≈ once
  end
end
