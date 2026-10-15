# Architecture witness (diff check, not a failing test) — the sibling of `architecture-01.jl`.
#
# The relation η = (ν³/ε)^(1/4) is spelled in two places inside this package's own surface, and a
# third in the extraction-bound `Phenomenology` leaf, which spells its own formulas by design:
#
#   src/Observables.jl       kolmogorov_length(ε, ν)                     # the package's one home
#   src/SimulationRun.jl     the derived-ν solve, the relation inverted  # no inverse exists to call
#   src/Phenomenology.jl     kolmogorov_length(fp)                        # the leaf's own copy
#
# The ONLY test that pins the derived-ν calibration once re-derived η from a bare literal instead of
# calling the package's own function, so it was not independent of what it guards. This script
# asserts the relation the code SHOULD hold — routed through the canonical home — and keeps the
# literal beside it as the independent reference.
using Test
using GBGHomogeneousTurbulence
using Random

@testset "the derived ν solves `kolmogorov_length`'s relation, measured by that function" begin
  for (N, L, k, res) in ((32, 2π, 1.5, 2), (32, 2π, 1.5, 3), (16, 1.0, 0.75, 2), (48, 4π, 3.0, 1.5))
    sim = Simulation(grid_points_per_axis = N, side_length = L, kinetic_energy = k,
                     κ_max_η = res, rng = MersenneTwister(3))
    ν = sim.generator.conditions.viscosity
    ε = predicted_stationary_state(sim.domain; kinetic_energy = k, κ_max_η = res).dissipation

    η_canonical = kolmogorov_length(ε, ν)                 # the definition every diagnostic means by η
    η_literal   = (ν^3 / ε)^(1 / 4)                       # the independent reference
    κ_max       = max_resolved_wavenumber(sim.domain)

    # The @info line's claim, measured through the canonical home rather than a fourth spelling.
    @test isapprox(κ_max * η_canonical, res; rtol = 1e-10)
    # The literal is numerically identical — i.e. the finding was duplication, not divergence.
    @test η_literal ≈ η_canonical
    println("N=$N L=$L k=$k κ_max_η=$res :  ν=", ν, "  κ_max·η(canonical)=", κ_max * η_canonical,
            "  κ_max·η(literal)=", κ_max * η_literal)
  end
end
