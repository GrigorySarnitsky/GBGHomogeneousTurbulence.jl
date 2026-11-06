# Witness 01, lane "free-hot-path".
#
# The cache's velocity-at-particles slot is the one observable that is a function of TWO things — the
# resolved state (the velocity that was interpolated) and the tracer positions (where it was
# interpolated). The cache keeps two counters for exactly that reason: the particle `deposit!`
# (its stamping half, `deposit_velocity_at_particles!`) stamps both, `check_deposits` compares both, and the
# accessor's own docstring says the sample "is current only when both counters match its own".
#
# A tracer push advances `particles_epoch` alone, so a read comparing only the fields epoch would serve
# the sample taken at the positions the push has left. The consequence would be on the hot path:
# `advance!` opens with `sim.tracers === nothing || velocity_at_particles(sim.cache)`, the run layer's
# only freshness gate on the Heun v₁.
#
# This file asserts the CORRECT behaviour: the read refuses a sample whose positions have moved on,
# and the run layer's opening guard fires.

using Test
using Random
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: advance_particles_epoch!


@testset "velocity_at_particles is checked against BOTH epochs, so advance!'s guard fires after a push" begin
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                   particles = ParticleTracking(number_of_particles = 8), rng = MersenneTwister(1))
  advance!(sim)

  # Precondition — a closed iteration leaves the slot current on both counters and the read serves.
  @test sim.cache.velocity_at_particles_fields_epoch == sim.cache.fields_epoch
  @test sim.cache.velocity_at_particles_particles_epoch == sim.cache.particles_epoch
  v0 = copy(velocity_at_particles(sim.cache))
  @test size(v0) == (8, 3)

  # A push's epoch advance with no closing particle deposit. The state is untouched; the positions
  # the sample belongs to are left behind.
  advance_particles_epoch!(sim.cache)
  @test sim.cache.velocity_at_particles_fields_epoch == sim.cache.fields_epoch          # fields did not move
  @test sim.cache.velocity_at_particles_particles_epoch != sim.cache.particles_epoch    # positions did

  # (1) The cache's central invariant: a checked read serves a current value or throws.
  @test_throws ErrorException velocity_at_particles(sim.cache)

  # (2) The cache already agrees the slot is not current — on the identical state, its own
  #     completeness check rejects it. A serving read above is the cache contradicting itself.
  @test_throws ErrorException GBGHomogeneousTurbulence.Cache.check_deposits(sim.cache)

  # (3) The hot-path consequence: `advance!`'s opening guard is that same read, so the advance must
  #     refuse to integrate the trajectory on a v₁ measured at the positions left behind.
  @test_throws ErrorException advance!(sim)
end
