# State — the DNS realization of the Mori–Zwanzig State role: `ResolvedFields` (the evolving spectral
# velocity and scalar — the single source of truth; the physical fields are derived, never stored),
# the recovery map that recovers the physical representations, `ObservablesCache` (the stamped, memoized
# observation cache those recoveries fill), and the random initial conditions that seed a run. The
# per-step scratch lives with the integrator (`IntegratorBuffers` in `Propagator`). Everything is
# sized to a `FixedDomain` from `SimulationDomain`.

"""
    State

The evolving state a run advances, its derived views, and how it is seeded:
- [`ResolvedFields`](@ref) — the inert record of the evolving velocity and scalar in spectral
  representation (the single source of truth; the physical fields are derived, never stored).
- [`velocity_to_physical!`](@ref), [`vorticity_to_physical!`](@ref), [`scalar_to_physical!`](@ref) —
  recover the velocity, vorticity, and scalar in physical representation from the spectral state.
- [`ObservablesCache`](@ref) — the observation cache: stamped, memoized derived fields with
  recompute-on-staleness accessors.
- [`physical_velocity`](@ref), [`physical_vorticity`](@ref) — the sanctioned reads of the cached
  velocity and vorticity in physical representation.
- [`resolved_fields_modified!`](@ref) — declare an out-of-band state mutation so every cached observable
  is recomputed on its next read; [`spectral_scratch`](@ref) — the cache's spectral working space.
- [`random_solenoidal_velocity!`](@ref) and [`random_scalar!`](@ref) — the random initial conditions
  (a divergence-free velocity, a mean-zero scalar) that seed it.

All sized to a [`FixedDomain`](@ref).
"""
module State

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, spectral_vector, physical_vector,
                          scalar_spectral, scalar_physical, _real_type

export ResolvedFields, random_solenoidal_velocity!, random_scalar!,
       velocity_to_physical!, vorticity_to_physical!, scalar_to_physical!,
       ObservablesCache, physical_velocity, physical_vorticity, resolved_fields_modified!,
       spectral_scratch


"""
    ResolvedFields(domain; scalar = false)

The inert record of the evolving fields a run advances, in spectral representation — the single source
of truth, from which the velocity, vorticity, and scalar in physical representation are derived on demand
and never stored, so the state cannot go stale. Build it on a [`FixedDomain`](@ref); pass `scalar = true`
to carry a passive scalar.

# Fields
- `velocity` — the velocity in spectral representation, ``\\hat{\\boldsymbol{u}}``.
- `scalar` — the scalar in spectral representation, ``\\hat\\varphi``, or `nothing` when the run carries
  no passive scalar.
"""
struct ResolvedFields{UH, PH}
  velocity::UH                   # û (spectral) — the resolved velocity, the single source of truth
  scalar::PH                     # φ̂ (spectral), or nothing when the run carries no scalar
end

ResolvedFields(domain::FixedDomain; scalar::Bool = false) =
  ResolvedFields(spectral_vector(domain), scalar ? scalar_spectral(domain) : nothing)


"""
    velocity_to_physical!(u, û, domain, spectral_scratch)

Recover the velocity in physical representation into `u`, from the spectral `û` (left unchanged), on
the [`FixedDomain`](@ref) `domain` whose transform plans carry it. The scratch `spectral_scratch` (a
vector field in spectral representation) is the working space.
"""
function velocity_to_physical!(u, û, domain::FixedDomain, spectral_scratch)
  copyto!(field_data(spectral_scratch), field_data(û))  # copy û first — the in-place inverse transform consumes its spectral source
  to_physical!(u, spectral_scratch, domain.velocity_plans)
  return u
end


"""
    vorticity_to_physical!(ω, û, domain, spectral_scratch)

Compute the vorticity ``\\boldsymbol{\\omega} = \\nabla\\times\\boldsymbol{u}`` in physical representation
into `ω`, from the velocity `û` in spectral representation, leaving `û` untouched. The spectral vorticity
``\\mathrm{i}\\boldsymbol{\\kappa}\\times\\hat{\\boldsymbol{u}}`` is formed in the scratch
`spectral_scratch` (a vector field in spectral representation) and transformed to physical
representation by the [`FixedDomain`](@ref) `domain`'s plans.
"""
function vorticity_to_physical!(ω, û, domain::FixedDomain, spectral_scratch)
  curl!(spectral_scratch, û, domain.multipliers)
  to_physical!(ω, spectral_scratch, domain.velocity_plans)
  return ω
end


"""
    scalar_to_physical!(φ, φ̂, domain, scalar_scratch)

Recover the scalar in physical representation into `φ`, from the spectral `φ̂` (left unchanged), on the
[`FixedDomain`](@ref) `domain` whose transform plans carry it. The scratch `scalar_scratch` (a scalar
field in spectral representation) is the working space.
"""
function scalar_to_physical!(φ, φ̂, domain::FixedDomain, scalar_scratch)
  copyto!(field_data(scalar_scratch), field_data(φ̂))  # copy φ̂ first — the in-place inverse transform consumes its spectral source
  to_physical!(φ, scalar_scratch, domain.scalar_plans)
  return φ
end


# One observation-cache slot: the derived field's preallocated storage plus the fields epoch it was
# last computed at (0 = never). Mutable so an accessor can restamp in place.
mutable struct Stamped{F}
  value::F
  stamp::Int
end


"""
    ObservablesCache(domain; observables = (:velocity, :vorticity))

The observation cache of a run — preallocated, stamped, memoized derived fields, giving every reader
(a diagnostic, a particle push, a statistics callback) a sanctioned way to the physical representations
the time loop would otherwise compute and discard. Each slot holds a derived field's values —
on the grid lattice, or (for future trajectory-bound observables) at the tracer positions; particle content
never enters. An accessor ([`physical_velocity`](@ref), [`physical_vorticity`](@ref)) returns the
stored field when it is current for the present state and recomputes it first otherwise, so a stale
read is impossible.

Build the cache on a [`FixedDomain`](@ref); `observables` names the slots to allocate — resident memory is
opt-in, and reading one that was not declared is an error. The available observables are `:velocity`
(the velocity ``\\boldsymbol{u}`` in physical representation) and `:vorticity` (the vorticity
``\\boldsymbol{\\omega} = \\nabla\\times\\boldsymbol{u}`` in physical representation).

# Freshness
The cache carries one epoch counter per dynamical factor of the run — `fields_epoch` for the resolved
fields (advanced by every completed `step!`, and by [`resolved_fields_modified!`](@ref) after an
out-of-band mutation) and `particles_epoch` for the tracers (reserved for trajectory-bound observables).
A slot's stamp records the epoch it was computed at; a stamp behind the epoch marks the slot stale,
and the accessor recomputes and restamps it on the next read.

# Fields
- `observables` — a `NamedTuple` of the allocated slots; each slot holds the value's preallocated
  storage and its stamp.
- `spectral_scratch` — the cache's spectral working space (see [`spectral_scratch`](@ref)).
- `fields_epoch`, `particles_epoch` — the per-factor epoch counters.
"""
mutable struct ObservablesCache{NT, S}
  observables::NT
  spectral_scratch::S
  fields_epoch::Int
  particles_epoch::Int
end


function ObservablesCache(domain::FixedDomain; observables = (:velocity, :vorticity))
  known = (:velocity, :vorticity)
  for name in observables
    name in known ||
      throw(ArgumentError("unknown observable :$name; this cache offers $known"))
  end
  slots = NamedTuple{Tuple(observables)}(Tuple(Stamped(physical_vector(domain), 0) for _ in observables))
  return ObservablesCache(slots, spectral_vector(domain), 1, 1)
end


# Fetch a slot, with a complete-at-the-REPL error when the observable was not declared.
function _slot(derived::ObservablesCache, key::Symbol)
  hasproperty(derived.observables, key) ||
    throw(ArgumentError("the observable :$key was not cached for this run; declare it in the " *
                        "`observables` of `ObservablesCache` (resident memory is opt-in)"))
  return getproperty(derived.observables, key)
end


"""
    physical_velocity(derived, state, domain)
    physical_velocity(sim)

The velocity ``\\boldsymbol{u}`` in physical representation, current for the `state` — the sanctioned
read of the derived velocity field. When the [`ObservablesCache`](@ref) `cache`'s `:velocity` slot is
already current (its stamp matches the fields epoch) the stored field is returned as is; otherwise it
is first recomputed from the spectral ``\\hat{\\boldsymbol{u}}`` of `state` (a [`ResolvedFields`](@ref))
by [`velocity_to_physical!`](@ref) on the [`FixedDomain`](@ref) `domain`, and restamped. Treat the
returned field as read-only: it is the cache's storage, shared by every reader until the fields next
advance. The second form reads a `Simulation`'s cache, state, and domain.
"""
function physical_velocity(derived::ObservablesCache, state::ResolvedFields, domain::FixedDomain)
  slot = _slot(derived, :velocity)
  if slot.stamp != derived.fields_epoch
    velocity_to_physical!(slot.value, state.velocity, domain, derived.spectral_scratch)
    slot.stamp = derived.fields_epoch
  end
  return slot.value
end


"""
    physical_vorticity(derived, state, domain)
    physical_vorticity(sim)

The vorticity ``\\boldsymbol{\\omega} = \\nabla\\times\\boldsymbol{u}`` in physical representation,
current for the `state` — the sanctioned read of the derived vorticity field, memoized exactly as
[`physical_velocity`](@ref) (recomputed by [`vorticity_to_physical!`](@ref) when stale, returned as is
when current; treat as read-only). The second form reads a `Simulation`'s cache, state, and domain.
"""
function physical_vorticity(derived::ObservablesCache, state::ResolvedFields, domain::FixedDomain)
  slot = _slot(derived, :vorticity)
  if slot.stamp != derived.fields_epoch
    vorticity_to_physical!(slot.value, state.velocity, domain, derived.spectral_scratch)
    slot.stamp = derived.fields_epoch
  end
  return slot.value
end


"""
    resolved_fields_modified!(derived)
    resolved_fields_modified!(sim)

Declare that the resolved fields — the spectral ``\\hat{\\boldsymbol{u}}``, ``\\hat\\varphi`` — were
changed outside the sanctioned propagators (a re-seeded velocity, any direct write to the state's
storage), so every cached observable is stale and will be recomputed on its next read. Advances the
cache's fields epoch and returns `derived`.

The sanctioned mutators call this for you: `step!` advances the epoch itself when it completes. A
hand-run loop that mutates the spectral state directly **must** call it — a forgotten call leaves the
cached values serving the previous fields, the one staleness the cache cannot detect on its own.
"""
resolved_fields_modified!(derived::ObservablesCache) = (derived.fields_epoch += 1; derived)


"""
    spectral_scratch(derived)

The observation cache's working space in spectral representation (a vector field) — the scratch the
recomputations, and the run layer's spectral reductions, write through. Its contents are
undefined between operations: any single operation may use it freely; nothing may store into it
across operations.
"""
spectral_scratch(derived::ObservablesCache) = derived.spectral_scratch


"""
    random_solenoidal_velocity!(û, domain; kinetic_energy, peak_wavenumber,
                                spectrum = nothing, rng = default_rng())

Fill `û` (a velocity field in spectral representation) with a random, divergence-free velocity
``\\boldsymbol{u}`` of a chosen energy spectrum, dealiased and rescaled so the kinetic energy
``\\tfrac{1}{2}\\langle\\lvert\\boldsymbol{u}\\rvert^{2}\\rangle`` equals `kinetic_energy`. The Leray–Helmholtz
projection ``\\mathbb{P}`` enforces ``\\nabla\\cdot\\boldsymbol{u} = 0``.

By default (`spectrum = nothing`) the velocity is concentrated at large scales by a Gaussian envelope
``\\exp\\!\\big(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/\\kappa_p^{2}\\big)`` on the mode amplitudes, whose
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
    Seeding into a running case mutates the resolved fields out of band — follow it with
    [`resolved_fields_modified!`](@ref) so the cached observables are recomputed on their next read.
"""
function random_solenoidal_velocity!(û, domain::FixedDomain;
                                     kinetic_energy::Real, peak_wavenumber::Real,
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
  # The truncation rides in the envelope rather than as a second sweep of the field: both are
  # per-mode scalar multipliers, and a scalar commutes through the (per-mode) Leray projection, so
  # folding them costs one scalar-field pass instead of a whole vector field's.
  convolve!(envelope, envelope, domain.dealias)
  convolve!(û, û, envelope)
  helmholtz_projection!(û, û, domain.multipliers)

  current_energy = 0.5 * inner(û, û)
  current_energy > 0 && (field_data(û) .*= sqrt(T(kinetic_energy) / current_energy))
  return û
end


"""
    random_scalar!(φ̂, domain; scalar_variance, peak_wavenumber,
                   spectrum = nothing, rng = default_rng())

Fill `φ̂` (the scalar ``\\varphi`` in spectral representation) with a random, mean-zero scalar of a
chosen spectrum, dealiased and rescaled so the variance ``\\langle\\varphi^{2}\\rangle`` equals
`scalar_variance`. The mean vanishes by construction: the envelope is zero at
``\\boldsymbol{\\kappa}=\\boldsymbol 0``, and that mode's coefficient *is* the spatial mean
``\\langle\\varphi\\rangle``.

By default (`spectrum = nothing`) the scalar is concentrated at large scales by a Gaussian envelope
``\\exp\\!\\big(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/\\kappa_p^{2}\\big)`` on the mode amplitudes, whose
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
    Seeding into a running case mutates the resolved fields out of band — follow it with
    [`resolved_fields_modified!`](@ref) so the cached observables are recomputed on their next read.
"""
function random_scalar!(φ̂, domain::FixedDomain;
                        scalar_variance::Real, peak_wavenumber::Real,
                        spectrum = nothing, rng = Random.default_rng())
  T = _real_type(domain)
  noise = scalar_physical(domain)
  copyto!(field_data(noise), randn(rng, T, physical_field_shape(domain.grid, Val(0))...))
  to_spectral!(φ̂, noise, domain.scalar_plans)

  envelope = scalar_spectral(domain)
  if isnothing(spectrum)
    # The envelope vanishes at κ = 0, which IS the mean removal: the κ = 0 coefficient of a field is
    # its spatial mean, so killing that mode leaves ⟨φ⟩ = 0 without a physical-space pass or the
    # reduction one would need to measure the mean. The `spectrum` branch below vanishes there too.
    inverse_peak_squared = one(T) / T(peak_wavenumber)^2
    field_data(envelope) .= complex.(ifelse.(domain.squared_wavenumber .> 0,
                                             exp.((-inverse_peak_squared) .* domain.squared_wavenumber),
                                             zero(T)))
  else
    # Match a target radial scalar spectrum E_φ(κ): amplitude √(E_φ(κ))/κ ⇒ shell sum ∝ E_φ(κ).
    shape = k2 -> k2 > 0 ? T(sqrt(max(spectrum(sqrt(k2)), zero(k2))) / sqrt(k2)) : zero(T)
    field_data(envelope) .= complex.(shape.(domain.squared_wavenumber))
  end
  convolve!(envelope, envelope, domain.dealias)      # truncation folded in, as for the velocity
  convolve!(φ̂, φ̂, envelope)

  current_variance = inner(φ̂, φ̂)                         # ⟨φ²⟩ for a mean-zero field
  current_variance > 0 && (field_data(φ̂) .*= sqrt(T(scalar_variance) / current_variance))
  return φ̂
end

end # module State
