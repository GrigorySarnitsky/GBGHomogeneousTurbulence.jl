# The seed's envelope is stated in shells of the box's fundamental 2π/L, as the forcing bands are, so
# the same draw gives the same seed on every box. It was an absolute wavenumber whose default 2.0 was
# shell 2 only on L = 2π: on L = 1 it seeded shell 1 alone, and on a 2 cm box exp(−κ²/κ_p²)
# underflowed on every mode and the seeder threw.
using Test, Random
using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data


@testset "the seed has one shape on every box" begin
  box(L) = FixedDomain(grid_points_per_axis = 16, side_length = L, element_type = Float64,
                       dealiasing = TwoThirds(), array_family = Array)
  reference = box(2π)
  û_reference = random_solenoidal_velocity_spectral!(new_vector_field_spectral(reference), reference,
                                                     0.5; rng = MersenneTwister(1))
  φ̂_reference = random_scalar_spectral!(new_scalar_field_spectral(reference), reference, 1.0;
                                        rng = MersenneTwister(2))
  for L in (1.0, 0.02)
    domain = box(L)
    û = random_solenoidal_velocity_spectral!(new_vector_field_spectral(domain), domain, 0.5;
                                             rng = MersenneTwister(1))
    φ̂ = random_scalar_spectral!(new_scalar_field_spectral(domain), domain, 1.0;
                                rng = MersenneTwister(2))
    @test field_data(û) ≈ field_data(û_reference) rtol = 1e-12
    @test field_data(φ̂) ≈ field_data(φ̂_reference) rtol = 1e-12
  end
end
