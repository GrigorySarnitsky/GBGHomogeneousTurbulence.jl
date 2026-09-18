# The fused observable pair (PF decision 72 wired): `kinetic_energy_and_dissipation` must measure
# the SAME quantities as the two singles, and the comparison must be tight enough to pin the wiring
# itself — swapping the two weights in the tuple (unit against |κ|²) would silently exchange k's
# and ε's operands, which no green run would notice. The ε leg is bitwise (`===`): both routes are
# `weighted_inner`, and the backend's fusion shares the traversal, never the arithmetic. The k leg
# is NOT bitwise by design: `kinetic_energy` reduces through `inner` on the backend's threaded
# fixed tree, while the fused pass is serial — the sums associate differently at roundoff. So k is
# pinned bitwise against its own weighted route, and against `kinetic_energy` only to a few ulp
# (still far tighter than any operand swap could survive).
using Test, GBGHomogeneousTurbulence
using GBGPeriodicFields: weighted_inner
using Random


@testset "kinetic_energy_and_dissipation matches the two singles, ε bitwise" begin
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, rng = MersenneTwister(7))
  û = sim.state.velocity_spectral
  ν = sim.generator.conditions.viscosity
  pair = kinetic_energy_and_dissipation(û, sim.domain, ν)
  @test pair.dissipation === dissipation(û, sim.domain, ν)
  @test pair.kinetic_energy === weighted_inner(û, sim.domain.unit_kernel) / 2
  @test isapprox(pair.kinetic_energy, kinetic_energy(û); rtol = 16 * eps(Float64))
end
