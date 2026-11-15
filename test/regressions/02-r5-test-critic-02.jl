# Witness: `advance!`'s opening guard — `sim.tracers === nothing || velocity_at_particles_trail(sim.cache)`
# — must actually refuse an iteration whose particle step would start from a velocity sample that
# is not the one the previous closing deposit left, must refuse it BEFORE anything has moved, and
# must let the run on once the iteration left open has been closed.
#
# The claim under test was that nothing exercises this line. This file exercises it directly: a
# push's epoch advance NOT yet closed with the particle `deposit!` must make the next `advance!`
# throw, with the clock and the state untouched. Delete the guard line and part (1) fails on the
# state — the particle step still refuses, but only after the field step has run.

using Test, Random, GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: advance_particles_epoch!, advance_fields_epoch!
using GBGPeriodicFields: field_data, npoints

build() = Simulation(grid_points_per_axis = 8, viscosity = 0.05,
                     particles = ParticleTracking(number_of_particles = 4),
                     rng = MersenneTwister(1))

@testset "advance!'s opening guard refuses an unclosed tracer push" begin

  # (0) Control: a run in a valid state advances.
  sim = build()
  advance!(sim; dt = 0.01)
  @test current_step(sim) == 1
  advance!(sim; dt = 0.01)
  @test current_step(sim) == 2

  # (1) A push's epoch advance with no closing deposit: the deposited sample belongs to the positions
  #     left behind, so the opening guard must refuse the step — and must leave the clock and the
  #     fields exactly as they were on the way out.
  sim = build()
  advance!(sim; dt = 0.01)
  advance_particles_epoch!(sim.cache)
  step_before = current_step(sim)
  state_before = copy(field_data(sim.state.velocity_spectral))
  @test_throws ErrorException advance!(sim; dt = 0.01)
  @test current_step(sim) == step_before          # the refused iteration left the clock alone…
  @test field_data(sim.state.velocity_spectral) == state_before      # …and the fields

  # (2) Closing by hand the iteration the push belongs to — the fields' step it lacks, then both
  #     deposits — restores the read, and the very next `advance!` succeeds.
  @test_throws ErrorException deposit!(sim.cache, sim.tracers, current_time(sim) + 0.01)   # positions ahead of the fields
  advance_fields_epoch!(sim.cache)
  deposit!(sim.cache, sim.state, sim.domain, sim.buffers)
  deposit!(sim.cache, sim.tracers, current_time(sim) + 0.005)
  @test npoints(velocity_at_particles_trail(sim.cache)[0].value) == 4
  advance!(sim; dt = 0.01)
  @test current_step(sim) == step_before + 1

  # (3) The guard is scoped to tracer-carrying runs: a tracer-free run has no sample slot at all and
  #     must advance without the read being attempted.
  plain = Simulation(grid_points_per_axis = 8, viscosity = 0.05, rng = MersenneTwister(1))
  @test plain.tracers === nothing
  advance!(plain; dt = 0.01)
  @test current_step(plain) == 1
end
