# Witness: allocate_buffers(::AdamsBashforth{K}, tracers, cache) must not accept a cache whose
# Lagrangian sample history is shallower than the scheme needs (K-1 past samples).
#
# The hand-assembled route both `ParticleIntegratorBuffers`' and `Tracers`' docstrings show builds the cache
# separately from the scheme; `ObservablesCache`'s `history_depth` defaults to 1, so a depth-1 cache
# handed to `AdamsBashforth(order = 4)` is a construction-time mismatch that nothing rejects. The
# right behaviour is a named `ArgumentError` at `allocate_buffers` (the shape every neighbouring
# hazard in this subsystem takes), not a `BoundsError` from library internals on a later `advect!`.

using Test, Random
using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data, CatmullRom

@testset "a cache too shallow for an AdamsBashforth scheme is refused at allocate_buffers, not by a later BoundsError" begin
  domain = FixedDomain(grid_points_per_axis = 16, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_type = Array)
  u = new_vector_field_physical(domain)
  field_data(u) .= 0.3

  scheme = AdamsBashforth(order = 4)          # needs history_depth(scheme) == 4, i.e. 3 past slots

  make = () -> begin
    tracers = Tracers(domain; number_of_particles = 4, interpolation_scheme = CatmullRom,
                      rng = MersenneTwister(1))
    cache = ObservablesCache(domain; number_of_particles = number_of_particles(tracers))
    (tracers, cache)                          # history_depth defaults to 1 ⇒ zero past slots
  end

  # 1. The mismatch is detectable where it is created: the cache carries fewer past-sample slots
  #    than the scheme's order requires.
  let (tracers, cache) = make()
    @test length(cache.velocity_at_particles_history) < history_depth(scheme) - 1
  end

  # 2. The guard: `allocate_buffers` should refuse the pairing with a named `ArgumentError`.
  let (tracers, cache) = make()
    @test_throws ArgumentError allocate_buffers(scheme, tracers, cache)
  end

  # 3. Whatever the fix, no index error may escape from library internals. Either the pairing is
  #    rejected up front (`ArgumentError`) or the advance goes through; a `BoundsError` is neither.
  let (tracers, cache) = make()
    outcome = try
      buffers = allocate_buffers(scheme, tracers, cache)
      deposit!(cache, tracers, u)
      advect!(scheme, tracers, u, domain, buffers, 0.01)
      :advanced
    catch err
      err isa ArgumentError ? :rejected : Symbol(nameof(typeof(err)))
    end
    @test outcome === :rejected || outcome === :advanced
  end
end
