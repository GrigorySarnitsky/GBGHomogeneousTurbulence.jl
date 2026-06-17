# TimeIntegration — the pluggable time-marching schemes, as concrete `AbstractIntegrator` subtypes
# dispatched by `step!`. All schemes are of the integrating-factor family: the stiff diffusive part
# is advanced exactly through ℰ = exp(-ν|k|²Δt) (built in Equations), and the nonlinear term is
# advanced explicitly by a Runge–Kutta stage combination. This treats viscosity without a stability
# restriction, which is what keeps the schemes low-storage — the priority for GPU runs.
#
# IFLowStorageRK3 (Williamson 2N) is the default workhorse; IFRK2 (Heun) is a cheaper option that is
# only marginally stable for advection (see its docstring). Each `step!` assumes the caller has
# filled `ws.velocity` / `ws.vorticity_start` with the start-of-step physical velocity and vorticity
# (via `velocity_vorticity!`) — they are reused for the first stage and for the diagnostics, so the
# step recomputes nothing.

"""
    TimeIntegration

The pluggable time-marching schemes, as concrete `AbstractIntegrator` subtypes dispatched by
[`step!`](@ref). All are of the integrating-factor family: the stiff diffusive part is advanced
exactly by the integrating factor ``\\mathcal{E} = \\exp(-\\nu\\lvert\\mathbf{k}\\rvert^{2}\\Delta t)``
and the nonlinear term explicitly by a Runge–Kutta stage combination. The default is
[`IFLowStorageRK3`](@ref); [`recommended_cfl`](@ref) gives a scheme's advective-CFL ceiling.
"""
module TimeIntegration

using GBGPeriodicFields
using ..SimulationState: SpectralOperators, VelocityWorkspace
using ..Equations: velocity_vorticity!, velocity_nonlinear!, integrating_factor!
using ..Forcing: AbstractForcing, force!

export AbstractIntegrator, IFRK2, IFLowStorageRK3, step!,
       recommended_cfl, default_integrator


"""
    AbstractIntegrator

Supertype of the time-marching schemes. A scheme implements
[`step!`](@ref)`(integrator, uh, ops, ws, forcing, viscosity, dt)`, advancing the velocity field
`uh` (in spectral representation) by one timestep in place, and may specialize
[`recommended_cfl`](@ref).
"""
abstract type AbstractIntegrator end


"""
    step!(integrator, uh, ops, ws, forcing, viscosity, dt)

Advance the spectral velocity field `uh` by one timestep `dt` in place, using the scheme
`integrator`, the operators `ops`, the workspace `ws`, the `forcing` strategy, and the kinematic
`viscosity` ``\\nu``. Dispatches on the concrete `integrator` type (see `IFRK2`,
`IFLowStorageRK3`). The caller must have filled `ws.velocity` and `ws.vorticity_start` with the
start-of-step physical velocity and vorticity (via [`velocity_vorticity!`](@ref)).
"""
function step! end


"""
    IFLowStorageRK3()

Integrating-factor third-order low-storage Runge–Kutta (Williamson 2N). With the per-substep
integrating factor ``\\mathcal{E}(\\tau) = \\exp(-\\nu\\lvert\\mathbf{k}\\rvert^{2}\\tau)`` and
``\\widehat{\\mathbf{N}}`` the de-aliased Leray-projected nonlinearity (see
[`velocity_nonlinear!`](@ref)), the step carries the state ``\\hat{\\mathbf{u}}`` and a single
accumulator ``\\mathbf{h}`` through three stages ``i = 1,2,3``,

```math
\\mathbf{h} \\leftarrow A_i\\,\\mathbf{h} + \\Delta t\\,\\widehat{\\mathbf{N}}(\\hat{\\mathbf{u}}),
\\qquad
\\hat{\\mathbf{u}} \\leftarrow \\hat{\\mathbf{u}} + B_i\\,\\mathbf{h},
\\qquad
\\hat{\\mathbf{u}} \\leftarrow \\mathcal{E}(d_i\\Delta t)\\,\\hat{\\mathbf{u}},
\\quad
\\mathbf{h} \\leftarrow \\mathcal{E}(d_i\\Delta t)\\,\\mathbf{h},
```

with ``A = (0, -5/9, -153/128)``, ``B = (1/3, 15/16, 8/15)``, and the node increments
``d = (1/3, 5/12, 1/4)`` (from the abscissae ``c = (0, 1/3, 3/4)``). The integrating-factor rotation
by ``\\mathcal{E}(d_i\\Delta t)`` advances the diffusion exactly over each substep; setting
``\\nu = 0`` recovers the bare Williamson scheme, and dropping the nonlinearity recovers exact
diffusion ``\\mathcal{E}(\\Delta t)``. Three nonlinear evaluations per step, two field registers —
the default workhorse: third-order and stable on the imaginary axis (limit
``\\sqrt{3}``), unlike [`IFRK2`](@ref).
"""
struct IFLowStorageRK3 <: AbstractIntegrator end


function step!(::IFLowStorageRK3, uh, ops::SpectralOperators, ws::VelocityWorkspace,
               forcing::AbstractForcing, viscosity::Real, dt::Real)
  T = real(eltype(field_data(uh)))
  dt_T = T(dt)
  a = (zero(T), T(-5 // 9), T(-153 // 128))
  b = (T(1 // 3), T(15 // 16), T(8 // 15))
  d = (T(1 // 3), T(5 // 12), T(1 // 4))
  h = ws.stage1                                                              # the single 2N accumulator

  for i in 1:3
    if i == 1
      velocity_nonlinear!(ws.nonlinear, ws.velocity, ws.vorticity_start, ops, ws)        # N̂(ûₙ), cached start-of-step
      field_data(h) .= dt_T .* field_data(ws.nonlinear)                                  # A₁ = 0
    else
      velocity_vorticity!(ws.velocity_star, ws.vorticity_physical, uh, ops, ws)
      velocity_nonlinear!(ws.nonlinear, ws.velocity_star, ws.vorticity_physical, ops, ws)
      field_data(h) .= a[i] .* field_data(h) .+ dt_T .* field_data(ws.nonlinear)
    end
    field_data(uh) .+= b[i] .* field_data(h)
    integrating_factor!(ws.integrating_factor, ops, viscosity, d[i] * dt)                # ℰ(dᵢΔt)
    convolve!(uh, uh, ws.integrating_factor)                                             # rotate the state
    i < 3 && convolve!(h, h, ws.integrating_factor)                                      # rotate the accumulator (unused after i=3)
  end

  force!(forcing, uh, ops, ws.scratch)
  return uh
end


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

after which the forcing is applied. Two nonlinear evaluations per step.

!!! note
    Every two-stage explicit Runge–Kutta has stability function ``R(z) = 1 + z + z^{2}/2``, for which
    ``\\lvert R(iy)\\rvert^{2} = 1 + y^{4}/4 > 1``: the scheme is unstable on the imaginary axis, so
    it is stable only where the viscous damping of the integrating factor dominates. It is adequate
    for well-resolved, modest-Reynolds-number runs but is **not** the default — prefer
    [`IFLowStorageRK3`](@ref) for high Reynolds number or marginal resolution.
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


"""
    default_integrator()

The recommended default scheme, [`IFLowStorageRK3`](@ref) — third-order, low-storage, and stable on
the imaginary axis (unlike [`IFRK2`](@ref)).
"""
default_integrator() = IFLowStorageRK3()


"""
    recommended_cfl(integrator)

A conservative advective-CFL ceiling ``C`` for the scheme, for a timestep
``\\Delta t = C\\,\\Delta x / \\max_i\\lvert u_i\\rvert``.

The advective eigenvalues of the de-aliased system are imaginary, of magnitude up to
``k_{\\max}\\max\\lvert\\mathbf{u}\\rvert`` with ``k_{\\max} = \\tfrac{2}{3}\\,\\tfrac{N}{2}\\,\\tfrac{2\\pi}{L}``,
so ``k_{\\max}\\Delta x = 2\\pi/3 \\approx 2.09``; stability needs this times ``C`` to stay within the
scheme's imaginary-axis stability limit ``y_{\\mathrm{s}}``. For [`IFLowStorageRK3`](@ref)
``y_{\\mathrm{s}} = \\sqrt{3} \\approx 1.73`` (so ``C \\lesssim 0.83``), giving the conservative
``0.5``; [`IFRK2`](@ref) has ``y_{\\mathrm{s}} = 0`` (imaginary-axis unstable, relying on viscous
damping), so a small ``0.25``. These are defaults — override for a specific run.
"""
recommended_cfl(::AbstractIntegrator) = 0.3
recommended_cfl(::IFRK2) = 0.25
recommended_cfl(::IFLowStorageRK3) = 0.5


end # module TimeIntegration
