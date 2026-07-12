# State — the DNS realisation of the Mori–Zwanzig State role: the preallocated field buffers a step
# writes into (allocated only for what the configured run needs — no scalar scratch when scalar = false)
# and the random initial conditions that seed a run. Everything is sized to a `FixedDomain` from
# `SimulationDomain`.

"""
    State

The DNS realisation of the Mori–Zwanzig State role — the field the dynamics acts on, as stored and seeded:
[`FieldBuffers`](@ref), the preallocated scratch a coupled velocity + scalar step writes into (only what the
configured run needs; no scalar buffers when the run carries no scalar), and the random initial conditions
[`random_solenoidal_velocity!`](@ref) (the divergence-free velocity) and [`random_scalar!`](@ref) (the
mean-zero scalar ``\\varphi``). All sized to a [`FixedDomain`](@ref).
"""
module State

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, spectral_vector, physical_vector,
                          scalar_spectral, scalar_physical, _real_type

export FieldBuffers, random_solenoidal_velocity!, random_scalar!


# The passive-scalar step buffers — held by `FieldBuffers` only when a scalar is evolved, `nothing`
# otherwise (so a velocity-only run allocates none of them).
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
    FieldBuffers(domain; scalar = false)

Preallocated scratch for one integrating-factor step, sized so a step allocates no field-sized memory.
The velocity buffers are the spectral vorticity, two Runge–Kutta stage registers (buffers holding a
stage's state and accumulator), the predictor field, a velocity copy (the in-place inverse transform
consumes its source), a general spectral scratch, the nonlinear-term buffer, and the physical velocity /
start-of-step vorticity / per-stage vorticity / predictor / Lamb-vector
(``\\boldsymbol{u}\\times\\boldsymbol{\\omega}``); the shared integrating factor and the velocity's
per-mode linear-forcing-rate array ``A(\\boldsymbol{\\kappa})`` complete them.

When `scalar = true` a `ScalarBuffers` bundle is allocated for the passive scalar ``\\varphi`` (two stage
registers, a predictor, the nonlinear-term buffer, a copy, the physical scalar, and its forcing-rate
array; the scalar flux ``\\boldsymbol{u}\\varphi`` reuses the velocity scratch). When `scalar = false`
the run evolves no scalar, so `buffers.scalar` is `nothing` and none of those field-sized buffers are
allocated.
"""
struct FieldBuffers{VS, SS, VP, RK, SB}
  vorticity_spectral::VS
  stage1::VS
  stage2::VS
  velocity_star_spectral::VS
  velocity_copy::VS
  scratch::VS
  nonlinear::VS
  integrating_factor::SS
  velocity::VP
  vorticity_start::VP
  vorticity_physical::VP
  velocity_star::VP
  lamb::VP
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

function FieldBuffers(domain::FixedDomain; scalar::Bool = false)
  return FieldBuffers(
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
    random_solenoidal_velocity!(û, domain; energy = 0.5, peak_wavenumber = 2.0,
                                spectrum = nothing, rng = default_rng())

Fill `û` (a velocity field in spectral representation) with a random, divergence-free velocity
``\\boldsymbol{u}`` of a chosen energy spectrum, de-aliased and rescaled so the kinetic energy
``\\tfrac12\\langle\\lvert\\boldsymbol{u}\\rvert^{2}\\rangle`` equals `energy`. The Leray–Helmholtz
projection ``\\mathbb{P}`` enforces ``\\nabla\\cdot\\boldsymbol{u} = 0``.

By default (`spectrum = nothing`) the velocity is concentrated at large scales by the Gaussian envelope
``\\exp\\!\\big(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/k_p^{2}\\big)`` (``k_p`` is `peak_wavenumber`).
Pass `spectrum`, a function ``\\kappa \\mapsto E(\\kappa)`` giving a target radial energy spectrum, to
seed that shape instead: each mode is scaled by ``\\sqrt{E(\\kappa)}/\\kappa``, so the shell-summed
spectrum is ``\\propto \\kappa^{2}(\\sqrt{E}/\\kappa)^{2} = E(\\kappa)`` (the ``\\kappa^{2}`` is the
shell's mode count) and the overall amplitude is fixed by the `energy` rescaling. The run layer bridges
a `Phenomenology` model spectrum into this function.

`domain` is the [`FixedDomain`](@ref) supplying the grid, backend, wavenumber multipliers, and
de-alias kernel; `rng` is the random stream (defaults to `Random.default_rng()`).
"""
function random_solenoidal_velocity!(û, domain::FixedDomain;
                                     energy::Real = 0.5, peak_wavenumber::Real = 2.0,
                                     spectrum = nothing, rng = Random.default_rng())
  T = _real_type(domain)
  noise = physical_vector(domain)
  copyto!(field_data(noise), randn(rng, T, physical_field_shape(domain.grid, Val(1))...))
  to_spectral!(û, noise, domain.velocity_plans)

  envelope = scalar_spectral(domain)
  if isnothing(spectrum)
    inverse_peak_squared = one(T) / T(peak_wavenumber)^2
    field_data(envelope) .= complex.(exp.((-inverse_peak_squared) .* domain.squared_wavenumber))
  else
    # Match a target radial spectrum E(κ): a per-mode amplitude √(E(κ))/κ yields a shell-summed
    # spectrum ∝ κ²·(√E/κ)² = E(κ) (the κ² is the shell's mode count); the DC mode stays at 0.
    shape = k2 -> k2 > 0 ? T(sqrt(max(spectrum(sqrt(k2)), zero(k2))) / sqrt(k2)) : zero(T)
    field_data(envelope) .= complex.(shape.(domain.squared_wavenumber))
  end
  convolve!(û, û, envelope)

  helmholtz_projection!(û, û, domain.multipliers)
  convolve!(û, û, domain.dealias)

  current_energy = 0.5 * inner(û, û)
  current_energy > 0 && (field_data(û) .*= sqrt(T(energy) / current_energy))
  return û
end


"""
    random_scalar!(φ̂, domain; variance = 1.0, peak_wavenumber = 2.0,
                   spectrum = nothing, rng = default_rng())

Fill `φ̂` (the scalar ``\\varphi`` in spectral representation) with a random, mean-zero scalar of a
chosen spectrum, de-aliased and rescaled so the variance ``\\langle\\varphi^{2}\\rangle`` equals
`variance`. The physical noise is made mean-zero before the transform, so the
``\\boldsymbol{\\kappa}=\\boldsymbol 0`` (mean) mode vanishes.

By default (`spectrum = nothing`) the scalar is concentrated at large scales by the Gaussian envelope
``\\exp\\!\\big(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/k_p^{2}\\big)`` (``k_p`` is `peak_wavenumber`).
Pass `spectrum`, a function ``\\kappa \\mapsto E_\\varphi(\\kappa)`` giving a target radial
scalar-variance spectrum, to seed that shape instead: each mode is scaled by
``\\sqrt{E_\\varphi(\\kappa)}/\\kappa`` (the same construction the velocity uses), so the shell-summed
spectrum is ``\\propto E_\\varphi(\\kappa)`` and the amplitude is fixed by the `variance` rescaling —
e.g. an Obukhov–Corrsin form from `Phenomenology`.

`domain` is the [`FixedDomain`](@ref) supplying the grid, backend, wavenumber multipliers, and
de-alias kernel; `rng` is the random stream (defaults to `Random.default_rng()`).
"""
function random_scalar!(φ̂, domain::FixedDomain;
                        variance::Real = 1.0, peak_wavenumber::Real = 2.0,
                        spectrum = nothing, rng = Random.default_rng())
  T = _real_type(domain)
  noise = scalar_physical(domain)
  data = randn(rng, T, physical_field_shape(domain.grid, Val(0))...)
  data .-= sum(data) / length(data)                            # zero the spatial mean
  copyto!(field_data(noise), data)
  to_spectral!(φ̂, noise, domain.scalar_plans)

  envelope = scalar_spectral(domain)
  if isnothing(spectrum)
    inverse_peak_squared = one(T) / T(peak_wavenumber)^2
    field_data(envelope) .= complex.(exp.((-inverse_peak_squared) .* domain.squared_wavenumber))
  else
    # Match a target radial scalar spectrum E_φ(κ): amplitude √(E_φ(κ))/κ ⇒ shell sum ∝ E_φ(κ).
    shape = k2 -> k2 > 0 ? T(sqrt(max(spectrum(sqrt(k2)), zero(k2))) / sqrt(k2)) : zero(T)
    field_data(envelope) .= complex.(shape.(domain.squared_wavenumber))
  end
  convolve!(φ̂, φ̂, envelope)
  convolve!(φ̂, φ̂, domain.dealias)

  current_variance = inner(φ̂, φ̂)                         # ⟨φ²⟩ for a mean-zero field
  current_variance > 0 && (field_data(φ̂) .*= sqrt(T(variance) / current_variance))
  return φ̂
end

end # module State
