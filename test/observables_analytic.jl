# Closed forms for the observables. Each value here is derived by hand from a field sampled from a
# formula, never from another package operation, so these are the analytic oracles the oracle
# registry cites (RULE.TEST.ORACLE_INDEPENDENT).
#
# The velocity u = (A sin y, B sin z, C sin x) is divergence-free (each component is independent of its
# own coordinate) and lies entirely in shell 1, so on the 2π box:
#   k   = ½⟨|u|²⟩ = (A² + B² + C²)/4;
#   ω   = ∇ × u = −(B cos z, C cos x, A cos y), so ε = ν⟨|ω|²⟩ = ν(A² + B² + C²)/2;
#   E   is all in shell 1, so E(1) Δκ = k with Δκ = 1, and L₁₁ = (3π/4) ∫E/κ / ∫E = 3π/4;
#   max |u| = √(A² + B² + C²), reached where every sine is ±1, which the 16-point grid samples;
#   S   = 0: the strain has zero diagonal and off-diagonals ½A cos y, ½B cos z, ½C cos x, whose triple
#         product averages to zero.
# The scalar φ = D sin x gives ⟨φ²⟩ = D²/2 and ε_φ = 2ϰ⟨|∇φ|²⟩ = ϰD².
using Test
using GBGHomogeneousTurbulence
using GBGPeriodicFields: VectorFieldPhysical, ScalarFieldPhysical, to_spectral!, to_physical!, multiply!,
                         symmetric_gradient, inner, weighted_inner
using Logging

const N = 16
const L = 2π
const A, B, C, D = 0.7, -0.4, 1.1, 0.9
const ν, ϰ = 0.03, 0.05

domain_for(strategy) = FixedDomain(grid_points_per_axis = N, side_length = L, dealiasing = strategy,
                                   element_type = Float64, array_family = Array)

function analytic_velocity(d)
  u = VectorFieldPhysical(Array, (x, y, z) -> (A * sin(y), B * sin(z), C * sin(x)), d.grid; layout = d.layout)
  û = new_vector_field_spectral(d)
  to_spectral!(û, u, d.transform_plans)
  return û
end

function analytic_scalar(d)
  φ = ScalarFieldPhysical(Array, (x, y, z) -> D * sin(x), d.grid; layout = d.layout)
  φ̂ = new_scalar_field_spectral(d)
  to_spectral!(φ̂, φ, d.transform_plans)
  return φ̂
end


@testset "observables against closed forms" begin
  d = domain_for(TwoThirds())
  û, φ̂ = analytic_velocity(d), analytic_scalar(d)
  squares = A^2 + B^2 + C^2

  @test kinetic_energy(û) ≈ squares / 4 rtol = 1e-13
  @test dissipation(û, d, ν) ≈ ν * squares / 2 rtol = 1e-13
  pair = kinetic_energy_and_dissipation(û, d, ν)
  @test pair.kinetic_energy ≈ squares / 4 rtol = 1e-13
  @test pair.dissipation ≈ ν * squares / 2 rtol = 1e-13
  @test scalar_variance(φ̂) ≈ D^2 / 2 rtol = 1e-13
  @test scalar_dissipation(φ̂, d, ϰ) ≈ ϰ * D^2 rtol = 1e-13
  scalar_pair = scalar_variance_and_dissipation(φ̂, d, ϰ)
  @test scalar_pair.scalar_variance ≈ D^2 / 2 rtol = 1e-13
  @test scalar_pair.scalar_dissipation ≈ ϰ * D^2 rtol = 1e-13
  # the fused pair against its two single calls: the dissipation bitwise, the variance to roundoff
  @test scalar_pair.scalar_dissipation == scalar_dissipation(φ̂, d, ϰ)
  @test scalar_pair.scalar_variance ≈ scalar_variance(φ̂) rtol = 1e-14
  @test scalar_variance_and_dissipation(φ̂, d, 1.0f0).scalar_dissipation isa Float64

  κ, E = energy_spectrum(û, d)
  @test κ[2] == 1.0
  @test E[2] ≈ squares / 4 rtol = 1e-13                    # all of k in shell 1, Δκ = 1
  @test sum(E) ≈ E[2] rtol = 1e-13                         # and nothing elsewhere
  @test integral_scale(û, d) ≈ 3π / 4 rtol = 1e-12
  # the spectrum method: the field method measures the spectrum and hands it on, so the two agree
  # exactly, and a spectrum written by hand gives L₁₁ = (3π/4) Σ(E/κ)/ΣE with the κ = 0 shell left out
  @test integral_scale(energy_spectrum(û, d)) == integral_scale(û, d)
  two_shells = (; wavenumbers = [0.0, 1.0, 2.0], energy = [5.0, 2.0, 1.0])
  @test integral_scale(two_shells) ≈ 3π / 4 * (2.0 / 1.0 + 1.0 / 2.0) / (2.0 + 1.0) rtol = 1e-14
  @test_throws ArgumentError integral_scale((; wavenumbers = [0.0, 1.0], energy = [5.0, 0.0]))

  u = new_vector_field_physical(d)
  to_physical!(u, û, d.transform_plans, new_vector_field_spectral(d))
  @test max_speed(u) ≈ sqrt(squares) rtol = 1e-13

  # the skewness vanishes for this field, and is odd in the velocity for any field
  @test abs(derivative_skewness(û, d)) < 1e-12
  seeded = new_vector_field_spectral(d)
  random_solenoidal_velocity_spectral!(seeded, d, 1.0; envelope_wavenumber = 3.0)
  S = derivative_skewness(seeded, d)
  negated = multiply!(deepcopy(seeded), -1.0, seeded)
  @test S != 0
  @test derivative_skewness(negated, d) ≈ -S rtol = 1e-12
end


@testset "the skewness denominator: the Dirichlet route equals the direct ⟨S:S⟩" begin
  # `derivative_skewness` reads ⟨S:S⟩ = ½⟨|ω|²⟩ = ½Σ|κ|²|û|² from û rather than from the physical
  # strain tensor. The identity is exact for a solenoidal field on Fourier sums — the cross term
  # ⟨∂_{x_j}u_i ∂_{x_i}u_j⟩ vanishes by incompressibility — so the two routes agree to round-off. The
  # direct route is computed here explicitly, from the strain in physical representation.
  for (T, tolerance) in ((Float64, 1e-12), (Float32, 1e-5))
    d = FixedDomain(grid_points_per_axis = 32, side_length = 2π, dealiasing = TwoThirds(), element_type = T,
                    array_family = Array)
    û = new_vector_field_spectral(d)
    random_solenoidal_velocity_spectral!(û, d, 1.5; envelope_wavenumber = 4.0)
    S = new_tensor_field_physical(d)
    to_physical!(S, symmetric_gradient(û, d.multipliers), d.transform_plans)
    @test weighted_inner(û, d.squared_wavenumber_kernel) / 2 ≈ inner(S, S) rtol = tolerance
  end
end


@testset "the cutoffs and the integrating factor, in closed form" begin
  for (strategy, resolved, retained) in ((TwoThirds(), 2 / 3, 2 / 3), (HouLi(), 4 / 5, 1.0),
                                         (PhaseShift(), 2 * sqrt(2) / 3, 2 * sqrt(2) / 3))
    d = domain_for(strategy)
    @test max_resolved_wavenumber(d) ≈ resolved * (N / 2) * (2π / L) rtol = 1e-14
    @test max_retained_wavenumber(d) ≈ retained * (N / 2) * (2π / L) rtol = 1e-14
  end

  d = domain_for(TwoThirds())
  generator = ResolvedGenerator(d, FlowConditions(viscosity = ν, schmidt = 0.5, velocity_forcing = NoForcing(),
                                                  scalar_forcing = NoForcing()); scalar = true)
  τ = 0.01
  factor = velocity_integrating_factor(generator, τ)
  @test factor.coefficient ≈ -ν * τ && factor.offset_scale == τ && factor.offset === nothing
  scalar_factor = scalar_integrating_factor(generator, τ)
  @test scalar_factor.coefficient ≈ -(ν / 0.5) * τ && scalar_factor.offset_scale == τ
end


@testset "the CFL ceiling keeps the advective rate inside the scheme's stability limit" begin
  # C·κ_max·Δx is the rate times the step. The same ceiling holds it at one value under every
  # dealiasing strategy, and for a three-stage third-order scheme below √3, the imaginary-axis
  # stability limit every such explicit scheme shares.
  Δx = L / N
  for scheme in (IFLowStorageRK3(), IFSSPRK3())
    products = [recommended_cfl(scheme, domain_for(s)) * max_retained_wavenumber(domain_for(s)) * Δx
                for s in (TwoThirds(), HouLi(), PhaseShift())]
    @test all(p -> p ≈ products[1], products)
    @test products[1] < sqrt(3)
  end
end
