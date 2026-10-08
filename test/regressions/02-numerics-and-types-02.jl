# Witness: derivative_skewness must return the field's own real element type on EVERY branch,
# including the degenerate-strain guard (⟨S:S⟩ ≤ 0), which the existing regression test in
# test/validation.jl never reaches because it only feeds a randomly-seeded (hence ⟨S:S⟩ > 0) field.
using Test
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.SimulationDomain: FixedDomain, TwoThirds,
                                               new_vector_field_spectral
using GBGHomogeneousTurbulence.Observables: derivative_skewness

@testset "derivative_skewness returns the field's element type on the degenerate-strain branch" begin
  for T in (Float32, Float64)
    d = FixedDomain(grid_points_per_axis = 8, side_length = T(2π), element_type = T,
                    array_family = Array, dealiasing = TwoThirds())

    # (1) A freshly allocated velocity field: zero everywhere, so S ≡ 0 and ⟨S:S⟩ = 0.
    û = new_vector_field_spectral(d)
    S_zero = derivative_skewness(û, d)
    @test typeof(S_zero) === T

    # (2) A spatially uniform flow — only the κ = 0 mode is non-zero, so the strain still vanishes
    #     identically. This is a physically reachable state, not merely an unseeded buffer.
    v̂ = new_vector_field_spectral(d)
    v̂[1, 1, 1, 1] = one(eltype(v̂))       # u₁ ≡ const (only the κ = 0 mode), all gradients zero
    S_uniform = derivative_skewness(v̂, d)
    @test typeof(S_uniform) === T
  end
end
