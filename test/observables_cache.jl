# ObservablesCache tests — the no-recompute contract: a read serves the deposited value or throws
# (never rebuilds); slots double as the step's registers (taken mid-iteration, re-deposited at the
# end); the completeness check refuses an iteration that left a slot undeposited.

using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: take_velocity!, check_deposits
using GBGPeriodicFields: field_data, to_physical!
using Random
using Test


@testset "observables cache" begin
  N = 16
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = Float64, dealiasing = TwoThirds(), array_family = Array)
  û = new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û, domain, 0.5; peak_shell = 2.0, rng = MersenneTwister(1))
  state = ResolvedFields(û, nothing)
  buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = false)

  @testset "a read before any deposit throws; the deposit serves it" begin
    cache = ObservablesCache(domain)
    @test_throws ErrorException velocity_physical(cache)
    @test_throws ErrorException vorticity_physical(cache)
    @test_throws ErrorException max_speed(cache)
    deposit!(cache, state, domain, buffers)
    u = velocity_physical(cache)
    u_reference = new_vector_field_physical(domain)
    to_physical!(u_reference, û, domain.transform_plans, new_vector_field_spectral(domain))
    @test field_data(u) == field_data(u_reference)                 # the deposit is the recovery
    @test velocity_physical(cache) === u                         # second read: same storage, no work
    ω_reference = new_vector_field_physical(domain)
    vorticity_physical!(ω_reference, û, domain, new_vector_field_spectral(domain))
    @test field_data(vorticity_physical(cache)) == field_data(ω_reference)
    @test max_speed(cache) == max_speed(u_reference)             # the cached number is the reduction
  end

  @testset "a taken slot refuses reads until re-deposited" begin
    cache = ObservablesCache(domain)
    deposit!(cache, state, domain, buffers)
    take_velocity!(cache)                                        # a producer claims the register
    @test_throws ErrorException velocity_physical(cache)
    @test field_data(vorticity_physical(cache)) isa Any          # the other slot is untouched
    deposit!(cache, state, domain, buffers)
    @test velocity_physical(cache) isa Any
  end

  @testset "a scalar-free cache has no scalar slot" begin
    cache = ObservablesCache(domain)
    @test_throws ArgumentError scalar_physical(cache)
    with_scalar = ObservablesCache(domain; scalar = true)
    @test with_scalar.scalar_physical !== nothing
  end

  @testset "step! leaves the cache mid-iteration; deposit! closes it" begin
    cache = ObservablesCache(domain)
    deposit!(cache, state, domain, buffers)
    conditions = FlowConditions(viscosity = 0.1, schmidt = 1.0,
                                velocity_forcing = NoForcing(), scalar_forcing = NoForcing())
    generator = ResolvedGenerator(domain, conditions)
    epoch0 = cache.fields_epoch
    u_before = copy(field_data(velocity_physical(cache)))
    step!(IFLowStorageRK3(), state, generator, domain, buffers, cache, 0.01)
    @test cache.fields_epoch == epoch0 + 1
    @test_throws ErrorException velocity_physical(cache)         # taken as a stage register
    @test_throws ErrorException check_deposits(cache)            # the iteration is not closed
    deposit!(cache, state, domain, buffers)
    @test check_deposits(cache) === cache
    @test field_data(velocity_physical(cache)) != u_before       # the advanced state's recovery
  end
end
