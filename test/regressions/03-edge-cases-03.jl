# Witness: AdamsBashforth must restart its multistep history when the tracers are reseeded.
#
# `AdamsBashforth`'s docstring (src/Particles.jl:266-268) states:
#   "A multistep method has no history at t₀, so the first `order - 1` steps are taken with
#    `Heun` and the scheme then switches over; the same restart happens if the tracers are
#    reseeded."
#
# A reseed is announced with `particles_modified!` (the documented protocol: write the positions,
# announce, then the particle `deposit!`). After that protocol the AB scheme's
# stored past samples are Lagrangian velocities of the abandoned trajectories, so the scheme must
# restart: `filled == 0`, and the next advance must be the startup `Heun` step.

using Test, Random
using GBGPeriodicFields: point_coordinates
using GBGIsotropicTurbulence

const SEED = 11
const NPART = 24

function build(scheme)
  Simulation(grid_points_per_axis = 16, viscosity = 0.05, number_of_particles = NPART,
             particle_integration_scheme = scheme, rng = MersenneTwister(SEED))
end

@testset "AdamsBashforth restarts its history when the tracers are reseeded" begin
  ab = build(AdamsBashforth(order = 4))
  heun = build(Heun())

  # Fill AB4's history (order - 1 = 3 past samples).
  for _ in 1:4
    advance!(ab); advance!(heun)
  end
  @test ab.cache.history_filled == 3          # precondition: history is full

  # The two runs carry identical fields (same seed; tracers do not feed back on the flow), so any
  # difference in the tracer positions is the particle integration scheme alone. Before the reseed the two
  # legitimately differ — AB4 has switched over and is more accurate than Heun.

  # Reseed both tracer sets to the same brand-new positions, by the documented protocol.
  L = 2π
  X_new = L .* rand(MersenneTwister(99), Float64, NPART, 3)
  for sim in (ab, heun)
    copyto!(point_coordinates(sim.tracers.positions), X_new)
    particles_modified!(sim.cache)
    deposit!(sim.cache, sim.tracers, velocity_physical(sim.cache))
  end

  # The documented restart: the abandoned trajectories' samples are discarded.
  @test ab.cache.history_filled == 0

  # ... and therefore the first post-reseed advance is a startup Heun step, so the two runs
  # must still agree on the tracer positions.
  advance!(ab); advance!(heun)
  deviation = maximum(abs, point_coordinates(ab.tracers.positions) .- point_coordinates(heun.tracers.positions))
  println("max |X_AB4 - X_Heun| after one post-reseed step: ", deviation, "  (box side ", L, ")")
  @test point_coordinates(ab.tracers.positions) ≈ point_coordinates(heun.tracers.positions) atol = 1e-10
end
