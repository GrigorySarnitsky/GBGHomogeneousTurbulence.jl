# Witness: `_wrap!` must not fabricate a finite coordinate out of a non-finite one.
#
# `_wrap!(X, L)` is `X .= mod.(X, L)` then `X .= ifelse.(X .< L, X, zero(eltype(X)))`. The second
# pass exists to fold the excluded endpoint `L` back to `0`. But `mod(NaN, L) === NaN`,
# `mod(Inf, L) === NaN`, and `NaN < L` is `false` — so every non-finite coordinate takes the
# `zero(eltype(X))` branch and a blown-up trajectory is silently relocated to the box corner with a
# finite, in-range, entirely fabricated position. The intended fold survives NaN when written the
# other way round: `ifelse.(X .>= L, zero(eltype(X)), X)`, since `NaN >= L` is also `false`.
#
# Correct behaviour asserted here: a non-finite coordinate stays non-finite through `_wrap!` and
# through `advect!` (or the call throws), while the endpoint fold `L -> 0` and ordinary wrapping
# keep working.

using GBGIsotropicTurbulence
using GBGPeriodicFields: VectorFieldPhysical, field_data, CatmullRom, point_values
using Test

const _wrap! = GBGIsotropicTurbulence.Particles._wrap!

@testset "a non-finite tracer coordinate is never turned into a healthy 0.0" begin
  L = 2π

  @testset "_wrap! preserves non-finiteness" begin
    X = [NaN 1.0 1.0
         Inf 2.0 2.0
         -Inf 3.0 3.0]
    _wrap!(X, L)
    @test !isfinite(X[1, 1])          # NaN in -> non-finite out
    @test !isfinite(X[2, 1])          # +Inf in -> non-finite out
    @test !isfinite(X[3, 1])          # -Inf in -> non-finite out
    # the finite coordinates are untouched by the same call
    @test X[1, 2] ≈ 1.0 && X[2, 2] ≈ 2.0 && X[3, 2] ≈ 3.0
  end

  @testset "_wrap! still folds the excluded endpoint and wraps normally" begin
    Y = [0.0 L 1.5L; -1e-20 -0.5 L + 0.25]
    _wrap!(Y, L)
    @test all(0 .<= Y .< L)           # half-open box [0, L)
    @test Y[1, 1] == 0.0
    @test Y[1, 2] == 0.0              # the endpoint L folds to 0
    @test Y[1, 3] ≈ 0.5L
    @test Y[2, 1] == 0.0              # the mod(-1e-20, 2π) === 2π case folds to 0
    @test Y[2, 2] ≈ L - 0.5
    @test Y[2, 3] ≈ 0.25
  end

  @testset "advect! does not launder a blown-up velocity into finite positions" begin
    T = Float64
    N = 16
    domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                         dealiasing = TwoThirds(), array_type = Array)
    u = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)

    X0 = T[0.1 0.2 0.3; 1.0 2.0 3.0]
    tracers = Tracers(domain; positions = copy(X0), interpolation_scheme = CatmullRom)
    buffers = allocate_buffers(EndpointHeun(), tracers)

    field_data(u) .= NaN                       # the ordinary blow-up mode of an over-stepped run
    record_particle_velocities!(tracers, u)     # v1 <- u(t_n, X(t_n)), now non-finite
    @test !all(isfinite, point_values(tracers.particle_velocities))

    threw = false
    try
      advect!(EndpointHeun(), tracers, u, domain, buffers, 0.01)
    catch
      threw = true
    end
    # either the push refuses the non-finite state, or the corruption stays visible downstream
    @test threw || !all(isfinite, particle_positions(tracers))
  end
end
