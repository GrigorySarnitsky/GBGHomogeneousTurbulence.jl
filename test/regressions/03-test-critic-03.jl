# Witness test-critic-03 — the `AB` docstring's convergence claim, measured end to end.
#
# `AB`'s docstring states that the lower-order steps a multistep scheme starts with leave an error of
# third order behind, so that over a fixed window `AB(4)` converges at third order rather than
# fourth. Nothing in the suite once advanced a trajectory and measured that ratio: the checks of the
# day pinned the weights in isolation, or ran `advect!` and only asserted that the positions moved
# and stayed in the box. The wiring between the weights and the samples they multiply — a
# transposition, or an off-by-one in which sample is which — is exactly what a convergence ratio
# detects and a "positions changed" check does not.
#
# The setup is a spatially uniform, time-varying velocity u = cos(ωt) x̂, so interpolation is exact
# and the only error is temporal, and the trajectory is the analytic ∫₀ᵀ cos(ωt) dt. (A uniform flow
# cannot see a scheme's predictor; the orders of the corrected schemes are measured in
# test/particles.jl on a flow that varies in space.)

using GBGHomogeneousTurbulence
using GBGPeriodicFields: point_positions, npoints
using GBGPeriodicFields: VectorFieldPhysical, field_data, CatmullRom, PointSet
using Test


include(joinpath(@__DIR__, "..", "prescribed_flow.jl"))

set_uniform_x!(uf, cx) = (d = field_data(uf); d .= 0; @views(d[:, :, :, 1] .= cx); uf)


@testset "AB(4) converges at third order end to end, AB(2) at second" begin
  T = Float64
  N = 16
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_family = Array)

  ω = 1.0
  Tfinal = 0.5
  X0 = T[1.0 1.0 1.0]
  exact_x = X0[1, 1] + sin(ω * Tfinal) / ω                    # ∫₀ᵀ cos(ωt) dt

  # One tracer, a fixed step schedule, the iteration a run performs: the field at the new time, the
  # particle step, the sample at the new positions. The cache is built for the scheme.
  final_x(scheme, nsteps) = begin
    tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
    cache = ObservablesCache(domain; tracers, particle_integration_scheme = scheme)
    advect_in_prescribed_flow!((u, t) -> set_uniform_x!(u, cos(ω * t)), scheme, tracers, domain, cache,
                               fill(Tfinal / nsteps, nsteps))
    point_positions(tracers.positions)[1, 1]
  end

  error_ratio(scheme, coarse, fine) = abs(final_x(scheme, coarse) - exact_x) /
                                      abs(final_x(scheme, fine) - exact_x)

  ab4 = AB(4)
  ab2 = AB(2)

  # Third order ⇒ halving the step divides the error by ≈ 8. A transposed weight/history pairing or
  # an off-by-one in the shift would drop this to ≈ 2 or ≈ 4.
  @test 7.0 < error_ratio(ab4, 16, 32) < 9.0
  @test 7.0 < error_ratio(ab4, 32, 64) < 9.0

  # The two-step method's documented 2.0, measured the same way.
  @test 3.5 < error_ratio(ab2, 16, 32) < 4.5

  # "an error some fifty times smaller at equal step count" — the same window, same step count.
  @test abs(final_x(ab2, 32) - exact_x) / abs(final_x(ab4, 32) - exact_x) > 20.0
end
