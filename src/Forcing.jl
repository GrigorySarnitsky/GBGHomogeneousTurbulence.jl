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
# force field to the RHS — is a separate, stateful mechanism (`StochasticOU`), advanced once per step.

"""
    Forcing

The interchangeable energy-injection strategies — one implementation each serving both the velocity
and the scalar through tensor-order-generic field operators. A strategy acts on the step through up
to four hook methods, each defaulting to doing nothing, called in the order listed:

- [`AbstractForcing`](@ref) — the strategy supertype, defining the four-hook lifecycle.
- [`prepare_forcing!`](@ref) — advance the forcing's own internal state, once per step.
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
- [`DeferredForcing`](@ref) — the operator-free keyword form of a strategy, materialized once the
  [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) has built the domain; a
  construction-time object, not a lifecycle hook.
- [`write_forcing`](@ref) / [`read_forcing`](@ref) — a strategy's HDF5 persistence: its defining
  parameters as one self-describing group (available once `HDF5` is loaded).

Which keywords carry defaults follows one test: **does the value come from the method, or from this
run?** A canonical band (`lowest_shell = 1`, `highest_shell = 2`) is the method's and defaults; what
a run holds fixed — `target`, `rate`, `injection_rate`, `over` — has no canonical value and is
required. A default at this layer never hides a choice you needed to make; the run layer's
convenience default (a controller targeting the initial kinetic energy) is that layer's own,
documented choice.

A band reaching above the dealias cutoff is inert there — the mask holds those modes empty, and a
band forcing multiplies the field — so construction warns about it.

The two fields are forced **independently**:
[`FlowConditions`](@ref GBGIsotropicTurbulence.Generator.FlowConditions) takes a separate
`velocity_forcing` and `scalar_forcing`, so a run can force one, both, or neither.

"""
module Forcing

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, max_wavenumber, new_scalar_field_spectral, new_vector_field_spectral, new_scalar_field_physical, new_vector_field_physical

export AbstractForcing, DeferredForcing, NoForcing, VarianceRescaling, VarianceController,
       Linear, ConstantPower,
       set_forcing_rate!, uses_steady_linear_rate, project_forcing!, prepare_forcing!, add_forcing_source!


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

Supertype of the energy-injection strategies. A strategy may implement any of
[`prepare_forcing!`](@ref) (advance the strategy's **own** internal state — a stochastic forcing's
random process, say — never the simulation state), [`set_forcing_rate!`](@ref)
(a rate that is **constant in time**, folded into the integrating factor — a strategy implementing it
**must** also declare [`uses_steady_linear_rate`](@ref), or it is never given a rate array to fill),
[`add_forcing_source!`](@ref) (an additive per-stage source), and [`project_forcing!`](@ref) (a
post-step projection); all default to doing nothing, and a strategy owns whatever scratch its hooks
need.

The hooks form **one per-step lifecycle with a fixed order**: `prepare_forcing!` and
`set_forcing_rate!` run once before the Runge–Kutta stages (whatever internal state a later hook
consumes must be prepared here), `add_forcing_source!` runs at every stage, and `project_forcing!` runs after the completed
step. The rate and the source are two channels of **one** forcing term — the *steady* part is folded
exactly into the integrating factor, the remainder is added at the stages — so a single strategy may
legitimately use both.

Which channel a rate may take is decided by steadiness in time, **not** linearity in the field: the
integrating factor holds a rate fixed for the whole step, so one re-solved from the state must go
through `add_forcing_source!` instead. The declaration is cross-checked when the generator is
built, not trusted: a strategy that implements `set_forcing_rate!` without declaring
`uses_steady_linear_rate` is refused with an `ArgumentError`. Steadiness itself remains the
author's promise — no construction-time check can watch a rate over time.

Each mutating hook returns its mutated argument (`set_forcing_rate!` the rate,
`add_forcing_source!` the right-hand side, `project_forcing!` the field); `prepare_forcing!` returns
`nothing`.

!!! warning "One instance per forced field, for a strategy that carries state"
    A strategy holding per-field scratch or a random stream must not drive both fields from one
    instance, or their bookkeeping is conflated;
    [`FlowConditions`](@ref GBGIsotropicTurbulence.Generator.FlowConditions) throws an
    `ArgumentError` rather than let that happen. A stateless strategy — one whose whole content is
    its band and its target — has nothing to conflate and may be shared.
"""
abstract type AbstractForcing end


"""
    DeferredForcing

A deferred forcing. The operator-free keyword constructors

    Linear(; rate, lowest_shell = 1, highest_shell = 2)
    ConstantPower(; injection_rate, lowest_shell = 1, highest_shell = 2)
    VarianceRescaling(; target, over, lowest_shell = 1, highest_shell = 2)
    VarianceController(; target, gain = 1, turnover_time = nothing, lowest_shell = 1, highest_shell = 2)

each return a `DeferredForcing` capturing **the same keywords, with the same defaults**, as their
`domain`-taking forms documented on each strategy; it is materialized into the concrete
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
    prepare_forcing!(forcing, field, domain, dt) -> nothing

Update the strategy `forcing`'s internal state once per step, before the Runge–Kutta stages, from the
start-of-step `field` (in spectral representation) and the timestep `dt`, on the [`FixedDomain`](@ref)
`domain`. A stateful forcing owns whatever scratch this needs. The default does nothing.
"""
prepare_forcing!(::AbstractForcing, field, domain::FixedDomain, dt::Real) = nothing


"""
    add_forcing_source!(forcing, N̂, field, domain, diffusivity) -> N̂

Add the strategy `forcing`'s additive source to the assembled right-hand side `N̂`, on the
[`FixedDomain`](@ref) `domain`. The default does nothing.

This is the route a **state-dependent** forcing must take. It is called at every Runge–Kutta stage
and is handed that stage's own `field` — the velocity ``\\hat{\\boldsymbol{u}}`` or the scalar
``\\hat{\\varphi}`` in spectral representation, whichever this forcing drives — together with the
`diffusivity` acting on it (``\\nu`` for the velocity, ``\\varkappa`` for the scalar). A strategy
whose amplitude depends on the current state can therefore measure that state exactly where the
scheme will integrate the result.

The alternative costs accuracy: a state-dependent rate frozen once per step is the left-endpoint
rectangle rule on ``\\int A\\,\\mathrm{d}t``, dropping the scheme to first order however good it is.
Only a steady rate may go through [`set_forcing_rate!`](@ref).

Measuring the state costs one blocking device-to-host transfer **at every stage** — a single fused
multi-weight reduction answers [`VarianceController`](@ref)'s three weighted sums together,
[`ConstantPower`](@ref) reads its band (and the empty-band floor's scale) the same fused way, and
[`Linear`](@ref) pays none. That is the price of the order this route preserves.

!!! warning "The source is accumulated, never assigned"
    Every stage adds into an `N̂` the generator has already filled with the nonlinear term, so an
    implementation must **add** its contribution and must not overwrite the buffer.
"""
add_forcing_source!(::AbstractForcing, N̂, field, domain::FixedDomain, diffusivity::Real) = N̂


# An annular shell band-pass kernel for shells `lowest ≤ |k| ≤ highest` (integer shells of 2π/L).
# The shell arguments are validated HERE, once for all four band forcings, so the thrown message
# names the argument the caller typed — the backend's own guard fires on the padded band edges
# ("band edges must satisfy 0 <= low", with our −0.5 padding visible), which reads as internals.
function _shell_band(domain::FixedDomain, lowest::Integer, highest::Integer)
  lowest >= 1 ||
    throw(ArgumentError("`lowest_shell` must be at least 1, got $lowest: shell 0 is the mean " *
                        "(κ = 0) mode, which a band forcing cannot legitimately drive — it carries " *
                        "the box's total momentum (or the scalar's mean), not turbulence"))
  highest >= lowest ||
    throw(ArgumentError("`highest_shell` must be at least `lowest_shell`, got $highest < $lowest: " *
                        "the band would be empty and the forcing would silently do nothing"))
  k0 = 2π / domain.grid.domain_size[1]
  # A band above the dealias cutoff is INERT, not harmful: the mask keeps those modes empty, and
  # every band forcing is field-proportional, so it multiplies zero forever. Measured: a Linear on
  # shells 6–7 at N = 16 (cutoff shell ≈ 5.3) injected exactly nothing over 100 steps. Legal — a
  # marginal band is a legitimate choice — but it cannot be silent, or a run decays with its forcing
  # apparently on. (An ADDITIVE forcing would genuinely inject there; re-adding `StochasticOU` must
  # keep this warning in front of it.)
  κ_max = max_wavenumber(domain)
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
  # The target is an energy or a variance — both non-negative — and the rescale takes its square
  # root, so a negative value surfaced as a bare `DomainError` out of `sqrt` naming nothing.
  target >= 0 ||
    throw(ArgumentError("VarianceRescaling `target` must be non-negative, got $target: it is the " *
                        "kinetic energy or scalar variance the forcing holds, and the rescale " *
                        "takes its square root"))
  return VarianceRescaling(_shell_band(domain, lowest_shell, highest_shell), float(target), over,
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
  return Linear(indicator, float(rate), Int(lowest_shell), Int(highest_shell))
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
  that sets ``\\nu`` explicitly against a very different regime should pass its own value.
- `lowest_shell = 1`, `highest_shell = 2` — the forced band, in integer shells of ``2\\pi/L``.

!!! note "The settling time, not the gain, is the physical parameter"
    Only the ratio ``t_\\ell/G`` is observable: it is how long the variance takes to return after a
    disturbance. The two are kept separate because that is how the source states them.

# Fields
- `band` — the band-pass kernel, lazy; the controller convolves against it and stores nothing.
- `target`, `gain`, `turnover_time` — ``k_\\infty``, ``G`` and ``t_\\ell``.
- `lowest_shell`, `highest_shell` — the forced band's shell bounds: the parameters `band` is derived
  from.
"""
struct VarianceController{K, T} <: AbstractForcing
  band::K
  target::T
  gain::T
  turnover_time::T
  lowest_shell::Int    # the band's shell bounds — the parameters `band` is derived from
  highest_shell::Int
end


function VarianceController(domain::FixedDomain; target::Real, gain::Real = 1,
                            turnover_time = nothing, lowest_shell::Integer = 1,
                            highest_shell::Integer = 2)
  # Finite AND positive, as the codebase's other positive-scalar guards read: `Inf` passes `> 0` and
  # then propagates a NaN amplitude into the right-hand side, which surfaces as a blown-up run far
  # from the constructor that accepted it.
  (isfinite(target) && target > 0) ||
    throw(ArgumentError("`target` must be finite and positive, got $target: it is the variance the " *
                        "controller holds, and the rate divides by the band's own variance"))
  (isfinite(gain) && gain >= 0) ||
    throw(ArgumentError("`gain` must be finite and non-negative, got $gain: a negative gain makes " *
                        "the restoring term push the variance AWAY from the target. `gain = 0` is " *
                        "the bare marginal law — no restoring at all — and is allowed."))
  band = _shell_band(domain, lowest_shell, highest_shell)
  # t_ℓ = 2k_∞/3ε_∞, the large-eddy turnover time, with ε_∞ the stationary estimate for this box —
  # the same estimate the viscosity derivation uses, so the two agree on what "stationary" means.
  tℓ = turnover_time === nothing ?
       2 * float(target) / (3 * _stationary_dissipation_estimate(float(target),
                                                                 domain.grid.domain_size[1])) :
       turnover_time
  (isfinite(tℓ) && tℓ > 0) ||
    throw(ArgumentError("`turnover_time` must be finite and positive, got $turnover_time"))
  # Promote the three together, and `float` only `target` — which is what fixes the element type.
  # Flooring each argument separately re-imports Float64 through the back door, because `float(1)` on
  # the integer default gain is a Float64 and promotion then carries the whole struct up with it.
  return VarianceController(band, promote(float(target), gain, tℓ)...,
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


function add_forcing_source!(forcing::VarianceController, N̂, field, domain::FixedDomain,
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
  if _band_is_empty(band, whole)
    @warn "VarianceController: the forced band is empty (band observable $band against a " *
          "whole-field $whole): the amplitude is clamped to zero and the controller is inert " *
          "until content reaches the band" maxlog = 1
    amplitude = 0.0
  else
    amplitude = (dissipation - restoring) / (2 * band_variance)
  end
  convolve!(N̂, field, forcing.band, T(amplitude), one(T))
  return N̂
end

function ConstantPower(domain::FixedDomain; injection_rate::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2)
  # No materialized indicator: it existed only to fill the integrating-factor rate array, and this
  # forcing no longer uses that route. The lazy kernel is convolved against directly, so a
  # `ConstantPower` run now carries NO field-scale storage of its own — two arrays fewer.
  return ConstantPower(_shell_band(domain, lowest_shell, highest_shell), float(injection_rate),
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
function _injection_amplitude(injection_rate, band_observable, whole_observable)
  # TurTLE guards the same division with `if (energy_in_shell < 10*eps) energy_in_shell = 1`, a
  # machine-epsilon-relative floor substituting a benign denominator rather than skipping the step.
  if _band_is_empty(band_observable, whole_observable)
    @warn "the forced band is empty (band observable $band_observable against a whole-field " *
          "$whole_observable): the amplitude is clamped to zero and the forcing is inert until " *
          "content reaches the band" maxlog = 1
    return 0.0
  end
  return injection_rate / (2 * band_observable)
end


function add_forcing_source!(forcing::ConstantPower, N̂, field, domain::FixedDomain,
                             diffusivity::Real)
  T = field_scalar_type(N̂)
  # One fused traversal answers the band observable AND the whole-field scale the relative
  # empty-band floor divides against — same crossing count as the bare band read.
  band_raw, whole_raw = weighted_inner(field, (forcing.band, domain.unit_kernel))
  band_observable = _target_factor(field) * band_raw                              # at the STAGE state
  amplitude = _injection_amplitude(forcing.injection_rate, band_observable, _target_factor(field) * whole_raw)
  # N̂ ← N̂ + A·𝟙_band·field, the band-limited linear forcing as an explicit source. `convolve!`'s
  # α/β form accumulates in place, so this costs one fused pass and no scratch.
  convolve!(N̂, field, forcing.band, T(amplitude), one(T))
  return N̂
end


"""
    StochasticOU(domain; variance, correlation_time, lowest_shell = 1,
                 highest_shell = 2, seed = 0)

Stochastic forcing — Eswaran & Pope (1988,
[*An examination of forcing in direct numerical simulations of turbulence*](https://doi.org/10.1016/0045-7930%2888%2990013-8),
*Computers & Fluids* **16**, 257–278) — built on the
[`FixedDomain`](@ref) `domain`: each forced
Fourier mode in the band — the integer shells `lowest_shell` to `highest_shell`, in units of the
box's fundamental ``2\\pi/L`` — carries an
independent complex Ornstein–Uhlenbeck process, advanced once per step by the exact transition

```math
\\hat f \\leftarrow \\alpha \\hat f + \\sqrt{\\sigma^{2}(1-\\alpha^{2})} \\xi,
\\qquad \\alpha = \\exp(-\\Delta t / T_L),
```

with correlation time ``T_L = \\texttt{correlation\\_time}``, stationary forcing variance
``\\sigma^{2} = \\texttt{variance}`` (the stationary ``\\langle\\lvert f\\rvert^{2}\\rangle``), and
``\\xi`` a unit-variance, band-limited random field. The increment ``\\xi`` is generated as a real
physical field, transformed, and band-limited — guaranteeing a valid real field with no
Hermitian-symmetry bookkeeping — and, when forcing the velocity (a vector field), Leray-projected so
the forcing is divergence-free. The frozen ``\\hat f`` is added to the right-hand side at each stage
(see [`add_forcing_source!`](@ref)), so it integrates at the scheme's order. The `seed` (default 0) fixes
the random stream, so a forced run is reproducible.

The same type forces either the velocity or the scalar ``\\varphi``: it adapts to the field it is
given (a vector or scalar state, projected only for the velocity). The forcing owns its state and its
noise scratch — one field in physical and one in spectral representation, allocated on first use, so a
velocity-forcing instance holds two resident vector fields beside ``\\hat f``.

# Arguments
- `domain` — the `FixedDomain` the band and the noise scratch are built on.
- `variance` — the stationary forcing variance ``\\sigma^{2}``.
- `correlation_time` — the correlation time ``T_L`` of each mode's process.
- `lowest_shell = 1`, `highest_shell = 2` — the forced band, as integer shells in units of the box's
  fundamental ``2\\pi/L``.
- `seed = 0` — fixes the random stream, so a forced run is reproducible.

!!! note "The random increment is generated host-side"
    The random increment is generated host-side each step; on the GPU this is a portability-first
    choice, not yet a performance-tuned one.

# Fields
- `band` — the band-pass kernel for the noise.
- `correlation_time`, `variance` — ``T_L`` and ``\\sigma^{2}``.
- `rng` — the random stream, persisting across steps.
- `state`, `noise_physical`, `noise_spectral` — the evolving force ``\\hat{\\boldsymbol{f}}`` and
  its noise scratch, each `nothing` until first use.
- `lowest_shell`, `highest_shell` — the forced band's shell bounds: the parameters `band` is
  derived from.
"""
mutable struct StochasticOU{B, R, T} <: AbstractForcing
  band::B                                    # band-pass kernel for the noise
  correlation_time::T                        # T_L
  variance::T                                # σ²: stationary forcing variance ⟨|f|²⟩
  rng::R                                     # random stream (persists across steps)
  state::Union{Nothing, AbstractFieldSpectral}   # the OU forcing f̂ (allocated on first use)
  noise_physical::Union{Nothing, AbstractFieldPhysical}  # own noise scratch (allocated on first use)
  noise_spectral::Union{Nothing, AbstractFieldSpectral}
  lowest_shell::Int                          # the band's shell bounds — the parameters `band` is derived from
  highest_shell::Int
end

function StochasticOU(domain::FixedDomain; variance::Real, correlation_time::Real,
                      lowest_shell::Integer = 1, highest_shell::Integer = 2, seed::Integer = 0)
  # Both are documented non-negative and neither was checked: the variance's square root is taken
  # when the increment is scaled, so a negative one surfaced as a bare `DomainError` from `sqrt` two
  # frames away, naming nothing the caller had typed.
  variance >= 0 ||
    throw(ArgumentError("`variance` must be non-negative, got $variance: it is the stationary " *
                        "variance the process holds, and its square root sets the noise amplitude"))
  correlation_time > 0 ||
    throw(ArgumentError("`correlation_time` must be positive, got $correlation_time: it is the " *
                        "Ornstein–Uhlenbeck relaxation time τ, and the drift is −f/τ"))
  band = _shell_band(domain, lowest_shell, highest_shell)
  return StochasticOU(band, float(correlation_time), float(variance), MersenneTwister(seed),
                      nothing, nothing, nothing, Int(lowest_shell), Int(highest_shell))
end

_ou_state(::VectorFieldSpectral, domain) = new_vector_field_spectral(domain)
_ou_state(::ScalarFieldSpectral, domain) = new_scalar_field_spectral(domain)
_ou_noise(::VectorFieldSpectral, domain) = (new_vector_field_physical(domain), new_vector_field_spectral(domain))
_ou_noise(::ScalarFieldSpectral, domain) = (new_scalar_field_physical(domain), new_scalar_field_spectral(domain))
_ou_plans(::VectorFieldSpectral, domain) = domain.velocity_plans
_ou_plans(::ScalarFieldSpectral, domain) = domain.scalar_plans


function prepare_forcing!(ou::StochasticOU, field, domain::FixedDomain, dt::Real)
  T = real(eltype(field_data(field)))
  ou.state === nothing && (ou.state = _ou_state(field, domain))
  ou.noise_physical === nothing && ((ou.noise_physical, ou.noise_spectral) = _ou_noise(field, domain))
  noise_physical, noise_spectral, plans = ou.noise_physical, ou.noise_spectral, _ou_plans(field, domain)

  # unit-variance band-limited (and, for the velocity, solenoidal) random increment ξ
  # In place: `randn` would allocate a fresh field-scale array on every step of the hot loop, and on
  # a device backend a host array to copy across as well.
  randn!(ou.rng, field_data(noise_physical))
  to_spectral!(noise_spectral, noise_physical, plans)
  convolve!(noise_spectral, noise_spectral, ou.band)
  field isa VectorFieldSpectral && helmholtz_projection!(noise_spectral, noise_spectral, domain.multipliers)
  noise_variance = inner(noise_spectral, noise_spectral)

  # exact Ornstein–Uhlenbeck update. The unit-variance rescale of ξ is not a pass of its own: the
  # only consumer of ξ is the combination below, so 1/√⟨ξ,ξ⟩ rides in as part of its coefficient.
  α = exp(-T(dt) / T(ou.correlation_time))
  s = sqrt(T(ou.variance) * (one(T) - α^2))
  β = noise_variance > 0 ? s / sqrt(T(noise_variance)) : zero(T)
  combine!(ou.state, α, ou.state, β, noise_spectral)                        # f̂ ← α f̂ + √(σ²(1-α²)) ξ̂
  return nothing
end

add_forcing_source!(ou::StochasticOU, N̂, field, domain::FixedDomain, diffusivity::Real) =
  add!(N̂, N̂, ou.state)   # the increment was drawn once per step; the stage field is not needed


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

StochasticOU(; variance::Real, correlation_time::Real,
             lowest_shell::Integer = 1, highest_shell::Integer = 2, seed::Integer = 0) =
  DeferredForcing(domain -> StochasticOU(domain; variance, correlation_time, lowest_shell, highest_shell, seed))




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
indicator array) is rebuilt from them on read. A stochastic forcing (the archived, un-exported
`StochasticOU`) stores its parameters and **not** its evolving force or random stream: a reloaded
stochastic forcing resumes on a fresh stream, so continuation across a checkpoint is exact only
for the deterministic strategies. A
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
