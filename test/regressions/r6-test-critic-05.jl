# Witness: the cache/tracer mismatch guards — `allocate_buffers` (via `_allocate_particle_buffers`,
# src/Particles.jl:308-311) and the particle `deposit!` (src/Particles.jl:531-534) — must refuse a
# cache built without `number_of_particles` (whose `velocity_at_particles` slot is `nothing`) with a
# named `ArgumentError`, not fail deep inside `interpolate!`/`similar`.
#
# The claim under test (r6, test-critic lane): neither guard is exercised anywhere in test/ — the
# neighbouring history-depth guard is (04-free-hot-path-04.jl, 04-free-modules-04.jl), but both of
# those build their cache WITH `number_of_particles`, so the `=== nothing` branch is never taken by
# the suite. This file exercises both guards directly; delete either check and its @test_throws
# below fails (the failure then surfaces as a MethodError/BoundsError from library internals, or as
# a silent wrong construction, neither of which is an ArgumentError naming the missing slot).

using Test, Random, GBGIsotropicTurbulence
using GBGPeriodicFields: field_data, CatmullRom

@testset "a cache built without number_of_particles is refused by name at allocate_buffers and at the particle deposit!" begin
  domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_type = Array)
  tracers = Tracers(domain; number_of_particles = 5, interpolation_scheme = CatmullRom,
                    rng = MersenneTwister(1))
  cache = ObservablesCache(domain)                # no number_of_particles ⇒ slot is `nothing`
  @test cache.velocity_at_particles === nothing   # the mismatch this witness pairs with tracers

  u = new_vector_field_physical(domain)
  fill!(field_data(u), 0.2)

  # Guard 1: buffer allocation refuses the pairing where it is introduced.
  @test_throws ArgumentError allocate_buffers(Heun(), tracers, cache)

  # Guard 2: the particle deposit! refuses the same pairing on its own entry.
  @test_throws ArgumentError deposit!(cache, tracers, u)

  # Both refusals name the missing slot, so a hand-assembling user learns the fix from the message.
  for act in (() -> allocate_buffers(Heun(), tracers, cache), () -> deposit!(cache, tracers, u))
    err = try
      act()
      nothing
    catch e
      e
    end
    @test err isa ArgumentError
    @test occursin("velocity-at-particles slot", err.msg)
    @test occursin("number_of_particles", err.msg)
  end
end
