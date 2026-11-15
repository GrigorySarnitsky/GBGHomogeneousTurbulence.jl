# Witness: the samples of the velocity at the particles answer to the particles epoch — the version
# of the positions they were taken at. A tracer push advances `particles_epoch` and leaves
# `fields_epoch` alone, so a read comparing only the fields epoch would serve the sample taken at the
# positions the push has left as though it were current, instead of throwing.
#
# The contract under test is the one the accessor's own docstring states: the samples "are current
# exactly while the positions have not moved since the newest was taken".
#
# Consequence of the defect: the trajectory advance would integrate stale velocities, and the closing
# particle `deposit!` would stamp the result as a fresh observable.

using Test
using Random
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: advance_particles_epoch!
using GBGPeriodicFields: npoints

@testset "velocity_at_particles_trail(cache) throws after a push" begin
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                   particles = ParticleTracking(number_of_particles = 8), rng = MersenneTwister(3))
  advance!(sim)

  # Baseline: after a plain advance! the newest sample is current, so the read serves.
  @test sim.cache.velocity_at_particles_epoch == sim.cache.particles_epoch
  @test npoints(velocity_at_particles_trail(sim.cache)[0].value) == 8

  # A push's epoch advance with no closing particle deposit: the positions the sample belongs to are left behind.
  fields_before = sim.cache.fields_epoch
  advance_particles_epoch!(sim.cache)
  @test sim.cache.fields_epoch == fields_before                               # fields untouched
  @test sim.cache.velocity_at_particles_epoch != sim.cache.particles_epoch    # positions moved on

  # The cache's central invariant: a read finds a current value or throws.
  @test_throws ErrorException velocity_at_particles_trail(sim.cache)

  # The cache's own completeness check agrees the sample is not current on this identical state —
  # so a passing read above is the cache contradicting itself.
  @test_throws ErrorException GBGHomogeneousTurbulence.Cache.check_deposits(sim.cache)
end
