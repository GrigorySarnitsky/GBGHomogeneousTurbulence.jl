"""
    Phenomenology.StructureFunctions

Inertial-range structure-function laws — parametrizations of the longitudinal velocity structure
function ``D_{L\\dots}(r)`` and the mixed velocity–scalar structure function
``\\langle\\delta u_L\\,(\\delta\\varphi)^2\\rangle`` (Yaglom), evaluated by [`structure_function`](@ref).

- [`Kolmogorov1941`](@ref) — the K41 inertial-range laws: the exact 4/5 law, the 2/3 law, and the
  self-similar exponents (via [`scaling_exponent`](@ref)).
- [`Kolmogorov1962`](@ref) / [`SheLeveque1994`](@ref) — the K62 log-normal and She–Lévêque
  intermittency models: the anomalous scaling exponents ``\\zeta_p`` (via [`scaling_exponent`](@ref)).
- [`Yaglom1949`](@ref) — the exact 4/3 law for the mixed velocity–scalar structure function.
- [`Lundgren2002`](@ref) — the finite-Reynolds-number correction to the 4/5 law.
"""
module StructureFunctions

using ..Phenomenology: TurbulenceLaw, FlowParameters, Reference, taylor_reynolds
import ..Phenomenology: structure_function, scaling_exponent, provenance

export StructureFunction, Kolmogorov1941, Kolmogorov1962, SheLeveque1994, Yaglom1949, Lundgren2002,
       structure_function, scaling_exponent


"""
    StructureFunction <: TurbulenceLaw

Supertype of the inertial-range structure-function laws — parametrizations of the longitudinal velocity
moments ``D_{L\\dots}(r) = \\langle(\\delta u_L)^p\\rangle`` (the ``p``-th moment of the longitudinal
velocity increment across a separation ``r``) and the mixed velocity–scalar moment
``\\langle\\delta u_L\\,(\\delta\\varphi)^2\\rangle`` ([`Yaglom1949`](@ref)), evaluated by
[`structure_function`](@ref).
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

Both hold in the inertial range ``\\eta \\ll r \\ll L``. The state `fp` (a [`FlowParameters`](@ref))
supplies the dissipation rate ``\\varepsilon``; any other `order` throws (K41 fixes only these two
longitudinal moments universally). Its [`scaling_exponent`](@ref)`(law, order)` gives the self-similar
K41 exponent ``\\zeta_p = p/3``.
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
[`scaling_exponent`](@ref)`(law, order)` gives the anomalous exponent

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


const _K62 = Reference("Kolmogorov (1962), *J. Fluid Mech.* **13**, 82"; valid_Reλ = (200.0, Inf))

"""
    Kolmogorov1962(; μ = 0.25)

The Kolmogorov (1962) log-normal (refined-similarity) intermittency model. Its
[`scaling_exponent`](@ref)`(law, order)` gives

```math
\\zeta_p = \\frac{p}{3} - \\frac{\\mu}{18}\\,p\\,(p - 3),
```

with `μ` the intermittency exponent (``\\approx 0.25``). Like [`SheLeveque1994`](@ref) it is exact at
``\\zeta_3 = 1`` and bends below the self-similar ``p/3`` for ``p > 3``, but as a quadratic in ``p`` (the
log-normal ansatz) rather than She–Lévêque's log-Poisson form.
"""
struct Kolmogorov1962 <: StructureFunction
  μ::Float64
end

Kolmogorov1962(; μ = 0.25) = Kolmogorov1962(μ)

scaling_exponent(m::Kolmogorov1962, order::Real) = order / 3 - (m.μ / 18) * order * (order - 3)

provenance(::Kolmogorov1962) = _K62


const _YAGLOM = Reference("Yaglom (1949), *Dokl. Akad. Nauk SSSR* **69**, 743"; valid_Reλ = (100.0, Inf))

"""
    Yaglom1949()

The Yaglom (1949) "4/3 law" — the exact inertial-range scaling of the mixed third-order velocity–scalar
structure function, the passive-scalar analogue of the 4/5 law (a consequence of the Yaglom relation);
it carries no free constant. Its classical ``-\\tfrac{4}{3}`` coefficient is stated for the dissipation
rate of the *half*-variance ``\\tfrac12\\langle\\varphi^2\\rangle``, namely
``\\varkappa\\langle\\lvert\\nabla\\varphi\\rvert^2\\rangle`` — just as the 4/5 law pairs with
``\\varepsilon = \\nu\\langle\\lvert\\boldsymbol\\omega\\rvert^2\\rangle``, the dissipation of the
half-energy ``k``. This package's ``\\varepsilon_\\varphi = 2\\varkappa\\langle\\lvert\\nabla\\varphi\\rvert^2\\rangle``
(`scalar_dissipation`) is the *full*-variance rate, twice that, so in these variables the law is

```math
\\langle\\delta u_L\\,(\\delta\\varphi)^2\\rangle(r) = -\\tfrac{2}{3}\\,\\varepsilon_\\varphi\\,r.
```

[`structure_function`](@ref)`(law, r, fp; order = 3)` returns it, reading the scalar dissipation
``\\varepsilon_\\varphi`` (`fp.scalar_dissipation`, which must be set); any other `order` throws.
"""
struct Yaglom1949 <: StructureFunction end

function structure_function(::Yaglom1949, r, fp::FlowParameters; order::Integer = 3)
  order == 3 || throw(ArgumentError("Yaglom1949 gives only the 3rd-order (4/3) mixed law; got order=$order"))
  isnan(fp.scalar_dissipation) && throw(ArgumentError(
    "Yaglom1949 needs the scalar dissipation rate — set `scalar_dissipation` in FlowParameters"))
  return -(2//3) * fp.scalar_dissipation * r
end

provenance(::Yaglom1949) = _YAGLOM


const _LUNDGREN2002 = Reference("Lundgren (2002), *Phys. Fluids* **14**, 638"; valid_Reλ = (50.0, Inf))

"""
    Lundgren2002()

The finite-Reynolds-number correction to the 4/5 law for the third-order longitudinal velocity
structure function,

```math
D_{LLL}(r) = -\\left(\\tfrac{4}{5} - \\frac{8.45}{\\mathrm{Re}_\\lambda^{2/3}}\\right)\\varepsilon\\,r,
```

which relaxes to the exact ``-\\tfrac45\\varepsilon r`` of [`Kolmogorov1941`](@ref) as
``\\mathrm{Re}_\\lambda \\to \\infty`` — turbulence at a finite Reynolds number never quite reaches the
asymptotic 4/5 slope (Lundgren 2002; Sagaut & Cambon 2018, Table 4.5).
[`structure_function`](@ref)`(law, r, fp; order = 3)` returns it, reading ``\\mathrm{Re}_\\lambda`` from
`fp` via [`taylor_reynolds`](@ref); any other `order` throws.
"""
struct Lundgren2002 <: StructureFunction end

function structure_function(::Lundgren2002, r, fp::FlowParameters; order::Integer = 3)
  order == 3 || throw(ArgumentError("Lundgren2002 gives only the 3rd-order (finite-Re 4/5) law; got order=$order"))
  return -(4 // 5 - 8.45 / taylor_reynolds(fp)^(2 // 3)) * fp.dissipation * r
end

provenance(::Lundgren2002) = _LUNDGREN2002


end # module StructureFunctions
