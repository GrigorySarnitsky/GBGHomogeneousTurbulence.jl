# Witness: `velocity_at_particles(cache)` must refuse a stale read on EITHER of its two epochs.
#
# The slot is the one cached observable that depends on two dynamical factors — the resolved fields
# (the velocity that was interpolated) and the tracer positions (where it was interpolated). Its
# docstring promises it is "current only when both counters match its own", and `Cache.jl:264-268`
# encodes that as a conjunction. This file asserts the promise in both directions independently, so
# a check that tested only one counter, used `||` for `&&`, or compared the wrong counter would fail
# here rather than pass the suite silently.

using Test, Random, GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: advance_fields_epoch!, advance_particles_epoch!

build() = Simulation(grid_points_per_axis = 8, viscosity = 0.05,
                     particles = ParticleTracking(number_of_particles = 4),
                     rng = MersenneTwister(1))

@testset "velocity_at_particles refuses a stale read on either epoch" begin
  # (0) The control: after a completed iteration both epochs match and the read is served.
  sim = build()
  advance!(sim; dt = 0.01)
  @test size(velocity_at_particles(sim.cache)) == (4, 3)

  # (1) A fields-only advance. The positions are untouched, so the particles epoch still matches;
  #     only `velocity_at_particles_fields_epoch` falls behind, and the read must still throw.
  advance_fields_epoch!(sim.cache)
  @test sim.cache.velocity_at_particles_particles_epoch == sim.cache.particles_epoch   # the other counter agrees
  @test_throws ErrorException velocity_at_particles(sim.cache)

  # (2) A particles-only advance, the run's own tracer-advance verb. The fields are untouched, so the
  #     fields epoch still matches; only `velocity_at_particles_particles_epoch` falls behind, and the
  #     read must still throw.
  sim = build()
  advance!(sim; dt = 0.01)
  advance_particles_epoch!(sim.cache)
  @test sim.cache.velocity_at_particles_fields_epoch == sim.cache.fields_epoch
  @test_throws ErrorException velocity_at_particles(sim.cache)

  # (3) The particle deposit restores the read in ONE act: `deposit!(cache, tracers, u)` writes and
  #     stamps BOTH epochs together (decision 71), so nothing between the push and the deposit can
  #     serve the slot, and nothing after the deposit refuses it.
  sim = build()
  advance!(sim; dt = 0.01)
  advance_particles_epoch!(sim.cache)
  @test_throws ErrorException velocity_at_particles(sim.cache)
  deposit!(sim.cache, sim.tracers, velocity_physical(sim.cache))
  @test size(velocity_at_particles(sim.cache)) == (4, 3)
end
