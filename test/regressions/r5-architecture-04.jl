# Architecture witness r5-04 (diff check, not a failing test) — the isotropic conversion
# u' = √(2k/3) is spelled as a bare literal at THREE sites in one file, with no named home.
# This REPEATS round 4's `test/regressions/r4-architecture-05.jl` (line numbers have since
# shifted by +5); the three copies are still there.
#
#   src/SimulationRun.jl:306   rms_velocity = sqrt(2 * kinetic_energy / 3)   # grid-mode Re_λ report
#   src/SimulationRun.jl:321   rms_velocity = sqrt(2 * kinetic_energy / 3)   # Phenomenology IC spectrum
#   src/SimulationRun.jl:390   rms_velocity = sqrt(2k / 3)                   # flow_parameters bridge
#   (+ the forward direction, k = 3u'²/2, spelled at src/phenomenology/Spectra.jl:148)
#
# The first two are the SAME expression over the SAME local, fifteen lines apart in one function
# body — two lines below a comment stating the opposite rule ("Through the canonical reduction,
# not a second spelling of it"). `docs/src/notation.md` names `flow_parameters` as the code home
# of u' = √(2k/3); `Phenomenology` exports no callable conversion for the three to share.
#
# What IS runnable is the claim that the spellings agree TODAY — i.e. that the finding is
# duplication of a definition, not a present numeric divergence.
using Test, Random
using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Phenomenology: FlowParameters, taylor_reynolds

@testset "u' = √(2k/3): the constructor's two copies and the flow_parameters home agree" begin
  # (1) No named conversion exists for the three sites to route through: neither the umbrella nor
  #     Phenomenology exposes one, which is why each site re-spells the coefficient by hand.
  names_all = vcat(names(GBGIsotropicTurbulence), names(GBGIsotropicTurbulence.Phenomenology))
  @test !any(n -> occursin("rms", lowercase(String(n))), names_all)

  for (N, L, k) in ((16, 2π, 1.5), (16, 2π, 0.75), (24, 4π, 3.0))
    sim = Simulation(grid_points_per_axis = N, side_length = L, kinetic_energy = k,
                     κ_max_η = 2, rng = MersenneTwister(7))

    # (2) The seeder honours the target, so the constructor's k (sites 306/321) and the bridge's
    #     measured k (site 390) are the same number — the two spellings are compared at equal input.
    @test kinetic_energy(sim.state.velocity_spectral) ≈ k
    fp = flow_parameters(sim)
    @test fp.rms_velocity ≈ sqrt(2k / 3)

    # (3) The grid-mode @info Re_λ is built from site 306's copy; rebuilding it from the bridge's
    #     u' gives the same number today. A drift in ONE copy would separate these two.
    ν = sim.generator.conditions.viscosity
    reλ_bridge = taylor_reynolds(FlowParameters(; viscosity = ν, dissipation = fp.dissipation,
                                                rms_velocity = fp.rms_velocity, integral_scale = one(ν)))
    reλ_copy   = taylor_reynolds(FlowParameters(; viscosity = ν, dissipation = fp.dissipation,
                                                rms_velocity = sqrt(2 * k / 3), integral_scale = one(ν)))
    @test reλ_bridge ≈ reλ_copy
    println("N=$N L=$L k=$k :  u'(home, site 390)=", fp.rms_velocity,
            "  u'(literal, sites 306/321)=", sqrt(2k / 3),
            "  Re_λ(home)=", reλ_bridge, "  Re_λ(copy)=", reλ_copy)
  end
end
