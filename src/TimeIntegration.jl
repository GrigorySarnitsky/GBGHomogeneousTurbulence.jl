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

"""
    TimeIntegration

The pluggable time-marching schemes, as concrete `AbstractIntegrator` subtypes dispatched by
[`step!`](@ref). All are of the integrating-factor family: the stiff diffusive part is advanced
exactly by the integrating factor ``\\mathcal{E} = \\exp(-\\nu\\lvert\\mathbf{k}\\rvert^{2}\\Delta t)``
and the nonlinear term explicitly by a Runge–Kutta stage combination.
"""
module TimeIntegration

using GBGPeriodicFields
using ..SimulationState: SpectralOperators, VelocityWorkspace
using ..Equations: velocity_vorticity!, velocity_nonlinear!, integrating_factor!
using ..Forcing: AbstractForcing, force!

export AbstractIntegrator, IFRK2, step!


"""
    AbstractIntegrator

Supertype of the time-marching schemes. A scheme implements
[`step!`](@ref)`(integrator, uh, ops, ws, forcing, viscosity, dt)`, advancing the velocity field
`uh` (in spectral representation) by one timestep in place.
"""
abstract type AbstractIntegrator end


"""
    step!(integrator, uh, ops, ws, forcing, viscosity, dt)

Advance the spectral velocity field `uh` by one timestep `dt` in place, using the scheme
`integrator`, the operators `ops`, the workspace `ws`, the `forcing` strategy, and the kinematic
`viscosity` ``\\nu``. Dispatches on the concrete `integrator` type (see `IFRK2`). The caller must
have filled `ws.velocity` and `ws.vorticity_start` with the start-of-step physical velocity and
vorticity (via [`velocity_vorticity!`](@ref)).
"""
function step! end


"""
    IFRK2()

Integrating-factor second-order Runge–Kutta (Heun). With the integrating factor
``\\mathcal{E} = \\exp(-\\nu\\lvert\\mathbf{k}\\rvert^{2}\\Delta t)`` and ``\\widehat{\\mathbf{N}}``
the de-aliased Leray-projected nonlinearity (see [`velocity_nonlinear!`](@ref)), one step of the
velocity field ``\\hat{\\mathbf{u}}`` is

```math
\\begin{aligned}
\\widehat{\\mathbf{N}}_1 &= \\widehat{\\mathbf{N}}(\\hat{\\mathbf{u}}_n), &
\\hat{\\mathbf{u}}^{*} &= \\mathcal{E}\\,(\\hat{\\mathbf{u}}_n + \\Delta t\\,\\widehat{\\mathbf{N}}_1), \\\\
\\widehat{\\mathbf{N}}_2 &= \\widehat{\\mathbf{N}}(\\hat{\\mathbf{u}}^{*}), &
\\hat{\\mathbf{u}}_{n+1} &= \\mathcal{E}\\,\\hat{\\mathbf{u}}_n + \\tfrac{\\Delta t}{2}\\big(\\mathcal{E}\\,\\widehat{\\mathbf{N}}_1 + \\widehat{\\mathbf{N}}_2\\big),
\\end{aligned}
```

after which the forcing is applied. Two nonlinear evaluations per step, minimal storage.

!!! note
    Every two-stage explicit Runge–Kutta has stability function ``R(z) = 1 + z + z^{2}/2``, for which
    ``\\lvert R(iy)\\rvert^{2} = 1 + y^{4}/4 > 1``: the scheme is unstable on the imaginary axis, so
    it is stable only where the viscous damping of the integrating factor dominates. It is adequate
    for well-resolved, modest-Reynolds-number runs but not the workhorse — prefer the low-storage
    RK3 for high Reynolds number or marginal resolution.
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
