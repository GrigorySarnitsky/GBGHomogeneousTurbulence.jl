# Witness r4-edge-cases-05 — lane "edge-cases".
#
# Claim under test: a forcing constructor given `lowest_shell > highest_shell` silently builds a
# permanently empty band, so the run is silently unforced for its whole lifetime.
#
# The CORRECT behaviour asserted here: a swapped shell pair is rejected at construction with an
# `ArgumentError` (the alternative acceptable behaviour — silently reinterpreting the pair in the
# intended order — is deliberately NOT accepted: a typo should be reported, not guessed at).
using Test
using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.SimulationDomain: FixedDomain, TwoThirds
using GBGIsotropicTurbulence.Forcing: ConstantPower, Linear, VarianceRescaling, StochasticOU

@testset "A forcing constructor rejects lowest_shell > highest_shell instead of building an empty band" begin
  domain = FixedDomain(; grid_points_per_axis = 8, side_length = 2π,
                       element_type = Float64, dealiasing = TwoThirds(), array_type = Array)

  # Sanity: the ordered pair builds fine, so the throw below is about the ORDER, not the shells.
  @test ConstantPower(domain; injection_rate = 0.5, lowest_shell = 2, highest_shell = 5) isa ConstantPower

  @test_throws ArgumentError ConstantPower(domain; injection_rate = 0.5,
                                           lowest_shell = 5, highest_shell = 2)
  @test_throws ArgumentError Linear(domain; rate = 0.5, lowest_shell = 5, highest_shell = 2)
  @test_throws ArgumentError VarianceRescaling(domain; target = 0.5, over = :total,
                                           lowest_shell = 5, highest_shell = 2)
  @test_throws ArgumentError StochasticOU(domain; variance = 0.1, correlation_time = 0.5,
                                          lowest_shell = 5, highest_shell = 2)
end
