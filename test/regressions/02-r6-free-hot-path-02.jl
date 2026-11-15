# r6-free-hot-path-02: a cache and a particle scheme that do not belong together.
#
# The defect: a separate allocator of scheme registers admitted a cache whose sample history was
# deeper than the scheme's, and the first push then threw with a message blaming the registers for
# being "built for a different order" although this scheme's own allocator had built them for this
# call. The rule drawn from it: a pairing must be refused where it is made, with the reason.
#
# There is no allocator any more — a scheme owns no storage — so the cache and the scheme meet at
# the particle step, and that is where a mismatch is refused: with an `ArgumentError` naming the two
# sample counts, before a single position has moved. A cache built for the scheme is accepted.

using Test
using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data, PointSet, CatmullRom, point_positions

include(joinpath(@__DIR__, "..", "prescribed_flow.jl"))

@testset "a cache built for another particle scheme is refused at the step, by name, with nothing moved" begin
  T = Float64
  N = 16
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_family = Array)
  X0 = T[0.1 0.2 0.3; 1.0 2.0 3.0; 2.0 3.0 4.0; 4.0 5.0 6.0]
  uniform!(u, t) = (d = field_data(u); d .= 0; @views(d[:, :, :, 1] .= 0.5); u)
  ready(built_for) = begin
    tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
    cache = ObservablesCache(domain; tracers, particle_integration_scheme = built_for)
    deposit_prescribed_velocity!(u -> uniform!(u, 0.0), cache; step = false)
    deposit!(cache, tracers, 0.0)
    deposit_prescribed_velocity!(u -> uniform!(u, 0.01), cache)
    tracers, cache
  end

  # A cache keeping more samples than the scheme works from, and one keeping fewer.
  for (built_for, scheme) in ((ABM(4), AB(3)), (Heun(), AB(3)), (AB(3), ABM(3)))
    tracers, cache = ready(built_for)
    refusal = try advect!(scheme, tracers, domain, cache, 0.01) catch err; err end
    @test refusal isa ArgumentError
    @test occursin("sample(s)", refusal.msg) && occursin("build the cache with the scheme", refusal.msg)
    @test point_positions(tracers.positions) == X0          # refused before anything moved
  end

  # The matching pair is accepted, and the push moves the tracers.
  tracers, cache = ready(AB(3))
  @test advect!(AB(3), tracers, domain, cache, 0.01) === tracers
  @test point_positions(tracers.positions) != X0
end
