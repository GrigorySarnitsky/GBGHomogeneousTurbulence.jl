# Slice 1 — the velocity vertical slice: forced HIT advanced by IF-RK2, carrying an inert (zero)
# passive scalar. Checks the core physics and the GPU-relevant discipline — finite/bounded energy,
# divergence-free to roundoff, no field-sized per-step allocation — and that the passive scalar stays
# exactly zero (it must not perturb the velocity).

using GBGIsotropicTurbulence
using GBGPeriodicFields: divergence, l2norm, field_data
using Random
using Test


@testset "velocity slice — forced HIT, IF-RK2 (scalar inert)" begin
  T = Float64
  N = 32
  L = 2π
  ν = 5.0e-2

  ops = SpectralOperators(N, L; scalar_type = T)
  ws = Workspace(ops)
  physics = Physics(viscosity = ν,
                    velocity_forcing = BandRescaling(ops; energy = 0.6, lowest_shell = 1, highest_shell = 2))
  integrator = IFRK2()

  uh = spectral_vector(ops)
  random_solenoidal_velocity!(uh, ops; energy = 0.6, peak_wavenumber = 2.0, rng = MersenneTwister(42))
  dealias!(uh, ops)
  phih = scalar_spectral(ops)                          # zero scalar (passive ⇒ stays zero)

  Δx = L / N
  cfl = 0.5
  nsteps = 300
  energies = T[]
  for n in 1:nsteps
    velocity_vorticity!(ws.velocity, ws.vorticity_start, uh, ops, ws)
    dt = cfl * Δx / max(max_speed(ws.velocity), 1e-6)
    push!(energies, kinetic_energy(ws.velocity))
    step!(integrator, uh, phih, ops, ws, physics, dt)
  end

  @test all(isfinite, energies)
  @test isfinite(kinetic_energy(uh))
  @test 0.1 < energies[end] < 10.0

  early = sum(@view energies[101:200]) / 100
  late = sum(@view energies[201:300]) / 100
  @test abs(late - early) / early < 1.0

  relative_divergence = l2norm(divergence(uh, ops.multipliers)) / (l2norm(uh) + 1e-30)
  @test relative_divergence < 1e-8

  @test scalar_variance(phih) < 1e-20                  # the passive scalar stayed exactly zero

  velocity_vorticity!(ws.velocity, ws.vorticity_start, uh, ops, ws)
  dt = cfl * Δx / max(max_speed(ws.velocity), 1e-6)
  step!(integrator, uh, phih, ops, ws, physics, dt)                            # warm up
  step_bytes = @allocated step!(integrator, uh, phih, ops, ws, physics, dt)
  field_bytes = length(field_data(uh)) * sizeof(eltype(field_data(uh)))
  @test step_bytes < field_bytes
end
