# Witness (round 4, state-machine lane, 02): the sanctioned reposition protocol yields a genuine
# post-reposition sample, and an un-completed announcement is refused.
#
# The candidate once claimed the mark half of the old two-call protocol (`deposit_sample!`) was
# defective because, called alone, it stamped whatever the velocity-at-particles array happened to
# hold as the current-epoch observable. Decision 71 removed the reachable form of that hazard
# outright: the particle `deposit!` writes and stamps in one act, so no public call can mark values
# it did not just produce. What must hold — and what this file asserts — is the reachable contract:
#   (a) an announced reposition alone leaves the sample unreadable (the read throws);
#   (b) the single particle `deposit!` restores the read with values that genuinely belong to the
#       NEW positions, not the pre-reposition values;
#   (c) the run's own iteration leaves the slot exactly reproducible from the deposited velocity at
#       the deposited positions — the closing deposit wrote it, it did not merely mark it.

using Test, Random
using GBGPeriodicFields: point_positions
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: particles_modified!, velocity_at_particles

build() = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                     number_of_particles = 8, rng = MersenneTwister(1))

@testset "the reposition protocol serves a genuine post-reposition sample" begin
  sim = build()
  advance!(sim; dt = 0.01)
  before = copy(Array(velocity_at_particles(sim.cache)))

  L = sim.domain.grid.domain_size[1]
  point_positions(sim.tracers.positions) .= mod.(point_positions(sim.tracers.positions) .+ 3.0, L)

  # (a) The announcement alone: the sample belongs to the abandoned positions, so the read is refused.
  particles_modified!(sim.cache)
  @test_throws ErrorException velocity_at_particles(sim.cache)

  # (b) The single particle deposit restores the read with values of the NEW positions.
  deposit!(sim.cache, sim.tracers, velocity_physical(sim.cache))
  after = copy(Array(velocity_at_particles(sim.cache)))
  @test size(after) == (8, 3)
  @test after != before
  @test all(isfinite, after)
end

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
