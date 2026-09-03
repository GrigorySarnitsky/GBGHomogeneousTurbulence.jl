# Witness: `particles_modified!` must accept a `Simulation`.
#
# `particles_modified!`'s own docstring (src/Cache.jl:359-392) advertises TWO signatures —
# `particles_modified!(cache)` and `particles_modified!(sim)` — and instructs the user in bold to
# "**Prefer the `sim` form**", with a `!!! warning` stating that the bare-cache form "stamps the
# epoch and nothing else" and cannot restart a multistep trajectory history.  A user who follows
# that instruction after reseeding tracers must not get a `MethodError`.

using GBGIsotropicTurbulence
using GBGPeriodicFields: point_positions
using GBGIsotropicTurbulence.Cache: particles_modified!
using Random
using Test


@testset "particles_modified!(sim) — the docstring's preferred form — exists and restarts the history" begin
  # (1) The cheap, non-simulating form of the claim: the advertised two-signature generic has two
  #     methods, exactly as the sibling two-form verb `deposit!` does.
  @test length(methods(particles_modified!)) == 2

  # (2) The behavioural form: the prescribed call after a reseed runs, and restarts the multistep
  #     trajectory history the warning says the bare-cache form cannot reach.
  K = 4
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, number_of_particles = 8,
                   particle_integration_scheme = AdamsBashforth(order = K), rng = MersenneTwister(1))
  for _ in 1:5
    advance!(sim)
  end
  @test sim.cache.history_filled == K - 1        # precondition: steady multistep operation

  L = sim.domain.grid.domain_size[1]
  copyto!(point_positions(sim.tracers.positions), mod.(point_positions(sim.tracers.positions) .+ L / 2, L))

  @test (particles_modified!(sim); true)         # the docstring's prescribed call must not throw
  @test sim.cache.history_filled == 0            # and must restart the abandoned-path history
end
