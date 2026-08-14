# Cache — the observables cache: the stamped storage where a component of the iteration
# puts a value another component (or an observation) will read. The design is the no-recompute rule
# (docs/src/observables_cache.md): the schedule is fixed at construction and identical on every
# iteration; every slot is deposited at the tail of the iteration from the state it has just
# produced; a read either finds the stamped value or throws — there is no path, internal or on
# request, by which reading causes a computation. A slot IS the register its producer computes in:
# mid-iteration the step takes the array as stage scratch (clearing the stamp), and the tail deposit
# re-fills it, so caching adds nothing to what an iteration computes, moves, or stores.

"""
    Cache

The observables cache — the stamped storage where the iteration leaves the observables it produces,
for the run's own components and any observation to read. An **iteration** is one advance of the
run — one `step!` and the `deposit!` that closes it; a **boundary** is the instant between
iterations — the state at one ``t_n``, after one advance and before the next (an instant of the
run's clock, not a face of the periodic box); a slot's **stamp** records which boundary its value
belongs to, so a read can be refused rather than served stale. The cache's operations:
- [`ObservablesCache`](@ref) — the cache itself: the slots, their stamps, and the epoch counters.
- [`velocity_physical`](@ref), [`vorticity_physical`](@ref), [`scalar_physical`](@ref) — the checked
  reads of the cached fields (the velocity, vorticity, and scalar in physical representation).
- `max_speed` — the cached maximum velocity component, the number the timestep choice reads (one
  generic with the field reduction in `Observables`, whose docstring is the home).
- [`particle_velocities`](@ref) — the checked read of the particle velocities
  ``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))``, the velocity sampled along each trajectory.
- [`resolved_fields_modified!`](@ref) — announce a state mutation made outside the iteration, so
  every stamp is cleared and reads throw until the next deposit.

The solver's side of the contract is [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!)
— homed in `Propagator`, with the iteration it closes — which fills and stamps every slot at the
iteration's tail; internal per-slot deposit and take verbs move the individual stamps. A caller
reads through the accessors and never deposits.
"""
module Cache

using GBGPeriodicFields: point_values
using ..SimulationDomain: FixedDomain, new_vector_field_physical, new_scalar_field_physical
import ..Observables: max_speed           # one generic: the field reduction there, the cached read here

export ObservablesCache, velocity_physical, vorticity_physical, scalar_physical,
       particle_velocities, resolved_fields_modified!


# Stamp sentinels. A slot's stamp is the fields epoch it was deposited at; the sentinels mark the
# two states with no value: never deposited (fresh construction, or a cleared cache) and taken as a
# producer's mid-iteration scratch.
const NEVER_DEPOSITED = -2
const SCRATCH = -1


"""
    ObservablesCache(domain; scalar = false, particle_velocities = nothing)

The observables cache of a run — the stamped storage where each iteration deposits, at its end, the
observables its own schedule produces: the velocity ``\\boldsymbol{u}`` and vorticity
``\\boldsymbol{\\omega}`` in physical representation, the scalar ``\\varphi`` in physical
representation when the run carries one, the maximum velocity component (the `max_speed` number
the next timestep choice reads), and — when the run advects tracers — the particle velocities
``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))``. The contents are automatic — derived from the
configuration, never declared: the cache holds exactly what the iteration computes, materializes,
and leaves alive at the boundary, and nothing may be added on any cost axis.

Build it on a [`FixedDomain`](@ref) `domain`; pass `scalar = true` when the run evolves a passive
scalar (it adds the scalar's slot), and `particle_velocities` — the tracer set's own point-value
storage — when the run advects tracers (the slot IS that storage, stamped here; the tracers' push
writes it). The `Simulation` front door builds, wires, and seeds one for you.

Read through the accessors — [`velocity_physical`](@ref), [`vorticity_physical`](@ref),
[`scalar_physical`](@ref), and `max_speed` — each of which returns the deposited value or throws.
Nothing in the cache is ever recomputed: a read that finds a stale, taken, or never-deposited slot
reports a scheduling error — it throws an `ErrorException` whose message names the slot and which
of the three states it is in — and the only repair is to fix the schedule that failed to deposit.

!!! note
    A slot is also its producer's register: between deposits the step works in the same array, so a
    cached field is only valid at the boundaries between iterations. Treat every returned array as
    read-only — it is the storage the next iteration will work in.

# Fields
- `velocity`, `vorticity` — the cached velocity and vorticity in physical representation (the arrays
  double as the step's stage recovery registers).
- `scalar` — the cached scalar in physical representation, or `nothing` for a scalar-free run.
- `velocity_stamp`, `vorticity_stamp`, `scalar_stamp`, `max_speed_stamp` — each slot's stamp: the
  fields epoch it was deposited at, or a sentinel (never deposited / in use as scratch).
- `max_speed` — the cached maximum velocity component (a host number).
- `particle_velocities` — the particle-velocities slot (the tracer set's `(M, 3)` point values), or
  `nothing` for a tracer-free run; `sample_fields_stamp` / `sample_particles_stamp` are its stamps
  against BOTH epochs, since the sample is a function of the state and the positions together.
- `fields_epoch` — the state's epoch: advanced by every completed step and by
  [`resolved_fields_modified!`](@ref); a stamp is current exactly when it equals this.
- `particles_epoch` — the tracer positions' epoch (advanced by the tracer push), the second
  freshness axis of the trajectory-bound slots.
"""
mutable struct ObservablesCache{PV, PS, TS}
  const velocity::PV
  const vorticity::PV
  const scalar::PS
  const particle_velocities::TS
  velocity_stamp::Int
  vorticity_stamp::Int
  scalar_stamp::Int
  max_speed::Float64
  max_speed_stamp::Int
  sample_fields_stamp::Int
  sample_particles_stamp::Int
  fields_epoch::Int
  particles_epoch::Int
end

ObservablesCache(domain::FixedDomain; scalar::Bool = false, particle_velocities = nothing) =
  ObservablesCache(new_vector_field_physical(domain), new_vector_field_physical(domain),
                   scalar ? new_scalar_field_physical(domain) : nothing,
                   particle_velocities,
                   NEVER_DEPOSITED, NEVER_DEPOSITED, NEVER_DEPOSITED,
                   NaN, NEVER_DEPOSITED, NEVER_DEPOSITED, NEVER_DEPOSITED, 1, 1)


# The checked read shared by every accessor: serve the slot only when its stamp names the current
# fields epoch; otherwise throw with the schedule-facing message.
function _checked(cache::ObservablesCache, stamp::Int, what::String)
  stamp == cache.fields_epoch && return nothing
  if stamp == SCRATCH
    error("the cached $what is in use as a producer's scratch: mid-iteration the slot holds a " *
          "stage intermediate, not the observable; read it only at the boundaries between iterations")
  elseif stamp == NEVER_DEPOSITED
    error("the cached $what was never deposited: the schedule of this run does not fill the slot " *
          "before this read (a fresh cache is seeded by its deposit at construction)")
  else
    error("the cached $what is stale: the state has advanced past the deposited value, and " *
          "nothing in the cache is ever recomputed; read at a boundary, after the tail deposit")
  end
end


"""
    velocity_physical(cache)
    velocity_physical(sim)

The velocity ``\\boldsymbol{u}`` in physical representation at the current boundary — the checked
read of the [`ObservablesCache`](@ref) `cache`'s velocity slot. Returns the deposited field when its
stamp is current, and throws otherwise (the slot is mid-iteration scratch, stale, or was never
deposited); nothing is ever recomputed on a read. Treat the returned field as read-only — it is the
storage the next iteration works in. The second form reads a `Simulation`'s cache.
"""
function velocity_physical(cache::ObservablesCache)
  _checked(cache, cache.velocity_stamp, "velocity")
  return cache.velocity
end


"""
    vorticity_physical(cache)
    vorticity_physical(sim)

The vorticity ``\\boldsymbol{\\omega} = \\nabla\\times\\boldsymbol{u}`` in physical representation
at the current boundary — the checked read of the [`ObservablesCache`](@ref) `cache`'s vorticity
slot, with exactly [`velocity_physical`](@ref)'s contract (the deposited field or a throw; never a
recomputation; read-only). The deposited value is produced by
[`vorticity_physical!`](@ref GBGIsotropicTurbulence.Observables.vorticity_physical!) — measure with
that function, read with this one. The second form reads a `Simulation`'s cache.
"""
function vorticity_physical(cache::ObservablesCache)
  _checked(cache, cache.vorticity_stamp, "vorticity")
  return cache.vorticity
end


"""
    scalar_physical(cache)
    scalar_physical(sim)

The scalar ``\\varphi`` in physical representation at the current boundary — the checked read of the
[`ObservablesCache`](@ref) `cache`'s scalar slot, with exactly [`velocity_physical`](@ref)'s
contract (the deposited field or a throw; never a recomputation; read-only). Throws an
`ArgumentError` when the run carries no scalar. The second form reads a `Simulation`'s cache.
"""
function scalar_physical(cache::ObservablesCache)
  cache.scalar === nothing &&
    throw(ArgumentError("this run carries no passive scalar, so the cache has no scalar slot"))
  _checked(cache, cache.scalar_stamp, "scalar")
  return cache.scalar
end


# The cached-number read of the maximum speed. The generic and its docstring are homed in
# `Observables` (the field reduction); this method extends it with the checked cached read.
function max_speed(cache::ObservablesCache)
  _checked(cache, cache.max_speed_stamp, "maximum velocity component")
  return cache.max_speed
end


"""
    particle_velocities(cache)
    particle_velocities(sim)

The particle velocities ``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))`` at the current boundary — the
``(M, 3)`` array of the flow velocity sampled at the position each tracer occupies at that boundary:
the genuine Lagrangian velocity the statistics accumulate. The checked read of the
[`ObservablesCache`](@ref) `cache`'s particle-velocities slot: it serves the deposited values or
throws, like every cached read — the sample depends on the state **and** the positions, so it is
current only when both epochs match its stamps. Throws an `ArgumentError` when the run advects no
tracers. The second form reads a `Simulation`'s cache.

!!! note
    This is never the second velocity of the tracer position update (the corrector stage of its
    Heun-in-time push): that one is evaluated at a *predicted* position no tracer ever occupies — a
    stage register of the scheme, not a sample of the flow — and it is not readable.
"""
function particle_velocities(cache::ObservablesCache)
  cache.particle_velocities === nothing &&
    throw(ArgumentError("this run advects no tracers, so the cache has no particle-velocities slot"))
  cache.sample_fields_stamp == cache.fields_epoch &&
    cache.sample_particles_stamp == cache.particles_epoch ||
    error("the cached particle velocities are stale: the state or the tracer positions have advanced " *
          "past the deposited values, and nothing in the cache is ever recomputed; read at a " *
          "boundary, after the tail deposit")
  return point_values(cache.particle_velocities)
end


# ————————————————————————————————————————————————————————————————————————————————————————————————
# The producers' side: take a slot as scratch (clearing its stamp), deposit into it (stamping it at
# the current fields epoch). Deposits happen at the tail of the iteration, from the state it has
# just produced; the boundary check refuses to close an iteration with an undeposited slot.

# Take a slot's array as mid-iteration scratch. The stamp goes to SCRATCH, so a read between the
# take and the next deposit throws instead of returning a stage intermediate.
take_velocity!(cache::ObservablesCache) = (cache.velocity_stamp = SCRATCH; cache.velocity)
take_vorticity!(cache::ObservablesCache) = (cache.vorticity_stamp = SCRATCH; cache.vorticity)
take_scalar!(cache::ObservablesCache) = (cache.scalar_stamp = SCRATCH; cache.scalar)

# Stamp a slot as holding the observable at the current fields epoch. The producer writes the value
# into the slot's array first, then stamps.
deposit_velocity!(cache::ObservablesCache) = (cache.velocity_stamp = cache.fields_epoch; cache.velocity)
deposit_vorticity!(cache::ObservablesCache) = (cache.vorticity_stamp = cache.fields_epoch; cache.vorticity)
deposit_scalar!(cache::ObservablesCache) = (cache.scalar_stamp = cache.fields_epoch; cache.scalar)
deposit_max_speed!(cache::ObservablesCache, value::Real) =
  (cache.max_speed = Float64(value); cache.max_speed_stamp = cache.fields_epoch; value)
deposit_sample!(cache::ObservablesCache) =
  (cache.sample_fields_stamp = cache.fields_epoch;
   cache.sample_particles_stamp = cache.particles_epoch; cache.particle_velocities)


# The boundary completeness check: every slot the configuration carries must be stamped at the
# current epoch when an iteration closes. No caller can fail this — a slot exists only because the
# schedule fills it — so a throw here names a solver bug at its source rather than letting the slot
# hold scratch for the rest of the run.
function check_boundary(cache::ObservablesCache)
  cache.velocity_stamp == cache.fields_epoch ||
    error("iteration closed with the velocity slot undeposited — a solver scheduling bug")
  cache.vorticity_stamp == cache.fields_epoch ||
    error("iteration closed with the vorticity slot undeposited — a solver scheduling bug")
  cache.scalar === nothing || cache.scalar_stamp == cache.fields_epoch ||
    error("iteration closed with the scalar slot undeposited — a solver scheduling bug")
  cache.max_speed_stamp == cache.fields_epoch ||
    error("iteration closed with the maximum velocity component undeposited — a solver scheduling bug")
  cache.particle_velocities === nothing ||
    (cache.sample_fields_stamp == cache.fields_epoch &&
     cache.sample_particles_stamp == cache.particles_epoch) ||
    error("iteration closed with the particle velocities undeposited — a solver scheduling bug")
  return cache
end


"""
    resolved_fields_modified!(cache)
    resolved_fields_modified!(sim)

Announce that the resolved fields — the spectral ``\\hat{\\boldsymbol{u}}``, ``\\hat\\varphi`` —
were changed outside the iteration (a re-seeded velocity, any direct write to the state's storage).
Advances the fields epoch of `cache`, so every cached observable is stale and reads throw until
the next deposit; that interval belongs to whoever made the change. Returns `cache` (or `sim`).

The sanctioned mutators call this for you: `step!` advances the epoch itself when it completes, and
the iteration's tail deposit then restores the cache. After a hand-made mutation, re-deposit with the
run layer's `deposit!` before advancing again — the timestep choice reads the cached maximum speed.
"""
resolved_fields_modified!(cache::ObservablesCache) = (cache.fields_epoch += 1; cache)


# The tracer push's counterpart: the tracer positions advanced, so every trajectory-bound stamp is
# stale. (The particle-velocities slot arrives with the particle strand.)
particles_modified!(cache::ObservablesCache) = (cache.particles_epoch += 1; cache)


end # module Cache
