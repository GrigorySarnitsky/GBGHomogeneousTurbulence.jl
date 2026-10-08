# Witness: `advect!` documents "positions wrapped into [0, L)", but the wrap is `mod.(X, L)`, and
# Base.mod's own docstring warns that with floating point "if the exact result is very close to `y`,
# then it may be rounded to `y`" (docs.julialang.org/en/v1/base/math/#Base.mod). A coordinate that
# lands in the sub-ULP negative band before the wrap therefore comes back as exactly `L`.
#
# This file asserts the CORRECT behaviour: every returned coordinate is strictly less than L.

using GBGHomogeneousTurbulence
using GBGPeriodicFields: point_positions, npoints
using GBGPeriodicFields: VectorFieldPhysical, field_data, CatmullRom, PointSet
using Test

set_uniform_x!(uf, cx) = (d = field_data(uf); d .= 0; @views(d[:, :, :, 1] .= cx); uf)

@testset "advect! returns tracer positions strictly inside [0, L)" begin
  T = Float64
  N = 16
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_family = Array)
  u = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)

  @testset "physically-sized velocity, coordinate cancelling to a sub-ULP negative" begin
    # dt * v₁ = -1.0e-3 exactly; starting x = prevfloat(1.0e-3), so the Sterbenz-exact difference is
    # -ulp(1.0e-3) ≈ -2.2e-19 — magnitude far below eps(L)/2 ≈ 7.7e-16, hence inside the band.
    dt = 1.0e-3
    X0 = T[prevfloat(1.0e-3) 1.0 1.0]
    tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
    cache = ObservablesCache(domain; number_of_particles = npoints(tracers.positions))
    buffers = allocate_buffers(Heun(), tracers, cache)
    set_uniform_x!(u, -1.0)
    deposit!(cache, tracers, u)
    advect!(Heun(), tracers, u, domain, buffers, dt)
    X = point_positions(tracers.positions)
    @test all(0 .<= X)
    @test all(X .< L)
  end

  @testset "the same, reached from x = 0 with a tiny negative velocity" begin
    dt = 1.0
    X0 = T[0.0 1.0 1.0]
    tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
    cache = ObservablesCache(domain; number_of_particles = npoints(tracers.positions))
    buffers = allocate_buffers(Heun(), tracers, cache)
    set_uniform_x!(u, -1.0e-20)
    deposit!(cache, tracers, u)
    advect!(Heun(), tracers, u, domain, buffers, dt)
    X = point_positions(tracers.positions)
    @test all(X .< L)
  end
end
