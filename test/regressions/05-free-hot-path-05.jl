# Witness: `_scalar_flux_divergence!`'s `α` must scale the result on BOTH branches of `kernel`.
#
# The helper's signature offers `kernel = nothing, α = 1` as two independent defaults, and `α` is
# the sign that turns the flux divergence ∇·(uφ) into the advection term −∇·(uφ). On the
# kernel-composed branch α reaches PF's six-argument `divergence!`; on the `kernel === nothing`
# branch PF's three-argument `divergence!` takes no weights, so α is accepted and discarded.

using Test
using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Generator: _scalar_flux_divergence!
using GBGPeriodicFields: field_data
using Random


@testset "_scalar_flux_divergence! honours α on the kernel === nothing branch" begin
  N = 8
  domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_type = Array)

  # A fixed physical velocity and scalar; the velocity is CONSUMED by the flux, so rebuild it.
  rng = MersenneTwister(11)
  u_reference = rand(rng, Float64, N, N, N, 3)
  φ_values    = rand(rng, Float64, N, N, N)

  φ = new_scalar_field_physical(domain)
  copyto!(field_data(φ), φ_values)

  function flux_divergence(kernel, α)
    u = new_vector_field_physical(domain)
    copyto!(field_data(u), u_reference)
    scratch = new_vector_field_spectral(domain)
    out = new_scalar_field_spectral(domain)
    _scalar_flux_divergence!(out, u, φ, domain, scratch, kernel, α)
    return copy(field_data(out))
  end

  # Positive control: on the kernel-composed branch α = −1 negates the result, which is exactly
  # how the two in-tree callers obtain the advection term's sign.
  # `sign_error` is 0 when α = −1 negated the result and 2 when α was ignored entirely.
  sign_error(kernel) = (plus = flux_divergence(kernel, 1); minus = flux_divergence(kernel, -1);
                        maximum(abs, minus .+ plus) / maximum(abs, plus))

  # Positive control: on the kernel-composed branch α = −1 negates the result, which is exactly
  # how the two in-tree callers obtain the advection term's sign.
  @test sign_error(domain.dealias) < 1e-12

  # The claim under test: the same α must act on the undealiased branch.
  @test sign_error(nothing) < 1e-12
end
