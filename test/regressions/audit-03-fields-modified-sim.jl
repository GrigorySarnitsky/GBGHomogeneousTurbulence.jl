# Witness — AUDIT finding (two lanes, and confirmed by hand): the `fields_modified!(sim)` convenience
# added beside `particles_modified!(sim)` is a SECOND, unimported generic. It throws on the exact call
# its own comment describes, in both directions: the outer call finds no ::Simulation method on the
# exported binding, and its body's inner call finds no ::ObservablesCache method on the local one.
using Test, GBGIsotropicTurbulence, Random

@testset "fields_modified!(sim) works on the call its own documentation describes" begin
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, number_of_particles = 8,
                   trajectory_scheme = AdamsBashforth(order = 4), rng = MersenneTwister(4))
  for _ in 1:6; advance!(sim); end
  @test sim.cache.history_filled == 3
  # Wrapped: a bare call throws MethodError, which escapes the testset and registers as BROKEN
  # (evidence of nothing) rather than as the failure it is.
  ok = try; fields_modified!(sim); true; catch err; @info "threw" err; false; end
  @test ok                                    # the run-level announce must not throw
  @test sim.cache.history_filled == 0         # and must do what the cache form does
  @test length(methods(fields_modified!)) >= 2
end
