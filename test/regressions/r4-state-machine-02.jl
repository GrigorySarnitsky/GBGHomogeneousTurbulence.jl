# Witness (round 4, state-machine lane, 02): the run's own iteration never marks an unwritten sample.
#
# The candidate once claimed the mark half of the old two-call protocol (`deposit_sample!`) was
# defective because, called alone, it stamped whatever the velocity-at-particles array happened to
# hold as the current-epoch observable. Decision 71 removed the reachable form of that hazard
# outright: the particle `deposit!` writes and stamps in one act, so no public call can mark values
# it did not just produce. What must hold — and what this file asserts — is that the run's own
# iteration leaves the slot exactly reproducible from the deposited velocity at the deposited
# positions: the closing deposit wrote it, it did not merely mark it.

using Test, Random
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: velocity_at_particles

build() = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                     particles = ParticleTracking(number_of_particles = 8), rng = MersenneTwister(1))

@testset "the run's own iteration never marks an unwritten sample" begin
  sim = build()
  for _ in 1:3
    advance!(sim; dt = 0.01)
    v = copy(Array(velocity_at_particles(sim.cache)))
    @test all(isfinite, v)
    # Re-deriving the sample by hand from the deposited velocity at the same positions must
    # reproduce the slot exactly: the closing deposit wrote it, it did not merely mark it.
    deposit!(sim.cache, sim.tracers, velocity_physical(sim.cache))
    @test Array(velocity_at_particles(sim.cache)) == v
  end
end
