"""
    Phenomenology.Spectra

Model energy spectra — parametrizations of the reference velocity spectrum ``E(\\kappa)``, evaluated
by [`spectrum`](@ref). A model is **composed**: an inertial-range core ``C_K\\varepsilon^{2/3}\\kappa^{-5/3}``
times a large-scale roll-off and a dissipation-range roll-off, each swappable.

- [`ModelSpectrum`](@ref) — the composed spectrum: a Kolmogorov constant, a [`LargeScaleFactor`](@ref),
  and a [`DissipationFactor`](@ref).
- [`LargeScaleFactor`](@ref) / [`DissipationFactor`](@ref) — the swappable roll-off pieces, evaluated
  by [`large_scale_factor`](@ref) / [`dissipation_factor`](@ref); [`PopeLargeScale`](@ref) and
  [`PopeDissipation`](@ref) are Pope's forms.
- [`Pope2000`](@ref) — the Pope (2000) model spectrum, a preset of [`ModelSpectrum`](@ref).
"""
module Spectra

using ..Phenomenology: TurbulenceLaw, FlowParameters, Reference, kolmogorov_length
import ..Phenomenology: spectrum, provenance

export EnergySpectrum, LargeScaleFactor, DissipationFactor, PopeLargeScale, PopeDissipation,
       ModelSpectrum, large_scale_factor, dissipation_factor, Pope2000, spectrum


"""
    EnergySpectrum <: TurbulenceLaw

Supertype of the velocity energy-spectrum models — parametrizations of ``E(\\kappa)`` evaluated by
[`spectrum`](@ref). The concrete composed form is [`ModelSpectrum`](@ref).
"""
abstract type EnergySpectrum <: TurbulenceLaw end


"""
    LargeScaleFactor

Supertype of the dimensionless **large-scale roll-off** factors ``f_L(\\kappa L)`` of a composed
[`ModelSpectrum`](@ref) — the shape that bends the inertial ``\\kappa^{-5/3}`` law over into the
energy-containing range, with ``f_L \\to 1`` as ``\\kappa L \\to \\infty``. Evaluated by
[`large_scale_factor`](@ref); [`PopeLargeScale`](@ref) is Pope's form.
"""
abstract type LargeScaleFactor end


"""
    DissipationFactor

Supertype of the dimensionless **dissipation-range roll-off** factors ``f_\\eta(\\kappa\\eta)`` of a
composed [`ModelSpectrum`](@ref) — the shape that cuts the spectrum off near the Kolmogorov scale, with
``f_\\eta \\to 1`` as ``\\kappa\\eta \\to 0``. Evaluated by [`dissipation_factor`](@ref);
[`PopeDissipation`](@ref) is Pope's form.
"""
abstract type DissipationFactor end


"""
    large_scale_factor(f, κL) -> Float64

Evaluate the dimensionless large-scale roll-off `f` (a [`LargeScaleFactor`](@ref)) at the argument
``\\kappa L`` (`κL`). A new large-scale form is a subtype of [`LargeScaleFactor`](@ref) that adds a
method here.
"""
function large_scale_factor end


"""
    dissipation_factor(f, κη) -> Float64

Evaluate the dimensionless dissipation-range roll-off `f` (a [`DissipationFactor`](@ref)) at the
argument ``\\kappa\\eta`` (`κη`). A new dissipation-range form is a subtype of
[`DissipationFactor`](@ref) that adds a method here.
"""
function dissipation_factor end


"""
    PopeLargeScale(c_L, p₀)

Pope's large-scale roll-off ``f_L(\\kappa L) = \\left(\\dfrac{\\kappa L}{\\sqrt{(\\kappa L)^2 + c_L}}\\right)^{5/3 + p_0}``,
which tends to `1` in the inertial range and rolls the spectrum off below the integral scale. `c_L` is
set by the requirement that the spectrum integrate to the kinetic energy; `p₀` fixes the low-wavenumber
slope (Pope 2000).
"""
struct PopeLargeScale <: LargeScaleFactor
  c_L::Float64
  p₀::Float64
end

large_scale_factor(f::PopeLargeScale, κL) = (κL / sqrt(κL^2 + f.c_L))^(5//3 + f.p₀)


"""
    PopeDissipation(c_η, β)

Pope's dissipation-range roll-off
``f_\\eta(\\kappa\\eta) = \\exp\\!\\big(-\\beta\\{[(\\kappa\\eta)^4 + c_\\eta^4]^{1/4} - c_\\eta\\}\\big)``,
which tends to `1` in the inertial range and cuts the spectrum off near the Kolmogorov scale. `c_η` is
set by the requirement that the spectrum yield the dissipation rate; `β` fixes the sharpness of the
cutoff (Pope 2000).
"""
struct PopeDissipation <: DissipationFactor
  c_η::Float64
  β::Float64
end

dissipation_factor(f::PopeDissipation, κη) = exp(-f.β * ((κη^4 + f.c_η^4)^(1//4) - f.c_η))


"""
    ModelSpectrum(C_K, large_scale, dissipation, ref)

The composed model energy spectrum

```math
E(\\kappa) = C_K\\,\\varepsilon^{2/3}\\,\\kappa^{-5/3}\\,f_L(\\kappa L)\\,f_\\eta(\\kappa\\eta),
```

an inertial-range core with Kolmogorov constant `C_K` times a large-scale roll-off `large_scale` (a
[`LargeScaleFactor`](@ref), giving ``f_L``) and a dissipation-range roll-off `dissipation` (a
[`DissipationFactor`](@ref), giving ``f_\\eta``); `ref` is its [`Reference`](@ref). Build one directly to
mix roll-off forms, or use a preset such as [`Pope2000`](@ref). Evaluated by
[`spectrum`](@ref)`(model, κ, fp)`, which reads ``\\varepsilon`` and ``L`` from `fp` and forms
``\\eta`` with [`kolmogorov_length`](@ref).
"""
struct ModelSpectrum{L<:LargeScaleFactor, D<:DissipationFactor} <: EnergySpectrum
  C_K::Float64
  large_scale::L
  dissipation::D
  ref::Reference
end

spectrum(m::ModelSpectrum, κ, fp::FlowParameters) =
  m.C_K * fp.dissipation^(2//3) * κ^(-5//3) *
  large_scale_factor(m.large_scale, κ * fp.integral_scale) *
  dissipation_factor(m.dissipation, κ * kolmogorov_length(fp))

provenance(m::ModelSpectrum) = m.ref


const _POPE2000 = Reference("Pope (2000), *Turbulent Flows* §6.5"; valid_Reλ = (30.0, Inf))

"""
    Pope2000(; C_K = 1.5, c_L = 6.78, p₀ = 2.0, c_η = 0.40, β = 5.2)

The Pope (2000) model spectrum — a preset [`ModelSpectrum`](@ref) with [`PopeLargeScale`](@ref) and
[`PopeDissipation`](@ref) roll-offs:

```math
E(\\kappa) = C_K\\,\\varepsilon^{2/3}\\,\\kappa^{-5/3}\\,f_L(\\kappa L)\\,f_\\eta(\\kappa\\eta).
```

`C_K` is the Kolmogorov constant; the defaults `c_L = 6.78`, `c_η = 0.40` are the high-Reynolds-number
values Pope obtains from the energy and dissipation normalizations, with the shape exponents `p₀ = 2`
and `β = 5.2`. Override any coefficient to re-fit. Evaluate with [`spectrum`](@ref)`(Pope2000(), κ, fp)`.
"""
Pope2000(; C_K = 1.5, c_L = 6.78, p₀ = 2.0, c_η = 0.40, β = 5.2) =
  ModelSpectrum(C_K, PopeLargeScale(c_L, p₀), PopeDissipation(c_η, β), _POPE2000)


end # module Spectra
