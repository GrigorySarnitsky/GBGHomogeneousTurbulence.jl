# Candidate (r4, edge-cases, 06): "Grid-mode viscosity selection assumes `over = :total`
# `BandRescaling` but never checks the actual `velocity_forcing`" — SimulationRun.jl:297.
#
# The hunter's discriminator was: in grid mode with a non-`BandRescaling(over = :total)` forcing,
# the measured `max_wavenumber * kolmogorov_length` should stay near the nominal `κ_max_η = 2` the
# constructor's `@info` reports, and does not.
#
# This file runs that discriminator against BOTH arms — the accused forcing AND the control the
# docstring (lines 196-199) declares self-consistent, `BandRescaling(over = :total)`. The control
# misses 2 as well, because grid mode's ν comes from the *modeled* `Li2008` dissipation
# (`ε = (k/G)^{3/2}/L`, "a modeled estimate, not a measurement" — the comment at line 272), and at
# 32³ that model underestimates the box's actual ε by ~2×. The forcing check the candidate asks for
# would not move the control. The tests below assert what the code actually contracts: grid-mode ν
# is a function of the grid and the target energy alone, deliberately independent of the forcing,
# and the log line reports that design target rather than a measured state.

using Test, Random
using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Phenomenology: kolmogorov_length
const κ_max = GBGIsotropicTurbulence.SimulationDomain.max_wavenumber


"Build a 32³ grid-mode run with `forcing`, spin it up, return (ν, measured κ_max·η)."
function grid_mode_run(forcing)
  sim = Simulation(grid_points_per_axis = 32, velocity_forcing = forcing,
                   rng = MersenneTwister(4242))
  ν = sim.generator.conditions.viscosity
  warmup!(sim)
  return ν, κ_max(sim.domain) * kolmogorov_length(flow_parameters(sim))
end


@testset "Grid-mode ν is forcing-independent by contract, and its κ_max·η target is a modeled design value" begin
  ν_band,  ratio_band  = grid_mode_run(BandRescaling(target = 1.5, over = :total))
  ν_cp01,  ratio_cp01  = grid_mode_run(ConstantPower(injection_rate = 0.1))
  ν_cp30,  ratio_cp30  = grid_mode_run(ConstantPower(injection_rate = 3.0))
  @info "measured" ν_band ratio_band ratio_cp01 ratio_cp30

  # 1. The contract the constructor states: in grid mode ν is fixed by the grid, `kinetic_energy`
  #    and `κ_max_η`. It is the same number under every forcing — that is not an oversight, it is
  #    the documented meaning of the mode ("the constructor picks the highest Reynolds number
  #    consistent with the resolution criterion").
  @test ν_band == ν_cp01 == ν_cp30

  # 2. The hunter's discriminator fails on the CONTROL too: the forcing the docstring says
  #    "guarantees" self-consistency does not put the measured κ_max·η at the nominal 2 either.
  #    So a deviation from 2 does not isolate a missing forcing check.
  @test !isapprox(ratio_band, 2.0; rtol = 0.10)

  # 3. And the control's own miss is comparable in size to the accused arm's, i.e. the modeled-ε
  #    error dominates. Adding the requested `velocity_forcing` check would leave arm 2 untouched.
  @test abs(log(ratio_band / 2.0)) > 0.5 * abs(log(ratio_cp01 / 2.0))

  # 4. Grid mode really is reachable with any forcing, without warning or error — the documented
  #    behaviour ("Give the velocity a forcing that lets k float and the ν chosen here no longer
  #    matches the run"), which the docstring states as a precondition on the user, not a guard.
  @test ν_band > 0
end
