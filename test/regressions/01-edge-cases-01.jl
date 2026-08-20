# Witness: warmup! / StationarityCriterion must terminate for a zero-viscosity run.
#
# `viscosity = 0.0` is an accepted explicit-mode input to `Simulation` (no validation rejects it).
# With ν = 0 the dissipation ε = ν⟨|ω|²⟩ is identically zero, so the turnover clock
# `ε > 0 && (criterion.elapsed_turn += Δt * ε / k)` (src/SimulationRun.jl:666) never advances.
# Both exits of the callback — the flatness test's `elapsed_turn ≥ min_turnovers` and the give-up
# cap `elapsed_turn ≥ max_turnovers` — read that stuck clock, so the callback can never return
# `false` and `run!`'s `while true` loop never returns.
#
# The correct behaviour asserted here: the criterion stops the run within a bounded number of
# iterations (either by converging or by the `max_turnovers` warning). The loop below is `run!`'s
# own loop with a hard step cap, so the witness itself cannot hang.

using Test, Random, GBGIsotropicTurbulence

"Drive `criterion` exactly as `run!` does, but abort after `cap` iterations. Returns the number of
iterations taken and whether the criterion stopped the run itself."
function bounded_run!(criterion, sim; cap)
  steps = 0
  while steps ≤ cap
    criterion(sim) || return (steps, true)
    advance!(sim)
    steps += 1
  end
  return (steps, false)
end

@testset "warmup! terminates on a zero-viscosity run instead of looping forever" begin
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.0, rng = MersenneTwister(11))
  @test sim.generator.conditions.viscosity == 0.0

  criterion = StationarityCriterion(min_turnovers = 1, max_turnovers = 2,
                                    window_turnovers = 0.5, gate_skewness = false)
  steps, stopped = bounded_run!(criterion, sim; cap = 400)

  # ε ≡ 0 with ν = 0, so the turnover clock must not be the only thing that can end the run.
  @test stopped   # the criterion stopped the run within the 400-iteration budget
  @info "witness" steps stopped elapsed_turn = criterion.elapsed_turn current_step = current_step(sim)

  # Positive control: the identical criterion on an otherwise identical run with ν > 0 does stop
  # well inside the same budget, so the assertion above is not merely a too-small step cap.
  ref = Simulation(grid_points_per_axis = 16, viscosity = 0.05, rng = MersenneTwister(11))
  ref_criterion = StationarityCriterion(min_turnovers = 1, max_turnovers = 2,
                                        window_turnovers = 0.5, gate_skewness = false)
  ref_steps, ref_stopped = bounded_run!(ref_criterion, ref; cap = 400)
  @test ref_stopped
  @info "control" ref_steps ref_stopped elapsed_turn = ref_criterion.elapsed_turn
end
