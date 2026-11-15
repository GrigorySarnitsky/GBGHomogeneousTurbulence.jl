# Witness r4-test-critic-04 — the particle schemes' step counts are bounded at both ends.
#
# Claim under test: `AB(k)` rejects `k < 1` and `k > 8`, and `ABM(k)` rejects `k < 1` and `k > 7`,
# the ceilings guarding the four-point Gauss–Legendre rule that integrates the weights (exact only
# through degree 7, i.e. through eight nodes: the eight samples of `AB(8)`, or the seven samples and
# the step's end of `ABM(7)`), and nothing in the suite pinned either bound, so a regression that
# widened or dropped one would pass unnoticed.
#
# This file asserts the CORRECT behaviour: both bounds throw, the last admitted count is accepted,
# and the quadrature really does go inexact one node above the ceiling (so the ceiling sits where
# the numerics put it, not one off).

using Test
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.ParticlePropagator: _adams_weights

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

# The largest error of the package's weights on `n` nodes: the samples at 0, −1, …, with the step's
# end at +1 leading when `with_step_end`.
function quad_error(n; with_step_end::Bool = false)
  nodes = with_step_end ? Rational{BigInt}[2 - j for j in 1:n] : Rational{BigInt}[-(j - 1) for j in 1:n]
  got = collect(_adams_weights(Tuple(Float64.(nodes)), 1.0))
  return maximum(abs.(got .- Float64.(exact_weights(nodes))))
end

@testset "AB and ABM enforce both ends of their documented ranges" begin
  # ---- the floor -----------------------------------------------------------------------------
  @test_throws ArgumentError AB(0)
  @test_throws ArgumentError AB(-1)
  @test_throws ArgumentError ABM(0)

  # ---- the ceiling, pinned at the exact boundary rather than an off-by-one guess ---------------
  @test AB(8) isa AB{8}
  @test_throws ArgumentError AB(9)
  @test ABM(7) isa ABM{7}
  @test_throws ArgumentError ABM(8)
  # The parametric form is no way round it.
  @test_throws ArgumentError AB{9}()
  @test_throws ArgumentError ABM{8}()

  # ---- and the ceiling is where the quadrature puts it ----------------------------------------
  # Four-point Gauss–Legendre is exact through degree 7, i.e. through eight nodes; one node more and
  # the weights are inexact. Called below the constructors on purpose: this is the hazard the
  # ceilings exist to prevent. Measured 2026-08-21 on the samples alone: 1.7e-16 at eight nodes,
  # 3.94e-8 at nine — the latter comfortably above the 1e-10 tolerance
  # `test/regressions/01-numerics-and-types-01.jl` holds every accepted count to, so a regression that
  # WIDENED a ceiling would already fail that test.
  @test quad_error(8) < 1e-10
  @test quad_error(9) > 1e-10
  @test quad_error(8; with_step_end = true) < 1e-10      # ABM(7): seven samples and the step's end
  @test quad_error(9; with_step_end = true) > 1e-10      # ABM(8) would be here
end
