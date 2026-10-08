# energy_spectrum returns the spectral DENSITY E(κ), not the shell bin sum — the owner-directed
# cutover of 2026-08-23. The two conventions coincide numerically on the default 2π box (Δκ = 1),
# which is how the bin-sum convention survived: every test ran where the factor is invisible. This
# witness therefore pins the normalization on a NON-default box, where the conventions differ by
# Δκ = 2π/L = 2 — the old code fails the first assertion at exactly that factor.
using Test, GBGHomogeneousTurbulence, Random


@testset "energy_spectrum is a density: Parseval quadrature holds off the default box" begin
  domain = FixedDomain(grid_points_per_axis = 16, side_length = π, element_type = Float64,
                       dealiasing = TwoThirds(), array_family = Array)
  û = new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.7,
                                       envelope_wavenumber = 4.0, rng = MersenneTwister(5))
  κ, E = energy_spectrum(û, domain)
  Δκ = 2π / π                                   # the shell width on this box: 2, not 1
  @test isapprox(sum(E) * Δκ, kinetic_energy(û); rtol = 1e-12)   # k = Σ E(κₙ)·Δκ — the quadrature
  @test !isapprox(sum(E), kinetic_energy(û); rtol = 1e-2)        # the bin-sum reading is wrong here
end
