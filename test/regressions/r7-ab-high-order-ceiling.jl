# Pins the AB study of 2026-08-24 (owner-ruled): over a fixed window, `order = 6` and `order = 8`
# converge at the SAME third order as `order = 4` — the Heun bootstrap is the ceiling — and their
# errors are LARGER (the longer bootstrap costs more than the extra history returns). The docstring
# now states "order = 4 is the practical ceiling"; this is its witness. Setup mirrors
# 03-test-critic-03: uniform time-varying flow, interpolation exact, trajectory analytic.
using GBGHomogeneousTurbulence
using GBGPeriodicFields: point_positions, npoints
using GBGPeriodicFields: VectorFieldPhysical, field_data, CatmullRom, PointSet
using Test


set_uniform_x!(uf, cx) = (d = field_data(uf); d .= 0; @views(d[:, :, :, 1] .= cx); uf)


@testset "AdamsBashforth orders 6 and 8: still third order, and worse than order 4" begin
  T = Float64
  N = 16
  domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, element_type = T,
                       dealiasing = TwoThirds(), array_type = Array)
  ω = 1.0; Tfinal = 0.5
  exact_x = 1.0 + sin(ω * Tfinal) / ω

  final_x(scheme, nsteps) = begin
    tracers = Tracers(domain; positions = PointSet(T[1.0 1.0 1.0]), interpolation_scheme = CatmullRom)
    cache = ObservablesCache(domain; number_of_particles = npoints(tracers.positions),
                             history_depth = history_depth(scheme))
    buffers = allocate_buffers(scheme, tracers, cache)
    u_start = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)
    u_end = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)
    dt = Tfinal / nsteps
    for n in 0:nsteps-1
      set_uniform_x!(u_start, cos(ω * n * dt))
      set_uniform_x!(u_end, cos(ω * (n + 1) * dt))
      deposit!(cache, tracers, u_start)
      advect!(scheme, tracers, u_end, domain, buffers, dt)
    end
    point_positions(tracers.positions)[1, 1]
  end

  err(K, n) = abs(final_x(AdamsBashforth(order = K), n) - exact_x)
  for K in (6, 8)
    order = log2(err(K, 80) / err(K, 160))
    @test 2.6 < order < 3.4                        # the bootstrap's ceiling, not K - 1
    @test err(K, 80) > err(4, 80)                  # and strictly worse than order 4
  end
end
