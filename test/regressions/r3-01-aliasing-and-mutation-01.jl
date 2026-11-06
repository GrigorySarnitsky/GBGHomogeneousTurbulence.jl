# Witness: the checked read `velocity_at_particles(cache)` must honour BOTH epoch stamps.
#
# Its docstring: "the sample depends on the state **and** the positions, so it is current only when
# both counters match its own". A tracer push advances ONLY the particles epoch; the deposited sample
# is then stale until the closing particle `deposit!`, and the read must throw.

using Test, Random
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: advance_particles_epoch!

@testset "velocity_at_particles throws when only the particles epoch has advanced" begin
  sim = Simulation(; grid_points_per_axis = 16, particles = ParticleTracking(number_of_particles = 4),
                   kinetic_energy = 1.5, rng = MersenneTwister(20260821))
  advance!(sim)                                   # a full iteration: every slot deposited
  v_before = copy(Array(velocity_at_particles(sim.cache)))   # readable here, by construction

  # The window the run itself passes through mid-iteration: the push's epoch advance that precedes
  # the closing particle `deposit!`.
  advance_particles_epoch!(sim.cache)
  @test_throws ErrorException velocity_at_particles(sim.cache)

  # …and it must not be serving the pre-push values
  @test !(try
            Array(velocity_at_particles(sim.cache)) == v_before
          catch
            false
          end)
end
