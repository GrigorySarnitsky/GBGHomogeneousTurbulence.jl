"""
    Phenomenology.StructureFunctions

Inertial-range structure-function laws — parametrizations of the longitudinal velocity structure
function ``D_{L\\dots}(r)``, evaluated by [`structure_function`](@ref).

- [`Kolmogorov1941`](@ref) — the K41 inertial-range laws: the exact 4/5 law, the 2/3 law, and the
  self-similar exponents (via [`scaling_exponent`](@ref)).
- [`SheLeveque1994`](@ref) — the She–Lévêque intermittency model: the anomalous scaling exponents
  ``\\zeta_p`` (via [`scaling_exponent`](@ref)).
"""
module StructureFunctions

using ..Phenomenology: TurbulenceLaw, FlowParameters, Reference
import ..Phenomenology: structure_function, scaling_exponent, provenance

export StructureFunction, Kolmogorov1941, SheLeveque1994, structure_function, scaling_exponent


"""
    StructureFunction <: TurbulenceLaw

Supertype of the velocity structure-function laws — parametrizations of
``D_{L\\dots}(r) = \\langle(\\delta u_L)^p\\rangle`` (the ``p``-th moment of the longitudinal velocity
increment across a separation ``r``), evaluated by [`structure_function`](@ref).
"""
abstract type StructureFunction <: TurbulenceLaw end


const _K41 = Reference("Kolmogorov (1941), *Dokl. Akad. Nauk SSSR* **30**, 301"; valid_Reλ = (100.0, Inf))

"""
    Kolmogorov1941(; C₂ = 2.0)

The Kolmogorov (1941) inertial-range structure-function laws for the longitudinal velocity increment
``\\delta u_L``. [`structure_function`](@ref)`(law, r, fp; order)` returns:

  * `order = 2` — the **2/3 law** ``D_{LL}(r) = C_2\\,(\\varepsilon r)^{2/3}``, the second-order
    increment; the constant `C₂ ≈ 2.0` is empirical (default `2.0`).
  * `order = 3` — the **4/5 law** ``D_{LLL}(r) = -\\tfrac{4}{5}\\,\\varepsilon r``, the third-order
    increment; this one is *exact* (a consequence of the Kármán–Howarth–Monin relation), carrying no
    free constant.

Both hold in the inertial range ``\\eta \\ll r \\ll L``. `fp` (a [`FlowParameters`](@ref)) supplies the
dissipation rate ``\\varepsilon``. Any other `order` throws — K41 fixes only these two longitudinal
moments universally.
"""
struct Kolmogorov1941 <: StructureFunction
  C₂::Float64
end

Kolmogorov1941(; C₂ = 2.0) = Kolmogorov1941(C₂)

function structure_function(m::Kolmogorov1941, r, fp::FlowParameters; order::Integer = 2)
  εr = fp.dissipation * r
  order == 2 && return m.C₂ * εr^(2//3)
  order == 3 && return -(4//5) * εr
  throw(ArgumentError(
    "Kolmogorov1941 gives only the 2nd-order (2/3) and 3rd-order (4/5) longitudinal laws; got order=$order"))
end

provenance(::Kolmogorov1941) = _K41

scaling_exponent(::Kolmogorov1941, order::Real) = order / 3    # self-similar K41 exponent ζ_p = p/3


const _SHELEVEQUE = Reference("She & Lévêque (1994), *Phys. Rev. Lett.* **72**, 336"; valid_Reλ = (200.0, Inf))

"""
    SheLeveque1994()

The She–Lévêque (1994) intermittency model for the inertial-range scaling exponents. Its
[`scaling_exponent`](@ref)`(law, p)` gives the anomalous exponent

```math
\\zeta_p = \\frac{p}{9} + 2\\left[1 - \\left(\\tfrac{2}{3}\\right)^{p/3}\\right]
```

of the ``p``-th-order longitudinal structure function ``D_{L\\dots}(r) \\sim r^{\\zeta_p}``. It is
parameter-free, exact at ``\\zeta_3 = 1`` (the 4/5 law), and bends below the self-similar ``p/3`` for
``p > 3`` — the signature of small-scale intermittency. It predicts exponents, not amplitudes, so it
implements [`scaling_exponent`](@ref) but not [`structure_function`](@ref).
"""
struct SheLeveque1994 <: StructureFunction end

scaling_exponent(::SheLeveque1994, order::Real) = order / 9 + 2 * (1 - (2 / 3)^(order / 3))

provenance(::SheLeveque1994) = _SHELEVEQUE


end # module StructureFunctions
