# Witness: integral_scale on an energy-free velocity field silently returns NaN.
#
# The correct behaviour, by the two precedents this package already sets for the same failure
# mode — a diagnostic whose denominator degenerates:
#   * Observables.derivative_skewness guards it (`ss <= 0 && return zero(ss)`), and
#   * State.random_solenoidal_velocity_spectral! throws a descriptive ArgumentError
#     ("the seeded velocity has no energy to rescale: …") rather than handing back a
#     silently-degenerate result.
# Either resolution is acceptable; a silent NaN is not. The test below therefore passes if
# integral_scale returns a finite number OR throws, and fails only on the silent NaN.

using Test, GBGHomogeneousTurbulence

const DOMAIN = FixedDomain(grid_points_per_axis = 16, side_length = 2π,
                           dealiasing = TwoThirds(), element_type = Float64,
                           array_type = Array)

# The outcome of a call, without letting a (legitimate) throw abort the testset.
attempt(f) = try
  f()
catch err
  err
end

@testset "integral_scale guards its degenerate denominator" begin

@testset "integral_scale does not silently return NaN for an energy-free velocity field" begin
  û = new_vector_field_spectral(DOMAIN)          # freshly allocated: all modes exactly zero

  # The premise: the spectrum really is exactly zero, not round-off noise.
  κ, E = energy_spectrum(û, DOMAIN)
  @test sum(E) == 0.0
  @test kinetic_energy(û) == 0.0

  # The claim under test.
  L = attempt(() -> integral_scale(û, DOMAIN))
  @test !(L isa AbstractFloat && isnan(L))

  # Control: the sibling reduction with the same degenerate denominator resolves cleanly.
  @test derivative_skewness(û, DOMAIN) === 0.0
end


@testset "the public run layer cannot reach the NaN at all" begin
  # UPDATED 2026-08-21. As written, this reached the NaN by constructing a run with
  # `kinetic_energy = 0.0` — a route a SECOND fix from the same round has since closed at the front
  # door, so the constructor now throws and this block errored rather than passing. The defect it was
  # written for is fixed and pinned by the assertions above (`integral_scale` refuses an energy-free
  # field instead of returning NaN); what is testable here now is that the route is refused, which is
  # a stronger guarantee than the one originally asserted — the state can no longer be built.
  @test_throws ArgumentError Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                                        kinetic_energy = 0.0)
  @test_throws ArgumentError Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                                        kinetic_energy = -1.0)
end

end  # outer testset
