# Phenomenology — reference turbulence laws (model spectra, structure-function laws, scaling
# constants), each an author-year parametrization of an abstract law family per quantity. The
# *predicted* counterpart to `Observables`: a provider the validation layer reads, never a comparer.
#
# Extraction-bound (docs/ARCHITECTURE.md §4.8, decision 18): this module depends on no field or
# statistics backend and no dynamics — a law is a scalar function — and the umbrella does NOT
# re-export it, so it can be cut into a standalone `GBGTurbulencePhenomenology` with no rewrite.


"""
    Phenomenology

Reference turbulence phenomenology — the fitted scalings, model spectra, and structure-function laws
that theory and experiment have established, each an author-year parametrization of an abstract law
family. This is the *predicted* counterpart to the measured `Observables`: a provider the validation
layer reads to compare a run against, never a comparer itself and never assumed by the dynamics.

A law family is an abstract subtype of [`TurbulenceLaw`](@ref) (the root of every reference law
here); each parametrization is a named preset — usually a concrete subtype
carrying its fitted coefficients and its provenance, or (for the composed velocity spectra like
`Spectra.Pope2000`) an alias for one specialization of a composed type, with a keyword constructor
that fills in the published fit — so `spec isa Spectra.Pope2000` holds either way. Choosing a law is choosing the preset (the
published fit is the default); a name is disambiguated by its **submodule** (the quantity), its
**author-year** (the paper), and a trailing letter (a same-year collision).

The module's contents:
- [`FlowParameters`](@ref) — the flow-state bundle a law evaluates against, with the
  derived scales [`kolmogorov_length`](@ref), [`kolmogorov_time`](@ref), [`taylor_microscale`](@ref),
  [`taylor_reynolds`](@ref), and [`scalar_diffusivity`](@ref) as helpers.
- [`provenance`](@ref) — a law's citation and validity range (a [`Reference`](@ref)); [`fit`](@ref)
  is the (future) seam for fitting a parametrization to measured data.
- [`Spectra`](@ref GBGIsotropicTurbulence.Phenomenology.Spectra) — model velocity and scalar
  spectra, functions of
  wavenumber, evaluated by [`spectrum`](@ref).
- [`StructureFunctions`](@ref GBGIsotropicTurbulence.Phenomenology.StructureFunctions) — the
  inertial-range laws and their
  intermittency exponents, evaluated by [`structure_function`](@ref) and [`scaling_exponent`](@ref).
- [`Scalings`](@ref GBGIsotropicTurbulence.Phenomenology.Scalings) — the dimensionless constants and
  their Reynolds-number
  trends, evaluated by [`scaling`](@ref).

!!! note "Extraction-bound"
    Built inside `GBGIsotropicTurbulence` but designed to be cut into a standalone
    `GBGTurbulencePhenomenology` with no rewrite: it takes no field/statistics/dynamics dependency, and
    the umbrella does not re-export it — reach the laws opt-in through `Phenomenology`
    (`using GBGIsotropicTurbulence.Phenomenology.Spectra`).
"""
module Phenomenology


export TurbulenceLaw, FlowParameters, Reference, provenance, spectrum, structure_function,
       scaling_exponent, scaling, fit, kolmogorov_length, kolmogorov_time, taylor_microscale,
       taylor_reynolds, scalar_diffusivity


"""
    TurbulenceLaw

Supertype of every reference law — a model spectrum, a structure-function law, or a scaling constant.
A concrete law is a parametrization: it holds its fitted coefficients, reports its [`provenance`](@ref),
and implements the evaluator for its family ([`spectrum`](@ref), [`structure_function`](@ref), or
[`scaling`](@ref)), all against a [`FlowParameters`](@ref) bundle.
"""
abstract type TurbulenceLaw end


"""
    FlowParameters(; viscosity, dissipation, rms_velocity, integral_scale,
                     schmidt = 1.0, scalar_dissipation = NaN)

The flow-state bundle a law is evaluated against — the analogue of `FlowConditions` and
`FixedDomain` on the phenomenology side. It carries the dimensional quantities a law reads off a homogeneous
isotropic state (``\\nu``, ``\\varepsilon``, ``u'``, ``L_{11}``); the small scales and the dimensionless
Taylor-scale Reynolds number are [derived](@ref taylor_reynolds) from them, not stored.

# Arguments
All keyword; a homogeneous-isotropic state fixes the rest:

  * `viscosity` — the kinematic viscosity ``\\nu``.
  * `dissipation` — the mean dissipation rate ``\\varepsilon = \\nu\\langle\\lvert\\boldsymbol{\\omega}\\rvert^2\\rangle``.
  * `rms_velocity` — the single-component r.m.s. velocity ``u'`` (so the turbulent kinetic energy is
    ``k = \\tfrac{3}{2} u'^2``).
  * `integral_scale` — the longitudinal integral length ``L_{11}`` (a large-scale quantity, independent of ``\\nu`` and
    ``\\varepsilon``; it fixes the energy-containing range).
  * `schmidt` — the Schmidt number ``\\mathrm{Sc}`` (the scalar diffusivity is
    ``\\varkappa = \\nu/\\mathrm{Sc}``); default `1.0`.
  * `scalar_dissipation` — the scalar dissipation rate
    ``\\varepsilon_\\varphi = 2\\varkappa\\langle\\lvert\\nabla\\varphi\\rvert^{2}\\rangle``, the
    **full**-variance convention — a law fed the half-variance form
    ``\\varkappa\\langle\\lvert\\nabla\\varphi\\rvert^{2}\\rangle`` instead is off by a factor of two
    with no error; only scalar laws read it, and the default is
    `NaN` for a run that carries no scalar. `NaN` rather than `nothing` keeps the bundle
    a plain, type-stable set of `Float64`s. Every law here that reads the field checks it first and
    throws an `ArgumentError` naming the law and the missing rate, so a scalar law applied to a
    scalar-free state fails loudly rather than returning `NaN`. That guard covers the laws, not
    arithmetic a caller does on the field itself, where `NaN` propagates as it always does.

# Examples

Built from a run's measured state — which is what `flow_parameters(sim)` returns — or by hand to
evaluate a law at a state you specify:

```julia
fp = FlowParameters(; viscosity = 1e-3, dissipation = 1.0, rms_velocity = 1.0,
                      integral_scale = 0.5)                 # velocity-only: no scalar law applies

fps = FlowParameters(; viscosity = 1e-3, dissipation = 1.0, rms_velocity = 1.0,
                       integral_scale = 0.5, schmidt = 0.7, scalar_dissipation = 0.5)
```

# Fields

The plain constructor `FlowParameters(viscosity, dissipation, rms_velocity, integral_scale, schmidt,
scalar_dissipation)` takes the six fields directly, in the order shown; each holds the value documented for
the keyword of the same name above.
"""
struct FlowParameters
  viscosity::Float64
  dissipation::Float64
  rms_velocity::Float64
  integral_scale::Float64
  schmidt::Float64
  scalar_dissipation::Float64
end

FlowParameters(; viscosity, dissipation, rms_velocity, integral_scale,
                 schmidt = 1.0, scalar_dissipation = NaN) =
  FlowParameters(viscosity, dissipation, rms_velocity, integral_scale, schmidt, scalar_dissipation)


"""
    kolmogorov_length(fp) -> Float64

The Kolmogorov (dissipation) length ``\\eta = (\\nu^3/\\varepsilon)^{1/4}`` of the state `fp` (a
[`FlowParameters`](@ref)) — the scale at which viscosity terminates the cascade.
"""
kolmogorov_length(fp::FlowParameters) = (fp.viscosity^3 / fp.dissipation)^(1//4)


"""
    kolmogorov_time(fp) -> Float64

The Kolmogorov time ``\\tau_\\eta = (\\nu/\\varepsilon)^{1/2}`` of the state `fp` (a
[`FlowParameters`](@ref)) — the turnover time of the smallest eddies.
"""
kolmogorov_time(fp::FlowParameters) = sqrt(fp.viscosity / fp.dissipation)


"""
    taylor_microscale(fp) -> Float64

The Taylor microscale ``\\lambda = \\sqrt{15 \\nu u'^2/\\varepsilon}`` of the state `fp` (a
[`FlowParameters`](@ref)) — the intermediate scale set by the isotropic relation
``\\varepsilon = 15 \\nu u'^2/\\lambda^2``.
"""
taylor_microscale(fp::FlowParameters) =
  sqrt(15 * fp.viscosity * fp.rms_velocity^2 / fp.dissipation)


"""
    taylor_reynolds(fp) -> Float64

The Taylor-scale Reynolds number ``\\mathrm{Re}_\\lambda = u'\\lambda/\\nu`` of the state `fp` (a
[`FlowParameters`](@ref)) — the standard measure of how developed the turbulence is, and the argument
of every [`Scalings`](@ref GBGIsotropicTurbulence.Phenomenology.Scalings) trend. Equivalently
``\\mathrm{Re}_\\lambda = u'^2\\sqrt{15/(\\nu\\varepsilon)}``.
"""
taylor_reynolds(fp::FlowParameters) = fp.rms_velocity * taylor_microscale(fp) / fp.viscosity


"""
    scalar_diffusivity(fp) -> Float64

The scalar diffusivity ``\\varkappa = \\nu/\\mathrm{Sc}`` of the state `fp` (a
[`FlowParameters`](@ref)) — the diffusivity of the passive scalar ``\\varphi``, set by the Schmidt
number.
"""
scalar_diffusivity(fp::FlowParameters) = fp.viscosity / fp.schmidt


"""
    Reference(citation; valid_Reλ = (0.0, Inf))

The provenance of a law: a `citation` string (a full author–year reference) and the
Taylor-scale-Reynolds-number range `valid_Reλ = (lo, hi)` over which the fit is
meant to hold. A comparison reads `valid_Reλ` so a law is not judged outside its stated domain.

# Fields
The plain constructor `Reference(citation, valid_Reλ)` takes the two fields directly:
- `citation` — the full author–year reference the law is taken from.
- `valid_Reλ` — the ``\\mathrm{Re}_\\lambda`` range `(lo, hi)` the fit is meant to hold over.
"""
struct Reference
  citation::String
  valid_Reλ::Tuple{Float64,Float64}
end

Reference(citation; valid_Reλ = (0.0, Inf)) = Reference(citation, (Float64(valid_Reλ[1]), Float64(valid_Reλ[2])))


"""
    provenance(law) -> Reference

The [`Reference`](@ref) of a `law` (a [`TurbulenceLaw`](@ref)) — its citation and stated
Reynolds-number validity range. Every parametrization implements it; it is the single source of the
law's attribution.
"""
function provenance end


"""
    spectrum(law, κ, fp) -> Float64

The reference spectrum predicted by a model `law` at wavenumber `κ` for the state `fp` (a
[`FlowParameters`](@ref)) — the velocity energy spectrum ``E(\\kappa)`` for an `EnergySpectrum` (the
density in wavenumber of the kinetic energy, ``k = \\int_0^\\infty E(\\kappa)\\,\\mathrm{d}\\kappa``), or the scalar
spectrum ``E_\\varphi(\\kappa)`` for a `ScalarSpectrum`. Its home and the composed form are in
[`Spectra`](@ref GBGIsotropicTurbulence.Phenomenology.Spectra).
"""
function spectrum end


"""
    scaling_exponent(law; order) -> Float64

The inertial-range scaling exponent ``\\zeta_p`` of the longitudinal velocity structure function of
order ``p`` (the `order` argument), ``D_{L\\dots}(r) \\sim r^{\\zeta_p}``, predicted by a
`law` (a `StructureFunction`) — the
self-similar ``\\zeta_p = p/3`` of K41, or the anomalous exponent of an intermittency model. Its home is
[`StructureFunctions`](@ref GBGIsotropicTurbulence.Phenomenology.StructureFunctions).
"""
function scaling_exponent end


"""
    structure_function(law, r, fp; order) -> Float64

The reference structure function of the given `order` predicted by a `law` (a
[`StructureFunction`](@ref GBGIsotropicTurbulence.Phenomenology.StructureFunctions.StructureFunction)) at
separation `r` for the state `fp` (a [`FlowParameters`](@ref)). Most laws give the longitudinal
**velocity** moment ``D_{L\\dots}(r) = \\langle(\\delta u_L)^p\\rangle`` (the `order`-th moment ``p``) of the
velocity increment ``\\delta u_L`` across a distance `r`; a mixed velocity–scalar law (`Yaglom1949`) instead gives
``\\langle\\delta u_L (\\delta\\varphi)^{2}\\rangle``, the transport of scalar variance. Its home is
[`StructureFunctions`](@ref GBGIsotropicTurbulence.Phenomenology.StructureFunctions).
"""
function structure_function end


"""
    scaling(law, fp) -> Float64

The reference dimensionless constant predicted by a scaling `law` (a `ScalingLaw`) for the state `fp`
(a [`FlowParameters`](@ref)) — a single number or its Reynolds-number trend (e.g. the normalized
dissipation ``C_\\varepsilon`` or the Kolmogorov constant ``C_K``). Its home is
[`Scalings`](@ref GBGIsotropicTurbulence.Phenomenology.Scalings).
"""
function scaling end


"""
    fit(::Type{L}, ...) -> L

Fit a parametrization of law family `L` to measured data — the seam by which a run's own measurements
become a parametrization sitting beside the literature. No methods are defined yet; it is the recorded
extension point for fitting a run's own measurements to a parametrization.
"""
function fit end


include("phenomenology/Spectra.jl")
include("phenomenology/StructureFunctions.jl")
include("phenomenology/Scalings.jl")


end # module Phenomenology
