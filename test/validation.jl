using Test
using GBGIsotropicTurbulence
using GBGPeriodicFields: curl!
using GBGIsotropicTurbulence.Phenomenology
using GBGIsotropicTurbulence.Phenomenology.Spectra: Pope2000

# one short forced run, shared across the validation checks
const SIM = Simulation(grid_points_per_axis = 32, viscosity = 0.02, velocity_forcing = ConstantPower(target = 0.1))
for _ in 1:20
  advance!(SIM)
end


@testset "energy_spectrum — Parseval consistency" begin
  κ, E = energy_spectrum(SIM.state.velocity, SIM.domain)
  @test length(κ) == length(E)
  @test all(≥(0), E)                                          # a power spectrum is non-negative
  @test isapprox(sum(E), kinetic_energy(SIM.state.velocity); rtol = 1e-5)    # Σ E(κ) = k
  @test integral_scale(SIM.state.velocity, SIM.domain) > 0
end


@testset "flow_parameters — the measured-state bridge" begin
  fp = flow_parameters(SIM)
  @test fp isa FlowParameters
  @test fp.viscosity == 0.02
  curl!(SIM.buffers.vorticity_spectral, SIM.state.velocity, SIM.domain.multipliers)
  @test fp.dissipation ≈ dissipation(SIM.buffers.vorticity_spectral, SIM.conditions.viscosity)
  @test fp.rms_velocity ≈ sqrt(2 * kinetic_energy(SIM.state.velocity) / 3)
  @test fp.integral_scale ≈ integral_scale(SIM.state.velocity, SIM.domain)
  @test taylor_reynolds(fp) > 0
end


@testset "validate_spectrum — measured vs predicted" begin
  v = validate_spectrum(SIM, Pope2000())
  @test length(v.wavenumbers) == length(v.measured) == length(v.predicted)
  @test isfinite(v.relative_error) && v.relative_error ≥ 0
  # the prediction is the model density × the shell width Δκ = 2π/L (a per-shell energy, matching `measured`)
  fp = flow_parameters(SIM)
  Δκ = 2π / SIM.domain.grid.domain_size[1]
  i = findfirst(>(0), v.wavenumbers)
  @test v.predicted[i] ≈ spectrum(Pope2000(), v.wavenumbers[i], fp) * Δκ
end
