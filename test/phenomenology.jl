using Test
using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Phenomenology
using GBGIsotropicTurbulence.Phenomenology.Spectra
using GBGIsotropicTurbulence.Phenomenology.StructureFunctions
using GBGIsotropicTurbulence.Phenomenology.Scalings

const FP = FlowParameters(viscosity = 1e-3, dissipation = 0.1, rms_velocity = 1.0, integral_scale = 1.0)


@testset "FlowParameters — derived scales" begin
  @test kolmogorov_length(FP) ≈ (1e-3^3 / 0.1)^(1 / 4)
  @test kolmogorov_time(FP) ≈ sqrt(1e-3 / 0.1)
  @test taylor_microscale(FP) ≈ sqrt(15 * 1e-3 * 1.0^2 / 0.1)
  # Re_λ = u'λ/ν  and its equivalent closed form u'² √(15/(νε))
  @test taylor_reynolds(FP) ≈ 1.0 * taylor_microscale(FP) / 1e-3
  @test taylor_reynolds(FP) ≈ 1.0^2 * sqrt(15 / (1e-3 * 0.1))
  @test scalar_diffusivity(FlowParameters(viscosity = 2e-3, dissipation = 0.1, rms_velocity = 1.0,
                                          integral_scale = 1.0, schmidt = 2.0)) ≈ 1e-3
end


@testset "Spectra — Pope2000 model spectrum" begin
  E = Pope2000()
  @test E isa EnergySpectrum
  @test E isa ModelSpectrum

  Es = [spectrum(E, κ, FP) for κ in (2.0, 10.0, 30.0, 100.0)]
  @test all(>(0), Es)              # positive everywhere
  @test issorted(Es; rev = true)   # monotone decreasing across energy → inertial → dissipation

  # compensated spectrum κ^{5/3} E / ε^{2/3} = C_K f_L f_η ∈ (0, C_K]; peaks in the inertial range
  comp(κ) = spectrum(E, κ, FP) * κ^(5 / 3) / 0.1^(2 / 3)
  @test 0 < comp(10.0) ≤ 1.5 + 1e-9
  @test comp(10.0) > comp(2.0)     # above the energy-containing roll-off
  @test comp(10.0) > comp(100.0)   # below the dissipation roll-off

  # C_K scales the whole spectrum linearly (coefficient override)
  @test spectrum(Pope2000(C_K = 3.0), 10.0, FP) ≈ 2 * spectrum(Pope2000(C_K = 1.5), 10.0, FP)

  # roll-off limits: f_L → 1 at high κL, f_η → 1 at low κη
  @test large_scale_factor(PopeLargeScale(6.78, 2.0), 1e6) ≈ 1.0 atol = 1e-3
  @test dissipation_factor(PopeDissipation(0.40, 5.2), 1e-6) ≈ 1.0 atol = 1e-3

  @test provenance(E).valid_Reλ == (30.0, Inf)
end


@testset "StructureFunctions — Kolmogorov1941" begin
  k41 = Kolmogorov1941()
  r = 0.05
  @test k41 isa StructureFunction
  @test structure_function(k41, r, FP; order = 3) ≈ -(4 / 5) * 0.1 * r         # exact 4/5 law
  @test structure_function(k41, r, FP; order = 2) ≈ 2.0 * (0.1 * r)^(2 / 3)     # 2/3 law, C₂ = 2
  @test structure_function(Kolmogorov1941(C₂ = 2.2), r, FP; order = 2) ≈ 2.2 * (0.1 * r)^(2 / 3)
  @test_throws ArgumentError structure_function(k41, r, FP; order = 4)         # only 2 and 3
  @test provenance(k41).citation isa String
end


@testset "Scalings — Sreenivasan1998 dissipation constant" begin
  @test Sreenivasan1998() isa DissipationScaling
  @test scaling(Sreenivasan1998(), FP) == 0.5                    # plateau, no finite-Re correction
  @test scaling(Sreenivasan1998(asymptote = 0.4), FP) == 0.4
  @test scaling(Sreenivasan1998(correction = 100.0), FP) ≈ 0.5 * (1 + 100.0 / taylor_reynolds(FP))
end


@testset "Phenomenology is not re-exported by the umbrella" begin
  # the laws must NOT leak into `using GBGIsotropicTurbulence`
  @test !isdefined(GBGIsotropicTurbulence, :Pope2000)
  @test !isdefined(GBGIsotropicTurbulence, :FlowParameters)
  # but the submodule namespace IS reachable, and resolves to the same binding
  @test isdefined(GBGIsotropicTurbulence, :Phenomenology)
  @test GBGIsotropicTurbulence.Phenomenology.Spectra.Pope2000 === Pope2000
end
