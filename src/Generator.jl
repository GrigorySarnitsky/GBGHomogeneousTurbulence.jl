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
- [`ResolvedGenerator`](@ref) — the reified generator: the conditions bundled with the assembly
  scratch its evaluations write through, consumed by a scheme through the protocol below.
- [`prepare!`](@ref) — open a step: advance the forcings' internal state and arm the linear rates.
- [`velocity_rhs!`](@ref), [`scalar_rhs!`](@ref) — assemble the explicit right-hand sides (the
  dealiased, Leray-projected momentum term and the scalar advection, each plus its additive forcing
  source) at a stage state.
- [`velocity_factor!`](@ref), [`scalar_factor!`](@ref) — build each field's exact linear subflow (the
  viscous/diffusive integrating factor, with any linear forcing rate folded in).
- [`finalize!`](@ref) — close a step: apply the post-step forcing projections to the advanced state.

The physical-representation recoveries the assemblies consume
([`velocity_to_physical!`](@ref) and its siblings) live with the state, in
[`State`](@ref GBGIsotropicTurbulence.State).
"""
module Generator

using GBGPeriodicFields
using ..SimulationDomain: FixedDomain, DealiasingStrategy, TwoThirds, HouLi, PhaseShift,
                          spectral_vector, physical_vector, scalar_spectral, scalar_physical,
                          _real_type, _blank, _squared_wavenumber_lazy
using ..State: velocity_to_physical!, vorticity_to_physical!, scalar_to_physical!
using ..Forcing: AbstractForcing, NoForcing,
                 set_forcing_rate!, uses_linear_rate, apply_forcing!, prepare_forcing!,
                 add_forcing_source!

export FlowConditions, ResolvedGenerator,
       prepare!, velocity_rhs!, scalar_rhs!, velocity_factor!, scalar_factor!, finalize!


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


# Phase-shift dealiasing scratch + the two translation kernels (present only when `dealiasing isa
# PhaseShift`). The kernels are built once from the half-cell displacement; the scalar fields are
# `nothing` for a velocity-only run.
struct PhaseShiftBuffers{K, VS, VP, SS, SP}
  to_shifted::K                   # translation kernel: recover a field on the grid displaced by +½ cell
  back::K                         # translation kernel: shift a displaced term back to the grid
  velocity_shifted::VS            # û on the displaced grid, then the displaced nonlinear term
  u_shifted::VP                   # velocity recovered on the displaced grid
  omega_shifted::VP               # vorticity recovered on the displaced grid
  scalar_shifted::SS              # φ̂ on the displaced grid, then the displaced flux divergence (or nothing)
  scalar_copy::SS                 # recovery scratch for the displaced scalar (or nothing)
  phi_shifted::SP                 # scalar recovered on the displaced grid (or nothing)
end

# Build the two translation kernels once (offset = half a cell) and the displaced-evaluation scratch; the
# scalar fields only when a scalar is evolved. A scalar kernel translates a vector or scalar field alike.
function PhaseShiftBuffers(domain::FixedDomain, scalar::Bool)
  δ = 0.5 .* domain.grid.grid_spacing
  reference = scalar_spectral(domain)
  return PhaseShiftBuffers(
    translation_kernel(reference, domain.multipliers, .-δ),   # sample on the +½-cell grid (negated offset)
    translation_kernel(reference, domain.multipliers,   δ),   # shift a displaced term back to the grid
    spectral_vector(domain),
    physical_vector(domain), physical_vector(domain),
    scalar ? scalar_spectral(domain) : nothing,
    scalar ? scalar_spectral(domain) : nothing,
    scalar ? scalar_physical(domain) : nothing,
  )
end


# A rate array exists only for a forcing that declares one — the storage tracks the physics, not the
# possibility of it. A forcing that fills a rate without declaring it would be handed `nothing` and go
# silently unapplied, so that mismatch is a construction-time error rather than a wrong quiet run.
function _forcing_rate(domain::FixedDomain, forcing)
  if !uses_linear_rate(forcing)
    _overrides_rate_hook(forcing) &&
      throw(ArgumentError("$(nameof(typeof(forcing))) implements set_forcing_rate! but does not " *
                          "declare uses_linear_rate(::$(nameof(typeof(forcing)))) = true, so it " *
                          "would be given no rate array to fill and would never be applied"))
    return nothing
  end
  # A real array of spectral-scalar shape on the domain's backend (the shape the armed rate A(κ)
  # multiplies mode by mode), zeroed so an un-set rate acts as no forcing.
  return _blank(domain, _real_type(domain), spectral_field_shape(domain.grid, domain.layout, Val(0)))
end

# Does this forcing define its own `set_forcing_rate!`, rather than inheriting the do-nothing
# fallback? An unresolvable lookup (an ambiguity against the fallback) can only arise from a method
# the forcing itself added, so it answers yes.
_overrides_rate_hook(forcing) =
  try
    which(set_forcing_rate!, Tuple{typeof(forcing), Any, Any, FixedDomain}) !==
      which(set_forcing_rate!, Tuple{AbstractForcing, Any, Any, FixedDomain})
  catch
    true
  end


"""
    ResolvedGenerator(domain, conditions; scalar = false)

The reified right-hand side of the resolved dynamics — the flow's generator as one object: the
[`FlowConditions`](@ref) parameter record together with the assembly scratch its evaluations write
through (the quadratic-product fields, the displaced-evaluation buffers when the domain dealiases by
`PhaseShift`, and the per-mode forcing-rate arrays). A time-marching scheme consumes it through the
generator protocol — [`prepare!`](@ref) once per step, [`velocity_rhs!`](@ref) / [`scalar_rhs!`](@ref)
at each stage state, [`velocity_factor!`](@ref) / [`scalar_factor!`](@ref) for the exact linear
subflows, [`finalize!`](@ref) after the completed step — and itself does only stage arithmetic, so a
scheme can never assemble the right-hand side from a mismatched intermediate state.

Build it on the [`FixedDomain`](@ref) `domain` from the `conditions`; pass `scalar = true` when the run
carries a passive scalar (it allocates the scalar's forcing-rate array, required for a scalar-forced
run). The `Simulation` front door builds one for you.

# Fields
- `conditions` — the [`FlowConditions`](@ref) parameter record (``\\nu``, ``\\mathrm{Sc}``, the forcings).
- `product_physical`, `product_spectral` — the quadratic products in physical and spectral
  representation (the Lamb vector ``\\boldsymbol{u}\\times\\boldsymbol{\\omega}``, and the scalar flux
  ``\\boldsymbol{u}\\varphi``).
- `phase_shift` — the displaced-evaluation scratch and translation kernels (`PhaseShift` dealiasing
  only), else `nothing`.
- `velocity_rate`, `scalar_rate` — the per-mode linear forcing-rate arrays ``A(\\boldsymbol{\\kappa})``
  ([`prepare!`](@ref) fills them). Each is `nothing` unless that field's forcing declares
  `uses_linear_rate`, so a field driven by a post-step projection, a stochastic source, or nothing at
  all carries no rate storage; `scalar_rate` is also `nothing` for a scalar-free generator.
- `velocity_rate_active`, `scalar_rate_active` — whether [`prepare!`](@ref) armed each rate this step.
"""
mutable struct ResolvedGenerator{C<:FlowConditions, PP, PS, PB, RK, SR}
  const conditions::C
  const product_physical::PP
  const product_spectral::PS
  const phase_shift::PB
  const velocity_rate::RK
  const scalar_rate::SR
  velocity_rate_active::Bool
  scalar_rate_active::Bool
end

ResolvedGenerator(domain::FixedDomain, conditions::FlowConditions; scalar::Bool = false) =
  ResolvedGenerator(conditions,
                    physical_vector(domain), spectral_vector(domain),
                    domain.dealiasing isa PhaseShift ? PhaseShiftBuffers(domain, scalar) : nothing,
                    _forcing_rate(domain, conditions.velocity_forcing),
                    scalar ? _forcing_rate(domain, conditions.scalar_forcing) : nothing,
                    false, false)


"""
    prepare!(generator, state, domain, dt)

Open a step of the generator: advance each forcing's internal state once (its per-step
`prepare_forcing!` hook) and arm the per-mode linear forcing rates (its `set_forcing_rate!` hook,
written into the generator's rate arrays) from the start-of-step `state` (a `ResolvedFields`) over the
timestep `dt`, on the [`FixedDomain`](@ref) `domain`. A scheme calls this once before its Runge–Kutta
stages; the stage evaluations and the integrating factors then consume what it prepared. Returns
`generator`.
"""
function prepare!(generator::ResolvedGenerator, state, domain::FixedDomain, dt::Real)
  conditions = generator.conditions
  prepare_forcing!(conditions.velocity_forcing, state.velocity, domain, dt)
  generator.velocity_rate_active = generator.velocity_rate === nothing ? false :
    set_forcing_rate!(conditions.velocity_forcing, generator.velocity_rate, state.velocity, domain)
  if state.scalar !== nothing
    prepare_forcing!(conditions.scalar_forcing, state.scalar, domain, dt)
    generator.scalar_rate_active = generator.scalar_rate === nothing ? false :
      set_forcing_rate!(conditions.scalar_forcing, generator.scalar_rate, state.scalar, domain)
  end
  return generator
end


"""
    finalize!(generator, state, domain)

Close a step of the generator: apply each forcing's post-step projection (its `apply_forcing!` hook —
e.g. the energy rescale of a `BandRescaling`) to the advanced `state`, velocity first, then the scalar
when the run carries one. A scheme calls this once after its final stage, so everything that follows
the step — the diagnostics, the derived observables, the tracer push — sees the forced end-of-step fields.
Returns `state`.
"""
function finalize!(generator::ResolvedGenerator, state, domain::FixedDomain)
  apply_forcing!(generator.conditions.velocity_forcing, state.velocity, domain)
  state.scalar === nothing || apply_forcing!(generator.conditions.scalar_forcing, state.scalar, domain)
  return state
end


"""
    velocity_rhs!(N̂, generator, û, u, ω, domain)

Assemble the explicit right-hand side of the momentum equation into `N̂` — the dealiased,
Leray-projected rotational nonlinear term plus any additive forcing source — from the stage velocity
`û` in spectral representation and its physical velocity `u` and vorticity `ω`, using the
[`ResolvedGenerator`](@ref) `generator`'s conditions and scratch.

In physical space the rotational form writes the convective term as the Lamb vector, through the identity

```math
(\\boldsymbol{u}\\cdot\\nabla)\\boldsymbol{u} = \\nabla\\big(\\tfrac{1}{2}\\lvert\\boldsymbol{u}\\rvert^{2}\\big) - \\boldsymbol{u}\\times\\boldsymbol{\\omega},
```

so that, with the Leray–Helmholtz projection ``\\mathbb{P}`` onto divergence-free fields absorbing the
pressure and the ``\\nabla(\\tfrac{1}{2}\\lvert\\boldsymbol{u}\\rvert^{2})`` gradient, the momentum equation
becomes

```math
\\partial_t\\boldsymbol{u} = \\mathbb{P} (\\boldsymbol{u}\\times\\boldsymbol{\\omega}) + \\nu\\nabla^{2}\\boldsymbol{u} + \\boldsymbol{f}.
```

The term computed is the spectral image of ``\\mathbb{P} (\\boldsymbol{u}\\times\\boldsymbol{\\omega})``,
dealiased by the domain's [`DealiasingStrategy`](@ref), plus the per-stage additive source of the
generator's velocity forcing (its `add_forcing_source!` hook). A **mask** strategy ([`TwoThirds`](@ref),
[`HouLi`](@ref)) forms the term once from `u`, `ω` and multiplies by the low-pass `domain.dealias`,
leaving `û` unused; [`PhaseShift`](@ref) forms it **twice** — from `u`, `ω`, and from the fields
recovered on a grid displaced by half a cell (using `û` and the generator's displaced-evaluation
scratch) — averages the two to cancel the aliasing, then truncates spherically with `domain.dealias`.

Two linear pieces are deliberately **not** in `N̂`: the viscous term and the exactly-linear part of a
forcing are advanced exactly by the integrating factor ([`velocity_factor!`](@ref)). The Lamb vector
and its transform are held in the generator's own product scratch, so the operation allocates nothing.
"""
velocity_rhs!(N̂, generator::ResolvedGenerator, û, u, ω, domain::FixedDomain) =
  (_velocity_nonlinear!(domain.dealiasing, N̂, û, u, ω, domain,
                        generator.product_physical, generator.product_spectral, generator.phase_shift);
   add_forcing_source!(generator.conditions.velocity_forcing, N̂, domain))

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
  # The shift-back and the two-grid average are one α/β convolve — ½·back ⊙ (displaced) + ½·(primary).
  convolve!(nonlinear, phase_shift.velocity_shifted, phase_shift.back, T(1 // 2), T(1 // 2))
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
    velocity_factor!(ℰ, generator, domain, τ)

Write the velocity's exact linear subflow over a substep ``\\tau`` (`τ`) into `ℰ` (a scalar field in
spectral representation). The linear part of the momentum equation — the diffusion
``\\partial_t\\boldsymbol{u} = \\nu\\nabla^{2}\\boldsymbol{u}``, plus any linear forcing rate
``A(\\boldsymbol{\\kappa})`` that [`prepare!`](@ref) armed — is solved exactly in spectral
representation by the per-mode multiplier

```math
\\mathcal{E}(\\boldsymbol{\\kappa}) = \\exp\\!\\big((A(\\boldsymbol{\\kappa}) - \\nu\\lvert\\boldsymbol{\\kappa}\\rvert^{2}) \\tau\\big),
```

with ``A = 0`` when no linear forcing is active, so multiplying a field by `ℰ` advances its viscous
(and linear-forcing) part exactly — machine-exact, with no stability restriction; only a scheme's
explicit stage combination carries truncation error. The [`ResolvedGenerator`](@ref) `generator`
supplies ``\\nu`` and the armed rate; the `domain` (a [`FixedDomain`](@ref)) supplies
``\\lvert\\boldsymbol{\\kappa}\\rvert^{2}`` through its multipliers, evaluated per mode — in spectral
representation ``-\\nabla^{2}`` acts as multiplication by it.
"""
velocity_factor!(ℰ, generator::ResolvedGenerator, domain::FixedDomain, τ::Real) =
  _integrating_factor!(ℰ, domain, generator.conditions.viscosity, τ,
                       generator.velocity_rate_active ? generator.velocity_rate : nothing)


"""
    scalar_factor!(ℰ, generator, domain, τ)

Write the passive scalar's exact linear subflow over a substep ``\\tau`` into `ℰ` — the same per-mode
multiplier as [`velocity_factor!`](@ref) with the scalar diffusivity ``\\varkappa = \\nu/\\mathrm{Sc}``
in place of ``\\nu`` and the scalar forcing's armed linear rate in place of the velocity's.
"""
scalar_factor!(ℰ, generator::ResolvedGenerator, domain::FixedDomain, τ::Real) =
  _integrating_factor!(ℰ, domain, generator.conditions.viscosity / generator.conditions.schmidt, τ,
                       generator.scalar_rate_active ? generator.scalar_rate : nothing)


# The shared kernel of the factor pair: ℰ(κ) = exp((A(κ) − D|κ|²)τ), the exact solution of the
# diffusion ∂ₜf = D∇²f (+ the linear forcing rate A when armed) over τ. The |κ|² enters as the lazy
# per-axis broadcast (nothing field-sized is read or built for it); the whole build goes away with
# the stage-1b `exponential_convolve!` adoption, which applies this factor without materializing it.
function _integrating_factor!(factor, domain::FixedDomain, diffusivity::Real, dt::Real, rate = nothing)
  T = real(eltype(field_data(factor)))
  κ2 = _squared_wavenumber_lazy(domain)
  if rate === nothing
    field_data(factor) .= complex.(exp.(T(-diffusivity * dt) .* κ2))
  else
    field_data(factor) .= complex.(exp.(T(dt) .* (rate .- T(diffusivity) .* κ2)))
  end
  return factor
end


"""
    scalar_rhs!(N̂, generator, û, φ̂, u, φ, domain)

Assemble the explicit right-hand side of the passive-scalar equation into `N̂` — the dealiased
advection term plus any additive forcing source — from the stage velocity `û` and scalar `φ̂` in
spectral representation and their physical `u`, `φ`, using the [`ResolvedGenerator`](@ref)
`generator`'s conditions and scratch.

In conservative form the advection is ``-\\nabla\\cdot(\\boldsymbol{u}\\varphi)`` (equal to
``-\\boldsymbol{u}\\cdot\\nabla\\varphi`` since ``\\nabla\\cdot\\boldsymbol{u} = 0``); the conservative form
conserves the scalar mean exactly — the divergence has no ``\\boldsymbol{\\kappa}=\\boldsymbol 0``
component, and the dealias kernel `domain.dealias` (the sharp ``2/3`` rule by default) leaves that mode
untouched.

It is computed pseudospectrally as
``- \\mathrm{dealias}\\big(\\mathrm{i}\\boldsymbol{\\kappa}\\cdot\\widehat{\\boldsymbol{u}\\varphi}\\big)``,
plus the per-stage additive source of the generator's scalar forcing (its `add_forcing_source!` hook).
The dealiasing strategy controls the aliasing of the quadratic product: a **mask** strategy
([`TwoThirds`](@ref), [`HouLi`](@ref)) forms the flux once from `u`, `φ`, leaving `û` and `φ̂` unused;
[`PhaseShift`](@ref) instead averages it with the flux recovered on a grid displaced half a cell —
using `û`, `φ̂`, and the generator's displaced-evaluation scratch — before the spherical truncation.
The diffusion ``\\varkappa\\nabla^{2}\\varphi`` and the exactly-linear part of a forcing are **not** in
`N̂`: they are advanced exactly by [`scalar_factor!`](@ref).

The scalar flux ``\\boldsymbol{u}\\varphi`` reuses the generator's momentum product scratch, so the
operation allocates nothing.
"""
scalar_rhs!(N̂, generator::ResolvedGenerator, û, φ̂, u, φ, domain::FixedDomain) =
  (_scalar_nonlinear!(domain.dealiasing, N̂, û, φ̂, u, φ, domain,
                      generator.product_physical, generator.product_spectral, generator.phase_shift);
   add_forcing_source!(generator.conditions.scalar_forcing, N̂, domain))

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
  divergence!(phase_shift.scalar_shifted, product_spectral, domain.multipliers)                          # displaced ∇·, still on the displaced grid
  # The shift-back symbol commutes through the iκ· contraction (iκ·(ĝ v̂) = ĝ (iκ·v̂)), so it rides
  # the averaging convolve — ½·back ⊙ (displaced ∇·) + ½·(primary ∇·) — one pass, not shift + combine.
  convolve!(nonlinear, phase_shift.scalar_shifted, phase_shift.back, T(1 // 2), T(1 // 2))
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
