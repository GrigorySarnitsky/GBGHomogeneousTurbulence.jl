# Witness r4-edge-cases-03 — claim: `Tracers(domain; positions = ...)` never wraps caller-supplied
# positions into [0, L), so a position sitting exactly on the excluded upper endpoint L (or outside
# the box) is read by the interpolation at a different place than its periodic image.
#
# The assertion below is the CORRECT behaviour: a tracer placed at the periodic image of a point must
# see the same interpolated velocity as one placed at the point itself, exactly as `_wrap!` guarantees
# for every position that reaches the boundary through `advect!`.

using GBGIsotropicTurbulence
using GBGPeriodicFields: npoints
using GBGPeriodicFields: VectorFieldPhysical, field_data, CatmullRom, point_values, PointSet
using Test

@testset "hand-built tracer positions are read periodically (x = L is the same point as x = 0)" begin
  T = Float64
  N = 16
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_type = Array)

  # A spatially varying, band-limited velocity: the value at x = 0 differs from a neighbouring cell,
  # so an off-by-one-cell read would show up immediately.
  u = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)
  d = field_data(u)
  Δ = L / N
  for k in 1:N, j in 1:N, i in 1:N
    x, y, z = (i - 1) * Δ, (j - 1) * Δ, (k - 1) * Δ
    d[i, j, k, 1] = sin(x) * cos(y)
    d[i, j, k, 2] = cos(x) * sin(z)
    d[i, j, k, 3] = sin(2x) + cos(y)
  end

  sample(X) = begin
    tracers = Tracers(domain; positions = PointSet(copy(X)), interpolation_scheme = CatmullRom)
    cache = ObservablesCache(domain; number_of_particles = npoints(tracers.positions))
    deposit!(cache, tracers, u)
    copy(point_values(cache.velocity_at_particles))
  end

  # (a) the excluded upper endpoint against its image at 0 — the case `_wrap!`'s own comment names
  v_endpoint = sample(T[L 0.3 0.7])
  v_image    = sample(T[0.0 0.3 0.7])
  @test v_endpoint ≈ v_image

  # (b) the same, on all three axes at once
  @test sample(T[L L L]) ≈ sample(T[0.0 0.0 0.0])

  # (c) a position outside the box, against its periodic image inside it
  @test sample(T[L+0.4 0.3 0.7]) ≈ sample(T[0.4 0.3 0.7])
  @test sample(T[-0.4 0.3 0.7]) ≈ sample(T[L-0.4 0.3 0.7])
end
