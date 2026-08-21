# Witness: `particle_velocities(cache)` must refuse a stale read on EITHER of its two epochs.
#
# The slot is the one cached observable that depends on two dynamical factors — the resolved fields
# (the velocity that was interpolated) and the tracer positions (where it was interpolated). Its
# docstring promises it is "current only when both counters match its own", and `Cache.jl:264-268`
# encodes that as a conjunction. This file asserts the promise in both directions independently, so
# a check that tested only one counter, used `||` for `&&`, or compared the wrong counter would fail
# here rather than pass the suite silently.

using Test, Random, GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Cache: advance_particles_epoch!

build() = Simulation(grid_points_per_axis = 8, viscosity = 0.05, number_of_particles = 4,
                     rng = MersenneTwister(1))

@testset "particle_velocities refuses a stale read on either epoch" begin
  # (0) The control: after a completed iteration both epochs match and the read is served.
  sim = build()
  advance!(sim; dt = 0.01)
  @test size(particle_velocities(sim.cache)) == (4, 3)

  # (1) A fields-only out-of-band mutation. The positions are untouched, so the particles epoch
  #     still matches; only `sample_fields_epoch` falls behind, and the read must still throw.
  fields_modified!(sim.cache)
  @test sim.cache.sample_particles_epoch == sim.cache.particles_epoch   # the other counter agrees
  @test_throws ErrorException particle_velocities(sim.cache)

  # (2) A particles-only mutation. The fields are untouched, so the fields epoch still matches;
  #     only `sample_particles_epoch` falls behind, and the read must still throw.
  sim = build()
  advance!(sim; dt = 0.01)
  particles_modified!(sim.cache)                       # the documented reposition announcement
  @test sim.cache.sample_fields_epoch == sim.cache.fields_epoch         # the other counter agrees
  @test_throws ErrorException particle_velocities(sim.cache)

  # (2b) The same direction through the run's own tracer-advance verb, which bumps the particles
  #      epoch without discarding the sample history.
  sim = build()
  advance!(sim; dt = 0.01)
  advance_particles_epoch!(sim.cache)
  @test sim.cache.sample_fields_epoch == sim.cache.fields_epoch
  @test_throws ErrorException particle_velocities(sim.cache)

  # (3) Recording the values without recording the epochs must NOT make the slot readable: the
  #     write alone leaves it stale, as `deposit_sample!`'s docstring states.
  sim = build()
  advance!(sim; dt = 0.01)
  particles_modified!(sim.cache)
  record_particle_velocities!(sim.tracers, velocity_physical(sim.cache))
  @test_throws ErrorException particle_velocities(sim.cache)
  deposit_sample!(sim.cache)                            # …and only this restores the read
  @test size(particle_velocities(sim.cache)) == (4, 3)
end
