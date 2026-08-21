# Witness: the adaptive CFL rule has no upper bound, so an UNFORCED (decaying) run enters a
# positive-feedback runaway — the resolved turbulence decays, `max_speed` shrinks, Δt = cfl·Δx/u_max
# grows, the exact integrating factor exp(-2ν|κ|²Δt) then annihilates what is left in a single step,
# `max_speed` falls to the spurious round-off mean and STOPS decreasing, and Δt latches at ~1e15.
# From there the state is bit-frozen while the clock adds ~1e15 per step, and nothing throws:
# `advance!` guards only `isfinite(max_speed)`, and 2e-16 is finite.
#
# The correct behaviour asserted here: an adaptive step must stay bounded by a physical time scale of
# the problem, and a run that reports success must actually be integrating something.

using Test, Random, GBGIsotropicTurbulence
const IT = GBGIsotropicTurbulence

@testset "an unforced decaying run keeps a bounded timestep and a meaningful clock" begin
  ν = 0.02
  sim = Simulation(grid_points_per_axis = 16, viscosity = ν,
                   velocity_forcing = NoForcing(), rng = MersenneTwister(1))

  # The viscous time of the largest resolved eddy on a 2π box: τ_ν = 1/(2ν κ_min²) = 1/(2ν) = 25.
  # A step longer than this spans the entire life of the flow — the integrating factor wipes the
  # whole resolved spectrum inside one step — so it is not an integration step in any useful sense.
  τ_ν = 1 / (2ν)

  largest_step = 0.0
  for _ in 1:200
    largest_step = max(largest_step, IT.SimulationRun.cfl_timestep(sim))
    advance!(sim)
  end

  # (1) The adaptive rule must never hand back a step orders of magnitude past the physical time
  #     scale. 1e3 is a deliberately generous 40·τ_ν, so this fails only on a genuine runaway.
  @test largest_step < 1e3

  # (2) The documented step-budget pattern from `run!`'s own docstring (`current_step(s) < 200`)
  #     must not return a run whose clock reads 10^16 for a field that e-folded away by t ≈ 100.
  @test current_time(sim) < 1e4

  # (3) A step that reports success must actually advance the state, or else refuse to run: the run
  #     must not sit bit-frozen while the clock keeps adding time.
  k0 = kinetic_energy(sim.state.velocity_spectral)
  t0 = current_time(sim)
  for _ in 1:3
    advance!(sim)
  end
  k1 = kinetic_energy(sim.state.velocity_spectral)
  frozen = (k1 == k0)
  clock_ran = (current_time(sim) - t0) > 1e3
  @test !(frozen && clock_ran)
end
