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
- [`ResolvedFields`](@ref) — the evolving velocity and scalar in spectral representation, and any
  forcing's evolving state. This is the single source of truth: the physical fields are recovered from
  it and never held in the state.
- [`random_solenoidal_velocity_spectral!`](@ref) and [`random_scalar_spectral!`](@ref) — the random
  initial conditions (a divergence-free velocity, a mean-zero scalar) that seed it.
- [`write_state`](@ref) / [`read_state`](@ref) — the state's HDF5 persistence: the fields in
  spectral representation and the forcing states as one self-describing group (available once `HDF5`
  is loaded).

All of them are sized to a [`FixedDomain`](@ref).

The recoveries do not disturb the state. An inverse transform consumes the coefficients it runs from,
which is a property of the FFT backends rather than a choice, so a naive recovery would destroy the
state it read. Recovery therefore goes through the four-argument
[`to_physical!`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.to_physical!), whose extra
argument is a scratch field the transform consumes in the state's place; the vorticity comes from
[`vorticity_physical!`](@ref GBGHomogeneousTurbulence.Observables.vorticity_physical!) instead. The
recovered values are deposited into the
[`ObservablesCache`](@ref GBGHomogeneousTurbulence.Cache.ObservablesCache).
"""
module State

using GBGPeriodicFields
using Random
using ..Observables: kinetic_energy as measure_kinetic_energy,
                     scalar_variance as measure_scalar_variance
using ..SimulationDomain: FixedDomain, max_retained_wavenumber, new_vector_field_spectral, new_vector_field_physical,
                          new_scalar_field_spectral, new_scalar_field_physical, _real_type

export ResolvedFields, random_solenoidal_velocity_spectral!, random_scalar_spectral!


# The seeded spectrum peaks at κ_p/√2; a peak at or beyond the retained band's edge puts most of
# the pre-rescale seed into shells the dealias mask holds empty — the energy rescale then inflates
# what little survives, and the run starts from a field nothing like the envelope's shape. The
# forcing-band warning's sibling (owner-ruled 2026-08-24).
function _warn_envelope_beyond_cutoff(domain, envelope_wavenumber)
  κ_max = max_retained_wavenumber(domain)
  peak = envelope_wavenumber / sqrt(2)
  peak >= κ_max &&
    @warn "the seed's spectrum peak κ_p/√2 = $peak sits at or beyond the dealias cutoff " *
          "$κ_max: most of the drawn field lies in masked shells, and the energy rescale will " *
          "amplify the retained residue. Lower `envelope_wavenumber` well below the cutoff."
  return nothing
end


"""
    ResolvedFields(domain; scalar = false)
    ResolvedFields(velocity_spectral, scalar_spectral,
                   modeled = (velocity_forcing = nothing, scalar_forcing = nothing))

The record of what a run advances: the evolving fields in spectral representation — the single
source of truth — and the evolving state of any forcing that carries one. The velocity, vorticity, and
scalar in physical representation are recoveries of the fields, not part of the record — since it
holds no derived copies, nothing in it can fall out of date. The
[`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!) that closes each step recovers the
physical representations into the
[`ObservablesCache`](@ref GBGHomogeneousTurbulence.Cache.ObservablesCache).

The positional form wraps existing fields without copying them, which is how a state is handed to
[`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) to adopt.

# Arguments
- `domain` — the [`FixedDomain`](@ref) to build the fields on, in the first form.
- `scalar = false` — `true` to carry a passive scalar.
- `velocity_spectral`, `scalar_spectral` — existing fields in spectral representation, in the second
  form, wrapped as they are; `scalar_spectral` is `nothing` for a run without a scalar.
- `modeled` — the forcing states, in the second form. The first form, and the second without it,
  leave it empty; a `Simulation` fills it from its forcings, starting any forcing state the record does not already carry.

# Fields
- `velocity_spectral` — the velocity in spectral representation, ``\\hat{\\boldsymbol{u}}``.
- `scalar_spectral` — the scalar in spectral representation, ``\\hat\\varphi``, or `nothing` when the
  run carries no passive scalar.
- `modeled` — each forcing's evolving state, as it stands now:
  `(velocity_forcing = …, scalar_forcing = …)`. A forcing's
  [`initial_forcing_state`](@ref GBGHomogeneousTurbulence.Forcing.initial_forcing_state) creates the
  entry and its [`prepare_forcing!`](@ref GBGHomogeneousTurbulence.Forcing.prepare_forcing!) advances it
  once per step; it is `nothing` for a forcing without one, which is every strategy but
  [`StochasticOU`](@ref GBGHomogeneousTurbulence.Forcing.StochasticOU), whose entry is a
  [`StochasticOUState`](@ref GBGHomogeneousTurbulence.Forcing.StochasticOUState). A stochastic forcing's
  process lives here rather than in the forcing, so this record is the whole evolving state of the
  run: saving it saves everything that advances.
"""
struct ResolvedFields{UH, PH, MD<:NamedTuple{(:velocity_forcing, :scalar_forcing)}}
  velocity_spectral::UH          # û (spectral) — the resolved velocity, the single source of truth
  scalar_spectral::PH            # φ̂ (spectral), or nothing when the run carries no scalar
  modeled::MD                    # each forcing's evolving state (decision 23(c)), or nothing per field
end

const NO_FORCING_STATE = (velocity_forcing = nothing, scalar_forcing = nothing)

ResolvedFields(velocity_spectral, scalar_spectral) =
  ResolvedFields(velocity_spectral, scalar_spectral, NO_FORCING_STATE)

ResolvedFields(domain::FixedDomain; scalar::Bool = false) =
  ResolvedFields(new_vector_field_spectral(domain), scalar ? new_scalar_field_spectral(domain) : nothing)

# Display (the convention is stated once, at `SimulationDomain`'s display section). The two
# representations-of-record, each through the field library's own `show` — grid, element type,
# storage — which is exactly what a run checks a state against; the scalar's absence is said aloud,
# and a forcing state appears only when one is carried.
function Base.show(io::IO, state::ResolvedFields)
  print(io, "ResolvedFields(û ", state.velocity_spectral)
  isnothing(state.scalar_spectral) ? print(io, ", no scalar") : print(io, ", φ̂ ", state.scalar_spectral)
  isnothing(state.modeled.velocity_forcing) || print(io, ", velocity forcing state ", state.modeled.velocity_forcing)
  isnothing(state.modeled.scalar_forcing) || print(io, ", scalar forcing state ", state.modeled.scalar_forcing)
  print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", state::ResolvedFields)
  print(io, "ResolvedFields")
  print(io, "\n  velocity_spectral  û  ", state.velocity_spectral)
  print(io, "\n  scalar_spectral    φ̂  ", something(state.scalar_spectral, "nothing (no scalar)"))
  print(io, "\n  modeled            velocity forcing ", something(state.modeled.velocity_forcing, "nothing"),
        ", scalar forcing ", something(state.modeled.scalar_forcing, "nothing"))
end


# Standard normal noise drawn on the HOST, so a seed gives the same field on every backend (decision
# 107, which extends the forcing's rule of decision 90 to every draw). On the CPU the drawn
# array IS the noise field's storage; on a device it is moved into a device field. The first form saved
# a field-sized copy on the CPU (2026-10-01) and reaches no raw storage.
function _host_noise(rng, T, domain, ::Val{R}) where {R}
  host = randn(rng, T, field_physical_shape(domain.grid, Val(R))...)
  drawn = R == 0 ? ScalarFieldPhysical(host, domain.grid; layout = domain.layout) :
                   VectorFieldPhysical(host, domain.grid; layout = domain.layout)
  domain.array_family === Array && return drawn
  noise = R == 0 ? new_scalar_field_physical(domain) : new_vector_field_physical(domain)
  adapt!(noise, drawn)
  return noise
end


"""
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy, envelope_wavenumber,
                                initial_spectrum = nothing, rng = default_rng())

Fill `û` (a velocity field in spectral representation) with a random, divergence-free velocity
``\\boldsymbol{u}`` of a chosen energy spectrum, dealiased and rescaled so the kinetic energy
``\\tfrac{1}{2}\\langle\\lvert\\boldsymbol{u}\\rvert^{2}\\rangle`` equals the requested
`kinetic_energy`. The Leray–Helmholtz projection ``\\mathbb{P}`` enforces
``\\nabla\\cdot\\boldsymbol{u} = 0``.

# Arguments
- `û` — the velocity field in spectral representation to fill.
- `domain` — the [`FixedDomain`](@ref) the field is generated on.
- `kinetic_energy` — the kinetic energy the seeded field is rescaled to.
- `envelope_wavenumber` — the Gaussian envelope's characteristic wavenumber ``\\kappa_p`` (the
  default branch below); inert when `initial_spectrum` is given.
- `initial_spectrum = nothing` — a target radial energy spectrum ``\\kappa \\mapsto E(\\kappa)``
  (the second branch below).
- `rng = default_rng()` — the random stream.

By default (`initial_spectrum = nothing`) the velocity is concentrated at large scales by a Gaussian
envelope ``\\exp\\bigl(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/\\kappa_p^{2}\\bigr)`` on the mode
amplitudes, zeroed at ``\\boldsymbol{\\kappa} = \\boldsymbol{0}`` so the mean mode stays empty; its
characteristic wavenumber ``\\kappa_p`` is `envelope_wavenumber`. Because the envelope multiplies the
amplitudes, the shell-summed energy spectrum
``\\propto \\kappa^{2}\\exp\\bigl(-2\\kappa^{2}/\\kappa_p^{2}\\bigr)`` peaks at
``\\kappa_p/\\sqrt{2}``, not at ``\\kappa_p`` itself (the ``\\kappa^{2}`` is the shell's mode count).
Keep ``\\kappa_p`` well below the dealias cutoff: a value near or above it puts most of the
pre-rescale seed into shells the dealiasing truncation zeroes, and the seeder warns when the peak
``\\kappa_p/\\sqrt{2}`` reaches the cutoff.

Pass `initial_spectrum`, a function ``\\kappa \\mapsto E(\\kappa)`` giving a target radial energy
spectrum, to seed that shape instead — e.g. a von Kármán or Pope form from the
[`Phenomenology`](@ref GBGHomogeneousTurbulence.Phenomenology) submodule's model spectra, which the run
layer can wire in for you ([`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) forwards its `initial_spectrum` keyword here). Each mode is
scaled by ``\\sqrt{E(\\kappa)}/\\kappa``, so the shell-summed spectrum is
``\\propto \\kappa^{2}(\\sqrt{E}/\\kappa)^{2} = E(\\kappa)`` and the overall amplitude is fixed by
the `kinetic_energy` rescaling. In this branch `envelope_wavenumber` has no effect: the spectrum
carries its own large scale and will not generally peak at ``\\kappa_p/\\sqrt{2}``.

Returns `û`.

!!! note "Seeding a running simulation invalidates the observables cache"
    The cache holds what the last
    [`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!) — the end-of-step write of the
    observables — left, so a seed written into a live run makes every cached observable wrong. Announce the change with
    [`fields_modified!`](@ref GBGHomogeneousTurbulence.Cache.fields_modified!), which advances the
    fields epoch — the cache's freshness counter — so cached reads throw rather than serve stale
    values, then restore the cache with `deposit!` before advancing again. The
    interval between the two calls is yours to close.
"""
function random_solenoidal_velocity_spectral!(û, domain::FixedDomain;
                                     kinetic_energy::Real, envelope_wavenumber::Real,
                                     initial_spectrum = nothing, rng = Random.default_rng())
  T = _real_type(domain)
  isnothing(initial_spectrum) && _warn_envelope_beyond_cutoff(domain, envelope_wavenumber)
  noise = _host_noise(rng, T, domain, Val(1))
  to_spectral!(û, noise, domain.transform_plans)

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
                  domain.multipliers)
  else
    # Match a target radial spectrum E(κ): a per-mode amplitude √(E(κ))/κ yields a shell-summed
    # spectrum ∝ κ²·(√E/κ)² = E(κ) (the κ² is the shell's mode count); the DC mode stays at 0.
    radial_kernel(k2 -> k2 > 0 ?
                    oftype(zero_value, sqrt(max(initial_spectrum(sqrt(k2)), zero(k2))) / sqrt(k2)) :
                    zero_value,
                  domain.multipliers)
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
  multiply!(û, sqrt(T(kinetic_energy) / current_energy), û)
  return û
end


"""
    random_scalar_spectral!(φ̂, domain; scalar_variance, envelope_wavenumber,
                   initial_spectrum = nothing, rng = default_rng())

Fill `φ̂` (the scalar ``\\varphi`` in spectral representation) with a random, mean-zero scalar of a
chosen spectrum, dealiased and rescaled so the variance ``\\langle\\varphi^{2}\\rangle`` equals the
requested `scalar_variance`. The mean vanishes by construction: the envelope is zeroed at
``\\boldsymbol{\\kappa}=\\boldsymbol{0}``, and that mode's coefficient *is* the spatial mean
``\\langle\\varphi\\rangle``.

# Arguments
- `φ̂` — the scalar field in spectral representation to fill.
- `domain` — the [`FixedDomain`](@ref) the field is generated on.
- `scalar_variance` — the variance the seeded field is rescaled to.
- `envelope_wavenumber` — the Gaussian envelope's characteristic wavenumber ``\\kappa_p`` (the
  default branch below); inert when `initial_spectrum` is given.
- `initial_spectrum = nothing` — a target radial scalar-variance spectrum
  ``\\kappa \\mapsto E_\\varphi(\\kappa)`` (the second branch below).
- `rng = default_rng()` — the random stream.

By default (`initial_spectrum = nothing`) the scalar is concentrated at large scales by a Gaussian
envelope ``\\exp\\bigl(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/\\kappa_p^{2}\\bigr)`` on the mode
amplitudes — zeroed, as above, at the origin — whose characteristic wavenumber ``\\kappa_p`` is
`envelope_wavenumber`. Because the envelope multiplies the amplitudes, the shell-summed
scalar-variance spectrum ``\\propto \\kappa^{2}\\exp\\bigl(-2\\kappa^{2}/\\kappa_p^{2}\\bigr)``
peaks at ``\\kappa_p/\\sqrt{2}``, not at ``\\kappa_p`` itself (the ``\\kappa^{2}`` is the shell's
mode count). Keep ``\\kappa_p`` well below the dealias cutoff — a value near or above it puts most
of the pre-rescale seed into shells the dealiasing truncation zeroes, and the seeder warns when the peak
``\\kappa_p/\\sqrt{2}`` reaches the cutoff.

Pass `initial_spectrum`, a function ``\\kappa \\mapsto E_\\varphi(\\kappa)`` giving a target radial
scalar-variance spectrum, to seed that shape instead — e.g. an Obukhov–Corrsin form from
[`Phenomenology`](@ref GBGHomogeneousTurbulence.Phenomenology). Each mode is scaled by
``\\sqrt{E_\\varphi(\\kappa)}/\\kappa`` (the same construction the velocity uses), so the
shell-summed spectrum is ``\\propto E_\\varphi(\\kappa)`` and the amplitude is fixed by the
`scalar_variance` rescaling. In this branch `envelope_wavenumber` has no effect: the spectrum
carries its own large scale and will not generally peak at ``\\kappa_p/\\sqrt{2}``.

Returns `φ̂`.

!!! note "Seeding a running simulation invalidates the observables cache"
    The cache holds what the last
    [`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!) — the end-of-step write of the
    observables — left, so a seed written into a live run makes every cached observable wrong. Announce the change with
    [`fields_modified!`](@ref GBGHomogeneousTurbulence.Cache.fields_modified!), which advances the
    fields epoch — the cache's freshness counter — so cached reads throw rather than serve stale
    values, then restore the cache with `deposit!` before advancing again. The
    interval between the two calls is yours to close.
"""
function random_scalar_spectral!(φ̂, domain::FixedDomain;
                        scalar_variance::Real, envelope_wavenumber::Real,
                        initial_spectrum = nothing, rng = Random.default_rng())
  T = _real_type(domain)
  isnothing(initial_spectrum) && _warn_envelope_beyond_cutoff(domain, envelope_wavenumber)
  noise = _host_noise(rng, T, domain, Val(0))
  to_spectral!(φ̂, noise, domain.transform_plans)

  # Radial-symbol envelope, as for the velocity: lazy kernels, value-only captures.
  zero_value = zero(T)
  envelope = if isnothing(initial_spectrum)
    # The envelope vanishes at κ = 0, which IS the mean removal: the κ = 0 coefficient of a field is
    # its spatial mean, so killing that mode leaves ⟨φ⟩ = 0 without a physical-space pass or the
    # reduction one would need to measure the mean. The `initial_spectrum` branch below vanishes there too.
    inverse_peak_squared = one(T) / T(envelope_wavenumber)^2
    radial_kernel(k2 -> ifelse(k2 > zero_value, exp(-inverse_peak_squared * k2), zero_value),
                  domain.multipliers)
  else
    # Match a target radial scalar spectrum E_φ(κ): amplitude √(E_φ(κ))/κ ⇒ shell sum ∝ E_φ(κ).
    radial_kernel(k2 -> k2 > 0 ?
                    oftype(zero_value, sqrt(max(initial_spectrum(sqrt(k2)), zero(k2))) / sqrt(k2)) :
                    zero_value,
                  domain.multipliers)
  end
  convolve!(φ̂, φ̂, convolve(envelope, domain.dealias))   # truncation folded in, as for the velocity

  current_variance = measure_scalar_variance(φ̂)          # ⟨φ²⟩ for a mean-zero field
  current_variance > 0 ||
    throw(ArgumentError("the seeded scalar has no variance to rescale: every mode was annihilated " *
                        "by the envelope and the dealiasing band together, so the requested " *
                        "`scalar_variance` cannot be realized. Lower `envelope_wavenumber` below " *
                        "the dealiasing cutoff, or raise the resolution."))
  multiply!(φ̂, sqrt(T(scalar_variance) / current_variance), φ̂)
  return φ̂
end



# ————————————————————————————————————————————————————————————————————————————————————————————————
# HDF5 persistence. The bare generics live here so the docstrings and the docs build work without
# HDF5 in the environment; the methods live in the `GBGHomogeneousTurbulenceHDF5Ext` weak-dependency
# extension, loaded automatically alongside the HDF5 package (the arrangement the field library's
# persistence pairs established).

export write_state, read_state


"""
    write_state(parent::HDF5.H5DataStore, name::AbstractString, state::ResolvedFields)

Write the [`ResolvedFields`](@ref) `state` under `parent` as one self-describing HDF5 group — the
velocity, and the scalar when the run carries one, each a nested field group in spectral
representation, and each forcing state it carries. The spectral representation is the single
source of truth, so no physical representation is stored. Available once the `HDF5` package is loaded;
the caller owns the file.

# Arguments
- `parent` — the open HDF5 file or group to write under.
- `name` — the created group's name.
- `state` — the `ResolvedFields` to record.

Returns the created group. Reload with [`read_state`](@ref).
"""
function write_state end


"""
    read_state(parent::HDF5.H5DataStore, name::AbstractString,
               domain::FixedDomain) -> ResolvedFields

Rebuild a [`ResolvedFields`](@ref) from the group [`write_state`](@ref) wrote, allocated on and
copied to the storage backend of `domain`, a [`FixedDomain`](@ref) that must agree with the file in
grid (point count, side length and origin) and element type. A domain that disagrees is refused with an `ArgumentError`, as is a group
not written by `write_state`. The forcing states come back with the fields; a group written before
forcing states were stored reads with none, and a run adopting it starts its forcing afresh.
Available once the `HDF5` package is loaded.

# Arguments
- `parent` — the open HDF5 file or group holding the state group.
- `name` — the group's name.
- `domain` — the `FixedDomain` whose backend the rebuilt state lives on.
"""
function read_state end


end # module State
