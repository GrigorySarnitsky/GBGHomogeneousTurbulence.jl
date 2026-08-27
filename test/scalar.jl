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


function integrate_coupled(scheme, domain, buffers, û0, φ̂0, conditions, dt, nsteps)
  generator = ResolvedGenerator(domain, conditions; scalar = true)
  cache = ObservablesCache(domain; scalar = true)
  û = new_vector_field_spectral(domain)
  φ̂ = new_scalar_field_spectral(domain)
  copyto!(field_data(û), field_data(û0))
  copyto!(field_data(φ̂), field_data(φ̂0))
  state = ResolvedFields(û, φ̂)
  deposit!(cache, state, domain, buffers)
  for _ in 1:nsteps
    step!(scheme, state, generator, domain, buffers, cache, dt)
    deposit!(cache, state, domain, buffers)
  end
  return û, φ̂
end

diffnorm(a, b) = sqrt(sum(abs2, field_data(a) .- field_data(b)))


@testset "passive scalar" begin
  T = Float64
  N = 16
  L = 2π
  ν = 0.1
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T, dealiasing = TwoThirds(), array_type = Array)
  buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = true)

  @testset "diffusion exactness (u = 0)" begin
    Sc = 0.7
    κ = ν / Sc
    û0 = new_vector_field_spectral(domain)                                   # zero velocity
    φ̂0 = new_scalar_field_spectral(domain)
    random_scalar_spectral!(φ̂0, domain; scalar_variance = 1.0, envelope_wavenumber = 2.0, rng = MersenneTwister(3))
    conditions = FlowConditions(viscosity = ν, schmidt = Sc, velocity_forcing = NoForcing(), scalar_forcing = NoForcing())               # unforced
    dt = 0.02
    nsteps = 25
    total_time = dt * nsteps
    _, φ̂ = integrate_coupled(IFLowStorageRK3(), domain, buffers, û0, φ̂0, conditions, dt, nsteps)

    m = domain.multipliers   # |κ|² from the axis vectors — the stored array is gone (decision 38)
    κ² = reshape(m.squared_wavenumber_1, :, 1, 1) .+ reshape(m.squared_wavenumber_2, 1, :, 1) .+
         reshape(m.squared_wavenumber_3, 1, 1, :)
    expected = field_data(φ̂0) .* complex.(exp.(-κ .* κ² .* total_time))
    relative_error = sqrt(sum(abs2, field_data(φ̂) .- expected)) / sqrt(sum(abs2, expected))
    @test relative_error < 1e-10
  end

  @testset "temporal convergence (RK3, coupled)" begin
    û0 = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û0, domain; kinetic_energy = 0.5, envelope_wavenumber = 2.0, rng = MersenneTwister(1))
    truncate_to_band!(û0, domain)
    φ̂0 = new_scalar_field_spectral(domain)
    random_scalar_spectral!(φ̂0, domain; scalar_variance = 1.0, envelope_wavenumber = 2.0, rng = MersenneTwister(2))
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
    û0 = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û0, domain; kinetic_energy = 0.5, envelope_wavenumber = 2.0, rng = MersenneTwister(5))
    truncate_to_band!(û0, domain)
    φ̂0 = new_scalar_field_spectral(domain)
    random_scalar_spectral!(φ̂0, domain; scalar_variance = 1.0, envelope_wavenumber = 2.0, rng = MersenneTwister(6))
    field_data(φ̂0)[1, 1, 1] = 3.0 + 0.0im                    # impose a nonzero mean (the k=0 mode)
    mean_before = field_data(φ̂0)[1, 1, 1]

    conditions = FlowConditions(viscosity = ν,
                      velocity_forcing = VarianceRescaling(domain; target = 0.5, over = :band, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, scalar_forcing = NoForcing())
    _, φ̂ = integrate_coupled(IFLowStorageRK3(), domain, buffers, û0, φ̂0, conditions, 0.02, 30)
    @test field_data(φ̂)[1, 1, 1] ≈ mean_before
  end

  @testset "scalar dissipation = Dirichlet energy" begin
    Sc = 0.7
    κ = ν / Sc
    φ̂ = new_scalar_field_spectral(domain)
    random_scalar_spectral!(φ̂, domain; scalar_variance = 1.0, envelope_wavenumber = 3.0, rng = MersenneTwister(11))

    # ground truth: 2κ⟨|∇φ|²⟩ from the explicit physical gradient (the pre-fusion computation)
    grad_spectral = new_vector_field_spectral(domain)
    grad_physical = new_vector_field_physical(domain)
    gradient!(grad_spectral, φ̂, domain.multipliers)
    to_physical!(grad_physical, grad_spectral, domain.transform_plans)
    expected = 2 * κ * inner(grad_physical, grad_physical)

    @test scalar_dissipation(φ̂, domain, κ) > 0
    @test scalar_dissipation(φ̂, domain, κ) ≈ expected
  end
end
