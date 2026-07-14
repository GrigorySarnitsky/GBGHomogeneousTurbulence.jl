# Integrator tests — the decisive check is temporal convergence order: IFLowStorageRK3 must be
# third-order and IFRK2 second-order in Δt. Measured by self-convergence (Cauchy): integrating the
# same unforced decay to a fixed time with steps Δt, Δt/2, Δt/4, the ratio ‖u(Δt)−u(Δt/2)‖ /
# ‖u(Δt/2)−u(Δt/4)‖ ≈ 2^p for order p (≈8 for RK3, ≈4 for RK2). Plus RK3 forced-HIT invariants and
# the per-scheme CFL. (Velocity-only: the scalar is carried inert at zero.)

using GBGIsotropicTurbulence
using GBGPeriodicFields: divergence, l2norm, field_data
using Random
using Test


# Integrate the velocity from a copy of `û0` with a fixed `dt` for `nsteps`, carrying a zero scalar.
function integrate_fixed(integrator, domain, buffers, û0, conditions, dt, nsteps)
  û = spectral_vector(domain)
  copyto!(field_data(û), field_data(û0))
  φ̂ = scalar_spectral(domain)
  for _ in 1:nsteps
    velocity_to_physical!(buffers.velocity_physical, û, domain, buffers.velocity_copy)
    vorticity_to_physical!(buffers.vorticity_start, û, domain, buffers.vorticity_spectral)
    step!(integrator, û, φ̂, domain, buffers, conditions, dt)
  end
  return û
end

diffnorm(a, b) = sqrt(sum(abs2, field_data(a) .- field_data(b)))


@testset "integrators" begin
  T = Float64
  N = 16
  L = 2π
  ν = 0.1
  domain = FixedDomain(N, L; element_type = T, dealiasing = TwoThirds(), array_type = Array)
  buffers = IntegratorBuffers(domain; scalar = true)

  û0 = spectral_vector(domain)
  random_solenoidal_velocity!(û0, domain; kinetic_energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(7))
  dealias!(û0, domain)

  Tfinal = 0.5
  n = 8

  @testset "temporal convergence order" begin
    unforced = FlowConditions(viscosity = ν, schmidt = 1.0, velocity_forcing = NoForcing(), scalar_forcing = NoForcing())
    rk3 = IFLowStorageRK3()
    u1 = integrate_fixed(rk3, domain, buffers, û0, unforced, Tfinal / n, n)
    u2 = integrate_fixed(rk3, domain, buffers, û0, unforced, Tfinal / (2n), 2n)
    u4 = integrate_fixed(rk3, domain, buffers, û0, unforced, Tfinal / (4n), 4n)
    rk3_ratio = diffnorm(u1, u2) / diffnorm(u2, u4)

    rk2 = IFRK2()
    v1 = integrate_fixed(rk2, domain, buffers, û0, unforced, Tfinal / n, n)
    v2 = integrate_fixed(rk2, domain, buffers, û0, unforced, Tfinal / (2n), 2n)
    v4 = integrate_fixed(rk2, domain, buffers, û0, unforced, Tfinal / (4n), 4n)
    rk2_ratio = diffnorm(v1, v2) / diffnorm(v2, v4)

    @test 5.0 < rk3_ratio < 12.0      # third order ⇒ ≈ 8
    @test 3.0 < rk2_ratio < 6.0       # second order ⇒ ≈ 4
    @test rk3_ratio > rk2_ratio       # RK3 converges faster than RK2
  end

  @testset "IFLowStorageRK3 forced-HIT invariants" begin
    conditions = FlowConditions(viscosity = ν,
                      velocity_forcing = BandRescaling(domain; target = 0.5, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, scalar_forcing = NoForcing())
    integrator = IFLowStorageRK3()
    û = spectral_vector(domain)
    copyto!(field_data(û), field_data(û0))
    φ̂ = scalar_spectral(domain)
    Δx = L / N
    cfl = recommended_cfl(integrator, domain)
    energies = T[]
    for _ in 1:200
      velocity_to_physical!(buffers.velocity_physical, û, domain, buffers.velocity_copy)
      vorticity_to_physical!(buffers.vorticity_start, û, domain, buffers.vorticity_spectral)
      dt = cfl * Δx / max(max_speed(buffers.velocity_physical), 1e-6)
      push!(energies, kinetic_energy(buffers.velocity_physical))
      step!(integrator, û, φ̂, domain, buffers, conditions, dt)
    end
    @test all(isfinite, energies)
    @test 0.05 < energies[end] < 10.0
    rel_div = l2norm(divergence(û, domain.multipliers)) / (l2norm(û) + 1e-30)
    @test rel_div < 1e-8

    velocity_to_physical!(buffers.velocity_physical, û, domain, buffers.velocity_copy)
    vorticity_to_physical!(buffers.vorticity_start, û, domain, buffers.vorticity_spectral)
    dt = cfl * Δx / max(max_speed(buffers.velocity_physical), 1e-6)
    step!(integrator, û, φ̂, domain, buffers, conditions, dt)                       # warm up
    bytes = @allocated step!(integrator, û, φ̂, domain, buffers, conditions, dt)
    field_bytes = length(field_data(û)) * sizeof(eltype(field_data(û)))
    @test bytes < field_bytes
  end

  @testset "recommended_cfl" begin
    @test recommended_cfl(IFLowStorageRK3(), domain) > recommended_cfl(IFRK2(), domain)
    @test 0 < recommended_cfl(IFRK2(), domain) < 1
    @test 0 < recommended_cfl(IFLowStorageRK3(), domain) < 1
  end
end
