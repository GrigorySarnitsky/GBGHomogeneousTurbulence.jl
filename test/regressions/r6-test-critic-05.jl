# Witness: a cache built without tracers has no trail of the velocity at the particles, and the two
# operations that need one — the particle step and the particle `deposit!` — must refuse it with a
# named `ArgumentError`, not fail deep inside `interpolate!` or on a `nothing`.
#
# The claim under test (r6, test-critic lane): neither guard was exercised anywhere in test/ — the
# neighbouring guards on a cache built for another scheme were, but those caches all had tracers, so
# the `=== nothing` branch was never taken by the suite. This file exercises both guards directly;
# delete either check and its @test_throws below fails (the failure then surfaces as a MethodError
# from library internals, or as an error about a stale field, neither of which names what is
# missing).

using Test, Random, GBGHomogeneousTurbulence
using GBGPeriodicFields: CatmullRom

@testset "a cache built without tracers is refused by name at the particle step and at the particle deposit!" begin
  domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_family = Array)
  tracers = Tracers(domain; number_of_particles = 5, interpolation_scheme = CatmullRom,
                    rng = MersenneTwister(1))
  cache = ObservablesCache(domain)                      # no tracers ⇒ no trail
  @test cache.velocity_at_particles_trail === nothing   # the mismatch this witness pairs with tracers

  # Guard 1: the particle step refuses the pairing on its own entry.
  @test_throws ArgumentError advect!(Heun(), tracers, domain, cache, 0.01)

  # Guard 2: the particle deposit! refuses the same pairing on its own entry.
  @test_throws ArgumentError deposit!(cache, tracers, 0.0)

  # The read refuses it too, in the reader's terms.
  @test_throws ArgumentError velocity_at_particles_trail(cache)

  # Both refusals name what is missing and how to supply it, so the fix is in the message.
  for act in (() -> advect!(Heun(), tracers, domain, cache, 0.01), () -> deposit!(cache, tracers, 0.0))
    err = try
      act()
      nothing
    catch e
      e
    end
    @test err isa ArgumentError
    @test occursin("no trail of the velocity at the particles", err.msg)
    @test occursin("tracers", err.msg) && occursin("particle_integration_scheme", err.msg)
  end
end
