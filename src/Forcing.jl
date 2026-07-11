# Forcing — the pluggable energy-injection strategies, concrete `AbstractForcing` subtypes that hook
# into the time step in one of two ways:
#
#   * `forcing_rate!` — for forcings LINEAR in the field (`f = A·field`): fill a per-mode rate A(k)
#     that is folded into the integrating factor, so the linear operator becomes A(k) - D|k|². This
#     is exact for the linear forcing and preserves the integrator's order (no operator splitting).
#     `Linear` (fixed A) and `ConstantPower` (A set each step so the injection rate is ε_target) use it.
#   * `apply_forcing!` — a post-step projection/rescale. `BandRescaling` (hold band or total energy fixed) uses it.
#
# One implementation serves both the velocity (a vector field) and the scalar φ (a scalar field),
# since the hooks are written through tensor-order-generic field operators. A linear rate keeps a
# solenoidal velocity solenoidal (per-mode scaling), so the velocity needs no projection here.
#
# The additive stochastic (Ornstein–Uhlenbeck / Eswaran–Pope) forcing — which adds a time-correlated
# force field to the RHS — is a separate, stateful mechanism (`StochasticOU`), advanced once per step.

"""
    Forcing

The pluggable energy-injection strategies, concrete `AbstractForcing` subtypes. A strategy hooks into
the step through up to four methods — [`forcing_rate!`](@ref) (a linear rate folded into the
integrating factor), [`apply_forcing!`](@ref) (a post-step projection), [`prepare_forcing!`](@ref) (a
per-step state advance), and [`forcing_source!`](@ref) (an additive per-stage source).
Every step hook takes the operator bundle `domain` (a [`SimulationDomain`](@ref)) — as do the
`domain`-taking forcing constructors, which build their band kernels from it; `forcing_rate!`,
`prepare_forcing!`, and `forcing_source!` additionally take the preallocated scratch `buffers` (a
[`FieldBuffers`](@ref GBGIsotropicTurbulence.SimulationState.FieldBuffers)), while `apply_forcing!` takes a spectral `scratch` buffer. `NoForcing`,
`BandRescaling`, `Linear`, and `ConstantPower` are provided; one
implementation serves both the velocity and the scalar, and the two are forced **independently** —
`Physics` takes a separate `velocity_forcing` and `scalar_forcing` (each an `AbstractForcing`, each
defaulting to `NoForcing()`), so a run can force the velocity while the scalar decays freely, force
both (with the same or different strategies), or leave either unforced. An operator-free keyword
constructor returns a [`ForcingSpec`](@ref), a deferred forcing that `Simulation` materialises once
the domain exists.
"""
module Forcing

using GBGPeriodicFields
using Random
using ..SimulationState: SimulationDomain, scalar_spectral, spectral_vector

export AbstractForcing, ForcingSpec, NoForcing, BandRescaling, Linear, ConstantPower,
       forcing_rate!, apply_forcing!, prepare_forcing!, forcing_source!


"""
    AbstractForcing

Supertype of the energy-injection strategies. A strategy may implement any of [`forcing_rate!`](@ref)
(a linear forcing rate folded into the integrating factor), [`apply_forcing!`](@ref) (a post-step
projection), [`prepare_forcing!`](@ref) (a per-step state advance), and [`forcing_source!`](@ref) (an
additive per-stage source); all default to doing nothing.
"""
abstract type AbstractForcing end


"""
    ForcingSpec

A deferred forcing. The operator-free keyword constructors — `Linear(; rate)`, `ConstantPower(; power)`, and
`BandRescaling(; energy)` — return a `ForcingSpec`
capturing the parameters; it is materialised into the concrete `AbstractForcing` once the
`SimulationDomain` exist (done for you by `Simulation`). A forcing argument therefore accepts either a
ready-built `AbstractForcing` (from the `domain`-taking constructor) or a `ForcingSpec`.
"""
struct ForcingSpec{F}
  build::F
end

(spec::ForcingSpec)(domain::SimulationDomain) = spec.build(domain)


"""
    forcing_rate!(forcing, rate, field, domain, buffers) -> Bool

For a forcing linear in the field, fill the real per-mode rate array `rate` with ``A(\\boldsymbol{\\kappa})``
(the forcing ``f = A\\,\\texttt{field}``) and return `true`; the integrator folds it into the diffusive
integrating factor ``\\mathcal E(\\boldsymbol{\\kappa})`` (see [`integrating_factor!`](@ref GBGIsotropicTurbulence.Dynamics.integrating_factor!)), so the
forced modes advance at the net linear rate ``A(\\boldsymbol{\\kappa}) - D\\lvert\\boldsymbol{\\kappa}\\rvert^{2}``
(``D`` the field's diffusivity). Return `false` (the default) when the forcing contributes no linear
rate. `field` is the start-of-step field in spectral representation.
"""
forcing_rate!(::AbstractForcing, rate, field, domain::SimulationDomain, buffers) = false


"""
    apply_forcing!(forcing, field, domain, scratch) -> field

Apply a post-step forcing to `field` (a velocity or scalar ``\\varphi`` field in spectral
representation) in place, using the spectral `scratch` buffer. The default does nothing; see
`BandRescaling`.
"""
apply_forcing!(::AbstractForcing, field, domain::SimulationDomain, scratch) = field


"""
    prepare_forcing!(forcing, field, domain, buffers, dt) -> nothing

Update a forcing's internal state once per step, before the Runge–Kutta stages, from the
start-of-step `field` (in spectral representation) and the timestep `dt`. The default does nothing.
"""
prepare_forcing!(::AbstractForcing, field, domain::SimulationDomain, buffers, dt::Real) = nothing


"""
    forcing_source!(forcing, nonlinear, domain, buffers) -> nonlinear

Add an additive forcing source to the de-aliased nonlinear-term buffer `nonlinear` at each Runge–Kutta
stage (the source is held fixed over the step, so it integrates at the scheme's order). The default
does nothing.
"""
forcing_source!(::AbstractForcing, nonlinear, domain::SimulationDomain, buffers) = nonlinear


# An annular shell band-pass kernel for shells `lowest ≤ |k| ≤ highest` (integer shells of 2π/L).
function _shell_band(domain::SimulationDomain, lowest::Integer, highest::Integer)
  k0 = 2π / domain.grid.domain_size[1]
  return spectral_band(scalar_spectral(domain), domain.multipliers, (lowest - 0.5) * k0, (highest + 0.5) * k0)
end


"""
    NoForcing()

The unforced case: all four hooks keep their defaults (do nothing) — a freely decaying field.
"""
struct NoForcing <: AbstractForcing end


"""
    BandRescaling(domain; energy, target = :band, lowest_shell = 1, highest_shell = 2)

Deterministic constant-energy forcing (post-step). Each step the in-band Fourier modes (integer
shells ``\\texttt{lowest\\_shell} \\le \\kappa \\le \\texttt{highest\\_shell}`` of
``2\\pi/L``) are rescaled by a single factor; `target` selects what is held fixed:

  * `:band` (default) — the band's own energy ``\\tfrac12\\langle\\lvert\\cdot\\rvert^{2}\\rangle_{\\mathrm{band}} = \\texttt{energy}`` (band kinetic energy for the velocity, half the band scalar variance ``\\tfrac12\\langle\\varphi^{2}\\rangle_{\\mathrm{band}}`` for the scalar ``\\varphi``); the *total* energy then floats, oscillating slowly about its mean as the band feeds the cascade.
  * `:total` — the band is rescaled to absorb the whole-field deficit so the *total* energy ``\\tfrac12\\langle\\lvert\\cdot\\rvert^{2}\\rangle = \\texttt{energy}``, which directly pins the r.m.s. velocity ``u'`` and hence ``\\mathrm{Re}_\\lambda``. If the out-of-band energy alone exceeds `energy`, the band is zeroed (the closest reachable state).

Rescaling preserves the divergence-free constraint either way.
"""
struct BandRescaling{K, T} <: AbstractForcing
  band::K              # annular band-pass kernel (ScalarFieldSpectral)
  target_energy::T     # the energy ½⟨|·|²⟩ to hold (in the band, or the total)
  target::Symbol       # :band (hold the band energy) or :total (hold the total energy)
end

function BandRescaling(domain::SimulationDomain; energy::Real, target::Symbol = :band,
                       lowest_shell::Integer = 1, highest_shell::Integer = 2)
  target in (:band, :total) ||
    throw(ArgumentError("BandRescaling `target` must be :band or :total; got :$target"))
  return BandRescaling(_shell_band(domain, lowest_shell, highest_shell), float(energy), target)
end


function apply_forcing!(forcing::BandRescaling, field, domain::SimulationDomain, scratch)
  band_energy = 0.5 * weighted_inner(field, forcing.band)  # ½⟨|·|²⟩ in the band (fused; no band-pass copy)
  band_energy < 1e-12 && return field                  # nothing in the band yet (guard)
  # aim the band at: the target itself (:band), or what makes the *total* hit the target (:total)
  target_band = if forcing.target === :total
    total_energy = 0.5 * inner(field, field)           # ½⟨|·|²⟩ over the whole field
    max(zero(band_energy), forcing.target_energy - total_energy + band_energy)
  else
    forcing.target_energy
  end
  scale = sqrt(target_band / band_energy)
  convolve!(field, field, forcing.band, scale - 1, 1)  # rescale in-band modes (α/β accumulate)
  return field
end


"""
    Linear(domain; rate, lowest_shell = 1, highest_shell = 2)

Linear (negative-damping) forcing ``f = A\\,\\boldsymbol{u}`` in a low-wavenumber band (Lundgren 2003),
with the fixed rate ``A = \\texttt{rate}`` on shells
``\\texttt{lowest\\_shell} \\le \\kappa \\le \\texttt{highest\\_shell}``. The rate is
folded into the integrating factor (exact for the linear term), so the forced band modes grow at net
rate ``A - \\nu\\lvert\\boldsymbol{\\kappa}\\rvert^{2}``. A positive `rate` injects energy.
"""
struct Linear{M, T} <: AbstractForcing
  mask::M              # real array: the band indicator (1 in band, 0 outside)
  rate::T              # the linear rate A
end

function Linear(domain::SimulationDomain; rate::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2)
  mask = real.(field_data(_shell_band(domain, lowest_shell, highest_shell)))
  return Linear(mask, float(rate))
end

function forcing_rate!(forcing::Linear, rate, field, domain::SimulationDomain, buffers)
  T = eltype(rate)
  rate .= T(forcing.rate) .* forcing.mask
  return true
end


"""
    ConstantPower(domain; power, lowest_shell = 1, highest_shell = 2)

Constant-power forcing: a banded linear forcing ``f = A\\,\\boldsymbol{u}`` on integer shells
``\\texttt{lowest\\_shell} \\le \\kappa \\le \\texttt{highest\\_shell}`` of ``2\\pi/L`` (default 1–2),
whose rate is set each step so the energy-injection rate
``\\langle\\boldsymbol{u}\\cdot f\\rangle = A\\,(2E_{\\mathrm{band}})`` equals
the target ``\\varepsilon = \\texttt{power}`` — i.e. ``A = \\varepsilon / (2E_{\\mathrm{band}})`` with
``E_{\\mathrm{band}} = \\tfrac12\\langle\\lvert\\cdot\\rvert^{2}\\rangle_{\\mathrm{band}}`` of the
start-of-step field. The rate is folded into the integrating factor; like `Linear`, it preserves a
solenoidal velocity.
"""
struct ConstantPower{K, M, T} <: AbstractForcing
  band::K              # band-pass kernel (for the band energy)
  mask::M              # real array band indicator
  target_power::T      # the target injection rate ε
end

function ConstantPower(domain::SimulationDomain; power::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2)
  band = _shell_band(domain, lowest_shell, highest_shell)
  mask = real.(field_data(band))
  return ConstantPower(band, mask, float(power))
end

function forcing_rate!(forcing::ConstantPower, rate, field, domain::SimulationDomain, buffers)
  T = eltype(rate)
  band_energy = 0.5 * weighted_inner(field, forcing.band)       # E_band (fused; no band-pass copy)
  amplitude = band_energy > 1e-12 ? forcing.target_power / (2 * band_energy) : 0.0
  rate .= T(amplitude) .* forcing.mask
  return true
end


"""
    StochasticOU(domain; variance, correlation_time, lowest_shell = 1, highest_shell = 2,
                 seed = 0)

Stochastic (Eswaran–Pope) forcing: each forced Fourier mode in the band
(``\\texttt{lowest\\_shell} \\le \\kappa \\le \\texttt{highest\\_shell}``) carries an
independent complex Ornstein–Uhlenbeck process, advanced once per step by the exact transition

```math
\\hat f \\leftarrow \\theta\\,\\hat f + \\sqrt{\\sigma^{2}(1-\\theta^{2})}\\;\\xi,
\\qquad \\theta = \\exp(-\\Delta t / T_L),
```

with correlation time ``T_L = \\texttt{correlation\\_time}``, stationary forcing variance
``\\sigma^{2} = \\texttt{variance}`` (the stationary ``\\langle\\lvert f\\rvert^{2}\\rangle``), and
``\\xi`` a unit-variance, band-limited random field. The increment ``\\xi`` is generated as a real
physical field, transformed, and band-limited — guaranteeing a valid real field with no
Hermitian-symmetry bookkeeping — and, when forcing the velocity (a vector field), Leray-projected so
the forcing is divergence-free. The frozen ``\\hat f`` is added to the right-hand side at each stage
(see [`forcing_source!`](@ref)), so it integrates at the scheme's order. The `seed` (default 0) fixes
the random stream, so a forced run is reproducible.

The same type forces either the velocity or the scalar ``\\varphi``: it adapts to the field it is
given (a vector or scalar state, projected only for the velocity), allocated on first use.

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
end

function StochasticOU(domain::SimulationDomain; variance::Real, correlation_time::Real,
                      lowest_shell::Integer = 1, highest_shell::Integer = 2, seed::Integer = 0)
  band = _shell_band(domain, lowest_shell, highest_shell)
  return StochasticOU(band, float(correlation_time), float(variance), MersenneTwister(seed), nothing)
end

_ou_state(::VectorFieldSpectral, domain) = spectral_vector(domain)
_ou_state(::ScalarFieldSpectral, domain) = scalar_spectral(domain)
_ou_buffers(::VectorFieldSpectral, buffers, domain) = (buffers.lamb, buffers.scratch, domain.velocity_plans)
_ou_buffers(::ScalarFieldSpectral, buffers, domain) = (buffers.scalar.field, buffers.scalar.copy, domain.scalar_plans)


function prepare_forcing!(ou::StochasticOU, field, domain::SimulationDomain, buffers, dt::Real)
  T = real(eltype(field_data(field)))
  ou.state === nothing && (ou.state = _ou_state(field, domain))
  noise_physical, noise_spectral, plans = _ou_buffers(field, buffers, domain)

  # unit-variance band-limited (and, for the velocity, solenoidal) random increment ξ
  copyto!(field_data(noise_physical), randn(ou.rng, T, size(field_data(noise_physical))...))
  to_spectral!(noise_spectral, noise_physical, plans)
  convolve!(noise_spectral, noise_spectral, ou.band)
  field isa VectorFieldSpectral && helmholtz_projection!(noise_spectral, noise_spectral, domain.multipliers)
  noise_variance = inner(noise_spectral, noise_spectral)
  noise_variance > 0 && multiply!(noise_spectral, one(T) / sqrt(T(noise_variance)), noise_spectral)

  # exact Ornstein–Uhlenbeck update
  θ = exp(-T(dt) / T(ou.correlation_time))
  s = sqrt(T(ou.variance) * (one(T) - θ^2))
  combine!(ou.state, θ, ou.state, s, noise_spectral)                        # f̂ ← θ f̂ + √(σ²(1-θ²)) ξ
  return nothing
end

forcing_source!(ou::StochasticOU, nonlinear, domain::SimulationDomain, buffers) =
  add!(nonlinear, nonlinear, ou.state)


# Operator-free keyword constructors: capture the parameters now and build the forcing once the
# domain exists (via `ForcingSpec`), so a case can name its forcing before the grid is built —
# `ConstantPower(power = 0.1)` — with `Simulation` supplying the domain.
Linear(; rate::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  ForcingSpec(domain -> Linear(domain; rate, lowest_shell, highest_shell))

ConstantPower(; power::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  ForcingSpec(domain -> ConstantPower(domain; power, lowest_shell, highest_shell))

BandRescaling(; energy::Real, target::Symbol = :band, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  ForcingSpec(domain -> BandRescaling(domain; energy, target, lowest_shell, highest_shell))

StochasticOU(; variance::Real, correlation_time::Real,
             lowest_shell::Integer = 1, highest_shell::Integer = 2, seed::Integer = 0) =
  ForcingSpec(domain -> StochasticOU(domain; variance, correlation_time, lowest_shell, highest_shell, seed))


end # module Forcing
