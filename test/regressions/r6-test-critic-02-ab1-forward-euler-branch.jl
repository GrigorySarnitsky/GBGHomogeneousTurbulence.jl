# AdamsBashforth(order = 1) — the bootstrap-free branch: `history_filled < K - 1` is
# `0 < 0`, false from the first call, so the multistep update runs from step one as forward
# Euler on the DEPOSITED sample u(t_n), with `velocity_end` (the t_{n+1} field) never read.
# The suite exercises only order = 2 and order = 4 through `advect!`; this pins K = 1
# end-to-end: the exact Euler recursion, the unread endpoint, and first-order convergence
# (ratio ≈ 2, not Heun's ≈ 4).

using GBGIsotropicTurbulence
using GBGPeriodicFields: point_positions, npoints
using GBGPeriodicFields: VectorFieldPhysical, field_data, PointSet, CatmullRom
using Test


set_uniform_x!(uf, cx) = (d = field_data(uf); d .= 0; @views(d[:, :, :, 1] .= cx); uf)


@testset "AdamsBashforth(order = 1) is forward Euler on the deposited sample from step one" begin
  T = Float64
  N = 16
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_type = Array)
  scheme = AdamsBashforth(order = 1)
  ω = 1.0
  Tfinal = 0.5

  # One run: nsteps of AB1 in the time-varying uniform field u_x(t) = cos(ωt).
  # u_end is poisoned with a WRONG value (NaN) — the K = 1 update must never read it.
  final_x(nsteps; poison_end = true) = begin
    X0 = T[1.0 1.0 1.0]
    tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
    cache = ObservablesCache(domain; number_of_particles = npoints(tracers.positions))
    buffers = allocate_buffers(scheme, tracers, cache)
    u_start = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)
    u_end = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)
    dt = Tfinal / nsteps
    for n in 0:nsteps-1
      set_uniform_x!(u_start, cos(ω * n * dt))
      set_uniform_x!(u_end, poison_end ? T(NaN) : cos(ω * (n + 1) * dt))
      deposit!(cache, tracers, u_start)
      advect!(scheme, tracers, u_end, domain, buffers, dt)
    end
    point_positions(tracers.positions)[1, 1]
  end

  # (1) The trajectory IS the explicit forward-Euler recursion X_{n+1} = X_n + dt·u(t_n) —
  #     no averaging with the endpoint sample, from the very first step (no Heun bootstrap).
  nsteps = 8
  dt = Tfinal / nsteps
  euler_x = 1.0
  for n in 0:nsteps-1
    euler_x += dt * cos(ω * n * dt)
  end
  @test final_x(nsteps) ≈ euler_x atol = 1e-12

  # (2) velocity_end was NaN throughout and the positions are still finite — the endpoint
  #     field is never read at K = 1.
  @test isfinite(final_x(nsteps))

  # (3) Self-convergence order is ≈ 1 (halving dt halves the error), NOT Heun's ≈ 2 —
  #     discriminating a K = 1 branch that silently fell back to (or stuck in) Heun.
  exact_x = 1.0 + sin(ω * Tfinal) / ω
  error_coarse = abs(final_x(8; poison_end = false) - exact_x)
  error_fine = abs(final_x(16; poison_end = false) - exact_x)
  @test 1.5 < error_coarse / error_fine < 3.0
end
