# Witness — AUDIT finding (six lanes independently): the CFL ceiling added while fixing the runaway
# is a statement about UNITS. It caps Δt at `cfl*Δx`, the value the rule gives at unit speed, so it
# binds for every run whose characteristic velocity is below 1 — which is a property of the units the
# caller chose, not of the physics. The runaway it targets (u_max → 0 sending Δt → 1e15) is real; the
# clamp is not a bound at u_max → 0, it is a silent throttle everywhere below unit speed.
using Test, GBGIsotropicTurbulence, Random
const SR = GBGIsotropicTurbulence.SimulationRun

@testset "the adaptive timestep is not silently throttled for a sub-unit-speed run" begin
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, kinetic_energy = 0.02,
                   velocity_forcing = NoForcing(), rng = MersenneTwister(1))
  speed = max_speed(sim.cache)
  @test 0 < speed < 1                       # the regime under test: legitimate, and previously fine
  advective = sim.cfl * (2π / 16) / speed   # what the documented rule Δt = cfl·Δx/u_max gives
  @test SR.cfl_timestep(sim) ≈ advective    # the rule, unthrottled
end

@testset "and the runaway it was meant to bound is still bounded" begin
  # A decaying run drives u_max → 0. Δt must not diverge; a caller may bound it explicitly.
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.5, kinetic_energy = 1e-8,
                   velocity_forcing = NoForcing(), max_dt = 0.05, rng = MersenneTwister(2))
  for _ in 1:10; advance!(sim); end
  @test SR.cfl_timestep(sim) <= 0.05        # the bound is the caller's, stated in their own units
end
