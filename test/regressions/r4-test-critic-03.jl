# Witness — lane "test-critic", round 4, 03.
#
# Claim under test: the `Simulation` constructor's `scalar_variance >= 0` precondition
# (src/SimulationRun.jl:281) is unpinned by any test, unlike its sibling `kinetic_energy > 0`
# guard, which has test/regressions/r3-02-edge-cases-02.jl. This file asserts the behaviour the
# guard is supposed to have: a negative ⟨φ²⟩ is rejected with an `ArgumentError` naming the
# keyword, and the boundary value 0 — a physically valid zero-variance scalar — is accepted, so
# that a later `>` -for- `>=` slip cannot pass in silence. Since 2026-10-14 the variance is
# `PassiveScalar`'s `variance`, and the guard lives there.

using Test, GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data

@testset "a negative scalar `variance` is rejected and the zero boundary accepted" begin
  # Explicit-viscosity mode.
  @test_throws ArgumentError Simulation(grid_points_per_axis = 8, viscosity = 0.05,
                                        scalar = PassiveScalar(variance = -1.0))

  # The ν derivation (the default route) must reject it just as early.
  @test_throws ArgumentError Simulation(grid_points_per_axis = 8,
                                        scalar = PassiveScalar(variance = -1.0))

  # The old `scalar_variance` keyword no longer exists on `Simulation`, so a variance given to a
  # scalar-free run is a call error rather than a setting silently ignored.
  @test_throws MethodError Simulation(grid_points_per_axis = 8, viscosity = 0.05,
                                      scalar_variance = -1.0)

  # The message must name the keyword at fault.
  msg = try
    Simulation(grid_points_per_axis = 8, viscosity = 0.05, scalar = PassiveScalar(variance = -1.0))
    ""
  catch e
    sprint(showerror, e)
  end
  @test occursin("variance", msg)

  # The boundary: ⟨φ²⟩ = 0 is a valid state (an identically-zero passive scalar), so `>=` must
  # admit it — and the resulting field must be finite, not a 0/0 from the seeder's rescaling.
  sim = Simulation(grid_points_per_axis = 8, viscosity = 0.05,
                   scalar = PassiveScalar(variance = 0.0))
  @test scalar_variance(sim.state.scalar_spectral) == 0.0
  @test all(isfinite, Array(field_data(sim.state.scalar_spectral)))
end
