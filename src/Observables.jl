# Observables — the functions of the flow state that are measured: kinetic energy, dissipation, the
# velocity-derivative skewness, the scalar variance and its dissipation, and the maximum component
# speed (which feeds the CFL). In the Mori–Zwanzig reading (ARCHITECTURE §8) these are the observables
# of the `Generator`: their plateaus gate warm-up and their statistics are to be tracked by
# GBGStreamingStatistics. Each reduces a field to a scalar — a GBGPeriodicFields inner product or moment.

"""
    Observables

The measured functions of the flow state:
- [`kinetic_energy`](@ref), [`scalar_variance`](@ref) — the turbulent kinetic energy and the scalar
  variance.
- [`dissipation`](@ref), [`scalar_dissipation`](@ref) — their dissipation rates.
- [`derivative_skewness`](@ref) — the velocity-derivative skewness, the K41 marker of developed
  turbulence.
- [`max_speed`](@ref) — the maximum velocity component, which sets the advective-CFL step.
- [`energy_spectrum`](@ref), [`integral_scale`](@ref) — the measured energy spectrum and the integral
  length scale derived from it.

Their plateaus gate warm-up (`warmup!`). Each reduces a field to a scalar (the energy spectrum, to a
distribution over wavenumber); none de-aliases first — a reduction is Parseval-exact and the run keeps
the field de-aliased, so a reduction in physical representation is exact too.
"""
module Observables

using GBGPeriodicFields
using ..SimulationDomain: FixedDomain, tensor_physical, scalar_physical

export kinetic_energy, dissipation, max_speed,
       scalar_variance, scalar_dissipation, derivative_skewness,
       energy_spectrum, integral_scale


"""
    kinetic_energy(u)

The turbulent kinetic energy ``\\tfrac12\\langle\\lvert\\boldsymbol{u}\\rvert^{2}\\rangle`` of the
velocity field `u`. Computed as ``\\tfrac12\\,\\langle\\boldsymbol{u},\\boldsymbol{u}\\rangle`` with
the normalized inner product, so by Parseval's theorem it accepts `u` in either
representation.
"""
kinetic_energy(u) = 0.5 * inner(u, u)


"""
    dissipation(ω, viscosity)

The mean kinetic-energy dissipation rate of a homogeneous flow,
``\\varepsilon = \\nu\\,\\langle\\lvert\\boldsymbol{\\omega}\\rvert^{2}\\rangle``, from the physical
`ω` ``\\boldsymbol{\\omega}`` and the kinematic `viscosity` ``\\nu`` (the homogeneous
identity ``\\varepsilon = 2\\nu\\langle S_{ij}S_{ij}\\rangle = \\nu\\langle\\lvert\\boldsymbol{\\omega}\\rvert^{2}\\rangle``,
with the strain-rate tensor ``S_{ij} = \\tfrac12(\\partial_{x_j}u_i + \\partial_{x_i}u_j)``).
"""
dissipation(ω, viscosity::Real) = viscosity * inner(ω, ω)


"""
    max_speed(u)

The largest velocity component in absolute value, ``\\max_i\\lvert u_i\\rvert`` — an allocation-free
reduction used to set the advective CFL timestep. It differs from the true ``\\sup\\lvert\\boldsymbol{u}\\rvert``
by at most ``\\sqrt{3}``, well inside the CFL margin.
"""
max_speed(u) = maximum(abs, field_data(u))


"""
    scalar_variance(φ)

The scalar variance ``\\langle\\varphi^{2}\\rangle`` of the scalar field `φ` (for a mean-zero
``\\varphi``). Computed as ``\\langle\\varphi,\\varphi\\rangle`` with the normalized inner product,
so by Parseval's theorem it accepts `φ` in either representation.
"""
scalar_variance(φ) = inner(φ, φ)


"""
    scalar_dissipation(φ, domain, diffusivity)

The mean scalar-variance dissipation rate
``\\varepsilon_\\varphi = 2\\varkappa\\,\\langle\\lvert\\nabla\\varphi\\rvert^{2}\\rangle``, from the scalar field
`φ` ``\\varphi`` (in spectral representation), the [`FixedDomain`](@ref) bundle `domain`, and the
scalar `diffusivity` ``\\varkappa = \\nu/\\mathrm{Sc}``.
The gradient energy ``\\langle\\lvert\\nabla\\varphi\\rvert^{2}\\rangle`` is the Dirichlet (``H^{1}``) energy
``\\langle\\varphi,\\lvert\\boldsymbol{\\kappa}\\rvert^{2}\\varphi\\rangle``, formed by a fused `weighted_inner`
against the squared-wavenumber multiplier `domain.squared_wavenumber_kernel` — straight from the spectral
coefficients, with no physical gradient ``\\nabla\\varphi`` materialized (unlike the velocity dissipation's
cached ``\\boldsymbol{\\omega}``, ``\\nabla\\varphi`` is not otherwise formed by the scalar right-hand side).
"""
scalar_dissipation(φ, domain::FixedDomain, diffusivity::Real) =
  2 * diffusivity * weighted_inner(φ, domain.squared_wavenumber_kernel)


# The exact isotropy constant relating the coordinate-free strain skewness to the classical longitudinal
# one: ⟨(∂u₁/∂x₁)³⟩/⟨(∂u₁/∂x₁)²⟩^{3/2} = C·⟨tr S³⟩/⟨S:S⟩^{3/2}, from ⟨tr S³⟩ = (105/8)⟨(∂u₁/∂x₁)³⟩ and
# ⟨S:S⟩ = (15/2)⟨(∂u₁/∂x₁)²⟩ for isotropic incompressible turbulence (Betchov 1956; verified numerically).
const _SKEWNESS_ISOTROPY_CONSTANT = (4 / 7) * sqrt(15 / 2)              # ≈ 1.5649


"""
    derivative_skewness(û, domain)

The velocity-derivative skewness ``S``, written coordinate-free as the normalized third invariant of
the strain-rate tensor ``\\boldsymbol{S} = \\operatorname{sym}\\nabla\\boldsymbol{u}`` (the italic ``S``
is the scalar skewness, the bold ``\\boldsymbol{S}`` the strain-rate tensor):

```math
S = C\\,\\frac{\\langle\\operatorname{tr}\\boldsymbol{S}^{3}\\rangle}{\\langle\\boldsymbol{S}:\\boldsymbol{S}\\rangle^{3/2}}
  = 3C\\,\\frac{\\langle\\det\\boldsymbol{S}\\rangle}{\\langle\\boldsymbol{S}:\\boldsymbol{S}\\rangle^{3/2}},
\\qquad C = \\tfrac{4}{7}\\sqrt{\\tfrac{15}{2}} \\approx 1.5649.
```

Because ``\\boldsymbol{S}`` is symmetric and, for the incompressible field, traceless,
``\\operatorname{tr}\\boldsymbol{S}^{3} = 3\\det\\boldsymbol{S}``. By isotropy this equals the classical
longitudinal skewness ``\\langle(\\partial u_1/\\partial x_1)^{3}\\rangle / \\langle(\\partial u_1/\\partial x_1)^{2}\\rangle^{3/2}``;
the constant follows from ``\\langle\\operatorname{tr}\\boldsymbol{S}^{3}\\rangle = \\tfrac{105}{8}\\langle(\\partial u_1/\\partial x_1)^{3}\\rangle``
and ``\\langle\\boldsymbol{S}:\\boldsymbol{S}\\rangle = \\tfrac{15}{2}\\langle(\\partial u_1/\\partial x_1)^{2}\\rangle`` (Betchov 1956). So the
reported value is the familiar ``S \\approx -0.5`` of developed turbulence, but from a genuine tensor
invariant rather than an axis-dependent gradient.

From the velocity field `û` in spectral representation, the strain is formed directly with
`symmetric_gradient` and the wavenumber `multipliers` of the [`FixedDomain`](@ref) bundle `domain`
(skipping the full nine-component velocity gradient), carried to physical space by its rank-2 tensor
transform plans, and reduced to ``\\langle\\boldsymbol{S}:\\boldsymbol{S}\\rangle`` (`inner`) and
``\\langle\\det\\boldsymbol{S}\\rangle`` (`det`); `domain` also sizes the per-call tensor and scalar scratch.
``S`` is the classic marker of *developed* turbulence: a random-phase (Gaussian) field has ``S \\approx 0``
(all odd invariants vanish), while fully developed isotropic turbulence has ``S \\approx -0.5`` (Kolmogorov)
— the enstrophy-production / vortex-stretching signature. Its plateau is the strict "real turbulence yet"
gate of the warm-up detector.
"""
function derivative_skewness(û, domain::FixedDomain)
  strain = symmetric_gradient(û, domain.multipliers)                   # Ŝ = sym∇u (fused; skips the full ∇u)
  strain_physical = tensor_physical(domain)
  to_physical!(strain_physical, strain, domain.tensor_plans)            # S in physical space (Ŝ is consumed)
  ss = inner(strain_physical, strain_physical)                       # ⟨S:S⟩
  ss <= 0 && return 0.0
  det_field = scalar_physical(domain)
  det!(det_field, strain_physical)                                   # det S at each grid point
  mean_det = sum(field_data(det_field)) / length(field_data(det_field))   # ⟨det S⟩
  return 3 * _SKEWNESS_ISOTROPY_CONSTANT * mean_det / ss^1.5         # C · 3⟨det S⟩/⟨S:S⟩^{3/2}
end


"""
    energy_spectrum(û, domain)

The measured kinetic-energy spectrum ``E(\\kappa)`` of the velocity field `û` (in spectral
representation) — the turbulent kinetic energy resolved over wavenumber-magnitude shells,
``k = \\sum_\\kappa E(\\kappa)``. Returns `(κ, E)`: the shell-center wavenumber magnitudes and the energy
in each shell (brought to the host, an occasional diagnostic). It is the `GBGPeriodicFields` radial
spectrum of `û` halved — the field reduction sums ``\\lvert\\hat{\\boldsymbol u}\\rvert^2`` while the
kinetic energy carries the ``\\tfrac12``. The `domain` (a [`FixedDomain`](@ref)) supplies the wavenumber
multipliers. This is the measured counterpart of a [`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology) model
spectrum, for validation.
"""
function energy_spectrum(û, domain::FixedDomain)
  shells, spec = radial_spectrum(û, domain.multipliers)
  return Array(shells), Array(0.5 .* spec)
end


"""
    integral_scale(û, domain)

The longitudinal integral length scale of the velocity field `û`, measured from its
[`energy_spectrum`](@ref) ``E(\\kappa)``,

```math
L_{11} = \\frac{3\\pi}{4}\\,\\frac{\\int_0^\\infty E(\\kappa)/\\kappa\\,\\mathrm d\\kappa}{\\int_0^\\infty E(\\kappa)\\,\\mathrm d\\kappa}.
```

``L_{11}`` is the large-eddy scale — the one flow parameter a
[`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology) model spectrum needs that the
small scales do not fix. The `domain` (a [`FixedDomain`](@ref)) supplies the wavenumber multipliers.
"""
function integral_scale(û, domain::FixedDomain)
  κ, E = energy_spectrum(û, domain)
  weighted = zero(eltype(E))
  total = zero(eltype(E))
  for i in eachindex(κ, E)
    total += E[i]
    κ[i] > 0 && (weighted += E[i] / κ[i])
  end
  return (3 * π / 4) * weighted / total
end


end # module Observables
