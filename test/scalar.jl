# Passive-scalar tests.
#  1. Diffusion exactness: with zero velocity the scalar evolves by the integrating factor alone, so
#     φ̂(T) = exp(-κ|k|²T) φ̂(0) to roundoff — verifies the scalar integrating factor and that the
#     advection term vanishes when u = 0.
#  2. Temporal convergence of the coupled (velocity + scalar) solve, measured on the scalar field:
#     third order for IFLowStorageRK3.
#  3. Mean conservation: the conservative form -∇·(uφ) leaves the k = 0 (mean) mode untouched.

using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data, gradient!, to_physical!, inner
using Random
using Test


function integrate_coupled(integrator, domain, buffers, û0, φ̂0, conditions, dt, nsteps)
  û = spectral_vector(domain)
  φ̂ = scalar_spectral(domain)
  copyto!(field_data(û), field_data(û0))
  copyto!(field_data(φ̂), field_data(φ̂0))
  for _ in 1:nsteps
    velocity_to_physical!(buffers.velocity_physical, û, domain, buffers.velocity_copy)
    vorticity_to_physical!(buffers.vorticity_start, û, domain, buffers.vorticity_spectral)
    step!(integrator, ResolvedFields(û, φ̂), domain, buffers, conditions, dt)
  end
  return û, φ̂
end

diffnorm(a, b) = sqrt(sum(abs2, field_data(a) .- field_data(b)))


@testset "passive scalar" begin
  T = Float64
  N = 16
  L = 2π
  ν = 0.1
  domain = FixedDomain(N, L; element_type = T, dealiasing = TwoThirds(), array_type = Array)
  buffers = IntegratorBuffers(domain; scalar = true)

  @testset "diffusion exactness (u = 0)" begin
    Sc = 0.7
    κ = ν / Sc
    û0 = spectral_vector(domain)                                   # zero velocity
    φ̂0 = scalar_spectral(domain)
    random_scalar!(φ̂0, domain; scalar_variance = 1.0, peak_wavenumber = 2.0, rng = MersenneTwister(3))
    conditions = FlowConditions(viscosity = ν, schmidt = Sc, velocity_forcing = NoForcing(), scalar_forcing = NoForcing())               # unforced
    dt = 0.02
    nsteps = 25
    total_time = dt * nsteps
    _, φ̂ = integrate_coupled(IFLowStorageRK3(), domain, buffers, û0, φ̂0, conditions, dt, nsteps)

    expected = field_data(φ̂0) .* complex.(exp.(-κ .* domain.squared_wavenumber .* total_time))
    relative_error = sqrt(sum(abs2, field_data(φ̂) .- expected)) / sqrt(sum(abs2, expected))
    @test relative_error < 1e-10
  end

  @testset "temporal convergence (RK3, coupled)" begin
    û0 = spectral_vector(domain)
    random_solenoidal_velocity!(û0, domain; kinetic_energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(1))
    dealias!(û0, domain)
    φ̂0 = scalar_spectral(domain)
    random_scalar!(φ̂0, domain; scalar_variance = 1.0, peak_wavenumber = 2.0, rng = MersenneTwister(2))
    conditions = FlowConditions(viscosity = ν, schmidt = 1.0, velocity_forcing = NoForcing(), scalar_forcing = NoForcing())                             # Sc = 1, unforced

    rk3 = IFLowStorageRK3()
    Tfinal = 0.4
    n = 8
    _, p1 = integrate_coupled(rk3, domain, buffers, û0, φ̂0, conditions, Tfinal / n, n)
    _, p2 = integrate_coupled(rk3, domain, buffers, û0, φ̂0, conditions, Tfinal / (2n), 2n)
    _, p4 = integrate_coupled(rk3, domain, buffers, û0, φ̂0, conditions, Tfinal / (4n), 4n)
    ratio = diffnorm(p1, p2) / diffnorm(p2, p4)
    @test 5.0 < ratio < 12.0
  end

  @testset "mean conservation (conservative form)" begin
    û0 = spectral_vector(domain)
    random_solenoidal_velocity!(û0, domain; kinetic_energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(5))
    dealias!(û0, domain)
    φ̂0 = scalar_spectral(domain)
    random_scalar!(φ̂0, domain; scalar_variance = 1.0, peak_wavenumber = 2.0, rng = MersenneTwister(6))
    field_data(φ̂0)[1, 1, 1] = 3.0 + 0.0im                    # impose a nonzero mean (the k=0 mode)
    mean_before = field_data(φ̂0)[1, 1, 1]

    conditions = FlowConditions(viscosity = ν,
                      velocity_forcing = BandRescaling(domain; target = 0.5, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, scalar_forcing = NoForcing())
    _, φ̂ = integrate_coupled(IFLowStorageRK3(), domain, buffers, û0, φ̂0, conditions, 0.02, 30)
    @test field_data(φ̂)[1, 1, 1] ≈ mean_before
  end

  @testset "scalar dissipation = Dirichlet energy" begin
    Sc = 0.7
    κ = ν / Sc
    φ̂ = scalar_spectral(domain)
    random_scalar!(φ̂, domain; scalar_variance = 1.0, peak_wavenumber = 3.0, rng = MersenneTwister(11))

    # ground truth: 2κ⟨|∇φ|²⟩ from the explicit physical gradient (the pre-fusion computation)
    grad_spectral = spectral_vector(domain)
    grad_physical = physical_vector(domain)
    gradient!(grad_spectral, φ̂, domain.multipliers)
    to_physical!(grad_physical, grad_spectral, domain.velocity_plans)
    expected = 2 * κ * inner(grad_physical, grad_physical)

    @test scalar_dissipation(φ̂, domain, κ) > 0
    @test scalar_dissipation(φ̂, domain, κ) ≈ expected
  end
end
