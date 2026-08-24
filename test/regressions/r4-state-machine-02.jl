# Witness (round 4, state-machine lane, 02): the sanctioned reposition protocol yields a genuine
# post-reposition sample, and an incomplete protocol is refused.
#
# The candidate claimed `deposit_sample!` is defective because, called alone, it stamps whatever the
# particle-velocities array happens to hold as the current-epoch observable. That is the documented
# contract of the call, not a defect: `deposit_sample!` is the MARK half of a two-call protocol whose
# WRITE half is `record_particle_velocities!` ("the cache never fills it, and cannot know when its
# contents became current" — its own docstring), exactly as `deposit_velocity!` / `deposit_vorticity!`
# / `deposit_scalar!` / `deposit_max_speed!` mark slots their producers have just written. Every
# in-package call site pairs the two unconditionally (SimulationRun.jl:335-336, 361-362, 466-467).
#
# What must hold — and what this file asserts — is the reachable contract:
#   (a) an announced reposition alone leaves the sample unreadable (the read throws);
#   (b) the write alone does not make it readable either;
#   (c) the complete protocol (move → announce → record → deposit) serves a sample that genuinely
#       belongs to the NEW positions, not the pre-reposition values;
#   (d) the run's own iteration keeps the pairing, so a plain `advance!` never leaves a marked-but-
#       unwritten sample behind.

using Test, Random
using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Cache: particles_modified!, particle_velocities, deposit_sample!
using GBGIsotropicTurbulence.Particles: record_particle_velocities!

build() = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                     number_of_particles = 8, rng = MersenneTwister(1))

@testset "the reposition protocol serves a genuine post-reposition sample" begin
  sim = build()
  advance!(sim; dt = 0.01)
  before = copy(Array(particle_velocities(sim.cache)))

  L = sim.domain.grid.domain_size[1]
  particle_positions(sim.tracers) .= mod.(particle_positions(sim.tracers) .+ 3.0, L)

  # (a) The announcement alone: the sample belongs to the abandoned positions, so the read is refused.
  particles_modified!(sim.cache)
  @test_throws ErrorException particle_velocities(sim.cache)

  # (b) The write alone still leaves the slot stale — the epochs have not been recorded.
  record_particle_velocities!(sim.tracers, velocity_physical(sim.cache))
  @test_throws ErrorException particle_velocities(sim.cache)

  # (c) The completed protocol serves values measured at the NEW positions.
  deposit_sample!(sim.cache)
  after = copy(Array(particle_velocities(sim.cache)))
  @test size(after) == (8, 3)
  @test after != before
  @test all(isfinite, after)
end

@testset "the run's own iteration never marks an unwritten sample" begin
  sim = build()
  for _ in 1:3
    advance!(sim; dt = 0.01)
    v = copy(Array(particle_velocities(sim.cache)))
    @test all(isfinite, v)
    # Re-deriving the sample by hand from the deposited velocity at the same positions must
    # reproduce the slot exactly: the closing deposit wrote it, it did not merely mark it.
    record_particle_velocities!(sim.tracers, velocity_physical(sim.cache))
    deposit_sample!(sim.cache)
    @test Array(particle_velocities(sim.cache)) == v
  end
end
