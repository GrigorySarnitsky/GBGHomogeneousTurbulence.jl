using Test
using GBGIsotropicTurbulence
using GBGPeriodicFields: curl!, field_data
using GBGIsotropicTurbulence.Phenomenology
using GBGIsotropicTurbulence.Phenomenology.Spectra: Pope2000

# one short forced run, shared across the validation checks
const SIM = Simulation(grid_points_per_axis = 32, viscosity = 0.02, velocity_forcing = ConstantPower(injection_rate = 0.1))
for _ in 1:20
  advance!(SIM)
end


@testset "energy_spectrum — Parseval consistency" begin
  κ, E = energy_spectrum(SIM.state.velocity_spectral, SIM.domain)
  @test length(κ) == length(E)
  @test all(≥(0), E)                                          # a power spectrum is non-negative
  @test isapprox(sum(E), kinetic_energy(SIM.state.velocity_spectral); rtol = 1e-5)    # Σ E(κ) = k
  @test integral_scale(SIM.state.velocity_spectral, SIM.domain) > 0
end


@testset "flow_parameters — the measured-state bridge" begin
  fp = flow_parameters(SIM)
  @test fp isa FlowParameters
  @test fp.viscosity == 0.02
  ω̂ = new_vector_field_spectral(SIM.domain)
  curl!(ω̂, SIM.state.velocity_spectral, SIM.domain.multipliers)
  @test fp.dissipation ≈ dissipation(ω̂, SIM.generator.conditions.viscosity)
  @test fp.rms_velocity ≈ sqrt(2 * kinetic_energy(SIM.state.velocity_spectral) / 3)
  @test fp.integral_scale ≈ integral_scale(SIM.state.velocity_spectral, SIM.domain)
  @test taylor_reynolds(fp) > 0
end


@testset "dissipation — the vorticity and Dirichlet routes, and the condition between them" begin
  # ε = ν⟨|ω|²⟩ from a formed curl versus ν⟨û,|κ|²û⟩ straight from the velocity. The two agree
  # because |κ×û|² = |κ|²|û|² − |κ·û|² and the projected dynamics keeps κ·û = 0 — so the second
  # route is exact on any state the solver produces, and the run layer measures ε through it.
  ν = SIM.generator.conditions.viscosity
  ω̂ = new_vector_field_spectral(SIM.domain)
  curl!(ω̂, SIM.state.velocity_spectral, SIM.domain.multipliers)
  @test dissipation(SIM.state.velocity_spectral, SIM.domain, ν) ≈ dissipation(ω̂, ν) rtol = 1e-12

  # The discarded term is not vacuous: break the solenoidal condition and the routes part company.
  # This is the negative control behind the docstring's warning — the Dirichlet route is a claim
  # about divergence-free fields, not an identity for an arbitrary vector field.
  û = new_vector_field_spectral(SIM.domain)
  copyto!(field_data(û), field_data(SIM.state.velocity_spectral))
  @views field_data(û)[:, :, :, 1] .*= 2                     # no longer divergence-free
  curl!(ω̂, û, SIM.domain.multipliers)
  @test !isapprox(dissipation(û, SIM.domain, ν), dissipation(ω̂, ν); rtol = 1e-3)
end


# Comparing a measured spectrum against a model is a TEST activity, not a package capability: it
# answers "does this run reproduce the literature", which is what a validation suite asks and a solver
# never does. The comparison lives here rather than in `src/` for that reason (decision 49).
#
# The one subtlety it encodes: the measured `energy_spectrum` is a per-shell energy (k = Σ_κ E_n)
# while a `Phenomenology` model is a spectral density (k = ∫ E(κ) dκ), so the density must be
# multiplied by the shell width Δκ = 2π/L before the two are comparable — at any box side L, not only
# the default L = 2π where Δκ = 1.
function compare_to_model(sim, model)
  fp = flow_parameters(sim)
  # `energy_spectrum` returns host `Vector`s whatever backend the field lives on — the shell
  # accumulators are O(N) and the reduction brings them back — so this comparison, which walks the
  # shells one at a time, needs no transfer of its own and never scalar-indexes a device array.
  κ, measured = energy_spectrum(sim.state.velocity_spectral, sim.domain)
  Δκ = 2π / sim.domain.grid.domain_size[1]
  predicted = similar(measured)
  num = zero(eltype(measured))
  den = zero(eltype(measured))
  for i in eachindex(κ, measured)
    predicted[i] = κ[i] > 0 ? spectrum(model, κ[i], fp) * Δκ : zero(eltype(measured))
    if measured[i] > 0
      num += (measured[i] - predicted[i])^2
      den += measured[i]^2
    end
  end
  return (; wavenumbers = κ, measured, predicted, relative_error = sqrt(num / den))
end


@testset "the measured spectrum against a model spectrum" begin
  v = compare_to_model(SIM, Pope2000())
  @test length(v.wavenumbers) == length(v.measured) == length(v.predicted)
  @test isfinite(v.relative_error) && v.relative_error ≥ 0
  # the prediction is the model density × the shell width Δκ = 2π/L (a per-shell energy, matching `measured`)
  fp = flow_parameters(SIM)
  Δκ = 2π / SIM.domain.grid.domain_size[1]
  i = findfirst(>(0), v.wavenumbers)
  @test v.predicted[i] ≈ spectrum(Pope2000(), v.wavenumbers[i], fp) * Δκ
end
