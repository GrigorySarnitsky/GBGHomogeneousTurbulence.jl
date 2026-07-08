"""
    Phenomenology.Scalings

Dimensionless scaling constants and their Reynolds-number trends, evaluated by [`scaling`](@ref).

- [`DissipationScaling`](@ref) — the normalized dissipation constant ``C_\\varepsilon``.
- [`Sreenivasan1998`](@ref) — the high-Reynolds-number plateau of ``C_\\varepsilon`` with an optional
  finite-Reynolds-number correction.
"""
module Scalings

using ..Phenomenology: TurbulenceLaw, FlowParameters, Reference, taylor_reynolds
import ..Phenomenology: scaling, provenance

export DissipationScaling, Sreenivasan1998, scaling


"""
    DissipationScaling <: TurbulenceLaw

Supertype of the laws for the **normalized dissipation constant**
``C_\\varepsilon = \\varepsilon L / u'^3`` — the ratio of the actual dissipation rate to the
large-scale estimate ``u'^3/L``, and one of the sharpest tests of developed turbulence. A law predicts
``C_\\varepsilon`` (a pure number, possibly Reynolds-number-dependent) via [`scaling`](@ref); the
*measured* value is ``\\varepsilon L/u'^3`` from a run, and the comparison is prediction against
measurement.
"""
abstract type DissipationScaling <: TurbulenceLaw end


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
struct Sreenivasan1998 <: DissipationScaling
  asymptote::Float64
  correction::Float64
end

Sreenivasan1998(; asymptote = 0.5, correction = 0.0) = Sreenivasan1998(asymptote, correction)

scaling(m::Sreenivasan1998, fp::FlowParameters) =
  m.asymptote * (1 + m.correction / taylor_reynolds(fp))

provenance(::Sreenivasan1998) = _SREENIVASAN


end # module Scalings
