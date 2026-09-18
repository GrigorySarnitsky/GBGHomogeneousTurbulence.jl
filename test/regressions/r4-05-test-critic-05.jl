# Witness for candidate r4/test-critic-05: "flow_parameters' scalar_dissipation branch is never
# measured on a scalar-carrying run".
#
# The claim is a COVERAGE claim: the composed call inside `flow_parameters`,
#
#     εφ = scalar_dissipation(state.scalar_spectral, domain, conditions.viscosity / conditions.schmidt)
#
# has to divide ν by Sc to get the scalar diffusivity ϰ = ν/Sc. No test asserts that composition on
# a scalar-carrying run, so a swap to `viscosity * schmidt` or a bare `viscosity` would go unnoticed.
#
# These tests assert the CORRECT behaviour, at a Schmidt number away from 1 so that ν/Sc, ν·Sc and ν
# are three distinct numbers and the assertion actually discriminates between them.

using GBGHomogeneousTurbulence
using Random
using Test


@testset "flow_parameters composes the scalar diffusivity as ϰ = ν/Sc on a scalar-carrying run" begin
  ν  = 0.02
  Sc = 0.7                                   # away from 1: ν/Sc ≠ ν·Sc ≠ ν
  sim = Simulation(grid_points_per_axis = 16, viscosity = ν, schmidt = Sc,
                   scalar = true, scalar_variance = 1.0,
                   velocity_forcing = ConstantPower(injection_rate = 0.1),
                   rng = MersenneTwister(1234))
  for _ in 1:5
    advance!(sim; dt = 1.0e-3)
  end

  fp = flow_parameters(sim)

  # The branch is live at all: a scalar run must not report the scalar-free NaN.
  @test sim.state.scalar_spectral !== nothing
  @test isfinite(fp.scalar_dissipation)
  @test fp.scalar_dissipation > 0

  # The conditions are carried through unchanged.
  @test fp.viscosity == ν
  @test fp.schmidt == Sc

  # The composed call agrees with the directly-called reduction at the scalar diffusivity ϰ = ν/Sc.
  expected = scalar_dissipation(sim.state.scalar_spectral, sim.domain, ν / Sc)
  @test fp.scalar_dissipation ≈ expected rtol = 1e-12

  # …and is NOT what the two plausible mis-wirings would produce.
  @test !isapprox(fp.scalar_dissipation, scalar_dissipation(sim.state.scalar_spectral, sim.domain, ν * Sc); rtol = 1e-3)
  @test !isapprox(fp.scalar_dissipation, scalar_dissipation(sim.state.scalar_spectral, sim.domain, ν);      rtol = 1e-3)

  # The Phenomenology bridge reads the same diffusivity back out of the record.
  @test GBGHomogeneousTurbulence.Phenomenology.scalar_diffusivity(fp) ≈ ν / Sc
end
