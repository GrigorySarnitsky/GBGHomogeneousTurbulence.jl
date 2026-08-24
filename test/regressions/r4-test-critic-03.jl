# Witness — lane "test-critic", round 4, 03.
#
# Claim under test: the `Simulation` constructor's `scalar_variance >= 0` precondition
# (src/SimulationRun.jl:281) is unpinned by any test, unlike its sibling `kinetic_energy > 0`
# guard, which has test/regressions/r3-02-edge-cases-02.jl. This file asserts the behaviour the
# guard is supposed to have: a negative ⟨φ²⟩ is rejected with an `ArgumentError` naming the
# keyword, and the boundary value 0 — a physically valid zero-variance scalar — is accepted, so
# that a later `>` -for- `>=` slip cannot pass in silence.

using Test, GBGIsotropicTurbulence
using GBGPeriodicFields: field_data

@testset "`Simulation` rejects a negative `scalar_variance` and accepts the zero boundary" begin
  # Explicit-viscosity mode.
  @test_throws ArgumentError Simulation(grid_points_per_axis = 8, viscosity = 0.05,
                                        scalar = true, scalar_variance = -1.0)

  # The ν derivation (the default route) must reject it just as early.
  @test_throws ArgumentError Simulation(grid_points_per_axis = 8,
                                        scalar = true, scalar_variance = -1.0)

  # The check is a precondition of the keyword, not of the `scalar` switch: it must fire even
  # when no scalar field is allocated, so a typo cannot be silently ignored.
  @test_throws ArgumentError Simulation(grid_points_per_axis = 8, viscosity = 0.05,
                                        scalar_variance = -1.0)

  # The message must name the keyword at fault.
  msg = try
    Simulation(grid_points_per_axis = 8, viscosity = 0.05, scalar = true, scalar_variance = -1.0)
    ""
  catch e
    sprint(showerror, e)
  end
  @test occursin("scalar_variance", msg)

  # The boundary: ⟨φ²⟩ = 0 is a valid state (an identically-zero passive scalar), so `>=` must
  # admit it — and the resulting field must be finite, not a 0/0 from the seeder's rescaling.
  sim = Simulation(grid_points_per_axis = 8, viscosity = 0.05,
                   scalar = true, scalar_variance = 0.0)
  @test scalar_variance(sim.state.scalar_spectral) == 0.0
  @test all(isfinite, Array(field_data(sim.state.scalar_spectral)))
end
