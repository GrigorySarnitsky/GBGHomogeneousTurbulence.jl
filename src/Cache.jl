# Cache — the observables cache: the storage where a component of the iteration puts a value another
# component (or the caller, between iterations) will read. The design is the no-recompute rule
# (docs/src/observables_cache.md): the schedule is fixed at construction and identical on every
# iteration; every slot is deposited at the end of the iteration from the state it has just
# produced; a read either finds a current value or throws — there is no path, internal or on
# request, by which reading causes a computation. A slot IS the register its producer computes in:
# mid-iteration the step takes the array as stage scratch (marking its epoch as scratch), and the
# closing deposit re-fills it, so caching adds nothing to what an iteration computes, moves, or stores.

"""
    Cache

The observables cache — where the iteration leaves the observables it produces, so that the run's
own components, and the caller between iterations, read them instead of computing them again. Each value is *deposited*, written together with its
*epoch*: the version of the state it was computed from, a number raised by one with each step and
each tracer push.

The cache's operations:
- [`ObservablesCache`](@ref) — the cache itself: the slots, their epochs, and the two counters.
- [`velocity_physical`](@ref), [`vorticity_physical`](@ref), [`scalar_physical`](@ref) — the checked
  reads of the cached fields (the velocity, vorticity, and scalar in physical representation).
- [`max_speed`](@ref GBGHomogeneousTurbulence.Observables.max_speed) — the cached largest flow speed,
  the number the timestep choice reads (one generic with the field reduction in `Observables`, whose
  docstring is the home).
- [`velocity_at_particles_trail`](@ref) — the checked read of the velocity sampled along each
  trajectory: its last few samples, the newest first.

The field slots are filled by [`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!), which
`Propagator` owns rather than this module because it needs the scheme's scratch to recover the
fields. Each slot carries both the value and the epoch that value belongs to, so a read can be refused
rather than served stale.

The solver's side of the contract is that `deposit!` fills every field-derived slot at the
iteration's end (the trail of the velocity at the particles receives its new sample from the same
generic's particle form, after the tracers advance) and sets
its epoch. A caller reads through the accessors.

The cache keeps one epoch counter per dynamical factor — the resolved fields, the tracer positions —
and a slot is readable exactly when its own epoch equals the counter it depends on.
"""
module Cache

using GBGPeriodicFields: field_scalar_type
using ..SimulationDomain: FixedDomain, new_vector_field_physical, new_scalar_field_physical
using ..Particles: Tracers, ParticleTrail, new_vector_point_values, trail_capacity,
                   _new_trail, _next_slot!, _check_time, _push!, _empty!, _capacity
import ..Observables: max_speed           # one generic: the field reduction there, the cached read here

export ObservablesCache, velocity_physical, vorticity_physical, scalar_physical,
       velocity_at_particles_trail


# Epoch sentinels. A slot's epoch is the fields epoch it was deposited at; the sentinels mark the
# two states with no value: never deposited (fresh construction, or a cleared cache) and taken as a
# producer's mid-iteration scratch.
const NEVER_DEPOSITED = -2
const SCRATCH = -1


"""
    ObservablesCache(domain; scalar = false, tracers = nothing,
                     particle_integration_scheme = nothing)

The observables cache of a run — the storage where each iteration deposits, at its end, the
observables its own schedule produces: the velocity ``\\boldsymbol{u}`` and vorticity
``\\boldsymbol{\\omega}`` in physical representation, the scalar ``\\varphi`` in physical
representation when the run carries one, the fastest flow speed on the grid (the
[`max_speed`](@ref GBGHomogeneousTurbulence.Observables.max_speed) number the next timestep choice
reads), and — when the run advects tracers — the flow velocity at the tracer positions
``\\boldsymbol{X}``, ``\\boldsymbol{u}(t, \\boldsymbol{X}(t))``, at the current time and at the
few earlier times the particle integration scheme works from.

The contents are automatic, derived from the configuration: the cache holds
exactly what the iteration computes, materializes, and leaves alive at its end, and nothing more.
The cache allocates and owns every slot, the velocity at the particles included — that sample is an
observable of the flow, not particle state (a tracer has no velocity of its own), so its storage
lives here and the tracer push writes into it exactly as the step writes into the field slots.

Build it on a [`FixedDomain`](@ref) `domain`. [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) builds, wires,
and seeds one for you.

# Arguments
- `domain` — the `FixedDomain` the run lives on; it sizes every field slot.
- `scalar = false` — pass `true` when the run evolves a passive scalar, which adds the scalar's slot.
- `tracers = nothing` — the [`Tracers`](@ref GBGHomogeneousTurbulence.Particles.Tracers) the run
  advects; they size the trail of the velocity at the particles.
- `particle_integration_scheme = nothing` — the scheme that advances those tracers, which fixes how
  many samples the trail keeps. Give both of these or neither.

Read through the accessors — [`velocity_physical`](@ref), [`vorticity_physical`](@ref),
[`scalar_physical`](@ref), [`velocity_at_particles_trail`](@ref), and `max_speed` — each of which
returns the deposited value or throws.
Nothing in the cache is ever recomputed: a read that finds a slot stale, *taken* (in use as the
step's own scratch mid-iteration), or never deposited throws an `ErrorException` naming the slot
and its state — a scheduling error whose only repair is to fix the schedule that failed to
deposit.

!!! note "A cached array is the next iteration's scratch"
    A slot is also the array its producer computes in: between deposits the step writes its own
    stage values there, so a cached field is meaningful only between iterations. Treat every
    returned array as read-only — it is the storage the next iteration will work in.

# Fields
The word *epoch* names two things here, and these fields are of both kinds. The two counters, `fields_epoch` and
`particles_epoch`, rise as the state and the positions change; every other `*_epoch` field records the counter's value at the moment its slot
was filled. A slot is readable exactly while the epoch it records still equals the counter it
depends on.

- `velocity_physical`, `vorticity_physical` — the cached velocity and vorticity in physical
  representation. Mid-iteration the step also writes each stage's velocity and vorticity *into
  these same arrays*, which is why they are not readable then.

- `scalar_physical` — the cached scalar in physical representation, or `nothing` for a scalar-free run.

- `max_speed` — the cached fastest flow speed (a host number in the field's own element type).

- `velocity_at_particles_trail` — the
  [`ParticleTrail`](@ref GBGHomogeneousTurbulence.Particles.ParticleTrail) of the velocity sampled
  at the particle positions, or `nothing` for a tracer-free run.

- `velocity_epoch`, `vorticity_epoch`, `scalar_epoch`, `max_speed_epoch` — the epoch each slot's
  value was deposited at, or a sentinel (never deposited / in use as scratch).

- `velocity_at_particles_epoch` — the particles epoch the trail's newest sample was taken at.

- `fields_epoch` — the resolved fields' counter, advanced by every completed step. A field-derived
  slot is readable exactly when its epoch equals this.

- `particles_epoch` — the tracer positions' counter, advanced by every
  [`advect!`](@ref GBGHomogeneousTurbulence.ParticlePropagator.advect!) push.
"""
mutable struct ObservablesCache{PV, PS, TR, T <: AbstractFloat}
  const velocity_physical::PV
  const vorticity_physical::PV
  const scalar_physical::PS
  # The velocity at the particles, as the trail of its last few samples: the newest is the current
  # observable, the earlier ones are what a multistep scheme integrates over and what a time
  # derivative along the trajectories is taken from.
  const velocity_at_particles_trail::TR
  velocity_epoch::Int
  vorticity_epoch::Int
  scalar_epoch::Int
  max_speed::T
  max_speed_epoch::Int
  velocity_at_particles_epoch::Int
  fields_epoch::Int
  particles_epoch::Int
end

function ObservablesCache(domain::FixedDomain; scalar::Bool = false,
                          tracers::Union{Nothing, Tracers} = nothing,
                          particle_integration_scheme = nothing)
  (tracers === nothing) == (particle_integration_scheme === nothing) ||
    throw(ArgumentError("give `tracers` and `particle_integration_scheme` together, or neither: " *
                        "the tracers size the trail of the velocity at the particles and the " *
                        "scheme fixes how many samples it keeps"))
  velocity = new_vector_field_physical(domain)
  # The speed slot takes the field's own element type, read off the velocity slot beside it: a
  # hardwired `Float64` promoted a Float32 run's timestep arithmetic and broke the element-type
  # contract the rest of the observables surface keeps. `NaN` in that type is the never-deposited
  # value, matching the epoch sentinel next to it.
  T = field_scalar_type(velocity)
  # The trail is the cache's own, like every other slot (decision 67 — the sample is an observable of
  # the flow, not particle state, so its storage lives with the observables), built by the
  # constructor a caller's own trail is built by, and marked so that only the particle deposit adds
  # to it.
  trail = tracers === nothing ? nothing :
          _new_trail(new_vector_point_values, tracers, trail_capacity(particle_integration_scheme), true)
  return ObservablesCache(velocity, new_vector_field_physical(domain),
                          scalar ? new_scalar_field_physical(domain) : nothing, trail,
                          NEVER_DEPOSITED, NEVER_DEPOSITED, NEVER_DEPOSITED,
                          T(NaN), NEVER_DEPOSITED, NEVER_DEPOSITED, 1, 1)
end


# The checked read shared by every accessor: serve the slot only when its epoch names the current
# fields epoch; otherwise throw with the schedule-facing message.
function _checked(cache::ObservablesCache, epoch::Int, what::String)
  epoch == cache.fields_epoch && return nothing
  if epoch == SCRATCH
    error("the cached $what is in use as a producer's scratch: mid-iteration the slot holds a " *
          "stage intermediate, not the observable; read it only between iterations")
  elseif epoch == NEVER_DEPOSITED
    error("the cached $what was never deposited: the schedule of this run does not fill the slot " *
          "before this read (a fresh cache is seeded by its deposit at construction)")
  else
    error("the cached $what is stale: the state has advanced past the deposited value, and " *
          "nothing in the cache is ever recomputed; read between iterations, after the closing deposit")
  end
end


"""
    velocity_physical(cache)

The velocity ``\\boldsymbol{u}`` in physical representation at the current epoch — the checked
read of the [`ObservablesCache`](@ref) `cache`'s velocity slot. Returns the deposited field when its
epoch is current, and throws otherwise (the slot is mid-iteration scratch, stale, or was never
deposited): the throw is an `ErrorException` naming the slot and which of the three states it is in,
and nothing is ever recomputed on a read. Treat the returned field as read-only — it is the
storage the next iteration works in.
"""
function velocity_physical(cache::ObservablesCache)
  _checked(cache, cache.velocity_epoch, "velocity")
  return cache.velocity_physical
end


"""
    vorticity_physical(cache)

The vorticity in physical representation
at the current epoch — the checked read of the [`ObservablesCache`](@ref) `cache`'s vorticity
slot, with exactly [`velocity_physical`](@ref)'s contract (the deposited field or a throw; never a
recomputation; read-only). The deposited value is produced by
[`vorticity_physical!`](@ref GBGHomogeneousTurbulence.Observables.vorticity_physical!) — measure with
that function, read with this one.
"""
function vorticity_physical(cache::ObservablesCache)
  _checked(cache, cache.vorticity_epoch, "vorticity")
  return cache.vorticity_physical
end


"""
    scalar_physical(cache)

The scalar ``\\varphi`` in physical representation at the current epoch — the checked read of the
[`ObservablesCache`](@ref) `cache`'s scalar slot, on [`velocity_physical`](@ref)'s terms (the
deposited field or a throw; never a recomputation; read-only) plus one of its own: it throws an
`ArgumentError` when the run carries no scalar, so there is no slot to read.
"""
function scalar_physical(cache::ObservablesCache)
  cache.scalar_physical === nothing &&
    throw(ArgumentError("this run carries no passive scalar, so the cache has no scalar slot"))
  _checked(cache, cache.scalar_epoch, "scalar")
  return cache.scalar_physical
end


# The cached-number read of the maximum speed. The generic and its docstring are homed in
# `Observables` (the field reduction); this method extends it with the checked cached read.
function max_speed(cache::ObservablesCache)
  _checked(cache, cache.max_speed_epoch, "maximum speed")
  return cache.max_speed
end


"""
    velocity_at_particles_trail(cache)

The flow velocity at the tracer positions ``\\boldsymbol{X}``,
``\\boldsymbol{u}(t, \\boldsymbol{X}(t))`` — the genuine Lagrangian velocity, the input to the
caller's statistics — as the [`ParticleTrail`](@ref GBGHomogeneousTurbulence.Particles.ParticleTrail)
of its last few samples. `trail[0].value` is the velocity at the current time ``t_n``, one vector
per tracer, and `trail[0].time` is that time; `trail[-1]` is the sample one iteration back. How
many samples the trail keeps is fixed by the run's particle integration scheme, whose docstring
states it. Treat every value as read-only — it is the cache's own storage, and the tracer advance
writes into it mid-iteration.

This is the checked read of the [`ObservablesCache`](@ref) `cache`: it serves the deposited
samples or throws an `ErrorException`, like every cached read. The samples belong to the
particles' time, so they are current exactly while the positions have not moved since the newest
was taken. Throws an `ArgumentError` when the run advects no tracers.
"""
function velocity_at_particles_trail(cache::ObservablesCache)
  trail = cache.velocity_at_particles_trail
  trail === nothing &&
    throw(ArgumentError("this run advects no tracers, so the cache has no trail of the velocity " *
                        "at the particles"))
  cache.velocity_at_particles_epoch == NEVER_DEPOSITED &&
    error("the cached velocity at the particles was never deposited: the schedule of this run " *
          "does not fill it before this read (a fresh cache is seeded by its deposit at construction)")
  # The particles counter alone: a sample is u(t, X(t)) at the time the positions were at X, so a
  # field step taken since does not date it — only a move of the positions does.
  cache.velocity_at_particles_epoch == cache.particles_epoch ||
    error("the cached velocity at the particles is stale: the tracer positions have advanced " *
          "past the newest sample, and nothing in the cache is ever recomputed; read " *
          "between iterations, after the closing deposit")
  return trail
end


# ————————————————————————————————————————————————————————————————————————————————————————————————
# The producers' side: take a slot as scratch (its epoch goes to SCRATCH), deposit into it (its
# epoch becomes the current fields epoch). Deposits happen at the end of the iteration, from the state it has
# just produced; the completeness check refuses to close an iteration with an undeposited slot.

# Take a slot's array as mid-iteration scratch. The epoch goes to SCRATCH, so a read between the
# take and the next deposit throws instead of returning a stage intermediate.
take_velocity!(cache::ObservablesCache) = (cache.velocity_epoch = SCRATCH; cache.velocity_physical)
take_vorticity!(cache::ObservablesCache) = (cache.vorticity_epoch = SCRATCH; cache.vorticity_physical)
take_scalar!(cache::ObservablesCache) = (cache.scalar_epoch = SCRATCH; cache.scalar_physical)

# Mark a slot as holding the observable at the current fields epoch. The producer writes the value
# into the slot's array first, then sets the epoch.
deposit_velocity!(cache::ObservablesCache) = (cache.velocity_epoch = cache.fields_epoch; cache.velocity_physical)
deposit_vorticity!(cache::ObservablesCache) = (cache.vorticity_epoch = cache.fields_epoch; cache.vorticity_physical)
deposit_scalar!(cache::ObservablesCache) = (cache.scalar_epoch = cache.fields_epoch; cache.scalar_physical)
deposit_max_speed!(cache::ObservablesCache{PV, PS, TR, T}, value::Real) where {PV, PS, TR, T} =
  (cache.max_speed = T(value); cache.max_speed_epoch = cache.fields_epoch; value)

# ————————————————————————————————————————————————————————————————————————————————————————————————
# The particle side. The trail is written through these functions alone, by the particle step, the
# particle deposit and the checkpoint's restore, so that no other module reaches into its state.
#
# Two counters say whether a field and a set of positions belong to one time: each rises by one
# with its own advance, and they are equal exactly when the positions have caught up with the
# fields. An iteration reads them as
#
#     start: fields n, particles n → field step: n + 1, n → particle step: n + 1, n + 1 → sample.

function _particle_trail(cache::ObservablesCache)
  cache.velocity_at_particles_trail === nothing &&
    throw(ArgumentError("this cache carries no trail of the velocity at the particles: build it " *
                        "with the run's `tracers` and `particle_integration_scheme`"))
  return cache.velocity_at_particles_trail
end

# The read the particle step makes, with the check that belongs to it: the fields have taken
# exactly one step past the positions, and the newest sample was taken at these positions. The
# velocity field the step then interpolates is read through its own checked accessor.
function trail_for_particle_step(cache::ObservablesCache, capacity::Integer)
  trail = _particle_trail(cache)
  _capacity(trail) == capacity ||
    throw(ArgumentError("this cache's trail of the velocity at the particles keeps " *
                        "$(_capacity(trail)) sample(s), but the particle integration scheme " *
                        "works from $capacity: build the cache with the scheme that advances the tracers"))
  cache.velocity_at_particles_epoch == cache.particles_epoch ||
    error("the particle step has no current velocity sample to start from: the particle deposit " *
          "that closes the previous advance was not made")
  cache.fields_epoch == cache.particles_epoch + 1 ||
    error("the particle step needs the fields exactly one step ahead of the tracer positions, " *
          "and they are $(cache.fields_epoch - cache.particles_epoch) ahead: advance the fields " *
          "once, deposit, then advance the tracers")
  return trail
end

# The particle side as it stands between iterations, which is where an iteration must start: the
# newest sample taken at the current positions, and the positions level with the fields. Returns the
# trail.
function trail_between_iterations(cache::ObservablesCache)
  trail = velocity_at_particles_trail(cache)
  cache.particles_epoch == cache.fields_epoch ||
    error("the fields have taken $(cache.fields_epoch - cache.particles_epoch) step(s) that the " *
          "tracers have not, so the two belong to different times. A run that has let them part " *
          "cannot be repaired; build a new one from its state and tracers")
  return trail
end

# The storage the particle step may use as scratch for the velocity at its predicted positions: the
# slot the closing deposit will fill, which no read can reach meanwhile.
take_velocity_at_particles!(cache::ObservablesCache) = _next_slot!(_particle_trail(cache))

# The particle deposit, around the interpolation the caller supplies as `fill_value!`: check that
# the field and the positions belong to one time, add the sample at time `t`, and stamp it.
function deposit_velocity_at_particles!(fill_value!, cache::ObservablesCache, t::Real)
  trail = _particle_trail(cache)
  _check_time(trail, t)                    # refused before anything is changed
  if cache.velocity_at_particles_epoch == NEVER_DEPOSITED
    # The first sample starts the pairing: fields stepped alone before any tracking began leave the
    # counters apart, and from here on they must move together. Asked of the stamp, not of the
    # trail's being empty: a trail of one slot is empty again whenever a sample fails to be written.
    cache.particles_epoch = cache.fields_epoch
  else
    cache.particles_epoch == cache.fields_epoch ||
      error("the velocity cannot be sampled at the particles: the fields and the tracer " *
            "positions belong to different times (the fields have taken " *
            "$(cache.fields_epoch - cache.particles_epoch) more step(s)). A run that has let " *
            "them part cannot be repaired; build a new one from its state and tracers")
    cache.velocity_at_particles_epoch == cache.particles_epoch &&
      error("the velocity at the particles is already sampled at these positions; the next " *
            "sample follows the next particle step")
  end
  _push!(fill_value!, trail, t)
  cache.velocity_at_particles_epoch = cache.particles_epoch
  return cache
end

# The checkpoint's restore: empty the trail, so that the stored earlier samples can be put back in
# time order (`restore_velocity_at_particles!`) before the ordinary deposit adds the newest.
function reset_velocity_at_particles!(cache::ObservablesCache)
  _empty!(_particle_trail(cache))
  cache.velocity_at_particles_epoch = NEVER_DEPOSITED
  return cache
end

restore_velocity_at_particles!(fill_value!, cache::ObservablesCache, t::Real) =
  (_push!(fill_value!, _particle_trail(cache), t); cache)


# The deposit-completeness check: every slot the configuration carries must sit at the
# current epoch when an iteration closes. No caller can fail this — a slot exists only because the
# schedule fills it — so a throw here names a solver bug at its source rather than letting the slot
# hold scratch for the rest of the run.
function check_deposits(cache::ObservablesCache)
  cache.velocity_epoch == cache.fields_epoch ||
    error("iteration closed with the velocity slot undeposited — a solver scheduling bug")
  cache.vorticity_epoch == cache.fields_epoch ||
    error("iteration closed with the vorticity slot undeposited — a solver scheduling bug")
  cache.scalar_physical === nothing || cache.scalar_epoch == cache.fields_epoch ||
    error("iteration closed with the scalar slot undeposited — a solver scheduling bug")
  cache.max_speed_epoch == cache.fields_epoch ||
    error("iteration closed with the maximum speed undeposited — a solver scheduling bug")
  cache.velocity_at_particles_trail === nothing ||
    (cache.velocity_at_particles_epoch == cache.particles_epoch &&
     cache.particles_epoch == cache.fields_epoch) ||
    error("iteration closed with the velocity sample undeposited — a solver scheduling bug")
  return cache
end


# The run's field advance: `step!` calls this as the step completes, so every field-derived slot reads
# as stale until the closing deposit. The trail of the velocity at the particles is untouched: its
# samples belong to the particles' time, and are what the particle step integrates over next.
advance_fields_epoch!(cache::ObservablesCache) = (cache.fields_epoch += 1; cache)


# The run's tracer advance: every `advect!` push calls this, so the trail of the velocity at the
# particles reads as stale until the closing particle deposit adds the sample at the new positions.
advance_particles_epoch!(cache::ObservablesCache) = (cache.particles_epoch += 1; cache)


# ————————————————————————————————————————————————————————————————————————————————————————————————
# Display (the convention is stated once, at `SimulationDomain`'s display section). The one line
# carries what a consumer refuses on: the velocity slot (grid, element type, storage — the library's
# spelling), the optional scalar slot and the particle trail through their own displays — the trail's
# carries the count a tracer set is matched on and the capacity a particle scheme is matched on.
# An absent slot is said aloud as `no scalar` / `no particles`, the package's one spelling
# of an absent companion. The REPL form adds each slot's standing, read off the epochs exactly as the
# checked reads decide it — and reads nothing, so it prints where a read would throw.

function Base.show(io::IO, cache::ObservablesCache)
  print(io, "ObservablesCache(", cache.velocity_physical)
  isnothing(cache.scalar_physical) ? print(io, ", no scalar") :
    print(io, ", scalar_physical ", cache.scalar_physical)
  isnothing(cache.velocity_at_particles_trail) ? print(io, ", no particles") :
    print(io, ", velocity_at_particles_trail ", cache.velocity_at_particles_trail)
  print(io, ")")
end

# The standing of a slot, in the words the checked read would refuse it with.
function _standing(epoch::Int, current::Int)
  epoch == current && return "current"
  epoch == SCRATCH && return "a producer's scratch (mid-iteration)"
  epoch == NEVER_DEPOSITED && return "never deposited"
  return "stale (deposited at fields epoch $epoch)"
end

# The trail answers to the particles counter alone: its samples belong to the particles' time.
function _particle_standing(cache::ObservablesCache)
  cache.velocity_at_particles_epoch == NEVER_DEPOSITED && return "never deposited"
  cache.velocity_at_particles_epoch == cache.particles_epoch && return "current"
  return "stale (the tracer positions have advanced past the newest sample)"
end

function Base.show(io::IO, ::MIME"text/plain", cache::ObservablesCache)
  now = cache.fields_epoch
  slot(name, value, standing) = print(io, "\n  ", rpad(name, 29), value, " — ", standing)
  absent(name, why) = print(io, "\n  ", rpad(name, 29), "nothing (", why, ")")
  print(io, "ObservablesCache (fields epoch ", now, ", particles epoch ", cache.particles_epoch, ")")
  slot("velocity_physical", cache.velocity_physical, _standing(cache.velocity_epoch, now))
  slot("vorticity_physical", cache.vorticity_physical, _standing(cache.vorticity_epoch, now))
  isnothing(cache.scalar_physical) ? absent("scalar_physical", "no scalar") :
    slot("scalar_physical", cache.scalar_physical, _standing(cache.scalar_epoch, now))
  slot("max_speed", cache.max_speed, _standing(cache.max_speed_epoch, now))
  isnothing(cache.velocity_at_particles_trail) ? absent("velocity_at_particles_trail", "no particles") :
    slot("velocity_at_particles_trail", cache.velocity_at_particles_trail, _particle_standing(cache))
end


end # module Cache
