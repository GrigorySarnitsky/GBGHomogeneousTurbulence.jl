# Witness r5-edge-cases-03 — a negative `number_of_particles` must be rejected at construction,
# the way every sibling non-negative keyword of this constructor already is (`kinetic_energy`,
# `scalar_variance`, `κ_max_η`), instead of being silently routed to the tracer-free branch.
using Test, GBGHomogeneousTurbulence

@testset "Simulation rejects a negative `number_of_particles` instead of silently dropping tracers" begin
  # The legitimate tracer-free request keeps working: zero means "no tracers".
  sim0 = Simulation(grid_points_per_axis = 8, viscosity = 0.05)
  @test sim0.tracers === nothing

  # A negative count is not a count. It must raise, naming the keyword.
  @test_throws ArgumentError Simulation(grid_points_per_axis = 8, viscosity = 0.05,
                                        particles = ParticleTracking(number_of_particles = -5))

  err = try
    Simulation(grid_points_per_axis = 8, viscosity = 0.05, particles = ParticleTracking(number_of_particles = -5))
    nothing
  catch e
    e
  end
  @test err isa ArgumentError && occursin("number_of_particles", sprint(showerror, err))
end
