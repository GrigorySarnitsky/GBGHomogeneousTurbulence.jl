"""
    Phenomenology.Spectra

Model spectra — parametrizations of the reference velocity spectrum ``E(\\kappa)`` and the scalar
spectrum ``E_\\varphi(\\kappa)``, evaluated by [`spectrum`](@ref). A velocity model is **composed**: an
inertial-range core ``C_K\\varepsilon^{2/3}\\kappa^{-5/3}`` times a large-scale roll-off and a
dissipation-range roll-off, each swappable.

- [`ModelSpectrum`](@ref) — the composed velocity spectrum: a Kolmogorov constant, a
  [`LargeScaleFactor`](@ref), and a [`DissipationFactor`](@ref).
- [`LargeScaleFactor`](@ref) / [`DissipationFactor`](@ref) — the swappable roll-off pieces, evaluated by
  [`large_scale_factor`](@ref) / [`dissipation_factor`](@ref): [`PopeLargeScale`](@ref) /
  [`PopeDissipation`](@ref) are Pope's forms, [`VonKarmanLarge`](@ref) the classic ``\\kappa^4`` energy
  range, [`PaoDissipation`](@ref) Pao's cutoff, [`ExponentialDissipation`](@ref) the closure-predicted
  exponential cutoff, [`SaffmanDissipation`](@ref) a Gaussian cutoff, and [`UnitLargeScale`](@ref) /
  [`UnitDissipation`](@ref) are the trivial (no-roll-off) factors.
- [`Pope2000`](@ref) / [`VonKarman1948`](@ref) / [`Pao1965`](@ref) — named velocity-spectrum presets of
  [`ModelSpectrum`](@ref).
- [`ScalarSpectrum`](@ref) — the passive-scalar spectra; [`ObukhovCorrsin1949`](@ref) is the
  inertial-convective range.
"""
module Spectra

using ..Phenomenology: TurbulenceLaw, FlowParameters, Reference, kolmogorov_length
import ..Phenomenology: spectrum, provenance

export EnergySpectrum, ScalarSpectrum, LargeScaleFactor, DissipationFactor, PopeLargeScale,
       PopeDissipation, VonKarmanLarge, UnitLargeScale, UnitDissipation, PaoDissipation,
       ExponentialDissipation, SaffmanDissipation, ModelSpectrum, large_scale_factor,
       dissipation_factor, Pope2000, VonKarman1948, Pao1965, ObukhovCorrsin1949, spectrum


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

!!! note "Bottleneck models deferred"
    These factors are inertial-normalized cutoffs. Models of the near-dissipation *bottleneck* — a bump
    before the cutoff (Qian 1984; Ishihara et al. 2005; Kraichnan 1959, all of the form
    ``A(\\kappa\\eta)^\\gamma\\exp(-\\beta\\kappa\\eta)`` with ``\\gamma < 0``) — do not satisfy
    ``f_\\eta\\to 1`` and need a richer spectrum structure; they are deliberately deferred.
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
    VonKarmanLarge(c_L)

The von Kármán large-scale roll-off
``f_L(\\kappa L) = \\left(\\dfrac{(\\kappa L)^2}{(\\kappa L)^2 + c_L}\\right)^{17/6}``, which tends to `1`
in the inertial range and produces the classic ``\\kappa^4`` energy-containing range at low wavenumber
(``E \\sim \\kappa^{-5/3}f_L \\sim \\kappa^4``); `c_L` fixes the peak scale (von Kármán 1948).
"""
struct VonKarmanLarge <: LargeScaleFactor
  c_L::Float64
end

large_scale_factor(f::VonKarmanLarge, κL) = (κL^2 / (κL^2 + f.c_L))^(17//6)


"""
    UnitDissipation()

The trivial dissipation-range factor ``f_\\eta \\equiv 1`` — no viscous cutoff, for a spectrum defined
only over the energy-containing and inertial ranges (the classic [`VonKarman1948`](@ref) form).
"""
struct UnitDissipation <: DissipationFactor end

dissipation_factor(::UnitDissipation, κη) = one(κη)


"""
    UnitLargeScale()

The trivial large-scale factor ``f_L \\equiv 1`` — no energy-containing roll-off, for a spectrum defined
only over the inertial and dissipation ranges (the [`Pao1965`](@ref) form).
"""
struct UnitLargeScale <: LargeScaleFactor end

large_scale_factor(::UnitLargeScale, κL) = one(κL)


"""
    PaoDissipation(α)

Pao's dissipation-range roll-off
``f_\\eta(\\kappa\\eta) = \\exp\\!\\big(-\\tfrac32\\,\\alpha\\,(\\kappa\\eta)^{4/3}\\big)``, from the
hypothesis that the spectral energy flux stays constant through the dissipation range; `α` is the
Kolmogorov constant ``C_K`` (Pao 1965).
"""
struct PaoDissipation <: DissipationFactor
  α::Float64
end

dissipation_factor(f::PaoDissipation, κη) = exp(-1.5 * f.α * κη^(4//3))


"""
    ExponentialDissipation(β)

The pure-exponential dissipation-range roll-off ``f_\\eta(\\kappa\\eta) = \\exp(-\\beta\\,\\kappa\\eta)``
— the ``n = 1`` case of the general ``\\exp(-\\beta(\\kappa\\eta)^n)`` family, and the form the triadic
spectral closures (EDQNM, DIA, LRA) consistently predict (Kaneda 1993; Sagaut & Cambon 2018). `β` is
fit-dependent — of order `0.6` in high-Reynolds-number DNS (Ishihara et al. 2005) — and the factor
tends to `1` in the inertial range (``\\kappa\\eta \\to 0``).
"""
struct ExponentialDissipation <: DissipationFactor
  β::Float64
end

dissipation_factor(f::ExponentialDissipation, κη) = exp(-f.β * κη)


"""
    SaffmanDissipation()

Saffman's Gaussian dissipation-range roll-off ``f_\\eta(\\kappa\\eta) = \\exp(-2(\\kappa\\eta)^2)``
(Saffman 1963) — a simple, parameter-free cutoff that tends to `1` in the inertial range.
"""
struct SaffmanDissipation <: DissipationFactor end

dissipation_factor(::SaffmanDissipation, κη) = exp(-2 * κη^2)


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

This is the standard generic form for a model spectrum (Sagaut & Cambon 2018; Pope 2000; Meyers &
Meneveau 2008); the large-scale roll-off sets the low-wavenumber slope
``E(\\kappa\\to 0)\\propto\\kappa^\\sigma`` — ``\\sigma = 2`` (Saffman-type, the [`PopeLargeScale`](@ref)
default) or ``\\sigma = 4`` (Batchelor-type, [`VonKarmanLarge`](@ref)).
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


const _VONKARMAN2000 = Reference("von Kármán (1948), *Proc. Natl. Acad. Sci.* **34**, 530"; valid_Reλ = (0.0, Inf))

"""
    VonKarman1948(; C_K = 1.5, c_L = 1.0)

The von Kármán (1948) energy spectrum — a preset [`ModelSpectrum`](@ref) with the
[`VonKarmanLarge`](@ref) roll-off and no viscous cutoff ([`UnitDissipation`](@ref)):

```math
E(\\kappa) = C_K\\,\\varepsilon^{2/3}\\,\\kappa^{-5/3}
             \\left(\\frac{(\\kappa L)^2}{(\\kappa L)^2 + c_L}\\right)^{17/6},
```

the classic interpolation between the ``\\kappa^4`` energy-containing range and the ``\\kappa^{-5/3}``
inertial range, with no dissipation-range cutoff (use [`Pope2000`](@ref) when the cutoff matters). `C_K`
is the Kolmogorov constant; `c_L` fixes the peak scale.
"""
VonKarman1948(; C_K = 1.5, c_L = 1.0) =
  ModelSpectrum(C_K, VonKarmanLarge(c_L), UnitDissipation(), _VONKARMAN2000)


const _PAO1965 = Reference("Pao (1965), *Phys. Fluids* **8**, 1063"; valid_Reλ = (0.0, Inf))

"""
    Pao1965(; C_K = 1.5)

The Pao (1965) energy spectrum — a preset [`ModelSpectrum`](@ref) with no energy-containing roll-off
([`UnitLargeScale`](@ref)) and the [`PaoDissipation`](@ref) cutoff:

```math
E(\\kappa) = C_K\\,\\varepsilon^{2/3}\\,\\kappa^{-5/3}\\,
             \\exp\\!\\big(-\\tfrac32\\,C_K\\,(\\kappa\\eta)^{4/3}\\big),
```

covering the inertial and dissipation ranges from a constant-spectral-flux hypothesis — the Kolmogorov
constant `C_K` appears in both the amplitude and the cutoff, so the cutoff carries no free constant
(unlike [`Pope2000`](@ref)). It has no energy-containing range; use [`Pope2000`](@ref) or
[`VonKarman1948`](@ref) when the large scales matter.
"""
Pao1965(; C_K = 1.5) = ModelSpectrum(C_K, UnitLargeScale(), PaoDissipation(C_K), _PAO1965)


"""
    ScalarSpectrum <: TurbulenceLaw

Supertype of the passive-scalar spectrum models — parametrizations of ``E_\\varphi(\\kappa)``, the
density in wavenumber of the scalar variance ``\\langle\\varphi^2\\rangle``, evaluated by
[`spectrum`](@ref). [`ObukhovCorrsin1949`](@ref) is the inertial-convective range.
"""
abstract type ScalarSpectrum <: TurbulenceLaw end


const _OBUKHOVCORRSIN = Reference("Obukhov (1949) / Corrsin (1951)"; valid_Reλ = (50.0, Inf))

"""
    ObukhovCorrsin1949(; C_OC = 0.67)

The Obukhov–Corrsin inertial-convective scalar spectrum

```math
E_\\varphi(\\kappa) = C_{OC}\\,\\varepsilon_\\varphi\\,\\varepsilon^{-1/3}\\,\\kappa^{-5/3},
```

the scalar analogue of the Kolmogorov ``-5/3`` law: for a Schmidt number of order one the scalar's
inertial-convective range coincides with the velocity inertial range. `C_OC` is the Obukhov–Corrsin
constant (``\\approx 0.67`` for the three-dimensional spectrum). [`spectrum`](@ref) reads the scalar
dissipation ``\\varepsilon_\\varphi`` (`fp.scalar_dissipation`, which must be set) and the
kinetic-energy dissipation ``\\varepsilon`` from `fp`.
"""
struct ObukhovCorrsin1949 <: ScalarSpectrum
  C_OC::Float64
end

ObukhovCorrsin1949(; C_OC = 0.67) = ObukhovCorrsin1949(C_OC)

function spectrum(m::ObukhovCorrsin1949, κ, fp::FlowParameters)
  isnan(fp.scalar_dissipation) && throw(ArgumentError(
    "ObukhovCorrsin1949 needs the scalar dissipation rate — set `scalar_dissipation` in FlowParameters"))
  return m.C_OC * fp.scalar_dissipation * fp.dissipation^(-1//3) * κ^(-5//3)
end

provenance(::ObukhovCorrsin1949) = _OBUKHOVCORRSIN


end # module Spectra
