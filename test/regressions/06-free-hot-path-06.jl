# Witness: `advance!` must reject a non-positive `dt` regardless of the trajectory scheme.
#
# Today the only guard on a degenerate step lives in `advect!(::AdamsBashforth, …)`
# (src/Particles.jl:459), so whether the call is refused depends on which *trajectory* scheme a run
# happens to carry — not on the field solver, where Δt is actually consumed. With dt < 0 the
# integrating factor becomes exp(+ν|κ|²|Δt|) and the step is an unconditionally unstable backward
# heat solve; the clock also runs backwards.

using Test, Random, GBGIsotropicTurbulence

@testset "advance! rejects a non-positive dt for every trajectory scheme, not only AdamsBashforth" begin

  # Control: the multistep scheme already refuses it, at the wrong layer.
  a = Simulation(grid_points_per_axis = 16, viscosity = 0.05, number_of_particles = 4,
                 trajectory_scheme = AdamsBashforth(order = 2), rng = MersenneTwister(1))
  @test_throws ArgumentError advance!(a; dt = -2e-3)

  # The claim: the same call, same physics, default one-step trajectory scheme.
  b = Simulation(grid_points_per_axis = 16, viscosity = 0.05, number_of_particles = 4,
                 trajectory_scheme = EndpointHeun(), rng = MersenneTwister(1))
  @test_throws ArgumentError advance!(b; dt = -2e-3)
  @test current_step(b) == 0            # a refused call must not have advanced the run
  @test current_time(b) ≥ 0             # the clock must never run backwards

  # A zero step must be refused too: it advances `current_step` while leaving `current_time` fixed,
  # so a `run!` callback written against `current_time` never terminates.
  c = Simulation(grid_points_per_axis = 16, viscosity = 0.05, rng = MersenneTwister(2))
  @test_throws ArgumentError advance!(c; dt = 0.0)

  # The physical consequence, with no particles at all: an unforced run cannot gain kinetic energy.
  s = Simulation(grid_points_per_axis = 32, viscosity = 0.05,
                 velocity_forcing = NoForcing(), rng = MersenneTwister(3))
  # CORRECTED 2026-08-21. As written this stepped the run BACKWARDS forty times and asserted that an
  # unforced flow had not gained energy — a demonstration of the harm, which is the wrong shape for a
  # witness: it exhibits the defect rather than asserting the right behaviour, so once `advance!`
  # validates `dt` the loop simply throws and the file becomes BROKEN rather than passing. The harm is
  # now unreachable by construction, and what remains testable is the rejection that makes it so.
  k0 = kinetic_energy(s.state.velocity_spectral)
  @test_throws ArgumentError advance!(s; dt = -2e-3)
  @test kinetic_energy(s.state.velocity_spectral) == k0    # and the refused step changed nothing
end
