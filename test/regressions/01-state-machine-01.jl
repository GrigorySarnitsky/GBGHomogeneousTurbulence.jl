# Witness: the velocity-at-particles cached read must be checked against BOTH epochs.
#
# `velocity_at_particles(cache)`'s own docstring and `check_deposits` agree that the sample is current
# only when `velocity_at_particles_fields_epoch == fields_epoch` AND `velocity_at_particles_particles_epoch == particles_epoch`
# (it is a function of the state and of the positions together). After a tracer push that has not yet
# been closed with the particle `deposit!`, the sample is stale: it holds u(tₙ, X_old), not
# u(tₙ, X_new). The read must throw, and `advance!` — whose opening guard is exactly this read — must
# refuse to step on it.

using Test, Random
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: advance_particles_epoch!, velocity_at_particles
using GBGHomogeneousTurbulence.SimulationRun: Simulation, advance!

function fresh_run()
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                   particles = ParticleTracking(number_of_particles = 8), rng = MersenneTwister(1))
  advance!(sim)
  return sim
end

@testset "the velocity-at-particles read is stale after an unclosed push" begin

  @testset "the accessor throws once the positions have moved past the sample" begin
    sim = fresh_run()
    v_before = copy(Array(velocity_at_particles(sim.cache)))

    # The push's epoch advance, NOT yet closed with the particle `deposit!`.
    advance_particles_epoch!(sim.cache)

    # The sample now belongs to the positions left behind: reading it must throw.
    @test_throws ErrorException velocity_at_particles(sim.cache)

    # And it must certainly not silently serve the pre-push values.
    ok = try
      v_after = copy(Array(velocity_at_particles(sim.cache)))
      !(v_after == v_before)      # served something — it had better not be the stale sample
    catch
      true                        # threw, as it should
    end
    @test ok
  end

  @testset "advance! refuses to step on a sample stale in the particles epoch" begin
    sim = fresh_run()
    advance_particles_epoch!(sim.cache)

    # advance!'s opening guard exists to refuse a step whose trajectory v₁ is stale.
    @test_throws ErrorException advance!(sim)
  end

end
