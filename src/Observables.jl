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
using ..SimulationState: SpectralOperators, Workspace

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
    scalar_dissipation(scalar_gradient, diffusivity)

The mean scalar-variance dissipation rate
``\\varepsilon_\\varphi = 2\\varkappa\\,\\langle\\lvert\\nabla\\varphi\\rvert^{2}\\rangle``, from the physical scalar
gradient `scalar_gradient` ``\\nabla\\varphi`` and the scalar `diffusivity` ``\\varkappa = \\nu/\\mathrm{Sc}``.
"""
scalar_dissipation(scalar_gradient, diffusivity::Real) = 2 * diffusivity * inner(scalar_gradient, scalar_gradient)


"""
    derivative_skewness(uh, ops, ws)

The velocity-derivative skewness

```math
S = \\frac{\\big\\langle(\\partial u_1/\\partial x_1)^3\\big\\rangle}{\\big\\langle(\\partial u_1/\\partial x_1)^2\\big\\rangle^{3/2}},
```

the skewness of a **single** diagonal velocity gradient. The repeated index is *not* summed: this is
``\\partial u_1/\\partial x_1`` for one direction, **not** the divergence
``\\partial u_i/\\partial x_i = \\nabla\\cdot\\boldsymbol{u}``, which is identically zero for the
incompressible field. By isotropy the three diagonal gradients — ``\\partial u_1/\\partial x_1``,
``\\partial u_2/\\partial x_2``, ``\\partial u_3/\\partial x_3`` — share the same skewness, so the code
forms each spectrally (`gradient!`), transforms it to physical space, reduces it to its second and
third moments, and averages the three for better statistics.

``S`` is the classic marker of *developed* turbulence: a random-phase (Gaussian) field has
``S \\approx 0`` (a linear image of a Gaussian is Gaussian, hence symmetric), while fully developed
isotropic turbulence has ``S \\approx -0.5`` (Kolmogorov). Its plateau is the strict "real turbulence
yet" gate of the warm-up detector. No field-sized allocation — reuses the workspace scratch
(`ws.scratch`, `ws.velocity_star`).
"""
function derivative_skewness(uh, ops::SpectralOperators, ws::Workspace)
  grad = ws.scratch                                                     # ∇uᵢ, spectral vector scratch
  gradient_physical = ws.velocity_star                                  # ∇uᵢ, physical vector scratch
  skew = 0.0
  for i in 1:3
    ui = ScalarFieldSpectral(selectdim(field_data(uh), 4, i), ops.grid) # ûᵢ (a component view)
    gradient!(grad, ui, ops.multipliers)                               # ∇uᵢ in spectral representation
    to_physical!(gradient_physical, grad, ops.velocity_plans)          # ∇uᵢ in physical space
    g = selectdim(field_data(gradient_physical), 4, i)                 # ∂uᵢ/∂xᵢ (physical view)
    n = length(g)
    m2 = mapreduce(abs2, +, g) / n                                     # ⟨(∂uᵢ/∂xᵢ)²⟩ — i fixed, no sum
    m3 = mapreduce(x -> x^3, +, g) / n                                 # ⟨(∂uᵢ/∂xᵢ)³⟩ — i fixed, no sum
    m2 > 0 && (skew += m3 / m2^1.5)
  end
  return skew / 3
end


end # module Observables
