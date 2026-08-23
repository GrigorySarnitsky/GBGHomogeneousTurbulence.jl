"""
    Phenomenology.Scalings

Dimensionless turbulence constants and their Reynolds-number trends, evaluated by [`scaling`](@ref).

- [`ScalingLaw`](@ref) — the family root every law below subtypes.
- [`Sreenivasan1998`](@ref) — the normalized dissipation constant ``C_\\varepsilon``
  (``L_{11}`` the longitudinal integral scale), a high-Reynolds-number plateau with an optional
  finite-Reynolds-number correction.
- [`Sreenivasan1995`](@ref) — the (three-dimensional) Kolmogorov constant ``C_K`` of the inertial-range
  spectrum.
- [`stationary_dissipation`](@ref) — the dissipation a stationary run sustains, predicted from its
  energy and box side.
- [`Li2008`](@ref) — the box-normalized dissipation group ``G``, the constant
  `stationary_dissipation` inverts.
"""
module Scalings

using ..Phenomenology: TurbulenceLaw, FlowParameters, Reference, taylor_reynolds
import ..Phenomenology: scaling, provenance

export ScalingLaw, Sreenivasan1998, Sreenivasan1995, Li2008, scaling, stationary_dissipation


"""
    ScalingLaw <: TurbulenceLaw

Supertype of the laws for a **dimensionless turbulence constant** — a pure number characterizing
developed turbulence — here the normalized dissipation ``C_\\varepsilon``, the Kolmogorov constant
``C_K``, and the box-normalized dissipation group ``G`` — possibly Reynolds-number-dependent. A law predicts the constant via
[`scaling`](@ref)`(law, fp)`; the *measured* value comes from a run, and the comparison is prediction
against measurement.
"""
abstract type ScalingLaw <: TurbulenceLaw end


"""
    stationary_dissipation(law, kinetic_energy, side_length) -> Float64

The dissipation rate ``\\varepsilon`` a stationary run sustains, predicted by a box-normalized
dissipation `law` from the turbulent kinetic energy ``\\texttt{kinetic\\_energy} \\equiv k`` and the
periodic-box side length ``\\texttt{side\\_length} \\equiv L`` — the inverse of the law's [`scaling`](@ref) group (each law owns its own inverse;
[`Li2008`](@ref) gives the ``(k/G)^{3/2}/L`` form). This is the seam by which a run's
viscosity can be set from its grid and target energy, rather than the reverse.
"""
function stationary_dissipation end


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


const _LI2008 = Reference("Li et al. (2008), *J. Turbulence* **9**, N31 (JHTDB). [doi:10.1080/14685240802376389](https://doi.org/10.1080/14685240802376389)";
                          valid_Reλ = (100.0, Inf))

"""
    Li2008(; dissipation_group = 0.9)

The box-normalized dissipation group

```math
G = \\frac{k}{(L\\varepsilon)^{2/3}} \\approx 0.9,
```

relating the turbulent kinetic energy ``k``, the periodic-box side length ``L``, and the
dissipation rate ``\\varepsilon`` — nearly Reynolds-number-independent. The value is this
package's own reduction of the Johns Hopkins Turbulence Database (JHTDB) forced-isotropic
dataset (``\\mathrm{Re}_\\lambda \\approx 433``), consistent with higher-Reynolds-number
periodic-box DNS.

The `dissipation_group` is the group value ``G`` (default `0.9`); [`scaling`](@ref)`(law, fp)`
returns it. Inverted, `stationary_dissipation(law, kinetic_energy, side_length)` predicts the
dissipation a stationary run of energy ``k`` in a box ``L`` sustains,
``\\varepsilon = (k/G)^{3/2}/L`` — the seam the run layer uses to set the viscosity from the
grid and target energy.

``G`` is a distinct group from the classical dissipation anomaly
``C_\\varepsilon = \\varepsilon L_{11}/u'^3`` (Taylor 1935, *Proc. R. Soc. A* **151**, 421–444,
[doi:10.1098/rspa.1935.0158](https://doi.org/10.1098/rspa.1935.0158); Sreenivasan 1998,
[doi:10.1063/1.869575](https://doi.org/10.1063/1.869575); Kaneda et al. 2003,
[doi:10.1063/1.1539855](https://doi.org/10.1063/1.1539855), for the periodic box), whose
high-Reynolds-number plateau ``C_\\varepsilon \\approx 0.5`` is normalized on the **integral**
scale ``L_{11}``, not the box side ``L``.

On a common length the two are exactly related by ``G = \\tfrac{3}{2} C_\\varepsilon^{-2/3}``
(using ``u'^2 = 2k/3``). The quoted values, however, sit at *different* lengths
(``L/L_{11} \\approx 5``), so they must not be substituted into that identity directly — and,
as fits to different datasets, they need not close exactly: carrying
``C_\\varepsilon \\approx 0.5`` across at that ratio gives ``G \\approx 0.81`` against the
quoted ``0.9``.

# Fields
The plain constructor `Li2008(dissipation_group)` takes the field directly:
- `dissipation_group` — the group value ``G``.
"""
struct Li2008 <: ScalingLaw
  dissipation_group::Float64
end

Li2008(; dissipation_group = 0.9) = Li2008(dissipation_group)

scaling(m::Li2008, ::FlowParameters) = m.dissipation_group

stationary_dissipation(m::Li2008, kinetic_energy::Real, side_length::Real) =
  (kinetic_energy / m.dissipation_group)^(3//2) / side_length

provenance(::Li2008) = _LI2008


end # module Scalings
