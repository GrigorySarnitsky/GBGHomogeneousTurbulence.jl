# Witness: `integral_scale`'s emptiness guard tests the wrong sum.
#
# `integral_scale` computes L₁₁ = (3π/4)·Σ(Eₙ/κₙ)/ΣEₙ, where the numerator deliberately drops the
# κ = 0 shell (`k > 0 ? e/k : zero(e)`) while the denominator `total = sum(E)` keeps it. The guard
#
#     total > 0 || throw(ArgumentError("this velocity field carries no energy, …"))
#
# therefore passes for a field whose energy sits entirely in the κ = 0 shell — a uniform mean flow —
# and the function returns exactly 0.0.
#
# Zero is not a length, and it is not even the limit: a uniform flow has R₁₁(r) = u₀² for every r,
# so ∫₀^∞ R₁₁ dr diverges and L₁₁ → ∞. The returned 0.0 is the same silent-degenerate-value failure
# the guard exists to prevent (its own comment: "0/0 would hand back a silent NaN that then
# propagates into every derived quantity — a Reynolds number, a turnover time"), reached through the
# other summand: `flow_parameters` reports integral_scale = 0.0, and a `Phenomenology` law
# normalised on L₁₁ then evaluates at κL = 0.
#
# The correct behaviour is fix-agnostic and is what is asserted below: L₁₁ must never be handed back
# as zero. Excluding κ = 0 from BOTH sums satisfies every assertion here — the mean-flow-only field
# then degenerates honestly (0/0) and hits the existing throw, and the mixed field below stops being
# rescaled by energy the numerator never saw.

using Test, GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data

const N = 8
const DOMAIN = FixedDomain(grid_points_per_axis = N, side_length = 2π,
                           dealiasing = TwoThirds(), element_type = Float64,
                           array_type = Array)

# The outcome of a call, without letting a (legitimate) throw abort the testset.
attempt(f) = try
  f()
catch err
  err
end

# A length a diagnostic may legitimately hand back is strictly positive (Inf allowed — a uniform flow
# really is infinitely correlated). Refusing outright is an equally acceptable resolution, so a thrown
# error is mapped to a passing value; 0.0 and NaN are what must not come back.
reported_length(L) = L isa Exception ? Inf : L

# u(x) = (1, 0, 0): all the energy in the κ = 0 mode of the first component.
function mean_flow_spectral(amplitude = 1.0)
  û = new_vector_field_spectral(DOMAIN)
  field_data(û)[1, 1, 1, 1] = amplitude * N^3
  return û
end


@testset "integral_scale guards the sum it actually divides by" begin

@testset "a uniform mean flow does not get L₁₁ = 0" begin
  û = mean_flow_spectral()

  # The premise: this really is a uniform flow of unit speed — energy present, no gradients.
  @test kinetic_energy(û) ≈ 0.5
  @test dissipation(û, DOMAIN, 1.0) == 0.0
  κ, E = energy_spectrum(û, DOMAIN)
  @test κ[1] == 0.0
  @test E[1] ≈ 0.5             # every joule sits in the κ = 0 shell …
  @test sum(E[2:end]) == 0.0   # … and nowhere else.

  # The claim under test: the guard is passed (total = 0.5 > 0) and a zero length comes back.
  @test reported_length(attempt(() -> integral_scale(û, DOMAIN))) > 0
end


@testset "adding a uniform mean flow cannot shorten L₁₁" begin
  # A solenoidal single-mode field at κ = 1: u = (0, sin(x), 0), the turbulent part.
  turbulent = new_vector_field_spectral(DOMAIN)
  field_data(turbulent)[2, 1, 1, 2] = -0.5im * N^3   # κ_x = 1, second component
  L_turbulent = integral_scale(turbulent, DOMAIN)
  @test L_turbulent > 0                              # the healthy reference value

  # The same field riding on a uniform mean flow. The mean flow contributes a constant u₀² to
  # R₁₁(r) at every separation, so it can only lengthen the correlation — never shorten it.
  mixed = mean_flow_spectral(10.0)
  field_data(mixed) .+= field_data(turbulent)
  @test kinetic_energy(mixed) > kinetic_energy(turbulent)

  @test integral_scale(mixed, DOMAIN) >= L_turbulent
end


@testset "control: the existing guard still fires on a field with no energy at all" begin
  @test_throws ArgumentError integral_scale(new_vector_field_spectral(DOMAIN), DOMAIN)
end

end  # outer testset
