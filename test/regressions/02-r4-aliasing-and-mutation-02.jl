# Witness r4-aliasing-and-mutation-02.
#
# `deposit!` is the one call that sees BOTH the state and the cache, so it is where a
# scalar-configuration mismatch between the two must be caught. Today its scalar branch is gated by
#
#     if state.scalar_spectral !== nothing && cache.scalar_physical !== nothing   # Propagator.jl:527
#
# so a scalar-carrying state paired with a scalar-less cache takes the `false` arm and the deposit is
# skipped in silence. `check_deposits` cannot catch it afterwards — it is never handed the state, and
# its own guard `cache.scalar_physical === nothing || …` (Cache.jl:330) is satisfied by the first
# disjunct. The OPPOSITE mismatch (cache carries the slot, state does not) IS caught, because the
# slot's epoch stays at its never-deposited sentinel while the fields epoch advances; that asymmetry
# is what this witness pins down. Left unflagged, the mismatch surfaces one `step!` later as
# `ArgumentError: this run carries no passive scalar` — a claim that is factually false about the run.

using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data
using Random
using Test

const CacheModule = GBGIsotropicTurbulence.Cache


function seeded_state(domain, rng; scalar::Bool)
  û = new_vector_field_spectral(domain)
  field_data(û) .= 1e-2 .* complex.(randn(rng, Float64, size(field_data(û))),
                                    randn(rng, Float64, size(field_data(û))))
  scalar || return ResolvedFields(û, nothing)
  φ̂ = new_scalar_field_spectral(domain)
  field_data(φ̂) .= 1e-2 .* complex.(randn(rng, Float64, size(field_data(φ̂))),
                                    randn(rng, Float64, size(field_data(φ̂))))
  return ResolvedFields(û, φ̂)
end


@testset "a scalar-carrying state paired with a scalar-less cache is rejected, not silently skipped" begin
  domain = FixedDomain(grid_points_per_axis = 16, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_type = Array)

  # --- the mismatch: the state evolves φ̂, the hand-built cache has no slot to receive φ ---
  rng = MersenneTwister(1)
  state = seeded_state(domain, rng; scalar = true)
  buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = true)
  cache = ObservablesCache(domain; scalar = false)

  # `deposit!` holds both halves of the configuration, so it is the call that must flag the mismatch
  # at its source — as its scalar-less counterpart already is, one iteration later.
  @test_throws Exception deposit!(cache, state, domain, buffers)

  # --- control 1: the symmetric mismatch IS flagged today (cache has the slot, state has no φ̂) ---
  rng2 = MersenneTwister(1)
  state_noscalar = seeded_state(domain, rng2; scalar = false)
  buffers_noscalar = allocate_buffers(IFLowStorageRK3(), domain; scalar = false)
  cache_scalar = ObservablesCache(domain; scalar = true)
  deposit!(cache_scalar, state_noscalar, domain, buffers_noscalar)
  @test_throws Exception CacheModule.check_deposits(cache_scalar)

  # --- control 2: no false positive on either matched configuration ---
  rng3 = MersenneTwister(2)
  matched_scalar = seeded_state(domain, rng3; scalar = true)
  cache_ok = ObservablesCache(domain; scalar = true)
  deposit!(cache_ok, matched_scalar, domain, buffers)
  @test CacheModule.check_deposits(cache_ok) === cache_ok

  rng4 = MersenneTwister(3)
  matched_plain = seeded_state(domain, rng4; scalar = false)
  cache_plain = ObservablesCache(domain; scalar = false)
  deposit!(cache_plain, matched_plain, domain, buffers_noscalar)
  @test CacheModule.check_deposits(cache_plain) === cache_plain
end
