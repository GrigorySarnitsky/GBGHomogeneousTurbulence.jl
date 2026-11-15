# Witness (round 4, state-machine lane, 02): the run's own iteration never marks an unwritten sample.
#
# The candidate once claimed the mark half of the old two-call protocol (`deposit_sample!`) was
# defective because, called alone, it stamped whatever the velocity-at-particles array happened to
# hold as the current-epoch observable. Decision 71 removed the reachable form of that hazard
# outright: the particle `deposit!` writes and stamps in one act, so no public call can mark values
# it did not just produce. What must hold — and what this file asserts — is that the run's own
# iteration leaves the newest sample exactly reproducible from the deposited velocity at the
# deposited positions: the closing deposit wrote it, it did not merely mark it.

using Test, Random
using GBGHomogeneousTurbulence
using GBGPeriodicFields: point_values

build() = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                     particles = ParticleTracking(number_of_particles = 8), rng = MersenneTwister(1))

@testset "the run's own iteration never marks an unwritten sample" begin
  sim = build()
  by_hand = new_vector_point_values(sim.tracers)
  for _ in 1:3
    advance!(sim; dt = 0.01)
    v = Array(point_values(velocity_at_particles_trail(sim.cache)[0].value))
    @test all(isfinite, v)
    # Re-deriving the sample by hand from the deposited velocity at the same positions must
    # reproduce it exactly: the closing deposit wrote it, it did not merely mark it.
    interpolate_at_particles!(by_hand, velocity_physical(sim.cache), sim.tracers;
                              traversal = sim.particle_traversal)
    @test Array(point_values(by_hand)) == v
    # And a second deposit at the same positions is not a way to mark anything: it is refused.
    @test_throws ErrorException deposit!(sim.cache, sim.tracers, current_time(sim) + 1)
  end
end
