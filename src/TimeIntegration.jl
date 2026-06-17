# TimeIntegration — the pluggable time-marching schemes, as concrete `AbstractIntegrator` subtypes
# dispatched by `step!`. All schemes are of the integrating-factor family: the stiff diffusive part
# is advanced exactly through ℰ = exp(-ν|k|²Δt) (built in Equations), and the nonlinear term is
# advanced explicitly by a Runge–Kutta stage combination. This treats viscosity without a stability
# restriction, which is what keeps the schemes low-storage — the priority for GPU runs.
#
# Slice 1 ships `IFRK2` (integrating-factor Heun); `IFLowStorageRK3` (Williamson 2N) is added next.
# Each `step!` assumes the caller has filled `ws.velocity` / `ws.vorticity_start` with the
# start-of-step physical velocity and vorticity (via `velocity_vorticity!`) — they are reused for the
# first stage and for the diagnostics, so the step recomputes nothing.

module TimeIntegration

using GBGPeriodicFields
using ..SimulationState: SpectralOperators, VelocityWorkspace
using ..Equations: velocity_vorticity!, velocity_nonlinear!, integrating_factor!
using ..Forcing: AbstractForcing, force!

export AbstractIntegrator, IFRK2, step!


"""
    AbstractIntegrator

Supertype of the time-marching schemes. A scheme implements
`step!(integrator, uh, ops, ws, forcing, viscosity, dt)`, advancing the spectral velocity `uh` by
one timestep `dt` in place.
"""
abstract type AbstractIntegrator end


"""
    IFRK2()

Integrating-factor second-order Runge–Kutta (Heun). With `ℰ = exp(-ν|k|²Δt)` and `N̂` the de-aliased
Leray-projected nonlinearity,

    N̂₁ = N̂(ûₙ),   û* = ℰ(ûₙ + Δt N̂₁),   N̂₂ = N̂(û*),
    ûₙ₊₁ = ℰ ûₙ + (Δt/2)(ℰ N̂₁ + N̂₂),

then the forcing is applied. Two nonlinear evaluations per step, minimal storage.
"""
struct IFRK2 <: AbstractIntegrator end


function step!(::IFRK2, uh, ops::SpectralOperators, ws::VelocityWorkspace,
               forcing::AbstractForcing, viscosity::Real, dt::Real)
  integrating_factor!(ws.integrating_factor, ops, viscosity, dt)                       # ℰ = exp(-ν|k|²Δt)

  velocity_nonlinear!(ws.stage1, ws.velocity, ws.vorticity_start, ops, ws)             # N̂₁ = N̂(ûₙ)
  field_data(ws.velocity_star_spectral) .= field_data(uh) .+ dt .* field_data(ws.stage1)
  convolve!(ws.velocity_star_spectral, ws.velocity_star_spectral, ws.integrating_factor) # û* = ℰ(ûₙ + Δt N̂₁)

  velocity_vorticity!(ws.velocity_star, ws.vorticity_physical, ws.velocity_star_spectral, ops, ws)
  velocity_nonlinear!(ws.stage2, ws.velocity_star, ws.vorticity_physical, ops, ws)     # N̂₂ = N̂(û*)

  convolve!(ws.stage1, ws.stage1, ws.integrating_factor)                                # ℰ N̂₁
  convolve!(uh, uh, ws.integrating_factor)                                              # ℰ ûₙ
  field_data(uh) .+= (dt / 2) .* (field_data(ws.stage1) .+ field_data(ws.stage2))      # ûₙ₊₁

  force!(forcing, uh, ops, ws.scratch)
  return uh
end


end # module TimeIntegration
