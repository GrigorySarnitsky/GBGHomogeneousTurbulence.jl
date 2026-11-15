# Witness 01, lane "free-hot-path".
#
# The cache's samples of the velocity at the particles depend on where the tracers were when each was
# taken. A tracer push advances `particles_epoch`, so until the closing particle deposit the newest
# sample belongs to positions the tracers have left. The defect this witness was written against was
# a read that compared the fields epoch alone and so served that sample as current; the consequence
# was on the hot path, the particle step integrating from a velocity measured somewhere else.
#
# This file asserts the CORRECT behaviour: the read refuses a sample whose positions have moved on,
# the cache's completeness check agrees, and the next particle step refuses to start from it.
# (Since 2026-11-15 the read answers to the particles epoch alone — a sample is u(t, X(t)), which a
# field step does not date — and the particle step makes the check itself, where `advance!` once
# opened with a read made only for it.)

using Test
using Random
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: advance_particles_epoch!
using GBGPeriodicFields: npoints


@testset "the trail is checked against the particles epoch, so the particle step refuses after a push" begin
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                   particles = ParticleTracking(number_of_particles = 8), rng = MersenneTwister(1))
  advance!(sim)

  # Precondition — a closed iteration leaves the newest sample current and the read serves.
  @test sim.cache.velocity_at_particles_epoch == sim.cache.particles_epoch == sim.cache.fields_epoch
  @test npoints(velocity_at_particles_trail(sim.cache)[0].value) == 8

  # A push's epoch advance with no closing particle deposit. The state is untouched; the positions
  # the sample belongs to are left behind.
  advance_particles_epoch!(sim.cache)
  @test sim.cache.velocity_at_particles_epoch != sim.cache.particles_epoch    # positions moved on

  # (1) The cache's central invariant: a checked read serves a current value or throws.
  @test_throws ErrorException velocity_at_particles_trail(sim.cache)

  # (2) The cache already agrees the sample is not current — on the identical state, its own
  #     completeness check rejects it. A serving read above is the cache contradicting itself.
  @test_throws ErrorException GBGHomogeneousTurbulence.Cache.check_deposits(sim.cache)

  # (3) The hot-path consequence: the next particle step must refuse to integrate the trajectory
  #     from a velocity measured at the positions left behind.
  @test_throws ErrorException advance!(sim)
end
