"""
    Phenomenology.Scalings

Dimensionless turbulence constants and their Reynolds-number trends, evaluated by [`scaling`](@ref).

- [`Sreenivasan1998`](@ref) — the normalized dissipation constant ``C_\\varepsilon = \\varepsilon L/u'^3``,
  a high-Reynolds-number plateau with an optional finite-Reynolds-number correction.
- [`Sreenivasan1995`](@ref) — the (three-dimensional) Kolmogorov constant ``C_K`` of the inertial-range
  spectrum.
- [`Li2008`](@ref) — the box-normalized dissipation group ``k/(L\\varepsilon)^{2/3}``, which (inverted,
  via [`stationary_dissipation`](@ref)) predicts the dissipation a stationary run sustains from its energy
  and box side length.
"""
module Scalings

using ..Phenomenology: TurbulenceLaw, FlowParameters, Reference, taylor_reynolds
import ..Phenomenology: scaling, provenance

export ScalingLaw, Sreenivasan1998, Sreenivasan1995, Li2008, scaling, stationary_dissipation


"""
    ScalingLaw <: TurbulenceLaw

Supertype of the laws for a **dimensionless turbulence constant** — a pure number characterizing
developed turbulence (the normalized dissipation ``C_\\varepsilon``, the Kolmogorov constant ``C_K``,
the derivative skewness, …), possibly Reynolds-number-dependent. A law predicts the constant via
[`scaling`](@ref)`(law, fp)`; the *measured* value comes from a run, and the comparison is prediction
against measurement.
"""
abstract type ScalingLaw <: TurbulenceLaw end


"""
    stationary_dissipation(law, energy, side_length)

The dissipation rate ``\\varepsilon`` a stationary run sustains, predicted by a box-normalized
dissipation `law` from the turbulent kinetic energy `energy` (``k``) and the periodic-box side length
`side_length` (``L``) — the inverse of the law's [`scaling`](@ref) group (each law owns its own inverse;
[`Li2008`](@ref) gives the ``(k/G)^{3/2}/L`` form). This is the seam by which a run's
viscosity can be set from its grid and target energy, rather than the reverse.
"""
function stationary_dissipation end


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


const _LI2008 = Reference("Li et al. (2008), *J. Turbulence* **9**, N31 (JHTDB); dissipation-anomaly lineage Taylor 1935 / Sreenivasan 1998 / Kaneda et al. 2003";
                          valid_Reλ = (100.0, Inf))

"""
    Li2008(; constant = 0.9)

The box-normalized dissipation group

```math
G = \\frac{k}{(L\\varepsilon)^{2/3}} \\approx 0.9,
```

relating the turbulent kinetic energy ``k``, the periodic-box side length ``L``, and the dissipation
rate ``\\varepsilon`` — nearly Reynolds-number-independent from the Johns Hopkins Turbulence Database
(JHTDB) forced-isotropic dataset (``\\mathrm{Re}_\\lambda \\approx 433``) and consistent with
higher-Reynolds-number periodic-box DNS. It is a distinct group from the classical
dissipation anomaly ``C_\\varepsilon = \\varepsilon L_{11}/u'^3`` (Taylor 1935; Sreenivasan 1998; Kaneda
et al. 2003 for the periodic box), whose high-Reynolds-number plateau ``C_\\varepsilon \\approx 0.5`` is
normalized on the **integral** scale ``L_{11}``, not the box side ``L``. Formed on a common length the two
are exactly related by ``G = \\tfrac{3}{2}\\,C_\\varepsilon^{-2/3}`` (using ``u'^2 = 2k/3``); but the quoted
``G \\approx 0.9`` (box side) and ``C_\\varepsilon \\approx 0.5`` (integral scale) sit at *different*
lengths (``L/L_{11} \\approx 5``), so they must not be substituted into that identity directly.

The `constant` is the group value ``G`` (default `0.9`); [`scaling`](@ref)`(law, fp)` returns it;
inverted, [`stationary_dissipation`](@ref)`(law, energy, side_length)` predicts the dissipation a
stationary run of energy ``k`` in a box ``L`` sustains, ``\\varepsilon = (k/G)^{3/2}/L`` — the seam the
run layer uses to set the viscosity from the grid and target energy.
"""
struct Li2008 <: ScalingLaw
  constant::Float64
end

Li2008(; constant = 0.9) = Li2008(constant)

scaling(m::Li2008, ::FlowParameters) = m.constant

stationary_dissipation(m::Li2008, energy::Real, side_length::Real) = (energy / m.constant)^(3//2) / side_length

provenance(::Li2008) = _LI2008


end # module Scalings
