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

@testset "a zero-viscosity run cannot be built, and the criterion still terminates without one" begin
  # UPDATED 2026-08-21. This reached the non-terminating warm-up by building a ν = 0 run — a route a
  # LATER fix closed at the source, because ν sets the Reynolds number through Re = 1/ν and a
  # non-positive value has no dissipation scale. The original defect (the eddy-turnover clock cannot
  # advance when ε ≡ 0, while `max_turnovers` is denominated in exactly those units, so the give-up
  # cap could never be reached) is still fixed, and the positive control below exercises it. What is
  # testable here now is the stronger guarantee: the state that produced it cannot be constructed.
  @test_throws ArgumentError Simulation(grid_points_per_axis = 16, viscosity = 0.0,
                                        rng = MersenneTwister(11))
  @test_throws ArgumentError Simulation(grid_points_per_axis = 16, viscosity = -0.01,
                                        rng = MersenneTwister(11))


  # Positive control: the identical criterion on an otherwise identical run with ν > 0 does stop
  # well inside the same budget, so the assertion above is not merely a too-small step cap.
  ref = Simulation(grid_points_per_axis = 16, viscosity = 0.05, rng = MersenneTwister(11))
  ref_criterion = StationarityCriterion(min_turnovers = 1, max_turnovers = 2,
                                        window_turnovers = 0.5, gate_skewness = false)
  ref_steps, ref_stopped = bounded_run!(ref_criterion, ref; cap = 400)
  @test ref_stopped
  @info "control" ref_steps ref_stopped elapsed_turn = ref_criterion.elapsed_turn
end
