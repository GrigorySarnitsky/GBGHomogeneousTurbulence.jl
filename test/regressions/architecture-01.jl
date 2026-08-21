# Architecture witness (diff check, not a failing test): the grid-mode Simulation constructor's
# inline `reλ` at src/SimulationRun.jl:284 is the SAME formula as Phenomenology.taylor_reynolds,
# spelled a second time. This script demonstrates the two spellings agree numerically today —
# i.e. the finding is duplication of a definition, not a present numeric divergence.
using Test
using GBGIsotropicTurbulence.Phenomenology: FlowParameters, taylor_reynolds

inline_reλ(k, ε, ν) = (2 * k / 3) * sqrt(15 / (ε * ν))          # copy of SimulationRun.jl:284

@testset "grid-mode inline Re_λ duplicates Phenomenology.taylor_reynolds" begin
  for (k, ε, ν) in ((1.5, 1.0, 1e-3), (0.75, 0.3, 5e-4), (3.0, 2.2, 2e-2))
    fp = FlowParameters(; viscosity = ν, dissipation = ε, rms_velocity = sqrt(2k / 3),
                        integral_scale = 0.5)
    @test taylor_reynolds(fp) ≈ inline_reλ(k, ε, ν)
    println("k=$k ε=$ε ν=$ν :  taylor_reynolds=", taylor_reynolds(fp),
            "   inline=", inline_reλ(k, ε, ν))
  end
end
