# Witness: under `PhaseShift`, the generator's displaced-velocity freshness token records the
# *container identity* of `û` (`generator.displaced_velocity_source = û`, Generator.jl:391), and
# `scalar_rhs!` reuses the cached displaced velocity whenever that identity still matches
# (`if generator.displaced_velocity_source !== û`, Generator.jl:525).  But `û` in a run is
# `state.velocity_spectral`, ONE container whose contents every stage update overwrites in place.
# Identity therefore says nothing about value: after an in-place update of `û` the token still
# matches while `phase_shift.u_shifted` holds the displaced recovery of the PREVIOUS state, and the
# scalar right-hand side comes out silently wrong — no error, no NaN.
#
# The contract under test is the one the `ResolvedGenerator` docstring states:
#   "It is opportunistic, never load-bearing: a `scalar_rhs!` handed a different `û` than the
#    recorded one rebuilds the displaced velocity itself, value-identically."
# For that to hold, `scalar_rhs!` must return the same value at a given state whether or not the
# generator carries a cached displaced velocity.
#
# Every comparison below is between two assemblies AT THE SAME `û` — a cached generator against a
# freshly built one — so the only thing that varies is the cache.

using Test
using Random
using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data, to_physical!, combine!

@testset "scalar_rhs! is value-independent of the generator's cached displaced velocity" begin
  N, L, ν, dt = 16, 2π, 0.05, 0.05

  # Drive one velocity assembly (which arms the cache), optionally apply an ordinary in-place stage
  # update to `û`, then assemble the scalar RHS twice at the resulting state: once on the generator
  # that carries the cache, once on a fresh generator that must rebuild.  Returns the two results.
  function cached_versus_fresh(dealiasing; mutate::Bool)
    domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = Float64,
                         dealiasing = dealiasing, array_family = Array)
    û = new_vector_field_spectral(domain)
    φ̂ = new_scalar_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5, envelope_wavenumber = 2.0,
                                         rng = MersenneTwister(1))
    random_scalar_spectral!(φ̂, domain; scalar_variance = 1.0, envelope_wavenumber = 2.0,
                            rng = MersenneTwister(2))
    state = ResolvedFields(û, φ̂)
    conditions = FlowConditions(viscosity = ν, schmidt = 1.0,
                                velocity_forcing = NoForcing(), scalar_forcing = NoForcing())

    scratch_v = new_vector_field_spectral(domain)
    scratch_s = new_scalar_field_spectral(domain)
    # Both assemblies CONSUME their physical argument, so each recovery gets its own register.
    velocity() = (u = new_vector_field_physical(domain);
                  to_physical!(u, û, domain.transform_plans, scratch_v); u)
    vorticity() = (ω = new_vector_field_physical(domain);
                   vorticity_physical!(ω, û, domain, scratch_v); ω)
    scalar() = (φ = new_scalar_field_physical(domain);
                to_physical!(φ, φ̂, domain.transform_plans, scratch_s); φ)

    cached = ResolvedGenerator(domain, conditions; scalar = true)
    prepare!(cached, state, domain, dt)
    N̂u = new_vector_field_spectral(domain)
    velocity_rhs!(N̂u, cached, û, velocity(), vorticity(), domain)   # arms the cache / token

    mutate && combine!(û, 1.0, û, dt, N̂u)     # ûᵢ ← ûᵢ + Δt N̂u — SAME container, new contents

    N̂_cached = new_scalar_field_spectral(domain)
    scalar_rhs!(N̂_cached, cached, û, φ̂, velocity(), scalar(), domain)

    fresh = ResolvedGenerator(domain, conditions; scalar = true)    # no cache, no token
    prepare!(fresh, state, domain, dt)
    N̂_fresh = new_scalar_field_spectral(domain)
    scalar_rhs!(N̂_fresh, fresh, û, φ̂, velocity(), scalar(), domain)

    return field_data(N̂_cached), field_data(N̂_fresh)
  end

  reldiff((a, b)) = maximum(abs, a .- b) / maximum(abs, b)

  # Control 1 — the harness is sound: with `û` left alone the token is honest, and the cached
  # assembly agrees with the rebuilt one to round-off.
  @test reldiff(cached_versus_fresh(PhaseShift(); mutate = false)) < 1e-12

  # Control 2 — a mask strategy caches nothing, so the in-place update cannot desynchronize it.
  @test reldiff(cached_versus_fresh(TwoThirds(); mutate = true)) < 1e-12

  # The claim: after an ordinary in-place stage update of `û`, the cached assembly must STILL agree
  # with the honest rebuild.  It does not — the token matched on identity while the value moved.
  @test reldiff(cached_versus_fresh(PhaseShift(); mutate = true)) < 1e-12
end
