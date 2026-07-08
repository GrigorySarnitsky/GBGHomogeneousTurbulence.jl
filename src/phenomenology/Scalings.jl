"""
    Phenomenology.Scalings

Dimensionless turbulence constants and their Reynolds-number trends, evaluated by [`scaling`](@ref).

- [`Sreenivasan1998`](@ref) — the normalized dissipation constant ``C_\\varepsilon = \\varepsilon L/u'^3``,
  a high-Reynolds-number plateau with an optional finite-Reynolds-number correction.
- [`Sreenivasan1995`](@ref) — the (three-dimensional) Kolmogorov constant ``C_K`` of the inertial-range
  spectrum.
"""
module Scalings

using ..Phenomenology: TurbulenceLaw, FlowParameters, Reference, taylor_reynolds
import ..Phenomenology: scaling, provenance

export ScalingLaw, Sreenivasan1998, Sreenivasan1995, scaling


"""
    ScalingLaw <: TurbulenceLaw

Supertype of the laws for a **dimensionless turbulence constant** — a pure number characterizing
developed turbulence (the normalized dissipation ``C_\\varepsilon``, the Kolmogorov constant ``C_K``,
the derivative skewness, …), possibly Reynolds-number-dependent. A law predicts the constant via
[`scaling`](@ref)`(law, fp)`; the *measured* value comes from a run, and the comparison is prediction
against measurement.
"""
abstract type ScalingLaw <: TurbulenceLaw end


const _SREENIVASAN = Reference("Sreenivasan (1998), *Phys. Fluids* **10**, 528"; valid_Reλ = (50.0, Inf))

"""
    Sreenivasan1998(; asymptote = 0.5, correction = 0.0)

The normalized dissipation constant ``C_\\varepsilon = \\varepsilon L/u'^3`` as a high-Reynolds-number
plateau with an optional finite-Reynolds-number correction,

```math
C_\\varepsilon(\\mathrm{Re}_\\lambda) = C_{\\varepsilon\\infty}\\left(1 + \\frac{a}{\\mathrm{Re}_\\lambda}\\right),
```

with `asymptote` the plateau ``C_{\\varepsilon\\infty}`` and `correction` the coefficient ``a`` of the
``1/\\mathrm{Re}_\\lambda`` correction. Sreenivasan (1998) established that ``C_\\varepsilon`` approaches a
constant of order ``0.5`` (the default; the precise value depends on the integral-scale definition)
above ``\\mathrm{Re}_\\lambda \\sim 50``. The correction defaults to `0` (the pure plateau); set it to a
positive value to model the low-Reynolds-number rise. [`scaling`](@ref)`(law, fp)` reads
``\\mathrm{Re}_\\lambda`` from `fp` via [`taylor_reynolds`](@ref).
"""
struct Sreenivasan1998 <: ScalingLaw
  asymptote::Float64
  correction::Float64
end

Sreenivasan1998(; asymptote = 0.5, correction = 0.0) = Sreenivasan1998(asymptote, correction)

scaling(m::Sreenivasan1998, fp::FlowParameters) =
  m.asymptote * (1 + m.correction / taylor_reynolds(fp))

provenance(::Sreenivasan1998) = _SREENIVASAN


const _SREENIVASAN1995 = Reference("Sreenivasan (1995), *Phys. Fluids* **7**, 2778"; valid_Reλ = (50.0, Inf))

"""
    Sreenivasan1995(; C_K = 1.5)

The three-dimensional Kolmogorov constant ``C_K`` of the inertial-range energy spectrum
``E(\\kappa) = C_K\\,\\varepsilon^{2/3}\\kappa^{-5/3}`` — the amplitude a `Spectra` model uses. Reviewing
the experimental and numerical record, Sreenivasan (1995) found it close to universal, a reliable
estimate being ``C_K = 1.5 \\pm 0.1`` (the default; Sagaut & Cambon 2018), with no significant
Reynolds-number trend; [`scaling`](@ref)`(law, fp)` returns it, independent of `fp`.
"""
struct Sreenivasan1995 <: ScalingLaw
  C_K::Float64
end

Sreenivasan1995(; C_K = 1.5) = Sreenivasan1995(C_K)

scaling(m::Sreenivasan1995, ::FlowParameters) = m.C_K

provenance(::Sreenivasan1995) = _SREENIVASAN1995


end # module Scalings
