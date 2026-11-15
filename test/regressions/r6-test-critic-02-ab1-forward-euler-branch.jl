# AB(1) — the scheme with nothing to start: it integrates over one sample, which a run has from its
# seeding deposit, so the update runs from step one as forward Euler on the DEPOSITED sample u(t_n),
# with the field at t_{n+1} never read by the step. The suite once exercised only two and four steps
# through `advect!`; this pins k = 1 end-to-end: the exact Euler recursion, the unread end-of-step
# field, and first-order convergence (ratio ≈ 2, not Heun's ≈ 4).

using GBGHomogeneousTurbulence
using GBGPeriodicFields: point_positions
using GBGPeriodicFields: field_data, PointSet, CatmullRom
using Test

include(joinpath(@__DIR__, "..", "prescribed_flow.jl"))


set_uniform_x!(uf, cx) = (d = field_data(uf); d .= 0; @views(d[:, :, :, 1] .= cx); uf)


@testset "AB(1) is forward Euler on the deposited sample from step one" begin
  T = Float64
  N = 16
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_family = Array)
  scheme = AB(1)
  ω = 1.0
  Tfinal = 0.5

  # One run: nsteps of AB(1) in the time-varying uniform field u_x(t) = cos(ωt). While the particle
  # step runs, the cache's velocity — the field at t_{n+1} — is poisoned with NaN: the k = 1 update
  # must never read it. The true field is written back for the closing deposit, which does.
  final_x(nsteps; poison_end = true) = begin
    X0 = T[1.0 1.0 1.0]
    tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
    cache = ObservablesCache(domain; tracers, particle_integration_scheme = scheme)
    dt = Tfinal / nsteps
    deposit_prescribed_velocity!(u -> set_uniform_x!(u, cos(0.0)), cache; step = false)
    deposit!(cache, tracers, 0.0)
    for n in 0:nsteps-1
      true_end = cos(ω * (n + 1) * dt)
      deposit_prescribed_velocity!(u -> set_uniform_x!(u, poison_end ? T(NaN) : true_end), cache)
      advect!(scheme, tracers, domain, cache, dt)
      deposit_prescribed_velocity!(u -> set_uniform_x!(u, true_end), cache; step = false)
      deposit!(cache, tracers, (n + 1) * dt)
    end
    point_positions(tracers.positions)[1, 1]
  end

  # (1) The trajectory IS the explicit forward-Euler recursion X_{n+1} = X_n + dt·u(t_n) —
  #     no averaging with the end-of-step sample, from the very first step.
  nsteps = 8
  dt = Tfinal / nsteps
  euler_x = 1.0
  for n in 0:nsteps-1
    euler_x += dt * cos(ω * n * dt)
  end
  @test final_x(nsteps) ≈ euler_x atol = 1e-12

  # (2) The end-of-step field was NaN throughout every step and the positions are still finite —
  #     it is never read at k = 1.
  @test isfinite(final_x(nsteps))

  # (3) Self-convergence order is ≈ 1 (halving dt halves the error), NOT Heun's ≈ 2 —
  #     discriminating a k = 1 scheme that silently took (or stayed in) corrected steps.
  exact_x = 1.0 + sin(ω * Tfinal) / ω
  error_coarse = abs(final_x(8; poison_end = false) - exact_x)
  error_fine = abs(final_x(16; poison_end = false) - exact_x)
  @test 1.5 < error_coarse / error_fine < 3.0
end
