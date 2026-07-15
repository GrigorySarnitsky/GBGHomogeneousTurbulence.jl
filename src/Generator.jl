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
(the dealiased, Leray-projected nonlinear term), the passive-scalar advection, and the exact viscous
integrating factor.

Its contents (each formula lives in the operation's own docstring):
- [`FlowConditions`](@ref) — the physical conditions the right-hand side is built from (the viscosity,
  the Schmidt number, the forcings).
- [`velocity_to_physical!`](@ref), [`vorticity_to_physical!`](@ref), [`scalar_to_physical!`](@ref) —
  recover the velocity, vorticity, and scalar in physical representation from their spectral
  representation.
- [`velocity_nonlinear!`](@ref), [`scalar_nonlinear!`](@ref) — assemble the dealiased, Leray-projected
  momentum and scalar nonlinear terms.
- [`integrating_factor!`](@ref) — build the exact viscous/diffusive multiplier for the linear diffusion
  term.

Each field-transforming or nonlinear-assembly operation takes the `domain` (a [`FixedDomain`](@ref)) and
the individual preallocated scratch field(s) it writes into as its final argument(s);
[`integrating_factor!`](@ref) needs no scratch field — it takes `domain` with the scalar `diffusivity`,
the step `dt`, and an optional forcing `rate`.
"""
module Generator

using GBGPeriodicFields
using ..SimulationDomain: FixedDomain, DealiasingStrategy, TwoThirds, HouLi, PhaseShift
using ..Forcing: AbstractForcing, NoForcing

export velocity_to_physical!, vorticity_to_physical!, velocity_nonlinear!, integrating_factor!,
       scalar_to_physical!, scalar_nonlinear!, FlowConditions


"""
    FlowConditions(; viscosity, schmidt, velocity_forcing, scalar_forcing)

The physical conditions the generator is built from — the kinematic viscosity ``\\nu`` (`viscosity`;
the Reynolds number is ``\\mathrm{Re} = 1/\\nu``), the Schmidt number ``\\mathrm{Sc}`` (`schmidt`; the
scalar diffusivity is ``\\varkappa = \\nu/\\mathrm{Sc}``), and the velocity and scalar forcing strategies
(`velocity_forcing`, `scalar_forcing`, both `AbstractForcing`). Consumed by the time step (`step!`).

Every argument is explicit — `FlowConditions` carries no defaults; the `Simulation` front door supplies
the run-layer values (`schmidt = 1.0`, a stationary `BandRescaling` velocity forcing, and `NoForcing()`
for the scalar).

# Fields
- `viscosity`, `schmidt` — the kinematic viscosity ``\\nu`` and the Schmidt number ``\\mathrm{Sc}`` (both `Float64`).
- `velocity_forcing`, `scalar_forcing` — the velocity and scalar forcing strategies, each an `AbstractForcing`.
"""
struct FlowConditions{VF<:AbstractForcing, SF<:AbstractForcing}
  viscosity::Float64
  schmidt::Float64
  velocity_forcing::VF
  scalar_forcing::SF
end

FlowConditions(; viscosity, schmidt, velocity_forcing, scalar_forcing) =
  FlowConditions(Float64(viscosity), Float64(schmidt), velocity_forcing, scalar_forcing)


"""
    velocity_to_physical!(u, û, domain, velocity_copy)

Recover the velocity in physical representation into `u`, from the spectral `û` (left unchanged), on the
[`FixedDomain`](@ref) `domain` whose transform plans carry it. The scratch `velocity_copy` (a vector
field in spectral representation) is the working space.
"""
function velocity_to_physical!(u, û, domain::FixedDomain, velocity_copy)
  copyto!(field_data(velocity_copy), field_data(û))  # copy û first — the in-place inverse transform consumes its spectral source
  to_physical!(u, velocity_copy, domain.velocity_plans)
  return u
end


"""
    vorticity_to_physical!(ω, û, domain, vorticity_spectral)

Compute the vorticity ``\\boldsymbol{\\omega} = \\nabla\\times\\boldsymbol{u}`` in physical representation
into `ω`, from the velocity `û` in spectral representation, leaving `û` untouched. The spectral vorticity
``\\mathrm{i}\\boldsymbol{\\kappa}\\times\\hat{\\boldsymbol{u}}`` is formed in the scratch
`vorticity_spectral` (a vector field in spectral representation) and transformed to physical
representation by the [`FixedDomain`](@ref) `domain`'s plans.
"""
function vorticity_to_physical!(ω, û, domain::FixedDomain, vorticity_spectral)
  curl!(vorticity_spectral, û, domain.multipliers)
  to_physical!(ω, vorticity_spectral, domain.velocity_plans)
  return ω
end


"""
    velocity_nonlinear!(nonlinear, û, u, ω, domain, product_physical, product_spectral, phase_shift)

Assemble the dealiased, Leray-projected nonlinear term of the momentum equation into `nonlinear`, from
the velocity `û` in spectral representation and its physical velocity `u` and vorticity `ω`.

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

The term computed is the spectral image of ``\\mathbb{P}\\,(\\boldsymbol{u}\\times\\boldsymbol{\\omega})``,
dealiased by the domain's [`DealiasingStrategy`](@ref). A **mask** strategy ([`TwoThirds`](@ref),
[`HouLi`](@ref)) forms it once from `u`, `ω` and multiplies by the low-pass `domain.dealias`, leaving `û`
and `phase_shift` unused — pass `nothing` for `phase_shift` there. [`PhaseShift`](@ref) forms it **twice** —
from `u`, `ω`, and from the fields recovered on a grid displaced by half a cell (using `û` and the
`phase_shift` scratch, the run's `buffers.phase_shift`, built only for a `PhaseShift` domain) — averages
the two to cancel the aliasing, then truncates spherically with `domain.dealias`.

The Lamb vector is held in `product_physical` (a vector field in physical representation) and its
transform in `product_spectral`; the displaced evaluation reuses these and the `phase_shift` buffers, so
the operation allocates nothing.
"""
velocity_nonlinear!(nonlinear, û, u, ω, domain::FixedDomain, product_physical, product_spectral, phase_shift) =
  _velocity_nonlinear!(domain.dealiasing, nonlinear, û, u, ω, domain, product_physical, product_spectral, phase_shift)

# Mask strategies (TwoThirds / HouLi): one evaluation, post-multiplied by the low-pass kernel.
function _velocity_nonlinear!(::DealiasingStrategy, nonlinear, û, u, ω, domain::FixedDomain,
                              product_physical, product_spectral, phase_shift)
  _velocity_lamb!(nonlinear, u, ω, domain, product_physical, product_spectral)
  convolve!(nonlinear, nonlinear, domain.dealias)
  return nonlinear
end

# Phase-shift: average the primary and the half-cell-displaced evaluation (cancels the odd-parity
# aliases), then the spherical `domain.dealias` truncation removes the surviving two-axis aliases.
function _velocity_nonlinear!(::PhaseShift, nonlinear, û, u, ω, domain::FixedDomain,
                              product_physical, product_spectral, phase_shift)
  T = real(eltype(field_data(nonlinear)))
  _velocity_lamb!(nonlinear, u, ω, domain, product_physical, product_spectral)                        # primary
  convolve!(phase_shift.velocity_shifted, û, phase_shift.to_shifted)                                   # û on the displaced grid
  velocity_to_physical!(phase_shift.u_shifted, phase_shift.velocity_shifted, domain, product_spectral)
  vorticity_to_physical!(phase_shift.omega_shifted, phase_shift.velocity_shifted, domain, product_spectral)
  _velocity_lamb!(phase_shift.velocity_shifted, phase_shift.u_shifted, phase_shift.omega_shifted, domain, product_physical, product_spectral)
  convolve!(phase_shift.velocity_shifted, phase_shift.velocity_shifted, phase_shift.back)              # displaced term, shifted back
  combine!(nonlinear, T(1 // 2), nonlinear, T(1 // 2), phase_shift.velocity_shifted)                   # average the two grids
  convolve!(nonlinear, nonlinear, domain.dealias)                                                      # spherical truncation
  return nonlinear
end

# The raw pseudospectral ℙ(u×ω) in spectral representation, with no dealiasing — the piece both
# dealiasing strategies build.
function _velocity_lamb!(out, u, ω, domain::FixedDomain, product_physical, product_spectral)
  cross!(product_physical, u, ω)
  to_spectral!(product_spectral, product_physical, domain.velocity_plans)
  helmholtz_projection!(out, product_spectral, domain.multipliers)
  return out
end


"""
    integrating_factor!(factor, domain, diffusivity, dt, rate = nothing)

Write the exact diffusive integrating factor into `factor` (a scalar field in spectral representation). Over a step
``\\Delta t`` (`dt`) the diffusion equation ``\\partial_t f = D\\nabla^{2} f`` is solved exactly in spectral
representation by the per-mode multiplier

```math
\\mathcal{E}(\\boldsymbol{\\kappa}) = \\exp\\!\\big(-D\\,\\lvert\\boldsymbol{\\kappa}\\rvert^{2}\\,\\Delta t\\big),
```

so multiplying a field by `factor` advances its viscous/diffusive part exactly (no stability
restriction). The `domain` (a `FixedDomain`) supplies the squared-wavenumber
field ``\\lvert\\boldsymbol{\\kappa}\\rvert^{2}`` (`domain.squared_wavenumber`); in spectral
representation ``-\\nabla^{2}`` acts as multiplication by it. The diffusivity ``D`` (`diffusivity`) is the kinematic viscosity ``\\nu`` for the
velocity and ``\\nu/\\mathrm{Sc}`` for the scalar (``\\mathrm{Sc}`` the Schmidt number).

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

Recover the scalar in physical representation into `φ`, from the spectral `φ̂` (left unchanged), on the
[`FixedDomain`](@ref) `domain` whose transform plans carry it. The scratch `scalar_copy` (a scalar
field in spectral representation) is the working space.
"""
function scalar_to_physical!(φ, φ̂, domain::FixedDomain, scalar_copy)
  copyto!(field_data(scalar_copy), field_data(φ̂))  # copy φ̂ first — the in-place inverse transform consumes its spectral source
  to_physical!(φ, scalar_copy, domain.scalar_plans)
  return φ
end


"""
    scalar_nonlinear!(nonlinear, û, φ̂, u, φ, domain, product_physical, product_spectral, phase_shift)

Assemble the dealiased advection term of the passive-scalar equation into `nonlinear`, from the velocity
`û` and scalar `φ̂` in spectral representation and their physical `u`, `φ`.

In conservative form the advection is ``-\\nabla\\cdot(\\boldsymbol{u}\\varphi)`` (equal to
``-\\boldsymbol{u}\\cdot\\nabla\\varphi`` since ``\\nabla\\cdot\\boldsymbol{u} = 0``); the conservative form
conserves the scalar mean exactly — the divergence has no ``\\boldsymbol{\\kappa}=\\boldsymbol 0``
component, and the dealias kernel `domain.dealias` (the sharp ``2/3`` rule by default) leaves that mode
untouched.

It is computed pseudospectrally as
``-\\,\\mathrm{dealias}\\big(\\mathrm{i}\\boldsymbol{\\kappa}\\cdot\\widehat{\\boldsymbol{u}\\varphi}\\big)``.
The dealiasing strategy controls the aliasing of the quadratic product: a **mask** strategy
([`TwoThirds`](@ref), [`HouLi`](@ref)) forms the flux once from `u`, `φ`, leaving `û`, `φ̂`, and
`phase_shift` unused — pass `nothing` for `phase_shift` there. [`PhaseShift`](@ref) instead averages it
with the flux recovered on a grid displaced half a cell — using `û`, `φ̂`, and the `phase_shift` scratch
(the run's `buffers.phase_shift`, built only for a `PhaseShift` domain) — before the spherical truncation.

The scalar flux ``\\boldsymbol{u}\\varphi`` reuses the momentum scratch — `product_physical` in physical
representation, `product_spectral` in spectral.
"""
scalar_nonlinear!(nonlinear, û, φ̂, u, φ, domain::FixedDomain, product_physical, product_spectral, phase_shift) =
  _scalar_nonlinear!(domain.dealiasing, nonlinear, û, φ̂, u, φ, domain, product_physical, product_spectral, phase_shift)

# Mask strategies: one flux evaluation, divergence, low-pass — the −1 folds in the −∇· sign.
function _scalar_nonlinear!(::DealiasingStrategy, nonlinear, û, φ̂, u, φ, domain::FixedDomain,
                            product_physical, product_spectral, phase_shift)
  _scalar_flux_divergence!(nonlinear, u, φ, domain, product_physical, product_spectral)
  convolve!(nonlinear, nonlinear, domain.dealias, -1, 0)
  return nonlinear
end

# Phase-shift: average the primary and half-cell-displaced flux divergences (cancels the odd-parity
# aliases), then the spherical truncation (folding in the −∇· sign) removes the two-axis aliases.
function _scalar_nonlinear!(::PhaseShift, nonlinear, û, φ̂, u, φ, domain::FixedDomain,
                            product_physical, product_spectral, phase_shift)
  T = real(eltype(field_data(nonlinear)))
  _scalar_flux_divergence!(nonlinear, u, φ, domain, product_physical, product_spectral)                 # primary ∇·(uφ)
  convolve!(phase_shift.velocity_shifted, û, phase_shift.to_shifted)                                     # û on the displaced grid
  velocity_to_physical!(phase_shift.u_shifted, phase_shift.velocity_shifted, domain, product_spectral)
  convolve!(phase_shift.scalar_shifted, φ̂, phase_shift.to_shifted)                                       # φ̂ on the displaced grid
  scalar_to_physical!(phase_shift.phi_shifted, phase_shift.scalar_shifted, domain, phase_shift.scalar_copy)
  _scalar_flux!(product_spectral, phase_shift.u_shifted, phase_shift.phi_shifted, domain, product_physical)   # (u_s φ_s)^
  convolve!(product_spectral, product_spectral, phase_shift.back)                                        # displaced flux, shifted back
  divergence!(phase_shift.scalar_shifted, product_spectral, domain.multipliers)                          # displaced ∇·
  combine!(nonlinear, T(1 // 2), nonlinear, T(1 // 2), phase_shift.scalar_shifted)                       # average the two grids
  convolve!(nonlinear, nonlinear, domain.dealias, -1, 0)                                                 # spherical truncation, ×−1
  return nonlinear
end

# Raw ∇·(uφ) in spectral representation, no dealiasing.
function _scalar_flux_divergence!(out, u, φ, domain::FixedDomain, product_physical, product_spectral)
  _scalar_flux!(product_spectral, u, φ, domain, product_physical)
  divergence!(out, product_spectral, domain.multipliers)
  return out
end

# The flux uφ (a vector), transformed to spectral, into `flux_spectral`; `flux_physical` holds uφ.
function _scalar_flux!(flux_spectral, u, φ, domain::FixedDomain, flux_physical)
  φ_data = field_data(φ)
  field_data(flux_physical) .= field_data(u) .* reshape(φ_data, size(φ_data)..., 1)
  to_spectral!(flux_spectral, flux_physical, domain.velocity_plans)
  return flux_spectral
end


end # module Generator
