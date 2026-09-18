# Architecture witness (diff check, not a failing test) — the sibling of `architecture-01.jl`,
# one line ABOVE the Re_λ duplication that commit fbb1078 routed through `taylor_reynolds`.
#
# The relation η = (ν³/ε)^(1/4) is spelled THREE times in the tree:
#
#   src/Phenomenology.jl:137   kolmogorov_length(fp) = (fp.viscosity^3 / fp.dissipation)^(1//4)
#   src/SimulationRun.jl:283   ν = ε^(1//3) * (resolution / max_wavenumber(domain))^(4//3)   # inverse
#   test/simulation_run.jl:68  η = (ν^3 / ε)^(1 / 4)                                         # test copy
#
# The third is what makes this more than untidiness: the ONLY test that pins the derived-ν
# calibration re-derives η from a bare literal instead of calling `kolmogorov_length`, so it is
# not independent of what it guards. This script asserts the relation the code SHOULD hold —
# routed through the canonical home — and demonstrates it holds today.
using Test
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Phenomenology: FlowParameters, kolmogorov_length
using GBGHomogeneousTurbulence.Phenomenology.Scalings: stationary_dissipation, Li2008
using Random

@testset "the derived ν solves `kolmogorov_length`'s relation, measured by that function" begin
  for (N, L, k, res) in ((32, 2π, 1.5, 2), (32, 2π, 1.5, 3), (16, 1.0, 0.75, 2), (48, 4π, 3.0, 1.5))
    sim = Simulation(grid_points_per_axis = N, side_length = L, kinetic_energy = k,
                     κ_max_η = res, rng = MersenneTwister(3))
    ν = sim.generator.conditions.viscosity
    ε = stationary_dissipation(Li2008(), k, L)
    fp = FlowParameters(; viscosity = ν, dissipation = ε,
                        rms_velocity = sqrt(2k / 3), integral_scale = one(ν), schmidt = 1.0)

    η_canonical = kolmogorov_length(fp)                 # the definition every diagnostic means by η
    η_literal   = (ν^3 / ε)^(1 / 4)                     # test/simulation_run.jl:68's copy
    κ_max       = max_resolved_wavenumber(sim.domain)

    # The @info line's claim, measured through the canonical home rather than a fourth spelling.
    @test isapprox(κ_max * η_canonical, res; rtol = 1e-10)
    # The test copy is numerically identical today — i.e. the finding is duplication, not divergence.
    @test η_literal ≈ η_canonical
    println("N=$N L=$L k=$k κ_max_η=$res :  ν=", ν, "  κ_max·η(canonical)=", κ_max * η_canonical,
            "  κ_max·η(literal)=", κ_max * η_literal)
  end
end
