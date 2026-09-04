"""
    Phenomenology.Spectra

Model spectra — parametrizations of the reference velocity spectrum ``E(\\kappa)`` and the scalar
spectrum ``E_\\varphi(\\kappa)``, evaluated by [`spectrum`](@ref). A velocity model is **composed** —
an inertial-range core times a large-scale roll-off and a dissipation-range roll-off, each
swappable — and [`ModelSpectrum`](@ref) owns the formula.

- `ModelSpectrum` — the composed velocity spectrum: a Kolmogorov constant, a
  [`LargeScaleFactor`](@ref), and a [`DissipationFactor`](@ref).
- `LargeScaleFactor` / `DissipationFactor` — the swappable roll-off pieces, evaluated by
  [`large_scale_factor`](@ref) — at the length [`large_scale_length`](@ref) supplies — and
  [`dissipation_factor`](@ref): [`PopeLargeScale`](@ref) /
  [`PopeDissipation`](@ref) are Pope's forms, [`VonKarmanLarge`](@ref) the classic ``\\kappa^{4}`` energy
  range, [`PaoDissipation`](@ref) Pao's cutoff, [`ExponentialDissipation`](@ref) the closure-predicted
  exponential cutoff, [`SaffmanDissipation`](@ref) a Gaussian cutoff, and [`UnitLargeScale`](@ref) /
  [`UnitDissipation`](@ref) are the trivial (no-roll-off) factors.
- [`EnergySpectrum`](@ref) — the velocity-spectrum family root; [`Pope2000`](@ref) /
  [`VonKarman1948`](@ref) / [`Pao1965`](@ref) are its named presets, each a composed
  `ModelSpectrum`.
- [`ScalarSpectrum`](@ref) — the passive-scalar spectra; [`ObukhovCorrsin1949`](@ref) is the
  inertial-convective range.

Every preset is a type with a keyword constructor, invoked as `Name(; …)`; the roll-off **factor**
pieces they compose (`PopeLargeScale`, `ExponentialDissipation`, …) are plain positional parameter
records. The velocity-spectrum
presets `Pope2000` / `VonKarman1948` / `Pao1965` name the `ModelSpectrum` specialization
carrying their large-scale and dissipation factors, so a preset is the composition rather than a
wrapper around one; the scalar preset `ObukhovCorrsin1949`, like the structure-function and scaling
laws, is a plain struct.
"""
module Spectra

using ..Phenomenology: TurbulenceLaw, FlowParameters, Reference, kolmogorov_length
import ..Phenomenology: spectrum, provenance

export EnergySpectrum, ScalarSpectrum, LargeScaleFactor, DissipationFactor, PopeLargeScale,
       PopeDissipation, VonKarmanLarge, UnitLargeScale, UnitDissipation, PaoDissipation,
       ExponentialDissipation, SaffmanDissipation, ModelSpectrum, large_scale_factor, large_scale_length,
       dissipation_factor, Pope2000, VonKarman1948, Pao1965, ObukhovCorrsin1949, spectrum


"""
    EnergySpectrum <: TurbulenceLaw

Supertype of the velocity energy-spectrum models — parametrizations of ``E(\\kappa)`` evaluated by
[`spectrum`](@ref). The concrete composed form is [`ModelSpectrum`](@ref).
"""
abstract type EnergySpectrum <: TurbulenceLaw end


"""
    LargeScaleFactor

Supertype of the dimensionless **large-scale roll-off** factors ``f_L(\\kappa \\ell)`` — with
``\\ell`` the length that form's own coefficient was fitted against, *not* the box side ``L`` — of a composed
[`ModelSpectrum`](@ref) — the shape that bends the inertial ``\\kappa^{-5/3}`` law over into the
energy-containing range, with ``f_L \\to 1`` as ``\\kappa \\ell \\to \\infty``. Evaluated by
[`large_scale_factor`](@ref); [`PopeLargeScale`](@ref) is Pope's form.
"""
abstract type LargeScaleFactor end


"""
    DissipationFactor

Supertype of the dimensionless **dissipation-range roll-off** factors ``f_\\eta(\\kappa\\eta)`` of a
composed [`ModelSpectrum`](@ref) — the shape that cuts the spectrum off near the Kolmogorov scale, with
``f_\\eta \\to 1`` as ``\\kappa\\eta \\to 0``. Evaluated by [`dissipation_factor`](@ref);
[`PopeDissipation`](@ref) is Pope's form.

!!! note "Bottleneck models are deliberately deferred"
    These factors are inertial-normalized cutoffs.
    Models of the near-dissipation *bottleneck* — a bump
    before the cutoff (Qian 1984, [doi:10.1063/1.864902](https://doi.org/10.1063/1.864902);
    Ishihara et al. 2005, [doi:10.1143/JPSJ.74.1464](https://doi.org/10.1143/JPSJ.74.1464);
    Kraichnan 1959, [doi:10.1017/S0022112059000362](https://doi.org/10.1017/S0022112059000362) — all of the form
    ``A(\\kappa\\eta)^\\gamma\\exp(-\\beta\\kappa\\eta)`` with ``\\gamma > 0``, the prefactor that lifts the
    spectrum into the bump before the exponential cuts it down) — do not satisfy
    ``f_\\eta\\to 1`` and need a richer spectrum structure; they are deliberately deferred.
"""
abstract type DissipationFactor end


"""
    large_scale_factor(f, κL) -> Float64

Evaluate the dimensionless large-scale roll-off `f` (a [`LargeScaleFactor`](@ref)) at the argument
``\\kappa \\ell`` (`κL`), where ``\\ell`` is the length that form's own coefficient was fitted against —
[`large_scale_length`](@ref) supplies it. A new large-scale form is a subtype of `LargeScaleFactor`
that adds a method here, and a method there when its length is not ``L_{11}``.
"""
function large_scale_factor end


"""
    large_scale_length(f, fp) -> Float64

The length scale the large-scale roll-off `f` is evaluated against, read from the flow state `fp`
(a [`FlowParameters`](@ref)).

A fitted coefficient belongs to a particular length, and the two published forms here do not use
the same one. The default is the longitudinal integral scale ``L_{11}``, which
[`VonKarmanLarge`](@ref) uses. [`PopeLargeScale`](@ref) overrides it with
``\\ell_{0} = k^{3/2}/\\varepsilon``: Pope's ``c_L = 6.78`` is the value that makes
``\\int_0^\\infty E(\\kappa)\\,\\mathrm{d}\\kappa = k`` hold with *that* length, and feeding the
same coefficient ``L_{11}`` instead breaks that normalization.

The two lengths are related by ``L_{11}/\\ell_{0} = C_\\varepsilon (2/3)^{3/2}``, so the gap is
set by the normalized dissipation constant, not fixed: at ``C_\\varepsilon = 0.5`` the measured
``L_{11}`` is 3.7 times smaller than ``\\ell_{0}`` and the spectrum integrates to ``0.42k``; at
Pope's high-Reynolds-number ``L_{11} = 0.43\\ell_{0}`` it is 2.3 times smaller and integrates to
``0.57k``
(``\\int E\\,\\mathrm{d}\\kappa \\propto \\ell^{2/3}``).
"""
function large_scale_length end

large_scale_length(::LargeScaleFactor, fp::FlowParameters) = fp.integral_scale


"""
    dissipation_factor(f, κη) -> Float64

Evaluate the dimensionless dissipation-range roll-off `f` (a [`DissipationFactor`](@ref)) at the
argument ``\\kappa\\eta`` (`κη`). A new dissipation-range form is a subtype of
`DissipationFactor` that adds a method here.
"""
function dissipation_factor end


"""
    PopeLargeScale(c_L, p₀)

Pope's large-scale roll-off ``f_L(\\kappa \\ell) = \\Bigl(\\frac{\\kappa \\ell}{\\sqrt{(\\kappa \\ell)^2 + c_L}}\\Bigr)^{5/3 + p_0}``,
which tends to `1` in the inertial range and rolls the spectrum off below the integral scale. The
coefficient `c_L` is set by the requirement that the spectrum integrate to the kinetic energy; `p₀`
fixes the low-wavenumber slope (Pope 2000).

# Fields
The plain constructor `PopeLargeScale(c_L, p₀)` takes the two fields directly:
- `c_L` — the large-scale coefficient, set by the energy normalization.
- `p₀` — the low-wavenumber slope exponent.
"""
struct PopeLargeScale <: LargeScaleFactor
  c_L::Float64
  p₀::Float64
end

large_scale_factor(f::PopeLargeScale, κL) = (κL / sqrt(κL^2 + f.c_L))^(5//3 + f.p₀)

# Pope normalizes against L₀ = k^{3/2}/ε, not L₁₁ (Turbulent Flows §6.5); k = (3/2)u'² here.
large_scale_length(::PopeLargeScale, fp::FlowParameters) =
  (3 * fp.rms_velocity^2 / 2)^(3//2) / fp.dissipation


"""
    PopeDissipation(c_η, β)

Pope's dissipation-range roll-off
``f_\\eta(\\kappa\\eta) = \\exp\\!\\Bigl(-\\beta\\bigl\\{\\bigl[(\\kappa\\eta)^4 + c_\\eta^4\\bigr]^{1/4} - c_\\eta\\bigr\\}\\Bigr)``,
which tends to `1` in the inertial range and cuts the spectrum off near the Kolmogorov scale. The
constant `c_η` is set by the requirement that the spectrum yield the dissipation rate; `β` fixes the sharpness of the
cutoff (Pope 2000).

# Fields
The plain constructor `PopeDissipation(c_η, β)` takes the two fields directly:
- `c_η` — the dissipation-range coefficient, set by the dissipation normalization.
- `β` — the cutoff-sharpness exponent.
"""
struct PopeDissipation <: DissipationFactor
  c_η::Float64
  β::Float64
end

dissipation_factor(f::PopeDissipation, κη) = exp(-f.β * ((κη^4 + f.c_η^4)^(1//4) - f.c_η))


"""
    VonKarmanLarge(c_L)

The von Kármán large-scale roll-off
``f_L(\\kappa \\ell) = \\Bigl(\\frac{(\\kappa \\ell)^2}{(\\kappa \\ell)^2 + c_L}\\Bigr)^{17/6}``, which tends to `1`
in the inertial range and produces the classic ``\\kappa^{4}`` energy-containing range at low wavenumber
(``E \\sim \\kappa^{-5/3}f_L \\sim \\kappa^{4}``); `c_L` fixes the peak scale (von Kármán 1948).

# Fields
The plain constructor `VonKarmanLarge(c_L)` takes the field directly:
- `c_L` — the coefficient fixing the peak scale.
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
``f_\\eta(\\kappa\\eta) = \\exp\\!\\bigl(-\\tfrac{3}{2} \\alpha (\\kappa\\eta)^{4/3}\\bigr)``, from the
hypothesis that the cascade timescale — the spectral flux per unit spectral energy — retains its
inertial-range form through the dissipation range, so the flux decays there as viscosity drains
it; `α` is the Kolmogorov constant ``C_K`` (Pao 1965).

# Fields
The plain constructor `PaoDissipation(α)` takes the field directly:
- `α` — the Kolmogorov constant the cascade-timescale hypothesis reuses.
"""
struct PaoDissipation <: DissipationFactor
  α::Float64
end

dissipation_factor(f::PaoDissipation, κη) = exp(-1.5 * f.α * κη^(4//3))


"""
    ExponentialDissipation(β)

The pure-exponential dissipation-range roll-off ``f_\\eta(\\kappa\\eta) = \\exp(-\\beta \\kappa\\eta)``
— the ``n = 1`` case of the general ``\\exp(-\\beta(\\kappa\\eta)^n)`` family, and the form the
triadic spectral closures (eddy-damped quasi-normal Markovian, direct-interaction approximation,
Lagrangian renormalized approximation) consistently predict (Sagaut & Cambon 2018, the source used
here).

It is the *far*-dissipation form (``\\kappa\\eta \\gg 1``), where DNS resolving that range fit
``\\beta \\approx 6.7`` (Khurshid, Donzis & Sreenivasan 2018,
[doi:10.1103/PhysRevFluids.3.082601](https://doi.org/10.1103/PhysRevFluids.3.082601); consistent with
Chen et al. 1993, [doi:10.1103/PhysRevLett.70.3051](https://doi.org/10.1103/PhysRevLett.70.3051),
``\\beta \\approx 7.1``). The factor tends to ``1`` in the inertial range (``\\kappa\\eta \\to 0``).

[`PopeDissipation`](@ref) is asymptotically ``\\exp(-\\beta\\kappa\\eta)`` too, with ``\\beta = 5.2``
— a lower rate, because Pope fits his ``\\beta`` across the whole dissipation range including the
near-dissipation bend, while the values here are fitted to the far range alone.

The near-dissipation range is instead a stretched exponential (exponent ``\\approx 2/3``; Ishihara
et al. 2005), a different form this factor does not model.

# Fields
The plain constructor `ExponentialDissipation(β)` takes the field directly:
- `β` — the exponential decay rate.
"""
struct ExponentialDissipation <: DissipationFactor
  β::Float64
end

dissipation_factor(f::ExponentialDissipation, κη) = exp(-f.β * κη)


"""
    SaffmanDissipation()

A Gaussian dissipation-range roll-off ``f_\\eta(\\kappa\\eta) = \\exp(-2(\\kappa\\eta)^2)`` — a simple,
parameter-free cutoff that tends to `1` in the inertial range. The Gaussian form follows Saffman
(1963, appendix, [doi:10.1017/S0022112063000987](https://doi.org/10.1017/S0022112063000987); roughly half the
cutoff coefficient of the earlier Townsend 1951 form,
[doi:10.1098/rspa.1951.0179](https://doi.org/10.1098/rspa.1951.0179)), whose coefficient varies with the
derivative skewness ``S`` — about ``2.6`` to ``3.3`` across the range of ``S`` that paper considers — and
is simplified downward to ``2`` here for a parameter-free, deliberately soft cutoff, which retains more
near-cutoff energy than a measured spectrum shows.
"""
struct SaffmanDissipation <: DissipationFactor end

dissipation_factor(::SaffmanDissipation, κη) = exp(-2 * κη^2)


# The `Reference` is NOT a field. It is a property of the parametrization — the (large-scale,
# dissipation) pair that names a published model — not of a particular instance's coefficients, and
# holding it here made the struct a non-bitstype: a `Reference` carries strings. That blocked the one
# place a model is evaluated on a device, the `initial_spectrum` seeding closure, because a lazy
# radial kernel captures its σ by value and a device rejects a non-bitstype capture at launch. So a
# `Phenomenology`-seeded run could not start on a GPU at all.
"""
    ModelSpectrum(C_K, large_scale, dissipation)

The composed model energy spectrum

```math
E(\\kappa) = C_K \\varepsilon^{2/3} \\kappa^{-5/3} f_L(\\kappa \\ell) f_\\eta(\\kappa\\eta),
```

an inertial-range core with Kolmogorov constant `C_K` times a large-scale roll-off `large_scale` (a
[`LargeScaleFactor`](@ref), giving ``f_L``) and a dissipation-range roll-off `dissipation` (a
[`DissipationFactor`](@ref), giving ``f_\\eta``). Build one directly to
mix roll-off forms, or use a preset such as [`Pope2000`](@ref) — a preset's pairing carries its
published [`provenance`](@ref); an ad-hoc mix evaluates like any other, but it is not a published
model, so `provenance` throws for it rather than inventing a source. Evaluated by
[`spectrum`](@ref)`(model, κ, fp)`, which reads ``\\varepsilon`` and the roll-off's own length ``\\ell``
(see [`large_scale_length`](@ref) — ``L_{11}`` for most forms, ``k^{3/2}/\\varepsilon`` for Pope's) from
`fp` and forms ``\\eta`` with [`kolmogorov_length`](@ref).

This is the standard generic form for a model spectrum (Sagaut & Cambon 2018, *Homogeneous
Turbulence Dynamics*, 2nd ed., Springer, [doi:10.1007/978-3-319-73162-9](https://doi.org/10.1007/978-3-319-73162-9);
Pope 2000); the large-scale roll-off sets the low-wavenumber slope
``E(\\kappa\\to 0)\\propto\\kappa^\\sigma`` — ``\\sigma = 2`` (the Saffman-type ``\\kappa^{2}`` low-wavenumber
spectrum, the [`PopeLargeScale`](@ref) default) or ``\\sigma = 4`` (the Batchelor-type ``\\kappa^{4}``,
[`VonKarmanLarge`](@ref)).

# Fields
The (sole, positional) constructor above takes the three fields directly:
- `C_K` — the Kolmogorov constant of the inertial-range core.
- `large_scale` — the `LargeScaleFactor` giving ``f_L``.
- `dissipation` — the `DissipationFactor` giving ``f_\\eta``.
"""
struct ModelSpectrum{L<:LargeScaleFactor, D<:DissipationFactor} <: EnergySpectrum
  C_K::Float64
  large_scale::L
  dissipation::D
end

spectrum(m::ModelSpectrum, κ, fp::FlowParameters) =
  m.C_K * fp.dissipation^(2//3) * κ^(-5//3) *
  large_scale_factor(m.large_scale, κ * large_scale_length(m.large_scale, fp)) *
  dissipation_factor(m.dissipation, κ * kolmogorov_length(fp))

provenance(m::ModelSpectrum) = _reference(m.large_scale, m.dissipation)

# One published reference per strategy pair. An ad-hoc pairing has no published source, and saying so
# is more useful than inventing one.
_reference(::PopeLargeScale, ::PopeDissipation) = _POPE2000
_reference(::VonKarmanLarge, ::UnitDissipation) = _VONKARMAN1948
_reference(::UnitLargeScale, ::PaoDissipation) = _PAO1965
_reference(::LargeScaleFactor, ::DissipationFactor) =
  throw(ArgumentError("this combination of large-scale and dissipation factors is not a published " *
                      "model, so it has no reference; the named presets each carry one"))


const _POPE2000 = Reference("Pope (2000), *Turbulent Flows* (Cambridge University Press), §6.5. [doi:10.1017/CBO9780511840531](https://doi.org/10.1017/CBO9780511840531)"; valid_Reλ = (30.0, Inf))

"""
    Pope2000(; C_K = 1.5, c_L = 6.78, p₀ = 2.0, c_η = 0.40, β = 5.2)

The Pope (2000) model spectrum — the [`ModelSpectrum`](@ref) composition (whose docstring carries the
formula) with [`PopeLargeScale`](@ref) supplying ``f_L`` and [`PopeDissipation`](@ref) supplying
``f_\\eta``.

`C_K` is the Kolmogorov constant; the defaults `c_L = 6.78`, `c_η = 0.40` are the high-Reynolds-number
values Pope obtains from the energy and dissipation normalizations, with the shape exponents `p₀ = 2`
and `β = 5.2`. Override any coefficient to re-fit — but the two kinds of coefficient differ: the
shape exponents `p₀` and `β` are free axes, while `c_L` and `c_η` are the values *derived from* the
energy and dissipation normalizations, so hand-setting either breaks the stated
``\\int E = k`` / dissipation identities silently. Evaluate with [`spectrum`](@ref)`(Pope2000(), κ, fp)`.

`Pope2000` is the `ModelSpectrum` carrying Pope's two roll-off factors.
"""
const Pope2000 = ModelSpectrum{PopeLargeScale, PopeDissipation}

Pope2000(; C_K = 1.5, c_L = 6.78, p₀ = 2.0, c_η = 0.40, β = 5.2) =
  ModelSpectrum(C_K, PopeLargeScale(c_L, p₀), PopeDissipation(c_η, β))


const _VONKARMAN1948 = Reference("von Kármán (1948), *Proc. Natl. Acad. Sci.* **34**, 530. [doi:10.1073/pnas.34.11.530](https://doi.org/10.1073/pnas.34.11.530)"; valid_Reλ = (0.0, Inf))

"""
    VonKarman1948(; C_K = 1.5, c_L = 1.0)

The von Kármán (1948) energy spectrum — a preset [`ModelSpectrum`](@ref) with the
[`VonKarmanLarge`](@ref) roll-off and no viscous cutoff ([`UnitDissipation`](@ref)):

`ModelSpectrum`'s docstring carries the composed formula; here ``f_L`` is von Kármán's
``\\Bigl(\\frac{(\\kappa \\ell)^2}{(\\kappa \\ell)^2 + c_L}\\Bigr)^{17/6}`` and ``f_\\eta`` is unity. It is the
classic interpolation between the ``\\kappa^{4}`` energy-containing range and the ``\\kappa^{-5/3}``
inertial range, with no dissipation-range cutoff (use [`Pope2000`](@ref) when the cutoff matters).
`C_K` is the Kolmogorov constant; `c_L` fixes where the spectrum peaks and is a shape parameter of
this form rather than a normalization — unlike [`PopeLargeScale`](@ref)'s `c_L`, no energy condition
determines it, and the default `1.0` is the conventional choice.

`VonKarman1948` is the `ModelSpectrum` carrying von Kármán's large-scale factor and no
dissipation roll-off.
"""
const VonKarman1948 = ModelSpectrum{VonKarmanLarge, UnitDissipation}

VonKarman1948(; C_K = 1.5, c_L = 1.0) =
  ModelSpectrum(C_K, VonKarmanLarge(c_L), UnitDissipation())


const _PAO1965 = Reference("Pao (1965), *Phys. Fluids* **8**, 1063. [doi:10.1063/1.1761356](https://doi.org/10.1063/1.1761356)"; valid_Reλ = (0.0, Inf))

"""
    Pao1965(; C_K = 1.5)

The Pao (1965) energy spectrum — a preset [`ModelSpectrum`](@ref) with no energy-containing roll-off
([`UnitLargeScale`](@ref)) and the [`PaoDissipation`](@ref) cutoff:

`ModelSpectrum`'s docstring carries the composed formula; here ``f_L`` is unity and
``f_\\eta`` is Pao's ``\\exp\\!\\bigl(-\\tfrac{3}{2} C_K (\\kappa\\eta)^{4/3}\\bigr)``. It covers the
inertial and dissipation ranges from the constant-cascade-timescale hypothesis — the Kolmogorov
constant `C_K` appears in both the amplitude and the cutoff, so the cutoff carries no free constant
(unlike [`Pope2000`](@ref)). It has no energy-containing range; use `Pope2000` or
[`VonKarman1948`](@ref) when the large scales matter.

`Pao1965` is the `ModelSpectrum` carrying Pao's dissipation factor and no large-scale
roll-off.
"""
const Pao1965 = ModelSpectrum{UnitLargeScale, PaoDissipation}

Pao1965(; C_K = 1.5) = ModelSpectrum(C_K, UnitLargeScale(), PaoDissipation(C_K))


"""
    ScalarSpectrum <: TurbulenceLaw

Supertype of the passive-scalar spectrum models — parametrizations of ``E_\\varphi(\\kappa)``, the
density in wavenumber of the scalar variance ``\\langle\\varphi^2\\rangle``, evaluated by
[`spectrum`](@ref). [`ObukhovCorrsin1949`](@ref) is the inertial-convective range.
"""
abstract type ScalarSpectrum <: TurbulenceLaw end


const _OBUKHOVCORRSIN = Reference("Obukhov (1949), *Izv. Akad. Nauk SSSR, Ser. Geogr. Geofiz.* **13**, 58 (no DOI: a 1949 Soviet-journal article) / " *
                                  "Corrsin (1951), *J. Appl. Phys.* **22**, 469. [doi:10.1063/1.1699986](https://doi.org/10.1063/1.1699986)"; valid_Reλ = (50.0, Inf))

"""
    ObukhovCorrsin1949(; C_OC = 0.67)

The Obukhov–Corrsin inertial-convective scalar spectrum

```math
E_\\varphi(\\kappa) = C_{\\mathrm{OC}} \\varepsilon_\\varphi \\varepsilon^{-1/3} \\kappa^{-5/3},
```

the Obukhov–Corrsin scalar analogue of the Kolmogorov ``-5/3`` law: for a Schmidt number of order one the scalar's
inertial-convective range coincides with the velocity inertial range. `C_OC` is the Obukhov–Corrsin
constant (``\\approx 0.67`` for the three-dimensional spectrum — the high-Reynolds-number value of
Sreenivasan 1996, *Phys. Fluids* **8**, 189, [doi:10.1063/1.868826](https://doi.org/10.1063/1.868826)), quoted — unlike Yaglom's classical
``4/3`` — for the *full*-variance scalar dissipation ``2\\varkappa\\langle\\lvert\\nabla\\varphi\\rvert^2\\rangle``,
so it pairs directly with this package's full-variance ``\\varepsilon_\\varphi`` (`scalar_dissipation`)
with no factor-of-two conversion (the constant is invariant so long as a source scales its scalar
spectrum and its dissipation together — both double or both halve — so only a mixed-convention
quote would shift it by two).

The name is a dual eponym — Obukhov (1949) and Corrsin (independently, 1951); the `1949` handle is
Obukhov's year. Evaluating
[`spectrum`](@ref) reads
the scalar dissipation ``\\varepsilon_\\varphi`` (`fp.scalar_dissipation`, which must be set) and the
kinetic-energy dissipation ``\\varepsilon`` from `fp`.

# Fields
The plain constructor `ObukhovCorrsin1949(C_OC)` takes the field directly:
- `C_OC` — the Obukhov–Corrsin constant.
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
