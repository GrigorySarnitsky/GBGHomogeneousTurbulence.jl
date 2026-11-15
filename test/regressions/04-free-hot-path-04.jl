# Witness: a particle scheme must not run on a cache that keeps fewer samples of the velocity at the
# particles than the scheme integrates over.
#
# The defect: the cache was built apart from the scheme, with a sample history that defaulted to
# none, so a cache without history handed to a four-step scheme was a construction-time mismatch
# nothing rejected, and the first push died with a `BoundsError` from library internals. The right
# behaviour is a named `ArgumentError` where the two meet.
#
# The cache is now built FROM the scheme, so the mismatch needs two schemes to make; where they meet
# is the particle step, which refuses it by name.

using Test, Random
using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data, CatmullRom

include(joinpath(@__DIR__, "..", "prescribed_flow.jl"))

@testset "a cache keeping too few samples for the scheme is refused by name, not by a later BoundsError" begin
  domain = FixedDomain(grid_points_per_axis = 16, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_family = Array)
  uniform!(u, t) = (field_data(u) .= 0.3; u)
  scheme = AB(4)                              # integrates over four samples

  make = () -> begin
    tracers = Tracers(domain; number_of_particles = 4, interpolation_scheme = CatmullRom,
                      rng = MersenneTwister(1))
    (tracers, ObservablesCache(domain; tracers, particle_integration_scheme = Heun()))   # keeps two
  end

  # 1. The mismatch cannot be made by omission: a cache with tracers names its scheme.
  let (tracers, cache) = make()
    @test_throws ArgumentError ObservablesCache(domain; tracers)
  end

  # 2. Whatever the pairing, no index error may escape from library internals: it is rejected by
  #    name (`ArgumentError`) at the first step, and stays rejected.
  let (tracers, cache) = make()
    outcomes = map(1:3) do _
      try
        advect_in_prescribed_flow!(uniform!, scheme, tracers, domain, cache, (0.01,))
        :advanced
      catch err
        err isa ArgumentError ? :rejected : Symbol(nameof(typeof(err)))
      end
    end
    @test outcomes[1] === :rejected
  end
end
