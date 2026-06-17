# Integrator tests — the decisive check is temporal convergence order: IFLowStorageRK3 must be
# third-order and IFRK2 second-order in Δt. Measured by self-convergence (Cauchy): integrating the
# same unforced decay to a fixed time with steps Δt, Δt/2, Δt/4, the ratio ‖u(Δt)−u(Δt/2)‖ /
# ‖u(Δt/2)−u(Δt/4)‖ ≈ 2^p for order p (≈8 for RK3, ≈4 for RK2). Plus RK3 forced-HIT invariants and
# the per-scheme CFL.

using GBGIsotropicTurbulence
using GBGPeriodicFields: divergence, l2norm, field_data
using Random
using Test


# Integrate from a copy of `uh0` with a fixed `dt` for `nsteps`, returning the final spectral field.
function integrate_fixed(integrator, ops, ws, uh0, forcing, ν, dt, nsteps)
  uh = spectral_vector(ops)
  copyto!(field_data(uh), field_data(uh0))
  for _ in 1:nsteps
    velocity_vorticity!(ws.velocity, ws.vorticity_start, uh, ops, ws)
    step!(integrator, uh, ops, ws, forcing, ν, dt)
  end
  return uh
end

# L²-of-the-difference of two spectral fields (raw coefficient norm; only the ratio matters here).
diffnorm(a, b) = sqrt(sum(abs2, field_data(a) .- field_data(b)))


@testset "integrators" begin
  T = Float64
  N = 16
  L = 2π
  ν = 0.1
  ops = SpectralOperators(N, L; scalar_type = T)
  ws = VelocityWorkspace(ops)

  uh0 = spectral_vector(ops)
  random_solenoidal_velocity!(uh0, ops; energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(7))
  dealias!(uh0, ops)

  Tfinal = 0.5
  n = 8

  @testset "temporal convergence order" begin
    rk3 = IFLowStorageRK3()
    u1 = integrate_fixed(rk3, ops, ws, uh0, NoForcing(), ν, Tfinal / n, n)
    u2 = integrate_fixed(rk3, ops, ws, uh0, NoForcing(), ν, Tfinal / (2n), 2n)
    u4 = integrate_fixed(rk3, ops, ws, uh0, NoForcing(), ν, Tfinal / (4n), 4n)
    rk3_ratio = diffnorm(u1, u2) / diffnorm(u2, u4)

    rk2 = IFRK2()
    v1 = integrate_fixed(rk2, ops, ws, uh0, NoForcing(), ν, Tfinal / n, n)
    v2 = integrate_fixed(rk2, ops, ws, uh0, NoForcing(), ν, Tfinal / (2n), 2n)
    v4 = integrate_fixed(rk2, ops, ws, uh0, NoForcing(), ν, Tfinal / (4n), 4n)
    rk2_ratio = diffnorm(v1, v2) / diffnorm(v2, v4)

    @test 5.0 < rk3_ratio < 12.0      # third order ⇒ ≈ 8
    @test 3.0 < rk2_ratio < 6.0       # second order ⇒ ≈ 4
    @test rk3_ratio > rk2_ratio       # RK3 converges faster than RK2
  end

  @testset "IFLowStorageRK3 forced-HIT invariants" begin
    band = BandRescaling(ops; energy = 0.5, lowest_shell = 1, highest_shell = 2)
    integrator = IFLowStorageRK3()
    uh = spectral_vector(ops)
    copyto!(field_data(uh), field_data(uh0))
    Δx = L / N
    cfl = recommended_cfl(integrator)
    energies = T[]
    for _ in 1:200
      velocity_vorticity!(ws.velocity, ws.vorticity_start, uh, ops, ws)
      dt = cfl * Δx / max(max_speed(ws.velocity), 1e-6)
      push!(energies, kinetic_energy(ws.velocity))
      step!(integrator, uh, ops, ws, band, ν, dt)
    end
    @test all(isfinite, energies)
    @test 0.05 < energies[end] < 10.0
    rel_div = l2norm(divergence(uh, ops.multipliers)) / (l2norm(uh) + 1e-30)
    @test rel_div < 1e-8

    velocity_vorticity!(ws.velocity, ws.vorticity_start, uh, ops, ws)
    dt = cfl * Δx / max(max_speed(ws.velocity), 1e-6)
    step!(integrator, uh, ops, ws, band, ν, dt)                       # warm up
    bytes = @allocated step!(integrator, uh, ops, ws, band, ν, dt)
    field_bytes = length(field_data(uh)) * sizeof(eltype(field_data(uh)))
    @test bytes < field_bytes
  end

  @testset "recommended_cfl / default" begin
    @test recommended_cfl(IFLowStorageRK3()) > recommended_cfl(IFRK2())
    @test 0 < recommended_cfl(IFRK2()) < 1
    @test 0 < recommended_cfl(IFLowStorageRK3()) < 1
    @test default_integrator() isa IFLowStorageRK3
  end
end
