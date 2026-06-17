# Passive-scalar tests.
#  1. Diffusion exactness: with zero velocity the scalar evolves by the integrating factor alone, so
#     φ̂(T) = exp(-κ|k|²T) φ̂(0) to roundoff — verifies the scalar integrating factor and that the
#     advection term vanishes when u = 0.
#  2. Temporal convergence of the coupled (velocity + scalar) solve, measured on the scalar field:
#     third order for IFLowStorageRK3.
#  3. Mean conservation: the conservative form -∇·(uφ) leaves the k = 0 (mean) mode untouched.

using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data
using Random
using Test


function integrate_coupled(integrator, ops, ws, uh0, phih0, physics, dt, nsteps)
  uh = spectral_vector(ops)
  phih = scalar_spectral(ops)
  copyto!(field_data(uh), field_data(uh0))
  copyto!(field_data(phih), field_data(phih0))
  for _ in 1:nsteps
    velocity_vorticity!(ws.velocity, ws.vorticity_start, uh, ops, ws)
    step!(integrator, uh, phih, ops, ws, physics, dt)
  end
  return uh, phih
end

diffnorm(a, b) = sqrt(sum(abs2, field_data(a) .- field_data(b)))


@testset "passive scalar" begin
  T = Float64
  N = 16
  L = 2π
  ν = 0.1
  ops = SpectralOperators(N, L; scalar_type = T)
  ws = Workspace(ops)

  @testset "diffusion exactness (u = 0)" begin
    Sc = 0.7
    κ = ν / Sc
    uh0 = spectral_vector(ops)                                   # zero velocity
    phih0 = scalar_spectral(ops)
    random_scalar!(phih0, ops; variance = 1.0, peak_wavenumber = 2.0, rng = MersenneTwister(3))
    physics = Physics(viscosity = ν, schmidt = Sc)               # unforced
    dt = 0.02
    nsteps = 25
    total_time = dt * nsteps
    _, phih = integrate_coupled(IFLowStorageRK3(), ops, ws, uh0, phih0, physics, dt, nsteps)

    expected = field_data(phih0) .* complex.(exp.(-κ .* ops.squared_wavenumber .* total_time))
    relative_error = sqrt(sum(abs2, field_data(phih) .- expected)) / sqrt(sum(abs2, expected))
    @test relative_error < 1e-10
  end

  @testset "temporal convergence (RK3, coupled)" begin
    uh0 = spectral_vector(ops)
    random_solenoidal_velocity!(uh0, ops; energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(1))
    dealias!(uh0, ops)
    phih0 = scalar_spectral(ops)
    random_scalar!(phih0, ops; variance = 1.0, peak_wavenumber = 2.0, rng = MersenneTwister(2))
    physics = Physics(viscosity = ν)                             # Sc = 1, unforced

    rk3 = IFLowStorageRK3()
    Tfinal = 0.4
    n = 8
    _, p1 = integrate_coupled(rk3, ops, ws, uh0, phih0, physics, Tfinal / n, n)
    _, p2 = integrate_coupled(rk3, ops, ws, uh0, phih0, physics, Tfinal / (2n), 2n)
    _, p4 = integrate_coupled(rk3, ops, ws, uh0, phih0, physics, Tfinal / (4n), 4n)
    ratio = diffnorm(p1, p2) / diffnorm(p2, p4)
    @test 5.0 < ratio < 12.0
  end

  @testset "mean conservation (conservative form)" begin
    uh0 = spectral_vector(ops)
    random_solenoidal_velocity!(uh0, ops; energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(5))
    dealias!(uh0, ops)
    phih0 = scalar_spectral(ops)
    random_scalar!(phih0, ops; variance = 1.0, peak_wavenumber = 2.0, rng = MersenneTwister(6))
    field_data(phih0)[1, 1, 1] = 3.0 + 0.0im                    # impose a nonzero mean (the k=0 mode)
    mean_before = field_data(phih0)[1, 1, 1]

    physics = Physics(viscosity = ν,
                      velocity_forcing = BandRescaling(ops; energy = 0.5, lowest_shell = 1, highest_shell = 2))
    _, phih = integrate_coupled(IFLowStorageRK3(), ops, ws, uh0, phih0, physics, 0.02, 30)
    @test field_data(phih)[1, 1, 1] ≈ mean_before
  end
end
