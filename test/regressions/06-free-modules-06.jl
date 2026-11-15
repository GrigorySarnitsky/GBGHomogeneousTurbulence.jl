# Witness for the architecture finding "the memory/optimality audits enumerate one particle
# integration scheme": the audits pinned the per-particle residency of `Heun` alone, so what a run
# under a multistep scheme actually held was measured by nothing — and the audits' reflective walk
# could not have measured it, since it stopped at the `Vector` holding the earlier samples and
# counted the container for its contents.
#
# First written as a supporting measurement that only printed; the particle-scale ledger of
# test/memory_audit.jl now holds the count against a bound, so this asserts what it once displayed:
# with the audits' own walk, a front-door run under each scheme holds exactly the (M, 3) arrays its
# update formula needs — the positions and one per velocity value — and the walk descends into the
# trail to find them.
using GBGHomogeneousTurbulence
using GBGPeriodicFields: CatmullRom
using Random
using Test


# `pkgdir` rather than a path counted from this file: a witness is authored under
# .claude/bug-hunt/witnesses/ and PROMOTED into test/regressions/, so a fixed number of `..` hops
# resolves outside the repository once it moves. (Walking up to the first Project.toml is also wrong
# here — `test/` carries one of its own, so the walk stops a level early.)
include(joinpath((let d = @__DIR__; while !isfile(joinpath(d, "src", "GBGHomogeneousTurbulence.jl")); d = dirname(d); end; d end), "test", "audit_ops.jl"))

@testset "the audits' walk counts every particle array a run holds, under every scheme" begin
  M = 5
  domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π, element_type = Float64,
                       array_family = Array, dealiasing = TwoThirds())
  particle_arrays(owner) = (acc = AbstractArray[];
                            collect_field_arrays!(acc, owner, Set{UInt}(), 8; keep = a -> size(a) == (M, 3));
                            acc)

  # What a live front-door run holds on each point of the particle-scheme axis: the positions and
  # the velocity values of the scheme's formula, k for `AB(k)` and k + 1 for `ABM(k)`.
  for (scheme, velocity_values) in ((Heun(), 2), (AB(2), 2), (AB(4), 4), (AB(8), 8), (ABM(4), 5))
    sim = Simulation(domain; viscosity = 0.1,
                     particles = ParticleTracking(number_of_particles = M, particle_integration_scheme = scheme,
                                                  traversal_mode = :none),
                     rng = MersenneTwister(1))
    @test length(particle_arrays(sim)) == 1 + velocity_values
    # The walk reaches inside the trail: its slots are found one by one, not counted as a container.
    slots = sim.cache.velocity_at_particles_trail.values
    @test slots isa AbstractArray && !(eltype(slots) <: Number)
    @test length(particle_arrays(sim.cache)) == length(slots) == velocity_values
  end
end
