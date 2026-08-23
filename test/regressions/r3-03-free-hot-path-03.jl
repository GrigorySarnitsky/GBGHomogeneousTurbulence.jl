# Witness 03 (lane: free-hot-path) — the `step!` protocol return.
#
# The single home docstring on the bare generic `step!` (src/Propagator.jl) ends with
# "Returns `state`.", and `AbstractIntegrator` documents `step!` as the extension point a
# third-party scheme implements. Both in-tree methods close with `return û, φ̂` instead, so a
# caller following the documented hand-run loop (`state = step!(...)`) binds a `Tuple`, not the
# state. This file asserts the DOCUMENTED contract, for both schemes and both scalar modes.

using Test, Random
using GBGIsotropicTurbulence

@testset "step! returns `state`, as its protocol docstring promises" begin

  # The contract, pinned to the source rather than to memory.
  @test occursin("Returns `state`", string(@doc step!))

  # IFLowStorageRK3, scalar-free — the default scheme.
  s3 = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                  integration_scheme = IFLowStorageRK3(), rng = MersenneTwister(1))
  @test step!(s3.integration_scheme, s3.state, s3.generator, s3.domain, s3.buffers, s3.cache, 1e-3) === s3.state

  # IFRK2, with the passive scalar — the second in-tree method, same promise.
  s2 = Simulation(grid_points_per_axis = 16, viscosity = 0.05, scalar = true,
                  integration_scheme = IFRK2(), rng = MersenneTwister(1))
  @test step!(s2.integration_scheme, s2.state, s2.generator, s2.domain, s2.buffers, s2.cache, 1e-3) === s2.state
end
