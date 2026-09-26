"""
    Phenomenology.Scalings

Dimensionless turbulence constants and their Reynolds-number trends, evaluated by [`scaling`](@ref).

- [`ScalingLaw`](@ref) — the family root every law below subtypes.
- [`Sreenivasan1998`](@ref) — the normalized dissipation constant ``C_\\varepsilon``
  (``L_{11}`` the longitudinal integral scale), a high-Reynolds-number plateau with an optional
  finite-Reynolds-number correction.
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
developed turbulence — here the normalized dissipation ``C_\\varepsilon`` and the Kolmogorov constant
``C_K``; each may carry a Reynolds-number dependence. A law predicts the constant via
[`scaling`](@ref)`(law, fp)`; the *measured* value comes from a run, and the comparison is prediction
against measurement.
"""
abstract type ScalingLaw <: TurbulenceLaw end


const _SREENIVASAN = Reference("Sreenivasan (1998), *Phys. Fluids* **10**, 528. [doi:10.1063/1.869575](https://doi.org/10.1063/1.869575)"; valid_Reλ = (50.0, Inf))

"""
    Sreenivasan1998(; asymptote = 0.5, correction = 0.0)

The normalized dissipation constant ``C_\\varepsilon = \\varepsilon L_{11}/u'^3`` — normalized on the
longitudinal integral scale ``L_{11}``, not the box side — as a high-Reynolds-number plateau with an
optional finite-Reynolds-number correction,

```math
C_\\varepsilon(\\mathrm{Re}_\\lambda) = C_{\\varepsilon\\infty}\\Bigl(1 + \\frac{a}{\\mathrm{Re}_\\lambda}\\Bigr),
```

with `asymptote` the plateau ``C_{\\varepsilon\\infty}`` and `correction` the coefficient ``a`` of the
``1/\\mathrm{Re}_\\lambda`` correction. Sreenivasan (1998) established that ``C_\\varepsilon`` approaches a
constant of order ``0.5`` (the default; the precise value depends on the integral-scale definition)
above ``\\mathrm{Re}_\\lambda \\sim 50``. The correction defaults to `0` (the pure plateau); set it to a
positive value to model the low-Reynolds-number rise. Evaluating [`scaling`](@ref)`(law, fp)` reads
``\\mathrm{Re}_\\lambda`` from `fp` via [`taylor_reynolds`](@ref).

# Fields
The plain constructor `Sreenivasan1998(asymptote, correction)` takes the two fields directly:
- `asymptote` — the plateau ``C_{\\varepsilon\\infty}``.
- `correction` — the ``1/\\mathrm{Re}_\\lambda`` coefficient ``a``.
"""
struct Sreenivasan1998 <: ScalingLaw
  asymptote::Float64
  correction::Float64
end

Sreenivasan1998(; asymptote = 0.5, correction = 0.0) = Sreenivasan1998(asymptote, correction)

scaling(m::Sreenivasan1998, fp::FlowParameters) =
  m.asymptote * (1 + m.correction / taylor_reynolds(fp))

provenance(::Sreenivasan1998) = _SREENIVASAN


const _SREENIVASAN1995 = Reference("Sreenivasan (1995), *Phys. Fluids* **7**, 2778. [doi:10.1063/1.868656](https://doi.org/10.1063/1.868656)"; valid_Reλ = (50.0, Inf))

"""
    Sreenivasan1995(; C_K = 1.5)

The three-dimensional Kolmogorov constant ``C_K`` of the inertial-range energy spectrum

```math
E(\\kappa) = C_K \\varepsilon^{2/3}\\kappa^{-5/3},
```

the amplitude a `Spectra` model uses. Reviewing
the experimental and numerical record, Sreenivasan (1995) found it close to universal.
The default ``C_K = 1.5 \\pm 0.1`` used here is the consensus value as quoted by Sagaut & Cambon
(2018), not a figure read off the 1995 paper, with no significant
Reynolds-number trend; [`scaling`](@ref)`(law, fp)` returns it, independent of `fp`.

# Fields
The plain constructor `Sreenivasan1995(C_K)` takes the field directly:
- `C_K` — the Kolmogorov constant.
"""
struct Sreenivasan1995 <: ScalingLaw
  C_K::Float64
end

Sreenivasan1995(; C_K = 1.5) = Sreenivasan1995(C_K)

scaling(m::Sreenivasan1995, ::FlowParameters) = m.C_K

provenance(::Sreenivasan1995) = _SREENIVASAN1995


end # module Scalings
