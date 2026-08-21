# Witness r5-test-critic-01 — the hunter's claim: `advance!`'s blow-up guards (the non-finite
# velocity check at SimulationRun.jl:481 and the scalar branch at :487) are never exercised by any
# test, so a regression that moved the check back into `cfl_timestep`, ran it before the deposit,
# or dropped the scalar branch would pass the whole suite.
#
# This file is the hunter's own plan, executed: poison the velocity, then the scalar, and assert the
# CORRECT behaviour — `advance!` refuses to report success on a state it has just made non-finite,
# names the offending field, and leaves the clock untouched.
using Test, Random
using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data

@testset "advance! refuses a non-finite velocity, naming it, without advancing the clock" begin
  sim = Simulation(grid_points_per_axis = 12, viscosity = 0.05, rng = MersenneTwister(1))
  advance!(sim; dt = 1e-3)
  step_before, time_before = current_step(sim), current_time(sim)

  field_data(sim.state.velocity_spectral)[1] = NaN
  err = try
    advance!(sim; dt = 1e-3); nothing
  catch e
    e
  end

  @test err isa ErrorException
  @test occursin("non-finite velocity", sprint(showerror, err))
  # The refused iteration must not be counted: the clock advances only past the guard.
  @test current_step(sim) == step_before
  @test current_time(sim) == time_before
end


@testset "advance! refuses a non-finite scalar, naming the scalar rather than the velocity" begin
  sim = Simulation(grid_points_per_axis = 12, viscosity = 0.05, scalar = true,
                   rng = MersenneTwister(2))
  advance!(sim; dt = 1e-3)
  step_before, time_before = current_step(sim), current_time(sim)

  # Scalar only — the velocity stays finite, so `max_speed` cannot see this blow-up.
  field_data(sim.state.scalar_spectral)[3, 3, 3] = NaN + 0im
  fields_modified!(sim.cache)
  deposit!(sim)
  @test all(isfinite, field_data(velocity_physical(sim.cache)))   # sanity: velocity untouched

  err = try
    advance!(sim; dt = 1e-3); nothing
  catch e
    e
  end

  @test err isa ErrorException
  @test occursin("non-finite scalar", sprint(showerror, err))
  @test !occursin("non-finite velocity", sprint(showerror, err))
  @test current_step(sim) == step_before
  @test current_time(sim) == time_before
end
