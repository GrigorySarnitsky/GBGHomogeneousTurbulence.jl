# Witness: `ResolvedGenerator`'s `scalar` keyword must mean the same thing under every dealiasing
# strategy — and a mismatch against the state must not surface as a dependency-internal MethodError.
#
# Its docstring documents the keyword's whole effect as one allocation:
#   "`scalar = false` — pass `true` when the run carries a passive scalar; it allocates the scalar's
#    forcing-rate array, required for a scalar-forced run."
# For an UNFORCED scalar that makes `scalar = false` a legitimate configuration — and under
# `TwoThirds` and `HouLi` it demonstrably is: the scalar advances bit-identically either way
# (checked below). But the same flag also, undocumented, gates the `PhaseShiftBuffers` scalar
# scratch (`Generator.jl:260` → `Generator.jl:126–140`), leaving `scalar_shifted` / `scalar_copy` /
# `phi_shifted` as `nothing`. `step!`'s `has_scalar` comes from `state.scalar_spectral`, not from the
# generator, so `scalar_rhs!` reaches `convolve!(phase_shift.scalar_shifted, φ̂, …)`
# (`Generator.jl:548`) with a `nothing` destination.
#
# Either repair satisfies this test: allocate the scalar scratch unconditionally, or reject the
# mismatch with a package-level error that names it (as the constructor already rejects a misdeclared
# forcing). What must not stand is the current outcome — `MethodError: no method matching
# convolve!(::Nothing, …)` thrown from inside GBGPeriodicFields, naming nothing a caller could act on.

using Test, Random
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Propagator: deposit!
using GBGPeriodicFields: field_data


# One scalar-carrying run whose generator is built with the given `scalar` flag, stepped once.
# Returns the post-step scalar field in spectral representation, or the exception thrown.
function step_once(dealiasing, generator_scalar::Bool)
  domain = FixedDomain(; grid_points_per_axis = 8, side_length = 2π, dealiasing,
                       element_type = Float64, array_family = Array)
  conditions = FlowConditions(; viscosity = 0.05, schmidt = 1.0,
                              velocity_forcing = NoForcing(), scalar_forcing = NoForcing())
  state = ResolvedFields(domain; scalar = true)
  rng = MersenneTwister(20260821)
  random_solenoidal_velocity_spectral!(state.velocity_spectral, domain;
                                       kinetic_energy = 1.5, envelope_wavenumber = 2, rng)
  random_scalar_spectral!(state.scalar_spectral, domain;
                          scalar_variance = 1.0, envelope_wavenumber = 2, rng)
  scheme = IFLowStorageRK3()
  buffers = allocate_buffers(scheme, domain; scalar = true)
  cache = ObservablesCache(domain; scalar = true)
  deposit!(cache, state, domain, buffers)
  generator = ResolvedGenerator(domain, conditions; scalar = generator_scalar)
  try
    step!(scheme, state, generator, domain, buffers, cache, 1e-3)
    return copy(field_data(state.scalar_spectral))
  catch err
    return err
  end
end


@testset "the generator's `scalar` keyword means the same under every dealiasing strategy" begin
  # The baseline: for an unforced scalar the flag is a no-op, as documented.
  for dealiasing in (TwoThirds(), HouLi())
    with_flag    = step_once(dealiasing, true)
    without_flag = step_once(dealiasing, false)
    @test with_flag isa AbstractArray
    @test without_flag isa AbstractArray
    @test with_flag == without_flag
  end

  # The same configuration under PhaseShift: the correct outcomes are the same advance, or a
  # package-level rejection naming the misconfiguration. A MethodError from the field backend is
  # neither.
  reference = step_once(PhaseShift(), true)
  @test reference isa AbstractArray

  outcome = step_once(PhaseShift(), false)
  # A Bool, not the exception itself: a bare `outcome isa MethodError` prints the whole captured
  # field as the failure's evidence, which buries the one-line claim under a screenful of numbers.
  threw_dispatch_failure = outcome isa MethodError
  @test !threw_dispatch_failure                       # never a raw dispatch failure inside PF
  if outcome isa Exception
    message = sprint(showerror, outcome)
    message_names_the_flag = occursin("scalar", first(split(message, '\n')))
    @test message_names_the_flag                      # …and if rejected, the message must say why
  else
    @test outcome == reference                        # …or the scalar must simply advance
  end
end
