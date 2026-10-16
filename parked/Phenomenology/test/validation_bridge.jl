# A run compared to a model spectrum — the bridge from a run's measured state to the module's
# `FlowParameters`, and the comparison built on it. Both were the package's validation suite until
# the module was parked (decision 113); they are tests of this module's reading of a run, not of the
# solver, so they moved with it. Comparing a measured spectrum against a model is a TEST activity,
# not a package capability (decision 49): it answers "does this run reproduce the literature", which
# a validation suite asks and a solver never does.
using Test
using GBGHomogeneousTurbulence
using ..Phenomenology: FlowParameters, spectrum
using ..Phenomenology.Spectra: Pope2000

# one short forced run, shared across the checks
const SIM = Simulation(grid_points_per_axis = 32, viscosity = 0.02, velocity_forcing = ConstantPower(injection_rate = 0.1))
for _ in 1:20
  advance!(SIM)
end


# The bridge: the measured scalars a law reads, packed as the record the law takes. Every field is a
# measured quantity of the run; none is a stand-in (decision 112).
function measured_state(sim)
  ν = sim.generator.conditions.viscosity
  k = kinetic_energy(sim.state.velocity_spectral)
  FlowParameters(; viscosity = ν, dissipation = dissipation(sim.state.velocity_spectral, sim.domain, ν),
                 rms_velocity = sqrt(2k / 3),
                 integral_scale = integral_scale(sim.state.velocity_spectral, sim.domain),
                 schmidt = sim.generator.conditions.schmidt)
end

# The one subtlety the comparison encodes: the measured `energy_spectrum` is a density per unit
# wavenumber at the shell centres, and so is a model E(κ), but the measured value is compared per
# shell — so the model density is multiplied by the shell width Δκ = 2π/L before the two are set side
# by side, at any box side L, not only the default L = 2π where Δκ = 1.
function compare_to_model(sim, model)
  fp = measured_state(sim)
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


# The Δκ conversion is invisible on the default L = 2π box, where Δκ = 1, so it is pinned on a box
# where it is not: a wrong (or missing) shell-width factor changes the prediction there and nowhere
# else, which is exactly how such a factor survives a test suite.
@testset "the model comparison carries the shell width on a non-2π box" begin
  sim = Simulation(grid_points_per_axis = 32, side_length = 4π, viscosity = 0.02,
                   velocity_forcing = ConstantPower(injection_rate = 0.1))
  advance!(sim)
  v = compare_to_model(sim, Pope2000())
  fp = measured_state(sim)
  Δκ = 2π / sim.domain.grid.domain_size[1]
  @test Δκ ≈ 0.5                                        # not 1: the factor is live here
  i = findfirst(>(0), v.wavenumbers)
  @test v.predicted[i] ≈ spectrum(Pope2000(), v.wavenumbers[i], fp) * Δκ
end


@testset "the measured spectrum against a model spectrum" begin
  v = compare_to_model(SIM, Pope2000())
  @test length(v.wavenumbers) == length(v.measured) == length(v.predicted)
  @test isfinite(v.relative_error) && v.relative_error ≥ 0
  # the prediction is the model density × the shell width Δκ = 2π/L (a per-shell energy, matching `measured`)
  fp = measured_state(SIM)
  Δκ = 2π / SIM.domain.grid.domain_size[1]
  i = findfirst(>(0), v.wavenumbers)
  @test v.predicted[i] ≈ spectrum(Pope2000(), v.wavenumbers[i], fp) * Δκ
end
