# Witness: the FlowConditions guard against ONE mutable forcing instance driving BOTH fields.
# A stateful strategy (the mutable `StochasticOU`) carries per-field scratch and its own random
# stream, so sharing one instance across the velocity and the scalar conflates their bookkeeping.
# `FlowConditions` must reject it, and the `Simulation` front door must inherit that rejection
# (`_materialize_forcing` is the identity on an already-built `AbstractForcing`).

using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Forcing: StochasticOU   # un-exported (archived), reached by its module path
using Test


@testset "a shared mutable forcing instance is rejected for both fields" begin
  domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π,
                       element_type = Float64, dealiasing = TwoThirds(), array_type = Array)
  ou = StochasticOU(domain; variance = 0.3, correlation_time = 0.4, seed = 1)

  @test ismutable(ou)                       # the guard's predicate holds for this strategy

  # (1) the constructor itself
  @test_throws ArgumentError FlowConditions(viscosity = 0.05, schmidt = 1.0,
                                            velocity_forcing = ou, scalar_forcing = ou)

  # (2) the front door, which passes an already-built forcing straight through
  @test_throws ArgumentError Simulation(grid_points_per_axis = 8, viscosity = 0.05, scalar = true,
                                        velocity_forcing = ou, scalar_forcing = ou)

  # (3) the guard is narrow: two separately-built mutable instances are fine, …
  ou2 = StochasticOU(domain; variance = 0.3, correlation_time = 0.4, seed = 2)
  @test FlowConditions(viscosity = 0.05, schmidt = 1.0,
                       velocity_forcing = ou, scalar_forcing = ou2) isa FlowConditions

  # … and one shared IMMUTABLE strategy stays legal (no per-field state to conflate).
  band = BandRescaling(domain; target = 0.5, over = :band)
  @test !ismutable(band)
  @test FlowConditions(viscosity = 0.05, schmidt = 1.0,
                       velocity_forcing = band, scalar_forcing = band) isa FlowConditions
end
