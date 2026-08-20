# State — the DNS realization of the Mori–Zwanzig State role: `ResolvedFields` (the evolving spectral
# velocity and scalar — the single source of truth; the physical fields are recovered from it, never
# held in the state) and the random initial conditions that seed a run. The physical representations
# are recovered where they are consumed — through the source-preserving four-argument form of PF's `to_physical!`
# (the state is never consumed; PF decision 64) and, for the vorticity, `Observables.vorticity_physical!`
# — and land in `Cache` (`ObservablesCache`); the per-step scratch lives with the scheme
# (`IntegratorBuffers` in `Propagator`). Everything is sized to a `FixedDomain` from `SimulationDomain`.

"""
    State

The evolving state a run advances, and how it is seeded:
- [`ResolvedFields`](@ref) — the evolving velocity and scalar in spectral representation. This is the
  single source of truth: the physical fields are recovered from it and never held in the state.
- [`random_solenoidal_velocity_spectral!`](@ref) and [`random_scalar_spectral!`](@ref) — the random
  initial conditions (a divergence-free velocity, a mean-zero scalar) that seed it.

All sized to a [`FixedDomain`](@ref).

The recoveries do not disturb the state. An inverse transform consumes the coefficients it runs from,
which is a property of the FFT backends rather than a choice, so a naive recovery would destroy the
state it read. Recovery therefore goes through the four-argument
[`to_physical!`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.to_physical!), whose extra
argument is a scratch field the transform consumes in the state's place; the vorticity comes from
[`vorticity_physical!`](@ref GBGIsotropicTurbulence.Observables.vorticity_physical!) instead. The
recovered values are deposited into the
[`ObservablesCache`](@ref GBGIsotropicTurbulence.Cache.ObservablesCache).
"""
module State

using GBGPeriodicFields
using Random
using ..Observables: kinetic_energy as measure_kinetic_energy,
                     scalar_variance as measure_scalar_variance
using ..SimulationDomain: FixedDomain, new_vector_field_spectral, new_vector_field_physical,
                          new_scalar_field_spectral, new_scalar_field_physical, _real_type

export ResolvedFields, random_solenoidal_velocity_spectral!, random_scalar_spectral!


"""
    ResolvedFields(domain; scalar = false)

The record of the evolving fields a run advances, in spectral representation — the single source of
truth. The velocity, vorticity, and scalar in physical representation are recoveries of it, not part
of it: each **iteration** — one advance of the run, a step plus the deposit that closes it — recovers
them at its end into the
[`ObservablesCache`](@ref GBGIsotropicTurbulence.Cache.ObservablesCache), so the state itself cannot
go stale.

Build it on a [`FixedDomain`](@ref); pass `scalar = true` to carry a passive scalar.

# Fields
- `velocity_spectral` — the velocity in spectral representation, ``\\hat{\\boldsymbol{u}}``.
- `scalar_spectral` — the scalar in spectral representation, ``\\hat\\varphi``, or `nothing` when the
  run carries no passive scalar.
"""
struct ResolvedFields{UH, PH}
  velocity_spectral::UH          # û (spectral) — the resolved velocity, the single source of truth
  scalar_spectral::PH            # φ̂ (spectral), or nothing when the run carries no scalar
end

ResolvedFields(domain::FixedDomain; scalar::Bool = false) =
  ResolvedFields(new_vector_field_spectral(domain), scalar ? new_scalar_field_spectral(domain) : nothing)


"""
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy, envelope_wavenumber,
                                initial_spectrum = nothing, rng = default_rng())

Fill `û` (a velocity field in spectral representation) with a random, divergence-free velocity
``\\boldsymbol{u}`` of a chosen energy spectrum, dealiased and rescaled so the kinetic energy
``\\tfrac{1}{2}\\langle\\lvert\\boldsymbol{u}\\rvert^{2}\\rangle`` equals the requested `kinetic_energy`. The Leray–Helmholtz
projection ``\\mathbb{P}`` enforces ``\\nabla\\cdot\\boldsymbol{u} = 0``.

By default (`initial_spectrum = nothing`) the velocity is concentrated at large scales by a Gaussian envelope
``\\exp\\!\\bigl(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/\\kappa_p^{2}\\bigr)`` on the mode amplitudes (zeroed
at ``\\boldsymbol{\\kappa} = \\boldsymbol{0}``, so the mean mode stays empty), whose
characteristic wavenumber is ``\\kappa_p`` (`envelope_wavenumber`). Because the envelope multiplies the
amplitudes, the shell-summed energy spectrum ``\\propto \\kappa^{2}\\exp\\!\\bigl(-2\\kappa^{2}/\\kappa_p^{2}\\bigr)``
peaks at ``\\kappa_p/\\sqrt{2}``, not at ``\\kappa_p`` itself (the ``\\kappa^{2}`` is the shell's mode count). The `envelope_wavenumber` setting has no effect in the `initial_spectrum` branch below, which carries its own large scale and will not generally peak there — the two modes do not seed the same large scale at the same nominal setting.
Pass `initial_spectrum`, a function ``\\kappa \\mapsto E(\\kappa)`` giving a target radial energy spectrum (the
front door forwards its `initial_spectrum` keyword here), to
seed that shape instead: each mode is scaled by ``\\sqrt{E(\\kappa)}/\\kappa``, so the shell-summed
spectrum is ``\\propto \\kappa^{2}(\\sqrt{E}/\\kappa)^{2} = E(\\kappa)`` (the ``\\kappa^{2}`` is the
shell's mode count) and the overall amplitude is fixed by the `kinetic_energy` rescaling — e.g. a von Kármán or
Pope form from the [`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology) submodule's model
spectra, which the run layer can wire in for you.

The `domain` (a [`FixedDomain`](@ref)) is what the field is generated on; the `rng` is the random
stream (defaults to `Random.default_rng()`).

Returns `û`.

!!! note "Seeding a running case invalidates the observables cache"
    The cache holds what the last deposit left, so a seed written into a live run makes every cached
    observable wrong. Announce the change with
    [`fields_modified!`](@ref GBGIsotropicTurbulence.Cache.fields_modified!), which advances the
    fields epoch — the cache's freshness counter — so cached reads throw rather than serve stale
    values, then restore the cache with
    [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!) before advancing again. The
    interval between the two calls is yours to close.
"""
function random_solenoidal_velocity_spectral!(û, domain::FixedDomain;
                                     kinetic_energy::Real, envelope_wavenumber::Real,
                                     initial_spectrum = nothing, rng = Random.default_rng())
  T = _real_type(domain)
  noise = new_vector_field_physical(domain)
  copyto!(field_data(noise), randn(rng, T, physical_field_shape(domain.grid, Val(1))...))
  to_spectral!(û, noise, domain.velocity_plans)

  # The envelope is a radial symbol of |κ|², built as a lazy kernel (no field of coefficients); the
  # closures capture converted VALUES only — a captured `Type` is not a bitstype and a GPU launch
  # rejects it (PF's radial-kernel contract).
  zero_value = zero(T)
  envelope = if isnothing(initial_spectrum)
    # The envelope vanishes at κ = 0, which IS the mean removal: the κ = 0 coefficient of a field is
    # its spatial mean, so killing that mode leaves ⟨u⟩ = 0 with no physical-space pass. Without the
    # guard the Gaussian is exp(0) = 1 there and the seed carries a uniform mean flow — measured at
    # 13.5% of the seeded energy — which is not homogeneous isotropic turbulence, inflates u' and the
    # CFL speed, and sweeps every tracer. The `initial_spectrum` branch below and the scalar twin both guard.
    inverse_peak_squared = one(T) / T(envelope_wavenumber)^2
    radial_kernel(k2 -> ifelse(k2 > zero_value, exp(-inverse_peak_squared * k2), zero_value),
                  û, domain.multipliers)
  else
    # Match a target radial spectrum E(κ): a per-mode amplitude √(E(κ))/κ yields a shell-summed
    # spectrum ∝ κ²·(√E/κ)² = E(κ) (the κ² is the shell's mode count); the DC mode stays at 0.
    radial_kernel(k2 -> k2 > 0 ?
                    oftype(zero_value, sqrt(max(initial_spectrum(sqrt(k2)), zero(k2))) / sqrt(k2)) :
                    zero_value,
                  û, domain.multipliers)
  end
  # The truncation rides in the envelope rather than as a second sweep of the field: both are
  # per-mode scalar multipliers, and a scalar commutes through the (per-mode) Leray projection, so
  # composing them (radial∘radial collapses to one symbol) costs one field pass in total.
  convolve!(û, û, convolve(envelope, domain.dealias))
  helmholtz_projection!(û, û, domain.multipliers)

  # The canonical reduction, not a second spelling of it: the copy that stood here had already
  # drifted from the original, promoting a Float32 seed's energy through a Float64 literal.
  current_energy = measure_kinetic_energy(û)
  # Every seeded mode annihilated (an envelope and a dealiasing band with no overlap) leaves nothing
  # to rescale, and returning a zero field silently would hand back a state whose energy is not the
  # one asked for — which the run layer then reports as though it were.
  current_energy > 0 ||
    throw(ArgumentError("the seeded velocity has no energy to rescale: every mode was annihilated " *
                        "by the envelope and the dealiasing band together, so the requested " *
                        "`kinetic_energy` cannot be realized. Lower `envelope_wavenumber` below " *
                        "the dealiasing cutoff, or raise the resolution."))
  field_data(û) .*= sqrt(T(kinetic_energy) / current_energy)
  return û
end


"""
    random_scalar_spectral!(φ̂, domain; scalar_variance, envelope_wavenumber,
                   initial_spectrum = nothing, rng = default_rng())

Fill `φ̂` (the scalar ``\\varphi`` in spectral representation) with a random, mean-zero scalar of a
chosen spectrum, dealiased and rescaled so the variance ``\\langle\\varphi^{2}\\rangle`` equals
the requested `scalar_variance`. The
mean vanishes by
construction: the envelope is zeroed at
``\\boldsymbol{\\kappa}=\\boldsymbol{0}``, and that mode's coefficient *is* the spatial mean
``\\langle\\varphi\\rangle``.

By default (`initial_spectrum = nothing`) the scalar is concentrated at large scales by a Gaussian envelope
``\\exp\\!\\bigl(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/\\kappa_p^{2}\\bigr)`` on the mode amplitudes — zeroed,
as above, at the origin — whose
characteristic wavenumber is ``\\kappa_p`` (`envelope_wavenumber`). Because the envelope multiplies the
amplitudes, the shell-summed scalar-variance spectrum ``\\propto \\kappa^{2}\\exp\\!\\bigl(-2\\kappa^{2}/\\kappa_p^{2}\\bigr)``
peaks at ``\\kappa_p/\\sqrt{2}``, not at ``\\kappa_p`` itself (the ``\\kappa^{2}`` is the shell's mode count). The `envelope_wavenumber` setting has no effect in the `initial_spectrum` branch below, which carries its own large scale and will not generally peak there — the two modes do not seed the same large scale at the same nominal setting.
Pass `initial_spectrum`, a function ``\\kappa \\mapsto E_\\varphi(\\kappa)`` giving a target radial
scalar-variance spectrum, to seed that shape instead: each mode is scaled by
``\\sqrt{E_\\varphi(\\kappa)}/\\kappa`` (the same construction the velocity uses), so the shell-summed
spectrum is ``\\propto E_\\varphi(\\kappa)`` and the amplitude is fixed by the `scalar_variance` rescaling —
e.g. an Obukhov–Corrsin form from [`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology).

The `domain` (a [`FixedDomain`](@ref)) is what the field is generated on; the `rng` is the random
stream (defaults to `Random.default_rng()`).

Returns `φ̂`.

!!! note "Seeding a running case invalidates the observables cache"
    The cache holds what the last deposit left, so a seed written into a live run makes every cached
    observable wrong. Announce the change with
    [`fields_modified!`](@ref GBGIsotropicTurbulence.Cache.fields_modified!), which advances the
    fields epoch — the cache's freshness counter — so cached reads throw rather than serve stale
    values, then restore the cache with
    [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!) before advancing again. The
    interval between the two calls is yours to close.
"""
function random_scalar_spectral!(φ̂, domain::FixedDomain;
                        scalar_variance::Real, envelope_wavenumber::Real,
                        initial_spectrum = nothing, rng = Random.default_rng())
  T = _real_type(domain)
  noise = new_scalar_field_physical(domain)
  copyto!(field_data(noise), randn(rng, T, physical_field_shape(domain.grid, Val(0))...))
  to_spectral!(φ̂, noise, domain.scalar_plans)

  # Radial-symbol envelope, as for the velocity: lazy kernels, value-only captures.
  zero_value = zero(T)
  envelope = if isnothing(initial_spectrum)
    # The envelope vanishes at κ = 0, which IS the mean removal: the κ = 0 coefficient of a field is
    # its spatial mean, so killing that mode leaves ⟨φ⟩ = 0 without a physical-space pass or the
    # reduction one would need to measure the mean. The `initial_spectrum` branch below vanishes there too.
    inverse_peak_squared = one(T) / T(envelope_wavenumber)^2
    radial_kernel(k2 -> ifelse(k2 > zero_value, exp(-inverse_peak_squared * k2), zero_value),
                  φ̂, domain.multipliers)
  else
    # Match a target radial scalar spectrum E_φ(κ): amplitude √(E_φ(κ))/κ ⇒ shell sum ∝ E_φ(κ).
    radial_kernel(k2 -> k2 > 0 ?
                    oftype(zero_value, sqrt(max(initial_spectrum(sqrt(k2)), zero(k2))) / sqrt(k2)) :
                    zero_value,
                  φ̂, domain.multipliers)
  end
  convolve!(φ̂, φ̂, convolve(envelope, domain.dealias))   # truncation folded in, as for the velocity

  current_variance = measure_scalar_variance(φ̂)          # ⟨φ²⟩ for a mean-zero field
  current_variance > 0 ||
    throw(ArgumentError("the seeded scalar has no variance to rescale: every mode was annihilated " *
                        "by the envelope and the dealiasing band together, so the requested " *
                        "`scalar_variance` cannot be realized. Lower `envelope_wavenumber` below " *
                        "the dealiasing cutoff, or raise the resolution."))
  field_data(φ̂) .*= sqrt(T(scalar_variance) / current_variance)
  return φ̂
end

end # module State
