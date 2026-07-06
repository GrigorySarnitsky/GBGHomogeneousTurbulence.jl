# Equations — the physics the integrators advance: the incompressible Navier–Stokes right-hand side
# in rotational form, and the diagnostics derived from a velocity field.
#
# The momentum equation is advanced as ∂û/∂t = ℙ(u×ω)^ − ν|k|²û (+ forcing), with the viscous term
# integrated exactly through the integrating factor ℰ = exp(-ν|k|²Δt) (built here, applied in
# TimeIntegration). This module owns only the nonlinear-term assembly and the integrating factor;
# everything diagonal-in-Fourier is a GBGPeriodicFields operator.

"""
    Equations

The incompressible Navier–Stokes right-hand side in rotational form — the de-aliased,
Leray-projected nonlinear term and the exact viscous integrating factor — together with the
velocity diagnostics (kinetic energy, dissipation, maximum speed).
"""
module Equations

using GBGPeriodicFields
using ..SimulationState: SpectralOperators, Workspace

export velocity_vorticity!, velocity_nonlinear!, integrating_factor!,
       scalar_to_physical!, scalar_nonlinear!,
       kinetic_energy, dissipation, max_speed,
       scalar_variance, scalar_dissipation, derivative_skewness


"""
    velocity_vorticity!(velocity, vorticity, uh, ops, ws)

Compute the physical velocity ``\\mathbf{u}`` and vorticity
``\\boldsymbol{\\omega} = \\nabla\\times\\mathbf{u}`` of the velocity field `uh` (given in spectral
representation ``\\hat{\\mathbf{u}}``) into the buffers `velocity` and `vorticity`.

`uh` is preserved: the vorticity is transformed first, then a *copy* of `uh` is transformed — the
in-place inverse transform consumes its spectral source.
"""
function velocity_vorticity!(velocity, vorticity, uh, ops::SpectralOperators, ws::Workspace)
  curl!(ws.vorticity_spectral, uh, ops.multipliers)
  to_physical!(vorticity, ws.vorticity_spectral, ops.velocity_plans)
  copyto!(field_data(ws.velocity_copy), field_data(uh))
  to_physical!(velocity, ws.velocity_copy, ops.velocity_plans)
  return velocity, vorticity
end


"""
    velocity_nonlinear!(nonlinear, velocity, vorticity, ops, ws)

Assemble the de-aliased, Leray-projected nonlinear term of the momentum equation into `nonlinear`,
from the physical `velocity` ``\\mathbf{u}`` and `vorticity` ``\\boldsymbol{\\omega}``.

In physical space the rotational form writes the convective term as the Lamb vector: with the
identity ``(\\mathbf{u}\\cdot\\nabla)\\mathbf{u} = \\nabla\\big(\\tfrac12\\lvert\\mathbf{u}\\rvert^{2}\\big) - \\mathbf{u}\\times\\boldsymbol{\\omega}``,
the divergence-free momentum equation becomes
``\\partial_t\\mathbf{u} = \\mathbb{P}\\,(\\mathbf{u}\\times\\boldsymbol{\\omega}) + \\nu\\nabla^{2}\\mathbf{u} + \\mathbf{f}``,
where the Leray–Helmholtz projection ``\\mathbb{P}`` onto divergence-free fields absorbs the pressure
and the ``\\nabla(\\tfrac12\\lvert\\mathbf{u}\\rvert^{2})`` gradient. The term computed here is the
spectral image of ``\\mathbb{P}\\,(\\mathbf{u}\\times\\boldsymbol{\\omega})``, with the ``2/3`` rule
removing the aliasing of the quadratic product. Allocation-free (a destination distinct from its
sources takes the no-alias path).
"""
function velocity_nonlinear!(nonlinear, velocity, vorticity, ops::SpectralOperators, ws::Workspace)
  cross!(ws.lamb, velocity, vorticity)
  to_spectral!(ws.scratch, ws.lamb, ops.velocity_plans)
  helmholtz_projection!(nonlinear, ws.scratch, ops.multipliers)
  convolve!(nonlinear, nonlinear, ops.dealias)
  return nonlinear
end


"""
    integrating_factor!(factor, ops, diffusivity, dt, rate = nothing)

Write the exact diffusive integrating factor into the scalar spectral buffer `factor`. Over a step
``\\Delta t`` the diffusion equation ``\\partial_t f = D\\nabla^{2} f`` is solved exactly in spectral
representation by the per-mode multiplier

```math
\\mathcal{E}(\\mathbf{k}) = \\exp\\!\\big(-D\\,\\lvert\\mathbf{k}\\rvert^{2}\\,\\Delta t\\big),
```

so multiplying a field by `factor` advances its viscous/diffusive part exactly (no stability
restriction). The diffusivity ``D`` (`diffusivity`) is the kinematic viscosity ``\\nu`` for the
velocity and ``\\nu/\\mathrm{Sc}`` for the scalar ``\\varphi`` (``\\mathrm{Sc}`` the Schmidt number).

When a linear forcing rate ``A(\\mathbf{k})`` is supplied (`rate`, a real array; from the
`forcing_rate!` of a `Linear`/`ConstantPower` forcing), it is folded into the linear operator,
``\\mathcal{E}(\\mathbf{k}) = \\exp\\!\\big((A(\\mathbf{k}) - D\\lvert\\mathbf{k}\\rvert^{2})\\,\\Delta t\\big)``
— exact for the linear forcing, so the integrator keeps its order.
"""
function integrating_factor!(factor, ops::SpectralOperators, diffusivity::Real, dt::Real, rate = nothing)
  T = real(eltype(field_data(factor)))
  if rate === nothing
    field_data(factor) .= complex.(exp.(T(-diffusivity * dt) .* ops.squared_wavenumber))
  else
    field_data(factor) .= complex.(exp.(T(dt) .* (rate .- T(diffusivity) .* ops.squared_wavenumber)))
  end
  return factor
end


"""
    scalar_to_physical!(scalar, phih, ops, ws)

Compute the physical scalar `scalar` ``\\varphi`` from `phih` (the scalar in spectral representation
``\\hat{\\varphi}``), preserving `phih` — a copy is transformed, since the in-place inverse transform
consumes its source.
"""
function scalar_to_physical!(scalar, phih, ops::SpectralOperators, ws::Workspace)
  copyto!(field_data(ws.scalar_copy), field_data(phih))
  to_physical!(scalar, ws.scalar_copy, ops.scalar_plans)
  return scalar
end


"""
    scalar_nonlinear!(nonlinear, velocity, scalar, ops, ws)

Assemble the de-aliased advection term of the passive-scalar equation into `nonlinear`, from the
physical `velocity` ``\\mathbf{u}`` and physical `scalar` ``\\varphi``.

In conservative form the advection is
``-\\nabla\\cdot(\\mathbf{u}\\varphi)`` (equal to ``-\\mathbf{u}\\cdot\\nabla\\varphi`` since
``\\nabla\\cdot\\mathbf{u} = 0``); the conservative form is used because, with the ``2/3`` rule, it
conserves the scalar mean exactly (the divergence has no ``\\mathbf{k}=\\mathbf 0`` component). It is
computed pseudospectrally as ``-\\,\\mathrm{dealias}\\big(i\\mathbf{k}\\cdot\\widehat{\\mathbf{u}\\varphi}\\big)``.
The scalar flux ``\\mathbf{u}\\varphi`` reuses the physical and spectral velocity scratch.
"""
function scalar_nonlinear!(nonlinear, velocity, scalar, ops::SpectralOperators, ws::Workspace)
  scalar_data = field_data(scalar)
  field_data(ws.lamb) .= field_data(velocity) .* reshape(scalar_data, size(scalar_data)..., 1)  # flux uφ
  to_spectral!(ws.scratch, ws.lamb, ops.velocity_plans)        # (uφ)^
  divergence!(nonlinear, ws.scratch, ops.multipliers)          # i𝐤·(uφ)^ = ∇·(uφ)
  convolve!(nonlinear, nonlinear, ops.dealias, -1, 0)          # N_φ = -dealias(∇·(uφ))
  return nonlinear
end


"""
    kinetic_energy(velocity)

The turbulent kinetic energy ``\\tfrac12\\langle\\lvert\\mathbf{u}\\rvert^{2}\\rangle`` of the
velocity field `velocity`. Computed as ``\\tfrac12\\,\\langle\\mathbf{u},\\mathbf{u}\\rangle`` with
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
reduction used to set the advective CFL timestep. It differs from the true ``\\sup\\lvert\\mathbf{u}\\rvert``
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
``\\chi = 2\\kappa\\,\\langle\\lvert\\nabla\\varphi\\rvert^{2}\\rangle``, from the physical scalar
gradient `scalar_gradient` ``\\nabla\\varphi`` and the scalar `diffusivity` ``\\kappa = \\nu/\\mathrm{Sc}``.
"""
scalar_dissipation(scalar_gradient, diffusivity::Real) = 2 * diffusivity * inner(scalar_gradient, scalar_gradient)


"""
    derivative_skewness(uh, ops, ws)

The velocity-derivative skewness

```math
S = \\frac{\\big\\langle(\\partial_{x_i} u_i)^3\\big\\rangle}{\\big\\langle(\\partial_{x_i} u_i)^2\\big\\rangle^{3/2}},
```

averaged over the three diagonal components ``i = 1,2,3`` for isotropy, of the velocity `uh` (given in
spectral representation). Each diagonal derivative ``\\partial_{x_i} u_i`` is formed spectrally
(`gradient!`), transformed to physical space, and reduced to its second and third moments.

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
    m2 = mapreduce(abs2, +, g) / n                                     # ⟨(∂ᵢuᵢ)²⟩
    m3 = mapreduce(x -> x^3, +, g) / n                                 # ⟨(∂ᵢuᵢ)³⟩
    m2 > 0 && (skew += m3 / m2^1.5)
  end
  return skew / 3
end


end # module Equations
