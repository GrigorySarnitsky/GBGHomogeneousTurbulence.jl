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


@testset "Scalings — dissipation constant and Kolmogorov constant" begin
  @test Sreenivasan1998() isa ScalingLaw
  @test scaling(Sreenivasan1998(), FP) == 0.5                    # plateau, no finite-Re correction
  @test scaling(Sreenivasan1998(asymptote = 0.4), FP) == 0.4
  @test scaling(Sreenivasan1998(correction = 100.0), FP) ≈ 0.5 * (1 + 100.0 / taylor_reynolds(FP))
  @test Sreenivasan1995() isa ScalingLaw
  @test scaling(Sreenivasan1995(), FP) == 1.5                    # Kolmogorov constant, Re-independent
  @test scaling(Sreenivasan1995(C_K = 1.6), FP) == 1.6

  @test Li2008() isa ScalingLaw
  @test scaling(Li2008(), FP) == 0.9                             # the box-normalized group value G
  let k = 1.5, L = 2π, ε = stationary_dissipation(Li2008(), k, L)
    @test k / (L * ε)^(2 / 3) ≈ 0.9                              # stationary_dissipation inverts k/(Lε)^{2/3}=G
  end
  @test stationary_dissipation(Li2008(constant = 1.0), 1.0, 1.0) == 1.0   # ε = (k/G)^{3/2}/L
end


@testset "Spectra — Pao1965 and dissipation factors" begin
  pao = Pao1965()
  @test pao isa ModelSpectrum
  comp(κ) = spectrum(pao, κ, FP) * κ^(5 / 3) / 0.1^(2 / 3)
  @test isapprox(comp(1.0), 1.5; atol = 0.05)                             # ≈ C_K in the inertial range
  @test spectrum(pao, 10.0, FP) > spectrum(pao, 100.0, FP) > 0            # inertial then cutoff
  @test isapprox(dissipation_factor(PaoDissipation(1.5), 1e-6), 1.0; atol = 1e-3)
  @test large_scale_factor(UnitLargeScale(), 3.0) == 1.0
  # closure-predicted exponential cutoff: f_η → 1 in the inertial range, decays with κη
  @test isapprox(dissipation_factor(ExponentialDissipation(0.6), 1e-8), 1.0; atol = 1e-6)
  @test dissipation_factor(ExponentialDissipation(0.6), 5.0) <
        dissipation_factor(ExponentialDissipation(0.6), 1.0)
  @test isapprox(dissipation_factor(SaffmanDissipation(), 1e-6), 1.0; atol = 1e-6)   # Gaussian cutoff → 1
  @test dissipation_factor(SaffmanDissipation(), 2.0) < dissipation_factor(SaffmanDissipation(), 1.0)
end


# Physical self-consistency verification: check every model against the relations it MUST satisfy
# (asymptotic slopes, factor limits, structure-function exponents) — catches wrong exponents /
# coefficients / signs without a reference library. See the discussion in ARCHITECTURE §4.7.
@testset "Physical self-consistency — spectrum slopes and exponents" begin
  # very high Reynolds number ⇒ a wide inertial range (L/η ≈ 3×10⁴), so slopes are clean
  hi = FlowParameters(viscosity = 1e-7, dissipation = 0.1, rms_velocity = 1.0,
                      integral_scale = 1.0, scalar_dissipation = 0.05)
  sl(g, x) = (log(g(x * 1.001)) - log(g(x / 1.001))) / (log(x * 1.001) - log(x / 1.001))

  # every model spectrum has the Kolmogorov -5/3 inertial slope
  for m in (Pope2000(), VonKarman1948(), Pao1965(), ObukhovCorrsin1949())
    @test sl(κ -> spectrum(m, κ, hi), 100.0) ≈ -5 / 3 atol = 0.02
  end
  # the low-wavenumber slope is the energy-containing exponent σ
  @test sl(κ -> spectrum(Pope2000(), κ, hi), 1e-4) ≈ 2.0 atol = 0.01     # Saffman-type σ = 2
  @test sl(κ -> spectrum(VonKarman1948(), κ, hi), 1e-4) ≈ 4.0 atol = 0.01 # Batchelor-type σ = 4

  # every roll-off factor tends to 1 in the inertial range
  @test large_scale_factor(PopeLargeScale(6.78, 2.0), 1e8) ≈ 1.0 atol = 1e-4
  @test large_scale_factor(VonKarmanLarge(1.0), 1e8) ≈ 1.0 atol = 1e-4
  for d in (PopeDissipation(0.4, 5.2), PaoDissipation(1.5), ExponentialDissipation(0.6), SaffmanDissipation())
    @test dissipation_factor(d, 1e-8) ≈ 1.0 atol = 1e-6
  end

  # every intermittency model is exact at ζ_3 = 1 and bends below the self-similar p/3 for p > 3
  for m in (Kolmogorov1941(), Kolmogorov1962(), SheLeveque1994())
    @test scaling_exponent(m, 3) ≈ 1.0
    @test scaling_exponent(m, 6) ≤ 2.0 + 1e-9
    @test scaling_exponent(m, 2) ≥ 2 / 3 - 1e-9
  end
end


@testset "StructureFunctions — K62 log-normal exponents" begin
  k62 = Kolmogorov1962()
  @test scaling_exponent(k62, 3) ≈ 1.0                                    # exact at p = 3
  @test scaling_exponent(k62, 6) ≈ 2 - 0.25                               # ζ_6 = 2 − μ
  @test scaling_exponent(k62, 2) ≈ 2 / 3 - (0.25 / 18) * 2 * (2 - 3)
  @test scaling_exponent(k62, 6) < scaling_exponent(Kolmogorov1941(), 6)  # bends below p/3
end


@testset "StructureFunctions — Yaglom 4/3 and Lundgren finite-Re 4/5" begin
  fpφ = FlowParameters(viscosity = 1e-3, dissipation = 0.1, rms_velocity = 1.0,
                       integral_scale = 1.0, scalar_dissipation = 0.05)
  r = 0.05
  @test structure_function(Yaglom1949(), r, fpφ; order = 3) ≈ -(2 / 3) * 0.05 * r   # -(2/3)ε_φ r (full-variance ε_φ; the classical 4/3 pairs with the half-variance rate)
  @test_throws ArgumentError structure_function(Yaglom1949(), r, FP; order = 3)     # no scalar dissipation
  @test_throws ArgumentError structure_function(Yaglom1949(), r, fpφ; order = 2)
  # Lundgren's finite-Re 4/5 law, reduced from the exact -4/5 εr at finite Re_λ
  @test structure_function(Lundgren2002(), r, FP; order = 3) ≈
        -(4 / 5 - 8.45 / taylor_reynolds(FP)^(2 / 3)) * 0.1 * r
  @test abs(structure_function(Lundgren2002(), r, FP; order = 3)) <
        abs(structure_function(Kolmogorov1941(), r, FP; order = 3))
end


@testset "Spectra — VonKarman1948 and ObukhovCorrsin1949" begin
  vk = VonKarman1948()
  @test vk isa EnergySpectrum && vk isa ModelSpectrum
  # von Kármán gives the κ⁴ energy-containing range at low κ: E/κ⁴ → const
  @test spectrum(vk, 0.005, FP) / 0.005^4 ≈ spectrum(vk, 0.010, FP) / 0.010^4 rtol = 0.02
  @test dissipation_factor(UnitDissipation(), 3.0) == 1.0                  # no viscous cutoff
  @test large_scale_factor(VonKarmanLarge(1.0), 1e6) ≈ 1.0 atol = 1e-3     # f_L → 1 in the inertial range

  fpφ = FlowParameters(viscosity = 1e-3, dissipation = 0.1, rms_velocity = 1.0,
                       integral_scale = 1.0, scalar_dissipation = 0.05)
  oc = ObukhovCorrsin1949()
  @test oc isa ScalarSpectrum
  @test spectrum(oc, 10.0, fpφ) ≈ 0.67 * 0.05 * 0.1^(-1 / 3) * 10.0^(-5 / 3)
  @test_throws ArgumentError spectrum(oc, 10.0, FP)                        # FP has no scalar dissipation
end


@testset "StructureFunctions — She–Lévêque intermittency exponents" begin
  sl, k41 = SheLeveque1994(), Kolmogorov1941()
  @test sl isa StructureFunction
  @test scaling_exponent(sl, 3) ≈ 1.0                           # exact at p = 3 (the 4/5 law)
  @test scaling_exponent(k41, 3) ≈ 1.0
  @test scaling_exponent(k41, 2) ≈ 2 / 3                        # K41 self-similar ζ_p = p/3
  @test scaling_exponent(sl, 2) ≈ 2 / 9 + 2 * (1 - (2 / 3)^(2 / 3))
  @test scaling_exponent(sl, 6) < scaling_exponent(k41, 6)      # intermittency bends p > 3 down
  @test provenance(sl).valid_Reλ == (200.0, Inf)
end


@testset "Phenomenology is not re-exported by the umbrella" begin
  # the laws must NOT leak into `using GBGIsotropicTurbulence`
  @test !isdefined(GBGIsotropicTurbulence, :Pope2000)
  @test !isdefined(GBGIsotropicTurbulence, :FlowParameters)
  # but the submodule namespace IS reachable, and resolves to the same binding
  @test isdefined(GBGIsotropicTurbulence, :Phenomenology)
  @test GBGIsotropicTurbulence.Phenomenology.Spectra.Pope2000 === Pope2000
end
