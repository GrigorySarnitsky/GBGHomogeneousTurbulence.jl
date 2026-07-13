# Notation

The symbols used throughout the docstrings and the design documents, with the code object each one
denotes. All mathematics is rendered LaTeX; a code identifier always appears in `backticks` and never
inside a math span. This page is the single reference — a docstring introduces a symbol on first use
and need not repeat the convention.

The physical conventions are standard turbulence usage — see Pope, *Turbulent Flows*; the field and
spectral conventions follow [`GBGPeriodicFields`](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl),
a direct dependency.

## Conventions

| Concept | Symbol | Convention |
|---|---|---|
| Imaginary unit | ``\mathrm i`` | Upright, always — never bare italic `i`, never `\imath`. Writing it upright frees `i` for use as an index. |
| Indices | ``i, j, a, \dots`` | Italic, taken in order. A repeated index within a term is summed over the three components ``1,2,3`` (Einstein convention). |
| Spatial average | ``\langle\,\cdot\,\rangle`` | The box average ``\frac1{\lvert\Omega\rvert}\int_\Omega(\cdot)\,\mathrm d\boldsymbol x`` over the periodic domain ``\Omega`` — the homogeneous ensemble average. |
| Spectral representation | ``\hat f`` | The field ``f`` in spectral (Fourier) representation, `to_spectral(f)`. A field is one physical object; physical and spectral are two representations of it. |
| Wavenumber clash | ``\boldsymbol{\kappa}`` / ``\kappa`` / ``k`` | Kept distinct: **bold** ``\boldsymbol{\kappa}`` is the wavenumber *vector*, ``\kappa = \lvert\boldsymbol{\kappa}\rvert`` its *magnitude* (the spectrum coordinate), and italic scalar ``k`` is the *turbulent kinetic energy*. The scalar diffusivity ``\varkappa`` (Parameters) is a fourth, deliberately distinct glyph. |

## Physical variables

| Symbol | Meaning | Code |
|---|---|---|
| ``\boldsymbol u`` | the incompressible velocity field, ``\nabla\cdot\boldsymbol u = 0`` | the velocity state |
| ``\boldsymbol\omega`` | the vorticity ``\nabla\times\boldsymbol u`` | `vorticity_to_physical!` |
| ``\varphi`` | the passive scalar (never ``\theta``) | the scalar state |
| ``p`` | the pressure (absorbed by the Leray projection, never stored) | — |
| ``\boldsymbol f`` | a body forcing on the momentum equation | `AbstractForcing` |
| ``\boldsymbol x``, ``t`` | position in the box ``\Omega``; time | — |

## Parameters

| Symbol | Meaning | Code |
|---|---|---|
| ``\nu`` | kinematic viscosity (sets the Reynolds number) | `conditions.viscosity` |
| ``\mathrm{Sc}`` | Schmidt number | `conditions.schmidt` |
| ``\varkappa`` | scalar diffusivity ``\nu/\mathrm{Sc}`` | `ν / schmidt` |
| ``\mathrm{Re}``, ``\mathrm{Re}_\lambda`` | Reynolds number; Taylor-microscale Reynolds number | `1 / ν` (``\mathrm{Re}_\lambda`` measured) |

*(The scalar diffusivity ``\varkappa`` is a deliberately distinct glyph from the wavenumber
magnitude ``\kappa`` and the turbulent kinetic energy ``k``.)*

## Spectral representation and operators

| Symbol | Meaning | Code |
|---|---|---|
| ``\boldsymbol{\kappa}`` | wavenumber vector, components ``\kappa_a`` | [`FieldSpectralMultipliers`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.FieldSpectralMultipliers) |
| ``\kappa`` | wavenumber magnitude ``\lvert\boldsymbol{\kappa}\rvert`` (spectrum coordinate) | — |
| ``\lvert\boldsymbol{\kappa}\rvert^2`` | squared wavenumber; in spectral space ``-\nabla^2`` acts as multiplication by it | `domain.squared_wavenumber` |
| ``\mathcal F``, ``\mathcal F^{-1}`` | forward / inverse real transform | [`to_spectral`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.to_spectral), [`to_physical`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.to_physical) |
| ``\nabla\times``, ``\nabla\cdot`` | curl, divergence | [`curl`](@extref GBGPeriodicFields GBGPeriodicFields.DifferentialOperators.curl), [`divergence`](@extref GBGPeriodicFields GBGPeriodicFields.DifferentialOperators.divergence) |
| ``\mathbb P`` | the Helmholtz (Leray) projection onto divergence-free fields | [`helmholtz_projection`](@extref GBGPeriodicFields GBGPeriodicFields.DifferentialOperators.helmholtz_projection) |
| ``\mathcal E(\boldsymbol{\kappa})`` | the diffusive integrating factor ``\exp\!\big((A(\boldsymbol{\kappa})-D\lvert\boldsymbol{\kappa}\rvert^2)\Delta t\big)`` (``D`` the diffusivity — ``\nu`` for the velocity, ``\varkappa`` for the scalar; ``A(\boldsymbol{\kappa})`` the linear forcing rate) | `integrating_factor!` |
| ``\star`` | periodic convolution (the dealias/band/envelope kernels) | [`convolve`](@extref GBGPeriodicFields GBGPeriodicFields.Convolution.convolve) |

## Diagnostics

| Symbol | Meaning | Code |
|---|---|---|
| ``k`` | turbulent kinetic energy ``\tfrac12\langle\lvert\boldsymbol u\rvert^2\rangle`` | `kinetic_energy` |
| ``\varepsilon`` | mean dissipation rate ``\nu\langle\lvert\boldsymbol\omega\rvert^2\rangle`` | `dissipation` |
| ``E(\kappa)`` | energy spectrum (energy per unit wavenumber), ``k = \sum_\kappa E(\kappa)`` | `energy_spectrum` (the `GBGPeriodicFields` radial spectrum, halved) |
| ``\langle\varphi^2\rangle`` | scalar variance | `scalar_variance` |
| ``\varepsilon_\varphi`` | scalar dissipation rate ``2\varkappa\langle\lvert\nabla\varphi\rvert^2\rangle`` | `scalar_dissipation` |

## Derived scales

Measured from the resolved state, or derived from it through a `FlowParameters` bundle and its helpers.

| Symbol | Meaning | Code |
|---|---|---|
| ``u'`` | root-mean-square velocity (one component), ``u' = \sqrt{2k/3}`` | `flow_parameters` |
| ``\eta`` | Kolmogorov (dissipation) microscale, ``(\nu^3/\varepsilon)^{1/4}`` | `kolmogorov_length` |
| ``\tau_\eta`` | Kolmogorov time, ``(\nu/\varepsilon)^{1/2}`` | `kolmogorov_time` |
| ``\lambda`` | Taylor microscale, ``\sqrt{15\,\nu\,u'^2/\varepsilon}`` | `taylor_microscale` |

## Numerics

| Symbol | Meaning | Code |
|---|---|---|
| ``N`` | grid points per side | `grid_points_per_axis` |
| ``L`` | box side (``\Omega = [0,L)^3``); **also** the integral length scale in turbulence diagnostics (`integral_scale`, the model-spectrum roll-off ``f_L(\kappa L)``), which the box side only approximates | `side_length` |
| ``\Delta t`` | timestep | `dt` |
| ``C`` | advective-CFL ceiling, ``\Delta t = C\,\Delta x/\max_i\lvert u_i\rvert`` | `recommended_cfl` |
| ``\kappa_{\max}`` | dealiased maximum wavenumber, ``\tfrac23\cdot\tfrac N2\cdot\tfrac{2\pi}{L}`` for the default ``2/3`` rule (set by the `dealiasing` strategy) | `DealiasingStrategy` |
| ``A_i, B_i, d_i`` | the low-storage Runge–Kutta stage coefficients and node increments | `IFLowStorageRK3` |
| ``T`` | the real element type ([`Float32`](@extref Julia :jl:type:Core.Float32) / [`Float64`](@extref Julia :jl:type:Core.Float64)) | `scalar_type` |

## Forcing

| Symbol | Meaning | Code |
|---|---|---|
| ``A(\boldsymbol{\kappa})`` | per-mode linear forcing rate, folded into ``\mathcal E`` | `set_forcing_rate!` |
| ``\varepsilon_{\text{target}}`` | target energy-injection rate | `ConstantPower(target=…)` |
