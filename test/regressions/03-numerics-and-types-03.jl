# Witness: the cached `max_speed(cache)` must return the run's own real element type, exactly as the
# field form `max_speed(u)` does — the two are one generic serving "the same quantity", and the
# Observables module docstring promises "Each returns the field's own real element type rather than a
# fixed Float64, so a `Float32` run measures in `Float32`."

using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: deposit_max_speed!
using Random
using Test


@testset "the cached max_speed preserves the run's element type, like its field-form sibling" begin
  N = 8
  domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, element_type = Float32,
                       dealiasing = TwoThirds(), array_type = Array)
  û = new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5, envelope_wavenumber = 2.0,
                                       rng = MersenneTwister(1))
  state = ResolvedFields(û, nothing)
  buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = false)
  cache = ObservablesCache(domain)

  # The field form, measured on the recovered physical velocity: the reference type and value.
  deposit!(cache, state, domain, buffers)
  u = velocity_physical(cache)
  reference = max_speed(u)
  @test reference isa Float32                                    # the field form measures in Float32

  # The cached form: the same quantity, deposited by the run's own closing deposit.
  cached = max_speed(cache)
  @test cached == reference                                      # same number …
  @test typeof(cached) === typeof(reference)                     # … and the same type

  # And through the bare producer call, independent of the deposit! path.
  fresh = ObservablesCache(domain)
  deposit_max_speed!(fresh, reference)
  @test typeof(max_speed(fresh)) === Float32
end
