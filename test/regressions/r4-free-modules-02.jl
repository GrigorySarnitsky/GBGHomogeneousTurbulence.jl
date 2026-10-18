# Witness r4-free-modules-02 — `schmidt = 0` NaNs the scalar and the run reports success.
#
# Correct behaviour asserted: EITHER `Simulation` rejects a non-positive `schmidt` with an
# `ArgumentError` naming it (the house style of the `kinetic_energy` / `scalar_variance`
# preconditions beside it), OR `advance!` refuses to report success on a state it has just made
# non-finite — the guarantee its own guard comment claims, honoured for the velocity.

using Test, Random
using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data

@testset "negative control — the velocity twin does raise" begin
  sim = Simulation(grid_points_per_axis = 12; scalar = PassiveScalar(schmidt = 1.0),
  viscosity = 0.05, rng = MersenneTwister(1))
  advance!(sim; dt = 1e-3)
  # Force a non-finite velocity outside the iteration, exactly as the guard's comment envisages.
  # Poked in the state, not the cache: the step consumes it, the closing deposit re-measures, and
  # the guard is the only thing standing between a NaN velocity and a normal return.
  field_data(sim.state.velocity_spectral)[1] = NaN
  err = try
    advance!(sim; dt = 1e-3)
    nothing
  catch e
    e
  end
  @test err !== nothing
  @test occursin("non-finite velocity", sprint(showerror, err))
end


@testset "a run must not report success on a NaN scalar produced by schmidt = 0" begin

  built = try
    Simulation(grid_points_per_axis = 12; scalar = PassiveScalar(schmidt = 0.0),
    viscosity = 0.05, rng = MersenneTwister(1))
  catch err
    err
  end

  if built isa Exception
    # Route 1: the constructor refuses the argument.
    @test built isa ArgumentError
    @test occursin("schmidt", lowercase(sprint(showerror, built)))
  else
    sim = built
    # Route 2: the constructor accepted it, so the advance must refuse to report success.
    refusal = nothing
    for _ in 1:3
      try
        advance!(sim; dt = 1e-3)
      catch err
        refusal = err
        break
      end
    end

    # Establish that the state really is poisoned (so the assertion below is about the guard).
    poisoned = isnan(scalar_variance(sim.state.scalar_spectral)) ||
               !all(isfinite, field_data(scalar_physical(sim.cache)))
    @test poisoned            # sanity: the scalar is non-finite

    @test refusal !== nothing # THE CLAIM: `advance!` must not return normally on a non-finite scalar
  end
end
