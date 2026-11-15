# Witness: the read of the velocity at the particles must be refused once the positions have moved.
#
# After a tracer push that has not yet been closed with the particle `deposit!`, the newest sample is
# stale: it holds u(tₙ, X_old), not u(tₙ, X_new). The read must throw, and the next iteration — whose
# particle step starts from that sample — must refuse to run.

using Test, Random
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: advance_particles_epoch!, velocity_at_particles_trail
using GBGHomogeneousTurbulence.SimulationRun: Simulation, advance!
using GBGPeriodicFields: point_values

function fresh_run()
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                   particles = ParticleTracking(number_of_particles = 8), rng = MersenneTwister(1))
  advance!(sim)
  return sim
end

@testset "the velocity-at-particles read is stale after an unclosed push" begin

  @testset "the accessor throws once the positions have moved past the sample" begin
    sim = fresh_run()
    v_before = copy(Array(point_values(velocity_at_particles_trail(sim.cache)[0].value)))

    # The push's epoch advance, NOT yet closed with the particle `deposit!`.
    advance_particles_epoch!(sim.cache)

    # The sample now belongs to the positions left behind: reading it must throw.
    @test_throws ErrorException velocity_at_particles_trail(sim.cache)

    # And it must certainly not silently serve the pre-push values.
    ok = try
      v_after = copy(Array(point_values(velocity_at_particles_trail(sim.cache)[0].value)))
      !(v_after == v_before)      # served something — it had better not be the stale sample
    catch
      true                        # threw, as it should
    end
    @test ok
  end

  @testset "advance! refuses to step on a sample stale in the particles epoch" begin
    sim = fresh_run()
    advance_particles_epoch!(sim.cache)

    # The particle step refuses a velocity sample taken at positions the tracers have left.
    @test_throws ErrorException advance!(sim)
  end

end
