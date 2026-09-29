# reynolds_box and reynolds_taylor — plain functions of three measured scalars. Each is checked against
# its definition written out independently, against the identities tying them to the kinetic energy in
# box units and to the Kolmogorov length, for element type, and for its refusals.
using Test
using GBGHomogeneousTurbulence


@testset "the box and Taylor-microscale Reynolds numbers" begin
  ε, k, L, ν = 0.37, 1.5, 2π, 0.011

  # definitions, spelled through the physical scales rather than the closed forms the code uses
  u_box = (ε * L)^(1 / 3)                              # the Kolmogorov velocity of a box-sized eddy
  @test reynolds_box(ε, L, ν) ≈ u_box * L / ν rtol = 1e-14
  u′ = sqrt(2k / 3)
  λ = sqrt(15ν * u′^2 / ε)
  @test reynolds_taylor(ε, k, ν) ≈ u′ * λ / ν rtol = 1e-14

  # Re_λ = k̃ √((20/3) Re_box), with k̃ = k/(εL)^{2/3}
  k̃ = k / (ε * L)^(2 / 3)
  @test reynolds_taylor(ε, k, ν) ≈ k̃ * sqrt(20 / 3 * reynolds_box(ε, L, ν)) rtol = 1e-13
  # Re_box = (L/η)^{4/3}, with η = (ν³/ε)^{1/4} the Kolmogorov length
  η = (ν^3 / ε)^(1 / 4)
  @test reynolds_box(ε, L, ν) ≈ (L / η)^(4 / 3) rtol = 1e-13

  # the arguments' own floating-point type; integers promote to Float64
  @test reynolds_box(0.37f0, Float32(2π), 0.011f0) isa Float32
  @test reynolds_taylor(0.37f0, 1.5f0, 0.011f0) isa Float32
  @test reynolds_box(1, 1, 1) === 1.0
  @test reynolds_box(0.0, L, ν) == 0                   # no dissipation, no box-eddy velocity

  # refusals, by name
  @test_throws ArgumentError reynolds_box(-ε, L, ν)
  @test_throws ArgumentError reynolds_box(ε, 0, ν)
  @test_throws ArgumentError reynolds_box(ε, L, 0)
  @test_throws ArgumentError reynolds_box(Inf, L, ν)
  @test_throws ArgumentError reynolds_taylor(0, k, ν)
  @test_throws ArgumentError reynolds_taylor(ε, -k, ν)
  @test_throws ArgumentError reynolds_taylor(ε, k, -ν)
  @test_throws ArgumentError reynolds_taylor(ε, NaN, ν)
end
