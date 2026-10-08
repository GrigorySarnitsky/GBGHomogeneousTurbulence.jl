using Test, Random, GBGHomogeneousTurbulence
using GBGPeriodicFields: npoints
using GBGPeriodicFields: field_data, CatmullRom

@testset "allocate_buffers rejects a cache whose sample history is too short for the scheme" begin
  domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π,
                       dealiasing = TwoThirds(), element_type = Float64, array_family = Array)
  tracers = Tracers(domain; number_of_particles = 4, interpolation_scheme = CatmullRom,
                    rng = MersenneTwister(1))
  u = new_vector_field_physical(domain)
  fill!(field_data(u), 0.1)

  scheme = AdamsBashforth(order = 4)              # needs history_depth(scheme) == 4
  # A hand-assembled run that forgets `history_depth` gets the default 1 — no past slots at all.
  cache = ObservablesCache(domain; number_of_particles = npoints(tracers.positions))
  @test history_depth(scheme) == 4
  @test length(cache.velocity_at_particles_history) == 0

  # The mismatch must be refused where it is introduced, not deferred to a raw BoundsError deep
  # inside the tracer advance — the same construction-time refusal the package applies elsewhere.
  @test_throws ArgumentError allocate_buffers(scheme, tracers, cache)
end

# Measured on the tree at 9b3ecdd: `allocate_buffers` returned the multistep buffers silently, and the
# first `advect!` (after the particle `deposit!`) then throws
#   BoundsError: attempt to access 0-element Vector{VectorPointValues{Float64, Matrix{Float64}}} at index [1]
# from Particles.jl:474, `copyto!(point_values(past[1]), f0)` — naming neither the cache nor the scheme.
