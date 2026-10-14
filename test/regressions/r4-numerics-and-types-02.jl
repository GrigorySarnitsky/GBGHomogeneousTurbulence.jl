# Witness — round 4, lane "numerics-and-types", 02.
#
# Claim: `schmidt` is never validated, and a non-positive Schmidt number silently poisons the whole
# scalar field with NaN on the first `advance!`, undetected by the run's blow-up guard (which reads
# only the velocity, and the scalar is passive).
#
# Mechanism: `scalar_integrating_factor` forms coefficient = -(ν/Sc)·τ = -Inf at Sc = 0; the fused
# exponential evaluates exp(coefficient·|κ|² + …) per mode, and at the mean mode κ = 0 that is
# -Inf·0 = NaN, so exp(NaN) = NaN. The quadratic advection term then spreads the NaN.

using Test, Random
using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data


"""
Build a run with the given Schmidt number, advance one step, and report which of three things
happened: `:rejected` (the configuration was refused, at construction or at run time), `:finite`
(the run proceeded and the scalar stayed finite), or `:silent_nan` (the run reported success while
carrying a NaN scalar field). Only the last is a defect.
"""
function schmidt_outcome(schmidt)
  local sim
  try
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.01,
                     scalar = PassiveScalar(schmidt = schmidt, forcing = NoForcing()), velocity_forcing = NoForcing(),
                     rng = MersenneTwister(1))
    advance!(sim)
  catch
    return :rejected
  end
  return all(isfinite, field_data(sim.state.scalar_spectral)) ? :finite : :silent_nan
end


@testset "a non-positive Schmidt number never silently yields a NaN scalar field" begin
  # Fix-agnostic: whichever way the package chooses to handle it — reject the argument or surface
  # the corruption — a successful-looking run must never carry a NaN scalar.
  @test schmidt_outcome(0.0) != :silent_nan
  @test schmidt_outcome(-1.0) != :silent_nan

  # The handling the package's own conventions call for: `Simulation` already refuses a
  # non-positive `kinetic_energy` and a negative `scalar_variance` at construction, precisely so a
  # bad argument is named at its source rather than surfacing far downstream. Sc = ν/ϰ is positive
  # by definition, so the same guard belongs on it.
  @test_throws ArgumentError Simulation(grid_points_per_axis = 16, viscosity = 0.01,
                                        scalar = PassiveScalar(schmidt = 0.0, forcing = NoForcing()),
                                        velocity_forcing = NoForcing(),
                                        rng = MersenneTwister(1))
  @test_throws ArgumentError Simulation(grid_points_per_axis = 16, viscosity = 0.01,
                                        scalar = PassiveScalar(schmidt = -1.0, forcing = NoForcing()),
                                        velocity_forcing = NoForcing(),
                                        rng = MersenneTwister(1))
end
