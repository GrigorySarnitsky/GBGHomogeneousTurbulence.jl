# Witness: `derivative_skewness` must honour the `Observables` element-type contract —
# "Each returns the field's own real element type rather than a fixed `Float64`, so a `Float32` run
# measures in `Float32`" (src/Observables.jl module docstring) — on EVERY return path, including the
# degenerate ⟨S:S⟩ ≤ 0 guard at src/Observables.jl:278 (`ss <= 0 && return 0.0`).
#
# The degenerate state is reachable: a freshly built `ResolvedFields(domain)` has an identically
# zero velocity field, so ⟨S:S⟩ is exactly zero before any seeding.

using Test
using GBGHomogeneousTurbulence

@testset "derivative_skewness returns the field's own element type on the degenerate zero-field path" begin
  for T in (Float32, Float64)
    domain = FixedDomain(; grid_points_per_axis = 8, side_length = 2π,
                           dealiasing = TwoThirds(), element_type = T, array_family = Array)
    state = ResolvedFields(domain)                     # velocity left at its zeroed default

    S = derivative_skewness(state.velocity_spectral, domain)

    @test S == 0                                       # the degenerate value itself is fine
    @test typeof(S) === T                              # …but it must carry the run's element type
  end
end
