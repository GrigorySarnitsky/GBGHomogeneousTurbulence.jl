# Witness: `advance!`'s opening guard — `sim.tracers === nothing || velocity_at_particles(sim.cache)`
# (src/SimulationRun.jl:456) — must actually refuse an iteration whose trajectory v₁ is not the
# sample the previous closing deposit deposited, and must let the iteration through once the
# sanctioned announcement/completion protocol has restored it.
#
# The claim under test was that nothing exercises this line. This file exercises it directly: a
# hand-written reposition of the tracer positions, announced with `particles_modified!` and NOT yet
# completed, must make the next `advance!` throw; completing the protocol
# (the particle `deposit!`) must make the next `advance!` succeed. Delete
# the guard line and part (1) fails; check the wrong epoch there and part (1) fails too.

using Test, Random, GBGIsotropicTurbulence

build() = Simulation(grid_points_per_axis = 8, viscosity = 0.05, number_of_particles = 4,
                     rng = MersenneTwister(1))

@testset "advance!'s opening guard refuses an un-completed tracer reposition" begin

  # (0) Control: a run in a valid state advances.
  sim = build()
  advance!(sim; dt = 0.01)
  @test current_step(sim) == 1
  advance!(sim; dt = 0.01)
  @test current_step(sim) == 2

  # (1) A hand-written reposition, announced but not completed: the deposited sample belongs to the
  #     abandoned positions, so the opening guard must refuse the step — and must not advance the
  #     clock on the way out.
  sim = build()
  advance!(sim; dt = 0.01)
  L = sim.domain.grid.domain_size[1]
  X = particle_positions(sim.tracers)
  X .= mod.(X .+ 0.3, L)
  particles_modified!(sim)
  step_before = current_step(sim)
  @test_throws ErrorException advance!(sim; dt = 0.01)
  @test current_step(sim) == step_before          # the refused iteration left the clock alone

  # (2) The sanctioned completion restores the read, and the very next `advance!` succeeds.
  deposit!(sim.cache, sim.tracers, velocity_physical(sim.cache))
  @test size(velocity_at_particles(sim.cache)) == (4, 3)
  advance!(sim; dt = 0.01)
  @test current_step(sim) == step_before + 1

  # (3) The guard is scoped to tracer-carrying runs: a tracer-free run has no sample slot at all and
  #     must advance without the read being attempted.
  plain = Simulation(grid_points_per_axis = 8, viscosity = 0.05, rng = MersenneTwister(1))
  @test plain.tracers === nothing
  advance!(plain; dt = 0.01)
  @test current_step(plain) == 1
end
