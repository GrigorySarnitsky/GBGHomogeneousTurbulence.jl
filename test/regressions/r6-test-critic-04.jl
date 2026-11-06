# r6-test-critic-04 — the seed-peak-beyond-cutoff warning is exercised.
# The sibling of the forcing-band-cutoff warning test in test/forcing.jl ("a band above the dealias
# cutoff warns"). Mirrors its warns(f) capture helper. N = 16 under TwoThirds puts the dealias
# cutoff at κ_max ≈ 5.33; the seeded spectrum peaks at κ_p, so peak_shell = 12 must warn and
# peak_shell = 2 must stay silent.

using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.State: random_solenoidal_velocity_spectral!, random_scalar_spectral!
using GBGHomogeneousTurbulence.SimulationDomain: new_vector_field_spectral, new_scalar_field_spectral
using Logging
using Random
using Test


@testset "a seed envelope peaking at or beyond the dealias cutoff warns; an ordinary seed is silent" begin
  domain = FixedDomain(grid_points_per_axis = 16, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_family = Array)
  û = new_vector_field_spectral(domain)
  φ̂ = new_scalar_field_spectral(domain)

  warns(f) = begin
    buf = IOBuffer()
    Logging.with_logger(Logging.SimpleLogger(buf, Logging.Warn)) do; f(); end
    String(take!(buf))
  end

  # κ_max ≈ 5.33; κ_p = 12 puts the spectrum peak beyond it — must warn.
  @test occursin("beyond the dealias cutoff",
                 warns(() -> random_solenoidal_velocity_spectral!(û, domain, 0.5;
                                                                  peak_shell = 12.0,
                                                                  rng = MersenneTwister(1))))
  @test occursin("beyond the dealias cutoff",
                 warns(() -> random_scalar_spectral!(φ̂, domain, 1.0;
                                                     peak_shell = 12.0,
                                                     rng = MersenneTwister(2))))

  # The boundary is the peak itself: κ_p = 5.0 sits below the cutoff and is silent, κ_p = 5.5 above
  # it and warns. A peak taken as κ_p/√2 (the envelope's earlier definition) silences the second; one
  # taken as √2·κ_p warns on the first.
  @test isempty(warns(() -> random_solenoidal_velocity_spectral!(û, domain, 0.5;
                                                                 peak_shell = 5.0,
                                                                 rng = MersenneTwister(3))))
  @test occursin("beyond the dealias cutoff",
                 warns(() -> random_solenoidal_velocity_spectral!(û, domain, 0.5;
                                                                  peak_shell = 5.5,
                                                                  rng = MersenneTwister(3))))

  # An ordinary seed — the value every suite test uses — must stay silent.
  @test isempty(warns(() -> random_solenoidal_velocity_spectral!(û, domain, 0.5;
                                                                 peak_shell = 2.0,
                                                                 rng = MersenneTwister(4))))
  @test isempty(warns(() -> random_scalar_spectral!(φ̂, domain, 1.0;
                                                    peak_shell = 2.0,
                                                    rng = MersenneTwister(5))))
end
