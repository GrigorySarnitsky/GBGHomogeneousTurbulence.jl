# Witness: `advect!` must refuse a scheme whose order disagrees with the one its
# buffers were allocated for, with a named `ArgumentError` naming the argument pair —
# not a raw `BoundsError` from the cache's history vector, and not a silent wrong-order run.

using Test, Random
using GBGPeriodicFields: npoints
using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data, CatmullRom, point_values

@testset "advect! refuses a scheme order that its buffers were not built for" begin
  domain = FixedDomain(grid_points_per_axis = 16, side_length = 2π, dealiasing = TwoThirds(),
                       element_type = Float64, array_type = Array)
  u = new_vector_field_physical(domain)
  field_data(u) .= 0.2

  # --- forward mismatch: buffers for order 2, driven at order 4 -------------------------------
  tracers = Tracers(domain; number_of_particles = 6, interpolation_scheme = CatmullRom,
                    rng = MersenneTwister(1))
  cache = ObservablesCache(domain; number_of_particles = npoints(tracers.positions),
                           history_depth = 2)
  buffers = allocate_buffers(AdamsBashforth(order = 2), tracers, cache)

  @test_throws ArgumentError begin
    for _ in 1:5
      deposit!(cache, tracers, u)
      advect!(AdamsBashforth(order = 4), tracers, u, domain, buffers, 0.01)
    end
  end

  # --- reverse mismatch: buffers for order 4, driven at order 2 -------------------------------
  tracers2 = Tracers(domain; number_of_particles = 6, interpolation_scheme = CatmullRom,
                     rng = MersenneTwister(1))
  cache2 = ObservablesCache(domain; number_of_particles = npoints(tracers2.positions),
                            history_depth = 4)
  buffers2 = allocate_buffers(AdamsBashforth(order = 4), tracers2, cache2)

  @test_throws ArgumentError begin
    for _ in 1:5
      deposit!(cache2, tracers2, u)
      advect!(AdamsBashforth(order = 2), tracers2, u, domain, buffers2, 0.01)
    end
  end
end
