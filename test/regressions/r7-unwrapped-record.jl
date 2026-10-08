# Decision 65: wrapped dynamics, opt-in unwrapped record. The wrapped positions are the dynamical
# state and stay in [0, L); the unwrapped record receives the SAME displacement terms through the
# grid-free displace! and keeps the winding — on a uniform steady flow the Heun push is exact, so
# the record must equal the analytic X₀ + u·t across several box crossings while the wrapped
# positions equal its box reduction. A reposition announced through particles_modified! restarts
# the record (winding belongs to the abandoned trajectory), and an untracked set refuses the read.
using Test, Random
using GBGPeriodicFields: point_positions, npoints
using GBGHomogeneousTurbulence
using GBGPeriodicFields: VectorFieldPhysical, field_data, CatmullRom, PointSet


set_uniform_x!(uf, cx) = (d = field_data(uf); d .= 0; @views(d[:, :, :, 1] .= cx); uf)


@testset "the unwrapped record keeps winding; the wrapped positions keep the box" begin
  T = Float64
  N = 16
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_family = Array)
  u = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)
  set_uniform_x!(u, 1.0)                                # steady uniform flow: Heun is exact

  X0 = T[1.0 1.0 1.0]
  tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom,
                    unwrapped = true)
  cache = ObservablesCache(domain; number_of_particles = npoints(tracers.positions))
  buffers = allocate_buffers(Heun(), tracers, cache)
  nsteps = 160
  dt = T(2.5) * L / nsteps                              # total drift 2.5 boxes in x
  for _ in 1:nsteps
    deposit!(cache, tracers, u)
    advect!(Heun(), tracers, u, domain, buffers, dt)
  end
  Xw = point_positions(tracers.positions)
  Xu = point_positions(unwrapped_positions(tracers))
  @test Xu[1, 1] ≈ X0[1, 1] + 2.5L rtol = 1e-12          # winding kept, analytically exact
  @test Xu[1, 2] ≈ 1.0 && Xu[1, 3] ≈ 1.0
  @test 0 <= Xw[1, 1] < L                                # the dynamics stayed wrapped
  @test Xw[1, 1] ≈ mod(Xu[1, 1], L) rtol = 1e-10         # and the two agree modulo the box

  # The AdamsBashforth path shares the terms: same flow, same drift, both records advanced.
  ab = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom, unwrapped = true)
  sim_free_cache = ObservablesCache(domain; number_of_particles = npoints(ab.positions),
                                    history_depth = history_depth(AdamsBashforth(order = 2)))
  ab_buffers = allocate_buffers(AdamsBashforth(order = 2), ab, sim_free_cache)
  for _ in 1:nsteps
    deposit!(sim_free_cache, ab, u)
    advect!(AdamsBashforth(order = 2), ab, u, domain, ab_buffers, dt)
  end
  @test point_positions(unwrapped_positions(ab))[1, 1] ≈ X0[1, 1] + 2.5L rtol = 1e-10

  # An untracked set refuses the read with an actionable error.
  bare = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
  @test_throws ArgumentError point_positions(unwrapped_positions(bare))

  # A reposition through the run's announcement restarts the record at the new positions.
  sim = Simulation(domain; viscosity = 0.05, number_of_particles = 4, unwrapped = true,
                   rng = MersenneTwister(1))
  for _ in 1:3; advance!(sim); end
  point_positions(sim.tracers.positions) .= 0.5                 # hand reposition (out-of-band)
  particles_modified!(sim)
  @test all(point_positions(unwrapped_positions(sim.tracers)) .== 0.5)    # winding restarted with the new path
end
