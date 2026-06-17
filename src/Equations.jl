# Equations — the physics the integrators advance: the incompressible Navier–Stokes right-hand side
# in rotational form, and the diagnostics derived from a velocity field.
#
# The momentum equation is advanced as ∂û/∂t = ℙ(u×ω)^ − ν|k|²û (+ forcing), with the viscous term
# integrated exactly through the integrating factor ℰ = exp(-ν|k|²Δt) (built here, applied in
# TimeIntegration). This module owns only the nonlinear-term assembly and the integrating factor;
# everything diagonal-in-Fourier is a GBGPeriodicFields operator.

module Equations

using GBGPeriodicFields
using ..SimulationState: SpectralOperators, VelocityWorkspace

export velocity_vorticity!, velocity_nonlinear!, integrating_factor!,
       kinetic_energy, dissipation, max_speed


"""
    velocity_vorticity!(velocity, vorticity, uh, ops, ws)

Compute the physical velocity and vorticity of the spectral velocity field `uh` into the buffers
`velocity` and `vorticity`. `uh` is preserved (its vorticity is transformed first, then a copy of
`uh` is transformed — the in-place inverse transform consumes its spectral source).
"""
function velocity_vorticity!(velocity, vorticity, uh, ops::SpectralOperators, ws::VelocityWorkspace)
  curl!(ws.vorticity_spectral, uh, ops.multipliers)
  to_physical!(vorticity, ws.vorticity_spectral, ops.velocity_plans)
  copyto!(field_data(ws.velocity_copy), field_data(uh))
  to_physical!(velocity, ws.velocity_copy, ops.velocity_plans)
  return velocity, vorticity
end


"""
    velocity_nonlinear!(nonlinear, velocity, vorticity, ops, ws)

Assemble the de-aliased Leray-projected nonlinear term `N̂ = ℙ(u×ω)^` into `nonlinear`, from the
physical `velocity` and `vorticity`. The rotational form `u×ω` (the Lamb vector) carries the
convective term; the Leray–Helmholtz projection `ℙ` removes the pressure gradient, and the 2/3 rule
de-aliases the quadratic product. Allocation-free (distinct destination ⇒ no-alias path).
"""
function velocity_nonlinear!(nonlinear, velocity, vorticity, ops::SpectralOperators, ws::VelocityWorkspace)
  cross!(ws.lamb, velocity, vorticity)
  to_spectral!(ws.scratch, ws.lamb, ops.velocity_plans)
  helmholtz_projection!(nonlinear, ws.scratch, ops.multipliers)
  convolve!(nonlinear, nonlinear, ops.dealias)
  return nonlinear
end


"""
    integrating_factor!(factor, ops, diffusivity, dt)

Write the exact diffusive integrating factor `ℰ = exp(-diffusivity · |k|² · dt)` into the scalar
spectral buffer `factor` (used by the integrators to advance the viscous/diffusive part exactly).
For velocity `diffusivity` is the kinematic viscosity `ν`; for the scalar it is `ν/Sc`.
"""
function integrating_factor!(factor, ops::SpectralOperators, diffusivity::Real, dt::Real)
  field_data(factor) .= complex.(exp.((-diffusivity * dt) .* ops.squared_wavenumber))
  return factor
end


"""
    kinetic_energy(velocity)

The turbulent kinetic energy `½⟨|u|²⟩` (Parseval, so it accepts `velocity` in either representation).
"""
kinetic_energy(velocity) = 0.5 * inner(velocity, velocity)


"""
    dissipation(vorticity, viscosity)

The mean dissipation rate `ε = ν⟨|ω|²⟩` of a homogeneous flow, from the physical vorticity.
"""
dissipation(vorticity, viscosity::Real) = viscosity * inner(vorticity, vorticity)


"""
    max_speed(velocity)

The largest velocity component in absolute value, `max_i |u_i|` — an allocation-free reduction used
for the advective CFL timestep (it differs from the true `sup|u|` by at most `√3`, well inside the
CFL margin).
"""
max_speed(velocity) = maximum(abs, field_data(velocity))


end # module Equations
