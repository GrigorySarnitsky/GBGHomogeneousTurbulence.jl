# Witness — the adaptive timestep must obey the documented advective rule in the regime the rule is
# for, and must not run away where the rule goes vacuous.
#
# History: a ceiling of `cfl*Δx` was tried and is the step the rule gives at UNIT SPEED, so it bound
# every sub-unit-speed run — a units claim, caught by six audit lanes. The bound kept instead is the
# RESOLUTION limit 1/(D·κ_min²), the decay time of the longest mode the box holds, which is derived
# from the run's own ν and L and binds only below Re_L ≈ 1.
using Test, GBGHomogeneousTurbulence, Random
const SR = GBGHomogeneousTurbulence.SimulationRun

@testset "a sub-unit-speed turbulent run gets the documented advective step, unthrottled" begin
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, kinetic_energy = 0.02,
                   velocity_forcing = NoForcing(), rng = MersenneTwister(1))
  speed = max_speed(sim.cache)
  @test 0 < speed < 1                                  # the regime the units-claim ceiling broke
  @test SR.cfl_timestep(sim) ≈ sim.cfl * (2π / 16) / speed
end

@testset "the runaway is bounded by the box's own slowest decay, with no constant chosen" begin
  ν = 0.05
  sim = Simulation(grid_points_per_axis = 16, viscosity = ν, kinetic_energy = 1e-10,
                   velocity_forcing = NoForcing(), rng = MersenneTwister(2))
  resolution = 1 / (ν * (2π / 2π)^2)                   # 1/(ν κ_min²) = 20 here
  @test SR.cfl_timestep(sim) <= resolution * (1 + 1e-9)
  @test SR.cfl_timestep(sim) < 1e3                     # not ~1e15
end

@testset "a scalar that diffuses faster than the velocity sets the tighter bound" begin
  ν, Sc = 0.05, 0.25                                   # scalar diffusivity ν/Sc = 4x the velocity's
  sim = Simulation(grid_points_per_axis = 16, viscosity = ν, schmidt = Sc, scalar = true,
                   kinetic_energy = 1e-10, velocity_forcing = NoForcing(), rng = MersenneTwister(3))
  @test SR.cfl_timestep(sim) <= 1 / ((ν / Sc) * 1.0) * (1 + 1e-9)
end

@testset "max_dt still tightens it, and defaults to imposing nothing" begin
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, kinetic_energy = 1e-10,
                   velocity_forcing = NoForcing(), max_dt = 0.5, rng = MersenneTwister(4))
  @test SR.cfl_timestep(sim) <= 0.5
end
