# State — the DNS realization of the Mori–Zwanzig State role: `ResolvedFields` (the evolving spectral
# velocity and scalar — the single source of truth; the physical fields are recovered from it, never
# held in the state) and the random initial conditions that seed a run. The physical representations
# are recovered where they are consumed — through the source-preserving four-argument form of PF's `to_physical!`
# (the state is never consumed; PF decision 64) and, for the vorticity, `Observables.vorticity_physical!`
# — and land in `Cache` (`ObservablesCache`); the per-step scratch lives with the integrator
# (`IntegratorBuffers` in `Propagator`). Everything is sized to a `FixedDomain` from `SimulationDomain`.

"""
    State

The evolving state a run advances, and how it is seeded:
- [`ResolvedFields`](@ref) — the evolving velocity and scalar in spectral representation: a passive
  record with every operation external (the single source of truth; the physical fields are
  recovered from it, never held in the state).
- [`random_solenoidal_velocity_spectral!`](@ref) and [`random_scalar_spectral!`](@ref) — the random initial conditions
  (a divergence-free velocity, a mean-zero scalar) that seed it.

All sized to a [`FixedDomain`](@ref). The physical representations are recovered from the state with
the four-argument, source-preserving form (the extra argument is a scratch field the transform consumes
in the state's place) of
[`to_physical!`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.to_physical!) — the inverse
transform consumes the coefficients it runs from (a property of the FFT backends), so the recovery
copies into scratch and the state survives every recovery — and the vorticity with
[`vorticity_physical!`](@ref GBGIsotropicTurbulence.Observables.vorticity_physical!); the recovered
values are deposited into the
[`ObservablesCache`](@ref GBGIsotropicTurbulence.Cache.ObservablesCache).
"""
module State

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, new_vector_field_spectral, new_vector_field_physical,
                          new_scalar_field_spectral, new_scalar_field_physical, _real_type

export ResolvedFields, random_solenoidal_velocity_spectral!, random_scalar_spectral!


"""
    ResolvedFields(domain; scalar = false)

The record of the evolving fields a run advances, in spectral representation — the single source of
truth, a passive container with every operation external. The velocity, vorticity, and scalar in
physical representation are recoveries of it, not part of it. The iteration recovers them at its
end into the [`ObservablesCache`](@ref GBGIsotropicTurbulence.Cache.ObservablesCache), never on a
read: each cached slot records which epoch its value belongs to, and a read serves that value or
throws. The state itself therefore cannot go stale.
Build it on a [`FixedDomain`](@ref); pass `scalar = true` to carry a passive scalar.

# Fields
- `velocity` — the velocity in spectral representation, ``\\hat{\\boldsymbol{u}}``.
- `scalar` — the scalar in spectral representation, ``\\hat\\varphi``, or `nothing` when the run carries
  no passive scalar.
"""
struct ResolvedFields{UH, PH}
  velocity_spectral::UH          # û (spectral) — the resolved velocity, the single source of truth
  scalar_spectral::PH            # φ̂ (spectral), or nothing when the run carries no scalar
end

ResolvedFields(domain::FixedDomain; scalar::Bool = false) =
  ResolvedFields(new_vector_field_spectral(domain), scalar ? new_scalar_field_spectral(domain) : nothing)


"""
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy, peak_wavenumber,
                                spectrum = nothing, rng = default_rng())

Fill `û` (a velocity field in spectral representation) with a random, divergence-free velocity
``\\boldsymbol{u}`` of a chosen energy spectrum, dealiased and rescaled so the kinetic energy
``\\tfrac{1}{2}\\langle\\lvert\\boldsymbol{u}\\rvert^{2}\\rangle`` equals [`kinetic_energy`](@ref GBGIsotropicTurbulence.Observables.kinetic_energy). The Leray–Helmholtz
projection ``\\mathbb{P}`` enforces ``\\nabla\\cdot\\boldsymbol{u} = 0``.

By default (`spectrum = nothing`) the velocity is concentrated at large scales by a Gaussian envelope
``\\exp\\!\\big(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/\\kappa_p^{2}\\big)`` on the mode amplitudes (zeroed
at ``\\boldsymbol{\\kappa} = \\boldsymbol{0}``, so the mean mode stays empty), whose
characteristic wavenumber is ``\\kappa_p`` (`peak_wavenumber`). Because the envelope multiplies the
amplitudes, the shell-summed energy spectrum ``\\propto \\kappa^{2}\\exp\\!\\big(-2\\kappa^{2}/\\kappa_p^{2}\\big)``
peaks at ``\\kappa_p/\\sqrt{2}``, not at ``\\kappa_p`` itself (the ``\\kappa^{2}`` is the shell's mode count).
Pass `spectrum`, a function ``\\kappa \\mapsto E(\\kappa)`` giving a target radial energy spectrum, to
seed that shape instead: each mode is scaled by ``\\sqrt{E(\\kappa)}/\\kappa``, so the shell-summed
spectrum is ``\\propto \\kappa^{2}(\\sqrt{E}/\\kappa)^{2} = E(\\kappa)`` (the ``\\kappa^{2}`` is the
shell's mode count) and the overall amplitude is fixed by the `kinetic_energy` rescaling — e.g. a von Kármán or
Pope form from the [`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology) submodule's model
spectra, which the run layer can wire in for you.

The `domain` (a [`FixedDomain`](@ref)) is what the field is generated on; the `rng` is the random
stream (defaults to `Random.default_rng()`).

!!! note
    Seeding into a running case mutates the resolved fields out of band — announce it with
    [`fields_modified!`](@ref GBGIsotropicTurbulence.Cache.fields_modified!), and
    re-deposit with [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!) before advancing
    (cached reads throw in between; nothing is recomputed on a read).
"""
function random_solenoidal_velocity_spectral!(û, domain::FixedDomain;
                                     kinetic_energy::Real, peak_wavenumber::Real,
                                     spectrum = nothing, rng = Random.default_rng())
  T = _real_type(domain)
  noise = new_vector_field_physical(domain)
  copyto!(field_data(noise), randn(rng, T, physical_field_shape(domain.grid, Val(1))...))
  to_spectral!(û, noise, domain.velocity_plans)

  # The envelope is a radial symbol of |κ|², built as a lazy kernel (no field of coefficients); the
  # closures capture converted VALUES only — a captured `Type` is not a bitstype and a GPU launch
  # rejects it (PF's radial-kernel contract).
  zero_value = zero(T)
  envelope = if isnothing(spectrum)
    inverse_peak_squared = one(T) / T(peak_wavenumber)^2
    radial_kernel(k2 -> exp(-inverse_peak_squared * k2), û, domain.multipliers)
  else
    # Match a target radial spectrum E(κ): a per-mode amplitude √(E(κ))/κ yields a shell-summed
    # spectrum ∝ κ²·(√E/κ)² = E(κ) (the κ² is the shell's mode count); the DC mode stays at 0.
    radial_kernel(k2 -> k2 > 0 ?
                    oftype(zero_value, sqrt(max(spectrum(sqrt(k2)), zero(k2))) / sqrt(k2)) :
                    zero_value,
                  û, domain.multipliers)
  end
  # The truncation rides in the envelope rather than as a second sweep of the field: both are
  # per-mode scalar multipliers, and a scalar commutes through the (per-mode) Leray projection, so
  # composing them (radial∘radial collapses to one symbol) costs one field pass in total.
  convolve!(û, û, convolve(envelope, domain.dealias))
  helmholtz_projection!(û, û, domain.multipliers)

  current_energy = 0.5 * inner(û, û)
  current_energy > 0 && (field_data(û) .*= sqrt(T(kinetic_energy) / current_energy))
  return û
end


"""
    random_scalar_spectral!(φ̂, domain; scalar_variance, peak_wavenumber,
                   spectrum = nothing, rng = default_rng())

Fill `φ̂` (the scalar ``\\varphi`` in spectral representation) with a random, mean-zero scalar of a
chosen spectrum, dealiased and rescaled so the variance ``\\langle\\varphi^{2}\\rangle`` equals
[`scalar_variance`](@ref GBGIsotropicTurbulence.Observables.scalar_variance) . The mean vanishes by
construction: the envelope is zeroed at
``\\boldsymbol{\\kappa}=\\boldsymbol{0}``, and that mode's coefficient *is* the spatial mean
``\\langle\\varphi\\rangle``.

By default (`spectrum = nothing`) the scalar is concentrated at large scales by a Gaussian envelope
``\\exp\\!\\big(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/\\kappa_p^{2}\\big)`` on the mode amplitudes — zeroed,
as above, at the origin — whose
characteristic wavenumber is ``\\kappa_p`` (`peak_wavenumber`). Because the envelope multiplies the
amplitudes, the shell-summed scalar-variance spectrum ``\\propto \\kappa^{2}\\exp\\!\\big(-2\\kappa^{2}/\\kappa_p^{2}\\big)``
peaks at ``\\kappa_p/\\sqrt{2}``, not at ``\\kappa_p`` itself (the ``\\kappa^{2}`` is the shell's mode count).
Pass `spectrum`, a function ``\\kappa \\mapsto E_\\varphi(\\kappa)`` giving a target radial
scalar-variance spectrum, to seed that shape instead: each mode is scaled by
``\\sqrt{E_\\varphi(\\kappa)}/\\kappa`` (the same construction the velocity uses), so the shell-summed
spectrum is ``\\propto E_\\varphi(\\kappa)`` and the amplitude is fixed by the `scalar_variance` rescaling —
e.g. an Obukhov–Corrsin form from [`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology).

The `domain` (a [`FixedDomain`](@ref)) is what the field is generated on; the `rng` is the random
stream (defaults to `Random.default_rng()`).

!!! note
    Seeding into a running case mutates the resolved fields out of band — announce it with
    [`fields_modified!`](@ref GBGIsotropicTurbulence.Cache.fields_modified!), and
    re-deposit with [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!) before advancing
    (cached reads throw in between; nothing is recomputed on a read).
"""
function random_scalar_spectral!(φ̂, domain::FixedDomain;
                        scalar_variance::Real, peak_wavenumber::Real,
                        spectrum = nothing, rng = Random.default_rng())
  T = _real_type(domain)
  noise = new_scalar_field_physical(domain)
  copyto!(field_data(noise), randn(rng, T, physical_field_shape(domain.grid, Val(0))...))
  to_spectral!(φ̂, noise, domain.scalar_plans)

  # Radial-symbol envelope, as for the velocity: lazy kernels, value-only captures.
  zero_value = zero(T)
  envelope = if isnothing(spectrum)
    # The envelope vanishes at κ = 0, which IS the mean removal: the κ = 0 coefficient of a field is
    # its spatial mean, so killing that mode leaves ⟨φ⟩ = 0 without a physical-space pass or the
    # reduction one would need to measure the mean. The `spectrum` branch below vanishes there too.
    inverse_peak_squared = one(T) / T(peak_wavenumber)^2
    radial_kernel(k2 -> ifelse(k2 > zero_value, exp(-inverse_peak_squared * k2), zero_value),
                  φ̂, domain.multipliers)
  else
    # Match a target radial scalar spectrum E_φ(κ): amplitude √(E_φ(κ))/κ ⇒ shell sum ∝ E_φ(κ).
    radial_kernel(k2 -> k2 > 0 ?
                    oftype(zero_value, sqrt(max(spectrum(sqrt(k2)), zero(k2))) / sqrt(k2)) :
                    zero_value,
                  φ̂, domain.multipliers)
  end
  convolve!(φ̂, φ̂, convolve(envelope, domain.dealias))   # truncation folded in, as for the velocity

  current_variance = inner(φ̂, φ̂)                         # ⟨φ²⟩ for a mean-zero field
  current_variance > 0 && (field_data(φ̂) .*= sqrt(T(scalar_variance) / current_variance))
  return φ̂
end

end # module State
