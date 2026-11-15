# Witness: `advect!` must refuse a scheme that disagrees with the one its cache was built for, with
# a named `ArgumentError` — not a raw `BoundsError` from the cache's samples, and not a silent run at
# another order.

using Test, Random
using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data, CatmullRom

include(joinpath(@__DIR__, "..", "prescribed_flow.jl"))

@testset "advect! refuses a scheme its cache was not built for" begin
  domain = FixedDomain(grid_points_per_axis = 16, side_length = 2π, dealiasing = TwoThirds(),
                       element_type = Float64, array_family = Array)
  uniform!(u, t) = (field_data(u) .= 0.2; u)
  five_steps(built_for, driven_with) = begin
    tracers = Tracers(domain; number_of_particles = 6, interpolation_scheme = CatmullRom,
                      rng = MersenneTwister(1))
    cache = ObservablesCache(domain; tracers, particle_integration_scheme = built_for)
    advect_in_prescribed_flow!(uniform!, driven_with, tracers, domain, cache, fill(0.01, 5))
  end

  # --- forward mismatch: a cache for two samples, driven by a scheme of four ------------------
  @test_throws ArgumentError five_steps(AB(2), AB(4))
  # --- reverse mismatch: a cache for four, driven by a scheme of two --------------------------
  @test_throws ArgumentError five_steps(AB(4), AB(2))
  # --- the same number of steps, with and without the corrector: different sample counts ------
  @test_throws ArgumentError five_steps(AB(3), ABM(3))
  # --- and the matching pair runs ------------------------------------------------------------
  @test five_steps(AB(4), AB(4)) ≈ 0.05
end
