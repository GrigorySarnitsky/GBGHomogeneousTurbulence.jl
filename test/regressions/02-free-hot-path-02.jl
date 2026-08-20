# Witness: under PhaseShift, `scalar_rhs!` must assemble the scalar flux from the displaced velocity
# of the û IT WAS HANDED. The generator's `displaced_velocity_source` records the û OBJECT that
# `velocity_rhs!` last shifted — but the objects in this package are mutable wrappers whose contents
# are overwritten in place at every stage, so `===` cannot tell "the same velocity" from "the same
# buffer, now holding a different stage's velocity", and the reuse silently supplies the earlier
# stage's displaced velocity.

using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data, to_physical!
using Random
using Test

const SD = GBGIsotropicTurbulence.SimulationDomain

@testset "scalar_rhs! reuse is keyed on the CONTENTS of û, not on the buffer object" begin
  L, N = 2π, 12
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = Float64,
                       dealiasing = PhaseShift(), array_type = Array)
  conditions = FlowConditions(viscosity = 0.1, schmidt = 1.0,
                              velocity_forcing = NoForcing(), scalar_forcing = NoForcing())

  spectral_velocity(seed, κ0) = (û = SD.new_vector_field_spectral(domain);
                                 random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                   envelope_wavenumber = κ0, rng = MersenneTwister(seed)); û)
  û_a = spectral_velocity(11, 2.0)
  û_b = spectral_velocity(22, 3.0)                       # a DIFFERENT stage state
  φ̂ = SD.new_scalar_field_spectral(domain)
  random_scalar_spectral!(φ̂, domain; scalar_variance = 1.0, envelope_wavenumber = 2.0, rng = MersenneTwister(33))

  # fresh physical recoveries — both assemblies CONSUME their velocity/vorticity arguments
  function physical_velocity(û)
    u = SD.new_vector_field_physical(domain)
    to_physical!(u, û, domain.velocity_plans, SD.new_vector_field_spectral(domain))
    return u
  end
  function physical_vorticity(û)
    ω = SD.new_vector_field_physical(domain)
    vorticity_physical!(ω, û, domain, SD.new_vector_field_spectral(domain))
    return ω
  end
  function physical_scalar(φ̂)
    φ = SD.new_scalar_field_physical(domain)
    to_physical!(φ, φ̂, domain.scalar_plans, SD.new_scalar_field_spectral(domain))
    return φ
  end
  generator() = ResolvedGenerator(domain, conditions; scalar = true)
  data(f) = copy(field_data(f))
  reldiff(a, b) = maximum(abs, a .- b) / maximum(abs, b)

  # REFERENCE: the scalar right-hand side at û_b, assembled by a generator whose displaced scratch is
  # stale, so it rebuilds the displaced velocity from û_b itself — the documented fallback path.
  N̂_ref = SD.new_scalar_field_spectral(domain)
  scalar_rhs!(N̂_ref, generator(), û_b, φ̂, physical_velocity(û_b), physical_scalar(φ̂), domain)
  ref = data(N̂_ref)

  # POSITIVE CONTROL: same-stage pairing — the reuse path must be value-identical to the rebuild.
  N̂_ok = SD.new_scalar_field_spectral(domain)
  gen_ok = generator()
  velocity_rhs!(SD.new_vector_field_spectral(domain), gen_ok, û_b, physical_velocity(û_b), physical_vorticity(û_b), domain)
  scalar_rhs!(N̂_ok, gen_ok, û_b, φ̂, physical_velocity(û_b), physical_scalar(φ̂), domain)
  @test reldiff(data(N̂_ok), ref) < 1e-12

  # NON-TRIVIALITY: û_a's scalar right-hand side is genuinely different from û_b's.
  N̂_a = SD.new_scalar_field_spectral(domain)
  scalar_rhs!(N̂_a, generator(), û_a, φ̂, physical_velocity(û_a), physical_scalar(φ̂), domain)
  @test reldiff(data(N̂_a), ref) > 1e-2

  @testset "ONE buffer û, mutated in place between the two verbs" begin
    # The realistic stage pattern: a single resident `state.velocity_spectral` overwritten in place
    # by the integrator's exponential update. Object identity is preserved across the mutation.
    û = SD.new_vector_field_spectral(domain)
    copyto!(field_data(û), field_data(û_a))
    u_a, ω_a = physical_velocity(û), physical_vorticity(û)

    gen = generator()
    velocity_rhs!(SD.new_vector_field_spectral(domain), gen, û, u_a, ω_a, domain)

    copyto!(field_data(û), field_data(û_b))              # in-place stage update: SAME object, new contents
    N̂ = SD.new_scalar_field_spectral(domain)
    scalar_rhs!(N̂, gen, û, φ̂, physical_velocity(û), physical_scalar(φ̂), domain)

    @test reldiff(data(N̂), ref) < 1e-12
  end
end
