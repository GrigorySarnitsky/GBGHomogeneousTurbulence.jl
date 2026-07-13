# Propagator — the interchangeable time-marching schemes, as concrete `AbstractIntegrator` subtypes
# dispatched by `step!`. All schemes are of the integrating-factor family: the stiff diffusive part
# is advanced exactly through exp(-diffusivity·|k|²Δt) (built in Generator), and the nonlinear term is
# advanced explicitly by a Runge–Kutta stage combination.
#
# `step!` advances the velocity û and the passive scalar φ̂ *together* through the same RK stages: the
# scalar is passive, so the only time-accurate coupling is to evaluate both nonlinear terms at each
# stage's state — the velocity rotated by its viscous integrating factor E_ν, the scalar by its
# diffusive one E_κ (κ = ν/Sc), both reaching the same lab time each substep. Advancing velocity
# fully and then the scalar would drop the substage velocities and degrade the coupling to first order.
#
# IFLowStorageRK3 (Williamson 2N) is the default workhorse; IFRK2 (Heun) is a cheaper option that is
# only marginally stable for advection (see its docstring). Each `step!` assumes the caller has
# filled `buffers.velocity_physical` / `buffers.vorticity_start` with the start-of-step physical velocity and vorticity.

"""
    Propagator

The interchangeable time-marching schemes, concrete `AbstractIntegrator` subtypes dispatched by
[`step!`](@ref), which advances the coupled velocity + passive-scalar state; a run chooses one as the
`integrator` of its `Simulation`. All are of the
integrating-factor family: the stiff diffusive part is advanced exactly and the nonlinear term
explicitly by a Runge–Kutta stage combination. The default is [`IFLowStorageRK3`](@ref);
[`IFRK2`](@ref) (Heun) is a cheaper two-stage alternative, imaginary-axis unstable;
[`recommended_cfl`](@ref) gives a scheme's
advective-CFL ceiling; [`FlowConditions`](@ref) bundles the problem parameters and forcings.
"""
module Propagator

using GBGPeriodicFields
using ..SimulationDomain: FixedDomain, _retained_nyquist_fraction,
                          spectral_vector, physical_vector, scalar_spectral, scalar_physical
using ..Generator: velocity_to_physical!, vorticity_to_physical!, velocity_nonlinear!, integrating_factor!,
                  scalar_to_physical!, scalar_nonlinear!, FlowConditions
using ..Forcing: set_forcing_rate!, apply_forcing!, prepare_forcing!, add_forcing_source!

export AbstractIntegrator, IFRK2, IFLowStorageRK3, IntegratorBuffers, allocate_buffers, step!,
       recommended_cfl


"""
    AbstractIntegrator

Supertype of the time-marching schemes. A scheme implements
[`step!`](@ref)`(integrator, û, φ̂, domain, buffers, conditions, dt)`, advancing the velocity `û` and the
scalar `φ̂` (both in spectral representation) by one timestep in place, and may specialize
[`recommended_cfl`](@ref).
"""
abstract type AbstractIntegrator end


# The passive-scalar step buffers — held by `IntegratorBuffers` only when a scalar is evolved,
# `nothing` otherwise (so a velocity-only run allocates none of them).
struct ScalarBuffers{SS, SP, RK}
  stage1::SS
  stage2::SS
  star_spectral::SS
  nonlinear::SS
  copy::SS
  field::SP
  rate::RK                       # per-mode linear forcing rate for φ, folded into E_κ
end


"""
    IntegratorBuffers(domain; scalar = false)

The preallocated per-step scratch the integrator writes into, sized so a step allocates no field-sized
memory. Build it per scheme with [`allocate_buffers`](@ref), which dispatches on the concrete `integrator`.

Its fields — the shared right-hand-side scratch every scheme needs:
- `velocity_copy`, `vorticity_spectral` — spectral working space the physical velocity/vorticity
  recovery consumes.
- `product_physical`, `product_spectral` — the physical and spectral quadratic products (the Lamb
  vector, and the scalar flux ``\\boldsymbol{u}\\varphi``).
- `velocity_physical`, `vorticity_start`, `vorticity_physical`, `velocity_star`,
  `velocity_star_spectral` — the start-of-step and substage physical velocity/vorticity registers.
- `nonlinear`, `integrating_factor`, `velocity_rate` — the assembled nonlinear term, the shared viscous
  integrating factor, and the velocity's per-mode linear-forcing-rate array ``A(\\boldsymbol{\\kappa})``.
- `stage1`, `stage2` — the Runge–Kutta stage registers.
- `scalar` — a nested `ScalarBuffers` for the passive scalar ``\\varphi`` when `scalar = true`, else
  `nothing`; when `nothing`, the run evolves no scalar and none of its field-sized buffers are allocated.

# Arguments
- `domain` — the [`FixedDomain`](@ref) the buffers are sized (`similar`) to.
- `scalar = false` — whether to allocate the nested `ScalarBuffers` for a passive scalar.
"""
struct IntegratorBuffers{VS, SS, VP, RK, SB}
  vorticity_spectral::VS
  stage1::VS
  stage2::VS
  velocity_star_spectral::VS
  velocity_copy::VS
  product_spectral::VS
  nonlinear::VS
  integrating_factor::SS
  velocity_physical::VP
  vorticity_start::VP
  vorticity_physical::VP
  velocity_star::VP
  product_physical::VP
  velocity_rate::RK              # per-mode linear forcing rate A(k) (real), folded into E_ν
  scalar::SB                     # ScalarBuffers, or nothing when no passive scalar is evolved
end


_forcing_rate(domain::FixedDomain) =
  fill!(similar(domain.squared_wavenumber), zero(eltype(domain.squared_wavenumber)))

ScalarBuffers(domain::FixedDomain) = ScalarBuffers(
  scalar_spectral(domain), scalar_spectral(domain), scalar_spectral(domain),
  scalar_spectral(domain), scalar_spectral(domain),
  scalar_physical(domain),
  _forcing_rate(domain),
)

function IntegratorBuffers(domain::FixedDomain; scalar::Bool = false)
  return IntegratorBuffers(
    spectral_vector(domain), spectral_vector(domain), spectral_vector(domain),
    spectral_vector(domain), spectral_vector(domain), spectral_vector(domain), spectral_vector(domain),
    scalar_spectral(domain),
    physical_vector(domain), physical_vector(domain), physical_vector(domain),
    physical_vector(domain), physical_vector(domain),
    _forcing_rate(domain),
    scalar ? ScalarBuffers(domain) : nothing,
  )
end


"""
    allocate_buffers(integrator, domain; scalar = false) -> IntegratorBuffers

Allocate the [`IntegratorBuffers`](@ref) a step needs, dispatching on the concrete `integrator` so each
scheme allocates exactly its working set (currently the same for every scheme). The run layer calls this
when assembling a `Simulation`; to build buffers directly, use the `IntegratorBuffers(domain; scalar)`
constructor.
"""
allocate_buffers(::AbstractIntegrator, domain::FixedDomain; scalar::Bool = false) =
  IntegratorBuffers(domain; scalar)


"""
    step!(integrator, û, φ̂, domain, buffers, conditions, dt)

Advance the spectral velocity `û` and passive scalar `φ̂` by one timestep `dt` in place, using the
scheme `integrator`, the domain `domain`, the buffers `buffers`, and the problem `conditions` (a
[`FlowConditions`](@ref): viscosity, Schmidt number, and the two forcings). Dispatches on the concrete
`integrator` type (see `IFRK2`, `IFLowStorageRK3`). The caller must have filled `buffers.velocity_physical` and
`buffers.vorticity_start` with the start-of-step physical velocity and vorticity (via
[`velocity_to_physical!`](@ref) and [`vorticity_to_physical!`](@ref)).
"""
function step! end


"""
    IFLowStorageRK3()

Integrating-factor third-order low-storage Runge–Kutta (Williamson 1980, 2N-storage). With the diffusive
integrating factor ``\\mathcal{E}_D(\\tau)`` built by [`integrating_factor!`](@ref) over a substep
interval ``\\tau`` (``D = \\nu`` for the velocity, ``\\varkappa = \\nu/\\mathrm{Sc}`` for the scalar)
and ``\\widehat{\\boldsymbol{N}}`` the de-aliased nonlinearity of each field, the step carries a state
``\\hat q`` and a single accumulator
``\\boldsymbol{h}`` through three stages ``i = 1,2,3``,

```math
\\begin{aligned}
\\boldsymbol{h} &\\leftarrow A_i\\,\\boldsymbol{h} + \\Delta t\\,\\widehat{\\boldsymbol{N}}(\\hat q), \\\\
\\hat q &\\leftarrow \\hat q + B_i\\,\\boldsymbol{h}, \\\\
\\hat q &\\leftarrow \\mathcal{E}_D(d_i\\Delta t)\\,\\hat q, \\\\
\\boldsymbol{h} &\\leftarrow \\mathcal{E}_D(d_i\\Delta t)\\,\\boldsymbol{h},
\\end{aligned}
```

with ``A = (0, -5/9, -153/128)``, ``B = (1/3, 15/16, 8/15)``, and node increments
``d = (1/3, 5/12, 1/4)`` (abscissae ``c = (0, 1/3, 3/4)``). The velocity and scalar are advanced in
lockstep (the same ``A,B,d``), each with its own diffusivity.
Three nonlinear evaluations per step, two field registers per field — the default workhorse:
third-order and stable on the imaginary axis (limit ``\\sqrt{3}``), unlike [`IFRK2`](@ref).
"""
struct IFLowStorageRK3 <: AbstractIntegrator end


function step!(::IFLowStorageRK3, û, φ̂, domain::FixedDomain, buffers::IntegratorBuffers,
               conditions::FlowConditions, dt::Real)
  T = real(eltype(field_data(û)))
  dt_T = T(dt)
  a = (zero(T), T(-5 // 9), T(-153 // 128))
  b = (T(1 // 3), T(15 // 16), T(8 // 15))
  d = (T(1 // 3), T(5 // 12), T(1 // 4))
  ν = conditions.viscosity
  κ = conditions.viscosity / conditions.schmidt
  hu = buffers.stage1                                                             # velocity accumulator
  sb = buffers.scalar                                                             # ScalarBuffers, or nothing
  has_scalar = φ̂ !== nothing

  # per-step forcing state (OU advance) and linear rates, from the start-of-step state
  prepare_forcing!(conditions.velocity_forcing, û, domain, buffers, dt)
  velocity_rate = set_forcing_rate!(conditions.velocity_forcing, buffers.velocity_rate, û, domain, buffers) ? buffers.velocity_rate : nothing
  scalar_rate = nothing
  if has_scalar
    prepare_forcing!(conditions.scalar_forcing, φ̂, domain, buffers, dt)
    scalar_rate = set_forcing_rate!(conditions.scalar_forcing, sb.rate, φ̂, domain, buffers) ? sb.rate : nothing
  end

  for i in 1:3
    if i == 1
      u, ω = buffers.velocity_physical, buffers.vorticity_start                  # cached start-of-step
    else
      velocity_to_physical!(buffers.velocity_star, û, domain, buffers.velocity_copy)
      vorticity_to_physical!(buffers.vorticity_physical, û, domain, buffers.vorticity_spectral)
      u, ω = buffers.velocity_star, buffers.vorticity_physical
    end

    velocity_nonlinear!(buffers.nonlinear, u, ω, domain, buffers.product_physical, buffers.product_spectral)          # N̂_u
    add_forcing_source!(conditions.velocity_forcing, buffers.nonlinear, domain, buffers)         # + additive forcing (OU)
    if i == 1
      multiply!(hu, dt_T, buffers.nonlinear)                                      # A₁ = 0
    else
      combine!(hu, a[i], hu, dt_T, buffers.nonlinear)                             # hu ← Aᵢ hu + Δt N̂_u
    end
    combine!(û, one(T), û, b[i], hu)                                       # ûᵢ ← ûᵢ + Bᵢ hu
    integrating_factor!(buffers.integrating_factor, domain, ν, d[i] * dt, velocity_rate)   # E_ν(dᵢΔt)
    convolve!(û, û, buffers.integrating_factor)
    i < 3 && convolve!(hu, hu, buffers.integrating_factor)

    # The passive scalar rides the same stages (skipped, with its buffers unallocated, when absent).
    # `u` and `φ̂` are untouched above, so this is bit-identical to advancing them together.
    if has_scalar
      hφ = sb.stage1                                                              # scalar accumulator
      scalar_to_physical!(sb.field, φ̂, domain, sb.copy)                          # φ at the stage state
      scalar_nonlinear!(sb.nonlinear, u, sb.field, domain, buffers.product_physical, buffers.product_spectral)               # N̂_φ (reuses buffers.product_physical/buffers.product_spectral)
      add_forcing_source!(conditions.scalar_forcing, sb.nonlinear, domain, buffers)
      if i == 1
        multiply!(hφ, dt_T, sb.nonlinear)
      else
        combine!(hφ, a[i], hφ, dt_T, sb.nonlinear)
      end
      combine!(φ̂, one(T), φ̂, b[i], hφ)
      integrating_factor!(buffers.integrating_factor, domain, κ, d[i] * dt, scalar_rate)     # E_κ(dᵢΔt)
      convolve!(φ̂, φ̂, buffers.integrating_factor)
      i < 3 && convolve!(hφ, hφ, buffers.integrating_factor)
    end
  end

  apply_forcing!(conditions.velocity_forcing, û, domain, buffers.product_spectral)
  has_scalar && apply_forcing!(conditions.scalar_forcing, φ̂, domain, sb.nonlinear)   # scalar-spectral scratch (free here)
  return û, φ̂
end


"""
    IFRK2()

Integrating-factor second-order Runge–Kutta (Heun). With the velocity and scalar integrating
factors ``\\mathcal{E}_\\nu`` and ``\\mathcal{E}_\\varkappa`` (the diffusive kernel of
[`integrating_factor!`](@ref) at ``D = \\nu`` and ``D = \\varkappa = \\nu/\\mathrm{Sc}`` over the step
``\\Delta t``) and ``\\widehat{\\boldsymbol{N}}`` each field's de-aliased nonlinearity, one step of a
field ``\\hat q`` with
integrating factor ``\\mathcal{E}`` is

```math
\\begin{aligned}
\\hat q^{*} &= \\mathcal{E}\\,(\\hat q_n + \\Delta t\\,\\widehat{\\boldsymbol{N}}_1), \\\\
\\hat q_{n+1} &= \\mathcal{E}\\,\\hat q_n + \\tfrac{\\Delta t}{2}\\big(\\mathcal{E}\\,\\widehat{\\boldsymbol{N}}_1 + \\widehat{\\boldsymbol{N}}_2\\big),
\\end{aligned}
```

with ``\\widehat{\\boldsymbol{N}}_1`` at ``\\hat q_n`` and ``\\widehat{\\boldsymbol{N}}_2`` at the predictor
``\\hat q^{*}``; velocity and scalar use ``\\mathcal{E}_\\nu`` and ``\\mathcal{E}_\\varkappa``
respectively, then the forcings are applied. Two nonlinear evaluations per step.

!!! note
    Every second-order two-stage explicit Runge–Kutta has stability function
    ``R(z) = 1 + z + z^{2}/2``, for which ``\\lvert R(\\mathrm{i}y)\\rvert^{2} = 1 + y^{4}/4 > 1``: the
    scheme is unstable on the imaginary axis, so it is stable only where the viscous damping of the
    integrating factor dominates. It is adequate
    for well-resolved, modest-Reynolds-number runs but is **not** the default — prefer
    [`IFLowStorageRK3`](@ref) for high Reynolds number or marginal resolution.
"""
struct IFRK2 <: AbstractIntegrator end


function step!(::IFRK2, û, φ̂, domain::FixedDomain, buffers::IntegratorBuffers,
               conditions::FlowConditions, dt::Real)
  T = real(eltype(field_data(û)))
  dt_T = T(dt)
  half = dt_T / 2
  ν = conditions.viscosity
  κ = conditions.viscosity / conditions.schmidt
  sb = buffers.scalar                                                            # ScalarBuffers, or nothing
  has_scalar = φ̂ !== nothing

  # per-step forcing state (OU advance) and linear rates, from the start-of-step state
  prepare_forcing!(conditions.velocity_forcing, û, domain, buffers, dt)
  velocity_rate = set_forcing_rate!(conditions.velocity_forcing, buffers.velocity_rate, û, domain, buffers) ? buffers.velocity_rate : nothing
  scalar_rate = nothing
  if has_scalar
    prepare_forcing!(conditions.scalar_forcing, φ̂, domain, buffers, dt)
    scalar_rate = set_forcing_rate!(conditions.scalar_forcing, sb.rate, φ̂, domain, buffers) ? sb.rate : nothing
  end

  # stage 1 — nonlinear terms at the start-of-step state
  velocity_nonlinear!(buffers.stage1, buffers.velocity_physical, buffers.vorticity_start, domain, buffers.product_physical, buffers.product_spectral)              # N̂_u,1
  add_forcing_source!(conditions.velocity_forcing, buffers.stage1, domain, buffers)
  if has_scalar
    scalar_to_physical!(sb.field, φ̂, domain, sb.copy)
    scalar_nonlinear!(sb.stage1, buffers.velocity_physical, sb.field, domain, buffers.product_physical, buffers.product_spectral)            # N̂_φ,1
    add_forcing_source!(conditions.scalar_forcing, sb.stage1, domain, buffers)
  end

  # predictors û*, φ̂*
  integrating_factor!(buffers.integrating_factor, domain, ν, dt, velocity_rate)                 # E_ν
  combine!(buffers.velocity_star_spectral, one(T), û, dt_T, buffers.stage1)                      # û* ← ûₙ + Δt N̂_u,1
  convolve!(buffers.velocity_star_spectral, buffers.velocity_star_spectral, buffers.integrating_factor)
  if has_scalar
    integrating_factor!(buffers.integrating_factor, domain, κ, dt, scalar_rate)                 # E_κ
    combine!(sb.star_spectral, one(T), φ̂, dt_T, sb.stage1)                                       # φ̂* ← φ̂ₙ + Δt N̂_φ,1
    convolve!(sb.star_spectral, sb.star_spectral, buffers.integrating_factor)
  end

  # stage 2 — nonlinear terms at the predictor state
  velocity_to_physical!(buffers.velocity_star, buffers.velocity_star_spectral, domain, buffers.velocity_copy)
  vorticity_to_physical!(buffers.vorticity_physical, buffers.velocity_star_spectral, domain, buffers.vorticity_spectral)
  velocity_nonlinear!(buffers.stage2, buffers.velocity_star, buffers.vorticity_physical, domain, buffers.product_physical, buffers.product_spectral)      # N̂_u,2
  add_forcing_source!(conditions.velocity_forcing, buffers.stage2, domain, buffers)
  if has_scalar
    scalar_to_physical!(sb.field, sb.star_spectral, domain, sb.copy)
    scalar_nonlinear!(sb.stage2, buffers.velocity_star, sb.field, domain, buffers.product_physical, buffers.product_spectral)       # N̂_φ,2
    add_forcing_source!(conditions.scalar_forcing, sb.stage2, domain, buffers)
  end

  # velocity update: ûₙ₊₁ = E_ν ûₙ + (Δt/2)(E_ν N̂_u,1 + N̂_u,2)
  integrating_factor!(buffers.integrating_factor, domain, ν, dt, velocity_rate)
  convolve!(buffers.stage1, buffers.stage1, buffers.integrating_factor)
  convolve!(û, û, buffers.integrating_factor)
  combine!(û, one(T), û, half, buffers.stage1)                                             # ûₙ₊₁ += (Δt/2)(E_ν N̂_u,1 + N̂_u,2)
  combine!(û, one(T), û, half, buffers.stage2)

  # scalar update: φ̂ₙ₊₁ = E_κ φ̂ₙ + (Δt/2)(E_κ N̂_φ,1 + N̂_φ,2)
  if has_scalar
    integrating_factor!(buffers.integrating_factor, domain, κ, dt, scalar_rate)
    convolve!(sb.stage1, sb.stage1, buffers.integrating_factor)
    convolve!(φ̂, φ̂, buffers.integrating_factor)
    combine!(φ̂, one(T), φ̂, half, sb.stage1)                                  # φ̂ₙ₊₁ += (Δt/2)(E_κ N̂_φ,1 + N̂_φ,2)
    combine!(φ̂, one(T), φ̂, half, sb.stage2)
  end

  apply_forcing!(conditions.velocity_forcing, û, domain, buffers.product_spectral)
  has_scalar && apply_forcing!(conditions.scalar_forcing, φ̂, domain, sb.nonlinear)
  return û, φ̂
end


"""
    recommended_cfl(integrator)
    recommended_cfl(integrator, domain)

A conservative advective-CFL ceiling ``C`` for the scheme, for a timestep
``\\Delta t = C\\,\\Delta x / \\max_i\\lvert u_i\\rvert``.

The advective eigenvalues of the de-aliased system are imaginary, of magnitude up to
``\\kappa_{\\max}\\max\\lvert\\boldsymbol{u}\\rvert``; stability needs this times ``C`` to stay within the
scheme's imaginary-axis stability limit ``y_{\\mathrm{s}}``. The one-argument form returns the value
calibrated for the ``2/3`` rule (``\\kappa_{\\max}\\Delta x = 2\\pi/3 \\approx 2.09``): for
[`IFLowStorageRK3`](@ref) ``y_{\\mathrm{s}} = \\sqrt{3}`` gives ``C \\lesssim 0.83``, taken
conservatively as ``0.5``; [`IFRK2`](@ref) is imaginary-axis unstable (``y_{\\mathrm{s}} = 0``,
relying on viscous damping), so a small ``0.25``.

The two-argument form scales that ceiling by the domain's de-aliasing: a strategy that keeps modes
to a higher ``\\kappa_{\\max}`` (e.g. `HouLi`, out to the Nyquist wavenumber) takes a
proportionally smaller step, ``C \\propto 1/\\kappa_{\\max}``. This is the value `Simulation` uses.
Override either for a specific run.
"""
recommended_cfl(::AbstractIntegrator) = 0.3
recommended_cfl(::IFRK2) = 0.25
recommended_cfl(::IFLowStorageRK3) = 0.5

# Scale the base (2/3-calibrated) ceiling by the active de-aliasing: factor = (2/3)/f, f the retained
# Nyquist fraction (1 for TwoThirds ⇒ unchanged, 2/3 for HouLi ⇒ ×2/3, since it keeps modes to Nyquist).
recommended_cfl(integrator::AbstractIntegrator, domain::FixedDomain) =
  recommended_cfl(integrator) * (2 // 3) / _retained_nyquist_fraction(domain.dealiasing)


end # module Propagator
