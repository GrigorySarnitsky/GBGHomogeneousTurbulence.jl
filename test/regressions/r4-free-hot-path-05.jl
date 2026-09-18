# Witness r4-free-hot-path-05 — `advance!`'s blow-up guard covers the velocity only.
#
# The guard at the tail of `advance!` states its intent as "the iteration refuses to report success
# on a state it has just made non-finite". The state is the pair (û, φ̂), but the guarded quantity
# is `max_speed(sim.cache)`, which reduces the velocity alone, and `check_deposits` compares epochs
# only, never values. A passive scalar cannot feed back into the velocity, so a non-finite φ̂ never
# reaches the guard: the iteration closes normally, deposits a non-finite `scalar_physical`, and
# every scalar statistic a caller accumulates from then on is silently NaN.
using Test, Random
using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data

@testset "an iteration does not report success on a state whose scalar it has made non-finite" begin
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, scalar = true,
                   rng = MersenneTwister(2))

  # The sanctioned out-of-band route: write the state's storage directly, announce it, re-deposit.
  field_data(sim.state.scalar_spectral)[3, 3, 3] = NaN + 0im
  fields_modified!(sim.cache)
  deposit!(sim)

  # The velocity is untouched — this is a scalar-only blow-up, invisible to `max_speed`.
  @test all(isfinite, field_data(velocity_physical(sim.cache)))
  @test !all(isfinite, field_data(scalar_physical(sim.cache)))

  # The advance must refuse to report success on it.
  @test_throws ErrorException advance!(sim)
end
