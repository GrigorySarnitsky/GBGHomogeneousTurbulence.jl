# Dismissal-audit catch (2026-08-23, overturning a round-2 triage): the bare-positivity
# empty-band guard readmitted the unbounded kick its docstrings still promised away. A band
# emptied by a mask or a rescale retains roundoff-level content — positive, so it passed the
# guard — and A = rate/(2·k_band) then overflows the field in one stage (A ~ 1e58 measured from a
# subtracted band). The floor is back as a RELATIVE one (10·eps of the whole-field observable),
# riding the same fused traversal, so it is scale-invariant (the round-4 concern that removed the
# absolute floor) and costs no extra crossing.
using Test, GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Forcing: add_forcing_source!
using GBGPeriodicFields: field_data, convolve!, weighted_inner, l2norm, to_physical, to_spectral
using Random


@testset "an emptied band takes no kick; a genuinely weak band still forces, at any scale" begin
  domain = FixedDomain(grid_points_per_axis = 16, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_type = Array)
  forcing = ConstantPower(domain; injection_rate = 0.1)
  û = new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                       envelope_wavenumber = 2.0, rng = MersenneTwister(5))

  # Empty the forced band by SUBTRACTION, then round-trip through physical representation — the
  # reachable route (a mask, a rescale, any physical-space processing): the subtraction alone is
  # exact (x − x = 0), but the transform pair repopulates the emptied shells at roundoff, and
  # roundoff is POSITIVE — precisely the content the bare positivity guard mistook for a band.
  convolve!(û, û, forcing.band, -1.0, 1.0)
  u = to_physical(û, domain.transform_plans)
  field_data(û) .= field_data(to_spectral(u, domain.transform_plans))
  band_left = weighted_inner(û, forcing.band)
  @test 0 < band_left < 1e-25                        # roundoff, and positive: the old guard's hole

  N̂ = new_vector_field_spectral(domain); fill!(field_data(N̂), 0)
  add_forcing_source!(forcing, nothing, N̂, û, domain, 0.05)
  @test all(iszero, field_data(N̂))                   # no kick: the relative floor names it empty

  # A genuinely weak band still forces — and the decision is invariant under a uniform rescale.
  û2 = new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û2, domain; kinetic_energy = 0.5,
                                       envelope_wavenumber = 2.0, rng = MersenneTwister(6))
  for scale in (1.0, 1e-6)
    ûs = new_vector_field_spectral(domain)
    field_data(ûs) .= scale .* field_data(û2)
    N̂s = new_vector_field_spectral(domain); fill!(field_data(N̂s), 0)
    add_forcing_source!(forcing, nothing, N̂s, ûs, domain, 0.05)
    @test l2norm(N̂s) > 0                             # forced at unit scale AND at 1e-6 scale
    @test all(isfinite, field_data(N̂s))
  end
end
