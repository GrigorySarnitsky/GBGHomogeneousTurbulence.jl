# Witness — lane gpu-and-hot-loop, candidate 03.
#
# Claim: the per-step tracer advance under `AdamsBashforth` allocates on the host, because
# `_adams_bashforth_weights` builds two fresh `Vector{Float64}`s (`τ` at Particles.jl:343 and `b`
# at Particles.jl:347) on every call, while the buffers carried no scratch for them.
#
# Scope note, measured here and NOT part of the claim: the tracer path is not allocation-free as a
# whole — `GBGPeriodicFields`' `interpolate!` allocates 912 bytes per call, so `Heun`'s
# `advect!` and `record_velocity_at_particles!` each cost that much per step whatever the scheme.
# That is a backend cost, outside this package. The multistep branch of `advect!(::AdamsBashforth, …)`
# interpolates nothing, so its correct allocation count is exactly zero: the assertions below are
# achievable by giving the buffers the two weight registers (or by a stack-allocated solve).

using Test, Random, GBGIsotropicTurbulence

const IT = GBGIsotropicTurbulence

# @allocated inside a function body, on concrete arguments, so the measurement is of the callee
# alone and not of global-scope boxing.
function allocations_of(g, args...)
  g(args...)                                                 # compile + warm
  g(args...)
  return @allocated g(args...)
end

@testset "the multistep tracer advance allocates nothing once its history is full" begin

  # Reference measurement only: the one-step scheme's cost is PF's `interpolate!`, not IT's.
  heun = Simulation(grid_points_per_axis = 16, viscosity = 0.05, number_of_particles = 32,
                    particle_integration_scheme = Heun(), rng = MersenneTwister(11))
  for _ in 1:3; advance!(heun); end
  heun_bytes = allocations_of(advect!, heun.particle_integration_scheme, heun.tracers,
                              velocity_physical(heun.cache), heun.domain,
                              heun.particle_buffers, 1.0e-3)
  interp_bytes = allocations_of(IT.Particles.record_velocity_at_particles!, heun.cache, heun.tracers,
                                velocity_physical(heun.cache))
  @info "reference: one-step advance and its interpolation" heun_bytes interp_bytes

  # ---- the claim: AdamsBashforth(4), history full (filled == order - 1 == 3), no interpolation --
  ab = Simulation(grid_points_per_axis = 16, viscosity = 0.05, number_of_particles = 32,
                  particle_integration_scheme = AdamsBashforth(order = 4), rng = MersenneTwister(11))
  for _ in 1:5; advance!(ab); end
  @test ab.cache.history_filled == 3                      # the multistep branch is the live one

  ab_bytes = allocations_of(advect!, ab.particle_integration_scheme, ab.tracers,
                            velocity_physical(ab.cache), ab.domain,
                            ab.particle_buffers, 1.0e-3)
  @info "per-advance host allocations, multistep branch" ab_bytes
  @test ab_bytes == 0

  # ---- and the weight solve itself, isolated: the whole of the above ------------------------
  weight_bytes = allocations_of(IT.Particles._adams_bashforth_weights,
                                zeros(Float64, 4), zeros(Float64, 4), 1.0e-3,
                                [1.0e-3, 1.0e-3, 1.0e-3], 4)
  @info "weight-solve host allocations" weight_bytes
  @test weight_bytes == 0
  @test ab_bytes == weight_bytes                             # the advance's whole cost is the solve
end
