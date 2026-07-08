# TimeIntegration — the pluggable time-marching schemes, as concrete `AbstractIntegrator` subtypes
# dispatched by `step!`. All schemes are of the integrating-factor family: the stiff diffusive part
# is advanced exactly through exp(-diffusivity·|k|²Δt) (built in Dynamics), and the nonlinear term is
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
# filled `buffers.velocity` / `buffers.vorticity_start` with the start-of-step physical velocity and vorticity.

"""
    TimeIntegration

The pluggable time-marching schemes, as concrete `AbstractIntegrator` subtypes dispatched by
[`step!`](@ref), which advances the coupled velocity + passive-scalar state. All are of the
integrating-factor family: the stiff diffusive part is advanced exactly and the nonlinear term
explicitly by a Runge–Kutta stage combination. The default is [`IFLowStorageRK3`](@ref);
[`IFRK2`](@ref) (Heun) is a cheaper two-stage alternative, imaginary-axis unstable;
[`default_integrator`](@ref) returns the default; [`recommended_cfl`](@ref) gives a scheme's
advective-CFL ceiling; [`Physics`](@ref) bundles the problem parameters and forcings.
"""
module TimeIntegration

using GBGPeriodicFields
using ..SimulationState: SimulationDomain, FieldBuffers, _retained_nyquist_fraction
using ..Dynamics: velocity_vorticity!, velocity_nonlinear!, integrating_factor!,
                  scalar_to_physical!, scalar_nonlinear!
using ..Forcing: AbstractForcing, NoForcing, forcing_rate!, apply_forcing!,
                 prepare_forcing!, forcing_source!

export AbstractIntegrator, IFRK2, IFLowStorageRK3, step!,
       recommended_cfl, default_integrator, Physics


"""
    Physics(; viscosity, schmidt = 1.0, velocity_forcing = NoForcing(),
            scalar_forcing = NoForcing())

The problem definition consumed by [`step!`](@ref): the kinematic viscosity ``\\nu`` (`viscosity`),
the Schmidt number ``\\mathrm{Sc}`` (`schmidt`; the scalar diffusivity is ``\\varkappa = \\nu/\\mathrm{Sc}``),
and the velocity and scalar forcing strategies (`velocity_forcing`, `scalar_forcing`, both
`AbstractForcing`).
"""
struct Physics{VF<:AbstractForcing, SF<:AbstractForcing}
  viscosity::Float64
  schmidt::Float64
  velocity_forcing::VF
  scalar_forcing::SF
end

Physics(; viscosity, schmidt = 1.0, velocity_forcing = NoForcing(), scalar_forcing = NoForcing()) =
  Physics(Float64(viscosity), Float64(schmidt), velocity_forcing, scalar_forcing)


"""
    AbstractIntegrator

Supertype of the time-marching schemes. A scheme implements
[`step!`](@ref)`(integrator, û, φ̂, domain, buffers, physics, dt)`, advancing the velocity `û` and the
scalar `φ̂` (both in spectral representation) by one timestep in place, and may specialize
[`recommended_cfl`](@ref).
"""
abstract type AbstractIntegrator end


"""
    step!(integrator, û, φ̂, domain, buffers, physics, dt)

Advance the spectral velocity `û` and passive scalar `φ̂` by one timestep `dt` in place, using the
scheme `integrator`, the domain `domain`, the buffers `buffers`, and the problem `physics` (a
[`Physics`](@ref): viscosity, Schmidt number, and the two forcings). Dispatches on the concrete
`integrator` type (see `IFRK2`, `IFLowStorageRK3`). The caller must have filled `buffers.velocity` and
`buffers.vorticity_start` with the start-of-step physical velocity and vorticity (via
[`velocity_vorticity!`](@ref)).
"""
function step! end


"""
    IFLowStorageRK3()

Integrating-factor third-order low-storage Runge–Kutta (Williamson 2N). With the diffusive
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
lockstep (the same ``A,B,d``), each with its own diffusivity; setting ``D = 0`` recovers the bare
Williamson scheme, and dropping the nonlinearity recovers exact diffusion ``\\mathcal{E}_D(\\Delta t)``.
Three nonlinear evaluations per step, two field registers per field — the default workhorse:
third-order and stable on the imaginary axis (limit ``\\sqrt{3}``), unlike [`IFRK2`](@ref).
"""
struct IFLowStorageRK3 <: AbstractIntegrator end


function step!(::IFLowStorageRK3, û, φ̂, domain::SimulationDomain, buffers::FieldBuffers,
               physics::Physics, dt::Real)
  T = real(eltype(field_data(û)))
  dt_T = T(dt)
  a = (zero(T), T(-5 // 9), T(-153 // 128))
  b = (T(1 // 3), T(15 // 16), T(8 // 15))
  d = (T(1 // 3), T(5 // 12), T(1 // 4))
  ν = physics.viscosity
  κ = physics.viscosity / physics.schmidt
  hu = buffers.stage1                                                             # velocity accumulator
  sb = buffers.scalar                                                             # ScalarBuffers, or nothing
  has_scalar = φ̂ !== nothing

  # per-step forcing state (OU advance) and linear rates, from the start-of-step state
  prepare_forcing!(physics.velocity_forcing, û, domain, buffers, dt)
  velocity_rate = forcing_rate!(physics.velocity_forcing, buffers.velocity_rate, û, domain, buffers) ? buffers.velocity_rate : nothing
  scalar_rate = nothing
  if has_scalar
    prepare_forcing!(physics.scalar_forcing, φ̂, domain, buffers, dt)
    scalar_rate = forcing_rate!(physics.scalar_forcing, sb.rate, φ̂, domain, buffers) ? sb.rate : nothing
  end

  for i in 1:3
    if i == 1
      u, ω = buffers.velocity, buffers.vorticity_start                  # cached start-of-step
    else
      velocity_vorticity!(buffers.velocity_star, buffers.vorticity_physical, û, domain, buffers)
      u, ω = buffers.velocity_star, buffers.vorticity_physical
    end

    velocity_nonlinear!(buffers.nonlinear, u, ω, domain, buffers)          # N̂_u
    forcing_source!(physics.velocity_forcing, buffers.nonlinear, domain, buffers)         # + additive forcing (OU)
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
      scalar_to_physical!(sb.field, φ̂, domain, buffers)                          # φ at the stage state
      scalar_nonlinear!(sb.nonlinear, u, sb.field, domain, buffers)               # N̂_φ (reuses buffers.lamb/buffers.scratch)
      forcing_source!(physics.scalar_forcing, sb.nonlinear, domain, buffers)
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

  apply_forcing!(physics.velocity_forcing, û, domain, buffers.scratch)
  has_scalar && apply_forcing!(physics.scalar_forcing, φ̂, domain, sb.nonlinear)   # scalar-spectral scratch (free here)
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


function step!(::IFRK2, û, φ̂, domain::SimulationDomain, buffers::FieldBuffers,
               physics::Physics, dt::Real)
  T = real(eltype(field_data(û)))
  dt_T = T(dt)
  half = dt_T / 2
  ν = physics.viscosity
  κ = physics.viscosity / physics.schmidt
  sb = buffers.scalar                                                            # ScalarBuffers, or nothing
  has_scalar = φ̂ !== nothing

  # per-step forcing state (OU advance) and linear rates, from the start-of-step state
  prepare_forcing!(physics.velocity_forcing, û, domain, buffers, dt)
  velocity_rate = forcing_rate!(physics.velocity_forcing, buffers.velocity_rate, û, domain, buffers) ? buffers.velocity_rate : nothing
  scalar_rate = nothing
  if has_scalar
    prepare_forcing!(physics.scalar_forcing, φ̂, domain, buffers, dt)
    scalar_rate = forcing_rate!(physics.scalar_forcing, sb.rate, φ̂, domain, buffers) ? sb.rate : nothing
  end

  # stage 1 — nonlinear terms at the start-of-step state
  velocity_nonlinear!(buffers.stage1, buffers.velocity, buffers.vorticity_start, domain, buffers)              # N̂_u,1
  forcing_source!(physics.velocity_forcing, buffers.stage1, domain, buffers)
  if has_scalar
    scalar_to_physical!(sb.field, φ̂, domain, buffers)
    scalar_nonlinear!(sb.stage1, buffers.velocity, sb.field, domain, buffers)            # N̂_φ,1
    forcing_source!(physics.scalar_forcing, sb.stage1, domain, buffers)
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
  velocity_vorticity!(buffers.velocity_star, buffers.vorticity_physical, buffers.velocity_star_spectral, domain, buffers)
  velocity_nonlinear!(buffers.stage2, buffers.velocity_star, buffers.vorticity_physical, domain, buffers)      # N̂_u,2
  forcing_source!(physics.velocity_forcing, buffers.stage2, domain, buffers)
  if has_scalar
    scalar_to_physical!(sb.field, sb.star_spectral, domain, buffers)
    scalar_nonlinear!(sb.stage2, buffers.velocity_star, sb.field, domain, buffers)       # N̂_φ,2
    forcing_source!(physics.scalar_forcing, sb.stage2, domain, buffers)
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

  apply_forcing!(physics.velocity_forcing, û, domain, buffers.scratch)
  has_scalar && apply_forcing!(physics.scalar_forcing, φ̂, domain, sb.nonlinear)
  return û, φ̂
end


"""
    default_integrator()

The recommended default scheme, [`IFLowStorageRK3`](@ref) — third-order, low-storage, and stable on
the imaginary axis (unlike [`IFRK2`](@ref)).
"""
default_integrator() = IFLowStorageRK3()


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
recommended_cfl(integrator::AbstractIntegrator, domain::SimulationDomain) =
  recommended_cfl(integrator) * (2 // 3) / _retained_nyquist_fraction(domain.dealiasing)


end # module TimeIntegration
