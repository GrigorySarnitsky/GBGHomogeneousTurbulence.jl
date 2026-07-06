# Notation

The symbols used throughout the docstrings and the design documents, with the code object each one
denotes. All mathematics is rendered LaTeX; a code identifier always appears in `backticks` and never
inside a math span. This page is the single reference — a docstring introduces a symbol on first use
and need not repeat the convention.

The physical conventions follow Pope, *Turbulent Flows*; the field and spectral conventions follow
[`GBGPeriodicFields`](https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl).

## Conventions

| Concept | Symbol | Convention |
|---|---|---|
| Imaginary unit | ``\mathrm i`` | Upright, always — never bare italic `i`, never `\imath`. Writing it upright frees `i` for use as an index. |
| Indices | ``i, j, a, \dots`` | Italic, taken in order. A repeated index within a term is summed over the three components ``1,2,3`` (Einstein convention). |
| Spatial average | ``\langle\,\cdot\,\rangle`` | The box average ``\frac1{\lvert\Omega\rvert}\int_\Omega(\cdot)\,\mathrm d\mathbf x`` over the periodic domain ``\Omega`` — the homogeneous ensemble average. |
| Spectral representation | ``\hat f`` | The field ``f`` in spectral (Fourier) representation, `to_spectral(f)`. A field is one physical object; physical and spectral are two representations of it. |
| Wavenumber clash | ``\mathbf k`` / ``\kappa`` / ``k`` | Kept distinct: **bold** ``\mathbf k`` is the wavenumber *vector*, ``\kappa=\lvert\mathbf k\rvert`` its *magnitude* (the spectrum coordinate), and italic scalar ``k`` is the *turbulent kinetic energy*. |

## Physical variables

| Symbol | Meaning | Code |
|---|---|---|
| ``\mathbf u`` | the incompressible velocity field, ``\nabla\cdot\mathbf u = 0`` | the velocity state |
| ``\boldsymbol\omega`` | the vorticity ``\nabla\times\mathbf u`` | `velocity_vorticity!` |
| ``\varphi`` | the passive scalar (never ``\theta``) | the scalar state |
| ``p`` | the pressure (absorbed by the Leray projection, never stored) | — |
| ``\mathbf f`` | a body forcing on the momentum equation | `AbstractForcing` |
| ``\mathbf x``, ``t`` | position in the box ``\Omega``; time | — |

## Parameters

| Symbol | Meaning | Code |
|---|---|---|
| ``\nu`` | kinematic viscosity (sets the Reynolds number) | `Physics.viscosity` |
| ``\mathrm{Sc}`` | Schmidt number | `Physics.schmidt` |
| ``\kappa_\varphi`` | scalar diffusivity ``\nu/\mathrm{Sc}`` | ``\nu`` / `schmidt` |
| ``\mathrm{Re}``, ``\mathrm{Re}_\lambda`` | Reynolds number; Taylor-microscale Reynolds number | — (dimensionless control) |

*(The scalar diffusivity is written ``\kappa_\varphi`` where it must not be confused with the
wavenumber magnitude ``\kappa``; docstrings use ``\kappa`` for it where context is unambiguous.)*

## Spectral representation and operators

| Symbol | Meaning | Code |
|---|---|---|
| ``\mathbf k`` | wavenumber vector, components ``k_a`` | `FieldSpectralMultipliers` |
| ``\kappa`` | wavenumber magnitude ``\lvert\mathbf k\rvert`` (spectrum coordinate) | — |
| ``\lvert\mathbf k\rvert^2`` | squared wavenumber, the symbol of ``-\nabla^2`` | `ops.squared_wavenumber` |
| ``\mathcal F``, ``\mathcal F^{-1}`` | forward / inverse real transform | `to_spectral`, `to_physical` |
| ``\nabla\times``, ``\nabla\cdot`` | curl, divergence | `curl`, `divergence` |
| ``\mathbb P`` | the Helmholtz (Leray) projection onto divergence-free fields | `helmholtz_projection` |
| ``\mathcal E(\mathbf k)`` | the diffusive integrating factor ``\exp\!\big((A(\mathbf k)-D\lvert\mathbf k\rvert^2)\Delta t\big)`` | `integrating_factor!` |
| ``\star`` | periodic convolution (the dealias/band/envelope kernels) | `convolve` |

## Diagnostics

| Symbol | Meaning | Code |
|---|---|---|
| ``k`` | turbulent kinetic energy ``\tfrac12\langle\lvert\mathbf u\rvert^2\rangle`` | `kinetic_energy` |
| ``\varepsilon`` | mean dissipation rate ``\nu\langle\lvert\boldsymbol\omega\rvert^2\rangle`` | `dissipation` |
| ``E(\kappa)`` | energy spectrum (energy per unit wavenumber) | `radial_spectrum` (from `GBGPeriodicFields`) |
| ``\langle\varphi^2\rangle`` | scalar variance | `scalar_variance` |
| ``\chi`` | scalar dissipation rate ``2\kappa_\varphi\langle\lvert\nabla\varphi\rvert^2\rangle`` | `scalar_dissipation` |

## Numerics

| Symbol | Meaning | Code |
|---|---|---|
| ``N`` | grid points per side | `resolution` |
| ``L`` | box side (``\Omega = [0,L)^3``) | `box` |
| ``\Delta t`` | timestep | `dt` |
| ``C`` | advective-CFL ceiling, ``\Delta t = C\,\Delta x/\max_i\lvert u_i\rvert`` | `recommended_cfl` |
| ``\kappa_{\max}`` | dealiased maximum wavenumber, ``\tfrac23\cdot\tfrac N2\cdot\tfrac{2\pi}{L}`` | `dealias_fraction` |
| ``A_i, B_i, d_i`` | the low-storage Runge–Kutta stage coefficients and node increments | `IFLowStorageRK3` |
| ``T`` | the real element type (``\texttt{Float32}`` / ``\texttt{Float64}``) | `scalar_type` |

## Forcing

| Symbol | Meaning | Code |
|---|---|---|
| ``A(\mathbf k)`` | per-mode linear forcing rate, folded into ``\mathcal E`` | `forcing_rate!` |
| ``\varepsilon_{\text{target}}`` | target energy-injection rate | `ConstantPower(power=…)` |
| ``T_L`` | forcing correlation time (Ornstein–Uhlenbeck) | `StochasticOU(correlation_time=…)` |
| ``\sigma^2`` | stationary forcing variance ``\langle\lvert\mathbf f\rvert^2\rangle`` | `StochasticOU(variance=…)` |

## Lens symbols

Interpretive symbols from the design document's *Lenses* section. They are not realised in code — they
name the framework the package is understood and validated through (Mori–Zwanzig, the commuting
square, the filtered-density-function Model), not a type.

| Symbol | Meaning |
|---|---|
| ``\Pi`` | a coarse-graining / filtering projection (the LES filter) |
| ``\tau_{ij}`` | the subgrid stress ``\overline{u_i u_j}-\bar u_i\bar u_j`` |
| ``S_{\text{fine}}``, ``S_{\text{coarse}}`` | the fine (DNS) and coarse (LES) flow maps |
| ``F(\mathbf v;\mathbf x,t)`` | the velocity filtered density function (FDF) |
| ``P`` | a Mori–Zwanzig projection onto resolved variables |
