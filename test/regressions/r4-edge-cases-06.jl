# Candidate (r4, edge-cases, 06): "Grid-mode viscosity selection assumes `over = :total`
# `VarianceRescaling` but never checks the actual `velocity_forcing`" — SimulationRun.jl:297.
#
# The hunter's discriminator was: under a derived ν with a non-`VarianceRescaling(over = :total)` forcing,
# the measured `max_wavenumber * kolmogorov_length` should stay near the nominal `κ_max_η = 2` the
# constructor's `@info` reports, and does not.
#
# This file runs that discriminator against BOTH arms — the accused forcing AND the control the
# docstring (lines 196-199) declares self-consistent, `VarianceRescaling(over = :total)`. The control
# misses 2 as well, because the derived ν comes from the *modeled* `Li2008` dissipation
# (`ε = (k/G)^{3/2}/L`, "a modeled estimate, not a measurement" — the comment at line 272), and at
# 32³ that model underestimates the box's actual ε by ~2×. The forcing check the candidate asks for
# would not move the control. The tests below assert what the code actually contracts: the derived ν
# is a function of the grid and the target energy alone, deliberately independent of the forcing,
# and the log line reports that design target rather than a measured state.
#
# 2026-09-24 (decision 94): the stationary estimate now uses the package's provisional G = 0.7 rather
# than `Li2008`'s 0.9, and the control's miss shrank from the ~2×-in-ε error recorded above to ~9% in
# κ_max·η (1.815 against 2). Assertions 2 and 3 pinned the SIZE of the old calibration error, which
# the decision reduced, so they now pin what holds instead: the control's residual miss is small, and
# the forcing mismatch — the arm the constructor already warns about — is now the larger error.

using Test, Random, Logging
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Phenomenology: kolmogorov_length
const κ_max = GBGHomogeneousTurbulence.SimulationDomain.max_resolved_wavenumber


"Build a 32³ derived-viscosity run with `forcing`, spin it up, return (ν, measured κ_max·η)."
function grid_mode_run(forcing)
  sim = Simulation(grid_points_per_axis = 32, velocity_forcing = forcing,
                   rng = MersenneTwister(4242))
  ν = sim.generator.conditions.viscosity
  warmup!(sim)
  return ν, κ_max(sim.domain) * kolmogorov_length(flow_parameters(sim))
end


@testset "The derived ν is forcing-independent by contract, and its κ_max·η target is a modeled design value" begin
  ν_band,  ratio_band  = grid_mode_run(VarianceRescaling(target = 1.5, over = :total))
  ν_cp01,  ratio_cp01  = grid_mode_run(ConstantPower(injection_rate = 0.1))
  ν_cp30,  ratio_cp30  = grid_mode_run(ConstantPower(injection_rate = 3.0))
  @info "measured" ν_band ratio_band ratio_cp01 ratio_cp30

  # 1. The contract the constructor states: a derived ν is fixed by the grid, `kinetic_energy`
  #    and `κ_max_η`. It is the same number under every forcing — that is not an oversight, it is
  #    the documented meaning of the mode ("the constructor picks the highest Reynolds number
  #    consistent with the resolution criterion").
  @test ν_band == ν_cp01 == ν_cp30

  # 2. The control's miss is the modeled-ε residual at this grid's Reynolds number: small, but not
  #    zero, since a single G cannot follow G's rise with Re_λ (measured 1.815 against the nominal 2).
  @test isapprox(ratio_band, 2.0; rtol = 0.15)

  # 3. With the calibration closer, the forcing mismatch is the larger error — which is why the
  #    constructor warns about a forcing that does not hold k (assertion 4).
  @test abs(log(ratio_band / 2.0)) < abs(log(ratio_cp01 / 2.0))

  # 4. The derived route remains REACHABLE with any forcing — but the disposition this item once pinned
  #    ("without warning or error ... a precondition on the user, not a guard") was REVERSED by the
  #    owner on 2026-08-24: a hand-built forcing that voids the ν calibration now draws a WARNING
  #    (never an error). Reachability and the warning are asserted together below.
  @test ν_band > 0
  # A matching :total rescale is consistent with the calibration and stays silent; a forcing that
  # does not hold k warns; a mismatched target warns. Construction only — no spin-up needed.
  @test_logs min_level=Logging.Warn Simulation(grid_points_per_axis = 16,
      velocity_forcing = VarianceRescaling(target = 1.5, over = :total), rng = MersenneTwister(1))
  @test_logs (:warn, r"derived viscosity.*does not hold") match_mode=:any Simulation(
      grid_points_per_axis = 16, velocity_forcing = ConstantPower(injection_rate = 0.1),
      rng = MersenneTwister(1))
  @test_logs (:warn, r"holds target = 0.5") match_mode=:any Simulation(
      grid_points_per_axis = 16, velocity_forcing = VarianceController(target = 0.5),
      rng = MersenneTwister(1))
end
