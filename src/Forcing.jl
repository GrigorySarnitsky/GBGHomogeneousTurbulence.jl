# Forcing — the interchangeable energy-injection strategies, concrete `AbstractForcing` subtypes that act
# on the time step in one of two ways:
#
#   * `set_forcing_rate!` — for forcings LINEAR in the field (`f = A·field`): fill a per-mode rate A(k)
#     that is folded into the integrating factor, so the linear operator becomes A(k) - D|k|². This
#     is exact for the linear forcing and preserves the integrator's order (no operator splitting).
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

A strategy acts on the step through up to four methods, each defaulting to doing nothing (listed in
the order the step fires them):
- [`prepare_forcing!`](@ref) — a per-step internal-state advance.
- [`set_forcing_rate!`](@ref) — a linear forcing rate folded into the integrating factor;
  [`uses_linear_rate`](@ref) declares that a forcing supplies one.
- [`add_forcing_source!`](@ref) — an additive per-stage source.
- [`apply_forcing!`](@ref) — a post-step projection or rescale.

The strategies are [`NoForcing`](@ref), [`BandRescaling`](@ref), [`Linear`](@ref), and
[`ConstantPower`](@ref); one implementation serves both the velocity (a vector field) and the scalar (a
scalar field), through tensor-order-generic field operators. The velocity and scalar are forced
**independently**: [`FlowConditions`](@ref GBGIsotropicTurbulence.Generator.FlowConditions) takes a separate `velocity_forcing` and `scalar_forcing`
(each an `AbstractForcing`), so a run can force the velocity while the scalar decays freely, force both, or
leave either unforced.

An operator-free keyword constructor (`BandRescaling(; …)`, `Linear(; …)`, `ConstantPower(; …)`) returns
a [`DeferredForcing`](@ref) that a `Simulation` materializes once the domain exists.
"""
module Forcing

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, new_scalar_field_spectral, new_vector_field_spectral, new_scalar_field_physical, new_vector_field_physical

export AbstractForcing, DeferredForcing, NoForcing, BandRescaling, Linear, ConstantPower,
       set_forcing_rate!, uses_linear_rate, apply_forcing!, prepare_forcing!, add_forcing_source!


"""
    AbstractForcing

Supertype of the energy-injection strategies. A strategy may implement any of
[`prepare_forcing!`](@ref) (a per-step state advance), [`set_forcing_rate!`](@ref)
(a linear forcing rate folded into the integrating factor — a strategy implementing it **must** also
declare [`uses_linear_rate`](@ref), or it is never given a rate array to fill),
[`add_forcing_source!`](@ref) (an additive per-stage source), and [`apply_forcing!`](@ref) (a
post-step projection); all default to doing nothing, and a strategy owns whatever scratch its hooks
need.

The hooks form **one per-step lifecycle with a fixed order**: `prepare_forcing!` and
`set_forcing_rate!` run once before the Runge–Kutta stages (the state a later hook consumes must be
prepared here), `add_forcing_source!` runs at every stage, and `apply_forcing!` runs after the completed
step. The linear rate and the additive source are two channels of **one** forcing term — the part linear
in the field is folded exactly into the integrating factor, the remainder is added at the stages — so a
single strategy may legitimately use both.

The hooks' return conventions differ deliberately: `set_forcing_rate!` returns a `Bool` — whether
the rate it filled is armed for this step — while the other three return their mutated argument
(`apply_forcing!` the field, `add_forcing_source!` the right-hand side) or `nothing`
(`prepare_forcing!`).

!!! warning
    Construct one strategy instance per forced field. An instance owns per-field scratch and
    internal state, so passing the same instance as both `velocity_forcing` and `scalar_forcing`
    would silently conflate the two fields' bookkeeping.
"""
abstract type AbstractForcing end


"""
    DeferredForcing

A deferred forcing. The operator-free keyword constructors

    Linear(; rate, lowest_shell = 1, highest_shell = 2)
    ConstantPower(; target, lowest_shell = 1, highest_shell = 2)
    BandRescaling(; target, over = :band, lowest_shell = 1, highest_shell = 2)

each return a `DeferredForcing` capturing **the same keywords, with the same defaults**, as their
`domain`-taking forms documented on each strategy; it is materialized into the concrete
`AbstractForcing` once the `FixedDomain` exists (done for you by `Simulation`). A forcing argument
therefore accepts either a ready-built `AbstractForcing` (from the `domain`-taking constructor) or a
`DeferredForcing`.

# Fields
- `build` — the captured constructor closure: calling the `DeferredForcing` on a `FixedDomain`
  invokes it, yielding the concrete strategy.
"""
struct DeferredForcing{F}
  build::F
end

(deferred::DeferredForcing)(domain::FixedDomain) = deferred.build(domain)


"""
    set_forcing_rate!(forcing, rate, field, domain) -> Bool

For a strategy `forcing` linear in the field, fill the per-mode rate `rate` — a scalar field in spectral
representation holding real values — with ``A(\\boldsymbol{\\kappa})``
(the forcing ``f = A \\texttt{field}``) and return `true`; the integrator folds it into the diffusive
integrating factor ``\\mathcal{E}(\\boldsymbol{\\kappa})`` (see [`velocity_factor`](@ref GBGIsotropicTurbulence.Generator.velocity_factor)), so the
forced modes advance at the net linear rate ``A(\\boldsymbol{\\kappa}) - D\\lvert\\boldsymbol{\\kappa}\\rvert^{2}``
(``D`` the field's diffusivity). Return `false` (the default) when the forcing contributes no linear
rate. The `field` is the start-of-step field in spectral representation; `domain` is the
[`FixedDomain`](@ref).
"""
set_forcing_rate!(::AbstractForcing, rate, field, domain::FixedDomain) = false


"""
    uses_linear_rate(forcing) -> Bool

Whether `forcing` drives its field through a linear per-mode rate — that is, whether it implements
[`set_forcing_rate!`](@ref). The default is `false`; a forcing that does implement the hook **must**
declare it `true`.

The generator allocates a rate array ``A(\\boldsymbol{\\kappa})`` per field only for a forcing that
declares this, so an unforced field, a post-step projection, or a stochastic source carries no rate
storage at all. Declaring it is therefore part of implementing `set_forcing_rate!`, not an
optimization: a forcing that fills a rate without declaring one is never given an array to fill, and
the constructor rejects it rather than let the forcing go silently unapplied.
"""
uses_linear_rate(::AbstractForcing) = false


"""
    apply_forcing!(forcing, field, domain) -> field

Apply the strategy `forcing`'s post-step projection to `field` (a velocity or scalar ``\\varphi`` field in spectral
representation) in place, on the [`FixedDomain`](@ref) `domain`. The default does nothing; see
`BandRescaling`.
"""
apply_forcing!(::AbstractForcing, field, domain::FixedDomain) = field


"""
    prepare_forcing!(forcing, field, domain, dt) -> nothing

Update the strategy `forcing`'s internal state once per step, before the Runge–Kutta stages, from the
start-of-step `field` (in spectral representation) and the timestep `dt`, on the [`FixedDomain`](@ref)
`domain`. A stateful forcing owns whatever scratch this needs. The default does nothing.
"""
prepare_forcing!(::AbstractForcing, field, domain::FixedDomain, dt::Real) = nothing


"""
    add_forcing_source!(forcing, nonlinear, domain) -> nonlinear

Add the strategy `forcing`'s additive source to the dealiased nonlinear-term buffer `nonlinear` at each Runge–Kutta
stage (the source is held fixed over the step, so it integrates at the scheme's order), on the
[`FixedDomain`](@ref) `domain`. The default does nothing.
"""
add_forcing_source!(::AbstractForcing, nonlinear, domain::FixedDomain) = nonlinear


# An annular shell band-pass kernel for shells `lowest ≤ |k| ≤ highest` (integer shells of 2π/L).
function _shell_band(domain::FixedDomain, lowest::Integer, highest::Integer)
  k0 = 2π / domain.grid.domain_size[1]
  return spectral_band(new_scalar_field_spectral(domain), domain.multipliers, (lowest - 0.5) * k0, (highest + 0.5) * k0)
end


# The observable a forcing `target` agrees with: kinetic energy ½⟨|u|²⟩ for the velocity (a vector
# field, tensor order 1), scalar variance ⟨φ²⟩ for the scalar (order 0) — the ½ convention only for the
# vector, matching `Observables.kinetic_energy` / `Observables.scalar_variance`.
_target_factor(field) = field_tensor_order(field) == 0 ? 1.0 : 0.5


"""
    NoForcing()

The unforced case: all four methods keep their defaults (do nothing) — a freely decaying field.
"""
struct NoForcing <: AbstractForcing end


"""
    BandRescaling(domain; target, over = :band, lowest_shell = 1, highest_shell = 2)

Deterministic rescaling forcing (post-step) that holds a field's amplitude fixed, built on the
[`FixedDomain`](@ref) `domain`. Each step the in-band
Fourier modes — the integer shells `lowest_shell` to `highest_shell`, in units of the box's
fundamental ``2\\pi/L`` — are rescaled by a single factor to hold the `target`.

The `target` is the observable the forcing holds, chosen to agree with the diagnostics: the **kinetic
energy** ``\\tfrac{1}{2}\\langle\\lvert\\boldsymbol{u}\\rvert^{2}\\rangle`` (`kinetic_energy`) for the velocity,
the **scalar variance** ``\\langle\\varphi^{2}\\rangle`` (`scalar_variance`) for the scalar — the field's
``L^{2}`` observable, carrying the ``\\tfrac{1}{2}`` only for the vector.

The `over` keyword selects where the target applies:
  * `:band` (default) — hold the band's own value; the whole-field value then floats, oscillating slowly
    about its mean as the band feeds the cascade.
  * `:total` — rescale the band to absorb the whole-field deficit so the whole-field value equals
    `target` (for the velocity this pins the r.m.s. velocity ``u'``, setting the scale of
    ``\\mathrm{Re}_\\lambda`` — its value still fluctuates with the instantaneous dissipation).
    If the out-of-band value alone exceeds `target`, the band is zeroed (the closest reachable state).

Rescaling preserves the divergence-free constraint either way.

!!! note
    This is a deterministic clamp, not a faithful stationary sampler.
    Holding an amplitude fixed by deterministic rescaling is the Berendsen-thermostat limit of
    stochastic velocity rescaling: it has no conserved quantity, is not associated with a well-defined
    ensemble except in limiting cases, and suppresses the physical fluctuations of the quantity it
    holds (Bussi, Donadio & Parrinello 2007). Use it to spin up or to pin an amplitude; when the held
    quantity is itself measured, prefer a fixed-injection forcing (`ConstantPower`), which leaves the
    energy free to fluctuate.
"""
struct BandRescaling{K, T} <: AbstractForcing
  band::K              # annular band-pass kernel (ScalarFieldSpectral)
  target::T            # the observable to hold: kinetic_energy (velocity) or scalar_variance (scalar)
  over::Symbol         # :band (hold the band's value) or :total (hold the whole-field value)
end

function BandRescaling(domain::FixedDomain; target::Real, over::Symbol = :band,
                       lowest_shell::Integer = 1, highest_shell::Integer = 2)
  over in (:band, :total) ||
    throw(ArgumentError("BandRescaling `over` must be :band or :total; got :$over"))
  return BandRescaling(_shell_band(domain, lowest_shell, highest_shell), float(target), over)
end


function apply_forcing!(forcing::BandRescaling, field, domain::FixedDomain)
  factor = _target_factor(field)                       # ½ for the velocity (KE), 1 for the scalar (variance)
  band_value = factor * weighted_inner(field, forcing.band)  # the band observable (fused; no band-pass copy)
  band_value < 1e-12 && return field                   # nothing in the band yet (guard)
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

Linear (negative-damping) forcing ``f = A \\texttt{field}`` in a low-wavenumber band (a band-limited
variant of Lundgren 2003, whose linear forcing acts at every wavenumber), built on the
[`FixedDomain`](@ref) `domain`,
with the fixed rate ``A = \\texttt{rate}`` on the integer shells `lowest_shell` to
`highest_shell`. The rate is
folded into the integrating factor (exact for the linear term), so the forced band modes grow at net
rate ``A - D\\lvert\\boldsymbol{\\kappa}\\rvert^{2}`` (``D`` the field's diffusivity). A positive `rate`
amplifies the field.
"""
struct Linear{M, T} <: AbstractForcing
  mask::M              # real array: the band indicator (1 in band, 0 outside)
  rate::T              # the linear rate A
end

function Linear(domain::FixedDomain; rate::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2)
  # The band kernel is lazy (a radial symbol); the rate fill wants its values as a real array, so the
  # indicator is materialized once here — the same stored mask this forcing always carried.
  mask = real.(field_data(materialize_kernel(_shell_band(domain, lowest_shell, highest_shell)).field))
  return Linear(mask, float(rate))
end

uses_linear_rate(::Linear) = true

function set_forcing_rate!(forcing::Linear, rate, field, domain::FixedDomain)
  T = field_scalar_type(rate)
  rate .= T(forcing.rate) .* forcing.mask
  return true
end


"""
    ConstantPower(domain; target, lowest_shell = 1, highest_shell = 2)

Constant-injection-rate forcing, built on the [`FixedDomain`](@ref) `domain`: a banded linear
forcing ``f = A \\texttt{field}`` on the integer shells `lowest_shell` to `highest_shell` (in units
of the box's fundamental ``2\\pi/L``; default 1–2),
whose rate ``A`` is set each step so the field's injection rate holds the `target`. In stationarity the
injection balances dissipation, so `target` is the **dissipation rate**, chosen to agree with the
diagnostics: `dissipation` ``\\varepsilon`` for the velocity, `scalar_dissipation`
``\\varepsilon_\\varphi`` for the scalar. (A rate — note the contrast with `BandRescaling`, whose
`target` is a held amplitude.) The rate is folded into the integrating factor; like `Linear`, it preserves a solenoidal
velocity.
"""
struct ConstantPower{K, I, T} <: AbstractForcing
  band::K              # band-pass kernel (lazy radial symbol) — the band observable's weight
  indicator::I         # the band indicator as a real array — the rate fill's factor
  target::T            # the dissipation rate to hold: dissipation (velocity) or scalar_dissipation (scalar)
end

function ConstantPower(domain::FixedDomain; target::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2)
  band = _shell_band(domain, lowest_shell, highest_shell)
  # The kernel is lazy and carries no coefficients to read, so the rate fill's indicator is
  # materialized once here as a real array (half the complex field the stored band once was).
  indicator = real.(field_data(materialize_kernel(band).field))
  return ConstantPower(band, indicator, float(target))
end

uses_linear_rate(::ConstantPower) = true

function set_forcing_rate!(forcing::ConstantPower, rate, field, domain::FixedDomain)
  T = field_scalar_type(rate)
  band_observable = _target_factor(field) * weighted_inner(field, forcing.band)  # KE_band or variance_band (fused)
  amplitude = band_observable > 1e-12 ? forcing.target / (2 * band_observable) : 0.0
  rate .= T(amplitude) .* forcing.indicator
  return true
end


"""
    StochasticOU(domain; variance, correlation_time, lowest_shell = 1,
                 highest_shell = 2, seed = 0)

Stochastic (Eswaran & Pope 1988) forcing, built on the [`FixedDomain`](@ref) `domain`: each forced Fourier mode in the band
(``\\texttt{lowest\\_shell} \\le \\kappa \\le \\texttt{highest\\_shell}``) carries an
independent complex Ornstein–Uhlenbeck process, advanced once per step by the exact transition

```math
\\hat f \\leftarrow \\theta \\hat f + \\sqrt{\\sigma^{2}(1-\\theta^{2})} \\xi,
\\qquad \\theta = \\exp(-\\Delta t / T_L),
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

!!! note
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
  copyto!(field_data(noise_physical), randn(ou.rng, T, size(field_data(noise_physical))...))
  to_spectral!(noise_spectral, noise_physical, plans)
  convolve!(noise_spectral, noise_spectral, ou.band)
  field isa VectorFieldSpectral && helmholtz_projection!(noise_spectral, noise_spectral, domain.multipliers)
  noise_variance = inner(noise_spectral, noise_spectral)

  # exact Ornstein–Uhlenbeck update. The unit-variance rescale of ξ is not a pass of its own: the
  # only consumer of ξ is the combination below, so 1/√⟨ξ,ξ⟩ rides in as part of its coefficient.
  θ = exp(-T(dt) / T(ou.correlation_time))
  s = sqrt(T(ou.variance) * (one(T) - θ^2))
  β = noise_variance > 0 ? s / sqrt(T(noise_variance)) : zero(T)
  combine!(ou.state, θ, ou.state, β, noise_spectral)                        # f̂ ← θ f̂ + √(σ²(1-θ²)) ξ̂
  return nothing
end

add_forcing_source!(ou::StochasticOU, nonlinear, domain::FixedDomain) =
  add!(nonlinear, nonlinear, ou.state)


# Operator-free keyword constructors: capture the parameters now and build the forcing once the
# domain exists (via `DeferredForcing`), so a case can name its forcing before the grid is built —
# `ConstantPower(target = 0.1)` — with `Simulation` supplying the domain.
Linear(; rate::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  DeferredForcing(domain -> Linear(domain; rate, lowest_shell, highest_shell))

ConstantPower(; target::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  DeferredForcing(domain -> ConstantPower(domain; target, lowest_shell, highest_shell))

BandRescaling(; target::Real, over::Symbol = :band, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  DeferredForcing(domain -> BandRescaling(domain; target, over, lowest_shell, highest_shell))

StochasticOU(; variance::Real, correlation_time::Real,
             lowest_shell::Integer = 1, highest_shell::Integer = 2, seed::Integer = 0) =
  DeferredForcing(domain -> StochasticOU(domain; variance, correlation_time, lowest_shell, highest_shell, seed))


end # module Forcing
