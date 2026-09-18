# Witness test-critic-03 — the AdamsBashforth docstring's convergence claim, measured end to end.
#
# `AdamsBashforth`'s docstring states that over a fixed window `order = 4` converges at about third
# order rather than fourth — "3.0 against 2.0 for the two-step method, with an error some fifty times
# smaller at equal step count" — because the `order - 1` bootstrap steps are taken with
# `Heun`. Nothing in the suite advanced a trajectory and measured that ratio: the existing
# checks pin `_adams_bashforth_weights` in isolation, or run `advect!` and only assert that the
# positions moved and stayed in the box. The wiring between the weight vector `b[j]` and the rotated
# history `past[j-1]` — a transposition, or an off-by-one in the shift-loop range for K > 2 — is
# exactly what a convergence ratio detects and a "positions changed" check does not.
#
# The setup mirrors the existing "Heun-in-time is second order" test: a spatially uniform,
# time-varying velocity u = cos(ωt) x̂, so interpolation is exact and the only error is temporal, and
# the trajectory is the analytic ∫₀ᵀ cos(ωt) dt.

using GBGHomogeneousTurbulence
using GBGPeriodicFields: point_positions, npoints
using GBGPeriodicFields: VectorFieldPhysical, field_data, CatmullRom, PointSet
using Test


set_uniform_x!(uf, cx) = (d = field_data(uf); d .= 0; @views(d[:, :, :, 1] .= cx); uf)


@testset "AdamsBashforth(order = 4) converges at third order end to end, order = 2 at second" begin
  T = Float64
  N = 16
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_type = Array)

  ω = 1.0
  Tfinal = 0.5
  X0 = T[1.0 1.0 1.0]
  exact_x = X0[1, 1] + sin(ω * Tfinal) / ω                    # ∫₀ᵀ cos(ωt) dt

  # One tracer, a fixed step schedule, the two-verb push a run performs: record the sample at tₙ,
  # then advect. The multistep history is the cache's, so the cache is sized by the scheme's depth.
  final_x(scheme, nsteps) = begin
    tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
    cache = ObservablesCache(domain; number_of_particles = npoints(tracers.positions),
                             history_depth = history_depth(scheme))
    buffers = allocate_buffers(scheme, tracers, cache)
    u_start = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)
    u_end = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)
    dt = Tfinal / nsteps
    for n in 0:nsteps-1
      set_uniform_x!(u_start, cos(ω * n * dt))
      set_uniform_x!(u_end, cos(ω * (n + 1) * dt))            # only the bootstrap Heun steps read it
      deposit!(cache, tracers, u_start)
      advect!(scheme, tracers, u_end, domain, buffers, dt)
    end
    point_positions(tracers.positions)[1, 1]
  end

  error_ratio(scheme, coarse, fine) = abs(final_x(scheme, coarse) - exact_x) /
                                      abs(final_x(scheme, fine) - exact_x)

  ab4 = AdamsBashforth(order = 4)
  ab2 = AdamsBashforth(order = 2)

  # Third order ⇒ halving the step divides the error by ≈ 8. A transposed weight/history pairing or
  # an off-by-one in the shift would drop this to ≈ 2 or ≈ 4.
  @test 7.0 < error_ratio(ab4, 16, 32) < 9.0
  @test 7.0 < error_ratio(ab4, 32, 64) < 9.0

  # The two-step method's documented 2.0, measured the same way.
  @test 3.5 < error_ratio(ab2, 16, 32) < 4.5

  # "an error some fifty times smaller at equal step count" — the same window, same step count.
  @test abs(final_x(ab2, 32) - exact_x) / abs(final_x(ab4, 32) - exact_x) > 20.0
end
