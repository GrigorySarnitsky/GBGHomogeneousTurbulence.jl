# Architecture witness (diff check, not a failing test): the derived-viscosity Simulation constructor
# once spelled Re_λ inline, a second copy of the formula the package already owned. The constructor
# now calls `reynolds_taylor`; this script keeps the inline spelling as the independent reference and
# demonstrates the owned function reproduces it, so a drift in the owned formula is caught here.
using Test
using GBGHomogeneousTurbulence

inline_reλ(k, ε, ν) = (2 * k / 3) * sqrt(15 / (ε * ν))          # the constructor's former inline copy

@testset "`reynolds_taylor` reproduces the constructor's former inline Re_λ" begin
  for (k, ε, ν) in ((1.5, 1.0, 1e-3), (0.75, 0.3, 5e-4), (3.0, 2.2, 2e-2))
    @test reynolds_taylor(k, ε, ν) ≈ inline_reλ(k, ε, ν)
    println("k=$k ε=$ε ν=$ν :  reynolds_taylor=", reynolds_taylor(k, ε, ν),
            "   inline=", inline_reλ(k, ε, ν))
  end
end
