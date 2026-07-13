# Generator — the flow's equations of motion: the incompressible Navier–Stokes right-hand side in
# rotational form, the passive-scalar advection, and the exact viscous/diffusive integrating factor.
# In the Mori–Zwanzig reading (ARCHITECTURE §8) this is the generator of the full dynamics — the RHS
# the numerical propagator (Propagator) advances; the `Observables` are the functions of that state.
#
# The momentum equation is advanced as ∂û/∂t = ℙ(u×ω)^ − ν|k|²û (+ forcing), with the viscous term
# integrated exactly through the integrating factor ℰ = exp(-ν|k|²Δt) (built here, applied in
# Propagator). This module owns the nonlinear-term assembly and the integrating factor;
# everything diagonal-in-Fourier is a GBGPeriodicFields operator.

"""
    Generator

The flow's equations of motion — the incompressible Navier–Stokes right-hand side in rotational form
(the de-aliased, Leray-projected nonlinear term), the passive-scalar advection, and the exact viscous
integrating factor. In the Mori–Zwanzig reading (design doc §8) this is the *generator of the full
dynamics* — it advances the flow state; `Observables` are the functions of that state, and
`Propagator` the numerical propagator.

Its six operations (each formula lives in the operation's own docstring):
- [`velocity_to_physical!`](@ref), [`vorticity_to_physical!`](@ref), [`scalar_to_physical!`](@ref) —
  recover the physical velocity, vorticity, and scalar from their spectral representations.
- [`velocity_nonlinear!`](@ref), [`scalar_nonlinear!`](@ref) — assemble the de-aliased, Leray-projected
  momentum and scalar nonlinear terms (the reversible advection).
- [`integrating_factor!`](@ref) — build the exact viscous/diffusive spectral multiplier for the linear
  diffusion term.

Each field-transforming or nonlinear-assembly operation takes the `domain` (a [`FixedDomain`](@ref)) and
the individual preallocated scratch field(s) it writes into as its final argument(s), so the module names
no buffer bundle; [`integrating_factor!`](@ref) takes `domain` alone.
"""
module Generator

using GBGPeriodicFields
using ..SimulationDomain: FixedDomain
using ..Forcing: AbstractForcing, NoForcing

export velocity_to_physical!, vorticity_to_physical!, velocity_nonlinear!, integrating_factor!,
       scalar_to_physical!, scalar_nonlinear!, FlowConditions


"""
    FlowConditions(; viscosity, schmidt = 1.0, velocity_forcing = NoForcing(),
                   scalar_forcing = NoForcing())

The physical conditions the generator is built from — the kinematic viscosity ``\\nu`` (`viscosity`;
the Reynolds number is ``\\mathrm{Re} = 1/\\nu``), the Schmidt number ``\\mathrm{Sc}`` (`schmidt`; the
scalar diffusivity is ``\\varkappa = \\nu/\\mathrm{Sc}``), and the velocity and scalar forcing strategies
(`velocity_forcing`, `scalar_forcing`, both `AbstractForcing`). Consumed by the time step (`step!`).
"""
struct FlowConditions{VF<:AbstractForcing, SF<:AbstractForcing}
  viscosity::Float64
  schmidt::Float64
  velocity_forcing::VF
  scalar_forcing::SF
end

FlowConditions(; viscosity, schmidt = 1.0, velocity_forcing = NoForcing(), scalar_forcing = NoForcing()) =
  FlowConditions(Float64(viscosity), Float64(schmidt), velocity_forcing, scalar_forcing)


"""
    velocity_to_physical!(u, û, domain, velocity_copy)

Compute the physical velocity ``\\boldsymbol{u}`` from the velocity field `û` (given in spectral
representation ``\\hat{\\boldsymbol{u}}``) into `u`, leaving `û` unchanged. The scratch `velocity_copy` (a
spectral vector field) is the working space.
"""
function velocity_to_physical!(u, û, domain::FixedDomain, velocity_copy)
  copyto!(field_data(velocity_copy), field_data(û))  # copy û first — the in-place inverse transform consumes its spectral source
  to_physical!(u, velocity_copy, domain.velocity_plans)
  return u
end


"""
    vorticity_to_physical!(ω, û, domain, vorticity_spectral)

Compute the physical vorticity ``\\boldsymbol{\\omega} = \\nabla\\times\\boldsymbol{u}`` from the
velocity field `û` (given in spectral representation ``\\hat{\\boldsymbol{u}}``) into `ω`: the spectral
vorticity ``\\mathrm{i}\\boldsymbol{\\kappa}\\times\\hat{\\boldsymbol{u}}`` is formed in the scratch
`vorticity_spectral` (a spectral vector field) and transformed, leaving `û` untouched.
"""
function vorticity_to_physical!(ω, û, domain::FixedDomain, vorticity_spectral)
  curl!(vorticity_spectral, û, domain.multipliers)
  to_physical!(ω, vorticity_spectral, domain.velocity_plans)
  return ω
end


"""
    velocity_nonlinear!(nonlinear, u, ω, domain, product_physical, product_spectral)

Assemble the de-aliased, Leray-projected nonlinear term of the momentum equation into `nonlinear`,
from the physical velocity `u` ``\\boldsymbol{u}`` and vorticity `ω` ``\\boldsymbol{\\omega}``.

In physical space the rotational form writes the convective term as the Lamb vector, through the identity

```math
(\\boldsymbol{u}\\cdot\\nabla)\\boldsymbol{u} = \\nabla\\big(\\tfrac12\\lvert\\boldsymbol{u}\\rvert^{2}\\big) - \\boldsymbol{u}\\times\\boldsymbol{\\omega},
```

so that, with the Leray–Helmholtz projection ``\\mathbb{P}`` onto divergence-free fields absorbing the
pressure and the ``\\nabla(\\tfrac12\\lvert\\boldsymbol{u}\\rvert^{2})`` gradient, the momentum equation
becomes

```math
\\partial_t\\boldsymbol{u} = \\mathbb{P}\\,(\\boldsymbol{u}\\times\\boldsymbol{\\omega}) + \\nu\\nabla^{2}\\boldsymbol{u} + \\boldsymbol{f}.
```

The term computed here is the spectral image of ``\\mathbb{P}\\,(\\boldsymbol{u}\\times\\boldsymbol{\\omega})``,
with the de-alias kernel `domain.dealias` (the sharp ``2/3`` rule by default) controlling the aliasing of
the quadratic product. The Lamb vector is held in the scratch `product_physical` (a physical vector
field) and its transform in `product_spectral` (a spectral vector field), so the operation allocates
nothing.
"""
function velocity_nonlinear!(nonlinear, u, ω, domain::FixedDomain, product_physical, product_spectral)
  cross!(product_physical, u, ω)
  to_spectral!(product_spectral, product_physical, domain.velocity_plans)
  helmholtz_projection!(nonlinear, product_spectral, domain.multipliers)
  convolve!(nonlinear, nonlinear, domain.dealias)
  return nonlinear
end


"""
    integrating_factor!(factor, domain, diffusivity, dt, rate = nothing)

Write the exact diffusive integrating factor into the scalar spectral buffer `factor`. Over a step
``\\Delta t`` (`dt`) the diffusion equation ``\\partial_t f = D\\nabla^{2} f`` is solved exactly in spectral
representation by the per-mode multiplier

```math
\\mathcal{E}(\\boldsymbol{\\kappa}) = \\exp\\!\\big(-D\\,\\lvert\\boldsymbol{\\kappa}\\rvert^{2}\\,\\Delta t\\big),
```

so multiplying a field by `factor` advances its viscous/diffusive part exactly (no stability
restriction). The `domain` (a `FixedDomain`) supplies the squared-wavenumber
field ``\\lvert\\boldsymbol{\\kappa}\\rvert^{2}`` (`domain.squared_wavenumber`); in spectral
representation ``-\\nabla^{2}`` acts as multiplication by it. The diffusivity ``D`` (`diffusivity`) is the kinematic viscosity ``\\nu`` for the
velocity and ``\\nu/\\mathrm{Sc}`` for the scalar ``\\varphi`` (``\\mathrm{Sc}`` the Schmidt number).

When a linear forcing rate ``A(\\boldsymbol{\\kappa})`` is supplied (`rate`, a real array; from the
`set_forcing_rate!` of a `Linear`/`ConstantPower` forcing), it is folded into the linear operator,
``\\mathcal{E}(\\boldsymbol{\\kappa}) = \\exp\\!\\big((A(\\boldsymbol{\\kappa}) - D\\lvert\\boldsymbol{\\kappa}\\rvert^{2})\\,\\Delta t\\big)``
— exact for the linear forcing, so the integrator keeps its order.
"""
function integrating_factor!(factor, domain::FixedDomain, diffusivity::Real, dt::Real, rate = nothing)
  T = real(eltype(field_data(factor)))
  if rate === nothing
    field_data(factor) .= complex.(exp.(T(-diffusivity * dt) .* domain.squared_wavenumber))
  else
    field_data(factor) .= complex.(exp.(T(dt) .* (rate .- T(diffusivity) .* domain.squared_wavenumber)))
  end
  return factor
end


"""
    scalar_to_physical!(φ, φ̂, domain, scalar_copy)

Compute the physical scalar `φ` ``\\varphi`` from `φ̂` (the scalar in spectral representation
``\\hat{\\varphi}``) into `φ`, leaving `φ̂` unchanged. The scratch `scalar_copy` (a spectral scalar
field) is the working space.
"""
function scalar_to_physical!(φ, φ̂, domain::FixedDomain, scalar_copy)
  copyto!(field_data(scalar_copy), field_data(φ̂))  # copy φ̂ first — the in-place inverse transform consumes its spectral source
  to_physical!(φ, scalar_copy, domain.scalar_plans)
  return φ
end


"""
    scalar_nonlinear!(nonlinear, u, φ, domain, product_physical, product_spectral)

Assemble the de-aliased advection term of the passive-scalar equation into `nonlinear`, from the
physical `u` ``\\boldsymbol{u}`` and physical `φ` ``\\varphi``.

In conservative form the advection is
``-\\nabla\\cdot(\\boldsymbol{u}\\varphi)`` (equal to ``-\\boldsymbol{u}\\cdot\\nabla\\varphi`` since
``\\nabla\\cdot\\boldsymbol{u} = 0``); the conservative form is used because it conserves the scalar mean
exactly — the divergence has no ``\\boldsymbol{\\kappa}=\\boldsymbol 0`` component, and the de-alias
kernel `domain.dealias` (the sharp ``2/3`` rule by default) leaves that mode untouched. It is computed
pseudospectrally as ``-\\,\\mathrm{dealias}\\big(\\mathrm{i}\\boldsymbol{\\kappa}\\cdot\\widehat{\\boldsymbol{u}\\varphi}\\big)``,
the kernel controlling the aliasing of the quadratic product.
The scalar flux ``\\boldsymbol{u}\\varphi`` reuses the momentum scratch `product_physical` (physical) and
`product_spectral` (spectral).
"""
function scalar_nonlinear!(nonlinear, u, φ, domain::FixedDomain, product_physical, product_spectral)
  φ_data = field_data(φ)
  field_data(product_physical) .= field_data(u) .* reshape(φ_data, size(φ_data)..., 1)  # flux uφ
  to_spectral!(product_spectral, product_physical, domain.velocity_plans)        # (uφ)^
  divergence!(nonlinear, product_spectral, domain.multipliers)          # i𝛋·(uφ)^ = ∇·(uφ)
  convolve!(nonlinear, nonlinear, domain.dealias, -1, 0)          # N_φ = -dealias(∇·(uφ))
  return nonlinear
end


end # module Generator
