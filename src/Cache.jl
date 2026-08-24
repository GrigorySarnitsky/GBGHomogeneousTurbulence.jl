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
components and for any **observation** to read: a measurement the caller makes between iterations,
from the values the run has already computed.

The cache's operations:
- [`ObservablesCache`](@ref) — the cache itself: the slots, their epochs, and the two counters.
- [`fields_modified!`](@ref), [`particles_modified!`](@ref) — announce a state or tracer mutation
  made outside the iteration, so the affected slots go stale and reads throw until the next deposit.
- [`deposit_sample!`](@ref) — records the particle velocities
  [`record_particle_velocities!`](@ref GBGIsotropicTurbulence.Particles.record_particle_velocities!) wrote.
- [`velocity_physical`](@ref), [`vorticity_physical`](@ref), [`scalar_physical`](@ref) — the checked
  reads of the cached fields (the velocity, vorticity, and scalar in physical representation).
- [`max_speed`](@ref GBGIsotropicTurbulence.Observables.max_speed) — the cached largest flow speed,
  the number the timestep choice reads (one generic with the field reduction in `Observables`, whose
  docstring is the home).
- [`particle_velocities`](@ref) — the checked read of the velocity sampled along each trajectory.

The field slots are filled by [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!), which
`Propagator` owns rather than this module because it needs the scheme's scratch to recover the
fields. Each slot carries the value **and** the epoch that value belongs to, so a read can be refused
rather than served stale.

The solver's side of the contract is that `deposit!` fills every field-derived slot at the
iteration's end (the particle-velocities slot has its own pair of verbs, recorded below) and sets
its epoch. A caller reads through the accessors and never deposits.

The cache keeps one epoch counter per dynamical factor — the resolved fields, the tracer positions —
and a slot is readable exactly when its own epoch equals the counter it depends on.

An epoch counts *changes to the state*, not advances of the run: a completed
[`step!`](@ref GBGIsotropicTurbulence.Propagator.step!) advances the fields epoch, but so does any
announced out-of-band mutation, so the two counts diverge. The epoch answers "is this value still the
right one?"; the clock's
[`current_step`](@ref GBGIsotropicTurbulence.SimulationRun.current_step) answers "how far has the run
gone?".
"""
module Cache

using GBGPeriodicFields: point_values, field_data
using ..SimulationDomain: FixedDomain, new_vector_field_physical, new_scalar_field_physical
import ..Observables: max_speed           # one generic: the field reduction there, the cached read here

export ObservablesCache, velocity_physical, vorticity_physical, scalar_physical,
       particle_velocities, fields_modified!, particles_modified!, deposit_sample!


# Epoch sentinels. A slot's epoch is the fields epoch it was deposited at; the sentinels mark the
# two states with no value: never deposited (fresh construction, or a cleared cache) and taken as a
# producer's mid-iteration scratch.
const NEVER_DEPOSITED = -2
const SCRATCH = -1


"""
    ObservablesCache(domain; scalar = false, particle_velocities = nothing, history_depth = 1)

The observables cache of a run — the storage where each iteration deposits, at its end, the
observables its own schedule produces: the velocity ``\\boldsymbol{u}`` and vorticity
``\\boldsymbol{\\omega}`` in physical representation, the scalar ``\\varphi`` in physical
representation when the run carries one, the fastest flow speed on the grid (the
[`max_speed`](@ref GBGIsotropicTurbulence.Observables.max_speed) number the next timestep choice
reads), and — when the run advects tracers — the particle velocities
``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))``.

The contents are automatic, derived from the configuration: the cache holds
exactly what the iteration computes, materializes, and leaves alive at its end, and nothing more.
The cache allocates and owns every slot but one: the particle velocities are the tracer set's own
storage, which the cache borrows and records epochs for rather than filling itself.

Build it on a [`FixedDomain`](@ref) `domain`. [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) builds, wires,
and seeds one for you; a hand-assembled run constructs it here.

# Arguments
- `domain` — the `FixedDomain` the run lives on; it sizes every slot.
- `scalar = false` — pass `true` when the run evolves a passive scalar, which adds the scalar's slot.
- `history_depth = 1` — how many Lagrangian samples the run must be able to look back over,
  including the current one: the value of
  [`history_depth`](@ref GBGIsotropicTurbulence.Particles.history_depth)`(trajectory_scheme)` for
  the run's trajectory scheme, which is where a hand-assembled run gets the number. A one-step
  scheme needs 1 and stores no history; an `order`-step scheme needs `order`, and the scheme's
  register allocation refuses a cache built too shallow.
- `particle_velocities = nothing` — the tracer set's own point-value storage, passed when the run
  advects tracers. Pass `tracers.particle_velocities`: the slot **is** that array, so the tracer
  advance writes the values and the cache only records which epochs they belong to.

Read through the accessors — [`velocity_physical`](@ref), [`vorticity_physical`](@ref),
[`scalar_physical`](@ref), and `max_speed` — each of which returns the deposited value or throws.
Nothing in the cache is ever recomputed: a read that finds a slot stale, **taken** (in use as the
step's own scratch mid-iteration), or never deposited throws an `ErrorException` naming the slot
and its state — a scheduling error whose only repair is to fix the schedule that failed to
deposit.

!!! note "A cached array is the next iteration's scratch"
    A slot is also the array its producer computes in: between deposits the step writes its own
    stage values there, so a cached field is meaningful only between iterations. Treat every
    returned array as read-only — it is the storage the next iteration will work in.

# Fields
The word *epoch* names two things here, and these fields are of both kinds. The two **counters** tick
as the state changes; every other `*_epoch` field records the counter's value at the moment its slot
was filled. A slot is readable exactly while the epoch it records still equals the counter it
depends on.

- `velocity_physical`, `vorticity_physical` — the cached velocity and vorticity in physical
  representation. Mid-iteration the step also computes its stage recoveries *into these same
  arrays*, which is why they are not readable then.
- `scalar_physical` — the cached scalar in physical representation, or `nothing` for a scalar-free run.
- `max_speed` — the cached fastest flow speed (a host number in the field's own element type).
- `particle_velocities` — the particle-velocities slot, or `nothing` for a tracer-free run.
- `particle_velocity_history` — the earlier Lagrangian samples, most recent first, and
  `sample_steps` the step sizes they were taken over; `history_filled` says how many are valid. A
  multistep trajectory scheme integrates over these; an announced reposition invalidates them
  together with the current sample.
- `velocity_epoch`, `vorticity_epoch`, `scalar_epoch`, `max_speed_epoch` — the epoch each slot's
  value was deposited at, or a sentinel (never deposited / in use as scratch).
- `sample_fields_epoch`, `sample_particles_epoch` — the particle velocities' two epochs, against
  **both** counters, since that sample is a function of the state and the positions together.
- `fields_epoch` — the resolved fields' counter: advanced by every completed step and by
  [`fields_modified!`](@ref), so it runs ahead of
  [`current_step`](@ref GBGIsotropicTurbulence.SimulationRun.current_step). A
  field-derived slot is readable exactly when its epoch equals this.
- `particles_epoch` — the tracer positions' counter. The run layer advances it as part of the tracer
  advance; a hand-run loop that moves tracers itself announces the change with
  [`particles_modified!`](@ref), which is what advances it.
"""
mutable struct ObservablesCache{PV, PS, TS, T <: AbstractFloat}
  const velocity_physical::PV
  const vorticity_physical::PV
  const scalar_physical::PS
  const particle_velocities::TS
  # The earlier samples of the SAME observable, most recent first, with the step sizes they span.
  # They live here, with the slot they extend, so that `particles_modified!` — which owns the epoch —
  # can invalidate the whole history in one place. Held apart from the current slot rather than as a
  # ring including it, because the current slot is the tracer set's own storage, written in place.
  const particle_velocity_history::Vector{TS}
  const sample_steps::Vector{Float64}
  history_filled::Int
  velocity_epoch::Int
  vorticity_epoch::Int
  scalar_epoch::Int
  max_speed::T
  max_speed_epoch::Int
  sample_fields_epoch::Int
  sample_particles_epoch::Int
  fields_epoch::Int
  particles_epoch::Int
end

function ObservablesCache(domain::FixedDomain; scalar::Bool = false, particle_velocities = nothing,
                          history_depth::Integer = 1)
  velocity = new_vector_field_physical(domain)
  # The speed slot takes the field's own element type, read off the velocity slot beside it: a
  # hardwired `Float64` promoted a Float32 run's timestep arithmetic and broke the element-type
  # contract the rest of the observables surface keeps. `NaN` in that type is the never-deposited
  # value, matching the epoch sentinel next to it.
  T = real(eltype(field_data(velocity)))
  # `history_depth` past samples beyond the current one. A one-step scheme asks for 1 and gets none.
  past = particle_velocities === nothing ? typeof(particle_velocities)[] :
         [deepcopy(particle_velocities) for _ in 1:max(history_depth - 1, 0)]
  return ObservablesCache(velocity, new_vector_field_physical(domain),
                          scalar ? new_scalar_field_physical(domain) : nothing,
                          particle_velocities, past, zeros(Float64, length(past)), 0,
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
[`vorticity_physical!`](@ref GBGIsotropicTurbulence.Observables.vorticity_physical!) — measure with
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
    particle_velocities(cache)

The particle velocities ``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))`` at the current epoch — the
``(M, 3)`` array of the flow velocity sampled at the position each tracer occupies at that instant:
the genuine Lagrangian velocity the statistics accumulate. Treat the returned array as read-only —
it is the tracer set's own storage, and the tracer advance writes into it mid-iteration. The checked read of the
[`ObservablesCache`](@ref) `cache`'s particle-velocities slot: it serves the deposited values or
throws an `ErrorException`, like every cached read — the sample depends on the state **and** the
positions, so it is
current only when both counters match its own. Throws an `ArgumentError` when the run advects no
tracers.

"""
function particle_velocities(cache::ObservablesCache)
  cache.particle_velocities === nothing &&
    throw(ArgumentError("this run advects no tracers, so the cache has no particle-velocities slot"))
  # BOTH epochs, because the sample is a function of the state AND the positions — which is the whole
  # reason the cache keeps two counters for this one slot. Testing only the fields epoch left the
  # announced reposition, the very mutation the pair exists to catch, invisible to the read:
  # `particles_modified!` advances the particles epoch and touches nothing else, so a sample measured
  # along an abandoned trajectory was served as current, and `advance!`'s opening guard could never
  # fire. `check_deposits` had the test right; this read did not.
  (cache.sample_fields_epoch == cache.fields_epoch &&
   cache.sample_particles_epoch == cache.particles_epoch) ||
    error("the cached particle velocities are stale: the state or the tracer positions have advanced " *
          "past the deposited values, and nothing in the cache is ever recomputed; read " *
          "between iterations, after the closing deposit")
  return point_values(cache.particle_velocities)
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
"""
    deposit_sample!(cache)

Record the particle velocities already written into `cache` (an [`ObservablesCache`](@ref)) as
current, so [`particle_velocities`](@ref) will serve them instead of throwing.

Use it after writing new values at the particle positions —
[`record_particle_velocities!`](@ref GBGIsotropicTurbulence.Particles.record_particle_velocities!)
writes, this call records. The two are separate because the slot is the tracer set's own storage: the
cache never fills it, and cannot know when its contents became current. A run does both for you at
the end of each iteration; a hand-run loop that advances tracers itself must call both, in that
order, since the write alone leaves the slot stale.

This slot is the one checked against **two** epochs — the fields epoch of the velocity that was
interpolated, and the particles epoch of the positions it was interpolated at — so this call sets
both from the cache's current counters.

Returns the particle-velocities slot.
"""
deposit_sample!(cache::ObservablesCache) =
  (cache.sample_fields_epoch = cache.fields_epoch;
   cache.sample_particles_epoch = cache.particles_epoch; cache.particle_velocities)


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
  cache.particle_velocities === nothing ||
    (cache.sample_fields_epoch == cache.fields_epoch &&
     cache.sample_particles_epoch == cache.particles_epoch) ||
    error("iteration closed with the particle velocities undeposited — a solver scheduling bug")
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

This verb is only for out-of-band changes — [`step!`](@ref GBGIsotropicTurbulence.Propagator.step!)
advances the epoch itself, and the closing deposit restores the cache. After a hand-made mutation,
re-deposit with the
run layer's [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!) before advancing again —
the timestep choice reads the cached maximum speed.

Coefficients written by hand must respect the real-field layout's conjugate symmetry — a violation
makes spectral diagnostics silently disagree with the physical images. The `sim` form **checks**
this: it measures the conjugate-symmetry residual on the planes that store both members of a pair
and throws on an inconsistency beyond roundoff. The `cache` form cannot see the fields and trusts
the caller; the package's own seeders satisfy the constraint by construction.

Given a [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) it announces the change
to that run's cache — the form mirroring `particles_modified!`'s two.

Returns its argument.

!!! warning "It also discards the Lagrangian sample history"
    Those samples are the velocity measured along the trajectory *through the state being
    replaced*, so a multistep trajectory scheme integrating over them would blend the old field
    into the new one. The run's own field advance is not such a change and keeps its history.
"""
fields_modified!(cache::ObservablesCache) =
  (advance_fields_epoch!(cache); cache.history_filled = 0; cache)


# The run's OWN field advance, which is not an out-of-band replacement and must not clear the sample
# history: the samples it took are exactly what a multistep trajectory scheme integrates over next.
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

It also discards the Lagrangian **sample history** this cache carries, so a multistep trajectory
scheme starts over from the new positions rather than integrating across the abandoned path. That is
why the history lives here and not in the scheme's own registers: the object that owns the epoch owns
the invalidation. The run's own tracer advance is not such a change and keeps its history.

The run layer never calls this verb: its own tracer advance inside
[`advance!`](@ref GBGIsotropicTurbulence.SimulationRun.advance!) moves the particles epoch through a
separate, history-keeping announcement — the advance *extends* the history this verb discards.

A hand-run loop that repositions tracers itself calls this, then
[`record_particle_velocities!`](@ref GBGIsotropicTurbulence.Particles.record_particle_velocities!),
then `deposit_sample!` (the write alone leaves the slot stale, and a read of it throws). A loop
announcing to a bare cache rather than a `Simulation` must also call
[`restart!`](@ref GBGIsotropicTurbulence.Particles.restart!) itself, for a scheme carrying its own
registers: the `Simulation` form calls that for you; the bare-cache form cannot dispatch to it.

Given a [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) it announces the change
to that run's cache — the form to reach for when a run is what you are holding, mirroring
[`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!)'s two forms.

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


end # module Cache
