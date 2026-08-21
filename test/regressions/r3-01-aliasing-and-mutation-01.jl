# Witness: the checked read `particle_velocities(cache)` must honour BOTH epoch stamps.
#
# Its docstring: "the sample depends on the state **and** the positions, so it is current only when
# both counters match its own", and `particles_modified!`: "Advances the particles epoch […] so every
# trajectory-bound observable is stale and reads throw until the next deposit."
#
# Announcing an out-of-band reposition advances ONLY the particles epoch; the deposited sample is
# then stale and the read must throw. It does not, because the accessor compares only the fields
# epoch.

using Test, Random
using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Cache: advance_particles_epoch!

@testset "particle_velocities throws when only the particles epoch has advanced" begin
  rng = MersenneTwister(20260820)
  sim = Simulation(; grid_points_per_axis = 16, number_of_particles = 4,
                   kinetic_energy = 1.5, rng)
  advance!(sim)                                   # a full iteration: every slot deposited
  v_before = copy(Array(particle_velocities(sim.cache)))   # readable here, by construction

  # (a) the public announcement of an out-of-band reposition
  particles_modified!(sim.cache)
  @test_throws ErrorException particle_velocities(sim.cache)

  # …and it must not be serving the pre-announcement values
  @test !(try
            Array(particle_velocities(sim.cache)) == v_before
          catch
            false
          end)

  # (b) the same window the run itself passes through mid-iteration: the epoch bump that precedes
  #     `record_particle_velocities!` + `deposit_sample!`
  sim2 = Simulation(; grid_points_per_axis = 16, number_of_particles = 4,
                    kinetic_energy = 1.5, rng = MersenneTwister(20260821))
  advance!(sim2)
  advance_particles_epoch!(sim2.cache)
  @test_throws ErrorException particle_velocities(sim2.cache)
end
