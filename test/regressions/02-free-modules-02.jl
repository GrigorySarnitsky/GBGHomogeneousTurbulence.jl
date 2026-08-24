# Witness: the periodic wrap must not fabricate a finite coordinate out of a non-finite one.
#
# The contract was IT's `_wrap!` and is now PF's (`wrap!` and the grid form of `displace!`, their
# decision 73, adopted verbatim from this witness's findings): the excluded endpoint `L` folds to
# `0` (floating-point `mod` can return exactly `L` for a hair-below-zero coordinate), and the fold
# tests equality — an order test is false for NaN/Inf and would silently relocate a blown-up
# trajectory to a tidy in-box position, destroying the one signal a run has diverged. This witness
# pins that contract AT IT'S BOUNDARY — the surface `advect!` actually calls — so a PF regression
# on either half fails here, not just in PF's own suite.

using GBGIsotropicTurbulence
using GBGPeriodicFields: VectorFieldPhysical, field_data, CatmullRom, point_values, PointSet,
                         PointSet, wrap!, point_coordinates
using Test

@testset "a non-finite tracer coordinate is never turned into a healthy 0.0" begin
  L = 2π
  T = Float64
  N = 16
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_type = Array)

  @testset "wrap! preserves non-finiteness" begin
    X = [NaN 1.0 1.0
         Inf 2.0 2.0
         -Inf 3.0 3.0]
    wrap!(PointSet(X), domain.grid)
    @test !isfinite(X[1, 1])          # NaN in -> non-finite out
    @test !isfinite(X[2, 1])          # +Inf in -> non-finite out
    @test !isfinite(X[3, 1])          # -Inf in -> non-finite out
    # the finite coordinates are untouched by the same call
    @test X[1, 2] ≈ 1.0 && X[2, 2] ≈ 2.0 && X[3, 2] ≈ 3.0
  end

  @testset "wrap! still folds the excluded endpoint and wraps normally" begin
    Y = [0.0 L 1.5L; -1e-20 -0.5 L + 0.25]
    wrap!(PointSet(Y), domain.grid)
    @test all(0 .<= Y .< L)           # half-open box [0, L)
    @test Y[1, 1] == 0.0
    @test Y[1, 2] == 0.0              # the endpoint L folds to 0
    @test Y[1, 3] ≈ 0.5L
    @test Y[2, 1] == 0.0              # the mod(-1e-20, 2π) === 2π case folds to 0
    @test Y[2, 2] ≈ L - 0.5
    @test Y[2, 3] ≈ 0.25
  end

  @testset "advect! does not launder a blown-up velocity into finite positions" begin
    u = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)

    X0 = T[0.1 0.2 0.3; 1.0 2.0 3.0]
    tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
    cache = ObservablesCache(domain; number_of_particles = number_of_particles(tracers))
    buffers = allocate_buffers(Heun(), tracers, cache)

    field_data(u) .= NaN                       # the ordinary blow-up mode of an over-stepped run
    deposit!(cache, tracers, u)     # v1 <- u(t_n, X(t_n)), now non-finite
    @test !all(isfinite, point_values(cache.velocity_at_particles))

    threw = false
    try
      advect!(Heun(), tracers, u, domain, buffers, 0.01)
    catch
      threw = true
    end
    # either the push refuses the non-finite state, or the corruption stays visible downstream
    @test threw || !all(isfinite, particle_positions(tracers))
  end
end
