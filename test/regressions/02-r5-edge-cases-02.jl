# Witness: a `particle_integration_scheme` handed to the `Simulation` front door must never be silently
# discarded. The sibling case is already guarded — `ResolvedGenerator` refuses a non-`NoForcing`
# `scalar_forcing` paired with `scalar = false` (src/Generator.jl:273-277) precisely because a
# configured-but-never-invoked strategy is a quiet-wrong-configuration bug. The
# `particle_integration_scheme` / `number_of_particles` pairing has no analogous guard.
#
# The test accepts EITHER honest outcome of a fix: refuse the pairing with an `ArgumentError`
# (the sibling-guard shape), or keep the scheme the caller asked for. It fails only on the
# third, silent outcome — scheme dropped, nothing said.

using Test, GBGHomogeneousTurbulence
using Random

@testset "a particle_integration_scheme requested through Simulation is never silently discarded" begin
  # Control 1: with particles asked for, the requested scheme is honoured.
  with_particles = Simulation(grid_points_per_axis = 16,
                              particles = ParticleTracking(number_of_particles = 4,
                                                           particle_integration_scheme = AdamsBashforth(order = 4)),
                              rng = MersenneTwister(1))
  @test with_particles.particle_integration_scheme isa AdamsBashforth

  # Control 2: the untouched default (no particle_integration_scheme, no particles) stays a legal,
  # silent, tracer-free run — a guard must not over-throw on it.
  plain = Simulation(grid_points_per_axis = 16, rng = MersenneTwister(1))
  @test plain.tracers === nothing

  # The claim: a particle scheme requested without particles. Since 2026-10-14 the scheme travels
  # inside `ParticleTracking`, which always carries a tracer set, so the request cannot be written
  # for a tracer-free run: `Simulation` has no such keyword.
  @test_throws MethodError Simulation(grid_points_per_axis = 16,
                                      particle_integration_scheme = AdamsBashforth(order = 4),
                                      rng = MersenneTwister(1))
end
