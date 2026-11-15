# Pins the study of the high-order schemes' start-up, first made on 2026-08-24 (owner-ruled) and
# rerun on 2026-11-15 after the start-up changed.
#
# What the first study found: over a fixed window, six and eight steps converged at the SAME third
# order as four — the start-up was the ceiling — and their errors were LARGER, because the start-up
# was `Heun` for every one of the k − 1 first steps, and a longer start-up cost more than the extra
# samples returned. The docstring then called four steps "the practical ceiling".
#
# What the rerun finds, and this file asserts: the third order stands, since the first step is still
# taken on one sample; but the later first steps now use every sample present (ABM(2), ABM(3), …),
# so a longer scheme costs nothing — four, six and eight steps make the same error to a few percent,
# a third of what four steps made before (2.06, 2.03 and 2.03 against the old 6, 10 and 14, in units
# of 1e-8 at 80 steps). The docstrings now say that the order above three is lost in the ordinary
# start-up, not that it is harmful; `shortened_first_steps` restores it, which test/particles.jl
# pins on a flow that varies in space.
#
# Setup mirrors 03-test-critic-03: uniform time-varying flow, interpolation exact, trajectory analytic.
using GBGHomogeneousTurbulence
using GBGPeriodicFields: point_positions
using GBGPeriodicFields: field_data, CatmullRom, PointSet
using Test

include(joinpath(@__DIR__, "..", "prescribed_flow.jl"))


set_uniform_x!(uf, cx) = (d = field_data(uf); d .= 0; @views(d[:, :, :, 1] .= cx); uf)


@testset "above third order the ordinary start-up decides the error, and a longer scheme costs nothing" begin
  T = Float64
  N = 16
  domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, element_type = T,
                       dealiasing = TwoThirds(), array_family = Array)
  ω = 1.0; Tfinal = 0.5
  exact_x = 1.0 + sin(ω * Tfinal) / ω

  final_x(scheme, nsteps) = begin
    tracers = Tracers(domain; positions = PointSet(T[1.0 1.0 1.0]), interpolation_scheme = CatmullRom)
    cache = ObservablesCache(domain; tracers, particle_integration_scheme = scheme)
    advect_in_prescribed_flow!((u, t) -> set_uniform_x!(u, cos(ω * t)), scheme, tracers, domain, cache,
                               fill(Tfinal / nsteps, nsteps))
    point_positions(tracers.positions)[1, 1]
  end

  err(scheme, n) = abs(final_x(scheme, n) - exact_x)
  for scheme in (AB(6), AB(8), ABM(4), ABM(7))
    order = log2(err(scheme, 80) / err(scheme, 160))
    @test 2.6 < order < 3.4                        # the first step's ceiling, not the scheme's order
    @test isapprox(err(scheme, 80), err(AB(4), 80); rtol = 0.05)    # no worse than four steps, and no better
  end
  # The level itself, so that a start-up falling back to `Heun` throughout — the arrangement the
  # first study measured, 6e-8 here — would be seen.
  @test err(AB(4), 80) < 3e-8
  @test err(AB(8), 80) < 3e-8
end
