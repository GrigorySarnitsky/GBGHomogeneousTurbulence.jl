# Forcing — the pluggable energy-injection strategies, concrete `AbstractForcing` subtypes that hook
# into the time step in one of two ways:
#
#   * `forcing_rate!` — for forcings LINEAR in the field (`f = A·field`): fill a per-mode rate A(k)
#     that is folded into the integrating factor, so the linear operator becomes A(k) - D|k|². This
#     is exact for the linear forcing and preserves the integrator's order (no operator splitting).
#     `Linear` (fixed A) and `ConstantPower` (A set each step so the injection rate is ε_target) use it.
#   * `apply_forcing!` — a post-step projection/rescale. `BandRescaling` (hold band energy fixed) uses it.
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
per-step state advance), and [`forcing_source!`](@ref) (an additive per-stage source). `NoForcing`,
`BandRescaling`, `Linear`, `ConstantPower`, and the stochastic `StochasticOU` are provided; one
implementation serves both the velocity and the scalar ``\\varphi``.
"""
module Forcing

using GBGPeriodicFields
using Random
using ..SimulationState: SpectralOperators, scalar_spectral, spectral_vector

export AbstractForcing, ForcingSpec, NoForcing, BandRescaling, Linear, ConstantPower, StochasticOU,
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

A deferred forcing. The operator-free keyword constructors — `Linear(; rate)`, `ConstantPower(; power)`,
`BandRescaling(; energy)`, and `StochasticOU(; variance, correlation_time)` — return a `ForcingSpec`
capturing the parameters; it is materialised into the concrete `AbstractForcing` once the
`SpectralOperators` exist (done for you by `Simulation`). A forcing argument therefore accepts either a
ready-built `AbstractForcing` (from the `ops`-taking constructor) or a `ForcingSpec`.
"""
struct ForcingSpec{F}
  build::F
end

(spec::ForcingSpec)(ops::SpectralOperators) = spec.build(ops)


"""
    forcing_rate!(forcing, rate, field, ops, ws) -> Bool

For a forcing linear in the field, fill the real per-mode rate array `rate` with ``A(\\mathbf{k})``
(the forcing ``f = A\\,\\texttt{field}``) and return `true`; the integrator folds it into the
integrating factor as ``\\exp\\!\\big((A(\\mathbf{k}) - D\\lvert\\mathbf{k}\\rvert^{2})\\,\\tau\\big)``.
Return `false` (the default) when the forcing contributes no linear rate. `field` is the
start-of-step field in spectral representation.
"""
forcing_rate!(::AbstractForcing, rate, field, ops::SpectralOperators, ws) = false


"""
    apply_forcing!(forcing, field, ops, scratch) -> field

Apply a post-step forcing to `field` (a velocity or scalar ``\\varphi`` field in spectral
representation) in place, using the spectral `scratch` buffer. The default does nothing; see
`BandRescaling`.
"""
apply_forcing!(::AbstractForcing, field, ops::SpectralOperators, scratch) = field


"""
    prepare_forcing!(forcing, field, ops, ws, dt) -> nothing

Update a forcing's internal state once per step, before the Runge–Kutta stages, from the
start-of-step `field` (in spectral representation) and the timestep `dt`. The default does nothing;
the stochastic forcing advances its Ornstein–Uhlenbeck process here (see `StochasticOU`).
"""
prepare_forcing!(::AbstractForcing, field, ops::SpectralOperators, ws, dt::Real) = nothing


"""
    forcing_source!(forcing, nonlinear, ops, ws) -> nonlinear

Add an additive forcing source to the de-aliased nonlinear-term buffer `nonlinear` at each Runge–Kutta
stage (the source is held fixed over the step, so it integrates at the scheme's order). The default
does nothing; see `StochasticOU`.
"""
forcing_source!(::AbstractForcing, nonlinear, ops::SpectralOperators, ws) = nonlinear


# An annular shell band-pass kernel for shells `lowest ≤ |k| ≤ highest` (integer shells of 2π/L).
function _shell_band(ops::SpectralOperators, lowest::Integer, highest::Integer)
  k0 = 2π / ops.grid.domain_size[1]
  return spectral_band(scalar_spectral(ops), ops.multipliers, (lowest - 0.5) * k0, (highest + 0.5) * k0)
end

_band_scratch(::VectorFieldSpectral, ws) = ws.scratch
_band_scratch(::ScalarFieldSpectral, ws) = ws.scalar_copy


"""
    NoForcing()

The unforced case: both hooks do nothing (a freely decaying field).
"""
struct NoForcing <: AbstractForcing end


"""
    BandRescaling(ops; energy, lowest_shell = 1, highest_shell = 2)

Deterministic constant-energy forcing (post-step). Each step the in-band Fourier modes
(``\\texttt{lowest\\_shell} \\le \\lvert\\mathbf{k}\\rvert \\le \\texttt{highest\\_shell}``, in
integer shells of ``2\\pi/L``) are rescaled by a single factor so the band holds the fixed energy
``\\tfrac12\\langle\\lvert\\cdot\\rvert^{2}\\rangle_{\\mathrm{band}} = \\texttt{energy}`` (band kinetic
energy for the velocity, band variance for the scalar ``\\varphi``). Rescaling preserves the
divergence-free constraint. It fixes the band energy, not the injection rate, so the total energy
oscillates slowly about its mean.
"""
struct BandRescaling{K, T} <: AbstractForcing
  band::K              # annular band-pass kernel (ScalarFieldSpectral)
  target_energy::T     # the energy ½⟨|·|²⟩ held in the band
end

BandRescaling(ops::SpectralOperators; energy::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  BandRescaling(_shell_band(ops, lowest_shell, highest_shell), float(energy))


function apply_forcing!(forcing::BandRescaling, field, ops::SpectralOperators, scratch)
  convolve!(scratch, field, forcing.band)              # band-pass copy into scratch
  band_energy = 0.5 * inner(scratch, scratch)          # ½⟨|·|²_band⟩
  band_energy < 1e-12 && return field                  # nothing in the band yet (guard)
  scale = sqrt(forcing.target_energy / band_energy)
  convolve!(field, field, forcing.band, scale - 1, 1)  # rescale in-band modes (α/β accumulate)
  return field
end


"""
    Linear(ops; rate, lowest_shell = 1, highest_shell = 2)

Linear (negative-damping) forcing ``f = A\\,\\mathbf{u}`` in a low-wavenumber band (Lundgren-type),
with the fixed rate ``A = \\texttt{rate}`` on shells
``\\texttt{lowest\\_shell} \\le \\lvert\\mathbf{k}\\rvert \\le \\texttt{highest\\_shell}``. The rate is
folded into the integrating factor (exact for the linear term), so the forced band modes grow at net
rate ``A - \\nu\\lvert\\mathbf{k}\\rvert^{2}``. A positive `rate` injects energy.
"""
struct Linear{M, T} <: AbstractForcing
  mask::M              # real array: the band indicator (1 in band, 0 outside)
  rate::T              # the linear rate A
end

function Linear(ops::SpectralOperators; rate::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2)
  mask = real.(field_data(_shell_band(ops, lowest_shell, highest_shell)))
  return Linear(mask, float(rate))
end

function forcing_rate!(forcing::Linear, rate, field, ops::SpectralOperators, ws)
  T = eltype(rate)
  rate .= T(forcing.rate) .* forcing.mask
  return true
end


"""
    ConstantPower(ops; power, lowest_shell = 1, highest_shell = 2)

Constant-power forcing: a banded linear forcing ``f = A\\,\\mathbf{u}`` whose rate is set each step so
the energy-injection rate ``\\langle\\mathbf{u}\\cdot f\\rangle = A\\,(2E_{\\mathrm{band}})`` equals
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

function ConstantPower(ops::SpectralOperators; power::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2)
  band = _shell_band(ops, lowest_shell, highest_shell)
  mask = real.(field_data(band))
  return ConstantPower(band, mask, float(power))
end

function forcing_rate!(forcing::ConstantPower, rate, field, ops::SpectralOperators, ws)
  T = eltype(rate)
  scratch = _band_scratch(field, ws)
  convolve!(scratch, field, forcing.band)                       # band-pass copy
  band_energy = 0.5 * inner(scratch, scratch)                   # E_band
  amplitude = band_energy > 1e-12 ? forcing.target_power / (2 * band_energy) : 0.0
  rate .= T(amplitude) .* forcing.mask
  return true
end


"""
    StochasticOU(ops; variance, correlation_time, lowest_shell = 1, highest_shell = 2, seed = 0)

Stochastic (Eswaran–Pope) forcing: each forced Fourier mode in the band
(``\\texttt{lowest\\_shell} \\le \\lvert\\mathbf{k}\\rvert \\le \\texttt{highest\\_shell}``) carries an
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
(see [`forcing_source!`](@ref)), so it integrates at the scheme's order.

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

function StochasticOU(ops::SpectralOperators; variance::Real, correlation_time::Real,
                      lowest_shell::Integer = 1, highest_shell::Integer = 2, seed::Integer = 0)
  band = _shell_band(ops, lowest_shell, highest_shell)
  return StochasticOU(band, float(correlation_time), float(variance), MersenneTwister(seed), nothing)
end

_ou_state(::VectorFieldSpectral, ops) = spectral_vector(ops)
_ou_state(::ScalarFieldSpectral, ops) = scalar_spectral(ops)
_ou_buffers(::VectorFieldSpectral, ws, ops) = (ws.lamb, ws.scratch, ops.velocity_plans)
_ou_buffers(::ScalarFieldSpectral, ws, ops) = (ws.scalar_field, ws.scalar_copy, ops.scalar_plans)


function prepare_forcing!(ou::StochasticOU, field, ops::SpectralOperators, ws, dt::Real)
  T = real(eltype(field_data(field)))
  ou.state === nothing && (ou.state = _ou_state(field, ops))
  noise_physical, noise_spectral, plans = _ou_buffers(field, ws, ops)

  # unit-variance band-limited (and, for the velocity, solenoidal) random increment ξ
  copyto!(field_data(noise_physical), randn(ou.rng, T, size(field_data(noise_physical))...))
  to_spectral!(noise_spectral, noise_physical, plans)
  convolve!(noise_spectral, noise_spectral, ou.band)
  field isa VectorFieldSpectral && helmholtz_projection!(noise_spectral, noise_spectral, ops.multipliers)
  noise_variance = inner(noise_spectral, noise_spectral)
  noise_variance > 0 && (field_data(noise_spectral) .*= one(T) / sqrt(T(noise_variance)))

  # exact Ornstein–Uhlenbeck update
  θ = exp(-T(dt) / T(ou.correlation_time))
  s = sqrt(T(ou.variance) * (one(T) - θ^2))
  field_data(ou.state) .= θ .* field_data(ou.state) .+ s .* field_data(noise_spectral)
  return nothing
end

forcing_source!(ou::StochasticOU, nonlinear, ops::SpectralOperators, ws) =
  (field_data(nonlinear) .+= field_data(ou.state); nonlinear)


# Operator-free keyword constructors: capture the parameters now and build the forcing once the
# operators exist (via `ForcingSpec`), so a case can name its forcing before the grid is built —
# `ConstantPower(power = 0.1)` — with `Simulation` supplying the operators.
Linear(; rate::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  ForcingSpec(ops -> Linear(ops; rate, lowest_shell, highest_shell))

ConstantPower(; power::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  ForcingSpec(ops -> ConstantPower(ops; power, lowest_shell, highest_shell))

BandRescaling(; energy::Real, lowest_shell::Integer = 1, highest_shell::Integer = 2) =
  ForcingSpec(ops -> BandRescaling(ops; energy, lowest_shell, highest_shell))

StochasticOU(; variance::Real, correlation_time::Real,
             lowest_shell::Integer = 1, highest_shell::Integer = 2, seed::Integer = 0) =
  ForcingSpec(ops -> StochasticOU(ops; variance, correlation_time, lowest_shell, highest_shell, seed))


end # module Forcing
