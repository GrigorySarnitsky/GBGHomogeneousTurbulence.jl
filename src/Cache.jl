# Cache — the observables cache: the storage where a component of the iteration puts a value another
# component (or an observation) will read. The design is the no-recompute rule
# (docs/src/observables_cache.md): the schedule is fixed at construction and identical on every
# iteration; every slot is deposited at the end of the iteration from the state it has just
# produced; a read either finds a current value or throws — there is no path, internal or on
# request, by which reading causes a computation. A slot IS the register its producer computes in:
# mid-iteration the step takes the array as stage scratch (marking its epoch as scratch), and the
# closing deposit re-fills it, so caching adds nothing to what an iteration computes, moves, or stores.

"""
    Cache

The observables cache — where the iteration leaves the observables it produces, for the run's own
components and for any *observation* to read: a measurement the caller makes between iterations,
from the values the run has already computed. Each value is *deposited*, written together with its
*epoch*: the version of the state it was computed from, a number raised by one each time a step
completes or a change made outside the iteration is announced.

The cache's operations:
- [`ObservablesCache`](@ref) — the cache itself: the slots, their epochs, and the two counters.
- [`fields_modified!`](@ref), [`particles_modified!`](@ref) — announce a mutation of the state or
  of the [`Tracers`](@ref GBGHomogeneousTurbulence.Particles.Tracers) the run advects
  made outside the iteration, so the affected slots go stale and reads throw until the next deposit.
- [`velocity_physical`](@ref), [`vorticity_physical`](@ref), [`scalar_physical`](@ref) — the checked
  reads of the cached fields (the velocity, vorticity, and scalar in physical representation).
- [`max_speed`](@ref GBGHomogeneousTurbulence.Observables.max_speed) — the cached largest flow speed,
  the number the timestep choice reads (one generic with the field reduction in `Observables`, whose
  docstring is the home).
- [`velocity_at_particles`](@ref) — the checked read of the velocity sampled along each trajectory.

The field slots are filled by [`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!), which
`Propagator` owns rather than this module because it needs the scheme's scratch to recover the
fields. Each slot carries both the value and the epoch that value belongs to, so a read can be refused
rather than served stale.

The solver's side of the contract is that `deposit!` fills every field-derived slot at the
iteration's end (the velocity-at-particles slot is filled by the same generic's particle form,
after the tracers advance) and sets
its epoch. A caller reads through the accessors and deposits only to re-seed the cache after an
out-of-band mutation it announced (`fields_modified!`); the iteration's own deposits are the
solver's.

The cache keeps one epoch counter per dynamical factor — the resolved fields, the tracer positions —
and a slot is readable exactly when its own epoch equals the counter it depends on.

An epoch is not a step count: a completed
[`step!`](@ref GBGHomogeneousTurbulence.Propagator.step!) advances the fields epoch, but so does any
announced out-of-band mutation, so the two counts diverge. The epoch answers "is this value still the
right one?"; the run's step counter
[`current_step`](@ref GBGHomogeneousTurbulence.SimulationRun.current_step) answers "how far has the run
gone?".
"""
module Cache

using GBGPeriodicFields: point_values, field_data, field_scalar_type, VectorPointValues, npoints
using ..SimulationDomain: FixedDomain, new_vector_field_physical, new_scalar_field_physical
import ..Observables: max_speed           # one generic: the field reduction there, the cached read here

export ObservablesCache, velocity_physical, vorticity_physical, scalar_physical,
       velocity_at_particles, fields_modified!, particles_modified!


# Epoch sentinels. A slot's epoch is the fields epoch it was deposited at; the sentinels mark the
# two states with no value: never deposited (fresh construction, or a cleared cache) and taken as a
# producer's mid-iteration scratch.
const NEVER_DEPOSITED = -2
const SCRATCH = -1


"""
    ObservablesCache(domain; scalar = false, number_of_particles = 0, history_depth = 1)

The observables cache of a run — the storage where each iteration deposits, at its end, the
observables its own schedule produces: the velocity ``\\boldsymbol{u}`` and vorticity
``\\boldsymbol{\\omega}`` in physical representation, the scalar ``\\varphi`` in physical
representation when the run carries one, the fastest flow speed on the grid (the
[`max_speed`](@ref GBGHomogeneousTurbulence.Observables.max_speed) number the next timestep choice
reads), and — when the run advects tracers — the flow velocity at the tracer positions
``\\boldsymbol{X}`` at the current time ``t_n``, ``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))``.

The contents are automatic, derived from the configuration: the cache holds
exactly what the iteration computes, materializes, and leaves alive at its end, and nothing more.
The cache allocates and owns every slot, the velocity at the particles included — that sample is an
observable of the flow, not particle state (a tracer has no velocity of its own), so its storage
lives here and the tracer push writes into it exactly as the step writes into the field slots.

Build it on a [`FixedDomain`](@ref) `domain`. [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) builds, wires,
and seeds one for you; a hand-assembled run constructs it here.

# Arguments
- `domain` — the `FixedDomain` the run lives on; it sizes every slot.
- `scalar = false` — pass `true` when the run evolves a passive scalar, which adds the scalar's slot.
- `history_depth = 1` — how many Lagrangian samples the run must be able to look back over,
  including the current one. A hand-assembled run sets it to
  [`history_depth(scheme)`](@ref GBGHomogeneousTurbulence.Particles.history_depth) for its particle
  integration scheme. A one-step scheme needs 1 and stores no history; an `order`-step scheme needs
  `order`, and allocating the scheme's per-step buffers
  ([`allocate_buffers`](@ref GBGHomogeneousTurbulence.Propagator.allocate_buffers)) refuses a cache
  whose depth differs from it.
- `number_of_particles = 0` — the number of tracers the run advects; a positive count allocates
  the velocity-at-particles slot (an ``M \\times 3`` array of point values, ``M`` this count) and its sample history.

Read through the accessors — [`velocity_physical`](@ref), [`vorticity_physical`](@ref),
[`scalar_physical`](@ref), and `max_speed` — each of which returns the deposited value or throws.
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
- `velocity_at_particles` — the velocity sampled at the particle positions, or `nothing` for a tracer-free run.
- `velocity_at_particles_history` — the earlier Lagrangian samples, most recent first. A multistep
  particle integration scheme integrates over these; an announced reposition invalidates them
  together with the current sample.
- `history_steps` — the step sizes the earlier samples were taken over.
- `history_filled` — how many of the earlier samples are valid.
- `velocity_epoch`, `vorticity_epoch`, `scalar_epoch`, `max_speed_epoch` — the epoch each slot's
  value was deposited at, or a sentinel (never deposited / in use as scratch).
- `velocity_at_particles_fields_epoch`, `velocity_at_particles_particles_epoch` — the velocity-at-particles slot's two epochs, against
  both counters, since that sample is a function of the state and the positions together.
- `fields_epoch` — the resolved fields' counter: advanced by every completed step and by
  [`fields_modified!`](@ref), so it runs ahead of
  [`current_step`](@ref GBGHomogeneousTurbulence.SimulationRun.current_step). A
  field-derived slot is readable exactly when its epoch equals this.
- `particles_epoch` — the tracer positions' counter, advanced by every
  [`advect!`](@ref GBGHomogeneousTurbulence.Particles.advect!) push — the push announces itself —
  and by [`particles_modified!`](@ref) for a reposition made outside the push.
"""
mutable struct ObservablesCache{PV, PS, TS, T <: AbstractFloat}
  const velocity_physical::PV
  const vorticity_physical::PV
  const scalar_physical::PS
  const velocity_at_particles::TS
  # The earlier samples of the SAME observable, most recent first, with the step sizes they span.
  # They live here, with the slot they extend, so that `particles_modified!` — which owns the epoch —
  # can invalidate the whole history in one place. Held apart from the current slot rather than as a
  # ring including it, because the current slot is the tracer set's own storage, written in place.
  const velocity_at_particles_history::Vector{TS}
  const history_steps::Vector{Float64}
  history_filled::Int
  velocity_epoch::Int
  vorticity_epoch::Int
  scalar_epoch::Int
  max_speed::T
  max_speed_epoch::Int
  velocity_at_particles_fields_epoch::Int
  velocity_at_particles_particles_epoch::Int
  fields_epoch::Int
  particles_epoch::Int
end

function ObservablesCache(domain::FixedDomain; scalar::Bool = false,
                          number_of_particles::Integer = 0, history_depth::Integer = 1)
  velocity = new_vector_field_physical(domain)
  # The speed slot takes the field's own element type, read off the velocity slot beside it: a
  # hardwired `Float64` promoted a Float32 run's timestep arithmetic and broke the element-type
  # contract the rest of the observables surface keeps. `NaN` in that type is the never-deposited
  # value, matching the epoch sentinel next to it.
  T = field_scalar_type(velocity)
  # The velocity-at-particles slot is the cache's own, like every other slot (decision 67 — the
  # sample is an observable of the flow, not particle state, so its storage lives with the observables): an
  # M×3 point-value section on the domain's backend, plus `history_depth - 1` past samples for a
  # multistep scheme. A one-step scheme asks for 1 and gets no history.
  velocity_at_particles = number_of_particles > 0 ?
    VectorPointValues(domain.array_family{T}(undef, Int(number_of_particles), 3)) : nothing
  past = velocity_at_particles === nothing ? typeof(velocity_at_particles)[] :
         [deepcopy(velocity_at_particles) for _ in 1:max(history_depth - 1, 0)]
  return ObservablesCache(velocity, new_vector_field_physical(domain),
                          scalar ? new_scalar_field_physical(domain) : nothing,
                          velocity_at_particles, past, zeros(Float64, length(past)), 0,
                          NEVER_DEPOSITED, NEVER_DEPOSITED, NEVER_DEPOSITED,
                          T(NaN), NEVER_DEPOSITED, NEVER_DEPOSITED, NEVER_DEPOSITED, 1, 1)
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
    velocity_at_particles(cache)

The flow velocity at the tracer positions ``\\boldsymbol{X}`` at the current time ``t_n``,
``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))``, at the current epoch — the ``(M, 3)`` array (``M`` the tracer count) of the velocity sampled at each tracer's position at
that instant: the genuine Lagrangian velocity, the input to the caller's statistics. Treat the returned array as
read-only — it is the cache's own slot, and the tracer advance writes into it mid-iteration. This is
the checked read of the [`ObservablesCache`](@ref) `cache`'s velocity-at-particles slot: it serves the
deposited values or throws an `ErrorException`, like every cached read — the sample depends on the
state and the positions, so it is current only when both counters match its own. Throws an
`ArgumentError` when the run advects no tracers.
"""
function velocity_at_particles(cache::ObservablesCache)
  cache.velocity_at_particles === nothing &&
    throw(ArgumentError("this run advects no tracers, so the cache has no velocity-at-particles slot"))
  # BOTH epochs, because the sample is a function of the state AND the positions — which is the whole
  # reason the cache keeps two counters for this one slot. Testing only the fields epoch left the
  # announced reposition, the very mutation the pair exists to catch, invisible to the read:
  # `particles_modified!` advances the particles epoch and touches nothing else, so a sample measured
  # along an abandoned trajectory was served as current, and `advance!`'s opening guard could never
  # fire. `check_deposits` had the test right; this read did not.
  (cache.velocity_at_particles_fields_epoch == cache.fields_epoch &&
   cache.velocity_at_particles_particles_epoch == cache.particles_epoch) ||
    error("the cached velocity at the particles is stale: the state or the tracer positions have advanced " *
          "past the deposited values, and nothing in the cache is ever recomputed; read " *
          "between iterations, after the closing deposit")
  return point_values(cache.velocity_at_particles)
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
deposit_max_speed!(cache::ObservablesCache{PV, PS, TS, T}, value::Real) where {PV, PS, TS, T} =
  (cache.max_speed = T(value); cache.max_speed_epoch = cache.fields_epoch; value)
# The stamping half of the particle deposit, beside its field-slot siblings above: mark the
# velocity-at-particles slot current against BOTH counters — the fields epoch of the interpolated
# velocity and the particles epoch of the positions — since the sample is a function of the two
# together. `deposit!`'s particle method (in `Particles`, the module that owns the interpolation)
# writes the values and then calls this.
deposit_velocity_at_particles!(cache::ObservablesCache) =
  (cache.velocity_at_particles_fields_epoch = cache.fields_epoch;
   cache.velocity_at_particles_particles_epoch = cache.particles_epoch; cache.velocity_at_particles)


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
  cache.velocity_at_particles === nothing ||
    (cache.velocity_at_particles_fields_epoch == cache.fields_epoch &&
     cache.velocity_at_particles_particles_epoch == cache.particles_epoch) ||
    error("iteration closed with the velocity sample undeposited — a solver scheduling bug")
  return cache
end


"""
    fields_modified!(cache)
    fields_modified!(sim)

Announce that the resolved fields — ``\\hat{\\boldsymbol{u}}`` and ``\\hat\\varphi``, in spectral
representation —
were changed outside the iteration (a re-seeded velocity, any direct write to the state's storage).
Advances the fields epoch of `cache` (an [`ObservablesCache`](@ref)), so every cached observable is stale and reads throw until
the next deposit; that interval belongs to whoever made the change.

This verb is only for out-of-band changes — [`step!`](@ref GBGHomogeneousTurbulence.Propagator.step!)
advances the epoch itself, and the closing deposit restores the cache. After a hand-made mutation,
re-deposit with the
`Propagator`'s [`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!) before advancing again —
the timestep choice reads the cached maximum speed.

Coefficients written by hand must respect the real-field layout's conjugate symmetry — a violation
makes spectral diagnostics silently disagree with the physical images. The `sim` form checks
this: it measures the conjugate-symmetry residual on the planes that store both members of a pair
and throws on an inconsistency beyond roundoff. The `cache` form cannot see the fields and trusts
the caller; the package's own seeders satisfy the constraint by construction.

Given a [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) it announces the change
to that run's cache — the form to reach for when a run is what you are holding
(`particles_modified!` offers the same pair of forms).

Returns its argument.

!!! warning "It also discards the Lagrangian sample history"
    Those samples are the velocity measured along the trajectory *through the state being
    replaced*, so a multistep particle integration scheme integrating over them would blend the old field
    into the new one. The run's own field advance is not such a change and keeps its history.
"""
fields_modified!(cache::ObservablesCache) =
  (advance_fields_epoch!(cache); cache.history_filled = 0; cache)


# The run's OWN field advance, which is not an out-of-band replacement and must not clear the sample
# history: the samples it took are exactly what a multistep particle integration scheme integrates over next.
# `step!` calls this at every stage, so clearing there would pin the scheme in its bootstrap forever
# — the same trap the particles counterpart carries, and for the same reason: one verb was serving
# both "the run advanced" and "someone replaced the state behind the run's back".
advance_fields_epoch!(cache::ObservablesCache) = (cache.fields_epoch += 1; cache)


# Invalidating the sample history is the whole reason it lives in this cache: the samples in it were
# taken along the trajectory that has just been abandoned, and a multistep scheme integrating over
# them would blend the old path into the new one.
"""
    particles_modified!(cache)
    particles_modified!(sim)

Announce that the tracer positions were changed outside the iteration (a reseed, a hand-written
correction, any direct write to the tracer storage) — the particle counterpart of
[`fields_modified!`](@ref). Advances the particles epoch of `cache` (an [`ObservablesCache`](@ref)), so every
trajectory-bound observable is stale and reads throw until the next deposit.

It also discards the Lagrangian sample history this cache carries, so a multistep particle
integration scheme starts over from the new positions rather than integrating across the abandoned path. That is
why the history lives here and not in the scheme's own per-step buffers: the object that owns the epoch owns
the invalidation. The run's own tracer advance is not such a change and keeps its history.

The run's own tracer advance never needs this verb:
[`advect!`](@ref GBGHomogeneousTurbulence.Particles.advect!) moves the particles epoch itself and
keeps the history — the advance *extends* the history this verb discards.

A hand-run loop that repositions tracers itself calls this and then makes the particle deposit —
`deposit!(cache, tracers, u)` — from the
deposited velocity, so the slot is refilled at the new positions. A loop
announcing to a bare cache rather than a [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) must also call
[`restart!`](@ref GBGHomogeneousTurbulence.Particles.restart!) itself, for a scheme carrying per-step
buffers of its own
([`ParticleIntegratorBuffers`](@ref GBGHomogeneousTurbulence.Particles.ParticleIntegratorBuffers)):
the `Simulation` form calls that for you; the bare-cache form cannot dispatch to it.

Given a `Simulation` it announces the change
to that run's cache — the form to reach for when a run is what you are holding, mirroring
[`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!)'s own `sim` form.

Returns its argument.
"""
particles_modified!(cache::ObservablesCache) =
  (advance_particles_epoch!(cache); cache.history_filled = 0; cache)


# The run's OWN tracer advance, which is not an out-of-band change and must not clear the sample
# history: the samples it just took are exactly what a multistep scheme integrates over next. The two
# were one verb until the history moved into this cache, at which point the difference stopped being
# cosmetic — the routine path was clearing the history on every step and the multistep scheme could
# never leave its bootstrap.
advance_particles_epoch!(cache::ObservablesCache) = (cache.particles_epoch += 1; cache)


# ————————————————————————————————————————————————————————————————————————————————————————————————
# Display (the convention is stated once, at `SimulationDomain`'s display section). The one line
# carries what a consumer refuses on: the velocity slot (grid, element type, storage — the library's
# spelling), the optional scalar and particle slots through their own displays — the particle one
# carries the count a tracer set is matched on — and the history depth a multistep particle scheme
# demands. An absent slot is said aloud as `no scalar` / `no particles`, the package's one spelling
# of an absent companion. The REPL form adds each slot's standing, read off the epochs exactly as the
# checked reads decide it — and reads nothing, so it prints where a read would throw.

function Base.show(io::IO, cache::ObservablesCache)
  print(io, "ObservablesCache(", cache.velocity_physical)
  isnothing(cache.scalar_physical) ? print(io, ", no scalar") :
    print(io, ", scalar_physical ", cache.scalar_physical)
  if isnothing(cache.velocity_at_particles)
    print(io, ", no particles")
  else
    print(io, ", velocity_at_particles ", cache.velocity_at_particles, ", history depth ",
          length(cache.velocity_at_particles_history) + 1)
  end
  print(io, ")")
end

# The standing of a slot, in the words the checked read would refuse it with.
function _standing(epoch::Int, current::Int)
  epoch == current && return "current"
  epoch == SCRATCH && return "a producer's scratch (mid-iteration)"
  epoch == NEVER_DEPOSITED && return "never deposited"
  return "stale (deposited at fields epoch $epoch)"
end

# The particle slot answers to two counters — the sample is a function of the state AND the
# positions — so its standing names whichever has moved on, or both. The sentinels are tested first:
# a never-deposited slot is not "advanced past", whatever the counters say.
function _particle_standing(cache::ObservablesCache)
  fields_epoch, particles_epoch = cache.velocity_at_particles_fields_epoch, cache.velocity_at_particles_particles_epoch
  fields_epoch == SCRATCH && return "a producer's scratch (mid-iteration)"
  fields_epoch == NEVER_DEPOSITED && return "never deposited"
  fields_current, particles_current = fields_epoch == cache.fields_epoch, particles_epoch == cache.particles_epoch
  fields_current && particles_current && return "current"
  fields_current && return "stale (the tracer positions have advanced past the deposited sample)"
  particles_current && return "stale (deposited at fields epoch $fields_epoch)"
  return "stale (deposited at fields epoch $fields_epoch, and the tracer positions have advanced since)"
end

function Base.show(io::IO, ::MIME"text/plain", cache::ObservablesCache)
  now = cache.fields_epoch
  slot(name, value, standing) = print(io, "\n  ", rpad(name, 23), value, " — ", standing)
  absent(name, why) = print(io, "\n  ", rpad(name, 23), "nothing (", why, ")")
  print(io, "ObservablesCache (fields epoch ", now, ", particles epoch ", cache.particles_epoch, ")")
  slot("velocity_physical", cache.velocity_physical, _standing(cache.velocity_epoch, now))
  slot("vorticity_physical", cache.vorticity_physical, _standing(cache.vorticity_epoch, now))
  isnothing(cache.scalar_physical) ? absent("scalar_physical", "no scalar") :
    slot("scalar_physical", cache.scalar_physical, _standing(cache.scalar_epoch, now))
  slot("max_speed", cache.max_speed, _standing(cache.max_speed_epoch, now))
  if isnothing(cache.velocity_at_particles)
    absent("velocity_at_particles", "no particles")
  else
    slot("velocity_at_particles", cache.velocity_at_particles, _particle_standing(cache))
    depth = length(cache.velocity_at_particles_history) + 1
    slot("history", "depth $depth", "$(cache.history_filled) of $(depth - 1) past samples filled")
  end
end


end # module Cache
