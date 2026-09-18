# Decision 61 — the advanced STATE is re-projected every step, so its divergence is pinned at
# roundoff instead of compounding. Before the pin, the stage tendencies were projected but the
# state was not: divergence injected at roundoff by the stage combinations was damped only by
# exp(−νκ²Δt) — nearly nothing at the largest scales — and, measured in Float32 at 32³, grew
# ×120 per 1500 steps to 800×eps by step 2000. The discriminating half injects a LARGE divergent
# component by hand (the fields_modified! escape hatch): one step must scrub it to roundoff,
# which no viscous decay could fake.
using Test, GBGHomogeneousTurbulence
using GBGPeriodicFields: divergence, l2norm, field_data, gradient!
using Random


@testset "the advanced state is re-projected: divergence pinned at roundoff" begin
  @testset "a healthy Float32 run stays at roundoff over 300 steps" begin
    sim = Simulation(grid_points_per_axis = 16, element_type = Float32, rng = MersenneTwister(7))
    for _ in 1:300; advance!(sim); end
    d = l2norm(divergence(sim.state.velocity_spectral, sim.domain.multipliers))
    @test d < 10 * eps(Float32)                  # was ~7×eps at 500 steps pre-fix and GROWING
  end

  @testset "an injected divergent component is scrubbed in one step" begin
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, rng = MersenneTwister(7))
    û = sim.state.velocity_spectral
    # A pure-gradient (fully divergent) field of O(1) amplitude: u += ∇g.
    ĝ = new_scalar_field_spectral(sim.domain)   # the domain allocator, from the umbrella
    fill!(field_data(ĝ), 0)
    field_data(ĝ)[2, 3, 2] = 1e4 + 5e3im
    ∇ĝ = new_vector_field_spectral(sim.domain)
    gradient!(∇ĝ, ĝ, sim.domain.multipliers)
    field_data(û) .+= field_data(∇ĝ)
    # The full escape-hatch recipe: announce the mutation, then re-deposit so the cache serves the
    # mutated state (nothing in the cache is ever recomputed on a read).
    fields_modified!(sim.cache)
    deposit!(sim.cache, sim.state, sim.domain, sim.buffers)
    before = l2norm(divergence(û, sim.domain.multipliers))
    @test before > 1.0                           # the corruption is real and large
    advance!(sim)
    after = l2norm(divergence(sim.state.velocity_spectral, sim.domain.multipliers))
    @test after < 1e-12                          # one step pins it at roundoff
  end
end
