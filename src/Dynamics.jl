# Dynamics — the flow's equations of motion: the incompressible Navier–Stokes right-hand side in
# rotational form, the passive-scalar advection, and the exact viscous/diffusive integrating factor.
# In the Mori–Zwanzig reading (ARCHITECTURE §8) this is the generator of the full dynamics — the RHS
# the numerical propagator (TimeIntegration) advances; the `Observables` are the functions of that state.
#
# The momentum equation is advanced as ∂û/∂t = ℙ(u×ω)^ − ν|k|²û (+ forcing), with the viscous term
# integrated exactly through the integrating factor ℰ = exp(-ν|k|²Δt) (built here, applied in
# TimeIntegration). This module owns the nonlinear-term assembly and the integrating factor;
# everything diagonal-in-Fourier is a GBGPeriodicFields operator.

"""
    Dynamics

The flow's equations of motion — the incompressible Navier–Stokes right-hand side in rotational form
(the de-aliased, Leray-projected nonlinear term), the passive-scalar advection, and the exact viscous
integrating factor. In the Mori–Zwanzig reading (design doc §8) this is the *generator of the full
dynamics* — it advances the flow state; `Observables` are the functions of that state, and
`TimeIntegration` the numerical propagator.
"""
module Dynamics

using GBGPeriodicFields
using ..SimulationState: SpectralOperators, Workspace

export velocity_vorticity!, velocity_nonlinear!, integrating_factor!,
       scalar_to_physical!, scalar_nonlinear!


"""
    velocity_vorticity!(velocity, vorticity, uh, ops, ws)

Compute the physical velocity ``\\boldsymbol{u}`` and vorticity
``\\boldsymbol{\\omega} = \\nabla\\times\\boldsymbol{u}`` of the velocity field `uh` (given in spectral
representation ``\\hat{\\boldsymbol{u}}``) into the buffers `velocity` and `vorticity`.

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
from the physical `velocity` ``\\boldsymbol{u}`` and `vorticity` ``\\boldsymbol{\\omega}``.

In physical space the rotational form writes the convective term as the Lamb vector: with the
identity ``(\\boldsymbol{u}\\cdot\\nabla)\\boldsymbol{u} = \\nabla\\big(\\tfrac12\\lvert\\boldsymbol{u}\\rvert^{2}\\big) - \\boldsymbol{u}\\times\\boldsymbol{\\omega}``,
the divergence-free momentum equation becomes
``\\partial_t\\boldsymbol{u} = \\mathbb{P}\\,(\\boldsymbol{u}\\times\\boldsymbol{\\omega}) + \\nu\\nabla^{2}\\boldsymbol{u} + \\boldsymbol{f}``,
where the Leray–Helmholtz projection ``\\mathbb{P}`` onto divergence-free fields absorbs the pressure
and the ``\\nabla(\\tfrac12\\lvert\\boldsymbol{u}\\rvert^{2})`` gradient. The term computed here is the
spectral image of ``\\mathbb{P}\\,(\\boldsymbol{u}\\times\\boldsymbol{\\omega})``, with the ``2/3`` rule
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
\\mathcal{E}(\\boldsymbol{\\kappa}) = \\exp\\!\\big(-D\\,\\lvert\\boldsymbol{\\kappa}\\rvert^{2}\\,\\Delta t\\big),
```

so multiplying a field by `factor` advances its viscous/diffusive part exactly (no stability
restriction). The diffusivity ``D`` (`diffusivity`) is the kinematic viscosity ``\\nu`` for the
velocity and ``\\nu/\\mathrm{Sc}`` for the scalar ``\\varphi`` (``\\mathrm{Sc}`` the Schmidt number).

When a linear forcing rate ``A(\\boldsymbol{\\kappa})`` is supplied (`rate`, a real array; from the
`forcing_rate!` of a `Linear`/`ConstantPower` forcing), it is folded into the linear operator,
``\\mathcal{E}(\\boldsymbol{\\kappa}) = \\exp\\!\\big((A(\\boldsymbol{\\kappa}) - D\\lvert\\boldsymbol{\\kappa}\\rvert^{2})\\,\\Delta t\\big)``
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
physical `velocity` ``\\boldsymbol{u}`` and physical `scalar` ``\\varphi``.

In conservative form the advection is
``-\\nabla\\cdot(\\boldsymbol{u}\\varphi)`` (equal to ``-\\boldsymbol{u}\\cdot\\nabla\\varphi`` since
``\\nabla\\cdot\\boldsymbol{u} = 0``); the conservative form is used because, with the ``2/3`` rule, it
conserves the scalar mean exactly (the divergence has no ``\\boldsymbol{\\kappa}=\\boldsymbol 0`` component). It is
computed pseudospectrally as ``-\\,\\mathrm{dealias}\\big(i\\boldsymbol{\\kappa}\\cdot\\widehat{\\boldsymbol{u}\\varphi}\\big)``.
The scalar flux ``\\boldsymbol{u}\\varphi`` reuses the physical and spectral velocity scratch.
"""
function scalar_nonlinear!(nonlinear, velocity, scalar, ops::SpectralOperators, ws::Workspace)
  scalar_data = field_data(scalar)
  field_data(ws.lamb) .= field_data(velocity) .* reshape(scalar_data, size(scalar_data)..., 1)  # flux uφ
  to_spectral!(ws.scratch, ws.lamb, ops.velocity_plans)        # (uφ)^
  divergence!(nonlinear, ws.scratch, ops.multipliers)          # i𝛋·(uφ)^ = ∇·(uφ)
  convolve!(nonlinear, nonlinear, ops.dealias, -1, 0)          # N_φ = -dealias(∇·(uφ))
  return nonlinear
end


end # module Dynamics
