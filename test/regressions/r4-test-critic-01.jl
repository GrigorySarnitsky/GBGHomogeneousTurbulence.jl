# Witness: the FlowConditions guard against ONE mutable forcing instance driving BOTH fields.
# A strategy with mutable per-field bookkeeping conflates the two fields when one instance drives
# both, so `FlowConditions` must reject it, and the `Simulation` front door must inherit that
# rejection (`_materialize_forcing` is the identity on an already-built `AbstractForcing`).
#
# Written against the archived, mutable `StochasticOU`. The shipped one keeps its evolving state in
# the run's state and its scratch per field, so it is immutable and one instance may drive
# both fields — which the last block pins, together with the independence of the two streams.

using GBGHomogeneousTurbulence
using Random
using Test
import GBGHomogeneousTurbulence.Forcing: prepare_forcing!

mutable struct SharedCounter <: AbstractForcing
  calls::Int
end
prepare_forcing!(f::SharedCounter, forcing_state, field, domain, dt::Real) = (f.calls += 1; nothing)


@testset "a shared mutable forcing instance is rejected for both fields" begin
  domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π,
                       element_type = Float64, dealiasing = TwoThirds(), array_type = Array)
  counter = SharedCounter(0)
  @test ismutable(counter)                  # the guard's predicate holds for this strategy

  # (1) the constructor itself
  @test_throws ArgumentError FlowConditions(viscosity = 0.05, schmidt = 1.0,
                                            velocity_forcing = counter, scalar_forcing = counter)

  # (2) the front door, which passes an already-built forcing straight through
  @test_throws ArgumentError Simulation(grid_points_per_axis = 8, viscosity = 0.05, scalar = true,
                                        velocity_forcing = counter, scalar_forcing = counter)

  # (3) the guard is narrow: two separately-built mutable instances are fine, …
  @test FlowConditions(viscosity = 0.05, schmidt = 1.0, velocity_forcing = counter,
                       scalar_forcing = SharedCounter(0)) isa FlowConditions

  # … and one shared IMMUTABLE strategy stays legal (no per-field state to conflate).
  band = VarianceRescaling(domain; target = 0.5, over = :band)
  @test !ismutable(band)
  @test FlowConditions(viscosity = 0.05, schmidt = 1.0,
                       velocity_forcing = band, scalar_forcing = band) isa FlowConditions

  # (4) the shipped StochasticOU is such a strategy: one instance drives both fields, each with its
  #     own state in the record and its own stream.
  ou = StochasticOU(domain; forcing_variance = 0.3, correlation_time = 0.4, seed = 1)
  @test !ismutable(ou)
  sim = Simulation(domain; viscosity = 0.05, scalar = true, velocity_forcing = ou, scalar_forcing = ou,
                   rng = MersenneTwister(1))
  for _ in 1:3
    advance!(sim)
  end
  v, s = sim.state.modeled.velocity_forcing, sim.state.modeled.scalar_forcing
  @test v !== s && v.draws == 4 && s.draws == 4
  @test GBGHomogeneousTurbulence.SimulationRun.field_data(s.process) !=
        GBGHomogeneousTurbulence.SimulationRun.field_data(v.process)[:, :, :, 1]
end
