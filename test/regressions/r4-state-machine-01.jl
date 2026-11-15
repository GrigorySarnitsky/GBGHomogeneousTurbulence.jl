# Witness for the claim: "`advect!` reads the velocity sample by direct array access, bypassing the
# cache's checked accessor, so it silently consumes a sample the cache itself considers stale."
#
# When the claim was made, the sample was dated against the fields epoch as well as the particles
# epoch, so the read `advect!` makes mid-iteration — after the field step — could not go through the
# checked accessor, and `advance!` verified the sample at the iteration's start instead. The claim
# was answered by showing that the value consumed was the correct one.
#
# Since 2026-11-15 the question does not arise: a sample is u(t, X(t)) and belongs to the particles'
# time, so it is CURRENT in that window — the positions have not moved — and `advect!` reads it
# through a checked read of its own, which also requires the fields exactly one step ahead.
#
# So the assertions are:
#   (1) the run layer refuses to advance on a cache whose fields were stepped and not deposited;
#   (2) in the hand-composed sequence step!/deposit!/advect!/deposit!, the trail is readable between
#       the field deposit and the push, with the samples it had before the step, and the sequence
#       advances the trajectories to exactly the positions `advance!` produces.
# If (2) ever fails, the mid-iteration read consumed a wrong value.

using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: advance_fields_epoch!
using GBGPeriodicFields: point_positions
using GBGPeriodicFields: point_values
using Random
using Test


function fresh_sim(seed)
  return Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                    particles = ParticleTracking(number_of_particles = 8),
                    rng = MersenneTwister(seed))
end


@testset "the mid-iteration velocity-at-particles read consumes the correct sample" begin
  dt = 0.002

  # ————— (1) the run layer's refusal of an iteration left open —————
  guarded = fresh_sim(1)
  advance!(guarded; dt = dt)
  advance_fields_epoch!(guarded.cache)          # a step's epoch advance with no closing deposit
  @test_throws ErrorException velocity_physical(guarded.cache)
  @test_throws ErrorException advance!(guarded; dt = dt)

  # ————— (2) the hand-composed iteration —————
  reference = fresh_sim(1)
  advance!(reference; dt = dt)                  # a genuine sample is deposited
  advance!(reference; dt = dt)                  # the run layer takes the next whole iteration

  manual = fresh_sim(1)
  advance!(manual; dt = dt)                     # same genuine sample
  sample_before = copy(point_values(velocity_at_particles_trail(manual.cache)[0].value))

  step!(manual.field_integration_scheme, manual.state, manual.generator, manual.domain, manual.buffers, manual.cache, dt)
  deposit!(manual.cache, manual.state, manual.domain, manual.buffers)

  # The window `advance!` also advects in: the fields are one step ahead, the positions unmoved,
  # and the trail still serves u(tₙ, X(tₙ)).
  @test point_values(velocity_at_particles_trail(manual.cache)[0].value) == sample_before

  advect!(manual.particle_integration_scheme, manual.tracers, manual.domain, manual.cache, dt)
  @test_throws ErrorException velocity_at_particles_trail(manual.cache)     # now the positions have moved
  deposit!(manual.cache, manual.tracers, current_time(manual) + dt)

  # The decisive assertion: the value consumed was the correct u(tₙ, X(tₙ)), so the trajectories
  # land exactly where the run layer puts them — and so does the new sample.
  @test point_positions(manual.tracers.positions) == point_positions(reference.tracers.positions)
  @test point_values(velocity_at_particles_trail(manual.cache)[0].value) ==
        point_values(velocity_at_particles_trail(reference.cache)[0].value)
end
