# Witness r5-test-critic-06 — the two documented EDGE-CASE branches of
# `project_forcing!(::VarianceRescaling, …)` (src/Forcing.jl:327–341), which no test in the suite reaches:
#
#   (1) the `:total` ZEROING branch — when the value outside the forced shells alone already exceeds
#       `target`, `max(zero(band_value), target - total + band)` clamps the band target to 0, the
#       scale is 0, and the band is emptied in one step (docstring: "the band is **zeroed** — the
#       closest reachable state"). The failure mode guarded against is a lost `max(…, 0)`: a negative
#       `target_band` makes `sqrt` throw `DomainError` (or, in a variant, produces a `NaN` field).
#
#   (2) the EMPTY-BAND early return — `_band_is_empty(band_value) && return field`: a band with
#       nothing in it is left alone rather than divided by ~0 (docstring: "an empty band stays empty
#       instead of being driven to `target`"). The failure mode guarded against is an inverted or
#       dropped early return: `sqrt(target/0) == Inf`, and the field fills with `NaN`.
#
# Every quantity is measured INDEPENDENTLY of the code under test: the band is filtered into a
# scratch field with `convolve!` and reduced with `kinetic_energy` / `scalar_variance`, never through
# the `weighted_inner` route `project_forcing!` uses itself.

using Test
using GBGIsotropicTurbulence
using GBGPeriodicFields: convolve!, field_data, divergence, l2norm
using Random


# The band's own observable, measured the long way (filter into scratch, then reduce).
band_kinetic_energy(field, band, scratch) = kinetic_energy(convolve!(scratch, field, band))

band_scalar_variance(field, band, scratch) = scalar_variance(convolve!(scratch, field, band))


# (1 - band) ⊙ field, formed without a second kernel: the modes the rescale must never touch.
function outside_band(field, band, scratch)
  convolve!(scratch, field, band, -1, 0)
  field_data(scratch) .+= field_data(field)
  return copy(field_data(scratch))
end


# Strip the band's content out of `field` in place: field ← field - band ⊙ field.
strip_band!(field, band) = convolve!(field, field, band, -1, 1)


@testset "VarianceRescaling's two edge-case branches behave as documented" begin
  N, L, T = 24, 2π, Float64
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_type = Array)

  @testset ":total with the out-of-band value above `target` empties the band" begin
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                         envelope_wavenumber = 8.0, rng = MersenneTwister(21))
    scratch = new_vector_field_spectral(domain)
    forcing = VarianceRescaling(domain; target = 1e-4, over = :total)   # far below the out-of-band energy

    band_before = band_kinetic_energy(û, forcing.band, scratch)
    total_before = kinetic_energy(û)
    @test band_before > 0                                  # the ordinary path would run …
    @test total_before - band_before > forcing.target       # … but the out-of-band value alone exceeds `target`

    outside_before = outside_band(û, forcing.band, scratch)
    project_forcing!(forcing, û, domain)

    @test all(isfinite, field_data(û))                     # no DomainError/NaN from a lost max(…, 0)
    @test band_kinetic_energy(û, forcing.band, scratch) ≈ 0 atol = 1e-24   # the band is zeroed
    @test outside_band(û, forcing.band, scratch) ≈ outside_before          # nothing else moved
    @test kinetic_energy(û) ≈ total_before - band_before rtol = 1e-10
  end

  @testset "the step after a zeroing leaves the (now empty) band alone" begin
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                         envelope_wavenumber = 8.0, rng = MersenneTwister(22))
    forcing = VarianceRescaling(domain; target = 1e-4, over = :total)

    project_forcing!(forcing, û, domain)                     # the zeroing step
    zeroed = copy(field_data(û))
    project_forcing!(forcing, û, domain)                     # the step after
    @test field_data(û) == zeroed                          # bit-identical: the early return fired
  end

  @testset "an empty band is left untouched, not divided by ~0 (velocity, :band)" begin
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                         envelope_wavenumber = 8.0, rng = MersenneTwister(23))
    forcing = VarianceRescaling(domain; target = 0.7, over = :band)
    strip_band!(û, forcing.band)                           # exactly nothing left in the band

    scratch = new_vector_field_spectral(domain)
    @test band_kinetic_energy(û, forcing.band, scratch) == 0

    before = copy(field_data(û))
    project_forcing!(forcing, û, domain)
    @test field_data(û) == before                          # untouched, not driven to `target`
    project_forcing!(forcing, û, domain)
    @test field_data(û) == before                          # and still untouched on a second call
    @test all(isfinite, field_data(û))
  end

  @testset "an empty band is left untouched under :total as well" begin
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                         envelope_wavenumber = 8.0, rng = MersenneTwister(24))
    forcing = VarianceRescaling(domain; target = 0.7, over = :total)
    strip_band!(û, forcing.band)

    before = copy(field_data(û))
    project_forcing!(forcing, û, domain)
    @test field_data(û) == before
    @test all(isfinite, field_data(û))
  end

  @testset "an empty band is left untouched (scalar, the factor-1 dispatch)" begin
    φ̂ = new_scalar_field_spectral(domain)
    random_scalar_spectral!(φ̂, domain; scalar_variance = 1.0, envelope_wavenumber = 8.0,
                            rng = MersenneTwister(25))
    forcing = VarianceRescaling(domain; target = 0.5, over = :band)
    strip_band!(φ̂, forcing.band)

    scratch = new_scalar_field_spectral(domain)
    @test band_scalar_variance(φ̂, forcing.band, scratch) == 0

    before = copy(field_data(φ̂))
    project_forcing!(forcing, φ̂, domain)
    @test field_data(φ̂) == before
    @test all(isfinite, field_data(φ̂))
  end

  @testset "a zeroed velocity band keeps the field divergence-free" begin
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                         envelope_wavenumber = 8.0, rng = MersenneTwister(26))
    forcing = VarianceRescaling(domain; target = 1e-4, over = :total)
    project_forcing!(forcing, û, domain)
    rel_div = l2norm(divergence(û, domain.multipliers)) / (l2norm(û) + 1e-30)
    @test rel_div < 1e-10
  end
end
