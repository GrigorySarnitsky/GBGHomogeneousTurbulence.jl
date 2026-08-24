# Architecture witness 02 — State.jl re-spells Observables' canonical kinetic-energy and
# scalar-variance formulas as bare literals (State.jl:137, :207 vs Observables.jl:68, :195).
#
# An architecture finding has no failing program by nature; what IS runnable is the claim that the
# two spellings agree. They do not: the velocity copy `0.5 * inner(û, û)` promotes a Float32 field's
# energy to Float64 (the literal `0.5` is Float64), where the canonical `inner(u, u) / 2` keeps
# Float32 — a divergence that already exists between the two copies, before any future edit.
using Test, Random, GBGIsotropicTurbulence
using GBGPeriodicFields: inner

@testset "State.jl's seeding rescale agrees with the canonical Observables formulas" begin
  for T in (Float32, Float64)
    d = FixedDomain(grid_points_per_axis = 16, side_length = T(2π), element_type = T,
                    array_type = Array, dealiasing = TwoThirds())
    û = new_vector_field_spectral(d)
    random_solenoidal_velocity_spectral!(û, d; kinetic_energy = T(0.5), envelope_wavenumber = T(2),
                                         rng = MersenneTwister(1))
    φ̂ = new_scalar_field_spectral(d)
    random_scalar_spectral!(φ̂, d; scalar_variance = T(1), envelope_wavenumber = T(2),
                            rng = MersenneTwister(2))

    # (1) The seeded field must hold what the caller asked for, measured by the CANONICAL function —
    #     the property the derived-viscosity calibration in SimulationRun assumes. No test in the
    #     suite pins this today; it is what a divergence between the two copies would break.
    @test kinetic_energy(û)  ≈ T(0.5)
    @test scalar_variance(φ̂) ≈ T(1)

    # (2) CORRECTED 2026-08-20. As written, this asserted
    #       typeof(0.5 * inner(û, û)) === typeof(kinetic_energy(û))
    #     which is evaluated HERE, not in State.jl: `0.5` is a Float64 literal, so at T = Float32 the
    #     left side is Float64 and the assertion demanded that `kinetic_energy` PROMOTE — the exact
    #     opposite of the element-type contract, and unpassable unless the code were wrong. The
    #     divergence it was reaching for was real (State.jl carried `0.5 * inner(û, û)` while
    #     Observables carried `inner(u, u) / 2`), and the fix removed the duplication at its root by
    #     reordering the includes so the seeders CALL the canonical reductions. What remains testable
    #     is that the canonical spelling is the type-preserving one, in both element types.
    @test typeof(inner(φ̂, φ̂))     === typeof(scalar_variance(φ̂))
    @test typeof(inner(û, û) / 2) === typeof(kinetic_energy(û))
  end
end
