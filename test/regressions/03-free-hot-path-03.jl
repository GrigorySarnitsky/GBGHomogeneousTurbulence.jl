# Witness: the periodic wrap must not launder a non-finite tracer position into the box origin.
#
# `_wrap!` (src/Particles.jl:216-220) is
#     X .= mod.(X, L)
#     X .= ifelse.(X .< L, X, zero(eltype(X)))
# The second pass exists to fold the floating-point endpoint `mod(-1e-20, 2π) === 2π` back to 0
# (the comment at Particles.jl:211-215). But every comparison against NaN is false, so a NaN
# position — and an Inf, since `mod(Inf, L) === NaN` — also takes the `ifelse` FALSE branch and is
# written out as exactly `zero(eltype(X))`. Every `advect!` ends in `_wrap!`, so a blown-up
# velocity field lands the whole tracer set on the origin with `all(isfinite, positions) == true`.
#
# Correct behaviour, either way round: a trajectory advanced by a non-finite velocity must NOT
# report finite positions — it either carries the non-finiteness through (so a downstream
# `all(isfinite, …)` health check can see it) or is rejected with an error. What must not happen is
# the current outcome: silent, finite-looking zeros.

using Test, Random
using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Particles: EndpointHeun, advect!, record_particle_velocities!,
                                        particle_positions
using GBGIsotropicTurbulence.Propagator: allocate_buffers
using GBGPeriodicFields: field_data
using GBGPeriodicFields.Interpolation: CatmullRom

const N = 16

# Advance one step with a poisoned velocity; return (:ok, positions) or (:rejected, err).
function poisoned_step(poison)
  domain = FixedDomain(grid_points_per_axis = N, side_length = 2π,
                       element_type = Float64, dealiasing = TwoThirds(), array_type = Array)
  u = new_vector_field_physical(domain)
  field_data(u) .= poison
  tracers = Tracers(domain; positions = [1.0 2.0 3.0; 0.5 0.5 0.5],
                    interpolation_scheme = CatmullRom)
  buffers = allocate_buffers(EndpointHeun(), tracers)
  record_particle_velocities!(tracers, u)
  try
    advect!(EndpointHeun(), tracers, u, domain, buffers, 0.01)
  catch err
    return (:rejected, err)
  end
  return (:ok, copy(Array(particle_positions(tracers))))
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
    sim = Simulation(grid_points_per_axis = N, number_of_particles = 4,
                     rng = MersenneTwister(1234))
    field_data(sim.state.velocity_spectral) .= NaN
    fields_modified!(sim.cache)        # announce the out-of-band mutation …
    deposit!(sim)                      # … and refresh the cache from the poisoned state
    local X
    rejected = false
    try
      advance!(sim; dt = 0.01)
      X = copy(Array(particle_positions(sim.tracers)))
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
