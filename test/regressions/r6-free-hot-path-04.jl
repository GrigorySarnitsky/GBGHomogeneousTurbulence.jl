# Witness: StationarityCriterion's non-positive-dissipation warning must be clean prose —
# no embedded multi-space runs left over from a source-line reflow without concatenation.
#
# The @warn at src/SimulationRun.jl:967 was reflowed inside a single string literal, so the
# indentation became part of the message ("the eddy-turnover            clock", "no
# dissipation" with 12 spaces). Every sibling message in the file uses '*'-concatenation to
# avoid exactly this. The assertion below states the CORRECT behaviour (no "  " run in the
# emitted message) and therefore fails on the current tree.

using Test, Random, Logging, GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data

@testset "the ε ≤ 0 warning of StationarityCriterion carries no embedded multi-space runs" begin
  sim = Simulation(grid_points_per_axis = 8, viscosity = 0.05, rng = MersenneTwister(7))
  # Zero the velocity by hand: ε = ν⟨|ω|²⟩ is then exactly zero, which routes the criterion
  # into its no-dissipation warning branch. The criterion reads the spectral field directly.
  fill!(field_data(sim.state.velocity_spectral), 0)
  fields_modified!(sim.cache)

  criterion = StationarityCriterion()
  logs, result = Test.collect_test_logs() do
    criterion(sim)
  end
  @test result == false
  warnings = [rec for rec in logs if rec.level == Logging.Warn]
  @test length(warnings) == 1
  message = String(warnings[1].message)
  @test occursin("dissipation rate is not positive", message)
  # The correct behaviour: a user-facing diagnostic is one clean sentence stream, never
  # carrying source-indentation runs inside the text.
  @test !occursin("  ", message)
end
