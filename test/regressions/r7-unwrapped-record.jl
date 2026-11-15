# Decision 65: wrapped dynamics, opt-in unwrapped record. The wrapped positions are the dynamical
# state and stay in [0, L); the unwrapped record receives the SAME displacement terms through the
# grid-free displace! and keeps the winding — on a uniform steady flow every push is exact, so
# the record must equal the analytic X₀ + u·t across several box crossings while the wrapped
# positions equal its box reduction. An untracked set refuses the read.
using Test
using GBGPeriodicFields: point_positions, npoints
using GBGHomogeneousTurbulence
using GBGPeriodicFields: VectorFieldPhysical, field_data, CatmullRom, PointSet


include(joinpath(@__DIR__, "..", "prescribed_flow.jl"))

set_uniform_x!(uf, cx) = (d = field_data(uf); d .= 0; @views(d[:, :, :, 1] .= cx); uf)


@testset "the unwrapped record keeps winding; the wrapped positions keep the box" begin
  T = Float64
  N = 16
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_family = Array)
  steady!(u, t) = set_uniform_x!(u, 1.0)                # steady uniform flow: every scheme is exact

  X0 = T[1.0 1.0 1.0]
  nsteps = 160
  dt = T(2.5) * L / nsteps                              # total drift 2.5 boxes in x
  drifted(scheme) = begin
    tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom,
                      unwrapped = true)
    cache = ObservablesCache(domain; tracers, particle_integration_scheme = scheme)
    advect_in_prescribed_flow!(steady!, scheme, tracers, domain, cache, fill(dt, nsteps))
    tracers
  end

  tracers = drifted(Heun())
  Xw = point_positions(tracers.positions)
  Xu = point_positions(unwrapped_positions(tracers))
  @test Xu[1, 1] ≈ X0[1, 1] + 2.5L rtol = 1e-12          # winding kept, analytically exact
  @test Xu[1, 2] ≈ 1.0 && Xu[1, 3] ≈ 1.0
  @test 0 <= Xw[1, 1] < L                                # the dynamics stayed wrapped
  @test Xw[1, 1] ≈ mod(Xu[1, 1], L) rtol = 1e-10         # and the two agree modulo the box

  # The other schemes share the terms: same flow, same drift, both records advanced — the plain
  # multistep sum, and the corrected one, whose correction the unwrapped record must take too.
  for scheme in (AB(2), AB(4), ABM(3))
    other = drifted(scheme)
    @test point_positions(unwrapped_positions(other))[1, 1] ≈ X0[1, 1] + 2.5L rtol = 1e-10
    @test point_positions(other.positions)[1, 1] ≈ mod(X0[1, 1] + 2.5L, L) rtol = 1e-9
  end

  # An untracked set refuses the read with an actionable error.
  bare = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
  @test_throws ArgumentError point_positions(unwrapped_positions(bare))
end
