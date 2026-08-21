# Witness: flow_parameters must form the scalar diffusivity as ϰ = ν/Sc, not ν·Sc.
# Claim under test: SimulationRun.flow_parameters passes viscosity * schmidt to
# scalar_dissipation, so the reported ε_φ would be Sc² too large whenever Sc ≠ 1.
using Test, Random
using GBGIsotropicTurbulence

@testset "flow_parameters reports the scalar dissipation at ϰ = ν/Sc, not ν·Sc" begin
  ν  = 0.05
  Sc = 4.0
  sim = Simulation(grid_points_per_axis = 16, viscosity = ν, schmidt = Sc,
                   scalar = true, velocity_forcing = NoForcing(),
                   scalar_forcing = NoForcing(), rng = MersenneTwister(3))
  for _ in 1:3; advance!(sim); end

  fp = flow_parameters(sim)

  correct = scalar_dissipation(sim.state.scalar_spectral, sim.domain, ν / Sc)
  wrong   = scalar_dissipation(sim.state.scalar_spectral, sim.domain, ν * Sc)

  @info "measured" reported = fp.scalar_dissipation correct = correct wrong_nu_times_Sc = wrong ratio = fp.scalar_dissipation / correct

  # The scalar dissipation is linear in the diffusivity, so ν·Sc vs ν/Sc differ by Sc².
  @test correct > 0
  @test wrong / correct ≈ Sc^2

  # What SHOULD hold: the run layer reports the ν/Sc value.
  @test fp.scalar_dissipation ≈ correct rtol = 1e-10

  # And the FlowParameters bridge itself must agree on the diffusivity.
  @test GBGIsotropicTurbulence.Phenomenology.scalar_diffusivity(fp) ≈ ν / Sc rtol = 1e-12
end
