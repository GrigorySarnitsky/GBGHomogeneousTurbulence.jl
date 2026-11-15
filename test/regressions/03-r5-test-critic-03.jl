# Witness for the claim: "the checks on the cache's two counters are never driven to a failing state
# by either counter alone, so a regression comparing the wrong counter, or dropping one where both
# are meant, would pass the whole suite."
#
# The correct behaviour — the one this file asserts — is that each check names the counters it
# needs. The read of the trail of the velocity at the particles answers to the PARTICLES counter
# alone, because a sample is u(t, X(t)) and only a move of the positions dates it. The particle step
# needs the FIELDS exactly one step ahead of the positions. Each is exercised by moving one counter
# alone:
#
#   (1) `advance_fields_epoch!(cache)` alone — the positions are untouched, so the read is still
#       served, while the particle step now finds the fields ahead and, without a field deposit, no
#       current velocity to interpolate;
#   (2) `advance_particles_epoch!(cache)` alone — the fields are untouched, and the read throws.
#
# Each case pins the *other* counter as unmoved before asserting, which is what makes the case
# discriminating. (Before 2026-11-15 the read compared both counters, and this witness pinned that.)

using Test, Random
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: velocity_at_particles_trail, advance_fields_epoch!, advance_particles_epoch!
using GBGPeriodicFields: npoints


build() = Simulation(grid_points_per_axis = 8, viscosity = 0.05,
                     particles = ParticleTracking(number_of_particles = 4),
                     rng = MersenneTwister(20260821))


@testset "each counter alone moves exactly the checks that name it" begin

  # ————— the control: a completed iteration leaves the counters equal and the read served —————
  sim = build()
  advance!(sim; dt = 0.01)
  @test sim.cache.velocity_at_particles_epoch == sim.cache.particles_epoch == sim.cache.fields_epoch
  @test npoints(velocity_at_particles_trail(sim.cache)[0].value) == 4

  # ————— (1) the fields counter alone —————
  sim = build()
  advance!(sim; dt = 0.01)
  particles_before = sim.cache.particles_epoch
  advance_fields_epoch!(sim.cache)
  @test sim.cache.particles_epoch == particles_before            # the positions' counter did not move
  @test sim.cache.fields_epoch == sim.cache.particles_epoch + 1
  @test npoints(velocity_at_particles_trail(sim.cache)[0].value) == 4          # the read does not name the fields
  # The particle step does: with the fields one step ahead it runs, once their velocity is deposited…
  @test_throws ErrorException advect!(sim.particle_integration_scheme, sim.tracers, sim.domain, sim.cache, 0.01)
  deposit!(sim.cache, sim.state, sim.domain, sim.buffers)
  @test advect!(sim.particle_integration_scheme, sim.tracers, sim.domain, sim.cache, 0.01) === sim.tracers
  # …and with the fields two steps ahead it refuses.
  sim = build()
  advance!(sim; dt = 0.01)
  advance_fields_epoch!(sim.cache); advance_fields_epoch!(sim.cache)
  deposit!(sim.cache, sim.state, sim.domain, sim.buffers)
  @test_throws ErrorException advect!(sim.particle_integration_scheme, sim.tracers, sim.domain, sim.cache, 0.01)
  # With the fields not ahead at all it refuses as well.
  sim = build()
  advance!(sim; dt = 0.01)
  @test_throws ErrorException advect!(sim.particle_integration_scheme, sim.tracers, sim.domain, sim.cache, 0.01)

  # ————— (2) the particles counter alone —————
  sim = build()
  advance!(sim; dt = 0.01)
  fields_before = sim.cache.fields_epoch
  advance_particles_epoch!(sim.cache)
  @test sim.cache.fields_epoch == fields_before                  # the fields' counter did not move
  @test sim.cache.velocity_at_particles_epoch != sim.cache.particles_epoch
  @test_throws ErrorException velocity_at_particles_trail(sim.cache)
end
