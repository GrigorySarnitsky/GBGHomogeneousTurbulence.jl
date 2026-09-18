# Witness: a real `scalar_forcing` handed to a `scalar = false` run must not be silently discarded.
#
# `Simulation`'s constructor materializes `scalar_forcing` unconditionally and stores it in
# `FlowConditions` with no cross-check against the `scalar` flag, while `Generator.prepare!` and
# `Generator.finalize!` gate every scalar-forcing hook behind `state.scalar_spectral !== nothing`.
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
mutable struct HookSpy <: AbstractForcing
  prepares::Int
  applies::Int
end
HookSpy() = HookSpy(0, 0)
prepare_forcing!(f::HookSpy, forcing_state, field, domain::FixedDomain, dt::Real) = (f.prepares += 1; nothing)
project_forcing!(f::HookSpy, advanced_field, domain::FixedDomain) = (f.applies += 1; advanced_field)

const N = 16
const NU = 0.05
const STEPS = 3


@testset "a real scalar_forcing given to a scalar-free run is not silently accepted and dropped" begin

  # Control 1 — the instrument is sound: with `scalar = true` the generator does reach the hooks.
  spy_on = HookSpy()
  sim_on = Simulation(grid_points_per_axis = N, viscosity = NU, scalar = true, scalar_forcing = spy_on)
  for _ in 1:STEPS
    advance!(sim_on)
  end
  @test spy_on.prepares == STEPS
  @test spy_on.applies == STEPS

  # Control 2 — the matched configuration is untouched: `NoForcing()` with `scalar = false` builds.
  @test Simulation(grid_points_per_axis = N, viscosity = NU, scalar = false,
                   scalar_forcing = NoForcing()) isa Simulation

  # The claim. A non-`NoForcing` scalar forcing with `scalar = false` must be either rejected at
  # construction or actually honoured — never accepted and left uninvoked.
  spy_off = HookSpy()
  built = try
    Simulation(grid_points_per_axis = N, viscosity = NU, scalar = false, scalar_forcing = spy_off)
  catch err
    err
  end

  if built isa ArgumentError
    @test true                                    # rejected at construction: correct
  else
    @test built isa Simulation                    # anything else thrown is a different defect
    for _ in 1:STEPS
      advance!(built)
    end
    # Not rejected ⇒ it must have been honoured.
    @test spy_off.prepares > 0
    @test spy_off.applies > 0
  end

  # And the same statement made on the shipped strategy the hunter's plan names, without any spy:
  # the run must not end up holding a `ConstantPower` it can never apply.
  built2 = try
    Simulation(grid_points_per_axis = N, viscosity = NU, scalar = false,
               scalar_forcing = ConstantPower(injection_rate = 0.5))
  catch err
    err
  end
  @test built2 isa ArgumentError ||
        (built2 isa Simulation && built2.state.scalar_spectral !== nothing)
end
