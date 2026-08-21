# Witness — lane "edge-cases", 02.
#
# A negative `kinetic_energy` is not a physical state: k = ½⟨|u|²⟩ ≥ 0 by construction. The
# `Simulation` constructor must therefore reject it at the front door, in the house style used for
# every other precondition of this constructor (the `viscosity` / `κ_max_η` double-set check, the
# `dt > 0` and `order ≥ 1` checks in `Particles`, the "no energy to rescale" check in `State`): an
# `ArgumentError` naming the keyword at fault.
#
# On the current tree it instead reaches `stationary_dissipation(Li2008(), k, L) = (k/G)^(3//2)/L`
# (src/phenomenology/Scalings.jl), which is evaluated unconditionally at src/SimulationRun.jl:275
# — before any branch on `viscosity` — and throws `DomainError` from `Phenomenology.Scalings`,
# two modules from the argument that caused it and naming neither the keyword nor the precondition.

using Test, GBGIsotropicTurbulence

@testset "a negative `kinetic_energy` is rejected by `Simulation` with an ArgumentError naming it" begin
  # Explicit-viscosity mode: ε is never read on this path, yet it is computed eagerly.
  @test_throws ArgumentError Simulation(grid_points_per_axis = 8, viscosity = 0.05,
                                        kinetic_energy = -1.0)

  # Grid mode (the default): ε genuinely sets ν here, but the rejection must still be the
  # documented-precondition one, not an exponentiation failure inside the scaling law.
  @test_throws ArgumentError Simulation(grid_points_per_axis = 8, kinetic_energy = -1.0)

  # The message must name the keyword at fault, so the user can act on it.
  msg = try
    Simulation(grid_points_per_axis = 8, viscosity = 0.05, kinetic_energy = -1.0)
    ""
  catch e
    sprint(showerror, e)
  end
  @test occursin("kinetic_energy", msg)
end
