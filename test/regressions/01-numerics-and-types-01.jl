# Witness: the Adams weights must integrate the Lagrange basis EXACTLY for every number of steps
# the scheme constructors accept.
#
# The weights are w_j = ∫_{t_n}^{t_n+h} L_j(t) dt with L_j the Lagrange basis on the nodes: the k
# sample times for Adams–Bashforth, and those with the step's end for Adams–Moulton. `_adams_weights`
# evaluates that integral with a FIXED 4-node Gauss–Legendre rule, which is exact only for
# integrands of degree ≤ 2·4−1 = 7, i.e. at most 8 nodes: `AB(k)` to k = 8, `ABM(k)` to k = 7.
#
# Here the same integrals are computed independently and EXACTLY, in Rational{BigInt}: for uniform
# unit steps the nodes are the integers 1, 0, −1, …, so each L_j has exact rational
# coefficients and ∫_0^1 L_j is an exact rational number. No quadrature is involved on this side.

using Test, GBGHomogeneousTurbulence

using GBGHomogeneousTurbulence.ParticlePropagator: _adams_weights

"Exact ∫_0^1 L_j(t) dt for the Lagrange basis on nodes τ, in exact rational arithmetic."
function exact_weights(τ::Vector{Rational{BigInt}})
  k = length(τ)
  b = Vector{Rational{BigInt}}(undef, k)
  for j in 1:k
    # coefficients of ∏_{m≠j} (t − τ_m), ascending powers
    p = Rational{BigInt}[1]
    for m in 1:k
      m == j && continue
      q = zeros(Rational{BigInt}, length(p) + 1)
      for (i, c) in enumerate(p)
        q[i]   += -τ[m] * c        # constant part of (t − τ_m)
        q[i+1] +=  c               # t part
      end
      p = q
    end
    denom = prod(τ[j] - τ[m] for m in 1:k if m != j; init = Rational{BigInt}(1))
    # ∫_0^1 Σ c_i t^{i-1} dt = Σ c_i / i
    b[j] = sum(c // i for (i, c) in enumerate(p)) / denom
  end
  return b
end

accepted(construct, k) = try construct(k); true catch; false end

@testset "the Adams weights are exact for every number of steps the constructors accept" begin
  for k in 1:12
    past = Rational{BigInt}[-(j - 1) for j in 1:k]       # uniform unit steps, going backwards
    if accepted(AB, k)                                    # a number of steps the scheme rejects owes nothing
      got = collect(_adams_weights(Tuple(Float64.(past)), 1.0))
      @test maximum(abs.(got .- Float64.(exact_weights(past)))) < 1e-10
    end
    if accepted(ABM, k)                                   # the corrector: the step's end among the nodes
      nodes = vcat(Rational{BigInt}(1), past)
      got = collect(_adams_weights(Tuple(Float64.(nodes)), 1.0))
      @test maximum(abs.(got .- Float64.(exact_weights(nodes)))) < 1e-10
    end
  end
  # The constructors stop exactly where the quadrature does: eight nodes.
  @test accepted(AB, 8) && !accepted(AB, 9)
  @test accepted(ABM, 7) && !accepted(ABM, 8)
end
