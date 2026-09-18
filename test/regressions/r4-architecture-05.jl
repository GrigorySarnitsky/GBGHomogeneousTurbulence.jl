# Architecture witness r4-05 (diff check, not a failing test) — the third sibling of
# `architecture-01.jl` (inline Re_λ) and `05-free-hot-path-05-kolmogorov-length-duplication.jl`
# (inline η): the isotropic conversion u' = √(2k/3) is spelled as a bare literal at THREE sites,
# with no named home to route through.
#
#   src/SimulationRun.jl:301   rms_velocity = sqrt(2 * kinetic_energy / 3)   # grid-mode Re_λ report
#   src/SimulationRun.jl:316   rms_velocity = sqrt(2 * kinetic_energy / 3)   # Phenomenology IC spectrum
#   src/SimulationRun.jl:385   rms_velocity = sqrt(2k / 3)                   # flow_parameters bridge
#   (+ the inverse, k = 3u'²/2, spelled at src/phenomenology/Spectra.jl:148)
#
# `docs/src/notation.md:85` names `flow_parameters` as the code home of u' = √(2k/3); the two
# constructor sites are copies of that home's formula, made two lines below a comment that states
# the opposite rule ("Through the canonical reduction, not a second spelling of it").
#
# What IS runnable is the claim that the three spellings agree today: the seeder pins
# kinetic_energy(û) to the constructor's target k, so at t₀ the constructor's u' and the
# flow_parameters bridge's u' must be the same number. They are — i.e. the finding is duplication
# of a definition, not a present numeric divergence.
using Test, Random
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Phenomenology: FlowParameters, taylor_reynolds

@testset "u' = √(2k/3): the constructor's spelling and the flow_parameters bridge agree" begin
  for (N, L, k) in ((16, 2π, 1.5), (16, 2π, 0.75), (24, 4π, 3.0))
    sim = Simulation(grid_points_per_axis = N, side_length = L, kinetic_energy = k,
                     κ_max_η = 2, rng = MersenneTwister(7))

    # (1) The seeder honours the target, so the constructor's k and the bridge's measured k coincide.
    @test kinetic_energy(sim.state.velocity_spectral) ≈ k

    # (2) Site 385 (flow_parameters) reproduces sites 301/316's literal for the same k.
    fp = flow_parameters(sim)
    @test fp.rms_velocity ≈ sqrt(2k / 3)

    # (3) The ν-derivation @info line's Re_λ is built from site 301's copy; recomputing it from the
    #     bridge's u' gives the same number today — the two copies are numerically identical.
    ν = sim.generator.conditions.viscosity
    reλ_from_bridge = taylor_reynolds(FlowParameters(; viscosity = ν, dissipation = fp.dissipation,
                                                     rms_velocity = fp.rms_velocity,
                                                     integral_scale = one(ν)))
    reλ_from_copy   = taylor_reynolds(FlowParameters(; viscosity = ν, dissipation = fp.dissipation,
                                                     rms_velocity = sqrt(2 * k / 3),
                                                     integral_scale = one(ν)))
    @test reλ_from_bridge ≈ reλ_from_copy
    println("N=$N L=$L k=$k :  u'(bridge)=", fp.rms_velocity, "  u'(literal)=", sqrt(2k / 3),
            "  Re_λ(bridge)=", reλ_from_bridge, "  Re_λ(copy)=", reλ_from_copy)
  end
end
