# Round 5, lane test-critic, witness 05.
#
# Candidate: the "nothing left to rescale" guard in `State` — the `ArgumentError` raised when the
# Gaussian envelope and the dealiasing band together annihilate every seeded mode — is reached by no
# test in the suite, for either the velocity seeder (src/State.jl:145) or the scalar twin
# (src/State.jl:220). Every existing call passes `envelope_wavenumber = 2.0 … 4.0`, which keeps the
# band populated, so a regression turning the guard into a silent 0/0 (a NaN field rescaled by
# `sqrt(k/0)`) would pass the suite unnoticed.
#
# This asserts the CORRECT behaviour: with a characteristic wavenumber so small that
# exp(-κ²/κ_p²) underflows to 0 at every κ > 0 — and with the κ = 0 mode already zeroed by
# construction — the seeders must REFUSE the request with a descriptive `ArgumentError`, never hand
# back a zero or NaN-bearing field whose energy/variance is not the one asked for.

using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data
using Random
using Test


const DOMAIN = FixedDomain(grid_points_per_axis = 16, side_length = 2π,
                           dealiasing = TwoThirds(), element_type = Float64,
                           array_type = Array)


@testset "the seeders refuse a request whose every mode the envelope annihilates" begin

  @testset "velocity: the annihilating envelope really does empty the band" begin
    û = new_vector_field_spectral(DOMAIN)
    # Premise, asserted rather than assumed: the seeded field before rescaling is exactly zero.
    # (Reproduce the pre-rescale pipeline by catching the guard and inspecting nothing — instead
    #  assert the observable consequence: the call must throw.)
    thrown = try
      random_solenoidal_velocity_spectral!(û, DOMAIN; kinetic_energy = 1.0,
                                           envelope_wavenumber = 1.0e-8,
                                           rng = MersenneTwister(20260821))
      nothing
    catch err
      err
    end
    @test thrown isa ArgumentError
    # The message must name what the user can act on.
    @test thrown isa ArgumentError && occursin("envelope_wavenumber", sprint(showerror, thrown))
    # And nothing NaN-bearing was written into the caller's field.
    @test !any(isnan, field_data(û))
  end

  @testset "scalar: the same guard, on the twin" begin
    φ̂ = new_scalar_field_spectral(DOMAIN)
    thrown = try
      random_scalar_spectral!(φ̂, DOMAIN; scalar_variance = 1.0,
                              envelope_wavenumber = 1.0e-8,
                              rng = MersenneTwister(20260822))
      nothing
    catch err
      err
    end
    @test thrown isa ArgumentError
    @test thrown isa ArgumentError && occursin("envelope_wavenumber", sprint(showerror, thrown))
    @test !any(isnan, field_data(φ̂))
  end

  @testset "control: the guard has not over-fired on a normal seed" begin
    û = new_vector_field_spectral(DOMAIN)
    random_solenoidal_velocity_spectral!(û, DOMAIN; kinetic_energy = 0.5,
                                         envelope_wavenumber = 2.0,
                                         rng = MersenneTwister(1))
    @test kinetic_energy(û) ≈ 0.5

    φ̂ = new_scalar_field_spectral(DOMAIN)
    random_scalar_spectral!(φ̂, DOMAIN; scalar_variance = 1.0,
                            envelope_wavenumber = 2.0, rng = MersenneTwister(2))
    @test scalar_variance(φ̂) ≈ 1.0
  end

end
