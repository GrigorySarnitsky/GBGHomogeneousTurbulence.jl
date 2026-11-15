# ParticlePropagator — the map that advances the tracer positions in time. The schemes are the Adams
# family: a step integrates the polynomial through the last few samples of the velocity at the
# particles (`AB`), and may then correct the result with one more sample taken at the positions it
# predicted (`ABM`, of which `Heun` is the one-step member). The samples are the trail the
# observables cache keeps, so a scheme owns no storage at the particles' scale: the positions are
# advanced in place, and the velocity at the predicted positions is written into the trail slot the
# closing deposit is about to fill.
#
# The step needs only the velocity field at the end of the step, which the field solver has just
# deposited, so the tracer advance stays decoupled from the field Runge–Kutta internals.

"""
    ParticlePropagator

It advances Lagrangian particles in time:

- [`AbstractParticleIntegrator`](@ref) — the particle integration schemes: [`Heun`](@ref),
  [`ABM`](@ref) and [`AB`](@ref).
- [`advect!`](@ref) — advance the trajectories one step under the chosen scheme.
- [`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!) — this module adds the particle
  method: interpolate the flow velocity at the tracers' new positions and add it, with its time, to
  the trail the observables cache keeps. One value has two consumers: the Lagrangian statistics a
  caller accumulates, and the next advance, which integrates over it.

The particles themselves, and what is measured at them, are in
[`Particles`](@ref GBGHomogeneousTurbulence.Particles).
"""
module ParticlePropagator

using GBGPeriodicFields
using ..SimulationDomain: FixedDomain
using ..Particles: Tracers, ParticleTrail, _order
import ..Particles: trail_capacity
using ..Cache: ObservablesCache, velocity_physical, trail_for_particle_step,
               take_velocity_at_particles!, deposit_velocity_at_particles!,
               advance_particles_epoch!, _particle_trail
# One generic closes an advance on both sides of the run — the field step's and the particle
# step's — because it is one concept: deposit what the advance has just made measurable.
import ..Propagator: deposit!

export AbstractParticleIntegrator, Heun, ABM, AB, advect!


"""
    AbstractParticleIntegrator

The supertype of the particle integration schemes — how the tracer positions are advanced
over one step, the Lagrangian counterpart of the field side's
[`AbstractIntegrator`](@ref GBGHomogeneousTurbulence.Propagator.AbstractIntegrator). A scheme is a
value (`Heun()`, `ABM(4)`), given to a run as the `particle_integration_scheme` of its
[`ParticleTracking`](@ref GBGHomogeneousTurbulence.SimulationRun.ParticleTracking) and passed to
[`advect!`](@ref).

The family has two branches: [`AB`](@ref), which reuses the Lagrangian samples the run already
deposits and interpolates once per step, and [`ABM`](@ref), which interpolates a second time to
correct the step, with [`Heun`](@ref) its one-step member. Which trade a run wants is for its user
to measure — one interpolation per step against a smaller error at equal order.
"""
abstract type AbstractParticleIntegrator end


"""
    ABM(k)

The ``k``-step Adams–Bashforth–Moulton predictor–corrector for the tracer positions, of order
``k + 1``: an [`AB`](@ref) step over ``k`` samples predicts the positions, the velocity is
interpolated there, and the ``k``-step Adams–Moulton formula corrects the step with it. The
argument `k` counts the samples the predictor integrates over, from `1` to `7`, so the order is one
more than the number in the name, and `ABM(1)` is [`Heun`](@ref). The limit keeps the order at 8 or
below, beyond which the quadrature that computes the weights is no longer exact.

Writing ``\\boldsymbol{f}_{n-j} = \\boldsymbol{u}(t_{n-j}, \\boldsymbol{X}(t_{n-j}))`` for the
deposited samples of the velocity at the particles, one step of [`advect!`](@ref) is

```math
\\begin{aligned}
\\boldsymbol{X}^{*} &= \\boldsymbol{X} + \\sum_{j=0}^{k-1} b_j \\boldsymbol{f}_{n-j}, &
\\boldsymbol{f}^{*} &= \\boldsymbol{u}(t_{n+1}, \\boldsymbol{X}^{*}), \\\\
\\boldsymbol{X} &\\leftarrow \\boldsymbol{X} + \\beta^{*} \\boldsymbol{f}^{*}
  + \\sum_{j=0}^{k-1} \\beta_j \\boldsymbol{f}_{n-j},
\\end{aligned}
```

with positions wrapped into the box. The weights ``b_j`` integrate, over the step, the polynomial
through the ``k`` samples, and ``\\beta^{*}``, ``\\beta_j`` the polynomial through those and
``\\boldsymbol{f}^{*}``. They are recomputed every step from the samples' actual times, because the
run's timestep changes from one iteration to the next.

Against `AB(k + 1)`, which has the same order and keeps the same number of samples, this scheme
interpolates twice per step and makes a smaller error.

The run's trail of the velocity at the particles
([`velocity_at_particles_trail`](@ref GBGHomogeneousTurbulence.Cache.velocity_at_particles_trail))
keeps ``k + 1`` samples under this scheme. The scheme has no samples to work from at the start, so
the first ``k - 1`` steps are taken with `ABM(1)`, …, `ABM(k - 1)`. Those lower-order steps leave
an error of third order behind, and every step between the trail's samples is a full one after
``2k - 1`` iterations: a measurement that needs the full accuracy either discards those iterations or sets
`shortened_first_steps` on
[`ParticleTracking`](@ref GBGHomogeneousTurbulence.SimulationRun.ParticleTracking).

# Fields
The scheme stores no fields: `k` is carried as a type parameter.
"""
struct ABM{k} <: AbstractParticleIntegrator
  function ABM{k}() where {k}
    (k isa Int && 1 <= k <= 7) ||
      throw(ArgumentError("`ABM(k)` takes a number of steps `k` from 1 to 7, got $k: the " *
                          "four-point Gauss–Legendre rule that integrates the weights is exact " *
                          "only through the degree `k = 7` needs, so a longer scheme would be " *
                          "given silently wrong coefficients"))
    return new{k}()
  end
end

ABM(k::Integer) = ABM{Int(k)}()


"""
    Heun()

Second-order Heun-in-time on the velocity at the two ends of the step — the particle
integration scheme a run uses by default, and the one-step member `ABM(1)` of the [`ABM`](@ref)
family. It advances the positions with the start-of-step Lagrangian
velocity the previous iteration's closing particle
[`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!) left in the cache and the
end-of-step velocity field the solver has just produced, so it needs nothing from inside the field
scheme's stages.

It keeps two samples of the velocity at the particles, the current one and the one before. One
step of [`advect!`](@ref) over ``\\Delta t`` is

```math
\\begin{aligned}
\\boldsymbol{v}_1 &= \\boldsymbol{u}(t_n, \\boldsymbol{X}), &
\\boldsymbol{X}^{*} &= \\boldsymbol{X} + \\Delta t \\boldsymbol{v}_1, \\\\
\\boldsymbol{v}_2 &= \\boldsymbol{u}(t_{n+1}, \\boldsymbol{X}^{*}), &
\\boldsymbol{X} &\\leftarrow \\boldsymbol{X} + \\tfrac{\\Delta t}{2}(\\boldsymbol{v}_1 + \\boldsymbol{v}_2),
\\end{aligned}
```

with positions wrapped into ``[0, L)``, ``L`` the box side.

!!! note "Pair it with the default interpolant unless the grid is coarse"
    Under the advective-CFL loop ``\\Delta t \\propto \\Delta x``, so this scheme's error falls as
    ``\\Delta x^{2}`` while a degree-``d`` interpolant's trajectory floor falls as
    ``\\Delta x^{d+1}``. For the default
    [`CatmullRom`](@extref GBGPeriodicFields GBGPeriodicFields.Interpolation.CatmullRom) (degree 2)
    the floor therefore falls *faster* than the time error, and the two cross over: measured on a
    band-limited field of ``N`` grid points per axis, interpolation dominates at ``N = 16{-}32``
    and the time error dominates from ``N \\approx 64`` on (at ``N = 128`` the floor is
    ``1\\times10^{-5}`` against a time error of ``6\\times10^{-5}``; the numbers are setup-specific,
    and only the ``\\Delta x^{d+1}`` trend generalizes).

    So at production resolutions `CatmullRom` is
    not what limits a Heun
    trajectory and a wider stencil buys nothing; at coarse resolution, or with ``\\Delta t`` cut well
    below the CFL value, `LalescuSpline(8; smoothness = 1)` — same ``C^1``, degree 3 — moves the floor down by
    more than an order of magnitude. What governs this in a run is how well the grid resolves the
    Kolmogorov length ``\\eta``, so read ``N`` here as a stand-in for ``\\kappa_{\\max}\\eta``, with
    ``\\kappa_{\\max}`` the largest resolved wavenumber.
"""
const Heun = ABM{1}


"""
    AB(k)

Variable-step Adams–Bashforth trajectory integration of order ``k`` — the scheme TurTLE uses for
its tracers, at ``k = 4`` (Lalescu et al. 2022) — buying accuracy in
time at no extra field evaluation and no extra interpolation per step. The argument `k` is the
number of samples used, from `1` to `8`, the order beyond which the quadrature that computes the
weights is no longer exact. `AB(1)` is forward Euler, which is first order and should not be used
for a run.

Where [`ABM`](@ref) interpolates a second time, at predicted positions, Adams–Bashforth
reuses the Lagrangian samples the run has already deposited at earlier instants and stops there.
One step of [`advect!`](@ref) is

```math
\\boldsymbol{X} \\leftarrow \\boldsymbol{X}
  + \\sum_{j=0}^{k-1} b_j \\boldsymbol{u}(t_{n-j}, \\boldsymbol{X}(t_{n-j})),
```

with the weights ``b_j`` re-solved each step by integrating, over the step, the polynomial through
the samples at their actual times. The steps are not assumed uniform: the run's timestep changes
every iteration, which classical fixed-step coefficients would silently get wrong.

The run's trail of the velocity at the particles
([`velocity_at_particles_trail`](@ref GBGHomogeneousTurbulence.Cache.velocity_at_particles_trail))
keeps ``k`` samples under this scheme. The scheme has no samples to work from at the start, so the
first ``k - 1`` steps are taken with `ABM(1)`, …, `ABM(k - 1)`. Those lower-order steps leave
an error of third order behind, and every step between the trail's samples is a full one after
``2k - 2`` iterations: a measurement that needs the full accuracy either discards those iterations or sets
`shortened_first_steps` on
[`ParticleTracking`](@ref GBGHomogeneousTurbulence.SimulationRun.ParticleTracking).

The interval of stability shrinks fast with ``k``. A displacement of the trajectory in a direction
the flow compresses at the rate ``\\lambda`` is damped only while ``\\lambda\\Delta t`` stays below
``0.30`` for `AB(4)`, ``0.088`` for `AB(6)` and ``0.024`` for `AB(8)`, and a region of intense
strain can exceed the last two at an ordinary timestep. The corrected scheme of the same order,
`ABM(k - 1)`, keeps ``1.9``, ``1.0`` and ``0.58``: above ``k = 4`` it is the one to use.

!!! warning "The interpolant sets a floor no timestep can cross"
    Interpolating the velocity perturbs the field the tracers follow, and that perturbation does not
    shrink with ``\\Delta t``: for a perturbation of size ``\\delta`` and a flow with Lipschitz
    constant ``\\Lambda`` over a span ``t``, Grönwall bounds the trajectory error by
    ``\\delta(\\mathrm{e}^{\\Lambda t} - 1)/\\Lambda`` however the time integration is done. Refining the step, or raising `k`, pays only until the time error reaches that floor.

    The floor is set by the interpolant's polynomial reproduction degree, not its smoothness
    class — measured here, raising the degree at fixed ``C^1`` lowered it fifty-fold, while varying
    the smoothness at fixed degree left the time convergence unchanged. Raise the degree when the
    floor is what limits you; smoothness buys something different, namely readouts that
    *differentiate* the interpolant, such as acceleration (Lalescu, Teaca & Carati 2010).

# References
- Lalescu, C. C., Bramas, B., Rampp, M. & Wilczek, M. (2022). [*An efficient particle tracking algorithm for large-scale parallel pseudo-spectral simulations of turbulence*](https://doi.org/10.1016/j.cpc.2022.108406). *Comput. Phys. Commun.* 278, 108406.
- Lalescu, C. C., Teaca, B. & Carati, D. (2010). [*Implementation of high order spline interpolations for tracking test particles in discretized fields*](https://doi.org/10.1016/j.jcp.2009.10.046). *J. Comput. Phys.* 229(17), 5862–5869.

# Fields
The scheme stores no fields: `k` is carried as a type parameter.
"""
struct AB{k} <: AbstractParticleIntegrator
  function AB{k}() where {k}
    (k isa Int && 1 <= k <= 8) ||
      throw(ArgumentError("`AB(k)` takes a number of steps `k` from 1 to 8, got $k: the " *
                          "four-point Gauss–Legendre rule that integrates the weights is exact " *
                          "only through degree 7, so a higher order would be given silently " *
                          "wrong coefficients"))
    return new{k}()
  end
end

AB(k::Integer) = AB{Int(k)}()


# What the run and the step ask of a scheme: how many samples its predictor integrates over,
# whether a full step corrects the prediction, and its order of accuracy.
_steps(::ABM{k}) where {k} = k
_steps(::AB{k}) where {k} = k
_corrects(::ABM) = true
_corrects(::AB) = false
_order_of_accuracy(::ABM{k}) where {k} = k + 1
_order_of_accuracy(::AB{k}) where {k} = k

# The trail keeps what the scheme has alive at once. `ABM(k)` corrects with the velocity at the
# predicted positions while it still reads all `k` samples, so it needs one slot more; between
# steps that slot holds one more real sample.
trail_capacity(::ABM{k}) where {k} = k + 1
trail_capacity(::AB{k}) where {k} = k


# The Adams weights on arbitrary nodes: with values f_j at times `nodes[j]` (relative to the start of
# the step), the integral over the step [0, h] of the polynomial through them is Σ_j w_j f_j, where
# w_j is the integral of the Lagrange basis L_j. Given the sample times alone these are the
# Adams–Bashforth weights; with the step's end `h` among the nodes, the Adams–Moulton ones.
# Four-point Gauss–Legendre integrates a basis of degree at most 7 exactly, hence at most 8 nodes,
# which is the bound the scheme constructors enforce. The whole computation is O(nodes²) host
# arithmetic per step, independent of the tracer count.
const _GAUSS_NODES = (-0.8611363115940526, -0.3399810435848563, 0.3399810435848563, 0.8611363115940526)
const _GAUSS_WEIGHTS = (0.3478548451374538, 0.6521451548625461, 0.6521451548625461, 0.3478548451374538)

function _adams_weights(nodes::NTuple{N, Float64}, h::Float64) where {N}
  return ntuple(Val(N)) do j
    weight = 0.0
    for (ξ, w) in zip(_GAUSS_NODES, _GAUSS_WEIGHTS)
      t = h * (ξ + 1) / 2                      # map [-1, 1] → [0, h]
      basis = 1.0
      for m in 1:N
        m == j && continue
        basis *= (t - nodes[m]) / (nodes[j] - nodes[m])
      end
      weight += w * h / 2 * basis
    end
    weight
  end
end


# One step over `h` from `J` samples of the trail, corrected or not. The positions are advanced in
# place: first to the prediction X*, then — when corrected — by the difference between the
# Adams–Moulton and the Adams–Bashforth sums, which is the same update written so that no second
# set of positions is needed. The unwrapped positions take the same terms through the grid-free
# form, so the two records share every displacement by construction.
function _advance_positions!(::Val{J}, corrected::Bool, tracers::Tracers, u, domain::FixedDomain,
                             cache::ObservablesCache, trail::ParticleTrail, h::Float64,
                             traversal) where {J}
  newest = trail[0]
  T = eltype(newest.value)
  samples = ntuple(i -> trail[1 - i].value, Val(J))
  nodes = ntuple(i -> trail[1 - i].time - newest.time, Val(J))    # 0, then negative
  b = _adams_weights(nodes, h)
  # ONE fused J-term displacement, wrap included (PF decision 73).
  prediction = ntuple(i -> (T(b[i]), samples[i]), Val(J))
  displace!(tracers.positions, domain.grid, prediction...)
  tracers.unwrapped_positions === nothing || displace!(tracers.unwrapped_positions, prediction...)
  corrected || return tracers
  # f* is evaluated at the PREDICTED positions and is a stage value, never a sample — and it must
  # never be kept as the next step's newest sample: the two differ only at second order in the step,
  # but that reuse would corrupt the recorded observable the Lagrangian statistics accumulate (never
  # approximate the thing you measure). It is written into the slot the closing deposit fills, which
  # no read reaches meanwhile. The traversal order built over the tracers serves this gather too:
  # the predicted positions sit one step's displacement from them, inside the tiles the order
  # groups, and the field library admits any same-length order.
  f★ = take_velocity_at_particles!(cache)
  interpolate!(f★, u, tracers.positions, tracers.interpolation_scheme; traversal = _order(traversal))
  β = _adams_weights((h, nodes...), h)
  correction = ((T(β[1]), f★), ntuple(i -> (T(β[i + 1] - b[i]), samples[i]), Val(J))...)
  displace!(tracers.positions, domain.grid, correction...)
  tracers.unwrapped_positions === nothing || displace!(tracers.unwrapped_positions, correction...)
  return tracers
end


"""
    advect!(scheme, tracers, domain, cache, dt; traversal = nothing) -> tracers

Advance the positions of a tracer set by one step, in place, under the particle integration
scheme `scheme`, whose docstring gives the update.

# Arguments
- `scheme` — the particle integration scheme, an [`AbstractParticleIntegrator`](@ref).
- `tracers` — the [`Tracers`](@ref GBGHomogeneousTurbulence.Particles.Tracers) whose positions advance.
- `domain` — the [`FixedDomain`](@ref), which supplies the box side the positions are wrapped into.
- `cache` — the run's [`ObservablesCache`](@ref GBGHomogeneousTurbulence.Cache.ObservablesCache). The
  step reads two things from it: the velocity field at the end of the step, which the field deposit
  has just left there, and the trail of the velocity at the particles, whose samples it integrates
  over.
- `dt` — the step size ``\\Delta t``, positive.
- `traversal = nothing` — a
  [`ParticleTraversal`](@ref GBGHomogeneousTurbulence.Particles.ParticleTraversal), to gather the
  velocity in its memory-locality order; `nothing` gathers in tracer order, with identical values.

The step refuses to run, with an `ErrorException`, unless the fields have taken exactly one step
past the tracer positions and the trail's newest sample was taken at those positions: otherwise it
would move the tracers with a velocity from the wrong time. A `dt` that is not positive and finite,
and a cache whose trail does not keep the number of samples `scheme` works from, are each an
`ArgumentError`. The step also advances the cache's particles
epoch, the version of the positions, so a read of the trail throws as stale until the particle
[`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!) closing the iteration adds the
sample at the new positions.

While the trail holds fewer samples than the scheme integrates over, the step is taken with the
lower member of the [`ABM`](@ref) family that the samples present allow.
"""
function advect!(scheme::AbstractParticleIntegrator, tracers::Tracers, domain::FixedDomain,
                 cache::ObservablesCache, dt::Real; traversal = nothing)
  # A non-positive step would put the new sample at a repeated or earlier time, and the weights
  # divide by the differences of the times.
  (isfinite(dt) && dt > 0) ||
    throw(ArgumentError("`dt` must be positive and finite, got $dt: the samples a particle scheme " *
                        "integrates over must lie at increasing times"))
  trail = trail_for_particle_step(cache, trail_capacity(scheme))
  u = velocity_physical(cache)
  if length(trail) >= _steps(scheme)
    # The full step: its number of samples is the scheme's own, known to the compiler.
    _advance_positions!(Val(_steps(scheme)), _corrects(scheme), tracers, u, domain, cache, trail,
                        Float64(dt), traversal)
  else
    # Short of samples the step is the predictor–corrector the samples present allow, whatever the
    # scheme: it is one order more accurate than the uncorrected step on the same samples.
    _advance_positions!(Val(length(trail)), true, tracers, u, domain, cache, trail, Float64(dt),
                        traversal)
  end
  # The positions changed, so the particles counter moves (decision 76) and the trail reads stale
  # until the closing particle deposit.
  advance_particles_epoch!(cache)
  return tracers
end


# The particle method of `deposit!` — the generic, and the one docstring covering all its forms,
# live in `Propagator`. The cache checks that the field and the positions belong to one time, hands
# out the trail's next slot, and stamps the sample; this method supplies the interpolation.
function deposit!(cache::ObservablesCache, tracers::Tracers, t::Real; traversal = nothing)
  _particle_trail(cache)                 # a cache without tracers is refused by name, first
  u = velocity_physical(cache)
  deposit_velocity_at_particles!(cache, t) do value
    interpolate!(value, u, tracers.positions, tracers.interpolation_scheme;
                 traversal = _order(traversal))
  end
  return cache
end


# ————————————————————————————————————————————————————————————————————————————————————————————————
# Display (the convention is stated once, at `SimulationDomain`'s display section): a scheme prints
# as the constructor call that rebuilds it.

Base.show(io::IO, ::ABM{k}) where {k} = k == 1 ? print(io, "Heun()") : print(io, "ABM(", k, ")")
Base.show(io::IO, ::AB{k}) where {k} = print(io, "AB(", k, ")")


end # module ParticlePropagator
