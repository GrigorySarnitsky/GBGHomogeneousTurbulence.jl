# Forcing — the interchangeable energy-injection strategies, concrete `AbstractForcing` subtypes that act
# on the time step in one of two ways:
#
#   * `set_forcing_rate!` — for a forcing whose rate is linear in the field AND STEADY IN TIME: fill a
#     per-mode A(k) folded into the integrating factor, so the linear operator becomes A(k) - D|k|².
#     Exact, and free. `uses_steady_linear_rate` declares it, and BOTH words are load-bearing: the
#     exponent is ∫A dt, so a rate that varies over the step is integrated by a left-endpoint
#     rectangle rule — local error O(Δt²), and the whole iteration collapses to FIRST order however
#     good the scheme is. Only `Linear`, whose A is a fixed coefficient, qualifies.
#   * `add_forcing_source!` — a source added at each stage, at the STAGE state. This is where a
#     state-dependent rate belongs: the scheme's own order conditions then apply to it, with nothing
#     to prove. `ConstantPower` and `VarianceController` use it. (TurTLE does the same — its
#     `add_forcing_term` writes into the RHS and is called once per Runge-Kutta stage.)
#   * `project_forcing!` — a post-step projection. `VarianceRescaling` uses it, and this route is
#     LIE-TROTTER SPLITTING: first order by construction, independent of the scheme. Kept as the
#     reference implementation of Sullivan-Mahalingam-Kerr (1994) with that caveat documented; prefer
#     `VarianceController`, which holds the same quantity through the rate route.
#
# Measured on IFLowStorageRK3 (third order), refinement ladder: NoForcing 2.995, Linear 2.987,
# ConstantPower 1.018 and VarianceRescaling 1.023 BEFORE this split — the `Linear`/`ConstantPower`
# contrast isolates the mechanism exactly, since they share the code path and differ only in whether
# A is steady.
#
# One implementation serves both the velocity (a vector field) and the scalar φ (a scalar field),
# since the methods are written through tensor-order-generic field operators. A linear rate keeps a
# solenoidal velocity solenoidal (per-mode scaling), so the velocity needs no projection here.
#
# The additive stochastic (Ornstein–Uhlenbeck / Eswaran–Pope) forcing — which adds a time-correlated
# force field to the RHS — is a separate mechanism (`StochasticOU`): its process is advanced once per
# step and lives in the run's state, not in the strategy (decision 23(c)).

"""
    Forcing

The interchangeable energy-injection strategies — one implementation each serving both the velocity
and the scalar through tensor-order-generic field operators. A strategy acts on the step through up
to four hook methods, each defaulting to doing nothing, called in the order listed:

- [`AbstractForcing`](@ref) — the strategy supertype, defining the four-hook lifecycle.
- [`initial_forcing_state`](@ref) — the evolving state a forcing starts with, kept in the run's state
  record.
- [`prepare_forcing!`](@ref) — advance that state, once per step.
- [`set_forcing_rate!`](@ref) — supply a *steady* linear rate, folded into the integrating factor;
  [`uses_steady_linear_rate`](@ref) declares that a forcing supplies one.
- [`add_forcing_source!`](@ref) — add a source term at each stage.
- [`project_forcing!`](@ref) — project or rescale the field after the step.
- [`NoForcing`](@ref) — leave the field undriven.
- [`Linear`](@ref) — a fixed linear rate on a **band**, an annulus of integer Fourier shells (the
  convention every strategy shares).
- [`ConstantPower`](@ref) — a band amplitude re-solved each stage to hold the injection rate.
- [`VarianceController`](@ref) — drive the field's variance to a target by feedback; the default.
- [`VarianceRescaling`](@ref) — hold the band's or the whole field's variance (`over`) by
  deterministic rescaling, at first order.
- [`StochasticOU`](@ref) — a random force correlated over a finite time, independent of the flow
  (Eswaran & Pope); its evolving state is a [`StochasticOUState`](@ref).
- [`DeferredForcing`](@ref) — the operator-free keyword form of a strategy, built into the concrete strategy once the
  [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) has built the domain; a
  construction-time object, not a lifecycle hook.
- [`write_forcing`](@ref) / [`read_forcing`](@ref) — a strategy's HDF5 persistence: its defining
  parameters as one self-describing group (available once `HDF5` is loaded).

Which keywords carry defaults follows one test: **does the value come from the method, or from this
run?** A canonical band (`lowest_shell = 1`, `highest_shell = 2`) is the method's and defaults; what
a run holds fixed, or drives at — `target`, `rate`, `injection_rate`, `over`, `forcing_variance`,
`correlation_time` — has no canonical value and is required. A `seed` is neither: any value gives an
equally valid realization, so it defaults, and naming it is how a run is repeated. A default at this layer never hides a choice you needed to make; the run layer's
convenience default (a controller targeting the initial kinetic energy) is that layer's own,
documented choice.

A band reaching above the dealias cutoff is inert there for a forcing that multiplies the field — the
mask holds those modes empty — so construction warns about it; the additive `StochasticOU` would
inject there instead, and refuses such a band.

The two fields are forced **independently**:
[`FlowConditions`](@ref GBGIsotropicTurbulence.Generator.FlowConditions) — the `Generator`
parameter record bundling the viscosity, the Schmidt number, and the two forcings — takes a
separate `velocity_forcing` and `scalar_forcing`, so a run can force one, both, or neither.

"""
module Forcing

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, TwoThirds, max_retained_wavenumber, new_scalar_field_spectral, new_vector_field_spectral, new_scalar_field_physical, new_vector_field_physical, _real_type,
                          _storage_family_name, _show_shape

export AbstractForcing, DeferredForcing, NoForcing, VarianceRescaling, VarianceController,
       Linear, ConstantPower, StochasticOU, StochasticOUState,
       set_forcing_rate!, uses_steady_linear_rate, project_forcing!, initial_forcing_state,
       prepare_forcing!, add_forcing_source!


# Is there anything in the band to rescale? The test carries NO absolute scale, which is what the
# forced problem requires: the scalar equation is exactly linear in φ, so φ → sφ with ε_φ → s²ε_φ is
# an exact symmetry, and any constant floor breaks it — silently switching the forcing off for a run
# whose amplitudes happen to be small, and in Float32 for many ordinary ones.
#
# Positivity is the whole test, and it needs no second reduction. An earlier attempt normalized the
# band observable by the WHOLE-FIELD observable, which was scale-free but bought it with an extra
# `inner(field, field)` every step. The bare-positivity form that then stood here was itself wrong
# the other way (caught by the 2026-08-23 dismissal audit): a band emptied by a mask or a rescale
# retains ROUNDOFF-level content, which is positive, so the amplitude ~ ε/2k_f took the unbounded
# kick the docstrings promise it never takes — A ≈ 1e58 from a 1e-60 band, Inf in one stage. The
# floor is back, but RELATIVE now: measured against the whole field's observable, it is invariant
# under φ → sφ (both scale by s²), which is the invariance the positivity form was keeping — and
# since the multi-weight fused reduction (PF decision 72), the whole-field value shares the band's
# traversal, so the scale costs no extra pass and no extra readback. The 10·eps echoes TurTLE's
# guard on the same division.
_band_is_empty(band_value, whole_value) =
  !(isfinite(band_value) && band_value > 10 * eps(one(band_value)) * whole_value)


"""
    AbstractForcing

Supertype of the energy-injection strategies — the interchangeable ways a run drives its velocity or
its scalar.

A strategy implements whichever of four hooks it needs; each defaults to doing nothing. A step calls
them in one fixed order:

- [`prepare_forcing!`](@ref) — once, before the stages: advance the strategy's own evolving state,
  such as a stochastic forcing's random process. [`initial_forcing_state`](@ref) creates that state
  and the run's [`ResolvedFields`](@ref GBGIsotropicTurbulence.State.ResolvedFields) holds it.
- [`set_forcing_rate!`](@ref) — once, before the stages: fill a per-mode rate that stays fixed for the
  whole step, which the scheme folds exactly into the integrating factor. A strategy that implements
  this hook **must** also declare [`uses_steady_linear_rate`](@ref), or it is never handed a rate
  array to fill.
- [`add_forcing_source!`](@ref) — at every stage: add a source term to the right-hand side.
- [`project_forcing!`](@ref) — once, after the completed step: project or rescale the advanced field.

The rate and the source are two channels of **one** forcing term: the steady part folded exactly into
the integrating factor, the remainder added at the stages. A single strategy may use both.

Which channel a rate may take is decided by steadiness in time, **not** by linearity in the field. The
integrating factor holds a rate fixed for the whole step, so a rate re-solved from the state must go
through `add_forcing_source!` instead; freezing it in the integrating factor would drop the scheme to
first order.

The declaration is measured when the generator is built, not trusted. A declared rate is armed from two
different fields and refused with an `ArgumentError` when the two differ, the hook taking no time
argument, so a field-independent rate is a steady one. A strategy that fills a rate without declaring
it is refused the same way, rather than going silently unapplied.

Each mutating hook returns the argument it mutated: `set_forcing_rate!` the rate,
`add_forcing_source!` the right-hand side, `project_forcing!` the field. `prepare_forcing!` returns
`nothing`, having advanced the state it was handed in place.

A hook runs inside the time loop, which is allocation-free at field scale, so a strategy allocates
whatever scratch it needs once, when it is built, and its hooks touch only that scratch and the
arguments they are given.

!!! warning "One instance per forced field, for a strategy with mutable bookkeeping"
    A strategy that mutates its own fields as it runs must not drive both fields from one instance,
    or their bookkeeping is conflated;
    [`FlowConditions`](@ref GBGIsotropicTurbulence.Generator.FlowConditions) throws an
    `ArgumentError` rather than let that happen. Every strategy here may be shared: none carries
    anything from one call to the next, since what a strategy evolves lives in the run's state, one
    entry per field, and its scratch is overwritten before each use.
"""
abstract type AbstractForcing end


"""
    DeferredForcing

A deferred forcing. The operator-free keyword constructors

    Linear(; rate, lowest_shell = 1, highest_shell = 2)
    ConstantPower(; injection_rate, lowest_shell = 1, highest_shell = 2)
    VarianceRescaling(; target, over, lowest_shell = 1, highest_shell = 2)
    VarianceController(; target, gain = 1, turnover_time = nothing, lowest_shell = 1, highest_shell = 2)
    StochasticOU(; forcing_variance, correlation_time, lowest_shell = 1, highest_shell = 2, seed = 42)

each returns a `DeferredForcing` capturing **the same keywords, with the same defaults**, as their
`domain`-taking forms documented on each strategy; it is built into the concrete
`AbstractForcing` once the [`FixedDomain`](@ref GBGIsotropicTurbulence.SimulationDomain.FixedDomain)
exists (done for you by [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation)). A
forcing argument
therefore accepts either a ready-built `AbstractForcing` (from the `domain`-taking constructor) or a
`DeferredForcing`.

# Examples
Name a forcing before any grid exists, or build it directly once the domain is in hand:

```julia
# Name the forcing before any grid exists — `Simulation` supplies the domain:
sim = Simulation(grid_points_per_axis = 64, viscosity = 5e-3,
                 velocity_forcing = ConstantPower(injection_rate = 0.1))

# Or build it directly, once the domain is in hand:
domain = FixedDomain(; grid_points_per_axis = 64, side_length = 2π, dealiasing = TwoThirds(),
                     element_type = Float64, array_type = Array)
forcing = ConstantPower(domain; injection_rate = 0.1)
```

# Fields
- `build` — the captured constructor closure: calling the `DeferredForcing` on a `FixedDomain`
  invokes it, yielding the concrete strategy.
"""
struct DeferredForcing{F}
  build::F
end

(deferred::DeferredForcing)(domain::FixedDomain) = deferred.build(domain)


"""
    set_forcing_rate!(forcing, rate, field, domain) -> rate

For a strategy `forcing` whose rate is linear in the field **and constant in time** (the
[`uses_steady_linear_rate`](@ref) declaration), fill the per-mode rate `rate` — a scalar field in spectral
representation holding real values — with ``A(\\boldsymbol{\\kappa})``
(the forcing ``f = A \\texttt{field}``) and return `rate`; the scheme folds it into the diffusive
integrating factor ``\\mathcal{E}(\\boldsymbol{\\kappa})`` (see [`velocity_integrating_factor`](@ref GBGIsotropicTurbulence.Generator.velocity_integrating_factor)), so the
forced modes advance at the net linear rate ``A(\\boldsymbol{\\kappa}) - D\\lvert\\boldsymbol{\\kappa}\\rvert^{2}``
(``D`` the field's diffusivity). Only a forcing declaring `uses_steady_linear_rate` is ever handed
a rate array, so the default method is never reached in a run; it returns `rate` untouched. The
`field` is the start-of-step field in spectral representation; `domain` is the
[`FixedDomain`](@ref).
"""
set_forcing_rate!(::AbstractForcing, rate, field, domain::FixedDomain) = rate


"""
    uses_steady_linear_rate(forcing) -> Bool

Whether `forcing` drives its field through a per-mode rate that is **constant in time**, and can
therefore be folded into the integrating factor — that is, whether it implements
[`set_forcing_rate!`](@ref). The default is `false`; a forcing that does implement the hook **must**
declare it `true`.

*Steady*, not merely linear, is the load-bearing word: a per-mode rate re-solved from the state each
step must **not** declare this. Freezing it would be the left-endpoint rectangle rule on
``\\int A\\,\\mathrm{d}t``, dropping the scheme to first order; such a forcing goes through
[`add_forcing_source!`](@ref) instead.

The generator allocates a rate array ``A(\\boldsymbol{\\kappa})`` per field only for a forcing that
declares this, so an unforced field, a post-step projection, or a stochastic source carries no rate
storage at all. Declaring it is therefore part of implementing `set_forcing_rate!`: a forcing
that fills a rate without declaring one is never given an array to fill, and
the [`ResolvedGenerator`](@ref GBGIsotropicTurbulence.Generator.ResolvedGenerator) constructor
rejects
it rather than let the forcing go silently unapplied.
"""
uses_steady_linear_rate(::AbstractForcing) = false


"""
    project_forcing!(forcing, advanced_field, domain) -> advanced_field

Apply the strategy `forcing`'s post-step projection to `advanced_field` (a velocity or scalar
``\\varphi`` field in spectral representation) in place, on the [`FixedDomain`](@ref) `domain`. The
default does nothing; see `VarianceRescaling`.

Unlike the two hooks that read the start-of-step field, this one is handed the field the step has
already advanced — the argument is named for that instant, since a strategy that rescales toward a
target must measure the state it is correcting, not the one it started from.
"""
project_forcing!(::AbstractForcing, advanced_field, domain::FixedDomain) = advanced_field


"""
    initial_forcing_state(forcing, field, domain)

Create the state the strategy `forcing` begins from when it drives `field` — the velocity or the
scalar in spectral representation, whose tensor order sets how many components the state carries — on
the [`FixedDomain`](@ref) `domain`.

Returns `nothing` for a strategy that evolves no state of its own: the default, and the case of every
strategy but [`StochasticOU`](@ref), which returns a
[`StochasticOUState`](@ref) holding its random process.

A run calls this once per forced field, keeps what it returns as the `modeled` entry of its
[`ResolvedFields`](@ref GBGIsotropicTurbulence.State.ResolvedFields), and hands that value to
[`prepare_forcing!`](@ref) every step, which advances it in place. The strategy itself holds only its
parameters and its scratch, so a checkpoint of the state is enough to resume a forced run exactly.
"""
initial_forcing_state(::AbstractForcing, field, domain::FixedDomain) = nothing


"""
    prepare_forcing!(forcing, forcing_state, field, domain, dt) -> nothing

Advance the strategy `forcing`'s evolving state by one step, before the Runge–Kutta stages begin.
The state is mutated in place, so it holds its end-of-step value when this call returns; the default
does nothing.

Everything the stages will need must be ready when this returns, since
[`add_forcing_source!`](@ref) is handed no timestep of its own.

The arguments are:
- `forcing` — the strategy whose state advances.
- `forcing_state` — that state as it stands now, not as it started:
  [`initial_forcing_state`](@ref) created it once, and this hook has advanced it on every step since.
  It is `nothing` for a strategy that evolves no state.
- `field` — the start-of-step velocity or scalar, in spectral representation.
- `domain` — the [`FixedDomain`](@ref) the run advances on.
- `dt` — the step about to be taken.
"""
prepare_forcing!(::AbstractForcing, forcing_state, field, domain::FixedDomain, dt::Real) = nothing


"""
    add_forcing_source!(forcing, forcing_state, N̂, field, domain, diffusivity) -> N̂

Add the strategy `forcing`'s source term to the assembled right-hand side `N̂`, at every Runge–Kutta
stage. The default does nothing.

Two kinds of strategy come through this hook. One measures the stage's own `field` and sets its
amplitude from it — `ConstantPower` and `VarianceController` do, and this is the only route open to
them, since a state-dependent rate frozen once per step would drop the scheme to first order. The
other carries a source that does not read the field at all: [`StochasticOU`](@ref)'s random process,
already advanced for this step by [`prepare_forcing!`](@ref), which this hook only writes into `N̂`.

The arguments are:
- `forcing` — the strategy adding the source.
- `forcing_state` — its evolving state as `prepare_forcing!` left it this step, or `nothing` for a
  strategy without one. This hook reads it and does not advance it.
- `N̂` — the assembled right-hand side, accumulated into.
- `field` — this stage's own velocity ``\\hat{\\boldsymbol{u}}`` or scalar ``\\hat{\\varphi}``, in
  spectral representation, whichever the strategy drives.
- `domain` — the [`FixedDomain`](@ref) the term is assembled on.
- `diffusivity` — the diffusivity acting on the forced field: ``\\nu`` for the velocity,
  ``\\varkappa`` for the scalar.

Measuring the field costs one blocking device-to-host transfer at every stage, and that is the price
of the order this route preserves. A single fused multi-weight reduction answers
[`VarianceController`](@ref)'s three weighted sums together, and [`ConstantPower`](@ref) reads its
band the same fused way. A strategy that reads nothing pays nothing: `StochasticOU` makes no such
transfer, and [`Linear`](@ref), which takes the rate route instead, makes none either.

!!! warning "The source is accumulated, never assigned"
    Every stage adds into an `N̂` the generator has already filled with the nonlinear term, so an
    implementation must **add** its contribution and must not overwrite the buffer.
"""
add_forcing_source!(::AbstractForcing, forcing_state, N̂, field, domain::FixedDomain,
                    diffusivity::Real) = N̂


# An annular shell band-pass kernel for shells `lowest ≤ |k| ≤ highest` (integer shells of 2π/L).
# The shell arguments are validated HERE, once for all four band forcings, so the thrown message
# names the argument the caller typed — the backend's own guard fires on the padded band edges
# ("band edges must satisfy 0 <= low", with our −0.5 padding visible), which reads as internals.
function _check_shells(lowest::Integer, highest::Integer)
  lowest >= 1 ||
    throw(ArgumentError("`lowest_shell` must be at least 1, got $lowest: shell 0 is the mean " *
                        "(κ = 0) mode, which a band forcing cannot legitimately drive — it carries " *
                        "the box's total momentum (or the scalar's mean), not turbulence"))
  highest >= lowest ||
    throw(ArgumentError("`highest_shell` must be at least `lowest_shell`, got $highest < $lowest: " *
                        "the band would be empty and the forcing would silently do nothing"))
  return nothing
end

function _shell_band(domain::FixedDomain, lowest::Integer, highest::Integer)
  _check_shells(lowest, highest)
  k0 = 2π / domain.grid.domain_size[1]
  # A band above the dealias cutoff is INERT, not harmful: the mask keeps those modes empty, and
  # every band forcing is field-proportional, so it multiplies zero forever. Measured: a Linear on
  # shells 6–7 at N = 16 (cutoff shell ≈ 5.3) injected exactly nothing over 100 steps. Legal — a
  # marginal band is a legitimate choice — but it cannot be silent, or a run decays with its forcing
  # apparently on. (An ADDITIVE forcing would genuinely inject there, so `StochasticOU` does not take
  # this warning: it refuses such a band outright.)
  κ_max = max_retained_wavenumber(domain)
  if (lowest - 0.5) * k0 > κ_max
    @warn "the forcing band (shells $(lowest)–$(highest)) lies entirely above the dealias cutoff " *
          "(shell ≈ $(round(κ_max / k0, digits = 1))): those modes are held empty by the mask and " *
          "a band forcing multiplies the field, so this forcing will do NOTHING. Lower the shells, " *
          "or enlarge the grid."
  elseif (highest + 0.5) * k0 > κ_max
    @warn "the forcing band (shells $(lowest)–$(highest)) reaches above the dealias cutoff " *
          "(shell ≈ $(round(κ_max / k0, digits = 1))): the shells above it are held empty by the " *
          "mask and contribute nothing — the forcing acts only on the retained part of the band."
  end
  return spectral_band(domain.multipliers, (lowest - 0.5) * k0, (highest + 0.5) * k0)
end


# The observable a forcing `target` agrees with: kinetic energy ½⟨|u|²⟩ for the velocity (a vector
# field, tensor order 1), scalar variance ⟨φ²⟩ for the scalar (order 0) — the ½ convention only for the
# vector, matching `Observables.kinetic_energy` / `Observables.scalar_variance`.
# An `Int` and a `Rational`, not floating literals: `0.5` is a `Float64` and promoted every band
# observable — and the amplitude derived from it — off a Float32 run's element type, which the rest of
# the observable surface is pinned to preserve. Exact types multiply through without promoting and
# without asking the field what its element type is, so this needs no accessor and works against any
# field-like value a caller substitutes.
_target_factor(field) = field_tensor_order(field) == 0 ? 1 : 1 // 2


"""
    NoForcing()

The unforced case: all four methods keep their defaults (do nothing) — a freely decaying field.
"""
struct NoForcing <: AbstractForcing end


"""
    VarianceRescaling(domain; target, over, lowest_shell = 1, highest_shell = 2)

The deterministic rescaling forcing of Sullivan, Mahalingam & Kerr (1994,
[*Deterministic forcing of homogeneous, isotropic turbulence*](https://doi.org/10.1063/1.868274),
*Phys. Fluids* **6**(4), 1612–1614), built on the [`FixedDomain`](@ref)
`domain`: after each step the in-band Fourier modes — the integer shells `lowest_shell` to
`highest_shell`, in units of the box's fundamental ``2\\pi/L`` — are rescaled by a single factor that
holds `target`. The rescale is per-mode, so a divergence-free velocity stays divergence-free.

**Prefer [`VarianceController`](@ref) for a run whose accuracy in time matters**, which is nearly
always. It holds the same quantity through a rate the scheme integrates and keeps the scheme's order;
this one is applied after the step and costs it (see the caveat below). It is kept because it is a published
method a reader may need to reproduce, and because holding a band's value *exactly* is occasionally
what is wanted.

Which observable is held follows from the field, chosen to agree with the diagnostics: the **kinetic
energy** ``\\tfrac{1}{2}\\langle\\lvert\\boldsymbol{u}\\rvert^{2}\\rangle`` for the velocity
([`kinetic_energy`](@ref GBGIsotropicTurbulence.Observables.kinetic_energy)), the **scalar variance**
``\\langle\\varphi^{2}\\rangle`` for the scalar
([`scalar_variance`](@ref GBGIsotropicTurbulence.Observables.scalar_variance)) — each the field's
``L^{2}`` observable, the ``\\tfrac{1}{2}`` belonging to the kinetic energy's definition rather than
to the field being a vector.

The `over` keyword selects *where* that target applies — it is required, since a deterministic clamp destroys
the physical fluctuation of whatever it holds and no default is right for every run — and the two
modes differ in which quantity a run may no longer measure:

  * `:band` holds the band's own value. The whole-field value then floats, oscillating about its mean
    as the band feeds the cascade. On the default shells 1–2 — the energy-containing range — most of
    ``k`` is held rather than free, though it remains a measurable.
  * `:total` rescales the band to absorb the whole-field deficit, so the whole-field value equals
    `target`. For the velocity this pins ``u'`` and with it the scale of ``\\mathrm{Re}_\\lambda``
    (whose value still fluctuates with the instantaneous dissipation). Here ``k`` is what the forcing
    sets and the band is free.

Neither is a default, because the right answer depends on what the run is calibrated against.
A [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) deriving ``\\nu`` chooses it
from the *assumed* kinetic energy, so a forcing put there by hand must be a `:total` one or that
calibration stops holding. Where nothing calibrates against it, `:band` is the gentler clamp.

Sizing the rescale reduces the field to a number, so each step blocks on one device-to-host
transfer: the band and whole-field observables ride a single fused traversal, in either mode.

!!! warning "First order in time, and two extremes worth knowing"
    This is the one forcing that costs the scheme its order, by construction rather than by defect:
    the rescale is applied *after* the step, which is Lie–Trotter operator splitting — the step's
    map and the rescale's map composed one after the other, a composition whose error is
    ``O(\\Delta t)`` regardless of how accurate either map is alone — so it
    is first-order however good the scheme is. Measured on the third-order [`IFLowStorageRK3`](@ref GBGIsotropicTurbulence.Propagator.IFLowStorageRK3): **1.02**
    here, against **3.01** for `Linear`, `ConstantPower`, `VarianceController` and an unforced run.
    (A stochastic forcing is outside that comparison — it has no classical order to lose.)
    Molecular dynamics reached the same
    conclusion about the same manoeuvre — per-step rescaling is the deterministic (Berendsen) limit
    of stochastic velocity rescaling, with no conserved quantity and no well-defined ensemble except
    in limiting cases (Bussi, Donadio & Parrinello 2007,
    [*Canonical sampling through velocity rescaling*](https://doi.org/10.1063/1.2408420),
    *J. Chem. Phys.* **126**, 014101) — and the fix is to extend the dynamics with feedback rather
    than project after the fact.

    Two configurations also behave sharply. Under `:total`, if the out-of-band value alone exceeds
    `target`, the band is **zeroed** — the closest reachable state, and the most violent intervention
    the rescale can make. At the other end an empty band is **left alone** rather than divided by ~0,
    so it stays empty instead of being driven to `target`. Seed content in the band if a run depends
    on the clamp taking hold.

# Fields
- `band` — the band-pass kernel selecting the rescaled shells.
- `target` — the held value.
- `over` — `:band` or `:total`.
- `lowest_shell`, `highest_shell` — the forced band's shell bounds: the parameters the band kernel
  is derived from, kept so the strategy remains its own record.
"""
struct VarianceRescaling{K, T} <: AbstractForcing
  band::K              # annular band-pass kernel (ScalarFieldSpectral)
  target::T            # the VALUE to hold, of kinetic_energy (velocity) or scalar_variance (scalar)
  over::Symbol         # :band (hold the band's value) or :total (hold the whole-field value)
  lowest_shell::Int    # the band's shell bounds — the parameters `band` is derived from
  highest_shell::Int
end

function VarianceRescaling(domain::FixedDomain; target::Real, over::Symbol,
                       lowest_shell::Integer = 1, highest_shell::Integer = 2)
  over in (:band, :total) ||
    throw(ArgumentError("VarianceRescaling `over` must be :band or :total; got :$over"))
  # Cast to the domain's element type FIRST, so the guard certifies the stored value.
  target = _real_type(domain)(target)
  # The target is an energy or a variance — both non-negative — and the rescale takes its square
  # root, so a negative value surfaced as a bare `DomainError` out of `sqrt` naming nothing.
  (isfinite(target) && target >= 0) ||
    throw(ArgumentError("VarianceRescaling `target` must be finite and non-negative, got $target: " *
                        "it is the kinetic energy or scalar variance the forcing holds, and the " *
                        "rescale takes its square root"))
  return VarianceRescaling(_shell_band(domain, lowest_shell, highest_shell), target, over,
                           Int(lowest_shell), Int(highest_shell))
end


function project_forcing!(forcing::VarianceRescaling, field, domain::FixedDomain)
  factor = _target_factor(field)                       # ½ for the velocity (KE), 1 for the scalar (variance)
  # Both modes ride ONE fused traversal (one readback): the whole-field value serves the relative
  # empty-band floor in either mode, and the :total deficit on top.
  band_raw, whole_raw = weighted_inner(field, (forcing.band, domain.unit_kernel))
  band_value = factor * band_raw                       # the band observable (fused; no band-pass copy)
  if _band_is_empty(band_raw, whole_raw)               # roundoff-level band: leave it alone
    @warn "VarianceRescaling: the forced band is empty (band observable $band_raw against a " *
          "whole-field $whole_raw): the rescale is skipped until content reaches the band" maxlog = 1
    return field
  end
  # aim the band at: the target itself (:band), or what makes the *whole field* hit the target
  target_band = if forcing.over === :total
    total_value = factor * whole_raw                   # the observable over the whole field
    max(zero(band_value), forcing.target - total_value + band_value)
  else
    forcing.target
  end
  scale = sqrt(target_band / band_value)
  convolve!(field, field, forcing.band, scale - 1, 1)  # rescale in-band modes (α/β accumulate)
  return field
end


"""
    Linear(domain; rate, lowest_shell = 1, highest_shell = 2)

Linear (negative-damping) forcing ``f = A \\texttt{field}`` in a low-wavenumber band (a band-limited
variant of Lundgren (2003) — *Linearly forced isotropic turbulence*, *CTR Annual Research
Briefs*, 461–473 (no DOI) — whose linear forcing
acts at every wavenumber), built on the [`FixedDomain`](@ref) `domain`. The rate is folded into the
integrating factor, so the forced band modes grow at net rate
``A - D\\lvert\\boldsymbol{\\kappa}\\rvert^{2}`` (``D`` the field's diffusivity).

It is the only strategy taking that route — exactness there is a statement about a *steady* ``A`` —
which makes it the cheapest forcing here, at no per-stage reduction and no host readback.

# Arguments
- `domain` — the `FixedDomain` the band is built on.
- `rate` — the fixed linear rate ``A``. A positive value amplifies the field.
- `lowest_shell = 1`, `highest_shell = 2` — the forced band, as integer shells in units of the box's
  fundamental ``2\\pi/L``.

# Fields
- `indicator` — the band indicator as a real array.
- `rate` — the fixed linear rate ``A``.
- `lowest_shell`, `highest_shell` — the forced band's shell bounds: the parameters `indicator` is
  derived from.
"""
struct Linear{M, T} <: AbstractForcing
  indicator::M         # real array: the band indicator (1 in band, 0 outside)
  rate::T              # the linear rate A
  lowest_shell::Int    # the band's shell bounds — the parameters `indicator` is derived from
  highest_shell::Int
end

function Linear(domain::FixedDomain; rate::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2)
  # The band kernel is lazy (a radial symbol); the rate fill wants its values as a real array, so the
  # indicator is materialized once here — the same stored mask this forcing always carried.
  indicator = real.(field_data(materialize_kernel(_shell_band(domain, lowest_shell, highest_shell)).field))
  return Linear(indicator, _real_type(domain)(rate), Int(lowest_shell), Int(highest_shell))
end

uses_steady_linear_rate(::Linear) = true

function set_forcing_rate!(forcing::Linear, rate, field, domain::FixedDomain)
  T = field_scalar_type(rate)
  rate .= T(forcing.rate) .* forcing.indicator
  return rate
end


"""
    ConstantPower(domain; injection_rate, lowest_shell = 1, highest_shell = 2)

Constant-injection-rate forcing, built on the [`FixedDomain`](@ref) `domain`: a banded linear
forcing ``f = A \\texttt{field}`` on the integer shells `lowest_shell` to `highest_shell` (in units
of the box's fundamental ``2\\pi/L``; default 1–2),
whose rate ``A`` is re-solved at every stage so the injection rate holds the `injection_rate`. A
linear rate injects at ``2 A E_{\\mathrm{band}}``, with ``E_{\\mathrm{band}}`` the band's own
observable, so the rate that holds it is

```math
A = \\frac{\\texttt{injection\\_rate}}{2 E_{\\mathrm{band}}}.
```

In stationarity the injection balances dissipation, so `injection_rate` is the value ``\\varepsilon``
relaxes to in the stationary mean — chosen to agree with the diagnostics —
the rate ``\\varepsilon`` for the velocity (measured by
[`dissipation`](@ref GBGIsotropicTurbulence.Observables.dissipation)) and
``\\varepsilon_\\varphi`` for the scalar (by
[`scalar_dissipation`](@ref GBGIsotropicTurbulence.Observables.scalar_dissipation)). The keyword
names the kind of quantity it is — a **rate**, where `VarianceRescaling`'s `target` is an
**amplitude**.

Since that amplitude is re-solved from the state, it enters the right-hand side at **every stage**
rather than the integrating factor, where freezing it would cost the scheme its order. Like
[`Linear`](@ref) it is a per-mode multiple of the field, so it preserves a solenoidal velocity.

# Arguments
- `domain` — the `FixedDomain` the band is built on.
- `injection_rate` — the rate at which energy (for the velocity) or scalar variance (for the scalar)
  is injected; not an instantaneous dissipation the forcing measures or clamps.
- `lowest_shell = 1`, `highest_shell = 2` — the forced band, as integer shells in units of the box's
  fundamental ``2\\pi/L``.

!!! note "An empty band is left alone, not driven infinitely hard"
    The rate ``A`` diverges as the band's own value goes to zero — its energy for the velocity, its
    variance for the scalar — which is reachable: a scalar seeded with nothing in the forced shells,
    or the step after a `VarianceRescaling(over = :total)` zeroed the band. Below a
    machine-roundoff floor on the band's observable — measured relative to the whole field's, so
    the test is invariant under a uniform rescaling of the field — the amplitude is set to zero,
    and an empty band stays empty rather than taking an unbounded kick; seed content in the band
    if a run needs the forcing to take hold.

# Fields
- `band` — the band-pass kernel, lazy: the per-stage source both weights the band observable with it
  and convolves against it, so no indicator array is stored.
- `injection_rate` — the held rate.
- `lowest_shell`, `highest_shell` — the forced band's shell bounds: the parameters `band` is derived
  from.
"""
struct ConstantPower{K, T} <: AbstractForcing
  band::K              # band-pass kernel (lazy radial symbol) — the band observable's weight
  injection_rate::T    # the VALUE of the dissipation rate to hold: dissipation or scalar_dissipation
  lowest_shell::Int    # the band's shell bounds — the parameters `band` is derived from
  highest_shell::Int
end

"""
    VarianceController(domain; target, gain = 1, turnover_time = nothing,
                       lowest_shell = 1, highest_shell = 2)
    VarianceController(; target, gain = 1, turnover_time = nothing,
                       lowest_shell = 1, highest_shell = 2)

Hold the field's variance at `target` by feedback — the kinetic energy ``k`` for the velocity,
``\\langle\\varphi^{2}\\rangle`` for the scalar — with the constant-``k`` controller of
Bassenne et al. (2016, [*Constant-energetics physical-space forcing methods for improved convergence to homogeneous-isotropic turbulence with application to particle-laden flows*](https://doi.org/10.1063/1.4944629),
*Phys. Fluids* **28**, 035114).

Prefer it to [`VarianceRescaling`](@ref) whenever accuracy in time matters, which is nearly always:
it enters the right-hand side as a smooth rate the scheme integrates and keeps its order, where a
rescaling is a post-step projection capping the iteration at first order.

The rate is the marginal law ``A = \\varepsilon/2k_f`` plus a proportional restoring term:

```math
A(\\boldsymbol{\\kappa}, t) = \\frac{\\varepsilon(t) - G[k(t) - k_\\infty]/t_\\ell}{2k_f(t)}
\\quad\\text{in the band, } 0 \\text{ outside,}
```

so that ``\\mathrm{d}k/\\mathrm{d}t = -G(k - k_\\infty)/t_\\ell`` exactly: the variance relaxes
exponentially to a **stable attractor** with settling time ``t_\\ell/G``.

The limit `gain = 0` is the bare **marginal law**, and it is allowed: exact reinjection of the
instantaneous ``\\varepsilon`` makes ``\\mathrm{d}k/\\mathrm{d}t = 0``, so ``k`` is *conserved at
its initial value* and `target` never enters the rate. Every level is then a **neutral** equilibrium
— the reinjection cancels the cascade's own restoring response, which [`ConstantPower`](@ref)'s
fixed injection retains — so discrete integration bias accumulates uncorrected (about 1% of ``k``
per 1000 steps, measured at ``24^3`` in `Float64`; a `Float32` run's roundoff bias is larger and
unmeasured), and nothing ever restores it.

The two variances there are **not interchangeable**: ``k`` is the whole field's, the one held;
``k_f`` the forced band's, dividing out because the forcing injects only there. An empty band is
left alone rather than divided by ``\\sim 0`` (the floor `ConstantPower` documents), so seed content
in the band if the run depends on the controller taking hold.

The molecular-dynamics thermostats map the design space exactly, and **this controller is the
Berendsen-weak-coupling analogue** — gain-limited relaxation toward a target (Berendsen et al. 1984,
[*Molecular dynamics with coupling to an external bath*](https://doi.org/10.1063/1.448118),
*J. Chem. Phys.* **81**, 3684–3690), carrying that class's known caveat: the
held quantity's own fluctuations are distorted by the coupling. Per-step rescaling is the naive
thermostat, whose limit here is `VarianceRescaling`; the contrasting extended-variable class
that restores canonical fluctuations is Nosé–Hoover
(Nosé 1984, [*A unified formulation of the constant temperature molecular dynamics methods*](https://doi.org/10.1063/1.447334),
*J. Chem. Phys.* **81**(1), 511–519; Hoover 1985,
[*Canonical dynamics: Equilibrium phase-space distributions*](https://doi.org/10.1103/PhysRevA.31.1695),
*Phys. Rev. A* **31**(3), 1695–1697), a design this package
does not take.

# Arguments
- `domain` — the [`FixedDomain`](@ref) the band kernel is built on (the first form; the
  operator-free second form defers that to the run, as a [`DeferredForcing`](@ref)).
- `target` — the whole-field variance ``k_\\infty`` to hold, in the field's own convention: the
  kinetic energy for the velocity, ``\\langle\\varphi^{2}\\rangle`` for the scalar.
- `gain = 1` — the dimensionless gain ``G``. A larger gain relaxes faster; Bassenne et al. report
  ``O(1-10)``, and the default sits at that range's gentle end so the controller perturbs the
  dynamics least. `0` is the bare marginal law above.
- `turnover_time = nothing` — the large-eddy turnover time ``t_\\ell = 2k_\\infty/(3\\varepsilon_\\infty)``
  (Bassenne's convention: ``\\tfrac{2}{3}`` of the run layer's eddy-turnover unit ``k/\\varepsilon``).
  Left at `nothing` it is computed for you from that formula, with ``\\varepsilon_\\infty`` the
  stationary estimate for this box — the same estimate the viscosity derivation uses, so a run
  that sets ``\\nu`` explicitly against a very different regime should pass its own value. The
  derivation reads `target` as a kinetic energy, so it is valid only for the velocity: a
  controller left at the default and handed to
  [`FlowConditions`](@ref GBGIsotropicTurbulence.Generator.FlowConditions) as a `scalar_forcing` with a
  positive gain is refused there — a scalar variance is not an energy, and the derived settling
  time would depend on the scalar's amplitude unit, breaking the scalar equation's exact
  linearity in ``\\varphi`` (at `gain = 0` the settling time never enters the dynamics and the
  marginal law stays legal). Driving the scalar, pass the **flow's** turnover time
  ``2k/(3\\varepsilon)`` explicitly.
- `lowest_shell = 1`, `highest_shell = 2` — the forced band, in integer shells of ``2\\pi/L``.

!!! note "The settling time, not the gain, is the physical parameter"
    Only the ratio ``t_\\ell/G`` is observable: it is how long the variance takes to return after a
    disturbance. The two are kept separate because that is how the source states them.

# Fields
- `band` — the band-pass kernel, lazy; the controller convolves against it and stores nothing.
- `target`, `gain`, `turnover_time` — ``k_\\infty``, ``G`` and ``t_\\ell``.
- `turnover_time_derived` — `true` when ``t_\\ell`` came from the kinetic-energy default rather
  than the caller; the scalar binding refuses such a controller.
- `lowest_shell`, `highest_shell` — the forced band's shell bounds: the parameters `band` is derived
  from.
"""
struct VarianceController{K, T} <: AbstractForcing
  band::K
  target::T
  gain::T
  turnover_time::T
  turnover_time_derived::Bool   # true when tℓ came from the kinetic-energy default, not the caller
  lowest_shell::Int    # the band's shell bounds — the parameters `band` is derived from
  highest_shell::Int
end


function VarianceController(domain::FixedDomain; target::Real, gain::Real = 1,
                            turnover_time = nothing, lowest_shell::Integer = 1,
                            highest_shell::Integer = 2)
  # The strategy carries the DOMAIN's element type: each scalar is cast to it, so a Float32 run's
  # default controller stays Float32 even when the target arrives as an untyped Float64 literal —
  # the Simulation keyword default rode `promote(float(target), …)` up to Float64 on every
  # default-forced Float32 run before this cast. The cast comes FIRST, so the guards below certify
  # the values the struct will actually hold — a value that narrows to `Inf32` or `0.0f0` on a
  # Float32 domain is refused, not stored in violation of its own guard.
  Td = _real_type(domain)
  target = Td(target)
  gain = Td(gain)
  # Finite AND positive, as the codebase's other positive-scalar guards read: `Inf` passes `> 0` and
  # then propagates a NaN amplitude into the right-hand side, which surfaces as a blown-up run far
  # from the constructor that accepted it.
  (isfinite(target) && target > 0) ||
    throw(ArgumentError("`target` must be finite and positive, got $target: it is the variance the " *
                        "controller holds, and the rate divides by the band's own variance"))
  (isfinite(gain) && gain >= 0) ||
    throw(ArgumentError("`gain` must be finite and non-negative, got $gain: a negative gain makes " *
                        "the restoring term push the variance AWAY from the target. The value " *
                        "`gain = 0` is the bare marginal law — no restoring at all — and is allowed."))
  band = _shell_band(domain, lowest_shell, highest_shell)
  # t_ℓ = 2k_∞/3ε_∞, the large-eddy turnover time, with ε_∞ the stationary estimate for this box —
  # the same estimate the viscosity derivation uses, so the two agree on what "stationary" means.
  tℓ = Td(turnover_time === nothing ?
          2 * float(target) / (3 * _stationary_dissipation_estimate(float(target),
                                                                    domain.grid.domain_size[1])) :
          turnover_time)
  # r6-edge-cases-01: the message must show the value the check REJECTED. When the keyword was
  # omitted, that is the derived tℓ, never the caller's `nothing`.
  (isfinite(tℓ) && tℓ > 0) ||
    throw(ArgumentError("`turnover_time` must be finite and positive, got $tℓ" *
                        (turnover_time === nothing ?
                         " (derived from `target` = $target and the box side; pass " *
                         "`turnover_time` explicitly)" : "")))
  return VarianceController(band, target, gain, tℓ, turnover_time === nothing,
                            Int(lowest_shell), Int(highest_shell))
end


# ε_∞ = (k/G)^{3/2}/L for a stationary box-filling flow, with G ≈ 0.9 the box-normalized dissipation
# group Li et al. (2008) fit to JHTDB. Spelled here rather than reached for from `Phenomenology`,
# which is an extraction-bound leaf this module must not depend on — so the value is duplicated
# deliberately, and `test/forcing.jl` pins it against `Scalings.Li2008` so the copy cannot drift.
# It has to be the SAME estimate the viscosity derivation uses: that derivation chooses ν from the
# assumed k, and the controller's default relaxation time sets how fast the run reaches it. Two
# different notions of "stationary for this box" would put the two out of step with each other.
# A `Rational` and a rational exponent, never floating literals — the same rule `_target_factor`
# carries and for the same reason: a bare `0.9` or `3/2` is a `Float64` and promotes the estimate,
# the turnover time, and then the whole controller off a Float32 run's element type.
const _DISSIPATION_GROUP = 9 // 10
_stationary_dissipation_estimate(k, L) = (k / _DISSIPATION_GROUP)^(3 // 2) / L


uses_steady_linear_rate(::VarianceController) = false


function add_forcing_source!(forcing::VarianceController, forcing_state, N̂, field, domain::FixedDomain,
                             diffusivity::Real)
  T = field_scalar_type(N̂)
  factor = _target_factor(field)
  # Two DIFFERENT weights, and which one goes where is the whole content of Bassenne's Eq. 20.
  # The forcing acts on the band alone, so it injects 2·A·k_f and the amplitude must be normalized by
  # the BAND's variance; the quantity being held is the field's whole-field variance, so the restoring
  # term must measure THAT. Using k_f in both places holds the band at `target` instead, which is a
  # different physical model and leaves the whole field wherever the cascade puts it.
  # One traversal, one readback: the three weighted sums share a single fused reduction (PF
  # decision 72) where three separate calls would read the field three times and block on the
  # device three times per stage. Bitwise identical to the separate calls.
  whole, band, dirichlet =
    weighted_inner(field, (domain.unit_kernel, forcing.band, domain.squared_wavenumber_kernel))
  whole_variance = factor * whole                                        # k, the quantity held
  band_variance = factor * band                                          # k_f, the forced band
  # ε = D⟨|∇f|²⟩ = D·⟨f, |κ|²f⟩, the field's own dissipation at this stage. The factor is the same
  # convention `target` carries — ½ for the velocity, 1 for the scalar.
  dissipation = 2 * factor * diffusivity * dirichlet
  restoring = forcing.gain * (whole_variance - forcing.target) / forcing.turnover_time
  # One home for the empty-band clamp: the combinator ConstantPower shares. The controller's
  # numerator is what its amplitude must hold — the dissipation less the restoring term.
  amplitude = _injection_amplitude(dissipation - restoring, band_variance, whole_variance,
                                   :VarianceController)
  convolve!(N̂, field, forcing.band, T(amplitude), one(T))
  return N̂
end

function ConstantPower(domain::FixedDomain; injection_rate::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2)
  # No materialized indicator: it existed only to fill the integrating-factor rate array, and this
  # forcing no longer uses that route. The lazy kernel is convolved against directly, so a
  # `ConstantPower` run now carries NO field-scale storage of its own — two arrays fewer.
  return ConstantPower(_shell_band(domain, lowest_shell, highest_shell),
                       _real_type(domain)(injection_rate),
                       Int(lowest_shell), Int(highest_shell))
end

# NOT a steady rate, and declaring it one was the defect. `A = ε/2k_band` is linear in the field but
# depends on the band energy, which changes across the step — so folding it into the integrating
# factor evaluates ∫A dt by a LEFT-ENDPOINT RECTANGLE RULE, local error O(Δt²), and collapses the
# whole iteration to first order however good the scheme is. Measured before the move: IFLowStorageRK3
# gave 1.02 under this forcing against 2.995 unforced, while `Linear` — the same code path, the same
# exponent, differing only in that its A is genuinely steady — kept 2.987. That contrast is the proof.
# It goes through the per-stage source instead, where the scheme's own order conditions apply.
uses_steady_linear_rate(::ConstantPower) = false

# The amplitude A that injects `injection_rate` into the band, evaluated AT THE FIELD IT IS GIVEN.
# Shared by `ConstantPower` and `VarianceController`, which differ only in what A is asked to hold.
# `strategy` names the caller in the warning, and keys the warning's dedup budget (`_id`), so an
# inert velocity forcing does not swallow the one warning a later inert scalar forcing would emit —
# `maxlog` dedups by log-statement identity, which a shared helper would otherwise collapse.
function _injection_amplitude(injection_rate, band_observable, whole_observable, strategy::Symbol)
  # TurTLE guards the same division with `if (energy_in_shell < 10*eps) energy_in_shell = 1`, a
  # machine-epsilon-relative floor substituting a benign denominator rather than skipping the step.
  if _band_is_empty(band_observable, whole_observable)
    @warn "$strategy: the forced band is empty (band observable $band_observable against a " *
          "whole-field $whole_observable): the amplitude is clamped to zero and the forcing is " *
          "inert until content reaches the band" maxlog = 1 _id = Symbol(:empty_band_, strategy)
    return 0.0
  end
  return injection_rate / (2 * band_observable)
end


function add_forcing_source!(forcing::ConstantPower, forcing_state, N̂, field, domain::FixedDomain,
                             diffusivity::Real)
  T = field_scalar_type(N̂)
  # One fused traversal answers the band observable AND the whole-field scale the relative
  # empty-band floor divides against — same crossing count as the bare band read.
  band_raw, whole_raw = weighted_inner(field, (forcing.band, domain.unit_kernel))
  band_observable = _target_factor(field) * band_raw                              # at the STAGE state
  amplitude = _injection_amplitude(forcing.injection_rate, band_observable,
                                   _target_factor(field) * whole_raw, :ConstantPower)
  # N̂ ← N̂ + A·𝟙_band·field, the band-limited linear forcing as an explicit source. `convolve!`'s
  # α/β form accumulates in place, so this costs one fused pass and no scratch.
  convolve!(N̂, field, forcing.band, T(amplitude), one(T))
  return N̂
end


"""
    StochasticOU(domain; forcing_variance, correlation_time, lowest_shell = 1,
                 highest_shell = 2, seed = 42)

The stochastic forcing of Eswaran & Pope (1988,
[*An examination of forcing in direct numerical simulations of turbulence*](https://doi.org/10.1016/0045-7930%2888%2990013-8),
*Computers & Fluids* **16**, 257–278), built on the [`FixedDomain`](@ref) `domain`: a random term,
correlated over a finite time, added to the right-hand side on a band of low wavenumbers.

Use it when the forcing must not depend on the flow it drives. Every other strategy here measures the
field it forces and sets its amplitude from that measurement; this one draws from a random process
instead. The price is that the energy it injects fluctuates rather than being held — take
[`ConstantPower`](@ref) or [`VarianceController`](@ref) when a run needs the injection or the variance
held at a value.

Its strength is `forcing_variance`, the stationary mean square
``\\sigma^{2} = \\langle\\lvert\\boldsymbol{f}\\rvert^{2}\\rangle`` of the term added: an acceleration
when it drives the velocity, a rate of change of ``\\varphi`` when it drives the scalar. It is **not**
the variance of the field itself, which is what `VarianceController` holds.

The forcing lives on the band's Fourier modes — the integer shells `lowest_shell` to `highest_shell` in
units of the box's fundamental ``\\kappa_0 = 2\\pi/L``:

```math
\\boldsymbol{f}(\\boldsymbol{x}, t) = \\sum_{\\boldsymbol{\\kappa}} \\boldsymbol{a}_{\\boldsymbol{\\kappa}}(t) e^{\\mathrm{i}\\boldsymbol{\\kappa}\\cdot\\boldsymbol{x}},
```

where each amplitude ``\\boldsymbol{a}_{\\boldsymbol{\\kappa}}`` is an independent complex
Ornstein–Uhlenbeck process with correlation time ``T_L``. When the forced field is the velocity, each
amplitude is drawn transverse to its own ``\\boldsymbol{\\kappa}``, so the force is divergence-free.
``\\sigma^{2}`` is shared equally among the band's modes and their independent components.

Once per step every amplitude takes the process's exact transition over the step ``\\Delta t``,

```math
\\boldsymbol{a}_{\\boldsymbol{\\kappa}} \\leftarrow \\alpha \\boldsymbol{a}_{\\boldsymbol{\\kappa}} + \\sqrt{1 - \\alpha^{2}} \\boldsymbol{\\xi}_{\\boldsymbol{\\kappa}},
\\qquad \\alpha = e^{-\\Delta t / T_L},
```

with ``\\boldsymbol{\\xi}`` a fresh draw from the stationary distribution, so the statistics are exact for
any step, a step the CFL condition varies included. The process starts from a stationary draw rather
than from zero.

How much energy that injects depends on how the force and the field line up. Over a correlation time
the force builds the very velocity it then does work against, so while ``T_L`` is short against the
large-eddy turnover time the mean injection rate is close to ``\\sigma^{2} T_L`` into the kinetic energy
``k``, and to ``2\\sigma^{2} T_L`` into the scalar variance ``\\langle\\varphi^{2}\\rangle``. Both are
estimates the run drifts around, not values anything holds: choose `forcing_variance` from the
dissipation rate the run should sustain, and measure what it actually injects.

The forcing is held fixed over a step and added at every stage, as [`add_forcing_source!`](@ref) does for
every additive source. For a given sequence of amplitudes the field then advances at the scheme's
order, but the forcing itself is resolved in time only step by step, so ``T_L`` should span many steps.

The arguments are:
- `domain` — the `FixedDomain` of the run this forcing drives.
- `forcing_variance` — the stationary mean square ``\\sigma^{2}`` of the added term, as above.
- `correlation_time` — the correlation time ``T_L`` of each amplitude.
- `lowest_shell = 1`, `highest_shell = 2` — the forced band, as integer shells in units of ``\\kappa_0``;
  every mode of the band must lie inside the dealias cutoff.
- `seed = 42` — fixes the random stream. A velocity and a scalar forcing given the same seed still draw
  independent streams.

The process lives in the run's state, not in this strategy. A run keeps it as a
[`StochasticOUState`](@ref) — the `modeled` entry of its
[`ResolvedFields`](@ref GBGIsotropicTurbulence.State.ResolvedFields) — held on a small grid of its own
over the same box, large enough to carry the band and no larger, so the whole forcing costs a few
kilobytes and runs no transform at the resolution of the run. A checkpoint of the state therefore
resumes the same realization. This strategy holds its parameters and the scratch of one
draw, so one instance may drive both fields.

A `ResolvedFields` built by hand that carries no state for this forcing is refused: preparing it
throws an `ArgumentError` rather than leave the run unforced without saying so. A `Simulation` builds
it for you.

!!! warning "The band must lie inside the dealias cutoff"
    A forcing that multiplies the field injects nothing where the dealiasing mask holds the modes
    empty, but this forcing is added after the mask and would fill them. Construction therefore throws
    an `ArgumentError` for a band reaching past the cutoff, where the other strategies only warn.

# Fields
- `forcing_variance`, `correlation_time`, `seed`, `lowest_shell`, `highest_shell` — the parameters above.
- `companion` — the coarse `FixedDomain` over the same box the process is held on: the smallest grid
  whose modes cover the band, so the whole forcing costs a few kilobytes and no transform at the run's
  own resolution.
- `band` — the shell band, as a kernel on the companion.
- `velocity_scratch`, `scalar_scratch` — one draw's scratch for each kind of forced field: a physical
  and a spectral companion field, the host array the draw is made in, and the scale that turns a
  unit-variance draw into the stationary distribution.
- `rng` — the random-number generator, reseeded before every draw from the seed, the state's draw
  count, and which field is being forced, which is what makes a velocity and a scalar forcing of one
  seed independent. Scratch, not state.
"""
struct StochasticOU{T, D, K, V, S} <: AbstractForcing
  forcing_variance::T                    # σ²: the stationary mean square of the added term
  correlation_time::T                    # T_L
  seed::Int                              # the stream's seed — a defining parameter, persisted
  lowest_shell::Int                      # the band's shell bounds
  highest_shell::Int
  companion::D                           # the coarse FixedDomain over the same box
  band::K                                # the shell band on the companion
  velocity_scratch::V                    # one draw's scratch: (physical, spectral, host draw, scale)
  scalar_scratch::S
  rng::Xoshiro                           # scratch: reseeded from (seed, draws, field) before every draw
end


"""
    StochasticOUState

A [`StochasticOU`](@ref) forcing's evolving state holds two things: the force itself, as a field in
spectral representation on the forcing's companion grid, and the number of increments drawn so far.
[`initial_forcing_state`](@ref) creates it, [`prepare_forcing!`](@ref) advances it in place every step,
and a run keeps it as the `modeled` entry of
[`ResolvedFields`](@ref GBGIsotropicTurbulence.State.ResolvedFields) for the forced field. There is no
reason to build one by hand.

Holding the force as an ordinary field is what keeps the rest simple. The draw is made real-valued and
then transformed, so its spectrum satisfies the reality condition by construction; the transverse
projection is the field library's; and the state is saved by the same library's field persistence.

The amplitudes are physical — the coefficients of
``e^{\\mathrm{i}\\boldsymbol{\\kappa}\\cdot\\boldsymbol{x}}`` in the force, with no transform
normalization — so neither the state nor a checkpoint of it depends on either grid's size. The draw
count, with the forcing's seed, fixes every later draw.

# Fields
- `process` — the force in spectral representation on the companion grid.
- `draws` — the number of increments drawn so far, the stationary start included.
"""
mutable struct StochasticOUState{F}
  process::F                             # the force f̂ on the companion grid — physical amplitudes
  draws::Int                             # increments drawn so far — the stream's position
end


# The draw scratch of one kind of forced field, and the scale that makes a drawn increment stationary.
# A unit-variance real draw on the companion carries mean square NC over the whole grid; the band keeps
# the fraction M/N³ of it (M the band's lattice modes, counted once here), and the transverse projection
# keeps two components of three, so E⟨ξ,ξ⟩ = 2M/N³ for the velocity and M/N³ for the scalar. Dividing by
# its square root is what the expectation, rather than each draw's realized norm, sets — the realized
# norm would fix every increment's size, which is not the independent Gaussian modes the method defines,
# and would cost a device-to-host reduction every step.
function _ou_slots(companion::FixedDomain, modes::Integer, ::Val{R}) where {R}
  physical = R == 1 ? new_vector_field_physical(companion) : new_scalar_field_physical(companion)
  spectral = R == 1 ? new_vector_field_spectral(companion) : new_scalar_field_spectral(companion)
  T = _real_type(companion)
  points = prod(companion.grid.grid_size)
  retained = R == 1 ? 2 * modes : modes
  return (physical = physical, spectral = spectral,
          draws = Array{T}(undef, size(field_data(physical))),
          scale = one(T) / sqrt(T(retained) / T(points)))
end

# The band's lattice modes, counted over the whole companion spectrum (both members of every pair).
function _count_band_modes(companion::FixedDomain, low::Real, high::Real)
  n = companion.grid.grid_size[1]
  k0 = 2π / companion.grid.domain_size[1]
  half = n ÷ 2
  return count(low <= k0 * sqrt(i^2 + j^2 + k^2) <= high
               for i in -half:half-1, j in -half:half-1, k in -half:half-1)
end


function StochasticOU(domain::FixedDomain; forcing_variance::Real, correlation_time::Real,
                      lowest_shell::Integer = 1, highest_shell::Integer = 2, seed::Integer = 42)
  # Cast to the domain's element type FIRST, so the guards certify the stored values. Both are
  # documented non-negative: every draw is scaled by the variance's square root, so a negative one
  # surfaced as a bare `DomainError` from `sqrt` two frames away, naming nothing the caller had typed.
  T = _real_type(domain)
  forcing_variance = T(forcing_variance)
  correlation_time = T(correlation_time)
  (isfinite(forcing_variance) && forcing_variance >= 0) ||
    throw(ArgumentError("`forcing_variance` must be finite and non-negative, got $forcing_variance: " *
                        "it is the stationary mean square of the term the forcing adds, and its " *
                        "square root sets the amplitude of every draw"))
  (isfinite(correlation_time) && correlation_time > 0) ||
    throw(ArgumentError("`correlation_time` must be finite and positive, got $correlation_time: " *
                        "it is the Ornstein–Uhlenbeck relaxation time T_L, and each step decays " *
                        "the amplitudes by exp(−Δt/T_L)"))
  _check_shells(lowest_shell, highest_shell)
  L = domain.grid.domain_size[1]
  k0 = 2π / L
  low, high = (lowest_shell - 0.5) * k0, (highest_shell + 0.5) * k0
  # The source is added AFTER the dealiasing mask, so a mode past the cutoff would be filled where the
  # nonlinear term assumes nothing lives. Refused, not warned: the multiplicative strategies' "inert
  # there" warning is false for an additive force.
  κ_max = max_retained_wavenumber(domain)
  high <= κ_max ||
    throw(ArgumentError("the forcing band (shells $(lowest_shell)–$(highest_shell)) reaches " *
                        "|κ| = $(round(high, digits = 3)), past the dealias cutoff " *
                        "$(round(κ_max, digits = 3)); an additive force would fill modes the " *
                        "dealiasing holds empty. Lower the shells, or enlarge the grid."))
  # The companion grid: even, and large enough that the band lies strictly below its Nyquist
  # frequency, whose modes a transfer between resolutions cannot carry (one coarse Nyquist mode
  # describes a wave the finer grid splits in two).
  companion = FixedDomain(; grid_points_per_axis = 2 * (Int(highest_shell) + 1), side_length = L,
                          dealiasing = TwoThirds(), element_type = T, array_type = domain.storage_family)
  modes = _count_band_modes(companion, low, high)
  modes > 0 ||
    throw(ArgumentError("the band (shells $(lowest_shell)–$(highest_shell)) holds no lattice " *
                        "wavevector, so the forcing would drive nothing"))
  return StochasticOU(forcing_variance, correlation_time, Int(seed), Int(lowest_shell), Int(highest_shell),
                      companion, spectral_band(companion.multipliers, low, high),
                      _ou_slots(companion, modes, Val(1)), _ou_slots(companion, modes, Val(0)),
                      Xoshiro(42))
end


_ou_slots(ou::StochasticOU, field) =
  field_tensor_order(field) == 1 ? ou.velocity_scratch : ou.scalar_scratch

# The key of one draw: the seed, the draw's position in the stream, and which field is forced, packed
# into one 128-bit integer — exact and collision-free, so the stream is a pure function of the three and
# a state resumes it from its draw count alone. Widened BEFORE shifting: `Int << 64` is zero in Julia.
_draw_key(seed::Int, draws::Int, order::Int) =
  (UInt128(reinterpret(UInt64, seed)) << 64) | (UInt128(draws) << 2) | UInt128(order)

# One exact Ornstein–Uhlenbeck transition, a ← α a + √(σ²(1 − α²)) ξ, with ξ drawn from the stationary
# distribution: a real Gaussian field on the companion grid, transformed, cut to the band, and — for the
# velocity — projected transverse to κ. Drawing in the physical representation is what keeps ξ isotropic
# and its spectrum a real field's by construction; the draw is made on the host, so the realization
# follows the seed rather than the backend's generator.
function _advance_process!(ou::StochasticOU{T}, state::StochasticOUState, field, α) where {T}
  slots = _ou_slots(ou, field)
  Random.seed!(ou.rng, _draw_key(ou.seed, state.draws, field_tensor_order(field)))
  randn!(ou.rng, slots.draws)
  copyto!(field_data(slots.physical), slots.draws)
  to_spectral!(slots.spectral, slots.physical, ou.companion.transform_plans)
  convolve!(slots.spectral, slots.spectral, ou.band)
  field_tensor_order(field) == 1 &&
    helmholtz_projection!(slots.spectral, slots.spectral, ou.companion.multipliers)
  combine!(state.process, α, state.process,
           slots.scale * sqrt(ou.forcing_variance * (one(T) - α^2)), slots.spectral)
  state.draws += 1
  return state
end


function initial_forcing_state(ou::StochasticOU{T}, field, domain::FixedDomain) where {T}
  process = field_tensor_order(field) == 1 ? new_vector_field_spectral(ou.companion) :
                                             new_scalar_field_spectral(ou.companion)
  return _advance_process!(ou, StochasticOUState(process, 0), field, zero(T))  # α = 0: stationary
end


# A `ResolvedFields` built by hand without the forcing's state would hand `nothing` here, and the generic
# do-nothing method would then leave the force at zero for the whole run — refused instead.
prepare_forcing!(::StochasticOU, ::Nothing, field, domain::FixedDomain, dt::Real) =
  throw(ArgumentError("a StochasticOU was prepared with no forcing state: this field's `modeled` " *
                      "entry in the `ResolvedFields` is `nothing`. Start one with " *
                      "`initial_forcing_state(forcing, field, domain)` and pass it in the " *
                      "`ResolvedFields`, or let `Simulation` build them."))

function prepare_forcing!(ou::StochasticOU{T}, state::StochasticOUState, field, domain::FixedDomain,
                          dt::Real) where {T}
  field_tensor_order(state.process) == field_tensor_order(field) &&
    field_grid(state.process).grid_size == ou.companion.grid.grid_size ||
    throw(ArgumentError("this StochasticOUState holds a tensor-order-$(field_tensor_order(state.process)) " *
                        "process on a $(field_grid(state.process).grid_size[1])³ grid, but the forcing " *
                        "drives a tensor-order-$(field_tensor_order(field)) field and its companion grid " *
                        "is $(ou.companion.grid.grid_size[1])³; the state belongs to a different band " *
                        "or field"))
  _advance_process!(ou, state, field, exp(-T(dt) / ou.correlation_time))
  return nothing
end

# The force of the step, added where the run's own modes and the companion's coincide: the field
# library's transfer between resolutions, which costs the companion's size and never traverses the
# run's own field.
add_forcing_source!(ou::StochasticOU, state::StochasticOUState, N̂, field, domain::FixedDomain,
                    diffusivity::Real) = embed_modes!(N̂, state.process, 1, 1)


# Operator-free keyword constructors: capture the parameters now and build the forcing once the
# domain exists (via `DeferredForcing`), so a case can name its forcing before the grid is built —
# `ConstantPower(injection_rate = 0.1)` — with `Simulation` supplying the domain.
Linear(; rate::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  DeferredForcing(domain -> Linear(domain; rate, lowest_shell, highest_shell))

ConstantPower(; injection_rate::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  DeferredForcing(domain -> ConstantPower(domain; injection_rate, lowest_shell, highest_shell))

VarianceRescaling(; target::Real, over::Symbol, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  DeferredForcing(domain -> VarianceRescaling(domain; target, over, lowest_shell, highest_shell))

VarianceController(; target::Real, gain::Real = 1, turnover_time = nothing,
                   lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  DeferredForcing(domain -> VarianceController(domain; target, gain, turnover_time,
                                               lowest_shell, highest_shell))

StochasticOU(; forcing_variance::Real, correlation_time::Real,
             lowest_shell::Integer = 1, highest_shell::Integer = 2, seed::Integer = 42) =
  DeferredForcing(domain -> StochasticOU(domain; forcing_variance, correlation_time, lowest_shell,
                                         highest_shell, seed))




# ————————————————————————————————————————————————————————————————————————————————————————————————
# Display (the convention is stated once, at `SimulationDomain`'s display section). A forcing is
# its parameters and the shell band they act over, then the band kernel it built on the domain —
# through the field library's own `show`, which spells the grid, element type, and storage the
# kernel was derived on. The parameters print at full precision, never rounded.

_show_shells(io::IO, forcing) = print(io, "shells ", forcing.lowest_shell, " to ", forcing.highest_shell)

function Base.show(io::IO, forcing::ConstantPower)
  print(io, "ConstantPower(injection_rate ", forcing.injection_rate, ", ")
  _show_shells(io, forcing)
  print(io, ", ", forcing.band, ")")
end

function Base.show(io::IO, forcing::Linear)
  print(io, "Linear(rate ", forcing.rate, ", ")
  _show_shells(io, forcing)
  print(io, ", indicator ", _storage_family_name(forcing.indicator), "{", eltype(forcing.indicator), "} ")
  _show_shape(io, size(forcing.indicator))
  print(io, " coefficients)")
end

function Base.show(io::IO, forcing::VarianceRescaling)
  print(io, "VarianceRescaling(target ", forcing.target, " over ", repr(forcing.over), ", ")
  _show_shells(io, forcing)
  print(io, ", ", forcing.band, ")")
end

function Base.show(io::IO, forcing::VarianceController)
  print(io, "VarianceController(target ", forcing.target, ", gain ", forcing.gain, ", turnover_time ",
        forcing.turnover_time, forcing.turnover_time_derived ? " (derived from the target)" : "", ", ")
  _show_shells(io, forcing)
  print(io, ", ", forcing.band, ")")
end

function Base.show(io::IO, forcing::StochasticOU)
  print(io, "StochasticOU(forcing_variance ", forcing.forcing_variance, ", correlation_time ", forcing.correlation_time,
        ", seed ", forcing.seed, ", ")
  _show_shells(io, forcing)
  print(io, ", on a ", forcing.companion.grid.grid_size[1], "³ companion grid, ", forcing.band, ")")
end

Base.show(io::IO, state::StochasticOUState) =
  print(io, "StochasticOUState(", state.process, ", ", state.draws,
        state.draws == 1 ? " draw" : " draws", ")")

# The closure has no readable form; the display says what the value is waiting for.
Base.show(io::IO, ::DeferredForcing) = print(io, "DeferredForcing(awaiting a domain)")



# ————————————————————————————————————————————————————————————————————————————————————————————————
# HDF5 persistence. The bare generics live here so the docstrings and the docs build work without
# HDF5 in the environment; the methods live in the `GBGIsotropicTurbulenceHDF5Ext` weak-dependency
# extension, loaded automatically alongside the HDF5 package (the arrangement the field library's
# persistence pairs established).

export write_forcing, read_forcing


"""
    write_forcing(parent::HDF5.H5DataStore, name::AbstractString,
                  forcing::AbstractForcing)

Write the forcing strategy `forcing` (an [`AbstractForcing`](@ref)) under `parent` as one
self-describing HDF5 group — its defining parameters only; every derived object (a band kernel, an
indicator array) is rebuilt from them on read. What a strategy evolves is not a parameter: the
process of a [`StochasticOU`](@ref) lives in the run's state and is stored by
[`write_state`](@ref GBGIsotropicTurbulence.State.write_state), so a reloaded strategy continues the
same realization when the state is restored with it. A
[`DeferredForcing`](@ref) is refused — resolve it on a domain first. Available once the `HDF5`
package is loaded; the caller owns the file.

The arguments are:
- `parent` — the open HDF5 file or group to write under.
- `name` — the created group's name.
- `forcing` — the built strategy to record.

Returns the created group. Reload with [`read_forcing`](@ref).
"""
function write_forcing end


"""
    read_forcing(parent::HDF5.H5DataStore, name::AbstractString,
                 domain::FixedDomain) -> AbstractForcing

Rebuild a forcing strategy from the group [`write_forcing`](@ref) wrote, through its ordinary
keyword constructor on `domain` (a [`FixedDomain`](@ref)) — the derived band kernel or indicator
is rebuilt, never read. A group not written by `write_forcing`, or written by a newer schema
version, is refused with an `ArgumentError`. Available once the `HDF5` package is loaded.

The arguments are:
- `parent` — the open HDF5 file or group holding the forcing group.
- `name` — the group's name.
- `domain` — the `FixedDomain` the strategy is rebuilt on.
"""
function read_forcing end


end # module Forcing
