# ObservablesCache tests — the no-recompute contract: a read serves the deposited value or throws
# (never rebuilds); slots double as the step's registers (taken mid-iteration, re-deposited at the
# end); `fields_modified!` announces an out-of-band mutation and `deposit!` restores the
# deposits; the completeness check refuses an iteration that left a slot undeposited.

using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Cache: take_velocity!, check_deposits
using GBGPeriodicFields: field_data, to_physical!
using Random
using Test


@testset "observables cache" begin
  N = 16
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = Float64, dealiasing = TwoThirds(), array_type = Array)
  û = new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5, envelope_wavenumber = 2.0, rng = MersenneTwister(1))
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

  @testset "out-of-band mutation: announce, then re-deposit" begin
    cache = ObservablesCache(domain)
    deposit!(cache, state, domain, buffers)
    before = copy(field_data(velocity_physical(cache)))
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.7, envelope_wavenumber = 3.0, rng = MersenneTwister(2))
    fields_modified!(cache)
    @test_throws ErrorException velocity_physical(cache)         # stale: nothing is recomputed
    deposit!(cache, state, domain, buffers)
    after = field_data(velocity_physical(cache))
    @test after != before                                          # the new deposit is the new field
    u_reference = new_vector_field_physical(domain)
    to_physical!(u_reference, û, domain.transform_plans, new_vector_field_spectral(domain))
    @test after == field_data(u_reference)
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

  # A `Simulation` carries the cache; it is not itself a reading surface (decision 49). The user
  # reaches a deposited observable through `sim.cache` and the state through `sim.state`, so this
  # exercises the out-of-band announce/re-deposit cycle on those two directly.
  @testset "the announce/re-deposit cycle on a live run" begin
    sim = Simulation(grid_points_per_axis = N, viscosity = 0.05; scalar = false, rng = MersenneTwister(4))
    u = velocity_physical(sim.cache)                                # the constructor's seeding deposit
    @test u === velocity_physical(sim.cache)
    random_solenoidal_velocity_spectral!(sim.state.velocity_spectral, sim.domain; kinetic_energy = 0.9,
                                envelope_wavenumber = 2.0, rng = MersenneTwister(5))
    fields_modified!(sim.cache)
    @test_throws ErrorException velocity_physical(sim.cache)
    deposit!(sim)
    @test kinetic_energy(velocity_physical(sim.cache)) ≈ kinetic_energy(sim.state.velocity_spectral)
  end
end
