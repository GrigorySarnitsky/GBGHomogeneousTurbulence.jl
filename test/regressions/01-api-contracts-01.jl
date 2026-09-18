# Witness: the misdeclared-forcing guard in `ResolvedGenerator` must fire for ANY forcing that
# implements `set_forcing_rate!` without declaring `uses_steady_linear_rate`, including one whose
# non-dispatch parameters are typed narrower than `Any` (the idiomatic way to write the hook).
#
# `_overrides_rate_hook` (src/Generator.jl:162) probes with
#   which(set_forcing_rate!, Tuple{typeof(forcing), Any, Any, FixedDomain})
# and Base.which resolves that as an ordinary (invoke-style) lookup on the LITERAL argument types,
# so a method whose `rate` parameter is `::ScalarFieldSpectral` is not a candidate for an `Any`
# argument and the probe falls through to the `AbstractForcing` fallback — reporting "no override".

using Test
using GBGHomogeneousTurbulence
using GBGPeriodicFields: ScalarFieldSpectral, field_data

# Same mistake as test/forcing.jl's `UndeclaredRateForcing` — implements the hook, forgets the
# declaration — differing only in that `rate` carries its natural type.
struct TypedUndeclaredRateForcing <: AbstractForcing end
GBGHomogeneousTurbulence.Forcing.set_forcing_rate!(::TypedUndeclaredRateForcing,
                                                 rate::ScalarFieldSpectral, field,
                                                 domain::FixedDomain) = (rate .= 1; rate)

@testset "the misdeclared-forcing guard fires for a hook with a typed `rate` parameter" begin
  domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_type = Array)
  forcing = TypedUndeclaredRateForcing()

  # (a) The type genuinely overrides the hook: a real call dispatches to its own method, which
  #     fills the rate — unlike the do-nothing `AbstractForcing` fallback.
  rate = new_scalar_field_spectral(domain)
  set_forcing_rate!(forcing, rate, nothing, domain)
  @test all(real.(field_data(rate)) .== 1)

  # (b) Therefore the construction-time guard must reject it, per the `ResolvedGenerator`
  #     docstring: "Building a `ResolvedGenerator` around one throws an `ArgumentError`".
  conditions = FlowConditions(; viscosity = 0.05, schmidt = 1.0,
                              velocity_forcing = forcing, scalar_forcing = NoForcing())
  @test_throws ArgumentError ResolvedGenerator(domain, conditions)
end
