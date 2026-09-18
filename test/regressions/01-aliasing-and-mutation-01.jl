# Witness: AdamsBashforth must restart its history when the tracers are reseeded.
#
# `AdamsBashforth`'s own docstring promises: "the first `order - 1` steps are taken with
# `Heun` and the scheme then switches over; the same restart happens if the tracers are
# reseeded."  The invariant that promise encodes, stated without prescribing the mechanism:
#
#     after a reseed, the next tracer update may depend only on the POST-reseed trajectory —
#     the positions, the field, and the step — never on samples measured along the abandoned
#     pre-reseed trajectory.
#
# Two simulations are built whose velocity fields stay bit-identical (the tracers are passive, so
# they cannot feed back) but whose tracer histories differ.  Both are then reseeded onto the SAME
# positions through the sanctioned announcement (`particles_modified!` → the particle `deposit!`,
# the recipe `particles_modified!`'s docstring prescribes) and each takes one
# further step of the same size.  Their post-reseed state is identical, so the resulting positions
# must be identical.  `Heun`, which keeps no history, is the control.

using Test, Random, GBGHomogeneousTurbulence
using GBGPeriodicFields: point_positions
using GBGPeriodicFields: field_data

const N = 16
const M = 8
const DT = 0.01

make_sim(scheme) = Simulation(grid_points_per_axis = N, viscosity = 0.05, number_of_particles = M,
                              particle_integration_scheme = scheme, rng = MersenneTwister(1))

# Announce + refill the trajectory-bound slot after a hand-written change of the tracer positions.
function reseed!(sim, positions)
  copyto!(point_positions(sim.tracers.positions), positions)
  particles_modified!(sim.cache)
  deposit!(sim.cache, sim.tracers, velocity_physical(sim.cache))
  return sim
end

# Two runs, identical fields, deliberately different tracer histories; reseed both onto `fresh`,
# then step both once more.  Returns the two position arrays, which must agree.
function positions_after_reseed(scheme)
  a, b = make_sim(scheme), make_sim(scheme)
  L = a.domain.grid.domain_size[1]
  rng = MersenneTwister(7)
  reseed!(a, rand(rng, M, 3) .* L)
  reseed!(b, rand(rng, M, 3) .* L)

  advance!(a; dt = DT)
  advance!(b; dt = DT)
  @test Array(field_data(a.state.velocity_spectral)) ==
        Array(field_data(b.state.velocity_spectral))   # the tracers are passive

  fresh = rand(MersenneTwister(11), M, 3) .* L
  reseed!(a, fresh)
  reseed!(b, fresh)
  @test Array(point_positions(a.tracers.positions)) == Array(point_positions(b.tracers.positions))
  @test Array(velocity_at_particles(a.cache)) == Array(velocity_at_particles(b.cache))

  advance!(a; dt = DT)
  advance!(b; dt = DT)
  return Array(point_positions(a.tracers.positions)), Array(point_positions(b.tracers.positions))
end

@testset "control — Heun, which keeps no history, is unaffected by a reseed" begin
  xa, xb = positions_after_reseed(Heun())
  @test xa ≈ xb atol = 1e-12
end

@testset "a tracer reseed restarts AdamsBashforth, so the next step ignores pre-reseed samples" begin
  xa, xb = positions_after_reseed(AdamsBashforth(order = 2))
  @test xa ≈ xb atol = 1e-12
end
