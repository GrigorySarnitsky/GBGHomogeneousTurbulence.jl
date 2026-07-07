# TimeIntegration — the pluggable time-marching schemes, as concrete `AbstractIntegrator` subtypes
# dispatched by `step!`. All schemes are of the integrating-factor family: the stiff diffusive part
# is advanced exactly through exp(-diffusivity·|k|²Δt) (built in Equations), and the nonlinear term is
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
# filled `ws.velocity` / `ws.vorticity_start` with the start-of-step physical velocity and vorticity.

"""
    TimeIntegration

The pluggable time-marching schemes, as concrete `AbstractIntegrator` subtypes dispatched by
[`step!`](@ref), which advances the coupled velocity + passive-scalar state. All are of the
integrating-factor family: the stiff diffusive part is advanced exactly and the nonlinear term
explicitly by a Runge–Kutta stage combination. The default is [`IFLowStorageRK3`](@ref);
[`recommended_cfl`](@ref) gives a scheme's advective-CFL ceiling; [`Physics`](@ref) bundles the
problem parameters and forcings.
"""
module TimeIntegration

using GBGPeriodicFields
using ..SimulationState: SpectralOperators, Workspace, _retained_nyquist_fraction
using ..Equations: velocity_vorticity!, velocity_nonlinear!, integrating_factor!,
                   scalar_to_physical!, scalar_nonlinear!
using ..Forcing: AbstractForcing, NoForcing, forcing_rate!, apply_forcing!,
                 prepare_forcing!, forcing_source!

export AbstractIntegrator, IFRK2, IFLowStorageRK3, step!,
       recommended_cfl, default_integrator, Physics


"""
    Physics(; viscosity, schmidt = 1.0, velocity_forcing = NoForcing(), scalar_forcing = NoForcing())

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
[`step!`](@ref)`(integrator, uh, phih, ops, ws, physics, dt)`, advancing the velocity `uh` and the
scalar `phih` (both in spectral representation) by one timestep in place, and may specialize
[`recommended_cfl`](@ref).
"""
abstract type AbstractIntegrator end


"""
    step!(integrator, uh, phih, ops, ws, physics, dt)

Advance the spectral velocity `uh` and passive scalar `phih` by one timestep `dt` in place, using the
scheme `integrator`, the operators `ops`, the workspace `ws`, and the problem `physics` (a
[`Physics`](@ref): viscosity, Schmidt number, and the two forcings). Dispatches on the concrete
`integrator` type (see `IFRK2`, `IFLowStorageRK3`). The caller must have filled `ws.velocity` and
`ws.vorticity_start` with the start-of-step physical velocity and vorticity (via
[`velocity_vorticity!`](@ref)).
"""
function step! end


"""
    IFLowStorageRK3()

Integrating-factor third-order low-storage Runge–Kutta (Williamson 2N). With the per-substep
integrating factor ``\\mathcal{E}_D(\\tau) = \\exp(-D\\lvert\\boldsymbol{\\kappa}\\rvert^{2}\\tau)`` (``D = \\nu``
for the velocity, ``\\varkappa = \\nu/\\mathrm{Sc}`` for the scalar) and ``\\widehat{\\boldsymbol{N}}`` the
de-aliased nonlinearity of each field, the step carries a state ``\\hat q`` and a single accumulator
``\\boldsymbol{h}`` through three stages ``i = 1,2,3``,

```math
\\boldsymbol{h} \\leftarrow A_i\\,\\boldsymbol{h} + \\Delta t\\,\\widehat{\\boldsymbol{N}}(\\hat q),
\\qquad
\\hat q \\leftarrow \\hat q + B_i\\,\\boldsymbol{h},
\\qquad
\\hat q \\leftarrow \\mathcal{E}_D(d_i\\Delta t)\\,\\hat q,
\\quad
\\boldsymbol{h} \\leftarrow \\mathcal{E}_D(d_i\\Delta t)\\,\\boldsymbol{h},
```

with ``A = (0, -5/9, -153/128)``, ``B = (1/3, 15/16, 8/15)``, and node increments
``d = (1/3, 5/12, 1/4)`` (abscissae ``c = (0, 1/3, 3/4)``). The velocity and scalar are advanced in
lockstep (the same ``A,B,d``), each with its own diffusivity; setting ``D = 0`` recovers the bare
Williamson scheme, and dropping the nonlinearity recovers exact diffusion ``\\mathcal{E}_D(\\Delta t)``.
Three nonlinear evaluations per step, two field registers per field — the default workhorse:
third-order and stable on the imaginary axis (limit ``\\sqrt{3}``), unlike [`IFRK2`](@ref).
"""
struct IFLowStorageRK3 <: AbstractIntegrator end


function step!(::IFLowStorageRK3, uh, phih, ops::SpectralOperators, ws::Workspace,
               physics::Physics, dt::Real)
  T = real(eltype(field_data(uh)))
  dt_T = T(dt)
  a = (zero(T), T(-5 // 9), T(-153 // 128))
  b = (T(1 // 3), T(15 // 16), T(8 // 15))
  d = (T(1 // 3), T(5 // 12), T(1 // 4))
  ν = physics.viscosity
  κ = physics.viscosity / physics.schmidt
  hu = ws.stage1                                                             # velocity accumulator
  hφ = ws.scalar_stage1                                                      # scalar accumulator

  # per-step forcing state (OU advance) and linear rates, from the start-of-step state
  prepare_forcing!(physics.velocity_forcing, uh, ops, ws, dt)
  prepare_forcing!(physics.scalar_forcing, phih, ops, ws, dt)
  velocity_rate = forcing_rate!(physics.velocity_forcing, ws.velocity_rate, uh, ops, ws) ? ws.velocity_rate : nothing
  scalar_rate = forcing_rate!(physics.scalar_forcing, ws.scalar_rate, phih, ops, ws) ? ws.scalar_rate : nothing

  for i in 1:3
    if i == 1
      velocity, vorticity = ws.velocity, ws.vorticity_start                  # cached start-of-step
    else
      velocity_vorticity!(ws.velocity_star, ws.vorticity_physical, uh, ops, ws)
      velocity, vorticity = ws.velocity_star, ws.vorticity_physical
    end
    scalar_to_physical!(ws.scalar_field, phih, ops, ws)                      # φ at the stage state

    velocity_nonlinear!(ws.nonlinear, velocity, vorticity, ops, ws)          # N̂_u
    forcing_source!(physics.velocity_forcing, ws.nonlinear, ops, ws)         # + additive forcing (OU)
    scalar_nonlinear!(ws.scalar_nonlinear, velocity, ws.scalar_field, ops, ws)  # N̂_φ (reuses ws.lamb/ws.scratch)
    forcing_source!(physics.scalar_forcing, ws.scalar_nonlinear, ops, ws)

    if i == 1
      field_data(hu) .= dt_T .* field_data(ws.nonlinear)                     # A₁ = 0
      field_data(hφ) .= dt_T .* field_data(ws.scalar_nonlinear)
    else
      field_data(hu) .= a[i] .* field_data(hu) .+ dt_T .* field_data(ws.nonlinear)
      field_data(hφ) .= a[i] .* field_data(hφ) .+ dt_T .* field_data(ws.scalar_nonlinear)
    end
    field_data(uh) .+= b[i] .* field_data(hu)
    field_data(phih) .+= b[i] .* field_data(hφ)

    integrating_factor!(ws.integrating_factor, ops, ν, d[i] * dt, velocity_rate)   # E_ν(dᵢΔt)
    convolve!(uh, uh, ws.integrating_factor)
    i < 3 && convolve!(hu, hu, ws.integrating_factor)
    integrating_factor!(ws.integrating_factor, ops, κ, d[i] * dt, scalar_rate)     # E_κ(dᵢΔt)
    convolve!(phih, phih, ws.integrating_factor)
    i < 3 && convolve!(hφ, hφ, ws.integrating_factor)
  end

  apply_forcing!(physics.velocity_forcing, uh, ops, ws.scratch)
  apply_forcing!(physics.scalar_forcing, phih, ops, ws.scalar_nonlinear)    # scalar-spectral scratch (free here)
  return uh, phih
end


"""
    IFRK2()

Integrating-factor second-order Runge–Kutta (Heun). With the integrating factors
``\\mathcal{E}_\\nu = \\exp(-\\nu\\lvert\\boldsymbol{\\kappa}\\rvert^{2}\\Delta t)`` and
``\\mathcal{E}_\\varkappa = \\exp(-\\varkappa\\lvert\\boldsymbol{\\kappa}\\rvert^{2}\\Delta t)`` and
``\\widehat{\\boldsymbol{N}}`` each field's de-aliased nonlinearity, one step of a field ``\\hat q`` with
integrating factor ``\\mathcal{E}`` is

```math
\\hat q^{*} = \\mathcal{E}\\,(\\hat q_n + \\Delta t\\,\\widehat{\\boldsymbol{N}}_1),
\\qquad
\\hat q_{n+1} = \\mathcal{E}\\,\\hat q_n + \\tfrac{\\Delta t}{2}\\big(\\mathcal{E}\\,\\widehat{\\boldsymbol{N}}_1 + \\widehat{\\boldsymbol{N}}_2\\big),
```

with ``\\widehat{\\boldsymbol{N}}_1`` at ``\\hat q_n`` and ``\\widehat{\\boldsymbol{N}}_2`` at the predictor
``\\hat q^{*}``; velocity and scalar use ``\\mathcal{E}_\\nu`` and ``\\mathcal{E}_\\varkappa``
respectively, then the forcings are applied. Two nonlinear evaluations per step.

!!! note
    Every two-stage explicit Runge–Kutta has stability function ``R(z) = 1 + z + z^{2}/2``, for which
    ``\\lvert R(iy)\\rvert^{2} = 1 + y^{4}/4 > 1``: the scheme is unstable on the imaginary axis, so
    it is stable only where the viscous damping of the integrating factor dominates. It is adequate
    for well-resolved, modest-Reynolds-number runs but is **not** the default — prefer
    [`IFLowStorageRK3`](@ref) for high Reynolds number or marginal resolution.
"""
struct IFRK2 <: AbstractIntegrator end


function step!(::IFRK2, uh, phih, ops::SpectralOperators, ws::Workspace,
               physics::Physics, dt::Real)
  T = real(eltype(field_data(uh)))
  dt_T = T(dt)
  half = dt_T / 2
  ν = physics.viscosity
  κ = physics.viscosity / physics.schmidt

  # per-step forcing state (OU advance) and linear rates, from the start-of-step state
  prepare_forcing!(physics.velocity_forcing, uh, ops, ws, dt)
  prepare_forcing!(physics.scalar_forcing, phih, ops, ws, dt)
  velocity_rate = forcing_rate!(physics.velocity_forcing, ws.velocity_rate, uh, ops, ws) ? ws.velocity_rate : nothing
  scalar_rate = forcing_rate!(physics.scalar_forcing, ws.scalar_rate, phih, ops, ws) ? ws.scalar_rate : nothing

  # stage 1 — nonlinear terms at the start-of-step state
  scalar_to_physical!(ws.scalar_field, phih, ops, ws)
  velocity_nonlinear!(ws.stage1, ws.velocity, ws.vorticity_start, ops, ws)              # N̂_u,1
  forcing_source!(physics.velocity_forcing, ws.stage1, ops, ws)
  scalar_nonlinear!(ws.scalar_stage1, ws.velocity, ws.scalar_field, ops, ws)            # N̂_φ,1
  forcing_source!(physics.scalar_forcing, ws.scalar_stage1, ops, ws)

  # predictors û*, φ̂*
  integrating_factor!(ws.integrating_factor, ops, ν, dt, velocity_rate)                 # E_ν
  field_data(ws.velocity_star_spectral) .= field_data(uh) .+ dt_T .* field_data(ws.stage1)
  convolve!(ws.velocity_star_spectral, ws.velocity_star_spectral, ws.integrating_factor)
  integrating_factor!(ws.integrating_factor, ops, κ, dt, scalar_rate)                   # E_κ
  field_data(ws.scalar_star_spectral) .= field_data(phih) .+ dt_T .* field_data(ws.scalar_stage1)
  convolve!(ws.scalar_star_spectral, ws.scalar_star_spectral, ws.integrating_factor)

  # stage 2 — nonlinear terms at the predictor state
  velocity_vorticity!(ws.velocity_star, ws.vorticity_physical, ws.velocity_star_spectral, ops, ws)
  scalar_to_physical!(ws.scalar_field, ws.scalar_star_spectral, ops, ws)
  velocity_nonlinear!(ws.stage2, ws.velocity_star, ws.vorticity_physical, ops, ws)      # N̂_u,2
  forcing_source!(physics.velocity_forcing, ws.stage2, ops, ws)
  scalar_nonlinear!(ws.scalar_stage2, ws.velocity_star, ws.scalar_field, ops, ws)       # N̂_φ,2
  forcing_source!(physics.scalar_forcing, ws.scalar_stage2, ops, ws)

  # velocity update: ûₙ₊₁ = E_ν ûₙ + (Δt/2)(E_ν N̂_u,1 + N̂_u,2)
  integrating_factor!(ws.integrating_factor, ops, ν, dt, velocity_rate)
  convolve!(ws.stage1, ws.stage1, ws.integrating_factor)
  convolve!(uh, uh, ws.integrating_factor)
  field_data(uh) .+= half .* (field_data(ws.stage1) .+ field_data(ws.stage2))

  # scalar update: φ̂ₙ₊₁ = E_κ φ̂ₙ + (Δt/2)(E_κ N̂_φ,1 + N̂_φ,2)
  integrating_factor!(ws.integrating_factor, ops, κ, dt, scalar_rate)
  convolve!(ws.scalar_stage1, ws.scalar_stage1, ws.integrating_factor)
  convolve!(phih, phih, ws.integrating_factor)
  field_data(phih) .+= half .* (field_data(ws.scalar_stage1) .+ field_data(ws.scalar_stage2))

  apply_forcing!(physics.velocity_forcing, uh, ops, ws.scratch)
  apply_forcing!(physics.scalar_forcing, phih, ops, ws.scalar_nonlinear)
  return uh, phih
end


"""
    default_integrator()

The recommended default scheme, [`IFLowStorageRK3`](@ref) — third-order, low-storage, and stable on
the imaginary axis (unlike [`IFRK2`](@ref)).
"""
default_integrator() = IFLowStorageRK3()


"""
    recommended_cfl(integrator)
    recommended_cfl(integrator, ops)

A conservative advective-CFL ceiling ``C`` for the scheme, for a timestep
``\\Delta t = C\\,\\Delta x / \\max_i\\lvert u_i\\rvert``.

The advective eigenvalues of the de-aliased system are imaginary, of magnitude up to
``\\kappa_{\\max}\\max\\lvert\\boldsymbol{u}\\rvert``; stability needs this times ``C`` to stay within the
scheme's imaginary-axis stability limit ``y_{\\mathrm{s}}``. The one-argument form returns the value
calibrated for the ``2/3`` rule (``\\kappa_{\\max}\\Delta x = 2\\pi/3 \\approx 2.09``): for
[`IFLowStorageRK3`](@ref) ``y_{\\mathrm{s}} = \\sqrt{3}`` gives ``C \\lesssim 0.83``, taken
conservatively as ``0.5``; [`IFRK2`](@ref) is imaginary-axis unstable (``y_{\\mathrm{s}} = 0``,
relying on viscous damping), so a small ``0.25``.

The two-argument form scales that ceiling by the operators' de-aliasing: a strategy that keeps modes
to a higher ``\\kappa_{\\max}`` (e.g. `HouLi`, out to the Nyquist wavenumber) takes a
proportionally smaller step, ``C \\propto 1/\\kappa_{\\max}``. This is the value `Simulation` uses.
Override either for a specific run.
"""
recommended_cfl(::AbstractIntegrator) = 0.3
recommended_cfl(::IFRK2) = 0.25
recommended_cfl(::IFLowStorageRK3) = 0.5

# Scale the base (2/3-calibrated) ceiling by the active de-aliasing: factor = (2/3)/f, f the retained
# Nyquist fraction (1 for TwoThirds ⇒ unchanged, 2/3 for HouLi ⇒ ×2/3, since it keeps modes to Nyquist).
recommended_cfl(integrator::AbstractIntegrator, ops::SpectralOperators) =
  recommended_cfl(integrator) * (2 // 3) / _retained_nyquist_fraction(ops.dealiasing)


end # module TimeIntegration
