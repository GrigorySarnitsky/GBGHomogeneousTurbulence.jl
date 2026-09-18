# Witness: a negative `number_of_particles` must be REJECTED by the `Simulation`
# constructor, not silently reinterpreted as "this run carries no tracers".
#
# Every other numeric precondition of this constructor is guarded at the front door with a named
# `ArgumentError` (`cfl > 0`, `kinetic_energy > 0`, `scalar_variance >= 0`, the `κ_max_η` positivity
# check, the `viscosity`/`κ_max_η` double-set check), and `Tracers` itself refuses an ambiguous
# keyword pair. The particle count is the one input the constructor guesses at rather than reports:
#
#   src/SimulationRun.jl:333
#     tracers = number_of_particles > 0 ?
#       Tracers(domain; number_of_particles, interpolation_scheme = interpolation_scheme, rng) : nothing
#
# A sign typo therefore yields a run that constructs and advances normally, and only surfaces much
# later as `ArgumentError("this run advects no tracers, …")` from `velocity_at_particles(sim.cache)`
# — a message naming a configuration the user never asked for, and not naming the keyword at fault.

using Test, Random, GBGHomogeneousTurbulence
using GBGPeriodicFields: npoints

@testset "a negative `number_of_particles` is rejected at construction, not read as zero" begin
  build(n) = Simulation(; grid_points_per_axis = 8, viscosity = 0.1,
                        number_of_particles = n, rng = MersenneTwister(1))

  # The correct behaviour: a negative count is a user error and is reported as one.
  @test_throws ArgumentError build(-5)

  # The neighbouring cases must keep working exactly as before.
  @test build(0).tracers === nothing                        # zero honestly means "no tracers"
  @test npoints(build(4).tracers.positions) == 4            # a positive count seeds that many
end
