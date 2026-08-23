# Particles — Lagrangian tracer tracking. Tracers are advected by the velocity through the package's
# grid→point interpolation (a selectable `GBGPeriodicFields` spline scheme; `CatmullRom` by default,
# `LalescuSpline`/`LagrangeSpline` for higher order), and any physical field can be sampled along the
# trajectories; accumulating statistics over them is the caller's analysis, not this package's.
#
# Trajectory time integration is pluggable, exactly as the field side is: the scheme is an
# `AbstractParticleIntegrator` and its per-step registers are allocated per scheme by
# `allocate_buffers`, so the tracer set holds only trajectory STATE and never one scheme's scratch.
# `EndpointHeun` is the one scheme today — second-order, on the velocity at the start and end of the
# step (tₙ and tₙ₊₁), unlike advecting on the frozen start-of-step velocity (effectively first
# order). Its two velocity fields are exactly what the field solver already produces each step, so
# the tracer advance stays decoupled from the field Runge–Kutta internals. A higher-order scheme would
# want different registers (RK4 several stage velocities; a multistep scheme a velocity HISTORY and
# no predictor at all) — which is precisely why they are not in `Tracers`.

"""
    Particles

Lagrangian particle tracking — today the massless tracer:

- [`Tracers`](@ref) — the tracer set (positions and a selectable `interpolation_scheme`);
  [`particle_positions`](@ref) and [`number_of_particles`](@ref) read its state. The trajectory
  velocities are read from the run's observables cache through
  [`particle_velocities`](@ref GBGIsotropicTurbulence.Cache.particle_velocities).
- [`AbstractParticleIntegrator`](@ref) — the trajectory time-integration schemes,
  [`EndpointHeun`](@ref) and [`AdamsBashforth`](@ref); [`ParticleIntegratorBuffers`](@ref) and
  [`MultistepBuffers`](@ref) the per-step storage each needs, and [`history_depth`](@ref) the
  sample-history length a scheme requires.
- [`record_particle_velocities!`](@ref) — store the flow velocity at the tracers' current positions,
  which is both the measured Lagrangian sample and the first velocity the next advance needs.
- [`advect!`](@ref) — advance the trajectories one step under the chosen scheme;
  [`restart!`](@ref) discards a scheme's history after an out-of-band reposition.
- [`interpolate_at_particles!`](@ref) — read a field along the trajectories; [`new_vector_point_values`](@ref) /
  [`new_scalar_point_values`](@ref) allocate its `out` buffers.
"""
module Particles

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, _reference, _real_type
# One generic builds the per-scheme registers on both sides of the run — the field scheme's and
# the trajectory scheme's — because it is one concept: allocate exactly what this scheme needs.
import ..Propagator: allocate_buffers

export Tracers, AbstractParticleIntegrator, EndpointHeun, AdamsBashforth,
       ParticleIntegratorBuffers, MultistepBuffers,
       record_particle_velocities!, advect!, restart!, history_depth, interpolate_at_particles!,
       particle_positions, number_of_particles, new_vector_point_values, new_scalar_point_values


"""
    Tracers(domain; number_of_particles, interpolation_scheme, rng = default_rng())
    Tracers(domain; positions, interpolation_scheme)

(One method, shown as the two ways it is called — keywords do not dispatch.)

A set of Lagrangian tracers, built on `domain`'s backend and element type.

Give **exactly one** of `number_of_particles`, which seeds that many tracers uniformly at random in
the periodic box, or `positions`, an `(M, 3)` array of tracer positions to wrap (the columns being
the ``x, y, z`` components), converted to `domain`'s backend and element type. Supplying both, or
neither, raises an `ArgumentError`.

The `interpolation_scheme` is the `GBGPeriodicFields` scheme used to evaluate the velocity — and any
sampled field — at the tracer positions.
[`CatmullRom`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.CatmullRom) is the ``C^1``
choice and the front door's default; it is a ready-made value rather than a type, so it is passed
bare. [`LalescuSpline(n, m)`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.LalescuSpline)
and [`LagrangeSpline(n)`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.LagrangeSpline)
offer higher smoothness or interpolation order at a wider stencil — useful for derivative-sensitive
readouts such as acceleration statistics — with `n` (and, for `LalescuSpline`, `m`) the stencil and
smoothness parameters.

# Arguments

- `domain` — the [`FixedDomain`](@ref) whose backend, element type and box the set is built on.
- `number_of_particles` — seed this many tracers uniformly at random in the box.
- `positions` — or wrap this `(M, 3)` array instead; give exactly one of the two.
- `interpolation_scheme` — the scheme used to evaluate a field at the tracer positions.
- `rng` — the random stream seeding the positions (used with `number_of_particles`, ignored with
  `positions`); defaults to `Random.default_rng()`.

# Examples

A run carries tracers when the front door is given a count;
[`advance!`](@ref GBGIsotropicTurbulence.SimulationRun.advance!) then advances them with the
fields and records the Lagrangian velocity each iteration, so both reads below are current between
iterations:

```julia
sim = Simulation(grid_points_per_axis = 64, number_of_particles = 4096, scalar = true)
advance!(sim)

X = particle_positions(sim.tracers)         # the (M, 3) positions at this instant
v = particle_velocities(sim.cache)          # u(tₙ, X(tₙ)), the Lagrangian velocity — a checked read

out = new_scalar_point_values(sim.tracers)  # allocate once, then reuse every iteration
interpolate_at_particles!(out, scalar_physical(sim.cache), sim.tracers)
```

Building a set directly — to place tracers deliberately rather than at random, and to advance them
by hand — takes the `positions` form, and then the scheme's per-step storage is yours to allocate:

```julia
tracers = Tracers(domain; positions = [0.1 0.2 0.3; 1.0 1.0 1.0], interpolation_scheme = CatmullRom)
buffers = allocate_buffers(EndpointHeun(), tracers)

record_particle_velocities!(tracers, u)     # u(tₙ) at the current positions — do this first
advect!(EndpointHeun(), tracers, u_end, domain, buffers, dt)
```

Read the particle state with [`particle_positions`](@ref) and [`number_of_particles`](@ref), both of
which read the tracer set directly. The velocities are the exception, and deliberately so: they are a
*deposited observable* rather than tracer state, so they are read from the run's observables cache
through
[`particle_velocities`](@ref GBGIsotropicTurbulence.Cache.particle_velocities), where the
iteration's
closing deposit leaves them.

The trajectory scheme's own working storage is **not** here: it lives in a
[`ParticleIntegratorBuffers`](@ref), whose docstring explains the split.

# Fields
- `positions` — the `(M, 3)` tracer positions (read with `particle_positions`).
- `position_points` — a
  [`PointSet`](@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet) wrapping `positions`: the
  same coordinates in the form `GBGPeriodicFields`' interpolation takes, which is why both exist.
- `particle_velocities` — the interpolated velocity at the positions the tracers occupy, at the
  instant they occupy them: the genuine Lagrangian sample. This array **is** the observables cache's
  particle-velocities slot, the same storage under two names, so it carries that slot's rules —
  read it through
  `particle_velocities`, which serves it only when current, and treat it as read-only, since the tracer advance writes here mid-iteration.
- `interpolation_scheme` — the scheme used to evaluate a field at the tracer positions.
"""
struct Tracers{P, PSX, VV, S}
  positions::P              # (M, 3)
  position_points::PSX      # PointSet wrapping `positions`
  particle_velocities::VV   # VectorPointValues: u at the occupied positions — the Lagrangian sample
  interpolation_scheme::S
end


# The two forms are ONE method, not two: they are distinguished by which keyword is supplied, and
# Julia dispatches on positional arguments only. Hence the explicit either/or check, which also gives
# a better error than a missing-keyword one would.
function Tracers(domain::FixedDomain; interpolation_scheme, positions = nothing,
                 number_of_particles = nothing, rng = Random.default_rng())
  count(!isnothing, (positions, number_of_particles)) == 1 ||
    throw(ArgumentError("give exactly one of `positions` (an (M, 3) array to wrap) or " *
                        "`number_of_particles` (a count to seed at random)"))
  T = _real_type(domain)
  if isnothing(positions)
    M = Int(number_of_particles)
    positions = similar(_reference(domain), T, (M, 3))
    copyto!(positions, T(domain.grid.domain_size[1]) .* rand(rng, T, M, 3))
    pos = positions
  else
    size(positions, 2) == 3 ||
      throw(DimensionMismatch("tracer positions must have shape (M, 3); got $(size(positions))"))
    pos = similar(_reference(domain), T, size(positions))   # the domain's backend + element type
    copyto!(pos, positions)
  end
  return Tracers(pos, PointSet(pos), VectorPointValues(similar(pos)), interpolation_scheme)
end


"""
    AbstractParticleIntegrator

The supertype of the trajectory time-integration schemes — how the tracer positions are advanced
over one step, the Lagrangian counterpart of the field side's
[`AbstractIntegrator`](@ref GBGIsotropicTurbulence.Propagator.AbstractIntegrator). A scheme is a
value (`EndpointHeun()`), passed to [`advect!`](@ref) and to
[`allocate_buffers`](@ref GBGIsotropicTurbulence.Propagator.allocate_buffers), which builds exactly
the working storage that scheme needs.

Two members today: [`EndpointHeun`](@ref), a one-step method that buys second order with a second
interpolation, and [`AdamsBashforth`](@ref), a multistep method that buys more by reusing the
Lagrangian samples the run already deposits. Which trade a run wants is a fitness question — one
interpolation per step against one stored array per extra order.
"""
abstract type AbstractParticleIntegrator end


"""
    EndpointHeun()

Second-order Heun-in-time on the velocity at the two **ends** of the step — the trajectory
scheme a run uses by default. It advances the positions with the start-of-step Lagrangian
velocity that [`record_particle_velocities!`](@ref) stored and the end-of-step velocity field
the solver has just produced, so it needs nothing from inside the field scheme's stages.

It needs one set of predicted positions and the velocity interpolated there
([`ParticleIntegratorBuffers`](@ref)); the formula is given with [`advect!`](@ref).

!!! note "Pair it with the default interpolant unless the grid is coarse"
    Under the advective-CFL loop ``\\Delta t \\propto \\Delta x``, so this scheme's error falls as
    ``\\Delta x^{2}`` while a degree-``d`` interpolant's trajectory floor falls as
    ``\\Delta x^{d+1}``. For the default
    [`CatmullRom`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.CatmullRom) (degree 2)
    the floor therefore falls *faster* than the time error, and the two cross over: measured on a
    band-limited field, interpolation dominates at ``N = 16{-}32`` and the time error dominates from
    ``N \\approx 64`` on (at ``N = 128``, floor ``1\\times10^{-5}`` against time error
    ``6\\times10^{-5}`` — setup-specific numbers; only the ``\\Delta x^{d+1}`` trend generalizes). So at production resolutions `CatmullRom` is not what limits a Heun
    trajectory and a wider stencil buys nothing; at coarse resolution, or with ``\\Delta t`` cut well
    below the CFL value, `LalescuSpline(3, 1)` — same ``C^1``, degree 3 — moves the floor down by
    more than an order of magnitude. What governs this in a run is how well the grid resolves the
    dissipation scale, so read ``N`` here as a stand-in for ``\\kappa_{\\max}\\eta``.
"""
struct EndpointHeun <: AbstractParticleIntegrator end


# Periodic wrap into the half-open box [0, L). `mod` alone does NOT deliver that in floating point:
# for a position a hair below zero the exact quotient rounds to give back exactly `L` (measured:
# `mod(-1e-20, 2π) === 2π`), so a tracer that drifts marginally out of the box lands on the excluded
# endpoint and any consumer that buckets by `floor(x/Δx)` indexes one past the last cell. The second
# pass folds that endpoint back to 0, which is the same point of the periodic box.
function _wrap!(X, L)
  X .= mod.(X, L)
  # Fold ONLY the excluded endpoint. An `X .< L` test would also catch NaN and Inf — for which `<` is
  # false — and quietly rewrite them to 0.0, turning a diverged trajectory into tidy in-box positions
  # and destroying the one signal that a run has blown up. `mod` cannot return anything above `L`, so
  # equality is the whole of the correction.
  X .= ifelse.(X .== L, zero(eltype(X)), X)
  return X
end


"""
    restart!(scheme, buffers) -> buffers

Discard whatever history `buffers` holds, so the next [`advect!`](@ref) starts the scheme from
scratch.

Call it whenever the tracer positions are changed from outside the iteration — a reseed, a
hand-written correction, any direct write to the tracer storage. A one-step scheme carries no
history and this does nothing; a multistep scheme carries Lagrangian samples taken along the
trajectory just abandoned, and integrating over those would blend the old path with the new one.

The `Simulation` form of
[`particles_modified!`](@ref GBGIsotropicTurbulence.Cache.particles_modified!) calls this for you,
after announcing the reposition to the observables cache. Its bare-cache form clears only the
sample history the cache itself holds and cannot dispatch here — so a hand-run loop that announces
to the cache alone must also call this; a scheme's registers beyond that history are reached only
this way.
"""
function restart! end


"""
    ParticleIntegratorBuffers

The per-step storage a trajectory scheme computes in, sized to a tracer set and allocated once,
so advancing the tracers allocates nothing. Build it with
[`allocate_buffers`](@ref GBGIsotropicTurbulence.Propagator.allocate_buffers)`(scheme, tracers)`,
which allocates exactly what `scheme` needs and nothing more; a run builds it for you.

This storage belongs to the scheme, not to the trajectory: a different scheme wants a different
set — a multistep scheme wants a velocity history and no predicted positions at all — which is why it
lives here rather than in [`Tracers`](@ref).

# Fields
- `predictor` — the `(M, 3)` predicted positions, which no tracer ever occupies.
- `predictor_points` — a
  [`PointSet`](@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet) wrapping `predictor`.
- `velocity_predictor` — the velocity interpolated at the predicted positions (the particle-side
  counterpart of the field schemes' `velocity_predictor_spectral`). It is reachable like
  any field of this type, but it is a scheme intermediate rather than a sample of the flow at any
  instant, so nothing in the package offers it as one: read
  [`particle_velocities`](@ref GBGIsotropicTurbulence.Cache.particle_velocities) for the Lagrangian
  sample.
"""
struct ParticleIntegratorBuffers{P, PS, VV}
  predictor::P
  predictor_points::PS
  velocity_predictor::VV
end


function allocate_buffers(::EndpointHeun, tracers::Tracers)
  predictor = similar(tracers.positions)
  return ParticleIntegratorBuffers(predictor, PointSet(predictor),
                                   VectorPointValues(similar(predictor)))
end


# A one-step scheme is memoryless: every register it owns is overwritten before it is read.
restart!(::EndpointHeun, buffers::ParticleIntegratorBuffers) = buffers


"""
    AdamsBashforth(; order = 4)

Variable-step Adams–Bashforth trajectory integration — the scheme TurTLE uses for its tracers, at
its default order (Lalescu et al. 2022, *An efficient particle tracking algorithm for large-scale
parallel pseudo-spectral simulations of turbulence*, *Comput. Phys. Commun.* **278**, 108406,
[doi:10.1016/j.cpc.2022.108406](https://doi.org/10.1016/j.cpc.2022.108406)) — buying accuracy in
time at **no extra field evaluation and no extra interpolation** per step.

Use it in place of [`EndpointHeun`](@ref) when trajectory accuracy in time limits a measurement. Heun
buys its second order by interpolating a second time, at predicted positions; Adams–Bashforth instead
reuses the Lagrangian samples the run has already deposited at earlier instants. The trade is one
stored array per extra order against one interpolation per step.

The steps are **not** assumed uniform: the advective-CFL loop changes ``\\Delta t`` every iteration,
which classical fixed-step coefficients would silently get wrong, so the weights are recomputed each
step from the actual step history. That is ``\\mathcal{O}(\\texttt{order}^2)`` host arithmetic per
step, independent of the tracer count.

A multistep method has no history at ``t_0``, so the first `order - 1` steps are taken with
`EndpointHeun` and the scheme then switches over; the same restart happens if the tracers are
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
  since an Adams–Bashforth stability region shrinks with each step added.

!!! warning "The interpolant sets a floor no timestep can cross"
    Interpolating the velocity perturbs the field the tracers follow, and that perturbation does not
    shrink with ``\\Delta t``: for a perturbation of size ``\\delta`` and a flow with Lipschitz
    constant ``K`` over a span ``t``, Grönwall bounds the trajectory error by
    ``\\delta(\\mathrm{e}^{Kt} - 1)/K`` however the time integration is done. Refining the step, or raising `order`, pays only until the time error reaches that floor.

    The floor is set by the interpolant's **polynomial reproduction degree**, not its smoothness
    class — measured here, raising the degree at fixed ``C^1`` lowered it fifty-fold, while varying
    the smoothness at fixed degree left the time convergence unchanged. Raise the degree when the
    floor is what limits you; smoothness buys something different, namely readouts that
    *differentiate* the interpolant, such as acceleration (Lalescu, Teaca & Carati 2010,
    [doi:10.1016/j.jcp.2010.04.006](https://doi.org/10.1016/j.jcp.2010.04.006)).

# Fields
The plain constructor `AdamsBashforth(order)` takes the one field directly:
- `order` — the target method order; the scheme ramps to it as the sample history fills.
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


"""
    MultistepBuffers

The per-scheme registers of an [`AdamsBashforth`](@ref) trajectory integrator: the startup scheme's
registers, the host scratch its weight solve works in, and the cache it reads its past Lagrangian
samples from.

Build it with [`allocate_buffers`](@ref GBGIsotropicTurbulence.Propagator.allocate_buffers)`(scheme,
tracers, cache)`; a run builds it for you.

The past samples themselves are **not** held here. They are deposited observables — measurements of
the velocity along the trajectory — so they live in the
[`ObservablesCache`](@ref GBGIsotropicTurbulence.Cache.ObservablesCache) beside the current sample
they extend, which is what lets
[`particles_modified!`](@ref GBGIsotropicTurbulence.Cache.particles_modified!) invalidate the whole
history when the tracers are repositioned.

# Fields
- `cache` — the `ObservablesCache` holding the sample history this scheme integrates over.
- `startup` — the [`ParticleIntegratorBuffers`](@ref) the bootstrap `EndpointHeun` steps use.
- `weights`, `nodes` — the `order`-element host scratch the per-step weight solve works in.
"""
struct MultistepBuffers{C, S}
  cache::C
  startup::S
  # Host scratch for the weight solve. Two `order`-element vectors, allocated once: the solve runs
  # every warmed-up step, and the hot loop is allocation-free over preallocated buffers.
  weights::Vector{Float64}
  nodes::Vector{Float64}
end


function allocate_buffers(::AdamsBashforth{K}, tracers::Tracers, cache) where {K}
  # The history is the cache's, so a cache built for a shallower scheme would leave this one reading
  # fewer past samples than its order claims — a silently lower-order integration.
  length(cache.particle_velocity_history) >= K - 1 ||
    throw(ArgumentError("this cache carries $(length(cache.particle_velocity_history)) past " *
                        "sample(s), but `AdamsBashforth(order = $K)` integrates over $(K - 1); " *
                        "build the cache with `history_depth = $K`"))
  return MultistepBuffers(cache, allocate_buffers(EndpointHeun(), tracers),
                          zeros(Float64, K), zeros(Float64, K))
end


# A one-step scheme carries no history and ignores the cache; the three-argument form exists so a run
# can allocate either scheme's registers through one call.
allocate_buffers(scheme::EndpointHeun, tracers::Tracers, cache) = allocate_buffers(scheme, tracers)


"""
    history_depth(scheme) -> Int

How many Lagrangian samples `scheme` must be able to look back over, counting the current one.

A run reads this to size the sample history its
[`ObservablesCache`](@ref GBGIsotropicTurbulence.Cache.ObservablesCache) carries. A one-step scheme
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
                 buffers::MultistepBuffers, dt::Real) where {K}
  T = real(eltype(tracers.positions))
  L = T(domain.grid.domain_size[1])
  X = tracers.positions
  f0 = point_values(tracers.particle_velocities)

  # A non-positive step would enter the history as a repeated (or reversed) node, and the Lagrange
  # basis divides by the node differences — so the next warmed-up step divides by zero and returns
  # NaN positions. Refused here, where the history is written, rather than left to surface as a
  # silently ruined trajectory some steps later.
  dt > 0 || throw(ArgumentError("`dt` must be positive, got $dt: a multistep history cannot carry " *
                                "a zero-length or reversed step"))

  # The past samples are the cache's, not this scheme's: an announced reposition clears them there,
  # so a history that survived one is not reachable from here.
  cache = buffers.cache
  past, steps = cache.particle_velocity_history, cache.sample_steps
  # The history's depth IS the order this call will actually achieve. Handed buffers built for a
  # shallower scheme, the loop below would read fewer past samples than `K` claims and integrate at
  # a lower order without saying so.
  length(past) == K - 1 ||
    throw(ArgumentError("this `AdamsBashforth(order = $K)` integrates over $(K - 1) past sample(s), " *
                        "but the buffers it was handed carry $(length(past)): they were built for a " *
                        "different order. Equality, not sufficiency — the shared history's fill " *
                        "level is capped against the order of whichever call last advanced it, so " *
                        "mixing two orders over one history corrupts the bookkeeping in both."))

  if cache.history_filled < K - 1            # no history yet: start up on the one-step scheme
    advect!(EndpointHeun(), tracers, velocity_end, domain, buffers.startup, dt)
  else
    b = _adams_bashforth_weights(buffers.weights, buffers.nodes, Float64(dt), steps, K)
    X .= X .+ T(b[1]) .* f0
    for j in 2:K
      X .= X .+ T(b[j]) .* point_values(past[j-1])
    end
    _wrap!(X, L)
  end

  # Shift the history: the sample just used at t_n becomes the most recent past sample. The copy is
  # what keeps the deposited observable intact — the current slot is the tracer set's own storage and
  # is rewritten every iteration, so a multistep method that aliased it would integrate over values
  # that have since been overwritten.
  for j in min(cache.history_filled + 1, K - 1):-1:2
    copyto!(point_values(past[j]), point_values(past[j-1]))
    steps[j] = steps[j-1]
  end
  if K > 1
    copyto!(point_values(past[1]), f0)
    steps[1] = Float64(dt)
    cache.history_filled = min(cache.history_filled + 1, K - 1)
  end
  return tracers
end


restart!(::AdamsBashforth, buffers::MultistepBuffers) = (buffers.cache.history_filled = 0; buffers)


"""
    record_particle_velocities!(tracers, u) -> tracers

Store the Lagrangian velocity ``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))`` — the flow velocity seen by
each tracer where it currently sits — by interpolating the velocity field `u` (physical
representation) onto the positions of the tracer set `tracers`, with the set's interpolation scheme.

The values go into the tracer set's own `particle_velocities` storage, which is also the observables
cache's particle-velocities slot. **This call is that slot's only producer of values**, but it writes
values only: the slot stays stale, and reads of it throw, until
[`deposit_sample!`](@ref GBGIsotropicTurbulence.Cache.deposit_sample!) records them as current.
Interpolate here, then mark current there — a run does both at the end of each iteration, on the just-deposited velocity at
the just-advanced positions, and reading
[`particle_velocities`](@ref GBGIsotropicTurbulence.Cache.particle_velocities) after only the first
throws.

The stored values serve twice: they are the genuine Lagrangian velocity a caller accumulates, and they
are the start-of-step velocity ``\\boldsymbol{v}_1`` the next [`advect!`](@ref) needs — which is why
an [`EndpointHeun`](@ref) advance never interpolates at ``t_n`` itself. Storing them costs
``M\\times3`` values for ``M`` tracers, where keeping the velocity field would cost
``N^{3} \\times 3``.
"""
function record_particle_velocities!(tracers::Tracers, u)
  interpolate!(tracers.particle_velocities, u, tracers.position_points, tracers.interpolation_scheme)
  return tracers
end


"""
    advect!(scheme, tracers, velocity_end, domain, buffers, dt) -> tracers

Advance the positions of the tracer set `tracers` by one step of size `dt` (written ``\\Delta t``
below), in place, under the trajectory scheme `scheme` (an
[`AbstractParticleIntegrator`](@ref)), using its working storage `buffers` (the
registers [`allocate_buffers`](@ref GBGIsotropicTurbulence.Propagator.allocate_buffers) builds for
that scheme — `ParticleIntegratorBuffers` or [`MultistepBuffers`](@ref)). The `domain` (a [`FixedDomain`](@ref))
supplies the box side the positions are wrapped into.

Under [`EndpointHeun`](@ref), the scheme is Heun-in-time on the velocity at the two ends of the
step — the start-of-step values that [`record_particle_velocities!`](@ref) stored, and
`velocity_end`, the end-of-step velocity field ``\\boldsymbol{u}(t_{n+1})`` in physical
representation:

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

!!! note "The start-of-step velocity is read, never recomputed"
    ``\\boldsymbol{v}_1`` is read from the tracer set, not recomputed here: it must hold
    ``\\boldsymbol{u}(t_n, \\boldsymbol{X}(t_n))``, recorded by `record_particle_velocities!`
    at the previous iteration's end. In a run the observables cache records that sample at its epoch
    and the run layer reads it checked before each advance; a hand-run loop must call
    `record_particle_velocities!` itself between advances.
"""
function advect! end

function advect!(::EndpointHeun, tracers::Tracers, velocity_end, domain::FixedDomain,
                 buffers::ParticleIntegratorBuffers, dt::Real)
  L = real(eltype(tracers.positions))(domain.grid.domain_size[1])
  Δt = real(eltype(tracers.positions))(dt)
  X = tracers.positions
  Xstar = buffers.predictor

  v1 = point_values(tracers.particle_velocities)
  Xstar .= X .+ Δt .* v1
  _wrap!(Xstar, L)
  # v₂ is evaluated at the PREDICTOR positions and is a stage register, never deposited particle velocities —
  # and it must never be reused as the next step's v₁: the two differ only at O(Δt²), but that reuse
  # would corrupt the recorded observable the Lagrangian statistics accumulate (never approximate
  # the thing you measure).
  interpolate!(buffers.velocity_predictor, velocity_end, buffers.predictor_points, tracers.interpolation_scheme)
  v2 = point_values(buffers.velocity_predictor)
  X .= X .+ (Δt / 2) .* (v1 .+ v2)
  _wrap!(X, L)
  return tracers
end


"""
    interpolate_at_particles!(out, field, tracers) -> out

Sample the physical `field` at the current tracer positions into the point-value buffer `out` (a
[`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) for the
velocity, a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues)
for the scalar ``\\varphi``), using the interpolation scheme of the tracer set `tracers`. This is how
a field is gathered along the trajectories; what is then accumulated over those values is the
caller's own analysis.
"""
function interpolate_at_particles!(out, field, tracers::Tracers)
  interpolate!(out, field, tracers.position_points, tracers.interpolation_scheme)
  return out
end


"""
    particle_positions(tracers)

The `(M, 3)` array of current tracer positions — the probes' own state, read off the tracer set
`tracers`.
"""
particle_positions(tracers::Tracers) = tracers.positions


"""
    number_of_particles(tracers)

The number of tracers ``M`` in the tracer set `tracers`.
"""
number_of_particles(tracers::Tracers) = size(tracers.positions, 1)


"""
    new_vector_point_values(tracers)

Allocate a [`VectorPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.VectorPointValues) of
shape `(M, 3)` matching the tracer set `tracers`, for use as the `out` of
[`interpolate_at_particles!`](@ref) when sampling the velocity along the trajectories.
"""
new_vector_point_values(tracers::Tracers) = VectorPointValues(similar(tracers.positions))

"""
    new_scalar_point_values(tracers)

Allocate a [`ScalarPointValues`](@extref GBGPeriodicFields GBGPeriodicFields.Points.ScalarPointValues) of
length ``M`` matching the tracer set `tracers`, for use as the `out` of
[`interpolate_at_particles!`](@ref) when sampling the scalar ``\\varphi`` along the trajectories.
"""
new_scalar_point_values(tracers::Tracers) =
  ScalarPointValues(similar(tracers.positions, eltype(tracers.positions), number_of_particles(tracers)))


end # module Particles
