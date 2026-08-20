using Test, GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Cache: particles_modified!

@testset "particles_modified!(sim) — the form the docstring says to prefer — is callable" begin
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                   number_of_particles = 8, trajectory_scheme = AdamsBashforth(order = 4))
  advance!(sim)

  # (1) The documented `sim` form must exist.
  @test hasmethod(particles_modified!, Tuple{typeof(sim)})

  # (2) And it must actually run, announcing the reposition and restarting the history.
  @test try
    particles_modified!(sim)
    true
  catch err
    @info "particles_modified!(sim) threw" err
    false
  end

  # (3) The `!!! warning` claims a bare cache "stamps the epoch and nothing else".
  #     The correct state of affairs is what the code does: it also clears the multistep history,
  #     which is byte-for-byte what restart!(::AdamsBashforth, buffers) does.
  sim2 = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                    number_of_particles = 8, trajectory_scheme = AdamsBashforth(order = 4))
  advance!(sim2)
  @test sim2.cache.history_filled > 0            # the history did fill
  particles_modified!(sim2.cache)
  @test sim2.cache.history_filled == 0           # a bare cache DOES restart the history
  @test sim2.particle_buffers.cache === sim2.cache  # ... the very object restart! would clear
end
