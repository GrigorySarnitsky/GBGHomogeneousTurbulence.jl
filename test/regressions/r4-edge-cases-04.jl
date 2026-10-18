# Witness: a real `scalar_forcing` handed to a `scalar = false` run must not be silently discarded.
#
# `Simulation`'s constructor materializes `scalar_forcing` unconditionally and stores it in
# `FlowConditions` with no cross-check against the `scalar` flag, while `Generator.prepare!` and
# `Generator.finalize!` gate every scalar-forcing call behind `state.scalar_spectral !== nothing`.
# A forcing the user explicitly built is therefore held in the run's conditions and never invoked.
#
# The assertion is deliberately fix-agnostic: it demands only that the configuration NOT be
# silently dropped. Either construction rejects the mismatch (the convention this constructor
# already follows for the `viscosity`/`κ_max_η` double-set, and that `Generator._forcing_rate`
# follows for a forcing that "would never be applied"), or the run honours the forcing. Both count
# as correct; only "accepted and never invoked" fails.

using Test
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Forcing: AbstractForcing, ConstantPower, NoForcing
using GBGHomogeneousTurbulence.SimulationDomain: FixedDomain
import GBGHomogeneousTurbulence.Forcing: prepare_forcing!, project_forcing!

# A forcing that only records whether the generator ever reached it.
mutable struct ForcingSpy <: AbstractForcing
  prepares::Int
  applies::Int
end
ForcingSpy() = ForcingSpy(0, 0)
prepare_forcing!(f::ForcingSpy, forcing_state, field, domain::FixedDomain, dt::Real) = (f.prepares += 1; nothing)
project_forcing!(f::ForcingSpy, advanced_field, domain::FixedDomain) = (f.applies += 1; advanced_field)

const N = 16
const NU = 0.05
const STEPS = 3


@testset "a real scalar_forcing given to a scalar-free run is not silently accepted and dropped" begin

  # Control 1 — the instrument is sound: with `scalar = true` the generator does reach the forcing.
  spy_on = ForcingSpy()
  sim_on = Simulation(grid_points_per_axis = N, viscosity = NU, scalar = PassiveScalar(forcing = spy_on))
  for _ in 1:STEPS
    advance!(sim_on)
  end
  @test spy_on.prepares == STEPS
  @test spy_on.applies == STEPS

  # Control 2 — the matched configuration is untouched: a scalar-free run builds.
  @test Simulation(grid_points_per_axis = N, viscosity = NU) isa Simulation

  # The claim. Since 2026-10-14 the scalar's forcing travels inside `PassiveScalar`, so a scalar
  # forcing cannot be written for a scalar-free run at all: `Simulation` has no `scalar_forcing`
  # keyword, and a scalar forcing given a scalar-free generator by hand is still refused by name.
  spy_off = ForcingSpy()
  @test_throws MethodError Simulation(grid_points_per_axis = N, viscosity = NU, scalar_forcing = spy_off)
  @test spy_off.prepares == 0 && spy_off.applies == 0
  domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, dealiasing = TwoThirds(),
                       element_type = Float64, array_family = Array)
  conditions = FlowConditions(viscosity = NU, schmidt = 1.0, velocity_forcing = NoForcing(),
                              scalar_forcing = ConstantPower(domain; injection_rate = 0.5))
  @test_throws ArgumentError ResolvedGenerator(domain, conditions; scalar = false)
end
