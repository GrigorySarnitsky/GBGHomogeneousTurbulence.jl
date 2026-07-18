# DerivedFields tests — the observation-cache contract: accessors recompute exactly when stale
# (stamp behind the fields epoch), memoize otherwise; `resolved_fields_modified!` is the out-of-band
# invalidation verb; an undeclared chart is an error; `step!` advances the epoch.

using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data
using Random
using Test


@testset "derived fields" begin
  N = 16
  L = 2π
  domain = FixedDomain(N, L; element_type = Float64, dealiasing = TwoThirds(), array_type = Array)
  û = spectral_vector(domain)
  random_solenoidal_velocity!(û, domain; kinetic_energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(1))
  state = ResolvedFields(û, nothing)

  @testset "accessors recompute once and memoize" begin
    derived = DerivedFields(domain)
    u = physical_velocity(derived, state, domain)
    u_reference = physical_vector(domain)
    velocity_to_physical!(u_reference, û, domain, spectral_vector(domain))
    @test field_data(u) == field_data(u_reference)                 # the recompute is the recovery
    @test physical_velocity(derived, state, domain) === u          # second read: memoized, same storage
    ω = physical_vorticity(derived, state, domain)
    ω_reference = physical_vector(domain)
    vorticity_to_physical!(ω_reference, û, domain, spectral_vector(domain))
    @test field_data(ω) == field_data(ω_reference)
  end

  @testset "out-of-band mutation needs the invalidation verb" begin
    derived = DerivedFields(domain)
    before = copy(field_data(physical_velocity(derived, state, domain)))
    random_solenoidal_velocity!(û, domain; kinetic_energy = 0.7, peak_wavenumber = 3.0, rng = MersenneTwister(2))
    # Without the verb the chart still serves the previous fields — the documented contract.
    @test field_data(physical_velocity(derived, state, domain)) == before
    resolved_fields_modified!(derived)
    after = field_data(physical_velocity(derived, state, domain))
    @test after != before                                          # recomputed from the new û
    u_reference = physical_vector(domain)
    velocity_to_physical!(u_reference, û, domain, spectral_vector(domain))
    @test after == field_data(u_reference)
  end

  @testset "an undeclared chart is an error; charts are opt-in" begin
    velocity_only = DerivedFields(domain; charts = (:velocity,))
    @test physical_velocity(velocity_only, state, domain) isa Any   # allocated chart reads fine
    @test_throws ArgumentError physical_vorticity(velocity_only, state, domain)
    @test_throws ArgumentError DerivedFields(domain; charts = (:velocity, :enstrophy))
  end

  @testset "step! advances the fields epoch" begin
    derived = DerivedFields(domain)
    buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = false)
    conditions = FlowConditions(viscosity = 0.1, schmidt = 1.0,
                                velocity_forcing = NoForcing(), scalar_forcing = NoForcing())
    generator = ResolvedGenerator(domain, conditions)
    epoch0 = derived.fields_epoch
    u_before = copy(field_data(physical_velocity(derived, state, domain)))
    step!(IFLowStorageRK3(), state, generator, domain, buffers, derived, 0.01)
    @test derived.fields_epoch == epoch0 + 1
    @test field_data(physical_velocity(derived, state, domain)) != u_before   # recomputed post-step
  end

  @testset "Simulation-level accessors" begin
    sim = Simulation(grid_points_per_axis = N, viscosity = 0.05; scalar = false, rng = MersenneTwister(4))
    u = physical_velocity(sim)
    @test field_data(u) == field_data(physical_velocity(sim.derived, sim.state, sim.domain))
    @test physical_vorticity(sim) === physical_vorticity(sim.derived, sim.state, sim.domain)
    random_solenoidal_velocity!(sim.state.velocity, sim.domain; kinetic_energy = 0.9,
                                peak_wavenumber = 2.0, rng = MersenneTwister(5))
    resolved_fields_modified!(sim)
    @test kinetic_energy(physical_velocity(sim)) ≈ kinetic_energy(sim.state.velocity)
  end
end
