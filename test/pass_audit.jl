# The traffic audit (RULE.TEST.PASS_AUDIT): how many times each in-place operation actually reads and
# writes each field-shaped array, measured and pinned exactly.
#
# The package DECLARES the audit to GBGCodingTools: `CountingArray`, `Traffic`, `counting`, `audit`
# and the completeness check at the foot are the tool's engines, `GBGCodingTools.TestHarness`. A
# `CountingArray` wraps a plain `Array` and counts every element read and write; each row asserts an
# array's exact `(reads, writes)`, with the FUSED IDEAL beside it (each needed element read once, each
# output written once), and a count above its ideal must carry a named holder.
#
# The operations that transform are not measured here and are exempted below: FFT plans reject wrapped
# storage. Their traffic is the compute audit's (`test/compute_audit.jl`), which prices the whole
# iteration — transforms, passes and fusion bounds per scheme and dealiasing — from the op model in
# `test/audit_ops.jl`, and each exemption names the row that holds it. The two audits measure
# different units and both stay: this one counts elements per operation, that one field-scale passes
# per iteration.
#
# UNITS. Counts are absolute element touches, from the shapes: P the entries of a vector field in
# spectral representation, S of a scalar one, B the stored entries of the forcing band, and a tracer
# gather's M points × 4³ stencil entries × 3 components.
# REGENERATION. PASS_AUDIT_PRINT=1 prints every measured count; review each change against its ideal —
# a raised count is a fusion regression unless a new holder justifies it — then freeze it in the same
# commit, with the reason.
using Test
using GBGHomogeneousTurbulence
using GBGPeriodicFields: VectorFieldSpectral, VectorFieldPhysical, ScalarFieldSpectral, field_data,
                         materialize_kernel, spectral_band
using Random
using Logging
import KernelAbstractions
import GBGCodingTools
using GBGCodingTools.TestHarness: CountingArray, Traffic, counting, audit
using GBGHomogeneousTurbulence.Forcing: add_forcing_source!, project_forcing!, set_forcing_rate!, prepare_forcing!
using GBGHomogeneousTurbulence.Generator: prepare!, finalize!
using GBGHomogeneousTurbulence.Particles: advect!, new_vector_point_values
using GBGHomogeneousTurbulence.Propagator: deposit!

# The tool does not depend on KernelAbstractions, so a consumer names the backend a counting array
# lives on (the tool's instruction).
KernelAbstractions.get_backend(a::CountingArray) = KernelAbstractions.get_backend(a.data)

const HT = GBGHomogeneousTurbulence
const OWNED_MODULES = [HT.SimulationDomain, HT.Observables, HT.State, HT.Cache, HT.Forcing,
                       HT.Generator, HT.Propagator, HT.Particles, HT.SimulationRun]
const PRINT_COUNTS = get(ENV, "PASS_AUDIT_PRINT", "0") == "1"

const DOMAIN = FixedDomain(grid_points_per_axis = 16, side_length = 2π, dealiasing = TwoThirds(),
                           element_type = Float64, array_type = Array)
quiet(f) = with_logger(f, NullLogger())
const RUN = quiet(() -> Simulation(DOMAIN; viscosity = 0.05, number_of_particles = 8,
                                   velocity_forcing = ConstantPower(injection_rate = 0.1), rng = MersenneTwister(1)))
const OU_RUN = quiet(() -> Simulation(DOMAIN; viscosity = 0.05,
                                      velocity_forcing = StochasticOU(forcing_variance = 0.5,
                                                                      correlation_time_in_box_units = 0.3),
                                      rng = MersenneTwister(2)))

counting_spectral(f) = VectorFieldSpectral(counting(copy(field_data(f))), DOMAIN.grid, DOMAIN.layout)
counting_physical(f) = VectorFieldPhysical(counting(copy(field_data(f))), DOMAIN.grid, DOMAIN.layout)

const Û = counting_spectral(RUN.state.velocity_spectral)
const N̂ = counting_spectral(new_vector_field_spectral(DOMAIN))
const U = counting_physical(velocity_physical(RUN.cache))
const RATE = ScalarFieldSpectral(counting(zeros(ComplexF64, size(field_data(new_scalar_field_spectral(DOMAIN))))),
                                 DOMAIN.grid, DOMAIN.layout)
const SAMPLES = new_vector_point_values(RUN.tracers)
const OU_Û = counting_spectral(OU_RUN.state.velocity_spectral)
const OU_STATE = ResolvedFields(OU_Û, nothing, (velocity_forcing = OU_RUN.state.modeled.velocity_forcing,
                                                scalar_forcing = nothing))

const P = length(field_data(Û))
const S = length(field_data(RATE))
const GATHER = 8 * 4^3 * 3                       # M tracers × the 4³ CatmullRom stencil × 3 components
# The stored entries of the default forcing band, shells 1–2: the modes the stochastic source changes.
const B = 3 * count(!iszero, field_data(materialize_kernel(spectral_band(DOMAIN.multipliers, 0.5, 2.5)).field))
# The modes it actually touches: every mode of its companion grid below that grid's Nyquist frequency,
# n/2 × (n − 1)² per component, the companion being the smallest even grid above the band, n = 2(2 + 1).
const COMPANION = let n = 2 * (2 + 1); 3 * (n ÷ 2) * (n - 1)^2 end

const DOUBLE_READ = "PF's one-field `weighted_inner(f, w)` reads each element twice, once as each operand " *
                    "of ⟨f, w f⟩: one pass more than the reduction needs, PF's to remove"
const ACCUMULATE_READ = "the accumulating `convolve!(field, field, band, α, 1)` reads its destination beside " *
                        "its source, although here they are one array"
const WHOLE_COMPANION = "the source is PF's `embed_modes!`, which transfers every mode of the companion grid " *
                        "below its Nyquist frequency; the process is zero outside the band, and the transfer " *
                        "has no band-restricted form"
const TWO_CALL_RATE = "the rate is evaluated from the band kernel and then scaled, two PF calls: no PF operation " *
                      "writes a scaled kernel into a field in one pass"

const VELOCITY_FORCING = RUN.generator.conditions.velocity_forcing
const CONTROLLER = VarianceController(DOMAIN; target = 1.5)
const TOTAL = VarianceRescaling(DOMAIN; target = 1.5, over = :total)
const BAND = VarianceRescaling(DOMAIN; target = 0.5, over = :band)
const LINEAR = Linear(DOMAIN; rate = 0.1)
const OU = OU_RUN.generator.conditions.velocity_forcing
const OU_PROCESS = OU_RUN.state.modeled.velocity_forcing

# Warm each call once, so compilation and first-touch never meet a counter.
for warm in (() -> add_forcing_source!(VELOCITY_FORCING, nothing, N̂, Û, DOMAIN, 0.05),
             () -> add_forcing_source!(CONTROLLER, nothing, N̂, Û, DOMAIN, 0.05),
             () -> project_forcing!(TOTAL, Û, DOMAIN), () -> project_forcing!(BAND, Û, DOMAIN),
             () -> set_forcing_rate!(LINEAR, RATE, Û, DOMAIN), () -> truncate_to_band!(Û, DOMAIN),
             () -> interpolate_at_particles!(SAMPLES, U, RUN.tracers),
             () -> advect!(RUN.particle_integration_scheme, RUN.tracers, U, DOMAIN, RUN.particle_buffers, 1e-3),
             () -> deposit!(RUN.cache, RUN.tracers, U),
             () -> prepare_forcing!(OU, OU_PROCESS, OU_Û, DOMAIN, 1e-3),
             () -> add_forcing_source!(OU, OU_PROCESS, N̂, OU_Û, DOMAIN, 0.05),
             () -> prepare!(OU_RUN.generator, OU_STATE, DOMAIN, 1e-3), () -> finalize!(OU_RUN.generator, OU_STATE, DOMAIN))
  warm()
end


@testset "traffic audit: every measurable in-place operation, element by element" begin
  @testset "forcing hooks" begin
    audit(() -> add_forcing_source!(VELOCITY_FORCING, nothing, N̂, Û, DOMAIN, 0.05),
          "add_forcing_source!(ConstantPower)",
          Traffic("dest", field_data(N̂), (P, P)),
          Traffic("source", field_data(Û), (3P, 0), (2P, 0), DOUBLE_READ); print = PRINT_COUNTS)
    audit(() -> add_forcing_source!(CONTROLLER, nothing, N̂, Û, DOMAIN, 0.05),
          "add_forcing_source!(VarianceController)",
          Traffic("dest", field_data(N̂), (P, P)),
          Traffic("source", field_data(Û), (3P, 0), (2P, 0), DOUBLE_READ); print = PRINT_COUNTS)
    audit(() -> add_forcing_source!(OU, OU_PROCESS, N̂, OU_Û, DOMAIN, 0.05),
          "add_forcing_source!(StochasticOU)",
          Traffic("dest", field_data(N̂), (COMPANION, COMPANION), (B, B), WHOLE_COMPANION),
          Traffic("source", field_data(OU_Û), (0, 0)); print = PRINT_COUNTS)
    audit(() -> project_forcing!(TOTAL, Û, DOMAIN), "project_forcing!(VarianceRescaling :total)",
          Traffic("field", field_data(Û), (4P, P), (2P, P), DOUBLE_READ * "; and " * ACCUMULATE_READ);
          print = PRINT_COUNTS)
    audit(() -> project_forcing!(BAND, Û, DOMAIN), "project_forcing!(VarianceRescaling :band)",
          Traffic("field", field_data(Û), (4P, P), (2P, P), DOUBLE_READ * "; and " * ACCUMULATE_READ);
          print = PRINT_COUNTS)
    audit(() -> set_forcing_rate!(LINEAR, RATE, Û, DOMAIN), "set_forcing_rate!(Linear)",
          Traffic("rate", field_data(RATE), (S, 2S), (0, S), TWO_CALL_RATE),
          Traffic("field", field_data(Û), (0, 0)); print = PRINT_COUNTS)
    audit(() -> prepare_forcing!(OU, OU_PROCESS, OU_Û, DOMAIN, 1e-3), "prepare_forcing!(StochasticOU)",
          Traffic("field", field_data(OU_Û), (0, 0)); print = PRINT_COUNTS)
  end

  @testset "the generator's opening and closing, and the band truncation" begin
    audit(() -> prepare!(OU_RUN.generator, OU_STATE, DOMAIN, 1e-3), "prepare!",
          Traffic("state", field_data(OU_Û), (0, 0)); print = PRINT_COUNTS)
    audit(() -> finalize!(OU_RUN.generator, OU_STATE, DOMAIN), "finalize!",
          Traffic("state", field_data(OU_Û), (0, 0)); print = PRINT_COUNTS)
    audit(() -> truncate_to_band!(Û, DOMAIN), "truncate_to_band!",
          Traffic("field", field_data(Û), (P, P)); print = PRINT_COUNTS)
  end

  @testset "the tracer gathers: the stencil entries each point needs, once" begin
    audit(() -> interpolate_at_particles!(SAMPLES, U, RUN.tracers), "interpolate_at_particles!",
          Traffic("field", field_data(U), (GATHER, 0)); print = PRINT_COUNTS)
    audit(() -> advect!(RUN.particle_integration_scheme, RUN.tracers, U, DOMAIN, RUN.particle_buffers, 1e-3),
          "advect!(Heun)", Traffic("velocity_end", field_data(U), (GATHER, 0)); print = PRINT_COUNTS)
    audit(() -> deposit!(RUN.cache, RUN.tracers, U), "deposit!(the tracer sample)",
          Traffic("field", field_data(U), (GATHER, 0)); print = PRINT_COUNTS)
  end
end


# Completeness, derived from the export list. Each exemption says why the operation is not counted
# element by element here, and, for the ones that transform, which compute-audit row holds its traffic.
const IN_THE_COMPUTE_AUDIT = "transforms, and FFT plans reject wrapped storage; its traffic is the compute " *
                             "audit's, test/compute_audit.jl"
GBGCodingTools.TestHarness.traffic_completeness(HT, OWNED_MODULES;
  exempt = Dict(
    :advance!    => IN_THE_COMPUTE_AUDIT * ": the iteration's transform and pass ledgers, TRANSFORMS_BASE and PASSES_BASE",
    :run!        => IN_THE_COMPUTE_AUDIT * ": iterations of `advance!`, priced per iteration there",
    :warmup!     => IN_THE_COMPUTE_AUDIT * ": iterations of `advance!` until stationarity",
    :step!       => IN_THE_COMPUTE_AUDIT * ": the step's stages, the op lists of test/audit_ops.jl",
    :velocity_rhs! => IN_THE_COMPUTE_AUDIT * ": the velocity assembly, `_velocity_assembly` in test/audit_ops.jl",
    :scalar_rhs! => IN_THE_COMPUTE_AUDIT * ": the scalar assembly, `_scalar_assembly` in test/audit_ops.jl",
    :vorticity_physical! => IN_THE_COMPUTE_AUDIT * ": the closing deposit's vorticity recovery, `_closing_deposit`",
    :random_solenoidal_velocity_spectral! => "transforms the host draw, and FFT plans reject wrapped storage; " *
                                             "an initial-condition call, outside the iteration the compute audit prices",
    :random_scalar_spectral! => "transforms the host draw, and FFT plans reject wrapped storage; an " *
                                "initial-condition call, outside the iteration the compute audit prices",
    :fields_modified!    => "advances an epoch counter and restarts the particle registers; its only field " *
                            "reads are the O(N²) reality check's self-conjugate planes, not a field pass",
    :particles_modified! => "advances an epoch counter; it takes no field",
    :restart!            => "clears a particle scheme's O(M) history; it takes no field",
    :rebuild_traversal!  => "a counting sort over the tracer positions through Atomix, which a wrapper array " *
                            "cannot provide (PF exempts its own `point_traversal_order!` for the same reason); " *
                            "it reads no field",
  ))
