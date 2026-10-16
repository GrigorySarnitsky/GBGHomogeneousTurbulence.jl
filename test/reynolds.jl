# reynolds_box, reynolds_taylor, taylor_microscale and the three Kolmogorov scales — plain functions of
# measured scalars. Each is checked against its definition written out independently, against the
# identities tying them to each other (Re_λ = u′λ/ν, η = u_η τ_η, Re_box = (L/η)^{4/3}), for element
# type, and for its refusals.
using Test
using GBGHomogeneousTurbulence


@testset "the box and Taylor-microscale Reynolds numbers" begin
  ε, k, L, ν = 0.37, 1.5, 2π, 0.011

  # definitions, spelled through the physical scales rather than the closed forms the code uses
  u_box = (ε * L)^(1 / 3)                              # the Kolmogorov velocity of a box-sized eddy
  @test reynolds_box(L, ε, ν) ≈ u_box * L / ν rtol = 1e-14
  u′ = sqrt(2k / 3)
  λ = sqrt(15ν * u′^2 / ε)
  @test reynolds_taylor(k, ε, ν) ≈ u′ * λ / ν rtol = 1e-14

  # Re_λ = k̃ √((20/3) Re_box), with k̃ = k/(εL)^{2/3}
  k̃ = k / (ε * L)^(2 / 3)
  @test reynolds_taylor(k, ε, ν) ≈ k̃ * sqrt(20 / 3 * reynolds_box(L, ε, ν)) rtol = 1e-13
  # Re_box = (L/η)^{4/3}, with η = (ν³/ε)^{1/4} the Kolmogorov length
  η = (ν^3 / ε)^(1 / 4)
  @test reynolds_box(L, ε, ν) ≈ (L / η)^(4 / 3) rtol = 1e-13

  # the arguments' own floating-point type; integers promote to Float64
  @test reynolds_box(Float32(2π), 0.37f0, 0.011f0) isa Float32
  @test reynolds_taylor(1.5f0, 0.37f0, 0.011f0) isa Float32
  @test reynolds_box(1, 1, 1) === 1.0
  @test reynolds_box(L, 0.0, ν) == 0                   # no dissipation, no box-eddy velocity

  # refusals, by name
  @test_throws ArgumentError reynolds_box(L, -ε, ν)
  @test_throws ArgumentError reynolds_box(0, ε, ν)
  @test_throws ArgumentError reynolds_box(L, ε, 0)
  @test_throws ArgumentError reynolds_box(L, Inf, ν)
  @test_throws ArgumentError reynolds_taylor(k, 0, ν)
  @test_throws ArgumentError reynolds_taylor(-k, ε, ν)
  @test_throws ArgumentError reynolds_taylor(k, ε, -ν)
  @test_throws ArgumentError reynolds_taylor(NaN, ε, ν)
end


@testset "the Kolmogorov length" begin
  ε, ν, L = 0.37, 0.011, 2π
  # the definition, written out
  @test kolmogorov_length(ε, ν) ≈ (ν^3 / ε)^(1 / 4) rtol = 1e-14
  # the resolution a run states through it: Re_box = (L/η)^{4/3}, so η = L / Re_box^{3/4}
  @test kolmogorov_length(ε, ν) ≈ L / reynolds_box(L, ε, ν)^(3 / 4) rtol = 1e-13

  # the arguments' own floating-point type; integers promote to Float64
  @test kolmogorov_length(0.37f0, 0.011f0) isa Float32
  @test kolmogorov_length(1, 1) === 1.0

  # refusals, by name
  @test_throws ArgumentError kolmogorov_length(0, ν)
  @test_throws ArgumentError kolmogorov_length(-ε, ν)
  @test_throws ArgumentError kolmogorov_length(ε, 0)
  @test_throws ArgumentError kolmogorov_length(ε, -ν)
  @test_throws ArgumentError kolmogorov_length(Inf, ν)
  @test_throws ArgumentError kolmogorov_length(ε, NaN)
end


@testset "the Taylor microscale" begin
  ε, k, ν = 0.37, 1.5, 0.011
  u′ = sqrt(2k / 3)
  # the definition, written out
  @test taylor_microscale(k, ε, ν) ≈ sqrt(15ν * u′^2 / ε) rtol = 1e-14
  # the Reynolds number it is built into: Re_λ = u′λ/ν
  @test u′ * taylor_microscale(k, ε, ν) / ν ≈ reynolds_taylor(k, ε, ν) rtol = 1e-13
  # a flow with no energy has no Taylor microscale to speak of, and the formula says zero
  @test taylor_microscale(0, ε, ν) == 0

  # the arguments' own floating-point type; integers promote to Float64
  @test taylor_microscale(1.5f0, 0.37f0, 0.011f0) isa Float32
  @test taylor_microscale(1, 1, 1) === sqrt(10.0)

  # refusals, by name
  @test_throws ArgumentError taylor_microscale(-k, ε, ν)
  @test_throws ArgumentError taylor_microscale(NaN, ε, ν)
  @test_throws ArgumentError taylor_microscale(k, 0, ν)
  @test_throws ArgumentError taylor_microscale(k, -ε, ν)
  @test_throws ArgumentError taylor_microscale(k, Inf, ν)
  @test_throws ArgumentError taylor_microscale(k, ε, 0)
  @test_throws ArgumentError taylor_microscale(k, ε, -ν)
  @test_throws ArgumentError taylor_microscale(k, ε, NaN)
end


@testset "the Kolmogorov time and velocity" begin
  ε, ν = 0.37, 0.011
  # the definitions, written out
  @test kolmogorov_time(ε, ν) ≈ sqrt(ν / ε) rtol = 1e-14
  @test kolmogorov_velocity(ε, ν) ≈ (ε * ν)^(1 / 4) rtol = 1e-14
  # the three Kolmogorov scales are one set: η = u_η τ_η, and the eddy of size η has Reynolds number one
  @test kolmogorov_velocity(ε, ν) * kolmogorov_time(ε, ν) ≈ kolmogorov_length(ε, ν) rtol = 1e-13
  @test kolmogorov_velocity(ε, ν) * kolmogorov_length(ε, ν) / ν ≈ 1 rtol = 1e-13
  # the strain rate the time scale inverts: ⟨S:S⟩ = ε/(2ν) = 1/(2τ_η²)
  @test 1 / (2 * kolmogorov_time(ε, ν)^2) ≈ ε / (2ν) rtol = 1e-13

  # the arguments' own floating-point type; integers promote to Float64
  @test kolmogorov_time(0.37f0, 0.011f0) isa Float32
  @test kolmogorov_velocity(0.37f0, 0.011f0) isa Float32
  @test kolmogorov_time(1, 1) === 1.0
  @test kolmogorov_velocity(1, 1) === 1.0

  # refusals, by name — the same inputs `kolmogorov_length` refuses, the three scales being one set
  for f in (kolmogorov_time, kolmogorov_velocity)
    @test_throws ArgumentError f(0, ν)
    @test_throws ArgumentError f(-ε, ν)
    @test_throws ArgumentError f(Inf, ν)
    @test_throws ArgumentError f(ε, 0)
    @test_throws ArgumentError f(ε, -ν)
    @test_throws ArgumentError f(ε, NaN)
  end
end
