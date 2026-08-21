# Witness: the particle-velocities cached read must be checked against BOTH epochs.
#
# `particle_velocities(cache)`'s own docstring and `check_deposits` agree that the sample is current
# only when `sample_fields_epoch == fields_epoch` AND `sample_particles_epoch == particles_epoch`
# (it is a function of the state and of the positions together). After an announced out-of-band
# reposition — `particles_modified!` — that has not yet been completed with
# `record_particle_velocities!` + `deposit_sample!`, the sample is stale: it holds
# u(tₙ, X_old), not u(tₙ, X_new). The read must throw, and `advance!` — whose opening guard is
# exactly this read — must refuse to step on it.

using Test, Random
using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Cache: particles_modified!, particle_velocities
using GBGIsotropicTurbulence.SimulationRun: Simulation, advance!

function fresh_run()
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                   number_of_particles = 8, rng = MersenneTwister(1))
  advance!(sim)
  return sim
end

@testset "the particle-velocities read is stale after an announced reposition" begin

  @testset "the accessor throws once the positions have moved past the sample" begin
    sim = fresh_run()
    v_before = copy(Array(particle_velocities(sim.cache)))

    # An out-of-band reposition, announced exactly as the docstring prescribes, and NOT yet
    # completed with `record_particle_velocities!` / `deposit_sample!`.
    L = sim.domain.grid.domain_size[1]
    sim.tracers.positions .= mod.(sim.tracers.positions .+ 0.3, L)
    particles_modified!(sim.cache)

    # The sample now belongs to the abandoned positions: reading it must throw.
    @test_throws ErrorException particle_velocities(sim.cache)

    # And it must certainly not silently serve the pre-reposition values.
    ok = try
      v_after = copy(Array(particle_velocities(sim.cache)))
      !(v_after == v_before)      # served something — it had better not be the stale sample
    catch
      true                        # threw, as it should
    end
    @test ok
  end

  @testset "advance! refuses to step on a sample stale in the particles epoch" begin
    sim = fresh_run()
    L = sim.domain.grid.domain_size[1]
    sim.tracers.positions .= mod.(sim.tracers.positions .+ 0.3, L)
    particles_modified!(sim)      # the run-level announcement, per its own docstring

    # advance!'s opening guard exists to refuse a step whose trajectory v₁ is stale.
    @test_throws ErrorException advance!(sim)
  end

end
