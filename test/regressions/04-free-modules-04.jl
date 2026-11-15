using Test, Random, GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data, CatmullRom, point_positions

include(joinpath(@__DIR__, "..", "prescribed_flow.jl"))

@testset "a cache whose trail is too short for the scheme is refused where the two meet" begin
  domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π,
                       dealiasing = TwoThirds(), element_type = Float64, array_family = Array)
  tracers = Tracers(domain; number_of_particles = 4, interpolation_scheme = CatmullRom,
                    rng = MersenneTwister(1))
  uniform!(u) = (fill!(field_data(u), 0.1); u)

  scheme = AB(4)                                  # integrates over four samples
  # A cache built for the default scheme keeps two.
  cache = ObservablesCache(domain; tracers, particle_integration_scheme = Heun())
  @test length(cache.velocity_at_particles_trail.values) == 2

  # The mismatch must be refused where it is introduced, by name, not deferred to a raw BoundsError
  # deep inside the tracer advance — the same refusal the package applies elsewhere — and before the
  # tracers have moved.
  deposit_prescribed_velocity!(uniform!, cache; step = false)
  deposit!(cache, tracers, 0.0)
  deposit_prescribed_velocity!(uniform!, cache)
  before = copy(point_positions(tracers.positions))
  @test_throws ArgumentError advect!(scheme, tracers, domain, cache, 0.01)
  @test point_positions(tracers.positions) == before
end

# Measured on the tree at 9b3ecdd, where the cache was built apart from the scheme: the pairing was
# accepted silently, and the first `advect!` then threw
#   BoundsError: attempt to access 0-element Vector{VectorPointValues{Float64, Matrix{Float64}}} at index [1]
# naming neither the cache nor the scheme.
