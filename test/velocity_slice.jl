# Slice 1 — the velocity vertical slice: forced HIT advanced by IF-RK2.
#
# Runs a short spin-up of forced homogeneous isotropic turbulence at 32³ and checks the core
# physics and the GPU-relevant discipline: the energy stays finite and bounded, the field stays
# divergence-free to roundoff, and a step allocates no field-sized memory.

using GBGIsotropicTurbulence
using Random
using Test


@testset "velocity slice — forced HIT, IF-RK2" begin
  T = Float64
  N = 32
  L = 2π
  ν = 5.0e-2

  ops = SpectralOperators(N, L; scalar_type = T)
  ws = VelocityWorkspace(ops)
  forcing = BandRescaling(ops; energy = 0.6, lowest_shell = 1, highest_shell = 2)
  integrator = IFRK2()

  uh = spectral_vector(ops)
  random_solenoidal_velocity!(uh, ops; energy = 0.6, peak_wavenumber = 2.0, rng = MersenneTwister(42))
  dealias!(uh, ops)

  Δx = L / N
  cfl = 0.5
  nsteps = 300
  energies = T[]
  for n in 1:nsteps
    velocity_vorticity!(ws.velocity, ws.vorticity_start, uh, ops, ws)
    dt = cfl * Δx / max(max_speed(ws.velocity), 1e-6)
    push!(energies, kinetic_energy(ws.velocity))
    step!(integrator, uh, ops, ws, forcing, ν, dt)
  end

  # the run stays finite and in a physically sane band (it does not blow up or decay away)
  @test all(isfinite, energies)
  @test 0.1 < energies[end] < 10.0

  # not catastrophically drifting between the two late windows (loose stationarity)
  early = sum(@view energies[101:200]) / 100
  late = sum(@view energies[201:300]) / 100
  @test abs(late - early) / early < 1.0

  # divergence-free to roundoff: ‖∇·u‖ / ‖u‖
  relative_divergence = l2norm(divergence(uh, ops.multipliers)) / (l2norm(uh) + 1e-30)
  @test relative_divergence < 1e-8

  # allocation-free hot loop: one step allocates less than a single velocity field
  velocity_vorticity!(ws.velocity, ws.vorticity_start, uh, ops, ws)
  dt = cfl * Δx / max(max_speed(ws.velocity), 1e-6)
  step!(integrator, uh, ops, ws, forcing, ν, dt)                              # warm up
  step_bytes = @allocated step!(integrator, uh, ops, ws, forcing, ν, dt)
  field_bytes = length(field_data(uh)) * sizeof(eltype(field_data(uh)))
  @test step_bytes < field_bytes
end
