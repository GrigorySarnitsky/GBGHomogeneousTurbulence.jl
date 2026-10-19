# The allocation audit (RULE.TEST.ALLOC_ZERO): every exported in-place operation is shown not to
# allocate at field scale, on the CPU, where a materialized temporary is visible.
#
# The package DECLARES the audit to GBGCodingTools: `@alloc_below` and the completeness check at the
# foot are the tool's engines, `GBGCodingTools.TestHarness`. Each row warms its call up once, then
# asserts that one call allocates strictly less than its bound; the completeness check derives the
# required set from the export list, so a new in-place operation fails until it has a row or a stated
# exemption.
#
# BOUNDS. `field_threshold(bytes; components)` admits `bytes ÷ 16` of small temporaries and FFTW's
# per-thread task state for each plan execution, so any field-sized temporary fails. An operation that
# transforms is priced at its plan executions, and the iteration's count is the compute audit's own
# transform ledger (`test/audit_ops.jl`), so the two audits cannot disagree on it. Two kinds of call
# get a wider, stated bound: the seeders, which draw on the host so a seed gives the same field on
# every backend, and `fields_modified!`, whose reality check is O(N²).
#
# This audit sits beside the package's own: `test/memory_audit.jl` ledgers what a run keeps resident,
# and bounds a full iteration against it. This file bounds each operation alone.
using Test
using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data
using Random
using Logging
using GBGHomogeneousTurbulence.Generator: prepare!, finalize!, velocity_rhs!, scalar_rhs!
using GBGHomogeneousTurbulence.Forcing: add_forcing_source!, prepare_forcing!, project_forcing!
using GBGHomogeneousTurbulence.Particles: advect!, restart!, new_vector_point_values
using GBGHomogeneousTurbulence.Propagator: step!, deposit!
using GBGHomogeneousTurbulence.Cache: fields_modified!, particles_modified!
import GBGCodingTools
using GBGCodingTools.TestHarness: @alloc_below, field_threshold
include("audit_ops.jl")

const HT = GBGHomogeneousTurbulence
const OWNED_MODULES = [HT.SimulationDomain, HT.Observables, HT.State, HT.Cache, HT.Forcing,
                       HT.Generator, HT.Propagator, HT.Particles, HT.SimulationRun]

# A forced run with a scalar and tracers on a small CPU grid: every operation reaches its hot path.
const N = 16
const DOMAIN = FixedDomain(grid_points_per_axis = N, side_length = 2π, dealiasing = TwoThirds(),
                           element_type = Float64, array_family = Array)
const SIM = with_logger(NullLogger()) do
  Simulation(DOMAIN; viscosity = 0.05,
             scalar = PassiveScalar(forcing = StochasticOU(forcing_variance = 0.5, correlation_time_in_box_units = 0.3)),
             particles = ParticleTracking(number_of_particles = 8),
             velocity_forcing = ConstantPower(injection_rate = 0.1),
             rng = MersenneTwister(1))
end
const STATE, GENERATOR, BUFFERS, CACHE = SIM.state, SIM.generator, SIM.buffers, SIM.cache
const N̂_VECTOR, N̂_SCALAR = new_vector_field_spectral(DOMAIN), new_scalar_field_spectral(DOMAIN)
const U, Ω, Φ = new_vector_field_physical(DOMAIN), new_vector_field_physical(DOMAIN), new_scalar_field_physical(DOMAIN)
const SCRATCH = new_vector_field_spectral(DOMAIN)
const CONTROLLER = VarianceController(DOMAIN; target = 1.5)
const RESCALING = VarianceRescaling(DOMAIN; target = 1.5, over = :total)
const SAMPLES = new_vector_point_values(SIM.tracers)
const SEED = Xoshiro(2)                        # one generator, so a row does not count its own construction

const VECTOR_BYTES = sizeof(field_data(U))
const SCALAR_BYTES = sizeof(field_data(Φ))
# Plan executions per iteration of this run (IFLowStorageRK3, TwoThirds, with a scalar), from the
# compute audit's transform ledger: each execution transforms one component.
const ITERATION_TRANSFORMS = sum(_transforms(_ops(:RK3, :TwoThirds, true)))
# The reality check reads the self-conjugate planes: O(N²), measured at six planes per component.
const REALITY_CHECK_BYTES = 8 * 4 * N^2 * sizeof(ComplexF64)

bound(; transforms = 1) = field_threshold(VECTOR_BYTES; components = transforms)

# A stopping criterion that lets `run!` take exactly one iteration: `true` at the seeded instant it
# reads first, `false` after the iteration. Named, since `@alloc_below` evaluates its call twice.
const CALLBACK_CALLS = Ref(0)
one_iteration(sim) = isodd(CALLBACK_CALLS[] += 1)
# `step!` opens an iteration its closing deposit must end before the next can begin.
deposited_cache(sim) = (deposit!(sim); sim.cache)


@testset "allocation audit: every in-place operation, on the CPU" begin
  @testset "the run" begin
    @alloc_below bound(transforms = ITERATION_TRANSFORMS) advance!(SIM)
    @alloc_below bound(transforms = ITERATION_TRANSFORMS) run!(one_iteration, SIM)
    @alloc_below bound(transforms = ITERATION_TRANSFORMS) step!(SIM.field_integration_scheme, STATE, GENERATOR,
                                                             DOMAIN, BUFFERS, deposited_cache(SIM), 1e-3)
    deposit!(SIM)
    @alloc_below bound(transforms = 7) deposit!(CACHE, STATE, DOMAIN, BUFFERS)   # recovers u, ω and φ
    @alloc_below bound(transforms = 7) deposit!(SIM)
    @alloc_below bound() deposit!(CACHE, SIM.tracers, velocity_physical(CACHE))
    @alloc_below bound() + REALITY_CHECK_BYTES fields_modified!(SIM)
    deposit!(SIM)
    @alloc_below bound() fields_modified!(CACHE)
    deposit!(SIM)
    @alloc_below bound() particles_modified!(SIM)
    deposit!(SIM)
    @alloc_below bound() particles_modified!(CACHE)
    deposit!(SIM)
  end

  @testset "the generator" begin
    @alloc_below bound(transforms = 2) prepare!(GENERATOR, STATE, DOMAIN, 1e-3)
    @alloc_below bound() finalize!(GENERATOR, STATE, DOMAIN)
    @alloc_below bound(transforms = 6) velocity_rhs!(N̂_VECTOR, GENERATOR, STATE.velocity_spectral, U, Ω, DOMAIN)
    @alloc_below bound(transforms = 4) scalar_rhs!(N̂_SCALAR, GENERATOR, STATE.velocity_spectral,
                                                  STATE.scalar_spectral, U, Φ, DOMAIN)
    @alloc_below bound(transforms = 3) vorticity_physical!(Ω, STATE.velocity_spectral, DOMAIN, SCRATCH)
    @alloc_below bound() truncate_to_band!(STATE.velocity_spectral, DOMAIN)
  end

  @testset "the functions a step calls on a forcing" begin
    @alloc_below bound() add_forcing_source!(GENERATOR.conditions.velocity_forcing, nothing, N̂_VECTOR,
                                             STATE.velocity_spectral, DOMAIN, 0.05)
    @alloc_below bound() add_forcing_source!(CONTROLLER, nothing, N̂_VECTOR, STATE.velocity_spectral, DOMAIN, 0.05)
    @alloc_below bound() add_forcing_source!(GENERATOR.conditions.scalar_forcing, STATE.modeled.scalar_forcing,
                                             N̂_SCALAR, STATE.scalar_spectral, DOMAIN, 0.05)
    @alloc_below bound(transforms = 2) prepare_forcing!(GENERATOR.conditions.scalar_forcing,
                                                       STATE.modeled.scalar_forcing, STATE.scalar_spectral,
                                                       DOMAIN, 1e-3)
    @alloc_below bound() project_forcing!(RESCALING, STATE.velocity_spectral, DOMAIN)
  end

  @testset "the particles" begin
    deposit!(SIM)
    @alloc_below bound() advect!(SIM.particle_integration_scheme, SIM.tracers, velocity_physical(CACHE), DOMAIN,
                                 SIM.particle_buffers, 1e-3)
    @alloc_below bound() interpolate_at_particles!(SAMPLES, velocity_physical(CACHE), SIM.tracers)
    @alloc_below bound() rebuild_traversal!(SIM)
    @alloc_below bound() restart!(SIM.particle_integration_scheme, SIM.particle_buffers)
    fields_modified!(SIM); deposit!(SIM)
  end

  @testset "the seeders: one noise field, drawn into directly on the CPU" begin
    # On a device the draw is made into a host array and moved, a second field's worth; on the CPU
    # the noise field IS host memory and the draws go straight into it, so one field is the bound.
    @alloc_below VECTOR_BYTES + bound() random_solenoidal_velocity_spectral!(
      STATE.velocity_spectral, DOMAIN, 1.5; envelope_wavenumber = 2.0, rng = SEED)
    @alloc_below SCALAR_BYTES + bound() random_scalar_spectral!(
      STATE.scalar_spectral, DOMAIN, 1.0; envelope_wavenumber = 2.0, rng = SEED)
    fields_modified!(SIM); deposit!(SIM)
  end
end

# Completeness, derived from the export list rather than remembered.
GBGCodingTools.TestHarness.allocation_completeness(HT, OWNED_MODULES;
  exempt = Dict(
    :warmup! => "a loop of `advance!` iterations, each bounded by the `advance!` row, until a " *
                "stationarity criterion is met; the criterion records its samples in growing vectors " *
                "by design, so a single call has no fixed allocation to bound",
  ))
