# Witness for the claim: "`advect!` reads the velocity-at-particles slot by direct array access,
# bypassing the cache's checked accessor, so it silently consumes a sample the cache itself
# considers stale."
#
# The correct behaviour this file asserts is the one the code and its docstrings actually promise:
# the start-of-step velocity v₁ is CONSUMED MID-ITERATION, after the step has advanced the fields
# epoch, and the value sitting in `tracers.velocity_at_particles` at that moment is exactly
# u(tₙ, X(tₙ)) — the right v₁ for the step just taken. `advance!` verifies its freshness at tₙ (its
# opening `velocity_at_particles(sim.cache)` guard) precisely because the later read cannot be checked:
# the cache's "stale" flag is by design raised between the step and the closing particle `deposit!`,
# and `advance!` itself calls `advect!` in exactly that window.
#
# So the assertions are:
#   (1) the run layer refuses to advance on a genuinely stale sample (the guard exists and fires);
#   (2) the hand-composed sequence the claim calls a "scheduling violation" — step!/deposit!/advect!,
#       with the cache reporting the sample stale in between — advances the trajectories to exactly
#       the positions `advance!` produces, i.e. the value `advect!` consumed was the correct v₁ and
#       nothing was silently corrupted.
# If (2) ever fails, the mid-iteration read really did consume a wrong value and the claim is real.

using GBGIsotropicTurbulence
using GBGPeriodicFields: point_coordinates
using GBGPeriodicFields: point_values
using Random
using Test


function fresh_sim(seed)
  return Simulation(grid_points_per_axis = 16, viscosity = 0.05, number_of_particles = 8,
                    rng = MersenneTwister(seed))
end


@testset "the mid-iteration velocity-at-particles read consumes the correct v₁" begin
  dt = 0.002

  # ————— (1) the run layer's guard on a genuinely stale sample —————
  guarded = fresh_sim(1)
  advance!(guarded; dt = dt)
  fields_modified!(guarded.cache)               # an out-of-band state change: the sample is now stale
  @test_throws ErrorException velocity_at_particles(guarded.cache)
  @test_throws ErrorException advance!(guarded; dt = dt)

  # ————— (2) the hand-composed iteration —————
  reference = fresh_sim(1)
  advance!(reference; dt = dt)                  # a genuine sample is deposited
  advance!(reference; dt = dt)                  # the run layer takes the next whole iteration

  manual = fresh_sim(1)
  advance!(manual; dt = dt)                     # same genuine sample

  # The claim's own sequence: step + deposit, then read the slot directly through `advect!`.
  step!(manual.field_integration_scheme, manual.state, manual.generator, manual.domain, manual.buffers, manual.cache, dt)
  deposit!(manual.cache, manual.state, manual.domain, manual.buffers)

  # The cache reports the sample stale here — this is the window `advance!` also advects in.
  @test_throws ErrorException velocity_at_particles(manual.cache)

  advect!(manual.particle_integration_scheme, manual.tracers, velocity_physical(manual.cache), manual.domain,
          manual.particle_buffers, dt)

  # The decisive assertion: the "stale" value consumed was the correct u(tₙ, X(tₙ)), so the
  # trajectories land exactly where the guarded run layer puts them.
  @test point_coordinates(manual.tracers.positions) == point_coordinates(reference.tracers.positions)
end
