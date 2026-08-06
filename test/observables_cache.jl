# ObservablesCache tests — the no-recompute contract: a read serves the deposited value or throws
# (never rebuilds); slots double as the step's registers (taken mid-iteration, re-deposited at the
# tail); `resolved_fields_modified!` announces an out-of-band mutation and `deposit!` restores the
# boundary; the boundary check refuses an iteration that left a slot undeposited.

using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Cache: take_velocity!, check_boundary
using GBGPeriodicFields: field_data
using Random
using Test


@testset "observables cache" begin
  N = 16
  L = 2π
  domain = FixedDomain(N, L; element_type = Float64, dealiasing = TwoThirds(), array_type = Array)
  û = new_vector_field_spectral(domain)
  random_solenoidal_velocity!(û, domain; kinetic_energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(1))
  state = ResolvedFields(û, nothing)
  buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = false)

  @testset "a read before any deposit throws; the deposit serves it" begin
    derived = ObservablesCache(domain)
    @test_throws ErrorException velocity_physical(derived)
    @test_throws ErrorException vorticity_physical(derived)
    @test_throws ErrorException max_speed(derived)
    deposit!(derived, state, domain, buffers)
    u = velocity_physical(derived)
    u_reference = new_vector_field_physical(domain)
    velocity_to_physical!(u_reference, û, domain, new_vector_field_spectral(domain))
    @test field_data(u) == field_data(u_reference)                 # the deposit is the recovery
    @test velocity_physical(derived) === u                         # second read: same storage, no work
    ω_reference = new_vector_field_physical(domain)
    vorticity_to_physical!(ω_reference, û, domain, new_vector_field_spectral(domain))
    @test field_data(vorticity_physical(derived)) == field_data(ω_reference)
    @test max_speed(derived) == max_speed(u_reference)             # the cached number is the reduction
  end

  @testset "a taken slot refuses reads until re-deposited" begin
    derived = ObservablesCache(domain)
    deposit!(derived, state, domain, buffers)
    take_velocity!(derived)                                        # a producer claims the register
    @test_throws ErrorException velocity_physical(derived)
    @test field_data(vorticity_physical(derived)) isa Any          # the other slot is untouched
    deposit!(derived, state, domain, buffers)
    @test velocity_physical(derived) isa Any
  end

  @testset "out-of-band mutation: announce, then re-deposit" begin
    derived = ObservablesCache(domain)
    deposit!(derived, state, domain, buffers)
    before = copy(field_data(velocity_physical(derived)))
    random_solenoidal_velocity!(û, domain; kinetic_energy = 0.7, peak_wavenumber = 3.0, rng = MersenneTwister(2))
    resolved_fields_modified!(derived)
    @test_throws ErrorException velocity_physical(derived)         # stale: nothing is recomputed
    deposit!(derived, state, domain, buffers)
    after = field_data(velocity_physical(derived))
    @test after != before                                          # the new deposit is the new field
    u_reference = new_vector_field_physical(domain)
    velocity_to_physical!(u_reference, û, domain, new_vector_field_spectral(domain))
    @test after == field_data(u_reference)
  end

  @testset "a scalar-free cache has no scalar slot" begin
    derived = ObservablesCache(domain)
    @test_throws ArgumentError scalar_physical(derived)
    with_scalar = ObservablesCache(domain; scalar = true)
    @test with_scalar.scalar !== nothing
  end

  @testset "step! leaves the cache mid-iteration; deposit! closes it" begin
    derived = ObservablesCache(domain)
    deposit!(derived, state, domain, buffers)
    conditions = FlowConditions(viscosity = 0.1, schmidt = 1.0,
                                velocity_forcing = NoForcing(), scalar_forcing = NoForcing())
    generator = ResolvedGenerator(domain, conditions)
    epoch0 = derived.fields_epoch
    u_before = copy(field_data(velocity_physical(derived)))
    step!(IFLowStorageRK3(), state, generator, domain, buffers, derived, 0.01)
    @test derived.fields_epoch == epoch0 + 1
    @test_throws ErrorException velocity_physical(derived)         # taken as a stage register
    @test_throws ErrorException check_boundary(derived)            # the iteration is not closed
    deposit!(derived, state, domain, buffers)
    @test check_boundary(derived) === derived
    @test field_data(velocity_physical(derived)) != u_before       # the advanced state's recovery
  end

  @testset "Simulation-level accessors forward to the cache" begin
    sim = Simulation(grid_points_per_axis = N, viscosity = 0.05; scalar = false, rng = MersenneTwister(4))
    u = velocity_physical(sim)                                     # the constructor's seeding deposit
    @test u === velocity_physical(sim.derived)
    @test vorticity_physical(sim) === vorticity_physical(sim.derived)
    @test max_speed(sim) == max_speed(sim.derived)
    random_solenoidal_velocity!(sim.state.velocity, sim.domain; kinetic_energy = 0.9,
                                peak_wavenumber = 2.0, rng = MersenneTwister(5))
    resolved_fields_modified!(sim)
    @test_throws ErrorException velocity_physical(sim)
    deposit!(sim)
    @test kinetic_energy(velocity_physical(sim)) ≈ kinetic_energy(sim.state.velocity)
  end
end
