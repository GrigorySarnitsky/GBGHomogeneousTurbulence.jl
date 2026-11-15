# Witness — lane gpu-and-hot-loop, candidate 03.
#
# Claim: the per-step tracer advance under a multistep scheme allocates on the host, because the
# weight solve built fresh `Vector{Float64}`s on every call, with no scratch kept for them.
#
# Scope note, measured here and NOT part of the claim: the tracer path is not allocation-free as a
# whole — `GBGPeriodicFields`' `interpolate!` allocates on the host per call, so a corrected step
# and the particle `deposit!` each cost that much whatever the scheme. That is a backend cost,
# outside this package. A full `AB` step interpolates nothing, so its correct allocation count is
# exactly zero: the weights are computed as a tuple, on the stack.

using Test, Random, GBGHomogeneousTurbulence

const HT = GBGHomogeneousTurbulence

include(joinpath(@__DIR__, "..", "cache_counters.jl"))

# @allocated inside a function body, on concrete arguments, so the measurement is of the callee
# alone and not of global-scope boxing.
function allocations_of(g, args...)
  g(args...)                                                 # compile + warm
  g(args...)
  return @allocated g(args...)
end

# One particle step of a run, called out of an iteration: the cache's counters are put where the
# step needs them (which touches no array).
particle_step!(sim) = advect!(sim.particle_integration_scheme, sim.tracers, sim.domain,
                              ready_for_particle_step!(sim.cache), 1.0e-3)
particle_deposit!(sim) = HT.Propagator.deposit!(ready_for_particle_deposit!(sim.cache), sim.tracers, later())

@testset "the multistep tracer advance allocates nothing once its trail is full" begin

  # Reference measurement only: the one-step scheme's cost is PF's `interpolate!`, not HT's.
  heun = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                    particles = ParticleTracking(number_of_particles = 32, particle_integration_scheme = Heun()),
                    rng = MersenneTwister(11))
  for _ in 1:3; advance!(heun); end
  heun_bytes = allocations_of(particle_step!, heun)
  interp_bytes = allocations_of(particle_deposit!, heun)
  @info "reference: one-step advance and its interpolation" heun_bytes interp_bytes

  # ---- the claim: AB(4), trail full (four samples), no interpolation -----------------------------
  ab = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                  particles = ParticleTracking(number_of_particles = 32,
                                               particle_integration_scheme = AB(4)),
                  rng = MersenneTwister(11))
  for _ in 1:5; advance!(ab); end
  @test length(velocity_at_particles_trail(ab.cache)) == 4   # the full step is the live one

  ab_bytes = allocations_of(particle_step!, ab)
  @info "per-advance host allocations, full multistep step" ab_bytes
  @test ab_bytes == 0

  # ---- and the weight solve itself, isolated: the whole of the above ------------------------
  weights(nodes, h) = HT.ParticlePropagator._adams_weights(nodes, h)
  weight_bytes = allocations_of(weights, (0.0, -1.0e-3, -2.0e-3, -3.0e-3), 1.0e-3)
  @info "weight-solve host allocations" weight_bytes
  @test weight_bytes == 0
  @test ab_bytes == weight_bytes                             # the advance's whole cost is the solve
  # The corrector's weights, on one more node, cost no more.
  @test allocations_of(weights, (1.0e-3, 0.0, -1.0e-3, -2.0e-3, -3.0e-3), 1.0e-3) == 0
end
