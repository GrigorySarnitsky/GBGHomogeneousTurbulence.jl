# Forcing — the interchangeable energy-injection strategies, concrete `AbstractForcing` subtypes that act
# on the time step in one of two ways:
#
#   * `steady_linear_rate` — for a forcing whose rate is linear in the field AND STEADY IN TIME: return
#     a per-mode A(k) folded into the integrating factor, so the linear operator becomes A(k) - D|k|².
#     Exact, and free. BOTH words are load-bearing: the exponent is ∫A dt, so a rate that varies over
#     the step is integrated by a left-endpoint rectangle rule — local error O(Δt²), and the whole
#     iteration collapses to FIRST order however good the scheme is. The hook is handed no field, so
#     what it returns cannot depend on the state (decision 106). Only `Linear` qualifies.
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
to four hook methods, each defaulting to doing nothing. The module provides:

- [`AbstractForcing`](@ref) — the strategy supertype, defining the four-hook lifecycle.
- [`initial_forcing_state`](@ref) — the evolving state a forcing starts with, kept in the run's state
  record.
- [`prepare_forcing!`](@ref) — advance that state, once per step.
- [`steady_linear_rate`](@ref) — supply a *steady* linear rate, folded into the integrating factor.
- [`add_forcing_source!`](@ref) — add a source term at each stage.
- [`project_forcing!`](@ref) — project or rescale the field after the step.
- [`NoForcing`](@ref) — leave the field undriven.
- [`Linear`](@ref) — a fixed linear rate on a **band**, an annulus of integer Fourier shells (the
  convention every strategy shares).
- [`ConstantPower`](@ref) — a band amplitude re-solved each stage to hold the injection rate; the
  velocity default.
- [`VarianceController`](@ref) — drive the field's variance to a target by feedback.
- [`VarianceRescaling`](@ref) — hold the band's or the whole field's variance (`over`) by
  deterministic rescaling, at first order.
- [`StochasticOU`](@ref) — a random force correlated over a finite time, independent of the flow
  (Eswaran & Pope); its evolving state is a [`StochasticOUState`](@ref).
- [`kinetic_energy_in_box_units`](@ref), [`band_energy_fraction`](@ref) — the stationary state a
  forcing drives, as the kinetic energy in box units ``\\tilde{k}`` and the band's share of it.
- [`DeferredForcing`](@ref) — the keyword form of a strategy, taken without a domain and built into the concrete strategy once the
  [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) has built the domain; a
  construction-time object, not a lifecycle hook.
- [`write_forcing`](@ref) / [`read_forcing`](@ref) — a strategy's HDF5 persistence: its defining
  parameters as one self-describing group (available once `HDF5` is loaded).

Which keywords carry defaults follows one test: **does the value come from the method, or from this
run?** A canonical band (`lowest_shell = 1`, `highest_shell = 2`) is the method's and defaults; what
a run holds fixed, or drives at — `target`, `rate`, `injection_rate`, `over`, `forcing_variance`,
the correlation time — has no canonical value and is required. A `seed` is neither: any value gives an
equally valid realization, so one omitted is drawn — from the run's `rng` when a `Simulation`
builds the forcing, from the global stream otherwise — and naming it is how a run is repeated. A default at this layer never
hides a choice you needed to make.

The one relaxation is the run's own: a deferred velocity forcing may leave its target out, and the
run fills it from the stationary state it is set up for — the value still comes from the run, not
from a default here.

A band reaching above the dealias cutoff is inert there for a forcing that multiplies the field — the
mask holds those modes empty — so construction warns about it; the additive `StochasticOU` would
inject there instead, and refuses such a band. `highest_shell = Inf` asks for that reach on purpose —
every retained mode but the mean, on any grid — so it draws no warning; `StochasticOU` refuses it too.

The two fields are forced **independently**:
[`FlowConditions`](@ref GBGHomogeneousTurbulence.Generator.FlowConditions) — the `Generator`
parameter record bundling the viscosity, the Schmidt number, and the two forcings — takes a
separate `velocity_forcing` and `scalar_forcing`, so a run can force one, both, or neither.

"""
module Forcing

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, TwoThirds, max_retained_wavenumber, new_scalar_field_spectral, new_vector_field_spectral, new_scalar_field_physical, new_vector_field_physical, _real_type

export AbstractForcing, DeferredForcing, NoForcing, VarianceRescaling, VarianceController,
       Linear, ConstantPower, StochasticOU, StochasticOUState,
       steady_linear_rate, project_forcing!, initial_forcing_state,
       prepare_forcing!, add_forcing_source!, kinetic_energy_in_box_units, band_energy_fraction


# Is there anything in the band to rescale? The test carries NO absolute scale, which is what the
# forced problem requires: the scalar equation is exactly linear in φ, so φ → sφ with ε_φ → s²ε_φ is
# an exact symmetry, and any constant floor breaks it — silently switching the forcing off for a run
# whose amplitudes happen to be small, and in Float32 for many ordinary ones.
#
# Positivity is the whole test, and it needs no second reduction. An earlier attempt normalized the
# band observable by the WHOLE-FIELD observable, which was scale-free but bought it with an extra
# `inner(field, field)` every step. The bare-positivity form that then stood here was itself wrong
# the other way (caught by the 2026-08-23 dismissal audit): a band emptied by a mask or a rescale
# retains ROUNDOFF-level content, which is positive, so the amplitude ~ ε/2k_band took the unbounded
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

This is the supertype of the energy-injection strategies — the interchangeable ways a run drives its
velocity or its scalar.

A strategy implements whichever of four hooks it needs; each defaults to doing nothing. The
generator calls the first once, when it is built, and a step calls the other three in a fixed order:

- [`steady_linear_rate`](@ref) — once, when the generator is built: return a per-mode rate that
  stays fixed for the whole run, which the scheme folds exactly into the integrating factor.
- [`prepare_forcing!`](@ref) — once, before the stages: advance the strategy's own evolving state,
  such as a stochastic forcing's random process. [`initial_forcing_state`](@ref) creates that state
  and the run's [`ResolvedFields`](@ref GBGHomogeneousTurbulence.State.ResolvedFields) holds it.
- [`add_forcing_source!`](@ref) — at every stage: add a source term to the right-hand side.
- [`project_forcing!`](@ref) — once, after the completed step: project or rescale the advanced field.

The rate and the source are two channels of **one** forcing term: the steady part folded exactly into
the integrating factor, the remainder added at the stages. A single strategy may use both.

Which channel a rate may take is decided by steadiness in time, **not** by linearity in the field. The
integrating factor holds a rate fixed for the whole step, so a rate re-solved from the state must go
through `add_forcing_source!` instead; freezing it in the integrating factor would drop the scheme to
first order.

The rate hook is handed neither the field nor the time, so the rate it returns cannot depend on the
state: it is steady by construction.

Each mutating hook returns the argument it mutated: `add_forcing_source!` the right-hand side,
`project_forcing!` the field. The hook `prepare_forcing!` returns
`nothing`, having advanced the state it was handed in place.

A hook runs inside the time loop, which is allocation-free at field scale, so a strategy allocates
whatever scratch it needs once, when it is built, and its hooks touch only that scratch and the
arguments they are given.

!!! warning "One instance per forced field, for a strategy with mutable bookkeeping"
    A strategy that mutates its own fields as it runs must not drive both fields from one instance,
    or their bookkeeping is conflated;
    [`FlowConditions`](@ref GBGHomogeneousTurbulence.Generator.FlowConditions) throws an
    `ArgumentError` rather than let that happen. Every strategy here may be shared: none carries
    anything from one call to the next, since what a strategy evolves lives in the run's state, one
    entry per field, and its scratch is overwritten before each use.
"""
abstract type AbstractForcing end


"""
    DeferredForcing

A `DeferredForcing` is a forcing named before its domain exists. The keyword constructors,
which take no domain,

    ConstantPower(; injection_rate = nothing, lowest_shell = 1, highest_shell = 2)
    VarianceController(; target = nothing, gain = 1, turnover_time = nothing,
                       lowest_shell = 1, highest_shell = 2)
    VarianceRescaling(; target = nothing, over, lowest_shell = 1, highest_shell = 2)
    StochasticOU(; forcing_variance = nothing, correlation_time = nothing,
                 correlation_time_in_box_units = nothing, lowest_shell = 1,
                 highest_shell = 2, seed = nothing)
    Linear(; rate = nothing, lowest_shell = 1, highest_shell = 2)

each return a `DeferredForcing` holding their keywords. It is built into the concrete
`AbstractForcing` once the [`FixedDomain`](@ref GBGHomogeneousTurbulence.SimulationDomain.FixedDomain)
exists, which [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) does for you. A
forcing argument therefore accepts either a ready-built `AbstractForcing` (from the `domain`-taking
constructor) or a `DeferredForcing`.

**Only the deferred form may leave its target out**, because only a run can supply it. A velocity
forcing built by `Simulation` then takes the quantity it controls from the stationary state the
run is set up for:

- `ConstantPower` its `injection_rate`, from the dissipation rate ``\\varepsilon``;
- `VarianceController` and `VarianceRescaling(over = :total)` their `target`, from the kinetic
  energy ``k`` — or, bound to the scalar, from the scalar's stated `variance` — and the velocity's
  controller its `turnover_time`, from ``2k/(3\\varepsilon)``;
- `VarianceRescaling(over = :band)` its `target`, from the predicted energy in the band
  ``k_{\\mathrm{band}}``;
- `Linear` its `rate`, from ``A = \\varepsilon/(2 k_{\\mathrm{band}})``, the rate that injects ``\\varepsilon``;
- `StochasticOU` its `forcing_variance`, from ``\\varepsilon/T_L`` — the variance whose injection
  ``\\sigma^{2} T_L`` matches ``\\varepsilon`` while ``T_L`` is short.

The state, and ``k_{\\mathrm{band}}`` with it, is the one
[`predicted_stationary_state`](@ref GBGHomogeneousTurbulence.SimulationRun.predicted_stationary_state)
returns. The deferred `StochasticOU` may state its correlation time in box units, as a multiple of
``(L^{2}/\\varepsilon)^{1/3}``, which the run converts once into the constant time ``T_L`` the strategy
holds; its `seed`, left out, is drawn from the run's `rng`. A scalar forcing takes only a
whole-field target from the run, the scalar's stated `variance`, since no scalar stationary state
is modelled; anything else it states. Otherwise the keywords and defaults are those of the
`domain`-taking forms documented on each strategy.

# Examples
```julia
# The run supplies the injection rate from the dissipation it is set up for:
sim = Simulation(grid_points_per_axis = 64, kinetic_energy = 1.5,
                 velocity_forcing = ConstantPower())

# Or state it, and the forcing's target is the run's state:
sim = Simulation(grid_points_per_axis = 64,
                 velocity_forcing = ConstantPower(injection_rate = 0.4))

# Or build it directly, once the domain is in hand:
domain = FixedDomain(; grid_points_per_axis = 64, side_length = 2π,
                     dealiasing = TwoThirds(), element_type = Float64,
                     array_family = Array)
forcing = ConstantPower(domain; injection_rate = 0.4)
```

# Fields
The type parameter `F` is the strategy the forcing builds into.
- `parameters` — the keywords given, an omitted target held as `nothing`.
"""
struct DeferredForcing{F, P <: NamedTuple}
  parameters::P
end

DeferredForcing{F}(parameters::P) where {F, P <: NamedTuple} = DeferredForcing{F, P}(parameters)

# Build on `domain`, filling an omitted target from `design`, the run's stationary state
# `(; kinetic_energy, dissipation)` — or `nothing` where no state is modelled (the scalar), which
# makes an omitted target an error naming the keyword.
(deferred::DeferredForcing{F})(domain::FixedDomain, design = nothing) where {F} =
  F(domain; _completed(deferred, design)...)

_completed(deferred::DeferredForcing, design) = deferred.parameters

function _from_design(design, quantity::Symbol, strategy, keyword::Symbol)
  (design === nothing || !haskey(design, quantity) || getfield(design, quantity) === nothing) &&
    throw(ArgumentError("`$strategy(; …)` was given no `$keyword`, and nothing supplies one here: " *
                        "only a `Simulation` fills an omitted target, from the stationary state it " *
                        "sets up for the velocity or from the scalar's stated `variance`. A forcing " *
                        "built on a domain by hand, or a scalar forcing needing a quantity no scalar " *
                        "state models, must state `$keyword`."))
  return getfield(design, quantity)
end

_fill(parameters, keyword, value) = merge(parameters, NamedTuple{(keyword,)}((value,)))



"""
    steady_linear_rate(forcing, domain)

The per-mode rate ``A(\\boldsymbol{\\kappa})`` of a strategy `forcing` whose forcing is linear in the
field and constant in time, ``f = A \\texttt{field}``, on the [`FixedDomain`](@ref) `domain`; `nothing`
for every other strategy, the default. The scheme folds the rate into the diffusive integrating factor
``\\mathcal{E}(\\boldsymbol{\\kappa})`` (see [`velocity_integrating_factor`](@ref GBGHomogeneousTurbulence.Generator.velocity_integrating_factor)),
so the forced modes advance at the net linear rate
``A(\\boldsymbol{\\kappa}) - D\\lvert\\boldsymbol{\\kappa}\\rvert^{2}``, with ``D`` the field's diffusivity.

The generator calls it once, when it is built. A rate that is a function of
``\\lvert\\boldsymbol{\\kappa}\\rvert^{2}`` alone is returned as a radial kernel, evaluated per
mode inside the integrating factor and stored nowhere; any other rate as a scalar field in spectral
representation holding real values.

*Steady*, not merely linear, is the load-bearing word: a per-mode rate re-solved from the state each
step must not be returned here. Freezing it would be the left-endpoint rectangle rule on
``\\int A\\,\\mathrm{d}t``, dropping the scheme to first order; such a forcing goes through
[`add_forcing_source!`](@ref) instead. The hook is handed no field, so a rate it returns is steady by
construction.
"""
steady_linear_rate(::AbstractForcing, domain::FixedDomain) = nothing


"""
    project_forcing!(forcing, advanced_field, domain) -> advanced_field

Apply a strategy's post-step projection to the advanced field, in place. The default does nothing;
see `VarianceRescaling`.

# Arguments
- `forcing` — the strategy.
- `advanced_field` — a velocity or scalar ``\\varphi`` field in spectral representation, as the step
  has advanced it. Unlike the two hooks that read the start-of-step field, this one is handed the
  field at that later instant, since a strategy that rescales toward a target must measure the state
  it is correcting, not the one it started from.
- `domain` — the [`FixedDomain`](@ref).
"""
project_forcing!(::AbstractForcing, advanced_field, domain::FixedDomain) = advanced_field


"""
    initial_forcing_state(forcing, field, domain)

Create the state a forcing strategy begins from when it drives a field.

# Arguments
- `forcing` — the strategy.
- `field` — the velocity or the scalar in spectral representation; its tensor order sets how many
  components the state carries.
- `domain` — the [`FixedDomain`](@ref).

Returns `nothing` for a strategy that evolves no state of its own: the default, and the case of every
strategy but [`StochasticOU`](@ref), which returns a
[`StochasticOUState`](@ref) holding its random process.

A run calls this once per forced field, keeps what it returns as the `modeled` entry of its
[`ResolvedFields`](@ref GBGHomogeneousTurbulence.State.ResolvedFields), and hands that value to
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

# Arguments
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

# Arguments
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
function _check_shells(lowest::Integer, highest::Real)
  lowest >= 1 ||
    throw(ArgumentError("`lowest_shell` must be at least 1, got $lowest: shell 0 is the mean " *
                        "(κ = 0) mode, which a band forcing cannot legitimately drive — it carries " *
                        "the box's total momentum (or the scalar's mean), not turbulence"))
  # An integer shell, or `Inf` for no upper bound. Nothing between: a lattice |κ|²/κ₀² is always an
  # integer and an integer shell's edge sits at (n + ½)², which never is one, so no mode lies on an
  # edge for roundoff to decide. A bound of 2.5 would put the edge exactly on |κ| = 3κ₀. The test is
  # on the VALUE, not the type: `[2, 4, Inf]` promotes its integers to Float64, and 2.0 is shell 2.
  (highest == Inf || (isfinite(highest) && isinteger(highest))) ||
    throw(ArgumentError("`highest_shell` must be an integer shell or `Inf` (every retained mode " *
                        "but the mean), got $highest: a shell between two integers would put the " *
                        "band's edge on lattice modes, which roundoff then assigns"))
  highest >= lowest ||
    throw(ArgumentError("`highest_shell` must be at least `lowest_shell`, got $highest < $lowest: " *
                        "the band would be empty and the forcing would silently do nothing"))
  return nothing
end

function _shell_band(domain::FixedDomain, lowest::Integer, highest::Real)
  _check_shells(lowest, highest)
  highest = _shell_bound(highest)                     # 2.0 reads as shell 2 in the warnings too
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
  elseif isfinite(highest) && (highest + 0.5) * k0 > κ_max    # `Inf` asked for exactly this: no warning
    @warn "the forcing band (shells $(lowest)–$(highest)) reaches above the dealias cutoff " *
          "(shell ≈ $(round(κ_max / k0, digits = 1))): the shells above it are held empty by the " *
          "mask and contribute nothing — the forcing acts only on the retained part of the band."
  end
  return spectral_band(domain.multipliers, _shell_edges(domain, lowest, highest)...)
end

# The wavenumber edges of shells `lowest`–`highest`, the one home of the convention every band
# shares: shell h covers [h − ½, h + ½) in units of the fundamental 2π/L. PF's band needs a finite
# edge; the stored grid's corner — √3 times its Nyquist shell — lies past every mode the grid holds,
# retained or not, so `Inf` becomes "every mode but the mean" on any N.
function _shell_edges(domain::FixedDomain, lowest::Integer, highest::Real)
  k0 = 2π / domain.grid.domain_size[1]
  top = isfinite(highest) ? highest : _corner_shell(domain)
  return ((lowest - 0.5) * k0, (top + 0.5) * k0)
end

_corner_shell(domain::FixedDomain) = ceil(Int, sqrt(3) * maximum(domain.grid.grid_size) / 2)

# The stored upper bound: the integer the caller gave, or `Inf` itself — never the corner shell it
# resolves to on this grid, which would read back as "all modes" only on the grid it came from.
_shell_bound(highest::Real) = isinf(highest) ? Inf : Int(highest)


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

The deterministic rescaling forcing of Sullivan, Mahalingam & Kerr (1994), built on the [`FixedDomain`](@ref)
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
([`kinetic_energy`](@ref GBGHomogeneousTurbulence.Observables.kinetic_energy)), the **scalar variance**
``\\langle\\varphi^{2}\\rangle`` for the scalar
([`scalar_variance`](@ref GBGHomogeneousTurbulence.Observables.scalar_variance)) — each the field's
``L^{2}`` observable, the ``\\tfrac{1}{2}`` belonging to the kinetic energy's definition rather than
to the field being a vector.

# Arguments
- `domain` — the `FixedDomain` the band kernel is built on.
- `target` — the value held, in the field's own observable above. The deferred form may leave it
  out, and a run then supplies it: its stationary ``k`` for `over = :total`, and the band's predicted
  ``k_{\\mathrm{band}}`` for `over = :band`. That prediction takes the band's share of ``k`` to be the one
  `over = :total` holds on the same band: both rescale the same modes, and they are taken to reach
  the same stationary flow.
- `over` — *where* the target applies, `:band` or `:total`. It is required, since a deterministic
  clamp destroys the physical fluctuation of whatever it holds and no default is right for every run,
  and the two modes differ in which quantity a run may no longer measure:
    * `:band` holds the band's own value. The whole-field value then floats, oscillating about its
      mean as the band feeds the cascade. On the default shells 1–2 — the energy-containing range —
      most of ``k`` is held rather than free, though it remains a measurable.
    * `:total` rescales the band to absorb the whole-field deficit, so the whole-field value equals
      `target`. For the velocity this pins ``u'`` and with it the scale of ``\\mathrm{Re}_\\lambda``
      (whose value still fluctuates with the instantaneous dissipation). Here ``k`` is what the
      forcing sets and the band is free.
- `lowest_shell = 1`, `highest_shell = 2` — the rescaled band, as integer shells in units of the box's
  fundamental ``2\\pi/L``. With `highest_shell = Inf` the band is every retained mode but the mean, on
  any grid, and the two modes of `over` coincide — the mean holds nothing in a field started without
  one — so a single factor rescales the whole field: the rescaling a physical-space code applies.

Neither is a default, because the right answer depends on what the run is calibrated against.
A [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) deriving ``\\nu`` chooses it
from the *assumed* kinetic energy, so a forcing put there by hand must be a `:total` one or that
calibration stops holding. Where nothing calibrates against it, `:band` is the gentler clamp.

Sizing the rescale reduces the field to a number, so each step blocks on one device-to-host
transfer: the band and whole-field observables ride a single fused traversal, in either mode.

!!! warning "First order in time, and two extremes worth knowing"
    This is the one forcing that costs the scheme its order, by construction rather than by defect:
    the rescale is applied *after* the step, which is Lie–Trotter operator splitting — the step's
    map and the rescale's map composed one after the other, a composition whose error is
    ``O(\\Delta t)`` regardless of how accurate either map is alone — so it
    is first-order however good the scheme is. Measured on the third-order [`IFLowStorageRK3`](@ref GBGHomogeneousTurbulence.Propagator.IFLowStorageRK3): **1.02**
    here, against **3.01** for `Linear`, `ConstantPower`, `VarianceController` and an unforced run.
    (A stochastic forcing is outside that comparison — it has no classical order to lose.)
    Molecular dynamics reached the same
    conclusion about the same manoeuvre — per-step rescaling is the deterministic (Berendsen) limit
    of stochastic velocity rescaling, with no conserved quantity and no well-defined ensemble except
    in limiting cases (Bussi, Donadio & Parrinello 2007) — and the fix is to extend the dynamics with feedback rather
    than project after the fact.

    Two configurations also behave sharply. Under `:total`, if the out-of-band value alone exceeds
    `target`, the band is **zeroed** — the closest reachable state, and the most violent intervention
    the rescale can make. At the other end an empty band is **left alone** rather than divided by ~0,
    so it stays empty instead of being driven to `target`. Seed content in the band if a run depends
    on the clamp taking hold.

# References
- Sullivan, N. P., Mahalingam, S. & Kerr, R. M. (1994). [*Deterministic forcing of homogeneous, isotropic turbulence*](https://doi.org/10.1063/1.868274). *Phys. Fluids* **6**(4), 1612–1614.
- Bussi, G., Donadio, D. & Parrinello, M. (2007). [*Canonical sampling through velocity rescaling*](https://doi.org/10.1063/1.2408420). *J. Chem. Phys.* **126**, 014101.

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
  highest_shell::Union{Int, Float64}   # an integer shell, or `Inf`: every mode but the mean
end

function VarianceRescaling(domain::FixedDomain; target::Real, over::Symbol,
                       lowest_shell::Integer = 1, highest_shell::Real = 2)
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
                           Int(lowest_shell), _shell_bound(highest_shell))
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
- `rate` — the fixed linear rate ``A``. A positive value amplifies the field. The deferred form may
  leave it out, and a run then supplies ``A = \\varepsilon/(2 k_{\\mathrm{band}})``, with
  ``k_{\\mathrm{band}}`` the kinetic energy held in the forced band, from the state
  [`predicted_stationary_state`](@ref GBGHomogeneousTurbulence.SimulationRun.predicted_stationary_state) returns.
  The rate is fixed, not fed back from the measured state, so the run settles near that state rather
  than exactly at it.
- `lowest_shell = 1`, `highest_shell = 2` — the forced band, as integer shells in units of the box's
  fundamental ``2\\pi/L``. `highest_shell = Inf` lifts the band limit: every retained mode but the
  mean is forced, on any grid, and this is Lundgren's forcing itself — the form a physical-space code
  applies.

# Fields
- `band` — the band-pass kernel, evaluated per mode where used rather than stored, as is the rate
  on the same edges.
- `rate` — the fixed linear rate ``A``.
- `lowest_shell`, `highest_shell` — the forced band's shell bounds: the parameters `band` is derived
  from.
"""
struct Linear{K, T} <: AbstractForcing
  band::K              # band-pass kernel (lazy radial symbol): 1 in band, 0 outside
  rate::T              # the linear rate A
  lowest_shell::Int    # the band's shell bounds — the parameters `band` is derived from
  highest_shell::Union{Int, Float64}   # an integer shell, or `Inf`: every mode but the mean
end

Linear(domain::FixedDomain; rate::Real, lowest_shell::Integer = 1, highest_shell::Real = 2) =
  Linear(_shell_band(domain, lowest_shell, highest_shell), _real_type(domain)(rate), Int(lowest_shell),
         _shell_bound(highest_shell))

# The rate as a radial symbol, A on the band and zero elsewhere: the integrating factor evaluates it
# per mode beside ν|κ|², so nothing is stored (PF decision 92). The edges are the band's own, and the
# closure captures converted values only — a captured type is not a bitstype, which a device refuses.
function steady_linear_rate(forcing::Linear, domain::FixedDomain)
  T = _real_type(domain)
  low, high = _shell_edges(domain, forcing.lowest_shell, forcing.highest_shell)
  low², high², A, zero_rate = T(low)^2, T(high)^2, T(forcing.rate), zero(T)
  return radial_kernel(κ² -> ifelse(low² <= κ² <= high², A, zero_rate), domain.multipliers)
end


"""
    ConstantPower(domain; injection_rate, lowest_shell = 1, highest_shell = 2)

Constant-injection-rate forcing, built on the [`FixedDomain`](@ref) `domain`: a banded linear
forcing ``f = A \\texttt{field}`` on the integer shells `lowest_shell` to `highest_shell` (in units
of the box's fundamental ``2\\pi/L``; default 1–2),
whose rate ``A`` is re-solved at every stage so the injection rate holds the `injection_rate`. A
linear rate injects at ``2 A k_{\\mathrm{band}}``, with ``k_{\\mathrm{band}}`` the band's own
observable, so the rate that holds it is

```math
A = \\frac{\\texttt{injection\\_rate}}{2 k_{\\mathrm{band}}}.
```

In stationarity the injection balances dissipation, so `injection_rate` is the value ``\\varepsilon``
relaxes to in the stationary mean — chosen to agree with the diagnostics —
the rate ``\\varepsilon`` for the velocity (measured by
[`dissipation`](@ref GBGHomogeneousTurbulence.Observables.dissipation)) and
``\\varepsilon_\\varphi`` for the scalar (by
[`scalar_dissipation`](@ref GBGHomogeneousTurbulence.Observables.scalar_dissipation)). The keyword
names the kind of quantity it is — a **rate**, where `VarianceRescaling`'s `target` is an
**amplitude**.

Since that amplitude is re-solved from the state, it enters the right-hand side at **every stage**
rather than the integrating factor, where freezing it would cost the scheme its order. Like
[`Linear`](@ref) it is a per-mode multiple of the field, so it preserves a solenoidal velocity.

# Arguments
- `domain` — the `FixedDomain` the band is built on.
- `injection_rate` — the rate at which energy (for the velocity) or scalar variance (for the scalar)
  is injected; not an instantaneous dissipation the forcing measures or clamps. A deferred velocity
  forcing may leave it out, and the run then supplies its stationary ``\\varepsilon`` (see
  [`DeferredForcing`](@ref)).
- `lowest_shell = 1`, `highest_shell = 2` — the forced band, as integer shells in units of the box's
  fundamental ``2\\pi/L``. `highest_shell = Inf` forces every retained mode but the mean, on any grid:
  the band-free linear forcing of Lundgren (2003, *Linearly forced isotropic turbulence*,
  *CTR Annual Research Briefs*, 461–473) that physical-space codes apply, with its rate re-solved to
  hold the injection.

!!! note "An empty band is left alone, not driven infinitely hard"
    The rate ``A`` diverges as the band's own value goes to zero — its energy for the velocity, its
    variance for the scalar — which is reachable: a scalar seeded with nothing in the forced shells,
    or the step after a `VarianceRescaling(over = :total)` zeroed the band. Below a
    machine-roundoff floor on the band's observable — measured relative to the whole field's, so
    the test is invariant under a uniform rescaling of the field — the amplitude is set to zero,
    and an empty band stays empty rather than taking an unbounded kick; seed content in the band
    if a run needs the forcing to take hold.

# Fields
- `band` — the band-pass kernel, evaluated per mode where used: the per-stage source both weights the band observable with it
  and convolves against it, so no indicator array is stored.
- `injection_rate` — the held rate.
- `lowest_shell`, `highest_shell` — the forced band's shell bounds: the parameters `band` is derived
  from.
"""
struct ConstantPower{K, T} <: AbstractForcing
  band::K              # band-pass kernel (lazy radial symbol) — the band observable's weight
  injection_rate::T    # the VALUE of the dissipation rate to hold: dissipation or scalar_dissipation
  lowest_shell::Int    # the band's shell bounds — the parameters `band` is derived from
  highest_shell::Union{Int, Float64}   # an integer shell, or `Inf`: every mode but the mean
end

"""
    VarianceController(domain; target, gain = 1, turnover_time = nothing,
                       lowest_shell = 1, highest_shell = 2)
    VarianceController(; target = nothing, gain = 1, turnover_time = nothing,
                       lowest_shell = 1, highest_shell = 2)

Hold the field's variance at `target` by feedback — the kinetic energy ``k`` for the velocity,
``\\langle\\varphi^{2}\\rangle`` for the scalar — with the constant-``k`` controller of
Bassenne et al. (2016).

Prefer it to [`VarianceRescaling`](@ref) whenever accuracy in time matters, which is nearly always:
it enters the right-hand side as a smooth rate the scheme integrates and keeps its order, where a
rescaling is a post-step projection capping the iteration at first order.

The rate is the marginal law ``A = \\varepsilon/2k_{\\mathrm{band}}``, with ``k_{\\mathrm{band}}`` the variance held in
the forced band, plus a proportional restoring term:

```math
A(\\boldsymbol{\\kappa}, t) = \\frac{\\varepsilon(t) - G[k(t) - k_\\infty]/t_\\ell}{2k_{\\mathrm{band}}(t)}
\\quad\\text{in the band, } 0 \\text{ outside,}
```

with ``k_\\infty`` the `target`, ``G`` the `gain` and ``t_\\ell`` the `turnover_time`, so that
``\\mathrm{d}k/\\mathrm{d}t = -G(k - k_\\infty)/t_\\ell`` exactly: the variance relaxes
exponentially to a **stable attractor** with settling time ``t_\\ell/G``.

The limit `gain = 0` is the bare **marginal law**, and it is allowed: exact reinjection of the
instantaneous ``\\varepsilon`` makes ``\\mathrm{d}k/\\mathrm{d}t = 0``, so ``k`` is *conserved at
its initial value* and `target` never enters the rate. Every level is then a **neutral** equilibrium
— the reinjection cancels the cascade's own restoring response, which [`ConstantPower`](@ref)'s
fixed injection retains — so discrete integration bias accumulates uncorrected (about 1% of ``k``
per 1000 steps, measured at ``24^3`` in `Float64`; a `Float32` run's roundoff bias is larger and
unmeasured), and nothing ever restores it.

The two variances there are **not interchangeable**: ``k`` is the whole field's, the one held;
``k_{\\mathrm{band}}`` the forced band's, dividing out because the forcing injects only there. An empty band is
left alone rather than divided by ``\\sim 0`` (the floor `ConstantPower` documents), so seed content
in the band if the run depends on the controller taking hold.

# Arguments
- `domain` — the [`FixedDomain`](@ref) the band kernel is built on (the first form; the
  domain-free second form defers that to the run, as a [`DeferredForcing`](@ref)).
- `target` — the whole-field variance ``k_\\infty`` to hold, in the field's own convention: the
  kinetic energy for the velocity, ``\\langle\\varphi^{2}\\rangle`` for the scalar. The deferred
  velocity form may leave it out, and the run then supplies its stationary ``k``.
- `gain = 1` — the dimensionless gain ``G``. A larger gain relaxes faster; Bassenne et al. report
  ``O(1-10)``, and the default sits at that range's gentle end so the controller perturbs the
  dynamics least. `0` is the bare marginal law above.
- `turnover_time = nothing` — the large-eddy turnover time ``t_\\ell = 2k_\\infty/(3\\varepsilon_\\infty)``
  (Bassenne's convention: ``\\tfrac{2}{3}`` of the run layer's eddy-turnover unit ``k/\\varepsilon``).
  Left at `nothing` it is computed for you from that formula. A [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) uses the state it
  predicts; built on a domain, the controller takes
  ``\\varepsilon_\\infty = (k_\\infty/\\tilde{k})^{3/2}/L`` with ``\\tilde{k}`` its band's placeholder kinetic
  energy in box units
  ([`kinetic_energy_in_box_units`](@ref)), and refuses a band that model does not cover. A run that
  sets ``\\nu`` against a very different regime should pass its own value. The
  derivation reads `target` as a kinetic energy, so it is valid only for the velocity: a
  controller left at the default and handed to
  [`FlowConditions`](@ref GBGHomogeneousTurbulence.Generator.FlowConditions) as a `scalar_forcing` with a
  positive gain is refused there — a scalar variance is not an energy, and the derived settling
  time would depend on the scalar's amplitude unit, breaking the scalar equation's exact
  linearity in ``\\varphi`` (at `gain = 0` the settling time never enters the dynamics and the
  marginal law stays legal). Driving the scalar, pass the **flow's** turnover time
  ``2k/(3\\varepsilon)`` explicitly.
- `lowest_shell = 1`, `highest_shell = 2` — the forced band, in integer shells of ``2\\pi/L``.
  `highest_shell = Inf` forces every retained mode but the mean, on any grid: the band-free linear
  forcing of Lundgren (2003, *Linearly forced isotropic turbulence*, *CTR Annual Research Briefs*,
  461–473) that physical-space codes apply, where
  ``k_{\\mathrm{band}} = k`` — the form Bassenne et al. designed the controller in.

The molecular-dynamics thermostats map the design space exactly, and **this controller is the
Berendsen-weak-coupling analogue** — gain-limited relaxation toward a target (Berendsen et al. 1984), carrying that class's known caveat: the
held quantity's own fluctuations are distorted by the coupling. Per-step rescaling is the naive
thermostat, whose limit here is `VarianceRescaling`; the contrasting extended-variable class
that restores canonical fluctuations is Nosé–Hoover
(Nosé 1984; Hoover 1985), a design this package
does not take.

!!! note "The settling time, not the gain, is the physical parameter"
    Only the ratio ``t_\\ell/G`` is observable: it is how long the variance takes to return after a
    disturbance. The two are kept separate because that is how the source states them.

# References
- Bassenne, M., Urzay, J., Park, G. I. & Moin, P. (2016). [*Constant-energetics physical-space forcing methods for improved convergence to homogeneous-isotropic turbulence with application to particle-laden flows*](https://doi.org/10.1063/1.4944629). *Phys. Fluids* **28**, 035114.
- Berendsen, H. J. C., Postma, J. P. M., van Gunsteren, W. F., DiNola, A. & Haak, J. R. (1984). [*Molecular dynamics with coupling to an external bath*](https://doi.org/10.1063/1.448118). *J. Chem. Phys.* **81**, 3684–3690.
- Nosé, S. (1984). [*A unified formulation of the constant temperature molecular dynamics methods*](https://doi.org/10.1063/1.447334). *J. Chem. Phys.* **81**(1), 511–519.
- Hoover, W. G. (1985). [*Canonical dynamics: Equilibrium phase-space distributions*](https://doi.org/10.1103/PhysRevA.31.1695). *Phys. Rev. A* **31**(3), 1695–1697.

# Fields
- `band` — the band-pass kernel, evaluated per mode where used; the controller convolves against it and stores nothing.
- `target`, `gain`, `turnover_time` — ``k_\\infty``, ``G`` and ``t_\\ell``.
- `turnover_time_derived` — `true` when ``t_\\ell`` came from the kinetic-energy default rather
  than the caller; `FlowConditions` refuses such a controller as a `scalar_forcing` at a
  positive gain.
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
  highest_shell::Union{Int, Float64}   # an integer shell, or `Inf`: every mode but the mean
end


function VarianceController(domain::FixedDomain; target::Real, gain::Real = 1,
                            turnover_time = nothing, lowest_shell::Integer = 1,
                            highest_shell::Real = 2)
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
  # t_ℓ = 2k_∞/3ε_∞, the large-eddy turnover time, with ε_∞ = (k_∞/k̃)^{3/2}/L from the model's k̃ for
  # this band. A `Simulation` passes the turnover time of the state it predicts instead; this default
  # serves a controller built on a domain by hand, and holds only while the placeholder k̃ is flat in
  # the Reynolds number, which such a controller does not know.
  if turnover_time === nothing
    reason = _uncovered_reason((; lowest_shell, highest_shell))
    reason === nothing ||
      throw(ArgumentError("`turnover_time` has no default here: $reason. Pass `turnover_time`."))
    k̃ = Td(_placeholder_kinetic_energy_in_box_units(highest_shell))
    ε = (target / k̃)^(3 // 2) / Td(domain.grid.domain_size[1])
  end
  tℓ = Td(turnover_time === nothing ? 2 * target / (3 * ε) : turnover_time)
  # r6-edge-cases-01: the message must show the value the check REJECTED. When the keyword was
  # omitted, that is the derived tℓ, never the caller's `nothing`.
  (isfinite(tℓ) && tℓ > 0) ||
    throw(ArgumentError("`turnover_time` must be finite and positive, got $tℓ" *
                        (turnover_time === nothing ?
                         " (derived from `target` = $target and the box side; pass " *
                         "`turnover_time` explicitly)" : "")))
  return VarianceController(band, target, gain, tℓ, turnover_time === nothing,
                            Int(lowest_shell), _shell_bound(highest_shell))
end





# ————————————————————————————————————————————————————————————————————————————————————————————————
# The stationary-state model: k̃ = k/(εL)^{2/3} and k_band/k as functions of the forcing (its type,
# band and, for VarianceRescaling, `over`) and the box Reynolds number. PLACEHOLDER values (decisions
# 94, 101): k̃ is FLAT in Re — the keyword is accepted and validated, and changes nothing until the
# measured dependence replaces it — and the same for every forcing type. Band values from the first
# sweep (96³–128³ VarianceRescaling(over = :total)): 0.72 on shells 1–2, 0.56 on 1–4, 0.47 on every
# mode, piecewise linear in 1/highest_shell between them. k_band/k is the inertial-tail estimate with
# the same k̃. Both are to be replaced by a measured table for highest_shell = 2, …, 6 and Inf.

const _PLACEHOLDER_KINETIC_ENERGY_IN_BOX_UNITS = ((0.0, 0.47), (0.25, 0.56), (0.5, 0.72))  # (1/highest_shell, k̃)
const _KOLMOGOROV_CONSTANT = 1.5     # C_K in the inertial-tail estimate of k_band/k

# The forced band and the strategy's identity, read from a built strategy or its deferred form alike.
_band_parameters(f::DeferredForcing) = f.parameters
_band_parameters(f::AbstractForcing) = f
_band_parameters(p::NamedTuple) = p                  # a strategy's own shell bounds, as its constructor holds them
_strategy_name(::DeferredForcing{F}) where {F} = nameof(F)
_strategy_name(f::AbstractForcing) = nameof(typeof(f))
_strategy_name(::NamedTuple) = "forcing"

# Why the model has no value for `forcing`, or `nothing` when it has one.
function _uncovered_reason(forcing)
  (forcing isa NoForcing || forcing isa DeferredForcing{NoForcing}) &&
    return "an unforced flow decays and has no stationary state to predict"
  p = _band_parameters(forcing)
  (hasproperty(p, :lowest_shell) && hasproperty(p, :highest_shell)) ||
    return "$(_strategy_name(forcing)) forces no band of shells, and the model covers banded forcings only"
  p.lowest_shell == 1 ||
    return "the model covers bands that start at shell 1, but this $(_strategy_name(forcing)) starts " *
           "at shell $(p.lowest_shell)"
  (isinf(p.highest_shell) || p.highest_shell >= 2) ||
    return "the model has no value for a band ending at shell $(p.highest_shell); the measured bands " *
           "end at shell 2 or higher"
  return nothing
end

_model_covers(forcing) = _uncovered_reason(forcing) === nothing

function _modelled_band(forcing, who)
  reason = _uncovered_reason(forcing)
  reason === nothing || throw(ArgumentError("$who: $reason"))
  return _band_parameters(forcing).highest_shell
end

# The box Reynolds number from whichever keyword was given. The Taylor form is solved for Re_box from
# Re_λ = k̃(Re_box)·√((20/3)·Re_box) by bisection in log Re_box: the right side increases with Re_box
# whenever d ln k̃/d ln Re_box > −½, and the bracket is widened until it holds the root.
function _box_reynolds(k̃_of, reynolds_box, reynolds_taylor, who)
  (reynolds_box === nothing) == (reynolds_taylor === nothing) &&
    throw(ArgumentError("$who: give exactly one Reynolds number, `reynolds_box` or `reynolds_taylor`"))
  value, name = reynolds_box !== nothing ? (reynolds_box, "reynolds_box") : (reynolds_taylor, "reynolds_taylor")
  (isfinite(value) && value > 0) ||
    throw(ArgumentError("$who: `$name` must be finite and positive, got $value"))
  reynolds_box !== nothing && return Float64(reynolds_box)
  target = Float64(reynolds_taylor)
  taylor(log_box) = k̃_of(exp(log_box)) * sqrt(20 / 3 * exp(log_box))
  low, high = log(1e-6), log(1e12)
  (taylor(low) <= target <= taylor(high)) ||
    throw(ArgumentError("$who: no box Reynolds number gives `reynolds_taylor` = $target"))
  for _ in 1:200
    middle = (low + high) / 2
    taylor(middle) < target ? (low = middle) : (high = middle)
    high - low < 1e-13 && break
  end
  return exp((low + high) / 2)
end

function _placeholder_kinetic_energy_in_box_units(highest_shell)
  x = isinf(highest_shell) ? 0.0 : 1 / highest_shell
  table = _PLACEHOLDER_KINETIC_ENERGY_IN_BOX_UNITS
  x >= last(table)[1] && return last(table)[2]
  for i in 1:length(table) - 1
    (x0, y0), (x1, y1) = table[i], table[i + 1]
    x0 <= x <= x1 && return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
  end
end

_placeholder_band_energy_fraction(highest_shell, k̃) =
  isinf(highest_shell) ? 1.0 :
  1 - 3 / 2 * _KOLMOGOROV_CONSTANT / (k̃ * (2π * (highest_shell + 1 / 2))^(2 / 3))


"""
    kinetic_energy_in_box_units(forcing; reynolds_box = nothing, reynolds_taylor = nothing)

The kinetic energy a flow driven by `forcing` holds in its stationary state, in box units,
``\\tilde{k} \\equiv k/(\\varepsilon L)^{2/3}``: the kinetic energy ``k`` over the energy
``(\\varepsilon L)^{2/3}`` of a Kolmogorov eddy the size of the box, with ``L`` the box side and
``\\varepsilon`` the dissipation rate. Its ``3/2`` power is the large-eddy length
``k^{3/2}/\\varepsilon`` as a fraction of the box side. It is what a run predicts its state with: given
``k``, the dissipation is ``\\varepsilon = (k/\\tilde{k})^{3/2}/L``, and given ``\\varepsilon``, the
energy is ``k = \\tilde{k} (\\varepsilon L)^{2/3}``. Its companion [`band_energy_fraction`](@ref) is the share of
``k`` held in the forced band.

# Arguments
- `forcing` — the velocity forcing, built or in its deferred keyword form. The value depends on its
  strategy, its band and, for [`VarianceRescaling`](@ref), on `over`, but not on its strength.
- `reynolds_box`, `reynolds_taylor` — the Reynolds number the value is wanted at: exactly one of the box
  Reynolds number ``\\varepsilon^{1/3}L^{4/3}/\\nu`` ([`reynolds_box`](@ref GBGHomogeneousTurbulence.Observables.reynolds_box))
  and the Taylor-microscale ``\\mathrm{Re}_\\lambda``
  ([`reynolds_taylor`](@ref GBGHomogeneousTurbulence.Observables.reynolds_taylor)).

Returns a `Float64`. An unforced flow, a forcing without a band, a band that does not start at shell
1 and a band ending at shell 1 have no value and throw an `ArgumentError`, as do both or neither
Reynolds number.

!!! warning "Placeholder values"
    The values are provisional, the same for every strategy, and do not yet depend on the Reynolds
    number: the keyword is checked and then has no effect. They are 0.72 for shells 1–2, 0.56 for
    shells 1–4 and 0.47 for every mode but the mean, measured in this package's first sweep, and
    interpolated linearly in the reciprocal of `highest_shell` between them. A measured table per
    strategy and band replaces them.
"""
function kinetic_energy_in_box_units(forcing; reynolds_box = nothing, reynolds_taylor = nothing)
  who = "kinetic_energy_in_box_units"
  h = _modelled_band(forcing, who)
  k̃_of(_) = _placeholder_kinetic_energy_in_box_units(h)
  _box_reynolds(k̃_of, reynolds_box, reynolds_taylor, who)
  return k̃_of(nothing)
end


"""
    band_energy_fraction(forcing; reynolds_box = nothing, reynolds_taylor = nothing)

The share of the kinetic energy a flow driven by `forcing` holds in its forced band, in its
stationary state: ``k_{\\mathrm{band}}/k``, with ``k_{\\mathrm{band}} = \\tfrac{1}{2}\\sum_{\\text{band}}
\\lvert\\hat{\\boldsymbol{u}}\\rvert^{2}`` over the shells `lowest_shell` to `highest_shell`. A run uses it
to set a strength that is stated through the band: the rate of [`Linear`](@ref),
``A = \\varepsilon/(2 k_{\\mathrm{band}})``, and the target of `VarianceRescaling(over = :band)`, which
is ``k_{\\mathrm{band}}`` itself. The band that holds everything but the mean (`highest_shell = Inf`) has
the fraction 1.

# Arguments
- `forcing` — the velocity forcing, built or in its deferred keyword form, as for
  [`kinetic_energy_in_box_units`](@ref). For `VarianceRescaling(over = :band)` the fraction is the one
  `over = :total` holds on the same band: both rescale the same modes, one holding the band and the
  other the whole field, so they are taken to reach the same stationary flow.
- `reynolds_box`, `reynolds_taylor` — exactly one: the Reynolds number the value is wanted at.

Returns a `Float64`, and refuses what `kinetic_energy_in_box_units` refuses.

!!! warning "Placeholder values"
    Until it is measured, the fraction is the inertial-range estimate: the energy
    ``\\tfrac{3}{2}C_K \\varepsilon^{2/3}\\kappa_{\\mathrm{c}}^{-2/3}`` above the band's outer edge
    ``\\kappa_{\\mathrm{c}} = (h + \\tfrac{1}{2}) 2\\pi/L``, with ``h`` the `highest_shell` and
    ``C_K = 1.5``, subtracted from ``k``, so that
    ``k_{\\mathrm{band}}/k = 1 - \\tfrac{3}{2}C_K/[\\tilde{k}(2\\pi(h + \\tfrac{1}{2}))^{2/3}]`` with
    ``\\tilde{k}`` the placeholder kinetic energy in box units. It gives about 0.50 for shells 1–2 and
    0.57 for shells 1–4, and it
    does not depend on the Reynolds number.
"""
function band_energy_fraction(forcing; reynolds_box = nothing, reynolds_taylor = nothing)
  who = "band_energy_fraction"
  h = _modelled_band(forcing, who)
  k̃ = _placeholder_kinetic_energy_in_box_units(h)
  _box_reynolds(_ -> k̃, reynolds_box, reynolds_taylor, who)
  return _placeholder_band_energy_fraction(h, k̃)
end




function add_forcing_source!(forcing::VarianceController, forcing_state, N̂, field, domain::FixedDomain,
                             diffusivity::Real)
  T = field_scalar_type(N̂)
  factor = _target_factor(field)
  # Two DIFFERENT weights, and which one goes where is the whole content of Bassenne's Eq. 20.
  # The forcing acts on the band alone, so it injects 2·A·k_band and the amplitude must be normalized by
  # the BAND's variance; the quantity being held is the field's whole-field variance, so the restoring
  # term must measure THAT. Using k_band in both places holds the band at `target` instead, which is a
  # different physical model and leaves the whole field wherever the cascade puts it.
  # One traversal, one readback: the three weighted sums share a single fused reduction (PF
  # decision 72) where three separate calls would read the field three times and block on the
  # device three times per stage. Bitwise identical to the separate calls.
  whole, band, dirichlet =
    weighted_inner(field, (domain.unit_kernel, forcing.band, domain.squared_wavenumber_kernel))
  whole_variance = factor * whole                                        # k, the quantity held
  band_variance = factor * band                                          # k_band, the forced band
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

function ConstantPower(domain::FixedDomain; injection_rate::Real, lowest_shell::Integer = 1, highest_shell::Real = 2)
  # No materialized indicator: it existed only to fill the integrating-factor rate array, and this
  # forcing no longer uses that route. The lazy kernel is convolved against directly, so a
  # `ConstantPower` run now carries NO field-scale storage of its own — two arrays fewer.
  return ConstantPower(_shell_band(domain, lowest_shell, highest_shell),
                       _real_type(domain)(injection_rate),
                       Int(lowest_shell), _shell_bound(highest_shell))
end

# NOT a steady rate, and declaring it one was the defect. `A = ε/2k_band` is linear in the field but
# depends on the band energy, which changes across the step — so folding it into the integrating
# factor evaluates ∫A dt by a LEFT-ENDPOINT RECTANGLE RULE, local error O(Δt²), and collapses the
# whole iteration to first order however good the scheme is. Measured before the move: IFLowStorageRK3
# gave 1.02 under this forcing against 2.995 unforced, while `Linear` — the same code path, the same
# exponent, differing only in that its A is genuinely steady — kept 2.987. That contrast is the proof.
# It goes through the per-stage source instead, where the scheme's own order conditions apply.

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
                 highest_shell = 2, seed = rand(Int))
    StochasticOU(; forcing_variance = nothing, correlation_time = nothing,
                 correlation_time_in_box_units = nothing, lowest_shell = 1,
                 highest_shell = 2, seed = nothing)

The stochastic forcing of Eswaran & Pope (1988), built on the [`FixedDomain`](@ref) `domain`: a random term,
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
The variance ``\\sigma^{2}`` is shared equally among the band's modes and their independent components.

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

# Arguments
- `domain` — the `FixedDomain` of the run this forcing drives.
- `forcing_variance` — the stationary mean square ``\\sigma^{2}`` of the added term, as above. A
  deferred velocity forcing may leave it out, and the run then supplies ``\\varepsilon/T_L``, the
  variance whose estimated injection matches its stationary ``\\varepsilon``.
- `correlation_time` — the correlation time ``T_L`` of each amplitude. The deferred form takes
  either it or `correlation_time_in_box_units`, a multiple ``\\tilde{T}_L`` of
  ``(L^{2}/\\varepsilon)^{1/3}`` that a run converts once into
  ``T_L = \\tilde{T}_L (L^{2}/\\varepsilon)^{1/3}`` from its predicted ``\\varepsilon``; exactly one of
  the two.
- `lowest_shell = 1`, `highest_shell = 2` — the forced band, as integer shells in units of ``\\kappa_0``;
  every mode of the band must lie inside the dealias cutoff, so the `Inf` the field-multiplying
  strategies accept is refused here.
- `seed` — fixes the random stream; left out, it is drawn from the run's `rng` when a
  [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) builds the forcing, and
  from the global stream (`rand(Int)`) when the forcing is built on a domain. A velocity and a
  scalar forcing given the same seed still draw independent streams.

The process lives in the run's state, not in this strategy. A run keeps it as a
[`StochasticOUState`](@ref) — the `modeled` entry of its
[`ResolvedFields`](@ref GBGHomogeneousTurbulence.State.ResolvedFields) — held on a small grid of its own
over the same box, large enough to carry the band and no larger, so the whole forcing costs a few
kilobytes and runs no transform at the resolution of the run. A checkpoint of the state therefore
resumes the same realization. This strategy holds its parameters and the scratch of one
draw, so one instance may drive both fields.

A `ResolvedFields` built by hand that carries no state for this forcing is refused: preparing it
throws an `ArgumentError` rather than leave the run unforced without saying so. A `Simulation`
builds it for you.

!!! warning "The band must lie inside the dealias cutoff"
    A forcing that multiplies the field injects nothing where the dealiasing mask holds the modes
    empty, but this forcing is added after the mask and would fill them. Construction therefore throws
    an `ArgumentError` for a band reaching past the cutoff, where the other strategies only warn.

# References
- Eswaran, V. & Pope, S. B. (1988). [*An examination of forcing in direct numerical simulations of turbulence*](https://doi.org/10.1016/0045-7930%2888%2990013-8). *Computers & Fluids* **16**, 257–278.

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
The hook [`initial_forcing_state`](@ref) creates it, [`prepare_forcing!`](@ref) advances it in place every step,
and a run keeps it as the `modeled` entry of
[`ResolvedFields`](@ref GBGHomogeneousTurbulence.State.ResolvedFields) for the forced field. There is no
reason to build one by hand.

Holding the force as an ordinary field is what keeps the rest simple. The draw is made real-valued and
then transformed, so its spectrum satisfies the reality condition by construction; the transverse
projection is [`GBGPeriodicFields`](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/)'; and the state is saved by that package's field persistence.

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
          draws = R == 1 ? VectorFieldPhysical(Array{T}(undef, field_physical_shape(companion.grid, Val(1))),
                                               companion.grid; layout = companion.layout) :
                           ScalarFieldPhysical(Array{T}(undef, field_physical_shape(companion.grid, Val(0))),
                                               companion.grid; layout = companion.layout),
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
                      lowest_shell::Integer = 1, highest_shell::Real = 2, seed::Integer = rand(Int))
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
  # The band-free form the multiplicative strategies take is not open to an additive one: a source on
  # every mode would fill the ones the dealias mask holds empty, and the grid carrying the process is
  # sized from the top shell. Refused by name, before the cutoff guard reports "|κ| = Inf".
  isinf(highest_shell) &&
    throw(ArgumentError("StochasticOU needs a finite `highest_shell`, got Inf: it adds its process " *
                        "rather than multiplying the field, so its band must stay below the dealias " *
                        "cutoff, and the coarse grid carrying the process is sized from the band's " *
                        "top shell"))
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
                          dealiasing = TwoThirds(), element_type = T, array_family = domain.array_family)
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
  randn!(ou.rng, field_data(slots.draws))           # a host field: the draw follows the seed, not the backend
  adapt!(slots.physical, slots.draws)
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


# How each strategy's deferred form meets the run's stationary state (see `DeferredForcing`).
_completed(d::DeferredForcing{ConstantPower}, design) =
  d.parameters.injection_rate === nothing ?
    _fill(d.parameters, :injection_rate, _from_design(design, :dissipation, :ConstantPower, :injection_rate)) :
    d.parameters
# The controller's omitted settling time is the run's own large-eddy turnover time 2k/3ε, from the
# predicted state, so it follows the Reynolds number the model is evaluated at.
function _completed(d::DeferredForcing{VarianceController}, design)
  p = d.parameters.target === nothing ?
    _fill(d.parameters, :target, _from_design(design, :variance, :VarianceController, :target)) :
    d.parameters
  design === nothing || p.turnover_time !== nothing || !haskey(design, :dissipation) ||
    design.dissipation === nothing ||
    (p = _fill(p, :turnover_time, 2 * design.kinetic_energy / (3 * design.dissipation)))
  return p
end
# `:total` holds the whole field's energy, `:band` the band's own, which the model predicts.
_completed(d::DeferredForcing{VarianceRescaling}, design) =
  d.parameters.target === nothing ?
    _fill(d.parameters, :target,
          d.parameters.over === :total ?
            _from_design(design, :variance, :VarianceRescaling, :target) :
            _from_design(design, :band_kinetic_energy, :VarianceRescaling, :target)) :
    d.parameters
# The rate that injects the predicted ε into the predicted band energy: ε = 2A k_band.
_completed(d::DeferredForcing{Linear}, design) =
  d.parameters.rate === nothing ?
    _fill(d.parameters, :rate, _from_design(design, :dissipation, :Linear, :rate) /
                               (2 * _from_design(design, :band_kinetic_energy, :Linear, :rate))) :
    d.parameters
# A correlation time stated in box units, (L²/ε)^{1/3}, is converted once here; the strategy then
# holds a constant time, as its exact decay factor exp(−Δt/T_L) needs. A seed left out is drawn here
# from the global stream; a `Simulation` has filled it from its own `rng` before this runs.
function _completed(d::DeferredForcing{StochasticOU}, design)
  p = d.parameters
  if p.correlation_time !== nothing
    correlation_time = p.correlation_time
  else
    (design === nothing || !haskey(design, :box_time) || design.box_time === nothing) &&
      throw(ArgumentError("`StochasticOU(; …)` states its correlation time in box units, (L²/ε)^{1/3}, " *
                          "and nothing here supplies ε to convert it: only a `Simulation` does, from " *
                          "the stationary state it sets up for the velocity. State `correlation_time` " *
                          "instead."))
    correlation_time = p.correlation_time_in_box_units * design.box_time
  end
  forcing_variance = p.forcing_variance === nothing ?
    _from_design(design, :dissipation, :StochasticOU, :forcing_variance) / correlation_time :
    p.forcing_variance
  seed = p.seed === nothing ? rand(Int) : p.seed
  return (; forcing_variance, correlation_time, p.lowest_shell, p.highest_shell, seed)
end

# What a forcing states about the run's stationary state: `(; kinetic_energy = k)` or
# `(; dissipation = ε)` for the one quantity it holds exactly, `nothing` for a forcing that holds
# neither. A deferred forcing whose target is omitted states nothing — it takes the state instead.
# `Simulation` counts this as a source of the state, so a target cannot also be given there.
_stated_state(::Any) = nothing
_stated_state(f::ConstantPower) = (dissipation = f.injection_rate,)
_stated_state(f::VarianceController) = (kinetic_energy = f.target,)
_stated_state(f::VarianceRescaling) = f.over === :total ? (kinetic_energy = f.target,) : nothing
_stated_state(d::DeferredForcing{ConstantPower}) =
  d.parameters.injection_rate === nothing ? nothing : (dissipation = d.parameters.injection_rate,)
_stated_state(d::DeferredForcing{VarianceController}) =
  d.parameters.target === nothing ? nothing : (kinetic_energy = d.parameters.target,)
_stated_state(d::DeferredForcing{VarianceRescaling}) =
  d.parameters.over === :total && d.parameters.target !== nothing ?
    (kinetic_energy = d.parameters.target,) : nothing

# Whether a forcing takes its strength from the run's state — true only for a deferred forcing
# whose target was left out. Such a forcing is consistent with the derived viscosity by construction.
_takes_design(::Any) = false
_takes_design(d::DeferredForcing{ConstantPower}) = d.parameters.injection_rate === nothing
_takes_design(d::DeferredForcing{VarianceController}) = d.parameters.target === nothing
_takes_design(d::DeferredForcing{VarianceRescaling}) = d.parameters.target === nothing
_takes_design(d::DeferredForcing{StochasticOU}) = d.parameters.forcing_variance === nothing
_takes_design(d::DeferredForcing{Linear}) = d.parameters.rate === nothing


# Operator-free keyword constructors: hold the keywords now and build the forcing once the domain
# exists (via `DeferredForcing`), so a case can name its forcing before the grid is built —
# `ConstantPower(injection_rate = 0.1)`, or `ConstantPower()` for the run to supply the rate.
Linear(; rate::Union{Nothing, Real} = nothing, lowest_shell::Integer = 1, highest_shell::Real = 2) =
  DeferredForcing{Linear}((; rate, lowest_shell, highest_shell))

ConstantPower(; injection_rate::Union{Nothing, Real} = nothing, lowest_shell::Integer = 1,
              highest_shell::Real = 2) =
  DeferredForcing{ConstantPower}((; injection_rate, lowest_shell, highest_shell))

VarianceRescaling(; target::Union{Nothing, Real} = nothing, over::Symbol, lowest_shell::Integer = 1,
                  highest_shell::Real = 2) =
  DeferredForcing{VarianceRescaling}((; target, over, lowest_shell, highest_shell))

VarianceController(; target::Union{Nothing, Real} = nothing, gain::Real = 1, turnover_time = nothing,
                   lowest_shell::Integer = 1, highest_shell::Real = 2) =
  DeferredForcing{VarianceController}((; target, gain, turnover_time, lowest_shell, highest_shell))

function StochasticOU(; forcing_variance::Union{Nothing, Real} = nothing,
                      correlation_time::Union{Nothing, Real} = nothing,
                      correlation_time_in_box_units::Union{Nothing, Real} = nothing,
                      lowest_shell::Integer = 1, highest_shell::Real = 2,
                      seed::Union{Nothing, Integer} = nothing)
  # Exactly one statement of the correlation time, checked at naming rather than at the run.
  count(!isnothing, (correlation_time, correlation_time_in_box_units)) == 1 ||
    throw(ArgumentError("give exactly one of `correlation_time` (the time T_L itself) or " *
                        "`correlation_time_in_box_units` (a multiple of (L²/ε)^{1/3} the run converts)"))
  return DeferredForcing{StochasticOU}((; forcing_variance, correlation_time,
                                       correlation_time_in_box_units, lowest_shell, highest_shell,
                                       seed))
end




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
  print(io, ", ", forcing.band, ")")
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
# The keywords a run fills, per strategy — so only those `nothing`s read "from the run"; any other
# `nothing` (a controller's `turnover_time`) is the strategy's own default and prints as given. The
# member of an either-or pair that was not given is left out rather than printed as `nothing`.
_run_filled(::Type) = ()
_run_filled(::Type{ConstantPower}) = (:injection_rate,)
_run_filled(::Type{VarianceController}) = (:target,)
_run_filled(::Type{VarianceRescaling}) = (:target,)
_run_filled(::Type{Linear}) = (:rate,)
_run_filled(::Type{StochasticOU}) = (:forcing_variance, :seed)
_either_or(::Type) = ()
_either_or(::Type{StochasticOU}) = (:correlation_time, :correlation_time_in_box_units)

function Base.show(io::IO, d::DeferredForcing{F}) where {F}
  parts = String[]
  for (k, v) in pairs(d.parameters)
    v === nothing && k in _either_or(F) && continue
    push!(parts, v === nothing && k in _run_filled(F) ? "$k from the run" : "$k = $(repr(v))")
  end
  print(io, "DeferredForcing(", nameof(F), "(", join(parts, ", "), "))")
end



# ————————————————————————————————————————————————————————————————————————————————————————————————
# HDF5 persistence. The bare generics live here so the docstrings and the docs build work without
# HDF5 in the environment; the methods live in the `GBGHomogeneousTurbulenceHDF5Ext` weak-dependency
# extension, loaded automatically alongside the HDF5 package (the arrangement the field library's
# persistence pairs established).

export write_forcing, read_forcing


"""
    write_forcing(parent::HDF5.H5DataStore, name::AbstractString,
                  forcing::AbstractForcing)

Write the forcing strategy `forcing` (an [`AbstractForcing`](@ref)) under `parent` as one
self-describing HDF5 group — its defining parameters only; every derived object (a band kernel) is
rebuilt from them on read. What a strategy evolves is not a parameter: the
process of a [`StochasticOU`](@ref) lives in the run's state and is stored by
[`write_state`](@ref GBGHomogeneousTurbulence.State.write_state), so a reloaded strategy continues the
same realization when the state is restored with it. A
[`DeferredForcing`](@ref) is refused — resolve it on a domain first. Available once the `HDF5`
package is loaded; the caller owns the file.

# Arguments
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
keyword constructor on `domain` (a [`FixedDomain`](@ref)) — the derived band kernel is rebuilt,
never read. A group not written by `write_forcing`, or written by a newer schema
version, is refused with an `ArgumentError`. Available once the `HDF5` package is loaded.

# Arguments
- `parent` — the open HDF5 file or group holding the forcing group.
- `name` — the group's name.
- `domain` — the `FixedDomain` the strategy is rebuilt on.
"""
function read_forcing end


end # module Forcing
