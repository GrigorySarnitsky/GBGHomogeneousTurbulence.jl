# Witness: HouLi's non-default `order` / `strength` keywords must actually reach the built kernel.
# The default constructor is the only form the suite exercises; this pins the custom branch of
# `_build_dealias(::HouLi, …)` — the explicit-`strength` arm of the ternary and the `order` exponent.

using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data, materialize_kernel
using Test

@testset "HouLi honours explicit order and strength" begin
  L = 2π
  N = 16
  κ_Ny = (N / 2) * (2π / L)

  kernel_of(strategy) = real.(field_data(materialize_kernel(
    FixedDomain(grid_points_per_axis = N, side_length = L, dealiasing = strategy,
                element_type = Float64, array_type = Array).dealias).field))

  # |κ|² per mode, from the domain's own squared-wavenumber symbol.
  k2 = real.(field_data(materialize_kernel(
    FixedDomain(grid_points_per_axis = N, side_length = L, dealiasing = TwoThirds(),
                element_type = Float64, array_type = Array).squared_wavenumber_kernel).field))

  # keyword constructor stores what it was given
  @test HouLi(order = 4, strength = 2.0).order == 4
  @test HouLi(order = 4, strength = 2.0).strength == 2.0

  g_custom  = kernel_of(HouLi(order = 4, strength = 2.0))
  g_default = kernel_of(HouLi())

  # the exact transfer function exp(-strength·(κ/κ_Ny)^order), evaluated mode by mode
  expected_custom  = @. exp(-2.0 * (sqrt(k2) / κ_Ny)^4)
  expected_default = @. exp(-(-log(eps(Float64))) * (sqrt(k2) / κ_Ny)^36)
  @test g_custom  ≈ expected_custom  rtol = 1e-12
  @test g_default ≈ expected_default rtol = 1e-12

  # the Nyquist mode damps to exp(-strength) — NOT the element-type default ≈ eps(Float64)
  nyquist = findall(x -> isapprox(x, κ_Ny^2; rtol = 1e-12), k2)
  @test !isempty(nyquist)
  @test all(i -> isapprox(g_custom[i], exp(-2.0); rtol = 1e-12), nyquist)
  @test all(i -> isapprox(g_default[i], eps(Float64); rtol = 1e-12), nyquist)

  # a lower order rolls off earlier: strictly less retained at mid-band
  mid = findall(x -> isapprox(x, (κ_Ny / 2)^2; rtol = 1e-12), k2)
  @test !isempty(mid)
  @test all(i -> g_custom[i] < g_default[i], mid)
  @test all(i -> isapprox(g_default[i], 1.0; atol = 1e-9), mid)   # order 36 ⇒ flat at κ_Ny/2
end
