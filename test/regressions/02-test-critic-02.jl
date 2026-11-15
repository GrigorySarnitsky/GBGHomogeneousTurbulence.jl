# Witness: each of the cache's two counters is checked where it belongs, and nowhere else.
#
# The trail of the velocity at the particles depends on two dynamical factors — the resolved fields
# (the velocity that was interpolated) and the tracer positions (where it was interpolated). A
# sample is u(t, X(t)), taken when the two were at one time, and it belongs to the particles' time
# from then on. So:
#
#   - the READ answers to the particles counter alone: a move of the positions dates the samples, a
#     step of the fields does not;
#   - the particle DEPOSIT needs the two counters equal, which is what "one time" means;
#   - the iteration's completeness check needs both.
#
# This file asserts each of these in both directions, so a check that tested the wrong counter,
# both where one is meant, or one where both are meant, would fail here rather than pass the suite
# silently. (Before 2026-11-15 the read compared both counters, and this witness pinned that.)

using Test, Random, GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: advance_fields_epoch!, advance_particles_epoch!, check_deposits
using GBGPeriodicFields: npoints

build() = Simulation(grid_points_per_axis = 8, viscosity = 0.05,
                     particles = ParticleTracking(number_of_particles = 4),
                     rng = MersenneTwister(1))

@testset "each counter is checked where it belongs" begin
  # (0) The control: after a completed iteration the counters agree and the read is served.
  sim = build()
  advance!(sim; dt = 0.01)
  @test npoints(velocity_at_particles_trail(sim.cache)[0].value) == 4
  @test check_deposits(sim.cache) === sim.cache

  # (1) A fields-only advance. The positions are untouched, so the samples are still the velocity at
  #     the tracers' positions and time: the read is served. The iteration is nonetheless open, which
  #     the completeness check says, and a second sample at these positions is refused.
  advance_fields_epoch!(sim.cache)
  @test sim.cache.velocity_at_particles_epoch == sim.cache.particles_epoch
  @test npoints(velocity_at_particles_trail(sim.cache)[0].value) == 4
  @test_throws ErrorException check_deposits(sim.cache)
  @test_throws ErrorException deposit!(sim.cache, sim.tracers, current_time(sim) + 0.01)

  # (2) A particles-only advance, the run's own tracer-advance verb. The fields are untouched; the
  #     newest sample now belongs to positions the tracers have left, and the read must throw.
  sim = build()
  advance!(sim; dt = 0.01)
  advance_particles_epoch!(sim.cache)
  @test_throws ErrorException velocity_at_particles_trail(sim.cache)
  @test_throws ErrorException check_deposits(sim.cache)
  # …and the deposit refuses too: the positions are now AHEAD of the fields, another time again.
  @test_throws ErrorException deposit!(sim.cache, sim.tracers, current_time(sim) + 0.01)

  # (3) Both advanced, as an iteration advances them: the deposit is accepted, and restores the read
  #     in ONE act (decision 71) — nothing between the push and the deposit can serve the trail, and
  #     nothing after the deposit refuses it.
  sim = build()
  advance!(sim; dt = 0.01)
  advance_fields_epoch!(sim.cache)
  deposit!(sim.cache, sim.state, sim.domain, sim.buffers)
  advance_particles_epoch!(sim.cache)
  @test_throws ErrorException velocity_at_particles_trail(sim.cache)
  deposit!(sim.cache, sim.tracers, current_time(sim) + 0.01)
  @test npoints(velocity_at_particles_trail(sim.cache)[0].value) == 4
  @test velocity_at_particles_trail(sim.cache)[0].time == current_time(sim) + 0.01
  @test check_deposits(sim.cache) === sim.cache
end
