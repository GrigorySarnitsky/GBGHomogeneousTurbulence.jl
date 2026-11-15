# Witness: the periodic wrap must not launder a non-finite tracer position into the box origin.
#
# The defect: the wrap was `X .= mod.(X, L)` followed by `X .= ifelse.(X .< L, X, zero(eltype(X)))`,
# the second pass folding the floating-point endpoint `mod(-1e-20, 2π) === 2π` back to 0. But every
# comparison against NaN is false, so a NaN position — and an Inf, since `mod(Inf, L) === NaN` —
# also took the `ifelse` FALSE branch and was written out as exactly `zero(eltype(X))`. Every
# `advect!` ends in the wrap, so a blown-up velocity field landed the whole tracer set on the origin
# with `all(isfinite, positions) == true`.
#
# Correct behaviour, either way round: a trajectory advanced by a non-finite velocity must NOT
# report finite positions — it either carries the non-finiteness through (so a downstream
# `all(isfinite, …)` health check can see it) or is rejected with an error. What must not happen is
# silent, finite-looking zeros.

using Test, Random
using GBGPeriodicFields: point_positions, npoints
using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data, PointSet
using GBGPeriodicFields.Interpolation: CatmullRom

include(joinpath(@__DIR__, "..", "prescribed_flow.jl"))

const N = 16

# Advance one step with a poisoned velocity; return (:ok, positions) or (:rejected, err).
function poisoned_step(poison)
  domain = FixedDomain(grid_points_per_axis = N, side_length = 2π,
                       element_type = Float64, dealiasing = TwoThirds(), array_family = Array)
  tracers = Tracers(domain; positions = PointSet([1.0 2.0 3.0; 0.5 0.5 0.5]),
                    interpolation_scheme = CatmullRom)
  cache = ObservablesCache(domain; tracers, particle_integration_scheme = Heun())
  try
    advect_in_prescribed_flow!((u, t) -> (field_data(u) .= poison; u), Heun(), tracers, domain, cache, (0.01,))
  catch err
    return (:rejected, err)
  end
  return (:ok, copy(Array(point_positions(tracers.positions))))
end


@testset "a non-finite velocity does not produce finite-looking tracer positions" begin

  @testset "bare advect!, poison = $poison" for poison in (NaN, Inf)
    outcome, payload = poisoned_step(poison)
    if outcome === :rejected
      @test payload isa Exception          # a clean rejection is an acceptable answer
    else
      @test !all(isfinite, payload)        # the blow-up must remain visible in the positions
      @test payload != zeros(size(payload))
    end
  end

  @testset "front door: advance! with a hand-fixed dt" begin
    sim = Simulation(grid_points_per_axis = N, particles = ParticleTracking(number_of_particles = 4),
                     rng = MersenneTwister(1234))
    field_data(sim.state.velocity_spectral) .= NaN
    # Refresh the cache's fields from the poisoned state.
    deposit!(sim.cache, sim.state, sim.domain, sim.buffers)
    local X
    rejected = false
    try
      advance!(sim; dt = 0.01)
      X = copy(Array(point_positions(sim.tracers.positions)))
    catch err
      rejected = true
    end
    if !rejected
      @test !all(isfinite, X)
      @test X != zeros(size(X))
    else
      @test true                            # blowing up loudly is the acceptable alternative
    end
  end
end
