# Witness: an announced tracer reposition must restart the Adams–Bashforth multistep history.
#
# `AdamsBashforth`'s own docstring promises: "the first `order - 1` steps are taken with
# `Heun` and the scheme then switches over; the same restart happens if the tracers are
# reseeded."  The cache's sample history holds Lagrangian velocity samples measured along the OLD
# trajectory; after a reposition announced through `particles_modified!` those samples belong to a
# different trajectory and must not enter the next position update.

using GBGIsotropicTurbulence
using GBGPeriodicFields: PointSet, point_values
using Random
using Test


@testset "an announced tracer reposition restarts the AdamsBashforth history" begin
  K = 4
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, number_of_particles = 8,
                   particle_integration_scheme = AdamsBashforth(order = K), rng = MersenneTwister(7))
  for _ in 1:5
    advance!(sim)
  end
  @test sim.cache.history_filled == K - 1        # precondition: steady multistep operation

  # The sanctioned reposition sequence, exactly as `particles_modified!`'s docstring describes.
  L = sim.domain.grid.domain_size[1]
  copyto!(particle_positions(sim.tracers), mod.(particle_positions(sim.tracers) .+ L / 2, L))
  particles_modified!(sim.cache)
  record_velocity_at_particles!(sim.cache, sim.tracers, velocity_physical(sim.cache))
  deposit_sample!(sim.cache)

  # (1) The promised restart: the pre-reposition history is no longer valid.
  @test sim.cache.history_filled < K - 1

  # (2) The consequence that restart exists to guarantee: the next trajectory step must be the one a
  #     freshly started integrator would take at the same positions in the same velocity field, i.e.
  #     it must not depend on samples taken before the reposition.
  u  = velocity_physical(sim.cache)
  dt = 0.001
  fresh = Tracers(sim.domain; positions = PointSet(copy(particle_positions(sim.tracers))),
                  interpolation_scheme = sim.tracers.interpolation_scheme)

  # The sample history now lives in the ObservablesCache that owns the observable it extends, so an
  # independent integrator needs its own cache to hold its own history. The assertion is unchanged.
  fresh_cache = ObservablesCache(sim.domain; number_of_particles = number_of_particles(fresh),
                                 history_depth = history_depth(sim.particle_integration_scheme))
  fresh_buffers = allocate_buffers(sim.particle_integration_scheme, fresh, fresh_cache)
  record_velocity_at_particles!(fresh_cache, fresh, u)

  advect!(sim.particle_integration_scheme, sim.tracers, u, sim.domain, sim.particle_buffers, dt)
  advect!(sim.particle_integration_scheme, fresh, u, sim.domain, fresh_buffers, dt)

  @test particle_positions(sim.tracers) ≈ particle_positions(fresh)
end
