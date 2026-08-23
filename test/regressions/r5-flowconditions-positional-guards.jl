# Witness: `FlowConditions`'s two DOCUMENTED construction forms must enforce the same contract.
#
# `FlowConditions`'s own docstring advertises both forms — the keyword one in its signature line, and
# the positional one in `# Fields`:
#
#   "The plain constructor `FlowConditions(viscosity, schmidt, velocity_forcing, scalar_forcing)`
#    takes the four fields directly, in the order shown; each holds the value documented for the
#    keyword of the same name above"
#
# and promises, without qualifying which form it speaks of:
#
#   !!! warning "A stateful forcing cannot drive both fields"
#       "... passing the same *mutable* strategy instance as both `velocity_forcing` and
#        `scalar_forcing` throws an `ArgumentError` naming it. Build two."
#
# That promise holds only for the keyword outer constructor (`Generator.jl:91–115`), which is where
# all three guards live. `struct FlowConditions` (`Generator.jl:84`) declares no inner constructor, so
# Julia's auto-generated positional constructor is public, exported through the umbrella, and
# validates nothing: the shared-mutable-forcing guard, the `viscosity > 0` guard and the
# `schmidt > 0` guard are all bypassed by the very call the docstring tells the reader to make.
#
# The hazard the guard exists for is real and reachable. `StochasticOU` allocates its per-field state
# lazily on first `prepare_forcing!` (`Forcing.jl:534–536`), keyed on the field it is first handed:
# driving the velocity allocates a VECTOR `noise_physical`, and the scalar leg then reaches
# `to_spectral!(noise_spectral, noise_physical, domain.scalar_plans)` with the vector scratch still in
# place. The misconfiguration therefore surfaces as a `MethodError` raised inside GBGPeriodicFields,
# naming neither `FlowConditions` nor the shared forcing.
#
# The repair is a validating inner constructor (plus the outer wrapper that keeps the documented
# positional form callable), so that one contract covers both advertised entry points. Either that,
# or the numbers below stop being a contract at all — but the docstring, and the package's own
# convention of advertising this type's plain constructor, say they are.

using Test
using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Forcing: StochasticOU, NoForcing
using GBGIsotropicTurbulence.Generator: FlowConditions, prepare!


small_domain() = FixedDomain(; grid_points_per_axis = 8, side_length = 2π, dealiasing = TwoThirds(),
                             element_type = Float64, array_type = Array)


# How the shared-mutable-forcing misconfiguration surfaces when it is built positionally and run:
# `:rejected` — some package-level error names it (at construction or at `prepare!`);
# `:dependency_internal` — a `MethodError` from inside the field library, naming nothing a caller typed;
# `:accepted` — it runs, with the two fields silently sharing one random stream and one scratch.
function shared_forcing_outcome()
  domain = small_domain()
  ou = StochasticOU(domain; variance = 0.1, correlation_time = 0.5)
  conditions = try
    FlowConditions(0.05, 1.0, ou, ou)          # the positional form, exactly as documented
  catch err
    return err isa ArgumentError ? :rejected : :dependency_internal
  end
  generator = ResolvedGenerator(domain, conditions; scalar = true)
  state = ResolvedFields(domain; scalar = true)
  try
    prepare!(generator, state, domain, 1e-3)
    return :accepted
  catch err
    return err isa MethodError ? :dependency_internal : :rejected
  end
end


@testset "FlowConditions's documented plain constructor enforces the same contract as the keyword form" begin
  domain = small_domain()
  ou = StochasticOU(domain; variance = 0.1, correlation_time = 0.5)

  # Baseline — the keyword form enforces all three guards, as documented.
  @test_throws ArgumentError FlowConditions(; viscosity = 0.05, schmidt = 1.0,
                                           velocity_forcing = ou, scalar_forcing = ou)
  @test_throws ArgumentError FlowConditions(; viscosity = -1.0, schmidt = 1.0,
                                           velocity_forcing = NoForcing(), scalar_forcing = NoForcing())
  @test_throws ArgumentError FlowConditions(; viscosity = 0.05, schmidt = 0.0,
                                           velocity_forcing = NoForcing(), scalar_forcing = NoForcing())

  # The claim — the same three misconfigurations, through the other documented form.
  @test_throws ArgumentError FlowConditions(0.05, 1.0, ou, ou)
  @test_throws ArgumentError FlowConditions(-1.0, 1.0, NoForcing(), NoForcing())
  @test_throws ArgumentError FlowConditions(0.05, 0.0, NoForcing(), NoForcing())

  # And the consequence: whatever else it does, a shared mutable forcing must never reach the field
  # library and come back as a MethodError about transform plans.
  @test shared_forcing_outcome() === :rejected
end
