# Witness: Adams–Bashforth extrapolation weights must integrate the Lagrange basis EXACTLY
# for every `order` the constructor accepts.
#
# The weights are b_j = ∫_{t_n}^{t_n+h} L_j(t) dt with L_j the degree-(k-1) Lagrange basis on the
# k sample times. `_adams_bashforth_weights` evaluates that integral with a FIXED 4-node
# Gauss–Legendre rule, which is exact only for integrands of degree ≤ 2·4−1 = 7, i.e. k ≤ 8.
#
# Here the same integrals are computed independently and EXACTLY, in Rational{BigInt}: for uniform
# unit steps the nodes are the integers 0, −1, …, −(k−1), so each L_j has exact rational
# coefficients and ∫_0^1 L_j is an exact rational number. No quadrature is involved on this side.

using Test, GBGIsotropicTurbulence

const AB = GBGIsotropicTurbulence.Particles

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

@testset "AdamsBashforth weights are exact for every order the constructor accepts" begin
  for k in 1:12
    # Does the public constructor accept this order at all?
    accepted = try
      AdamsBashforth(order = k)
      true
    catch
      false
    end
    accepted || continue                     # an order the scheme rejects owes nothing

    τ = Rational{BigInt}[-(j - 1) for j in 1:k]          # uniform unit steps, going backwards
    want = Float64.(exact_weights(τ))
    got  = AB._adams_bashforth_weights(zeros(Float64, k), zeros(Float64, k), 1.0,
                                       ones(Float64, max(k - 1, 1)), k)

    err = maximum(abs.(got .- want))
    @test err < 1e-10
  end
end
