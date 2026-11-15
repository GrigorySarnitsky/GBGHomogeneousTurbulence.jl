# Witness: the checked read `velocity_at_particles_trail(cache)` must honour the particles epoch.
#
# Its docstring: the samples "are current exactly while the positions have not moved since the newest
# was taken". A tracer push advances ONLY the particles epoch; the deposited sample
# is then stale until the closing particle `deposit!`, and the read must throw.

using Test, Random
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: advance_particles_epoch!
using GBGPeriodicFields: point_values

@testset "velocity_at_particles_trail throws when only the particles epoch has advanced" begin
  sim = Simulation(; grid_points_per_axis = 16, particles = ParticleTracking(number_of_particles = 4),
                   kinetic_energy = 1.5, rng = MersenneTwister(20260821))
  advance!(sim)                                   # a full iteration: every slot deposited
  newest(cache) = Array(point_values(velocity_at_particles_trail(cache)[0].value))
  v_before = copy(newest(sim.cache))              # readable here, by construction

  # The window the run itself passes through mid-iteration: the push's epoch advance that precedes
  # the closing particle `deposit!`.
  advance_particles_epoch!(sim.cache)
  @test_throws ErrorException velocity_at_particles_trail(sim.cache)

  # …and it must not be serving the pre-push values
  @test !(try
            newest(sim.cache) == v_before
          catch
            false
          end)
end
