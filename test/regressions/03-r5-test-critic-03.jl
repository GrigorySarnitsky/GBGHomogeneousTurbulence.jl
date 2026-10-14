# Witness for the claim: "`velocity_at_particles(cache)`'s two-epoch AND check is never driven to a
# stale state by either epoch alone, so a regression flipping `&&` to `||`, or dropping either half,
# would pass the whole suite."
#
# The correct behaviour — the one this file asserts — is the contract the read's own docstring
# states: the sample is current only when BOTH counters match its own, so a mutation of EITHER
# factor alone must make the read throw. The two halves are exercised independently:
#
#   (1) `fields_modified!(cache)` alone — the tracer positions are untouched, so
#       `velocity_at_particles_particles_epoch == particles_epoch` still holds and only the fields half can fire;
#   (2) `particles_modified!(cache)` alone — the fields are untouched, so
#       `velocity_at_particles_fields_epoch == fields_epoch` still holds and only the particles half can fire.
#
# Each case pins the *other* counter as still-matching before asserting the throw, which is what
# makes the case discriminating: under `||` (or a dropped half) the surviving comparison would be
# satisfied and the read would be served instead of throwing.

using Test, Random
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: velocity_at_particles, fields_modified!, particles_modified!


build() = Simulation(grid_points_per_axis = 8, viscosity = 0.05,
                     particles = ParticleTracking(number_of_particles = 4),
                     rng = MersenneTwister(20260821))


@testset "each epoch alone drives the velocity-at-particles read stale" begin

  # ————— the control: a completed iteration leaves both counters current and the read served —————
  sim = build()
  advance!(sim; dt = 0.01)
  @test sim.cache.velocity_at_particles_fields_epoch == sim.cache.fields_epoch
  @test sim.cache.velocity_at_particles_particles_epoch == sim.cache.particles_epoch
  @test size(velocity_at_particles(sim.cache)) == (4, 3)

  # ————— (1) the fields half alone —————
  sim = build()
  advance!(sim; dt = 0.01)
  fields_modified!(sim.cache)
  # the particles half is still satisfied, so only the fields comparison can raise the throw
  @test sim.cache.velocity_at_particles_particles_epoch == sim.cache.particles_epoch
  @test sim.cache.velocity_at_particles_fields_epoch != sim.cache.fields_epoch
  @test_throws ErrorException velocity_at_particles(sim.cache)

  # ————— (2) the particles half alone —————
  sim = build()
  advance!(sim; dt = 0.01)
  particles_modified!(sim.cache)
  # the fields half is still satisfied, so only the particles comparison can raise the throw
  @test sim.cache.velocity_at_particles_fields_epoch == sim.cache.fields_epoch
  @test sim.cache.velocity_at_particles_particles_epoch != sim.cache.particles_epoch
  @test_throws ErrorException velocity_at_particles(sim.cache)

  # ————— and the sanctioned completion restores the read in the particles direction —————
  deposit!(sim.cache, sim.tracers, velocity_physical(sim.cache))
  @test size(velocity_at_particles(sim.cache)) == (4, 3)
end
