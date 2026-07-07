# Observables — the functions of the flow state that are measured: kinetic energy, dissipation, the
# velocity-derivative skewness, the scalar variance and its dissipation, and the maximum component
# speed (which feeds the CFL). In the Mori–Zwanzig reading (ARCHITECTURE §8) these are the observables
# of the `Dynamics`: their plateaus gate warm-up and their statistics are tracked by
# GBGStreamingStatistics. Each reduces a field to a scalar — a GBGPeriodicFields inner product or moment.

"""
    Observables

The functions of the flow state that are measured — kinetic energy, dissipation, the velocity-
derivative skewness, the scalar variance and its dissipation, and the maximum component speed. In the
Mori–Zwanzig reading (design doc §8) these are the *observables* of the `Dynamics`: their plateaus gate
warm-up (`warmup!`), and their statistics are tracked by `GBGStreamingStatistics`. Each reduces a field
to a scalar.
"""
module Observables

using GBGPeriodicFields
using ..SimulationState: SpectralOperators, tensor_physical, scalar_physical

export kinetic_energy, dissipation, max_speed,
       scalar_variance, scalar_dissipation, derivative_skewness


"""
    kinetic_energy(velocity)

The turbulent kinetic energy ``\\tfrac12\\langle\\lvert\\boldsymbol{u}\\rvert^{2}\\rangle`` of the
velocity field `velocity`. Computed as ``\\tfrac12\\,\\langle\\boldsymbol{u},\\boldsymbol{u}\\rangle`` with
the normalized inner product, so by Parseval's theorem it accepts `velocity` in either
representation.
"""
kinetic_energy(velocity) = 0.5 * inner(velocity, velocity)


"""
    dissipation(vorticity, viscosity)

The mean kinetic-energy dissipation rate of a homogeneous flow,
``\\varepsilon = \\nu\\,\\langle\\lvert\\boldsymbol{\\omega}\\rvert^{2}\\rangle``, from the physical
`vorticity` ``\\boldsymbol{\\omega}`` and the kinematic `viscosity` ``\\nu`` (the homogeneous
identity ``\\varepsilon = 2\\nu\\langle S_{ij}S_{ij}\\rangle = \\nu\\langle\\lvert\\boldsymbol{\\omega}\\rvert^{2}\\rangle``).
"""
dissipation(vorticity, viscosity::Real) = viscosity * inner(vorticity, vorticity)


"""
    max_speed(velocity)

The largest velocity component in absolute value, ``\\max_i\\lvert u_i\\rvert`` — an allocation-free
reduction used to set the advective CFL timestep. It differs from the true ``\\sup\\lvert\\boldsymbol{u}\\rvert``
by at most ``\\sqrt{3}``, well inside the CFL margin.
"""
max_speed(velocity) = maximum(abs, field_data(velocity))


"""
    scalar_variance(scalar)

The scalar variance ``\\langle\\varphi^{2}\\rangle`` of the scalar field `scalar` (for a mean-zero
``\\varphi``). Computed as ``\\langle\\varphi,\\varphi\\rangle`` with the normalized inner product,
so by Parseval's theorem it accepts `scalar` in either representation.
"""
scalar_variance(scalar) = inner(scalar, scalar)


"""
    scalar_dissipation(scalar, ops, diffusivity)

The mean scalar-variance dissipation rate
``\\varepsilon_\\varphi = 2\\varkappa\\,\\langle\\lvert\\nabla\\varphi\\rvert^{2}\\rangle``, from the scalar field
`scalar` ``\\varphi`` (in spectral representation) and the scalar `diffusivity` ``\\varkappa = \\nu/\\mathrm{Sc}``.
The gradient energy ``\\langle\\lvert\\nabla\\varphi\\rvert^{2}\\rangle`` is the Dirichlet (``H^{1}``) energy
``\\langle\\varphi,\\lvert\\boldsymbol{\\kappa}\\rvert^{2}\\varphi\\rangle``, formed by a fused `weighted_inner`
against the squared-wavenumber multiplier `ops.squared_wavenumber_kernel` — straight from the spectral
coefficients, with no physical gradient ``\\nabla\\varphi`` materialized (unlike the velocity dissipation's
cached ``\\boldsymbol{\\omega}``, ``\\nabla\\varphi`` is not otherwise formed by the scalar right-hand side).
"""
scalar_dissipation(scalar, ops::SpectralOperators, diffusivity::Real) =
  2 * diffusivity * weighted_inner(scalar, ops.squared_wavenumber_kernel)


# The exact isotropy constant relating the coordinate-free strain skewness to the classical longitudinal
# one: ⟨(∂u₁/∂x₁)³⟩/⟨(∂u₁/∂x₁)²⟩^{3/2} = C·⟨tr S³⟩/⟨S:S⟩^{3/2}, from ⟨tr S³⟩ = (105/8)⟨(∂u₁/∂x₁)³⟩ and
# ⟨S:S⟩ = (15/2)⟨(∂u₁/∂x₁)²⟩ for isotropic incompressible turbulence (Betchov; verified numerically).
const _SKEWNESS_ISOTROPY_CONSTANT = (4 / 7) * sqrt(15 / 2)              # ≈ 1.5649


"""
    derivative_skewness(uh, ops)

The velocity-derivative skewness, written coordinate-free as the normalized third invariant of the
strain-rate tensor ``\\boldsymbol{S} = \\operatorname{sym}\\nabla\\boldsymbol{u}``:

```math
S = C\\,\\frac{\\langle\\operatorname{tr}\\boldsymbol{S}^{3}\\rangle}{\\langle\\boldsymbol{S}:\\boldsymbol{S}\\rangle^{3/2}}
  = 3C\\,\\frac{\\langle\\det\\boldsymbol{S}\\rangle}{\\langle\\boldsymbol{S}:\\boldsymbol{S}\\rangle^{3/2}},
\\qquad C = \\tfrac{4}{7}\\sqrt{\\tfrac{15}{2}} \\approx 1.5649.
```

Because ``\\boldsymbol{S}`` is symmetric and, for the incompressible field, traceless,
``\\operatorname{tr}\\boldsymbol{S}^{3} = 3\\det\\boldsymbol{S}``. By isotropy this equals the classical
longitudinal skewness ``\\langle(\\partial u_1/\\partial x_1)^{3}\\rangle / \\langle(\\partial u_1/\\partial x_1)^{2}\\rangle^{3/2}``;
the constant follows from ``\\langle\\operatorname{tr}\\boldsymbol{S}^{3}\\rangle = \\tfrac{105}{8}\\langle(\\partial u_1/\\partial x_1)^{3}\\rangle``
and ``\\langle\\boldsymbol{S}:\\boldsymbol{S}\\rangle = \\tfrac{15}{2}\\langle(\\partial u_1/\\partial x_1)^{2}\\rangle``. So the
reported value is the familiar ``S \\approx -0.5`` of developed turbulence, but from a genuine tensor
invariant rather than an axis-dependent gradient.

The strain is formed directly with `symmetric_gradient` (skipping the full nine-component velocity
gradient), transformed to physical space, and reduced to ``\\langle\\boldsymbol{S}:\\boldsymbol{S}\\rangle``
(`inner`) and ``\\langle\\det\\boldsymbol{S}\\rangle`` (`det`). ``S`` is the classic marker of *developed*
turbulence: a random-phase (Gaussian) field has ``S \\approx 0`` (all odd invariants vanish), while fully
developed isotropic turbulence has ``S \\approx -0.5`` (Kolmogorov) — the enstrophy-production /
vortex-stretching signature. Its plateau is the strict "real turbulence yet" gate of the warm-up detector.
"""
function derivative_skewness(uh, ops::SpectralOperators)
  strain = symmetric_gradient(uh, ops.multipliers)                   # Ŝ = sym∇u (fused; skips the full ∇u)
  strain_physical = tensor_physical(ops)
  to_physical!(strain_physical, strain, ops.tensor_plans)            # S in physical space (Ŝ is consumed)
  ss = inner(strain_physical, strain_physical)                       # ⟨S:S⟩
  ss <= 0 && return 0.0
  det_field = scalar_physical(ops)
  det!(det_field, strain_physical)                                   # det S at each grid point
  mean_det = sum(field_data(det_field)) / length(field_data(det_field))   # ⟨det S⟩
  return 3 * _SKEWNESS_ISOTROPY_CONSTANT * mean_det / ss^1.5         # C · 3⟨det S⟩/⟨S:S⟩^{3/2}
end


end # module Observables
