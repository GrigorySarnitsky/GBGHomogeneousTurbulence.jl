# State — the DNS realisation of the Mori–Zwanzig State role: `ResolvedFields` (the evolving spectral
# velocity and scalar — the single source of truth; the physical fields are derived, never stored) and
# the random initial conditions that seed a run. The per-step scratch lives with the integrator
# (`IntegratorBuffers` in `Propagator`). Everything is sized to a `FixedDomain` from `SimulationDomain`.

"""
    State

The DNS realisation of the Mori–Zwanzig State role — the field the dynamics acts on and how it is
seeded: [`ResolvedFields`](@ref), the inert record of the evolving spectral velocity and scalar (the
single source of truth — the physical fields are derived, never stored), and the random initial
conditions [`random_solenoidal_velocity!`](@ref) (the divergence-free velocity) and
[`random_scalar!`](@ref) (the mean-zero scalar) that seed it. All sized to a
[`FixedDomain`](@ref).
"""
module State

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, spectral_vector, physical_vector,
                          scalar_spectral, scalar_physical, _real_type

export ResolvedFields, random_solenoidal_velocity!, random_scalar!


"""
    ResolvedFields(domain; scalar = false)

The inert record of the evolving spectral fields a run advances — the Mori–Zwanzig state, and the single
source of truth: the spectral velocity ``\\hat{\\boldsymbol u}`` (`velocity`) and, when the run carries a
passive scalar, the spectral scalar ``\\hat\\varphi`` (`scalar`; `nothing` otherwise). The physical
velocity, vorticity, and scalar are *derived* from these on demand, never stored here — so the state
cannot go stale. No operation hangs on this record: the generator advances it and the observables read it
as external functions of ``(\\hat{\\boldsymbol u}, \\hat\\varphi)``. Allocated on a [`FixedDomain`](@ref).
"""
struct ResolvedFields{UH, PH}
  velocity::UH                   # û (spectral) — the resolved velocity, the single source of truth
  scalar::PH                     # φ̂ (spectral), or nothing when the run carries no scalar
end

ResolvedFields(domain::FixedDomain; scalar::Bool = false) =
  ResolvedFields(spectral_vector(domain), scalar ? scalar_spectral(domain) : nothing)


"""
    random_solenoidal_velocity!(û, domain; kinetic_energy = 0.5, peak_wavenumber = 2.0,
                                spectrum = nothing, rng = default_rng())

Fill `û` (a velocity field in spectral representation) with a random, divergence-free velocity
``\\boldsymbol{u}`` of a chosen energy spectrum, de-aliased and rescaled so the kinetic energy
``\\tfrac12\\langle\\lvert\\boldsymbol{u}\\rvert^{2}\\rangle`` equals `kinetic_energy`. The Leray–Helmholtz
projection ``\\mathbb{P}`` enforces ``\\nabla\\cdot\\boldsymbol{u} = 0``.

By default (`spectrum = nothing`) the velocity is concentrated at large scales by the Gaussian envelope
``\\exp\\!\\big(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/k_p^{2}\\big)`` (``k_p`` is `peak_wavenumber`).
Pass `spectrum`, a function ``\\kappa \\mapsto E(\\kappa)`` giving a target radial energy spectrum, to
seed that shape instead: each mode is scaled by ``\\sqrt{E(\\kappa)}/\\kappa``, so the shell-summed
spectrum is ``\\propto \\kappa^{2}(\\sqrt{E}/\\kappa)^{2} = E(\\kappa)`` (the ``\\kappa^{2}`` is the
shell's mode count) and the overall amplitude is fixed by the `kinetic_energy` rescaling — e.g. a von Kármán or
Pope form from the `Phenomenology` submodule's model spectra, which the run layer can wire in for you.

`domain` is the [`FixedDomain`](@ref) the field is generated on; `rng` is the random stream
(defaults to `Random.default_rng()`).
"""
function random_solenoidal_velocity!(û, domain::FixedDomain;
                                     kinetic_energy::Real = 0.5, peak_wavenumber::Real = 2.0,
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
  current_energy > 0 && (field_data(û) .*= sqrt(T(kinetic_energy) / current_energy))
  return û
end


"""
    random_scalar!(φ̂, domain; scalar_variance = 1.0, peak_wavenumber = 2.0,
                   spectrum = nothing, rng = default_rng())

Fill `φ̂` (the scalar ``\\varphi`` in spectral representation) with a random, mean-zero scalar of a
chosen spectrum, de-aliased and rescaled so the variance ``\\langle\\varphi^{2}\\rangle`` equals
`scalar_variance`. The physical noise is made mean-zero before the transform, so the
``\\boldsymbol{\\kappa}=\\boldsymbol 0`` (mean) mode vanishes.

By default (`spectrum = nothing`) the scalar is concentrated at large scales by the Gaussian envelope
``\\exp\\!\\big(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/k_p^{2}\\big)`` (``k_p`` is `peak_wavenumber`).
Pass `spectrum`, a function ``\\kappa \\mapsto E_\\varphi(\\kappa)`` giving a target radial
scalar-variance spectrum, to seed that shape instead: each mode is scaled by
``\\sqrt{E_\\varphi(\\kappa)}/\\kappa`` (the same construction the velocity uses), so the shell-summed
spectrum is ``\\propto E_\\varphi(\\kappa)`` and the amplitude is fixed by the `scalar_variance` rescaling —
e.g. an Obukhov–Corrsin form from `Phenomenology`.

`domain` is the [`FixedDomain`](@ref) the field is generated on; `rng` is the random stream
(defaults to `Random.default_rng()`).
"""
function random_scalar!(φ̂, domain::FixedDomain;
                        scalar_variance::Real = 1.0, peak_wavenumber::Real = 2.0,
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
  current_variance > 0 && (field_data(φ̂) .*= sqrt(T(scalar_variance) / current_variance))
  return φ̂
end

end # module State
