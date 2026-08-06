using Test
using GBGIsotropicTurbulence
using GBGPeriodicFields: curl!, field_data
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
  ω̂ = new_vector_field_spectral(SIM.domain)
  curl!(ω̂, SIM.state.velocity, SIM.domain.multipliers)
  @test fp.dissipation ≈ dissipation(ω̂, SIM.generator.conditions.viscosity)
  @test fp.rms_velocity ≈ sqrt(2 * kinetic_energy(SIM.state.velocity) / 3)
  @test fp.integral_scale ≈ integral_scale(SIM.state.velocity, SIM.domain)
  @test taylor_reynolds(fp) > 0
end


@testset "dissipation — the vorticity and Dirichlet routes, and the condition between them" begin
  # ε = ν⟨|ω|²⟩ from a formed curl versus ν⟨û,|κ|²û⟩ straight from the velocity. The two agree
  # because |κ×û|² = |κ|²|û|² − |κ·û|² and the projected dynamics keeps κ·û = 0 — so the second
  # route is exact on any state the solver produces, and the run layer measures ε through it.
  ν = SIM.generator.conditions.viscosity
  ω̂ = new_vector_field_spectral(SIM.domain)
  curl!(ω̂, SIM.state.velocity, SIM.domain.multipliers)
  @test dissipation(SIM.state.velocity, SIM.domain, ν) ≈ dissipation(ω̂, ν) rtol = 1e-12

  # The discarded term is not vacuous: break the solenoidal condition and the routes part company.
  # This is the negative control behind the docstring's warning — the Dirichlet route is a claim
  # about divergence-free fields, not an identity for an arbitrary vector field.
  û = new_vector_field_spectral(SIM.domain)
  copyto!(field_data(û), field_data(SIM.state.velocity))
  @views field_data(û)[:, :, :, 1] .*= 2                     # no longer divergence-free
  curl!(ω̂, û, SIM.domain.multipliers)
  @test !isapprox(dissipation(û, SIM.domain, ν), dissipation(ω̂, ν); rtol = 1e-3)
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
