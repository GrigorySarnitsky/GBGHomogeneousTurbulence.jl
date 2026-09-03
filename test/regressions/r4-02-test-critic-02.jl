# Round 4, lane test-critic, witness 02.
#
# The `Tracers(domain; …)` keyword contract, asserted directly: the two construction forms are ONE
# method distinguished by which keyword is supplied, so the constructor must demand EXACTLY one of
# `positions` / `number_of_particles` (neither and both are errors, not a silent preference), and it
# must refuse a positions array whose second dimension is not 3. Neither guard was reached by any
# call in the suite before this file existed.

using GBGIsotropicTurbulence
using GBGPeriodicFields: point_positions, npoints
using GBGPeriodicFields: CatmullRom, PointSet
using Test


@testset "Tracers demands exactly one of `positions` / `number_of_particles`, and an (M, 3) shape" begin
  domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_type = Array)

  # Both keywords: ambiguous, must be rejected — never silently preferring one.
  @test_throws ArgumentError Tracers(domain; number_of_particles = 4, positions = PointSet(zeros(4, 3)),
                                     interpolation_scheme = CatmullRom)

  # Neither keyword: nothing to build from, must be rejected.
  @test_throws ArgumentError Tracers(domain; interpolation_scheme = CatmullRom)

  # A positions array whose second dimension is not 3 is not a set of 3-D positions.
  # A raw array where the PointSet is expected is refused by Tracers itself — coordinates cross
  # into the package only through the GBGPeriodicFields point types (decision 66).
  @test_throws ArgumentError Tracers(domain; positions = zeros(4, 3),
                                     interpolation_scheme = CatmullRom)
  # A malformed shape is refused one layer down, by PointSet's own constructor.
  @test_throws DimensionMismatch Tracers(domain; positions = PointSet(zeros(4, 2)),
                                         interpolation_scheme = CatmullRom)

  # And the two legal forms still build, so the guard has not over-fired.
  @test size(point_positions(Tracers(domain; positions = PointSet(zeros(4, 3)),
                                       interpolation_scheme = CatmullRom).positions)) == (4, 3)
  @test npoints(Tracers(domain; number_of_particles = 5,
                        interpolation_scheme = CatmullRom).positions) == 5
end
