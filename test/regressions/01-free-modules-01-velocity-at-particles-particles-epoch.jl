# Witness: the velocity-at-particles slot is the one cached observable that depends on TWO counters —
# the fields epoch of the interpolated velocity and the particles epoch of the positions it was
# interpolated at.  `deposit_velocity_at_particles!` stamps both, and `check_deposits`
# compares both.  A tracer push advances `particles_epoch` and leaves `fields_epoch` alone, so a read
# comparing only the fields epoch would serve the sample taken at the positions the push has left as
# though it were current, instead of throwing.
#
# The contract under test is the one the accessor's own docstring states:
#   "the sample depends on the state AND the positions, so it is current only when both counters
#    match its own."
#
# Consequence: `advance!` makes that read the run layer's only freshness gate
# on v₁, so the trajectory advance would integrate stale velocities and the closing particle `deposit!`
# would stamp the result as a fresh observable.

using Test
using Random
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: advance_particles_epoch!

@testset "velocity_at_particles(cache) throws after a push (both epochs checked)" begin
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                   particles = ParticleTracking(number_of_particles = 8), rng = MersenneTwister(3))
  advance!(sim)

  # Baseline: after a plain advance! the slot is current on BOTH counters, so the read serves.
  @test sim.cache.velocity_at_particles_fields_epoch == sim.cache.fields_epoch
  @test sim.cache.velocity_at_particles_particles_epoch == sim.cache.particles_epoch
  @test size(velocity_at_particles(sim.cache)) == (8, 3)

  # A push's epoch advance with no closing particle deposit: the positions the sample belongs to are left behind.
  advance_particles_epoch!(sim.cache)
  @test sim.cache.velocity_at_particles_fields_epoch == sim.cache.fields_epoch        # fields untouched
  @test sim.cache.velocity_at_particles_particles_epoch != sim.cache.particles_epoch  # positions moved on

  # The cache's central invariant: a read finds a current value or throws.
  @test_throws ErrorException velocity_at_particles(sim.cache)

  # The cache's own completeness check agrees the slot is not current on this identical state —
  # so a passing read above is the cache contradicting itself.
  @test_throws ErrorException GBGHomogeneousTurbulence.Cache.check_deposits(sim.cache)
end
