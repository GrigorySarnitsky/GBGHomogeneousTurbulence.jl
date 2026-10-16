using Test
using GBGHomogeneousTurbulence
using GBGPeriodicFields: curl!, field_data
using Random

# one short forced run, shared across the validation checks
const SIM = Simulation(grid_points_per_axis = 32, viscosity = 0.02, velocity_forcing = ConstantPower(injection_rate = 0.1))
for _ in 1:20
  advance!(SIM)
end


@testset "energy_spectrum — Parseval consistency" begin
  κ, E = energy_spectrum(SIM.state.velocity_spectral, SIM.domain)
  @test length(κ) == length(E)
  @test all(≥(0), E)                                          # a power spectrum is non-negative
  Δκ = 2π / SIM.domain.grid.domain_size[1]
  @test isapprox(sum(E) * Δκ, kinetic_energy(SIM.state.velocity_spectral); rtol = 1e-5)   # Σ E(κ)·Δκ = k
  @test integral_scale(SIM.state.velocity_spectral, SIM.domain) > 0
end


# The shell width Δκ = 2π/L is 1 on the default box, so a density that forgot to divide by it would
# pass the testset above and every other test on a 2π box. Parseval on a 4π box pins the factor:
# there Δκ = 1/2, and a missing (or doubled) division shows as a factor of two in k.
@testset "energy_spectrum — the shell width on a non-2π box" begin
  sim = Simulation(grid_points_per_axis = 32, side_length = 4π, viscosity = 0.02,
                   velocity_forcing = ConstantPower(injection_rate = 0.1))
  advance!(sim)
  κ, E = energy_spectrum(sim.state.velocity_spectral, sim.domain)
  Δκ = 2π / sim.domain.grid.domain_size[1]
  @test Δκ ≈ 0.5                                                  # not 1: the factor is live here
  @test isapprox(sum(E) * Δκ, kinetic_energy(sim.state.velocity_spectral); rtol = 1e-5)
  @test !isapprox(sum(E), kinetic_energy(sim.state.velocity_spectral); rtol = 1e-2)  # the bin sum is not k
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


# Comparing a measured spectrum against a model spectrum is a TEST activity, not a package capability
# (decision 49). That comparison, and the bridge from a run's measured state to the model's flow
# parameters, live with the parked reference-law module: parked/Phenomenology/test/validation_bridge.jl
# (decision 113).

# The module docstring promises every observable returns the field's own element type. That claim was
# found false in a new place on three consecutive review rounds — kinetic_energy/derivative_skewness,
# then dissipation/scalar_dissipation via their Real parameter, then energy_spectrum/integral_scale
# via untyped literals. Each fix was verified against the functions the finding named. This pins the
# CLAIM instead, over every exported observable, so the next leak fails a test rather than a review.
@testset "every observable returns the field's own element type" begin
  for T in (Float32, Float64)
    d = FixedDomain(grid_points_per_axis = 16, side_length = T(2π), element_type = T,
                    array_family = Array, dealiasing = TwoThirds())
    û = new_vector_field_spectral(d)
    random_solenoidal_velocity_spectral!(û, d, T(0.5); envelope_wavenumber = T(2),
                                         rng = MersenneTwister(1))
    φ̂ = new_scalar_field_spectral(d)
    random_scalar_spectral!(φ̂, d, T(1); envelope_wavenumber = T(2),
                            rng = MersenneTwister(2))
    @test typeof(kinetic_energy(û))            === T
    @test typeof(dissipation(û, d, 0.001))     === T   # a Float64 parameter must not promote
    @test typeof(scalar_variance(φ̂))           === T
    @test typeof(scalar_dissipation(φ̂, d, 0.001)) === T
    @test typeof(derivative_skewness(û, d))    === T
    @test typeof(integral_scale(û, d))         === T
    spec = energy_spectrum(û, d)
    @test eltype(spec.energy)      === T
    @test eltype(spec.wavenumbers) === T
  end
end
