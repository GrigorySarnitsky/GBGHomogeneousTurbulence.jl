# Witness: a configured, rate-carrying scalar forcing must never be silently discarded.
#
# `ResolvedGenerator(domain, conditions; scalar = false)` allocates no scalar rate array
# (src/Generator.jl:262), and `prepare!` gates `set_forcing_rate!` on `generator.scalar_rate === nothing`
# (src/Generator.jl:287-288) — a gate that never consults the state it was handed. Pair such a generator
# with a scalar-carrying `ResolvedFields` and a `scalar_forcing` that declares `uses_steady_linear_rate`
# (`ConstantPower`, `Linear`) and the forcing's ONLY hook, `set_forcing_rate!`, is never called: the run
# proceeds to completion with the configured forcing having exactly zero effect, and no error is raised
# anywhere in construction, `prepare!`, `step!`, or `deposit!`.
#
# The package's own doctrine on this class is explicit (src/Generator.jl:143-145): "A forcing that fills
# a rate without declaring it would be handed `nothing` and go silently unapplied, so that mismatch is a
# construction-time error rather than a wrong quiet run." This is the same wrong quiet run, reached from
# the other side of the pairing.
#
# The assertion below is deliberately agnostic about the fix: EITHER the mismatch is rejected with an
# error (the doctrine's remedy — `prepare!` holds both the state and the conditions, so it can see it),
# OR the forcing is actually applied. What must not happen is the third outcome, which is what the tree
# does today: the run completes, silently bit-identical to `NoForcing()`.

using Test
using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data
using Random


const N       = 16
const DT      = 2.0e-3
const NSTEPS  = 400
const SCHEME  = IFLowStorageRK3()


domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, element_type = Float64,
                     dealiasing = TwoThirds(), array_type = Array)

# One seeded initial condition, reused verbatim by every run below.
const û0 = new_vector_field_spectral(domain)
const φ̂0 = new_scalar_field_spectral(domain)
random_solenoidal_velocity_spectral!(û0, domain; kinetic_energy = 0.5, envelope_wavenumber = 2.0,
                                     rng = MersenneTwister(11))
random_scalar_spectral!(φ̂0, domain; scalar_variance = 1.0, envelope_wavenumber = 2.0,
                        rng = MersenneTwister(12))


"""Advance the seeded state `NSTEPS` steps and return the scalar's spectral coefficients."""
function evolve_scalar(scalar_forcing; generator_scalar::Bool)
  conditions = FlowConditions(; viscosity = 0.05, schmidt = 1.0,
                              velocity_forcing = NoForcing(), scalar_forcing = scalar_forcing)
  state = ResolvedFields(domain; scalar = true)
  copyto!(field_data(state.velocity_spectral), field_data(û0))
  copyto!(field_data(state.scalar_spectral), field_data(φ̂0))

  generator = ResolvedGenerator(domain, conditions; scalar = generator_scalar)
  buffers   = allocate_buffers(SCHEME, domain; scalar = true)
  cache     = ObservablesCache(domain; scalar = true)
  deposit!(cache, state, domain, buffers)
  for _ in 1:NSTEPS
    step!(SCHEME, state, generator, domain, buffers, cache, DT)
    deposit!(cache, state, domain, buffers)
  end
  return copy(field_data(state.scalar_spectral))
end


@testset "a rate-carrying scalar forcing is never silently discarded by a scalar-free generator" begin
  unforced = evolve_scalar(NoForcing(); generator_scalar = true)

  # Control: correctly wired, the same forcing demonstrably changes the scalar's evolution.
  wired = evolve_scalar(ConstantPower(domain; injection_rate = 0.1); generator_scalar = true)
  @test wired != unforced

  # The mismatch. Either it is caught, or the forcing takes effect — never a quiet identical run.
  mismatched = try
    evolve_scalar(ConstantPower(domain; injection_rate = 0.1); generator_scalar = false)
  catch err
    err     # an error is an acceptable outcome: the misconfiguration was reported
  end
  @test mismatched isa Exception || mismatched != unforced
end
