# Witness: under PhaseShift, `scalar_rhs!` must assemble the scalar flux from the displaced velocity
# of the û IT WAS HANDED. The generator's `displaced_velocity_fresh` Bool records only "velocity_rhs!
# ran since the last scalar consumption", never WHICH û it ran with, so a caller that pairs the two
# verbs at different stage states silently gets the earlier stage's displaced velocity.

using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data, to_physical!
using Random
using Test

const SD = GBGIsotropicTurbulence.SimulationDomain

@testset "scalar_rhs! uses the displaced velocity of the û it was given, not the û velocity_rhs! last saw" begin
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
  # relative discrepancy against the reference right-hand side, so a failure prints one number
  reldiff(a, b) = maximum(abs, a .- b) / maximum(abs, b)

  # REFERENCE: the scalar right-hand side at û_b, assembled by a generator whose displaced scratch is
  # stale, so it rebuilds the displaced velocity from û_b itself — the documented fallback path.
  N̂_ref = SD.new_scalar_field_spectral(domain)
  scalar_rhs!(N̂_ref, generator(), û_b, φ̂, physical_velocity(û_b), physical_scalar(φ̂), domain)
  ref = data(N̂_ref)

  # POSITIVE CONTROL: the same-stage pairing the in-tree schemes use — reuse must be value-identical.
  N̂_ok = SD.new_scalar_field_spectral(domain)
  gen_ok = generator()
  velocity_rhs!(SD.new_vector_field_spectral(domain), gen_ok, û_b, physical_velocity(û_b), physical_vorticity(û_b), domain)
  scalar_rhs!(N̂_ok, gen_ok, û_b, φ̂, physical_velocity(û_b), physical_scalar(φ̂), domain)
  @test reldiff(data(N̂_ok), ref) < 1e-12

  # NON-TRIVIALITY: û_a's scalar right-hand side is genuinely different from û_b's.
  N̂_a = SD.new_scalar_field_spectral(domain)
  scalar_rhs!(N̂_a, generator(), û_a, φ̂, physical_velocity(û_a), physical_scalar(φ̂), domain)
  @test reldiff(data(N̂_a), ref) > 1e-2

  @testset "mismatched pairing: velocity_rhs! at û_a, then scalar_rhs! at û_b" begin
    gen = generator()
    velocity_rhs!(SD.new_vector_field_spectral(domain), gen, û_a, physical_velocity(û_a), physical_vorticity(û_a), domain)
    N̂ = SD.new_scalar_field_spectral(domain)
    scalar_rhs!(N̂, gen, û_b, φ̂, physical_velocity(û_b), physical_scalar(φ̂), domain)
    @test reldiff(data(N̂), ref) < 1e-12
  end

  @testset "scalar-before-velocity stage order: stage 2's scalar_rhs! at û_b inherits stage 1's flag" begin
    # A scheme that assembles the scalar first at each stage. Stage 1 at û_a: scalar_rhs! (rebuilds,
    # clears the flag), then velocity_rhs! (sets it). Stage 2 at û_b: scalar_rhs! finds the flag set
    # by STAGE 1's velocity_rhs! and reuses û_a's displaced velocity.
    gen = generator()
    scalar_rhs!(SD.new_scalar_field_spectral(domain), gen, û_a, φ̂, physical_velocity(û_a), physical_scalar(φ̂), domain)
    velocity_rhs!(SD.new_vector_field_spectral(domain), gen, û_a, physical_velocity(û_a), physical_vorticity(û_a), domain)
    N̂ = SD.new_scalar_field_spectral(domain)
    scalar_rhs!(N̂, gen, û_b, φ̂, physical_velocity(û_b), physical_scalar(φ̂), domain)
    @test reldiff(data(N̂), ref) < 1e-12
  end
end
