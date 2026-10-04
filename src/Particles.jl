# Particles — Lagrangian tracer tracking. Tracers are advected by the velocity through the package's
# grid→point interpolation (a selectable `GBGPeriodicFields` spline scheme; `CatmullRom` by default,
# `LalescuSpline`/`LagrangeSpline` for higher order), and any physical field can be sampled along the
# trajectories; accumulating statistics over them is the caller's analysis, not this package's.
#
# Trajectory time integration is pluggable, exactly as the field side is: the scheme is an
# `AbstractParticleIntegrator` and its per-step registers are allocated per scheme by
# `allocate_buffers`, so the tracer set holds only trajectory STATE and never one scheme's scratch.
# `Heun` is the one scheme today — second-order, on the velocity at the start and end of the
# step (tₙ and tₙ₊₁), unlike advecting on the frozen start-of-step velocity (effectively first
# order). Its two velocity fields are exactly what the field solver already produces each step, so
# the tracer advance stays decoupled from the field Runge–Kutta internals. A higher-order scheme would
# want different registers (RK4 several stage velocities; a multistep scheme only host weight
# scratch, its sample history living in the cache) — which is precisely why they are not in `Tracers`.

"""
    Particles

It tracks Lagrangian particles, today the massless tracer:

- [`Tracers`](@ref) — the tracer set: the positions (a
  [`PointSet`](@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet)), a selectable
  interpolation scheme, and opt-in unwrapped positions read by [`unwrapped_positions`](@ref). The
  velocity at the particles is read from the run's observables cache through
  [`velocity_at_particles`](@ref GBGHomogeneousTurbulence.Cache.velocity_at_particles).
- [`AbstractParticleIntegrator`](@ref) — the particle integration schemes,
  [`Heun`](@ref) and [`AdamsBashforth`](@ref); [`ParticleIntegratorBuffers`](@ref) the
  per-step storage a scheme needs, and [`history_depth`](@ref) the length of the
  velocity-at-particles history a scheme requires.
- [`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!) — this module adds the particle
  method: interpolate the flow velocity at the tracers' current positions and deposit it in the
  observables cache. One value has two consumers: the Lagrangian statistics a caller accumulates,
  and the next advance, which reads it as its start-of-step velocity.
- [`advect!`](@ref) — advance the trajectories one step under the chosen scheme;
  [`restart!`](@ref) discards a scheme's history after the tracers are repositioned from outside
  the iteration.
- [`interpolate_at_particles!`](@ref) — read a field at the particle positions; [`new_vector_point_values`](@ref) /
  [`new_scalar_point_values`](@ref) allocate the output buffers it fills.
- [`ParticleTraversal`](@ref) — the memory-locality order the gathers visit the tracers in, a
  value-preserving accelerator; [`rebuild_traversal!`](@ref) refreshes it from the current
  positions.
- [`write_tracers`](@ref) / [`read_tracers`](@ref) — the tracer set's HDF5 persistence: positions,
  the opt-in unwrapped positions, and the interpolation scheme as one self-describing group
  (available once `HDF5` is loaded).
"""
module Particles

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, _real_type
using ..Cache: ObservablesCache, deposit_velocity_at_particles!, advance_particles_epoch!
# One generic builds the per-scheme registers on both sides of the run — the field scheme's and
# the particle integration scheme's — because it is one concept: allocate exactly what this scheme needs.
import ..Propagator: allocate_buffers, deposit!

export Tracers, AbstractParticleIntegrator, Heun, AdamsBashforth,
       ParticleIntegratorBuffers, ParticleTraversal, rebuild_traversal!,
       advect!, restart!, history_depth, interpolate_at_particles!,
       unwrapped_positions, new_vector_point_values, new_scalar_point_values


"""
    Tracers(domain; number_of_particles, interpolation_scheme, unwrapped = false,
            rng = default_rng())
    Tracers(domain; positions, interpolation_scheme, unwrapped = false)

A set of Lagrangian tracers, built on `domain`'s backend and element type.

Give **exactly one** of the two. The `number_of_particles` form seeds that many tracers uniformly
at random in the periodic box. The `positions` form supplies the tracer positions as a [`GBGPeriodicFields`](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/)
[`PointSet`](@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet), copied to `domain`'s
backend and element type. Supplying both, or neither, raises an `ArgumentError`, and so does a raw
array in place of the `PointSet`: coordinates cross into the package only through the
`GBGPeriodicFields` point types.

The `interpolation_scheme` is the `GBGPeriodicFields` scheme used to evaluate the velocity — and any
sampled field — at the tracer positions.
[`CatmullRom`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.CatmullRom) is the ``C^1``
choice and [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation)'s default; it is a ready-made value rather than a type, so it is passed
bare. [`LalescuSpline(n, m)`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.LalescuSpline)
and [`LagrangeSpline(n)`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.LagrangeSpline)
offer higher smoothness or interpolation order at a wider stencil — useful for derivative-sensitive
readouts such as acceleration statistics — with `n` (and, for `LalescuSpline`, `m`) the stencil and
smoothness parameters.

# Arguments

- `domain` — the [`FixedDomain`](@ref) whose backend, element type and box the set is built on.
- `number_of_particles` — seed this many tracers uniformly at random in the box.
- `positions` — or copy this `PointSet` in instead; give exactly one of the two.
- `interpolation_scheme` — the scheme used to evaluate a field at the tracer positions.
- `unwrapped = false` — set to `true` to also track the winding-preserving unwrapped positions
  [`unwrapped_positions`](@ref) serves; the wrapped positions stay the dynamical state either way.
- `rng` — the random stream seeding the positions (used with `number_of_particles`, ignored with
  `positions`); defaults to `Random.default_rng()`.

# Examples

A run carries tracers when `Simulation` is given a count;
[`advance!`](@ref GBGHomogeneousTurbulence.SimulationRun.advance!) then advances them with the
fields and records the Lagrangian velocity each iteration, so both reads below are current between
iterations:

```julia
sim = Simulation(grid_points_per_axis = 64, number_of_particles = 4096, scalar = true)
advance!(sim)

# the (M, 3) positions, via GBGPeriodicFields
X = point_positions(sim.tracers.positions)
# u(tₙ, X(tₙ)), the Lagrangian velocity — throws if stale
v = velocity_at_particles(sim.cache)

out = new_scalar_point_values(sim.tracers)  # allocate once, then reuse every iteration
interpolate_at_particles!(out, scalar_physical(sim.cache), sim.tracers)
```

Building a set directly — to place tracers deliberately rather than at random, and to advance them
by hand — takes the `positions` form, and then the scheme's per-step storage is yours to allocate:

```julia
tracers = Tracers(domain; positions = PointSet([0.1 0.2 0.3; 1.0 1.0 1.0]),
                  interpolation_scheme = CatmullRom)
cache   = ObservablesCache(domain; number_of_particles = npoints(tracers.positions))
buffers = allocate_buffers(Heun(), tracers, cache)

# u(tₙ) at the current positions — do this first
deposit!(cache, tracers, u)
advect!(Heun(), tracers, u_end, domain, buffers, dt)
```

Read the particle state straight off the struct's own fields — the positions are
[`PointSet`](@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet)s, and raw arrays and
counts come from `GBGPeriodicFields`' `point_positions` and `npoints`, never from accessors of
this package. Passing `unwrapped = true` additionally tracks the winding-preserving
unwrapped positions `unwrapped_positions` serves — the wrapped positions stay the dynamical
state either way. The velocities are a *deposited observable*, not tracer state: the particle form
of [`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!) writes them into the run's observables cache at the end of each iteration, and
[`velocity_at_particles`](@ref GBGHomogeneousTurbulence.Cache.velocity_at_particles) reads them there.

The particle integration scheme's own working storage is **not** here: it lives in a
[`ParticleIntegratorBuffers`](@ref), whose docstring explains the split.

# Fields
- `positions` — the tracer positions, as the
  [`PointSet`](@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet) every operation takes:
  the one storage, always wrapped — the dynamical state. `GBGPeriodicFields`' `point_positions`
  serves its `(M, 3)` matrix view, with ``M`` the tracer count.
- `interpolation_scheme` — the scheme used to evaluate a field at the tracer positions.
- `unwrapped_positions` — the opt-in unwrapped positions (`unwrapped = true`) as a `PointSet`, advanced
  by every push with the same displacement terms but never reduced to the box; `nothing` when
  untracked. Read it through `unwrapped_positions`.
"""
struct Tracers{PSX, S, UP}
  positions::PSX      # PointSet — the (always wrapped) dynamical state; the ONE storage
  interpolation_scheme::S
  unwrapped_positions::UP      # PointSet (the opt-in unwrapped positions, winding kept), or nothing
end


# The two forms are ONE method, not two: they are distinguished by which keyword is supplied, and
# Julia dispatches on positional arguments only. Hence the explicit either/or check, which also gives
# a better error than a missing-keyword one would.
function Tracers(domain::FixedDomain; interpolation_scheme, positions = nothing,
                 number_of_particles = nothing, unwrapped::Bool = false,
                 rng = Random.default_rng())
  count(!isnothing, (positions, number_of_particles)) == 1 ||
    throw(ArgumentError("give exactly one of `positions` (a `PointSet` of tracer positions) or " *
                        "`number_of_particles` (a count to seed at random)"))
  T = _real_type(domain)
  if isnothing(positions)
    M = Int(number_of_particles)
    pos = domain.storage_family{T}(undef, M, 3)
    # Drawn on the host so one seed gives the same positions on every backend (decision 107), and
    # scaled in place: on the CPU the kept array IS host memory and takes the draw directly; on a
    # device one host array is drawn into and moved.
    host = domain.storage_family === Array ? pos : Array{T}(undef, M, 3)
    rand!(rng, host)
    host .*= T(domain.grid.domain_size[1])
    host === pos || copyto!(pos, host)
  else
    positions isa PointSet ||
      throw(ArgumentError("`positions` must be a `GBGPeriodicFields` `PointSet` (wrap an (M, 3) " *
                          "array with `PointSet(array)`); got a $(typeof(positions)). Raw arrays " *
                          "cross into the package only through the `GBGPeriodicFields` point types."))
    supplied = point_positions(positions)
    pos = domain.storage_family{T}(undef, size(supplied)...)    # the domain's backend + element type
    copyto!(pos, supplied)
  end
  # The unwrapped record starts equal to the wrapped positions and thereafter receives the same
  # displacements WITHOUT the periodic reduction (the grid-free `displace!` — PF's universal-cover
  # lift), so the two can never disagree on a step, only on the winding the wrap discards.
  return Tracers(PointSet(pos), interpolation_scheme,
                 unwrapped ? PointSet(copy(pos)) : nothing)
end


"""
    ParticleTraversal(domain, tracers; automatic = true)

The memory-locality order in which a field is gathered at the tracers — a
[`PointTraversalOrder`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.PointTraversalOrder)
over the tracer set `tracers` on the grid of `domain` (a [`FixedDomain`](@ref)), together with the
scratch that lets it be rebuilt in place. Tracers seeded at random, or mixed by the flow, visit the
grid in no order at all, so each interpolation stencil is a cache miss; visiting them
tile-by-tile turns the gather into a sweep, and `GBGPeriodicFields`' `interpolate!` accepts such an
order through its `traversal` keyword. The order only reorders the visits — it changes no value,
so a run with and without it produces bitwise-identical trajectories and samples.

A run builds one for you: [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation)'s
`ordered_interpolation` keyword decides whether, and whether the run or the caller rebuilds it.
Building it by hand belongs with a hand-run loop, where it is passed on to
[`advect!`](@ref), the particle form of [`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!)
and [`interpolate_at_particles!`](@ref) through their `traversal` keyword.

# Arguments

- `domain` — the `FixedDomain` whose grid the tiles are laid over.
- `tracers` — the [`Tracers`](@ref) whose positions are ordered; the order is sized to their count
  and built from their current positions.
- `automatic = true` — whether a run rebuilds the order every iteration (`true`) or leaves the
  rebuilding to the caller, through [`rebuild_traversal!`](@ref) (`false`). A rebuild costs a small
  fraction of the gather it accelerates, so every iteration is the default; a stale order is never
  wrong, only progressively less useful as the flow mixes the tracers away from it.

!!! note "One order serves every gather of the step"
    `GBGPeriodicFields` accepts any same-length order for a point set of the same count, so the one
    order built from the tracer positions is also passed to the gather at the predicted positions
    a [`Heun`](@ref) step makes; those sit a step's displacement from the tracers, well inside the
    tiles the order groups.

# Fields
- `order` — the `PointTraversalOrder`: one `Int32` index per tracer, a permutation of the visits.
- `scratch` — the
  [`PointTraversalOrderScratch`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.PointTraversalOrderScratch)
  the in-place rebuild sorts in: the per-tracer tile keys and the per-tile counts and offsets.
- `automatic` — whether a run rebuilds the order every iteration.
"""
struct ParticleTraversal{O, S}
  order::O           # PointTraversalOrder — the Int32 permutation the gathers visit the tracers in
  scratch::S         # PointTraversalOrderScratch — the counting-sort scratch of the in-place rebuild
  automatic::Bool    # a run rebuilds every iteration (true), or the caller does through rebuild_traversal!
end


# Built through the in-place rebuild with the scratch the run keeps: the allocating
# `point_traversal_order` would make a second, temporary sorting scratch beside it. The identity
# permutation is the starting order the rebuild overwrites.
function ParticleTraversal(domain::FixedDomain, tracers::Tracers; automatic::Bool = true)
  coordinates = point_positions(tracers.positions)
  scratch = PointTraversalOrderScratch(domain.grid, tracers.positions)
  identity = similar(coordinates, Int32, size(coordinates, 1))
  identity .= Int32(1):Int32(length(identity))
  order = point_traversal_order!(PointTraversalOrder(identity), domain.grid, tracers.positions, scratch)
  return ParticleTraversal(order, scratch, automatic)
end


"""
    rebuild_traversal!(traversal, domain, tracers) -> traversal
    rebuild_traversal!(sim) -> sim

Rebuild the tracer traversal order from the current tracer positions, in place.

# Arguments
- `traversal` — the [`ParticleTraversal`](@ref) to rebuild.
- `domain` — the [`FixedDomain`](@ref) whose grid the order is taken on.
- `tracers` — the tracer set whose positions are ordered.
- `sim` — a run ([`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation)), in the second
  form: the traversal it carries as `sim.particle_traversal` is rebuilt.

Call it from a run's callback when the run was built with `ordered_interpolation = :manual`, at
whatever cadence you choose — every so many steps with
[`every_steps`](@ref GBGHomogeneousTurbulence.SimulationRun.every_steps), or every so much time with
[`every_time`](@ref GBGHomogeneousTurbulence.SimulationRun.every_time). With the default automatic
mode the run rebuilds every iteration and the call is never needed. The rebuild allocates nothing
at the tracer scale; a run without a traversal order refuses the call with an `ArgumentError`.
"""
function rebuild_traversal! end

function rebuild_traversal!(traversal::ParticleTraversal, domain::FixedDomain, tracers::Tracers)
  point_traversal_order!(traversal.order, domain.grid, tracers.positions, traversal.scratch)
  return traversal
end


"""
    AbstractParticleIntegrator

The supertype of the particle integration schemes — how the tracer positions are advanced
over one step, the Lagrangian counterpart of the field side's
[`AbstractIntegrator`](@ref GBGHomogeneousTurbulence.Propagator.AbstractIntegrator). A scheme is a
value (`Heun()`), passed to [`advect!`](@ref) and to
[`allocate_buffers`](@ref GBGHomogeneousTurbulence.Propagator.allocate_buffers), which builds exactly
the working storage that scheme needs.

The family has two members today: [`Heun`](@ref), a one-step method that buys second order with a second
interpolation, and [`AdamsBashforth`](@ref), a multistep method that buys more by reusing the
Lagrangian samples the run already deposits. Which trade a run wants is for its user to measure — one
interpolation per step against one stored array per extra order.
"""
abstract type AbstractParticleIntegrator end


"""
    Heun()

Second-order Heun-in-time on the velocity at the two **ends** of the step — the particle
integration scheme a run uses by default. It advances the positions with the start-of-step Lagrangian
velocity the previous iteration's closing particle
[`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!) left in the cache and the
end-of-step velocity field the solver has just produced, so it needs nothing from inside the field
scheme's stages.

It needs one set of predicted positions and the velocity interpolated there
([`ParticleIntegratorBuffers`](@ref)); the formula is given with [`advect!`](@ref).

!!! note "Pair it with the default interpolant unless the grid is coarse"
    Under the advective-CFL loop ``\\Delta t \\propto \\Delta x``, so this scheme's error falls as
    ``\\Delta x^{2}`` while a degree-``d`` interpolant's trajectory floor falls as
    ``\\Delta x^{d+1}``. For the default
    [`CatmullRom`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.CatmullRom) (degree 2)
    the floor therefore falls *faster* than the time error, and the two cross over: measured on a
    band-limited field, interpolation dominates at ``N = 16{-}32``
    and the time error dominates from ``N \\approx 64`` on (at ``N = 128`` the floor is
    ``1\\times10^{-5}`` against a time error of ``6\\times10^{-5}``; the numbers are setup-specific,
    and only the ``\\Delta x^{d+1}`` trend generalizes). So at production resolutions `CatmullRom` is
    not what limits a Heun
    trajectory and a wider stencil buys nothing; at coarse resolution, or with ``\\Delta t`` cut well
    below the CFL value, `LalescuSpline(3, 1)` — same ``C^1``, degree 3 — moves the floor down by
    more than an order of magnitude. What governs this in a run is how well the grid resolves the
    dissipation scale, so read ``N`` here as a stand-in for ``\\kappa_{\\max}\\eta``.
"""
struct Heun <: AbstractParticleIntegrator end




"""
    restart!(scheme, buffers) -> buffers

Discard whatever history `buffers` holds for the particle integration scheme `scheme`, so the
next [`advect!`](@ref) starts that scheme from scratch.

Call it whenever the tracer positions are changed from outside the iteration — a reseed, a
hand-written correction, any direct write to the tracer storage. A one-step scheme carries no
history and this does nothing; a multistep scheme carries Lagrangian samples taken along the
trajectory just abandoned, and integrating over those would blend the old path with the new one.
This is an in-memory reset of one scheme's history, not a checkpoint verb — restoring a saved run
is the job of [`read_simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.read_simulation).

The [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) form of
[`particles_modified!`](@ref GBGHomogeneousTurbulence.Cache.particles_modified!) calls this for you,
after announcing the reposition to the observables cache. Its bare-cache form clears only the
sample history the cache itself holds and cannot dispatch here — so a hand-run loop that announces
to the cache alone must also call this; a scheme's own per-step buffers beyond that history are
reached only this way.
"""
function restart! end


"""
    ParticleIntegratorBuffers

The per-step storage a particle integration scheme computes in, sized to a tracer set and allocated
once, so advancing the tracers allocates nothing. Build it with
[`allocate_buffers(scheme, tracers, cache)`](@ref GBGHomogeneousTurbulence.Propagator.allocate_buffers),
which allocates exactly what `scheme` needs and nothing more; a run builds it for you.

This storage belongs to the scheme, not to the trajectory — which is why it lives here rather than
in [`Tracers`](@ref). One type serves every scheme, because the storage sets nest: a multistep
scheme uses the predictor arrays for its [`Heun`](@ref) starting steps only, and adds two
`order`-element host vectors for its weight solve.

The past Lagrangian samples a multistep scheme integrates over are **not** held here. They are
deposited observables — measurements of the velocity along the trajectory — so they live in the
[`ObservablesCache`](@ref GBGHomogeneousTurbulence.Cache.ObservablesCache) beside the current sample
they extend, which is what lets
[`particles_modified!`](@ref GBGHomogeneousTurbulence.Cache.particles_modified!) invalidate the whole
history when the tracers are repositioned.

# Fields
- `predictor` — the `(M, 3)` predicted positions, which no tracer ever occupies.
- `predictor_points` — a
  [`PointSet`](@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet) wrapping `predictor`.
- `velocity_predictor` — the velocity interpolated at the predicted positions. It is reachable like
  any field of this type, but it is a scheme intermediate rather than a sample of the flow at any
  instant, so nothing in the package offers it as one: read
  [`velocity_at_particles`](@ref GBGHomogeneousTurbulence.Cache.velocity_at_particles) for the Lagrangian
  sample.
- `cache` — the run's `ObservablesCache`: the start-of-step sample and any multistep history are
  its slots.
- `weights`, `nodes` — the `order`-element host scratch of a multistep weight solve; empty for a
  one-step scheme.
"""
struct ParticleIntegratorBuffers{P, PS, VV, C}
  predictor::P
  predictor_points::PS
  velocity_predictor::VV
  cache::C                  # the run's ObservablesCache: the v₁ sample is ITS slot (decision 67)
  # Host scratch for the multistep weight solve, allocated once (the solve runs every warmed-up
  # step, and the hot loop is allocation-free over preallocated buffers). Empty for a one-step scheme.
  weights::Vector{Float64}
  nodes::Vector{Float64}
end


function _allocate_particle_buffers(tracers::Tracers, cache::ObservablesCache, order::Int)
  cache.velocity_at_particles === nothing &&
    throw(ArgumentError("this cache carries no velocity-at-particles slot: build it with " *
                        "`number_of_particles` matching the tracer set — the sample the push " *
                        "consumes is the cache's observable, not tracer state"))
  predictor = similar(point_positions(tracers.positions))
  return ParticleIntegratorBuffers(predictor, PointSet(predictor),
                                   VectorPointValues(similar(predictor)), cache,
                                   zeros(Float64, order), zeros(Float64, order))
end


allocate_buffers(::Heun, tracers::Tracers, cache::ObservablesCache) =
  _allocate_particle_buffers(tracers, cache, 0)


# A one-step scheme is memoryless: every register it owns is overwritten before it is read.
restart!(::Heun, buffers::ParticleIntegratorBuffers) = buffers


"""
    AdamsBashforth(; order = 4)

Variable-step Adams–Bashforth trajectory integration — the scheme TurTLE uses for its tracers, at
its default order (Lalescu et al. 2022) — buying accuracy in
time at **no extra field evaluation and no extra interpolation** per step.

Use it in place of [`Heun`](@ref) when trajectory accuracy in time limits a measurement. Heun
buys its second order by interpolating a second time, at predicted positions; Adams–Bashforth instead
reuses the Lagrangian samples the run has already deposited at earlier instants. The trade is one
stored array per extra order against one interpolation per step; the update formula is given with
[`advect!`](@ref).

The steps are **not** assumed uniform: the advective-CFL loop changes ``\\Delta t`` every iteration,
which classical fixed-step coefficients would silently get wrong, so the weights are recomputed each
step from the actual step history. That is ``\\mathcal{O}(\\texttt{order}^2)`` host arithmetic per
step, independent of the tracer count.

A multistep method has no history at ``t_0``, so the first `order - 1` steps are taken with
`Heun` and the scheme then switches over; the same restart happens if the tracers are
reseeded. Those second-order starting steps leave a fixed error behind, so over a fixed window
`order = 4` converges at about third order rather than fourth — on a smooth test problem, ``3.0``
against ``2.0`` for the two-step method, with an error some fifty times smaller at equal step count.
A higher-order start would need the velocity between the step endpoints, which the solver does not
produce.

# Arguments
- `order = 4` — how many past samples are used. `1` is forward Euler, `2` the two-step method, `4`
  TurTLE's default. Orders above `8` are refused with an `ArgumentError`: past it the four-point
  Gauss–Legendre rule that integrates the interpolation weights stops being exact, and the refusal
  is loud because the alternative is silently wrong weights. The cap is far above any useful order,
  since an Adams–Bashforth stability region shrinks with each step added — and the bootstrap makes
  high orders *worse*, not just useless: over a fixed window, `order = 6` and `order = 8` measure
  the same third-order convergence as `order = 4` with **larger** errors (measured ``1.0`` and
  ``1.4`` against ``0.6``, in units of ``10^{-7}`` at 80 steps: the longer `Heun` bootstrap
  costs more than the extra history returns). The practical ceiling is `order = 4`.

!!! warning "The interpolant sets a floor no timestep can cross"
    Interpolating the velocity perturbs the field the tracers follow, and that perturbation does not
    shrink with ``\\Delta t``: for a perturbation of size ``\\delta`` and a flow with Lipschitz
    constant ``\\Lambda`` over a span ``t``, Grönwall bounds the trajectory error by
    ``\\delta(\\mathrm{e}^{\\Lambda t} - 1)/\\Lambda`` however the time integration is done. Refining the step, or raising `order`, pays only until the time error reaches that floor.
    Where `Heun`'s docstring reports a crossover in resolution, this scheme has **none**:
    at third order under the advective-CFL loop the time error falls as ``\\Delta x^{3}`` — the
    same rate as the default `CatmullRom` floor's ``\\Delta x^{d+1}`` — so their ratio is set by
    prefactors alone, and measured on a band-limited field at ``N = 32``–``128`` the floor stays
    two to three orders of magnitude *below* the time error. At CFL steps the interpolant never
    limits an Adams–Bashforth trajectory, and a wider stencil buys nothing; only a ``\\Delta t``
    cut well below the CFL value surfaces the floor.

    The floor is set by the interpolant's **polynomial reproduction degree**, not its smoothness
    class — measured here, raising the degree at fixed ``C^1`` lowered it fifty-fold, while varying
    the smoothness at fixed degree left the time convergence unchanged. Raise the degree when the
    floor is what limits you; smoothness buys something different, namely readouts that
    *differentiate* the interpolant, such as acceleration (Lalescu, Teaca & Carati 2010).

# References
- Lalescu, C. C., Bramas, B., Rampp, M. & Wilczek, M. (2022). [*An efficient particle tracking algorithm for large-scale parallel pseudo-spectral simulations of turbulence*](https://doi.org/10.1016/j.cpc.2022.108406). *Comput. Phys. Commun.* **278**, 108406.
- Lalescu, C. C., Teaca, B. & Carati, D. (2010). [*Implementation of high order spline interpolations for tracking test particles in discretized fields*](https://doi.org/10.1016/j.jcp.2010.04.006). *J. Comput. Phys.* **229**(17), 5862–5869.

# Fields
The scheme stores no fields: `order` is carried as a type parameter, so the keyword constructor
above is the only way to build one.
"""
struct AdamsBashforth{K} <: AbstractParticleIntegrator end

# The upper bound is the quadrature's, not a taste: `_adams_bashforth_weights` integrates the
# degree-(order−1) Lagrange basis with a FOUR-point Gauss–Legendre rule, exact only through degree 7.
# At order ≥ 9 the rule would return silently inexact weights — a wrong trajectory with no symptom —
# so the ceiling is enforced here rather than documented and hoped for.
AdamsBashforth(; order::Integer = 4) =
  (order >= 1 || throw(ArgumentError("`order` must be at least 1, got $order"));
   order <= 8 || throw(ArgumentError("`order` must be at most 8, got $order: the four-point " *
                                     "Gauss–Legendre rule that integrates the weights is exact " *
                                     "only through degree 7, so a higher order would be given " *
                                     "silently wrong coefficients"));
   AdamsBashforth{Int(order)}())


function allocate_buffers(::AdamsBashforth{K}, tracers::Tracers, cache::ObservablesCache) where {K}
  # Equality, not sufficiency — the same demand every advect! makes. A shallower cache would read
  # fewer past samples than the order claims (a silently lower-order integration); a deeper one
  # passes allocation only to be refused by the first push, since the shared history's fill level
  # is capped against the order of the advancing call.
  length(cache.velocity_at_particles_history) == K - 1 ||
    throw(ArgumentError("this cache carries $(length(cache.velocity_at_particles_history)) past " *
                        "sample(s), but `AdamsBashforth(order = $K)` integrates over exactly " *
                        "$(K - 1); build the cache with `history_depth = $K`"))
  return _allocate_particle_buffers(tracers, cache, K)
end


"""
    history_depth(scheme) -> Int

How many Lagrangian samples `scheme` must be able to look back over, counting the current one.

A run reads this to size the sample history its
[`ObservablesCache`](@ref GBGHomogeneousTurbulence.Cache.ObservablesCache) carries. A one-step scheme
answers `1` and needs no history stored; an `order`-step method answers `order`.
"""
function history_depth end

history_depth(::AbstractParticleIntegrator) = 1
history_depth(::AdamsBashforth{K}) where {K} = K


# Variable-step Adams–Bashforth weights. With samples f_j at times t_n = τ_0 > τ_1 > … > τ_{k-1},
# the update is X_{n+1} = X_n + Σ_j b_j f_j, where b_j = ∫_{t_n}^{t_n+h} L_j(t) dt and L_j is the
# Lagrange basis on those nodes. Four-point Gauss–Legendre integrates the degree-(k-1) basis exactly
# for every order this scheme allows, and the whole computation is k² host arithmetic per step.
const _GAUSS_NODES = (-0.8611363115940526, -0.3399810435848563, 0.3399810435848563, 0.8611363115940526)
const _GAUSS_WEIGHTS = (0.3478548451374538, 0.6521451548625461, 0.6521451548625461, 0.3478548451374538)

function _adams_bashforth_weights(b::Vector{Float64}, τ::Vector{Float64}, h::Float64,
                                  steps::AbstractVector{Float64}, k::Int)
  τ[1] = 0.0                                 # node times, relative to t_n, going backwards
  for j in 2:k
    τ[j] = τ[j-1] - steps[j-1]
  end
  fill!(b, 0.0)
  for (ξ, w) in zip(_GAUSS_NODES, _GAUSS_WEIGHTS)
    t = h * (ξ + 1) / 2                      # map [-1,1] → [0,h]
    scale = w * h / 2
    for j in 1:k                             # Lagrange basis at t, on nodes τ
      Lj = 1.0
      for m in 1:k
        m == j && continue
        Lj *= (t - τ[m]) / (τ[j] - τ[m])
      end
      b[j] += scale * Lj
    end
  end
  return b
end


function advect!(scheme::AdamsBashforth{K}, tracers::Tracers, velocity_end, domain::FixedDomain,
                 buffers::ParticleIntegratorBuffers, dt::Real; traversal = nothing) where {K}
  T = real(eltype(point_positions(tracers.positions)))

  # A non-positive step would enter the history as a repeated (or reversed) node, and the Lagrange
  # basis divides by the node differences — so the next warmed-up step divides by zero and returns
  # NaN positions. Refused here, where the history is written, rather than left to surface as a
  # silently ruined trajectory some steps later.
  dt > 0 || throw(ArgumentError("`dt` must be positive, got $dt: a multistep history cannot carry " *
                                "a zero-length or reversed step"))

  # The past samples are the cache's, not this scheme's: an announced reposition clears them there,
  # so a history that survived one is not reachable from here.
  cache = buffers.cache
  past, steps = cache.velocity_at_particles_history, cache.history_steps
  # The history's depth IS the order this call will actually achieve. Handed buffers built for a
  # shallower scheme, the loop below would read fewer past samples than `K` claims and integrate at
  # a lower order without saying so.
  length(past) == K - 1 ||
    throw(ArgumentError("this `AdamsBashforth(order = $K)` integrates over $(K - 1) past sample(s), " *
                        "but the buffers it was handed carry $(length(past)): they were built for a " *
                        "different order. Equality, not sufficiency — the shared history's fill " *
                        "level is capped against the order of whichever call last advanced it, so " *
                        "mixing two orders over one history corrupts the bookkeeping in both."))
  # The weight scratch is sized at allocation; a mismatch means the buffers were built for another
  # scheme, and the solve below would read past their end. `allocate_buffers` ties the weights and
  # the history depth to one order, so through it the guard above always fires first; this one
  # stands for a hand-assembled `ParticleIntegratorBuffers`.
  length(buffers.weights) == K ||
    throw(ArgumentError("these buffers carry weight scratch for order $(length(buffers.weights)), " *
                        "not $K: they were built for a different scheme; allocate with " *
                        "`allocate_buffers(AdamsBashforth(order = $K), tracers, cache)`"))

  if cache.history_filled < K - 1            # no history yet: start up on the one-step scheme
    advect!(Heun(), tracers, velocity_end, domain, buffers, dt; traversal)
  else
    b = _adams_bashforth_weights(buffers.weights, buffers.nodes, Float64(dt), steps, K)
    # ONE fused K-term displacement, wrap included (PF decision 73): the K broadcast passes this
    # loop once made over the positions collapse into a single traversal. The unwrapped record,
    # when tracked, takes the identical terms through the grid-free form.
    terms = ((T(b[1]), cache.velocity_at_particles),
             ntuple(j -> (T(b[j + 1]), past[j]), K - 1)...)
    displace!(tracers.positions, domain.grid, terms...)
    tracers.unwrapped_positions === nothing ||
      displace!(tracers.unwrapped_positions, terms...)
    advance_particles_epoch!(cache)          # the bootstrap branch announced through Heun's push
  end

  # Shift the history: the sample just used at t_n becomes the most recent past sample. The copy is
  # what keeps the deposited observable intact — the current slot is rewritten every iteration, so a
  # multistep method that aliased it would integrate over values that have since been overwritten.
  for j in min(cache.history_filled + 1, K - 1):-1:2
    copyto!(point_values(past[j]), point_values(past[j-1]))
    steps[j] = steps[j-1]
  end
  if K > 1
    copyto!(point_values(past[1]), point_values(cache.velocity_at_particles))
    steps[1] = Float64(dt)
    cache.history_filled = min(cache.history_filled + 1, K - 1)
  end
  return tracers
end


restart!(::AdamsBashforth, buffers::ParticleIntegratorBuffers) = (buffers.cache.history_filled = 0; buffers)


# The particle method of `deposit!` — the generic, and the one docstring covering all its forms,
# live in `Propagator`. This method interpolates and stamps in one act: it is the slot's only
# producer of values, and the two counters it stamps against advance elsewhere (the step and the
# push), so the deposit is the pure closing measurement of both.
function deposit!(cache::ObservablesCache, tracers::Tracers, u; traversal = nothing)
  cache.velocity_at_particles === nothing &&
    throw(ArgumentError("this cache carries no velocity-at-particles slot: build it with " *
                        "`number_of_particles` matching the tracer set"))
  interpolate!(cache.velocity_at_particles, u, tracers.positions, tracers.interpolation_scheme;
               traversal)
  deposit_velocity_at_particles!(cache)
  return cache
end


"""
    advect!(scheme, tracers, velocity_end, domain, buffers, dt;
            traversal = nothing) -> tracers

Advance the positions of a tracer set by one step, in place.

# Arguments
- `scheme` — the particle integration scheme, an [`AbstractParticleIntegrator`](@ref).
- `tracers` — the tracer set whose positions advance.
- `velocity_end` — the end-of-step velocity field ``\\boldsymbol{u}(t_{n+1})`` in physical representation.
- `domain` — the [`FixedDomain`](@ref), which supplies the box side the positions are wrapped into.
- `buffers` — the scheme's working storage, the [`ParticleIntegratorBuffers`](@ref) that
  [`allocate_buffers`](@ref GBGHomogeneousTurbulence.Propagator.allocate_buffers) builds for it.
- `dt` — the step size, written ``\\Delta t`` below.
- `traversal = nothing` — the `PointTraversalOrder` of a [`ParticleTraversal`](@ref) (its `order`
  field), to gather the velocity in memory-locality order; `nothing` gathers in tracer order, with
  identical values.

Under [`Heun`](@ref), the scheme is Heun-in-time on the velocity at the two ends of the step — the
start-of-step values the previous iteration's closing particle deposit stored, and `velocity_end`:

```math
\\begin{aligned}
\\boldsymbol{v}_1 &= \\boldsymbol{u}(t_n, \\boldsymbol{X}), &
\\boldsymbol{X}^{*} &= \\boldsymbol{X} + \\Delta t \\boldsymbol{v}_1, \\\\
\\boldsymbol{v}_2 &= \\boldsymbol{u}(t_{n+1}, \\boldsymbol{X}^{*}), &
\\boldsymbol{X} &\\leftarrow \\boldsymbol{X} + \\tfrac{\\Delta t}{2}(\\boldsymbol{v}_1 + \\boldsymbol{v}_2),
\\end{aligned}
```

with positions wrapped into ``[0, L)``. This is second-order accurate in time — advecting on the
frozen start-of-step velocity alone would be first order.

Every push also advances the cache's particles epoch, its count of position changes, so a read of
the previous velocity sample throws as stale until the particle deposit closing the iteration
refreshes it. A hand-run loop gets the same protection as a run.

Under [`AdamsBashforth`](@ref), the position update integrates over the deposited samples instead
of interpolating a second time,

```math
\\boldsymbol{X} \\leftarrow \\boldsymbol{X}
  + \\sum_{j=0}^{K-1} b_j \\boldsymbol{u}(t_{n-j}, \\boldsymbol{X}(t_{n-j})),
```

with ``K`` the order and the weights ``b_j`` re-solved each step by integrating the Lagrange basis
on the recorded step history (the steps are not assumed uniform). The first ``K - 1`` pushes have
no history yet and are taken under `Heun`; `velocity_end` feeds only those bootstrap
pushes.

!!! note "The start-of-step velocity is read, never recomputed"
    The start-of-step velocity ``\\boldsymbol{v}_1`` comes from the cache's stored velocity at the
    particles, not recomputed here: it must hold
    ``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))``, deposited by the particle
    form of [`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!) at the previous
    iteration's end. The run's [`advance!`](@ref GBGHomogeneousTurbulence.SimulationRun.advance!) checks that it is current before each push; a hand-run
    loop must make that deposit itself between advances.
"""
function advect! end

function advect!(::Heun, tracers::Tracers, velocity_end, domain::FixedDomain,
                 buffers::ParticleIntegratorBuffers, dt::Real; traversal = nothing)
  Δt = real(eltype(point_positions(tracers.positions)))(dt)
  # The predictor displacement, wrap fused (PF decision 73): X* = X + Δt·v₁, reduced to the box.
  v₁ = buffers.cache.velocity_at_particles
  displace!(buffers.predictor_points, tracers.positions, domain.grid,
            (Δt, v₁))
  # v₂ is evaluated at the PREDICTOR positions and is a stage register, never the deposited velocity sample —
  # and it must never be reused as the next step's v₁: the two differ only at O(Δt²), but that reuse
  # would corrupt the recorded observable the Lagrangian statistics accumulate (never approximate
  # the thing you measure). The traversal order built over the tracers serves this gather too: the
  # predictor positions sit one step's displacement from them, inside the tiles the order groups,
  # and the field library admits any same-length order.
  interpolate!(buffers.velocity_predictor, velocity_end, buffers.predictor_points,
               tracers.interpolation_scheme; traversal)
  # The corrector: one fused two-term displacement, wrap included.
  displace!(tracers.positions, domain.grid,
            (Δt / 2, v₁), (Δt / 2, buffers.velocity_predictor))
  # The unwrapped positions take the SAME terms through the grid-free form: winding kept, and the
  # two records share the displacement by construction.
  tracers.unwrapped_positions === nothing ||
    displace!(tracers.unwrapped_positions,
              (Δt / 2, v₁), (Δt / 2, buffers.velocity_predictor))
  # The push announces itself (decision 76): the positions changed, so the particles counter moves
  # and the previously deposited sample reads stale until the closing particle deposit. This keeps
  # the two-epoch guard live on a hand-run loop, not only under `advance!`.
  advance_particles_epoch!(buffers.cache)
  return tracers
end


"""
    interpolate_at_particles!(out, field, tracers; traversal = nothing) -> out

Sample a physical field at the current tracer positions. This is how a field is gathered along the
trajectories; what is then accumulated over those values is the caller's own analysis.

# Arguments
- `out` — the point-value buffer written: a
  [`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) for the
  velocity, a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues)
  for the scalar ``\\varphi``.
- `field` — the field in physical representation.
- `tracers` — the tracer set, whose positions and interpolation scheme are used.
- `traversal = nothing` — the `PointTraversalOrder` of a [`ParticleTraversal`](@ref) (its `order`
  field), to gather in memory-locality order — on a run, `sim.particle_traversal.order`; `nothing`
  gathers in tracer order, with identical values.
"""
function interpolate_at_particles!(out, field, tracers::Tracers; traversal = nothing)
  interpolate!(out, field, tracers.positions, tracers.interpolation_scheme; traversal)
  return out
end


"""
    unwrapped_positions(tracers)

The **unwrapped** positions of the tracer set `tracers`, as a
[`PointSet`](@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet) — the trajectory with its
winding kept, each coordinate the literal sum of every displacement since seeding, never reduced to
the periodic box. These are the positions a mean-square-displacement or dispersion diagnostic
needs: those are functions of ``\\boldsymbol{X}(t) - \\boldsymbol{X}(0)``, which box-wrapped
positions cannot supply across a crossing. Accumulating such statistics over them — on the raw
`(M, 3)` array `GBGPeriodicFields`' `point_positions` extracts — is the caller's analysis.

The unwrapped positions exist only when the tracer set was built with `unwrapped = true`; reading
an untracked set throws an `ArgumentError` (which is why this throwing read exists while the plain
state is read straight off the struct's fields). The wrapped positions remain the dynamical state either
way — the dynamics always advance wrapped, since a coordinate that grows with winding loses
absolute floating-point resolution, while the unwrapped positions only ever feed differences,
whose *relative* accuracy the growth does not touch. An announced reposition
([`particles_modified!`](@ref GBGHomogeneousTurbulence.Cache.particles_modified!) on a run) restarts
the unwrapped positions at the wrapped ones: winding is a property of the trajectory just abandoned.
"""
function unwrapped_positions(tracers::Tracers)
  tracers.unwrapped_positions === nothing &&
    throw(ArgumentError("this tracer set carries no unwrapped positions: build it with " *
                        "`unwrapped = true` (a `Tracers` keyword, forwarded by `Simulation`) " *
                        "to track winding alongside the wrapped positions"))
  return tracers.unwrapped_positions
end


"""
    new_vector_point_values(tracers)

Allocate a [`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) of
shape `(M, 3)` matching the tracer set `tracers`, for use as the `out` of
[`interpolate_at_particles!`](@ref) when sampling the velocity at the particle positions.
"""
new_vector_point_values(tracers::Tracers) = VectorPointValues(similar(point_positions(tracers.positions)))

"""
    new_scalar_point_values(tracers)

Allocate a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues) of
length ``M`` matching the tracer set `tracers`, for use as the `out` of
[`interpolate_at_particles!`](@ref) when sampling the scalar ``\\varphi`` at the particle positions.
"""
new_scalar_point_values(tracers::Tracers) =
  ScalarPointValues(similar(point_positions(tracers.positions),
                            eltype(point_positions(tracers.positions)),
                            npoints(tracers.positions)))



# ————————————————————————————————————————————————————————————————————————————————————————————————
# Display (the convention is stated once, at `SimulationDomain`'s display section). A tracer set
# is its positions through the field library's `show` (count, element type, storage — what a run
# refuses a tracer set on), its interpolation scheme, and the unwrapped record, which the unwrapped
# read refuses on — through its own display when kept, `no unwrapped positions` when not. The
# scheme prints as the constructor call that rebuilds it.
# A register set is its predictor (the only display of the package still growing with the particle
# count, so it leads) and its order — the depth of history it holds, which the cache is matched on.

Base.show(io::IO, ::AdamsBashforth{K}) where {K} = print(io, "AdamsBashforth(order = ", K, ")")

function Base.show(io::IO, tracers::Tracers)
  print(io, "Tracers(", tracers.positions, ", ", tracers.interpolation_scheme)
  isnothing(tracers.unwrapped_positions) ? print(io, ", no unwrapped positions") :
    print(io, ", unwrapped_positions ", tracers.unwrapped_positions)
  print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", tracers::Tracers)
  row(name, value) = print(io, "\n  ", rpad(name, 22), value)
  print(io, "Tracers")
  row("positions", tracers.positions)
  row("interpolation_scheme", tracers.interpolation_scheme)
  row("unwrapped_positions", something(tracers.unwrapped_positions, "nothing (no unwrapped positions)"))
end

Base.show(io::IO, traversal::ParticleTraversal) =
  print(io, "ParticleTraversal(", traversal.order, traversal.automatic ? ", automatic" : ", manual", ")")

Base.show(io::IO, buffers::ParticleIntegratorBuffers) =
  print(io, "ParticleIntegratorBuffers(", buffers.predictor_points,
        isempty(buffers.weights) ? ", one-step" : ", order $(length(buffers.weights))", ")")



# ————————————————————————————————————————————————————————————————————————————————————————————————
# HDF5 persistence. The bare generics live here so the docstrings and the docs build work without
# HDF5 in the environment; the methods live in the `GBGHomogeneousTurbulenceHDF5Ext` weak-dependency
# extension, loaded automatically alongside the HDF5 package (the arrangement the field library's
# persistence pairs established).

export write_tracers, read_tracers


"""
    write_tracers(parent::HDF5.H5DataStore, name::AbstractString, tracers::Tracers)

Write the [`Tracers`](@ref) `tracers` under `parent` as one self-describing HDF5 group — the
wrapped positions, the unwrapped positions when tracked, and the interpolation scheme, each
persisted through `GBGPeriodicFields`' own pairs. Available once the `HDF5` package is loaded; the
caller owns the file.

# Arguments
- `parent` — the open HDF5 file or group to write under.
- `name` — the created group's name.
- `tracers` — the tracer set to record.

Returns the created group. Reload with [`read_tracers`](@ref).
"""
function write_tracers end


"""
    read_tracers(parent::HDF5.H5DataStore, name::AbstractString,
                 domain::FixedDomain) -> Tracers

Rebuild a [`Tracers`](@ref) from the group [`write_tracers`](@ref) wrote, its positions allocated
on the storage backend of `domain` (a [`FixedDomain`](@ref)), whose element type must agree with
the file or the read is refused with an `ArgumentError`, as is a group not written by
`write_tracers`. Available once the `HDF5` package is loaded.

# Arguments
- `parent` — the open HDF5 file or group holding the tracer group.
- `name` — the group's name.
- `domain` — the `FixedDomain` whose backend the rebuilt set lives on.
"""
function read_tracers end


end # module Particles
