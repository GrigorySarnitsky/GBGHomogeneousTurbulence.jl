# Forcing — the interchangeable energy-injection strategies, concrete `AbstractForcing` subtypes that act
# on the time step in one of two ways:
#
#   * `set_forcing_rate!` — for forcings LINEAR in the field (`f = A·field`): fill a per-mode rate A(k)
#     that is folded into the integrating factor, so the linear operator becomes A(k) - D|k|². This
#     is exact for the linear forcing and preserves the scheme's order (no operator splitting).
#     `Linear` (fixed A) and `ConstantPower` (A set each step so the injection rate is ε_target) use it.
#   * `apply_forcing!` — a post-step projection/rescale. `BandRescaling` (hold band or total energy fixed) uses it.
#
# One implementation serves both the velocity (a vector field) and the scalar φ (a scalar field),
# since the methods are written through tensor-order-generic field operators. A linear rate keeps a
# solenoidal velocity solenoidal (per-mode scaling), so the velocity needs no projection here.
#
# The additive stochastic (Ornstein–Uhlenbeck / Eswaran–Pope) forcing — which adds a time-correlated
# force field to the RHS — is a separate, stateful mechanism (`StochasticOU`), advanced once per step.

"""
    Forcing

The interchangeable energy-injection strategies:
- [`AbstractForcing`](@ref) — the strategy supertype, defining the four-hook lifecycle below.

A strategy acts on the step through up to four methods, each defaulting to doing nothing, listed in
the order the step calls them:
- [`prepare_forcing!`](@ref) — advance the forcing's own internal state, once per step.
- [`set_forcing_rate!`](@ref) — supply a linear forcing rate to be folded into the integrating
  factor; [`uses_linear_rate`](@ref) declares that a forcing supplies one.
- [`add_forcing_source!`](@ref) — add a source term at each stage.
- [`apply_forcing!`](@ref) — project or rescale the field after the step.

[`DeferredForcing`](@ref) is the operator-free keyword form of a strategy, materialized once the
[`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) has built the domain — a
construction-time object, not a lifecycle hook.

The strategies, one implementation each serving both the velocity and the scalar through
tensor-order-generic field operators:
- [`NoForcing`](@ref) — leave the field undriven.
- [`BandRescaling`](@ref) — hold a band's amplitude by deterministic rescaling.
- [`Linear`](@ref) — a fixed linear rate on a band.
- [`ConstantPower`](@ref) — a linear rate re-solved each step to hold the injection rate.

Which keywords carry defaults follows one test: **does the value come from the method, or from this
run?** A strategy's canonical band — `lowest_shell = 1`, `highest_shell = 2`, the large-scale band of
homogeneous isotropic turbulence — is a property of the method and defaults. What a run holds fixed —
`target`, `rate`, and `BandRescaling`'s `over` — has no canonical value and is therefore required. So a default here never hides a
choice you needed to make. The two fields are forced **independently**:
[`FlowConditions`](@ref GBGIsotropicTurbulence.Generator.FlowConditions) takes a separate
`velocity_forcing` and `scalar_forcing`, so a run can force one, both, or neither.

"""
module Forcing

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, new_scalar_field_spectral, new_vector_field_spectral, new_scalar_field_physical, new_vector_field_physical

export AbstractForcing, DeferredForcing, NoForcing, BandRescaling, Linear, ConstantPower,
       set_forcing_rate!, uses_linear_rate, apply_forcing!, prepare_forcing!, add_forcing_source!


# Is there anything in the band to rescale? The test carries NO absolute scale, which is what the
# forced problem requires: the scalar equation is exactly linear in φ, so φ → sφ with ε_φ → s²ε_φ is
# an exact symmetry, and any constant floor breaks it — silently switching the forcing off for a run
# whose amplitudes happen to be small, and in Float32 for many ordinary ones.
#
# Positivity is the whole test, and it needs no second reduction. An earlier attempt normalized the
# band observable by the WHOLE-FIELD observable, which was scale-free but bought it with an extra
# `inner(field, field)` every step — a full vector pass and a device-to-host readback, computed twice
# over on the `:total` branch where the rescale needs the same number again, and unaccounted for in
# both frozen audit ledgers. Multiplying by s² cannot change a sign, so the sign alone already has
# the invariance; the reduction was paying for nothing.
_band_is_empty(band_value) = !(isfinite(band_value) && band_value > zero(band_value))


"""
    AbstractForcing

Supertype of the energy-injection strategies. A strategy may implement any of
[`prepare_forcing!`](@ref) (advance the strategy's **own** internal state — a stochastic forcing's
random process, say — never the simulation state), [`set_forcing_rate!`](@ref)
(a linear forcing rate folded into the integrating factor — a strategy implementing it **must** also
declare [`uses_linear_rate`](@ref), or it is never given a rate array to fill),
[`add_forcing_source!`](@ref) (an additive per-stage source), and [`apply_forcing!`](@ref) (a
post-step projection); all default to doing nothing, and a strategy owns whatever scratch its hooks
need.

The hooks form **one per-step lifecycle with a fixed order**: `prepare_forcing!` and
`set_forcing_rate!` run once before the Runge–Kutta stages (whatever internal state a later hook
consumes must be prepared here), `add_forcing_source!` runs at every stage, and `apply_forcing!` runs after the completed
step. The linear rate and the additive source are two channels of **one** forcing term — the part linear
in the field is folded exactly into the integrating factor, the remainder is added at the stages — so a
single strategy may legitimately use both.

Each mutating hook returns its mutated argument (`set_forcing_rate!` the rate,
`add_forcing_source!` the right-hand side, `apply_forcing!` the field); `prepare_forcing!` returns
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
    BandRescaling(; target, over, lowest_shell = 1, highest_shell = 2)

each return a `DeferredForcing` capturing **the same keywords, with the same defaults**, as their
`domain`-taking forms documented on each strategy; it is materialized into the concrete
`AbstractForcing` once the [`FixedDomain`](@ref GBGIsotropicTurbulence.SimulationDomain.FixedDomain)
exists (done for you by [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation)). A
forcing argument
therefore accepts either a ready-built `AbstractForcing` (from the `domain`-taking constructor) or a
`DeferredForcing`.

# Examples
The two-form construction is the non-obvious part of this module, so the example lives here; the
strategies themselves are built by the forms shown below.

```julia
# Name the forcing before any grid exists — the front door supplies the domain:
sim = Simulation(grid_points_per_axis = 64, viscosity = 5e-3,
                 velocity_forcing = ConstantPower(injection_rate = 0.1))

# Or build it directly, once the domain is in hand:
domain = FixedDomain(; grid_points_per_axis = 64)
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

For a strategy `forcing` linear in the field, fill the per-mode rate `rate` — a scalar field in spectral
representation holding real values — with ``A(\\boldsymbol{\\kappa})``
(the forcing ``f = A \\texttt{field}``) and return `rate`; the scheme folds it into the diffusive
integrating factor ``\\mathcal{E}(\\boldsymbol{\\kappa})`` (see [`velocity_integrating_factor`](@ref GBGIsotropicTurbulence.Generator.velocity_integrating_factor)), so the
forced modes advance at the net linear rate ``A(\\boldsymbol{\\kappa}) - D\\lvert\\boldsymbol{\\kappa}\\rvert^{2}``
(``D`` the field's diffusivity). Only a forcing declaring [`uses_linear_rate`](@ref) is ever handed
a rate array, so the default method is never reached in a run; it returns `rate` untouched. The
`field` is the start-of-step field in spectral representation; `domain` is the
[`FixedDomain`](@ref).
"""
set_forcing_rate!(::AbstractForcing, rate, field, domain::FixedDomain) = rate


"""
    uses_linear_rate(forcing) -> Bool

Whether `forcing` drives its field through a linear per-mode rate — that is, whether it implements
[`set_forcing_rate!`](@ref). The default is `false`; a forcing that does implement the hook **must**
declare it `true`.

The generator allocates a rate array ``A(\\boldsymbol{\\kappa})`` per field only for a forcing that
declares this, so an unforced field, a post-step projection, or a stochastic source carries no rate
storage at all. Declaring it is therefore part of implementing `set_forcing_rate!`: a forcing
that fills a rate without declaring one is never given an array to fill, and
the [`ResolvedGenerator`](@ref GBGIsotropicTurbulence.Generator.ResolvedGenerator) constructor
rejects
it rather than let the forcing go silently unapplied.
"""
uses_linear_rate(::AbstractForcing) = false


"""
    apply_forcing!(forcing, advanced_field, domain) -> advanced_field

Apply the strategy `forcing`'s post-step projection to `advanced_field` (a velocity or scalar
``\\varphi`` field in spectral representation) in place, on the [`FixedDomain`](@ref) `domain`. The
default does nothing; see `BandRescaling`.

Unlike the two hooks that read the start-of-step field, this one is handed the field the step has
already advanced — the argument is named for that instant, since a strategy that rescales toward a
target must measure the state it is correcting, not the one it started from.
"""
apply_forcing!(::AbstractForcing, advanced_field, domain::FixedDomain) = advanced_field


"""
    prepare_forcing!(forcing, field, domain, dt) -> nothing

Update the strategy `forcing`'s internal state once per step, before the Runge–Kutta stages, from the
start-of-step `field` (in spectral representation) and the timestep `dt`, on the [`FixedDomain`](@ref)
`domain`. A stateful forcing owns whatever scratch this needs. The default does nothing.
"""
prepare_forcing!(::AbstractForcing, field, domain::FixedDomain, dt::Real) = nothing


"""
    add_forcing_source!(forcing, N̂, domain) -> N̂

Add the strategy `forcing`'s additive source to the assembled right-hand side `N̂` at each Runge–Kutta
stage (the source is held fixed over the step, so it integrates at the scheme's order), on the
[`FixedDomain`](@ref) `domain`. The default does nothing.
"""
add_forcing_source!(::AbstractForcing, N̂, domain::FixedDomain) = N̂


# An annular shell band-pass kernel for shells `lowest ≤ |k| ≤ highest` (integer shells of 2π/L).
function _shell_band(domain::FixedDomain, lowest::Integer, highest::Integer)
  k0 = 2π / domain.grid.domain_size[1]
  return spectral_band(new_scalar_field_spectral(domain), domain.multipliers, (lowest - 0.5) * k0, (highest + 0.5) * k0)
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
    BandRescaling(domain; target, over, lowest_shell = 1, highest_shell = 2)

Deterministic rescaling forcing (post-step) that holds a field's amplitude fixed, built on the
[`FixedDomain`](@ref) `domain`. Each step the in-band Fourier modes — the integer shells
`lowest_shell` to `highest_shell`, in units of the box's fundamental ``2\\pi/L`` — are rescaled by a
single factor to hold `target`. Rescaling preserves the divergence-free constraint.

Which observable is held follows from the field, chosen to agree with the diagnostics: the **kinetic
energy** ``\\tfrac{1}{2}\\langle\\lvert\\boldsymbol{u}\\rvert^{2}\\rangle`` for the velocity
([`kinetic_energy`](@ref GBGIsotropicTurbulence.Observables.kinetic_energy)), the **scalar variance**
``\\langle\\varphi^{2}\\rangle`` for the scalar
([`scalar_variance`](@ref GBGIsotropicTurbulence.Observables.scalar_variance)) — each the field's
``L^{2}`` observable, the ``\\tfrac{1}{2}`` belonging to the kinetic energy's definition rather than
to the field being a vector.

`over` selects *where* that target applies, and the two choices differ in which quantity a run may no
longer measure:

  * `:band` holds the band's own value. The whole-field value then floats, oscillating about its mean
    as the band feeds the cascade. The band's energy is set by the forcing rather than by the flow;
    the whole-field ``k`` remains a measurable, though on the default shells 1–2 — the
    energy-containing range — most of it is held rather than free.
  * `:total` rescales the band to absorb the whole-field deficit, so the whole-field value equals
    `target`. For the velocity this pins ``u'`` and with it the scale of ``\\mathrm{Re}_\\lambda``
    (whose value still fluctuates with the instantaneous dissipation). Here ``k`` is what the forcing
    sets and the band is free.

# Arguments
- `domain` — the `FixedDomain` the band is built on.
- `target` — the value of the held observable, as selected by `over`.
- `over` — `:band` or `:total`. Required: a deterministic clamp destroys the physical fluctuation of
  whatever it holds, and no default is right for every run.
- `lowest_shell = 1`, `highest_shell = 2` — the rescaled band, as integer shells in units of the
  box's fundamental ``2\\pi/L``.

!!! note "Which one a run wants depends on what else reads the kinetic energy"
    The [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) front door passes
    `:total`, and not as a preference: in grid mode it chooses ``\\nu`` from the *assumed* kinetic
    energy, so the resolution criterion ``\\kappa_{\\max}\\eta`` is self-consistent only if the run
    really holds ``k`` there — which is exactly what `:total` guarantees. A hand-built forcing that
    nothing downstream calibrates against has no such constraint, and `:band` is the gentler clamp.

!!! warning "Two extremes worth knowing before you rely on the clamp"
    Under `:total`, if the value outside the forced shells alone exceeds `target`, the band is
    **zeroed** — the closest reachable state, and the most violent intervention the rescale can make:
    it empties the energy-containing range in one step, leaving ``L_{11}``, ``u'`` and
    ``\\mathrm{Re}_\\lambda`` meaningless for turnovers afterwards. At the other end, a band with
    nothing in it is **left alone**: below a small floor the rescale returns the field untouched
    rather than dividing by ~0, so an empty band stays empty instead of being driven to `target` —
    reachable the step after a zeroing, and it means the clamp can stop applying. Seed content in the
    band if a run depends on it taking hold.

!!! note "It costs two host readbacks per step on a GPU"
    Sizing the rescale means reducing the field to a number and comparing it to `target`, so each
    step blocks on a device-to-host transfer — two under `over = :total`, which measures the band and
    the whole field. `ConstantPower` pays one; an unforced run pays none.

# Fields
- `band` — the band-pass kernel selecting the rescaled shells.
- `target` — the held value.
- `over` — `:band` or `:total`.
"""
struct BandRescaling{K, T} <: AbstractForcing
  band::K              # annular band-pass kernel (ScalarFieldSpectral)
  target::T            # the VALUE to hold, of kinetic_energy (velocity) or scalar_variance (scalar)
  over::Symbol         # :band (hold the band's value) or :total (hold the whole-field value)
end

function BandRescaling(domain::FixedDomain; target::Real, over::Symbol,
                       lowest_shell::Integer = 1, highest_shell::Integer = 2)
  over in (:band, :total) ||
    throw(ArgumentError("BandRescaling `over` must be :band or :total; got :$over"))
  # The target is an energy or a variance — both non-negative — and the rescale takes its square
  # root, so a negative value surfaced as a bare `DomainError` out of `sqrt` naming nothing.
  target >= 0 ||
    throw(ArgumentError("BandRescaling `target` must be non-negative, got $target: it is the " *
                        "kinetic energy or scalar variance the forcing holds, and the rescale " *
                        "takes its square root"))
  return BandRescaling(_shell_band(domain, lowest_shell, highest_shell), float(target), over)
end


function apply_forcing!(forcing::BandRescaling, field, domain::FixedDomain)
  factor = _target_factor(field)                       # ½ for the velocity (KE), 1 for the scalar (variance)
  band_value = factor * weighted_inner(field, forcing.band)  # the band observable (fused; no band-pass copy)
  _band_is_empty(band_value) && return field           # nothing in the band yet
  # aim the band at: the target itself (:band), or what makes the *whole field* hit the target (:total)
  target_band = if forcing.over === :total
    total_value = factor * inner(field, field)         # the observable over the whole field
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

Linear (negative-damping) forcing ``f = A \\texttt{field}`` in a low-wavenumber band — the
**fixed-rate** member of the two linear forcings, with
[`ConstantPower`](@ref) the member whose rate is re-solved each step (a band-limited
variant of Lundgren 2003, *CTR Annual Research Briefs*, which carries no DOI — whose linear
forcing acts at every wavenumber), built on the
[`FixedDomain`](@ref) `domain`. The rate is
folded into the integrating factor (exact for the linear term), so the forced band modes grow at net
rate ``A - D\\lvert\\boldsymbol{\\kappa}\\rvert^{2}`` (``D`` the field's diffusivity).

# Arguments
- `domain` — the `FixedDomain` the band is built on.
- `rate` — the fixed linear rate ``A``. A positive value amplifies the field.
- `lowest_shell = 1`, `highest_shell = 2` — the forced band, as integer shells in units of the box's
  fundamental ``2\\pi/L``.

# Fields
- `indicator` — the band indicator as a real array.
- `rate` — the fixed linear rate ``A``.
"""
struct Linear{M, T} <: AbstractForcing
  indicator::M         # real array: the band indicator (1 in band, 0 outside)
  rate::T              # the linear rate A
end

function Linear(domain::FixedDomain; rate::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2)
  # The band kernel is lazy (a radial symbol); the rate fill wants its values as a real array, so the
  # indicator is materialized once here — the same stored mask this forcing always carried.
  indicator = real.(field_data(materialize_kernel(_shell_band(domain, lowest_shell, highest_shell)).field))
  return Linear(indicator, float(rate))
end

uses_linear_rate(::Linear) = true

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
whose rate ``A`` is set each step so the field's injection rate holds the `injection_rate`. A
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
[`scalar_dissipation`](@ref GBGIsotropicTurbulence.Observables.scalar_dissipation)). The keyword is
named for the kind of quantity it is: a **rate**, where `BandRescaling`'s `target` is an
**amplitude** — which is why the two strategies do not share one keyword name. The rate is folded
into the integrating factor; like `Linear`, it preserves a solenoidal velocity.

# Arguments
- `domain` — the `FixedDomain` the band is built on.
- `injection_rate` — the rate at which energy (for the velocity) or scalar variance (for the scalar)
  is injected. In the stationary mean the corresponding dissipation relaxes to it; it is not an
  instantaneous dissipation the forcing measures or clamps.
- `lowest_shell = 1`, `highest_shell = 2` — the forced band, as integer shells in units of the box's
  fundamental ``2\\pi/L``.

!!! note "An empty band is left alone, not driven infinitely hard"
    The rate ``A`` diverges as the band's own value goes to zero — its energy for the velocity, its
    variance for the scalar — which is reachable: a scalar seeded with nothing in the forced shells, or the step after a `BandRescaling(over = :total)`
    zeroed the band. Below a small floor on ``E_{\\mathrm{band}}`` the rate is set to zero instead,
    so an empty band stays empty rather than receiving an unbounded kick; seed some content in the
    band if a run needs the forcing to take hold.
# Fields
- `band` — the band-pass kernel weighting the band observable.
- `indicator` — the band indicator as a real array, the rate fill's factor.
- `injection_rate` — the held rate.
"""
struct ConstantPower{K, I, T} <: AbstractForcing
  band::K              # band-pass kernel (lazy radial symbol) — the band observable's weight
  indicator::I         # the band indicator as a real array — the rate fill's factor
  injection_rate::T    # the VALUE of the dissipation rate to hold: dissipation or scalar_dissipation
end

function ConstantPower(domain::FixedDomain; injection_rate::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2)
  band = _shell_band(domain, lowest_shell, highest_shell)
  # The kernel is lazy and carries no coefficients to read, so the rate fill's indicator is
  # materialized once here as a real array (half the complex field the stored band once was).
  indicator = real.(field_data(materialize_kernel(band).field))
  return ConstantPower(band, indicator, float(injection_rate))
end

uses_linear_rate(::ConstantPower) = true

function set_forcing_rate!(forcing::ConstantPower, rate, field, domain::FixedDomain)
  T = field_scalar_type(rate)
  band_observable = _target_factor(field) * weighted_inner(field, forcing.band)  # KE_band or variance_band (fused)
  amplitude = _band_is_empty(band_observable) ? 0.0 :
              forcing.injection_rate / (2 * band_observable)
  rate .= T(amplitude) .* forcing.indicator
  return rate
end


"""
    StochasticOU(domain; variance, correlation_time, lowest_shell = 1,
                 highest_shell = 2, seed = 0)

Stochastic forcing — Eswaran & Pope (1988), *An examination of forcing in direct numerical
simulations of turbulence*, *Computers & Fluids* **16**, 257–278,
[doi:10.1016/0045-7930(88)90013-8](https://doi.org/10.1016/0045-7930%2888%2990013-8) — built on the
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
"""
mutable struct StochasticOU{B, R, T} <: AbstractForcing
  band::B                                    # band-pass kernel for the noise
  correlation_time::T                        # T_L
  variance::T                                # σ²: stationary forcing variance ⟨|f|²⟩
  rng::R                                     # random stream (persists across steps)
  state::Union{Nothing, AbstractFieldSpectral}   # the OU forcing f̂ (allocated on first use)
  noise_physical::Union{Nothing, AbstractFieldPhysical}  # own noise scratch (allocated on first use)
  noise_spectral::Union{Nothing, AbstractFieldSpectral}
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
                      nothing, nothing, nothing)
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

add_forcing_source!(ou::StochasticOU, N̂, domain::FixedDomain) =
  add!(N̂, N̂, ou.state)


# Operator-free keyword constructors: capture the parameters now and build the forcing once the
# domain exists (via `DeferredForcing`), so a case can name its forcing before the grid is built —
# `ConstantPower(injection_rate = 0.1)` — with `Simulation` supplying the domain.
Linear(; rate::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  DeferredForcing(domain -> Linear(domain; rate, lowest_shell, highest_shell))

ConstantPower(; injection_rate::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  DeferredForcing(domain -> ConstantPower(domain; injection_rate, lowest_shell, highest_shell))

BandRescaling(; target::Real, over::Symbol, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  DeferredForcing(domain -> BandRescaling(domain; target, over, lowest_shell, highest_shell))

StochasticOU(; variance::Real, correlation_time::Real,
             lowest_shell::Integer = 1, highest_shell::Integer = 2, seed::Integer = 0) =
  DeferredForcing(domain -> StochasticOU(domain; variance, correlation_time, lowest_shell, highest_shell, seed))


end # module Forcing
