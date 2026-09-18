# Witness r4-test-critic-04 — AdamsBashforth's order bounds are enforced at both ends.
#
# Claim under test: `AdamsBashforth(; order)` rejects `order < 1` and `order > 8`, the ceiling
# guarding the four-point Gauss–Legendre rule that integrates the interpolation weights
# (exact only through degree 7, i.e. through `order = 8`), and nothing in the suite pins either
# bound, so a regression that widened or dropped one would pass unnoticed.
#
# This file asserts the CORRECT behaviour: both bounds throw, order 8 is accepted, and the
# quadrature really does go inexact one step above the ceiling (so the ceiling sits where the
# numerics put it, not one off).

using Test
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Particles: AdamsBashforth
const AB = GBGHomogeneousTurbulence.Particles

# Exact Adams–Bashforth weights in rational arithmetic, on the same node layout the scheme uses:
# τ_j = -(j-1) (unit steps going backwards), b_j = ∫_0^1 L_j(t) dt.
function exact_weights(τ::Vector{Rational{BigInt}})
  k = length(τ)
  b = Vector{Rational{BigInt}}(undef, k)
  for j in 1:k
    p = Rational{BigInt}[1]                              # numerator polynomial, ascending powers
    for m in 1:k
      m == j && continue
      q = zeros(Rational{BigInt}, length(p) + 1)         # multiply by (t - τ[m])
      for (i, c) in enumerate(p)
        q[i]     += -τ[m] * c
        q[i + 1] += c
      end
      p = q
    end
    denom = prod(τ[j] - τ[m] for m in 1:k if m != j; init = Rational{BigInt}(1))
    b[j] = sum(c // i for (i, c) in enumerate(p)) / denom
  end
  return b
end

weights_at(k) = AB._adams_bashforth_weights(zeros(Float64, k), zeros(Float64, k), 1.0,
                                            ones(Float64, max(k - 1, 1)), k)

quad_error(k) = maximum(abs.(weights_at(k) .-
                             Float64.(exact_weights(Rational{BigInt}[-(j - 1) for j in 1:k]))))

@testset "AdamsBashforth enforces both ends of its documented order range" begin
  # ---- the floor -----------------------------------------------------------------------------
  @test_throws ArgumentError AdamsBashforth(order = 0)
  @test_throws ArgumentError AdamsBashforth(order = -1)

  # ---- the ceiling, pinned at the exact boundary rather than an off-by-one guess ---------------
  @test AdamsBashforth(order = 8) isa AdamsBashforth{8}
  @test_throws ArgumentError AdamsBashforth(order = 9)

  # ---- and the ceiling is where the quadrature puts it ----------------------------------------
  # Four-point Gauss–Legendre is exact through degree 7, i.e. through order 8; one order higher the
  # weights are inexact. Called below the constructor on purpose: this is the hazard the ceiling
  # exists to prevent. Measured 2026-08-21: 1.7e-16 at k = 8, 3.94e-8 at k = 9 — the latter is
  # comfortably above the 1e-10 tolerance `test/regressions/01-numerics-and-types-01.jl` holds every
  # accepted order to, so a regression that WIDENED the ceiling would already fail that test.
  @test quad_error(8) < 1e-10
  @test quad_error(9) > 1e-10
end
