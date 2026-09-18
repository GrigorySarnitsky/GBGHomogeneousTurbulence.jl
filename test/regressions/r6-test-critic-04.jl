# r6-test-critic-04 — the seed-envelope-beyond-cutoff warning (src/State.jl:47) is exercised.
# The sibling of the forcing-band-cutoff warning test in test/forcing.jl ("a band above the dealias
# cutoff warns"). Mirrors its warns(f) capture helper. N = 16 under TwoThirds puts the dealias
# cutoff at κ_max ≈ 5.33; the seeded spectrum peaks at κ_p/√2, so envelope_wavenumber = 12
# (peak ≈ 8.49) must warn, envelope_wavenumber = 2 must stay silent, and the initial_spectrum
# branch must stay silent regardless (the guard is gated on the default-envelope branch only).

using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.State: random_solenoidal_velocity_spectral!, random_scalar_spectral!
using GBGHomogeneousTurbulence.SimulationDomain: new_vector_field_spectral, new_scalar_field_spectral
using Logging
using Random
using Test


@testset "a seed envelope peaking at or beyond the dealias cutoff warns; an ordinary seed is silent" begin
  domain = FixedDomain(grid_points_per_axis = 16, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_type = Array)
  û = new_vector_field_spectral(domain)
  φ̂ = new_scalar_field_spectral(domain)

  warns(f) = begin
    buf = IOBuffer()
    Logging.with_logger(Logging.SimpleLogger(buf, Logging.Warn)) do; f(); end
    String(take!(buf))
  end

  # κ_max ≈ 5.33; κ_p = 12 puts the spectrum peak κ_p/√2 ≈ 8.49 beyond it — must warn.
  @test occursin("beyond the dealias cutoff",
                 warns(() -> random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                                                  envelope_wavenumber = 12.0,
                                                                  rng = MersenneTwister(1))))
  @test occursin("beyond the dealias cutoff",
                 warns(() -> random_scalar_spectral!(φ̂, domain; scalar_variance = 1.0,
                                                     envelope_wavenumber = 12.0,
                                                     rng = MersenneTwister(2))))

  # The boundary is the peak κ_p/√2, not κ_p itself: κ_p = 6 exceeds κ_max, but its peak
  # 6/√2 ≈ 4.24 < 5.33 — must stay silent (a dropped /√2 factor would warn here).
  @test isempty(warns(() -> random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                                                 envelope_wavenumber = 6.0,
                                                                 rng = MersenneTwister(3))))

  # An ordinary seed — the value every suite test uses — must stay silent.
  @test isempty(warns(() -> random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                                                 envelope_wavenumber = 2.0,
                                                                 rng = MersenneTwister(4))))
  @test isempty(warns(() -> random_scalar_spectral!(φ̂, domain; scalar_variance = 1.0,
                                                    envelope_wavenumber = 2.0,
                                                    rng = MersenneTwister(5))))

  # The initial_spectrum branch carries its own large scale; envelope_wavenumber is inert there,
  # so even an absurd value must stay silent.
  @test isempty(warns(() -> random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                                                 envelope_wavenumber = 12.0,
                                                                 initial_spectrum = κ -> exp(-κ^2),
                                                                 rng = MersenneTwister(6))))
  @test isempty(warns(() -> random_scalar_spectral!(φ̂, domain; scalar_variance = 1.0,
                                                    envelope_wavenumber = 12.0,
                                                    initial_spectrum = κ -> exp(-κ^2),
                                                    rng = MersenneTwister(7))))
end
