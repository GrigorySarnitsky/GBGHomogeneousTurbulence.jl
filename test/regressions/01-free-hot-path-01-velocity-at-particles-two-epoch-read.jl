# Witness 01, lane "free-hot-path".
#
# The cache's velocity-at-particles slot is the one observable that is a function of TWO things — the
# resolved state (the velocity that was interpolated) and the tracer positions (where it was
# interpolated). The cache keeps two counters for exactly that reason: the particle `deposit!`
# (its stamping half, `deposit_velocity_at_particles!`) stamps both, `check_deposits` compares both, the
# accessor's own docstring says the sample "is current only when both counters match its own", and
# `docs/src/observables_cache.md` §3.2 says the read is checked "against both epochs".
#
# `velocity_at_particles` (src/Cache.jl:264) compares only `velocity_at_particles_fields_epoch == fields_epoch`.
# `particles_modified!` — the announced-reposition verb — advances `particles_epoch` alone, so the
# exact mutation the two-counter design exists to catch is invisible to the read.
#
# The consequence is on the hot path: `advance!` (src/SimulationRun.jl:429) opens with
# `sim.tracers === nothing || velocity_at_particles(sim.cache)`, commented "the epoch is verified
# here". That read is the run layer's only freshness gate on the Heun v₁, so after an announced
# reposition the advance integrates the trajectory on velocities measured at abandoned positions.
#
# This file asserts the CORRECT behaviour: the read refuses a sample whose positions have moved on,
# and the run layer's opening guard fires.

using Test
using GBGPeriodicFields: point_positions
using Random
using GBGHomogeneousTurbulence


@testset "velocity_at_particles is checked against BOTH epochs, so advance!'s guard fires after a reposition" begin
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                   number_of_particles = 8, rng = MersenneTwister(1))
  advance!(sim)

  # Precondition — a closed iteration leaves the slot current on both counters and the read serves.
  @test sim.cache.velocity_at_particles_fields_epoch == sim.cache.fields_epoch
  @test sim.cache.velocity_at_particles_particles_epoch == sim.cache.particles_epoch
  v0 = copy(velocity_at_particles(sim.cache))
  @test size(v0) == (8, 3)

  # An out-of-band reposition, announced through the sanctioned verb. The state is untouched; the
  # positions the sample belongs to are abandoned.
  point_positions(sim.tracers.positions) .= 0.5 .* point_positions(sim.tracers.positions)
  particles_modified!(sim)
  @test sim.cache.velocity_at_particles_fields_epoch == sim.cache.fields_epoch          # fields did not move
  @test sim.cache.velocity_at_particles_particles_epoch != sim.cache.particles_epoch    # positions did

  # (1) The cache's central invariant: a checked read serves a current value or throws.
  @test_throws ErrorException velocity_at_particles(sim.cache)

  # (2) The cache already agrees the slot is not current — on the identical state, its own
  #     completeness check rejects it. A serving read above is the cache contradicting itself.
  @test_throws ErrorException GBGHomogeneousTurbulence.Cache.check_deposits(sim.cache)

  # (3) The hot-path consequence: `advance!`'s opening guard is that same read, so the advance must
  #     refuse to integrate the trajectory on a v₁ measured at the abandoned positions.
  @test_throws ErrorException advance!(sim)
end
