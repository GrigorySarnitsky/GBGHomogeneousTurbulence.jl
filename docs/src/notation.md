# Notation

The symbols used throughout the docstrings and the design documents, with the code object each one
denotes. All mathematics is rendered LaTeX; a code identifier always appears in `backticks` and never
inside a math span. This page is the single reference — a docstring introduces a symbol on first use
and need not repeat the convention.

The physical conventions are standard turbulence usage — see Pope (2000), *Turbulent Flows*; the field and
spectral conventions follow [`GBGPeriodicFields`](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl),
a direct dependency.

## Conventions

| Concept | Symbol | Convention |
|:---|:---|:---|
| Imaginary unit | ``\mathrm{i}`` | Upright, always — never bare italic ``i``, never ``\imath``. Writing it upright frees ``i`` for use as an index. |
| Indices | ``i, j, a, \dots`` | Italic, taken in order. A repeated index within a term is summed over the three components ``1,2,3`` (Einstein convention). |
| Spatial average | ``\langle \cdot \rangle`` | The box average ``\frac{1}{\lvert\Omega\rvert}\int_\Omega(\cdot)\,\mathrm d\boldsymbol{x}`` over the periodic domain ``\Omega`` — the single-realization estimate of the homogeneous ensemble average (exact only in the ergodic, infinite-box limit; at a finite box it retains the large-scale statistical fluctuation). |
| Spectral representation | ``\hat f`` | The field ``f`` in spectral (Fourier) representation, `to_spectral(f)`. A field is one physical object; physical and spectral are two representations of it. |
| Wavenumber clash | ``\boldsymbol{\kappa}`` / ``\kappa`` / ``k`` | Kept distinct: **bold** ``\boldsymbol{\kappa}`` is the wavenumber *vector*, ``\kappa = \lvert\boldsymbol{\kappa}\rvert`` its *magnitude* (the spectrum coordinate), and italic scalar ``k`` is the *turbulent kinetic energy*. The scalar diffusivity ``\varkappa`` (Parameters) is a fourth, deliberately distinct glyph. |

## Physical variables

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``\boldsymbol{u}`` | the incompressible velocity field, ``\nabla\cdot\boldsymbol{u} = 0`` | the velocity state |
| ``\boldsymbol{\omega}`` | the vorticity ``\nabla\times\boldsymbol{u}`` | `vorticity_to_physical!` |
| ``\varphi`` | the passive scalar (never ``\theta``) | the scalar state |
| ``p`` | the pressure (absorbed by the Leray–Helmholtz projection, never stored) | — |
| ``\boldsymbol{f}`` | a body forcing on the momentum equation | `AbstractForcing` |
| ``f_\varphi`` | a body forcing on the passive-scalar equation | `AbstractForcing` (via `scalar_forcing`) |
| ``\boldsymbol{x}``, ``t`` | position in the box ``\Omega``; time | — |
| ``\boldsymbol{X}(t)`` | the position of a tracer particle (capitalised, to keep it distinct from the Eulerian coordinate ``\boldsymbol{x}``) | [`particle_positions`](@ref) |
| ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` | the particle velocities — the velocity sampled at each tracer's position at the iteration boundary ``t_n`` | [`particle_velocities`](@ref) |
| ``M`` | the number of tracer particles | [`number_of_tracers`](@ref) |

## Parameters

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``\nu`` | kinematic viscosity (sets the Reynolds number) | `conditions.viscosity` |
| ``\mathrm{Sc}`` | Schmidt number | `conditions.schmidt` |
| ``\varkappa`` | scalar diffusivity ``\nu/\mathrm{Sc}`` | `ν / schmidt` |
| ``\mathrm{Re}`` | Reynolds number, set through the viscosity on the box's order-one reference scales (the default initial condition seeds ``u' = 1``, and the large scales are of order the box side — the ``U`` and ``L`` of ``UL/\nu`` are units, not inputs; the measured value is ``\mathrm{Re}_\lambda``) | `1 / ν` |

*(The scalar diffusivity ``\varkappa`` is a deliberately distinct glyph from the wavenumber
magnitude ``\kappa`` and the turbulent kinetic energy ``k``.)*

## Spectral representation and operators

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``\boldsymbol{\kappa}`` | wavenumber vector, components ``\kappa_a`` | [`FieldSpectralMultipliers`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.FieldSpectralMultipliers) |
| ``\kappa`` | wavenumber magnitude ``\lvert\boldsymbol{\kappa}\rvert`` (spectrum coordinate) | — |
| ``\lvert\boldsymbol{\kappa}\rvert^2`` | squared wavenumber; in spectral space ``-\nabla^{2}`` acts as multiplication by it | `domain.squared_wavenumber_kernel` |
| ``\mathcal F``, ``\mathcal F^{-1}`` | forward / inverse real transform | [`to_spectral`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.to_spectral), [`to_physical`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.to_physical) |
| ``\nabla\times``, ``\nabla\cdot`` | curl, divergence | [`curl`](@extref GBGPeriodicFields GBGPeriodicFields.DifferentialOperators.curl), [`divergence`](@extref GBGPeriodicFields GBGPeriodicFields.DifferentialOperators.divergence) |
| ``\mathbb{P}`` | the Leray–Helmholtz projection onto divergence-free fields | [`helmholtz_projection`](@extref GBGPeriodicFields GBGPeriodicFields.DifferentialOperators.helmholtz_projection) |
| ``\mathcal{E}(\boldsymbol{\kappa})`` | the diffusive integrating factor ``\exp\!\big((A(\boldsymbol{\kappa})-D\lvert\boldsymbol{\kappa}\rvert^2)\tau\big)`` over an interval ``\tau`` — a Runge–Kutta stage substep ``d_i\Delta t``, or the whole step ``\Delta t`` (``D`` the diffusivity — ``\nu`` for the velocity, ``\varkappa`` for the scalar; ``A(\boldsymbol{\kappa})`` the linear forcing rate) | [`velocity_factor`](@ref), [`scalar_factor`](@ref) |
| ``\star`` | periodic convolution (the dealias/band/envelope kernels) | [`convolve`](@extref GBGPeriodicFields GBGPeriodicFields.Convolution.convolve) |
| ``\widehat{\boldsymbol{N}}`` | a field's assembled explicit right-hand side — the dealiased nonlinear term plus any additive forcing source — in spectral representation | [`velocity_rhs!`](@ref), [`scalar_rhs!`](@ref) |

## Diagnostics

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``k`` | turbulent kinetic energy ``\tfrac{1}{2}\langle\lvert\boldsymbol{u}\rvert^2\rangle`` | `kinetic_energy` |
| ``\varepsilon`` | mean dissipation rate ``\nu\langle\lvert\boldsymbol{\omega}\rvert^2\rangle`` | `dissipation` |
| ``E(\kappa)`` | the energy spectrum, in two readings related by the shell width ``\Delta\kappa = 2\pi/L``: as *measured*, the energy in each wavenumber-magnitude shell (``k = \sum_\kappa E(\kappa)``); as a `Phenomenology` *model*, the spectral density per unit wavenumber (``k = \int_0^\infty E(\kappa)\,\mathrm d\kappa``) | `energy_spectrum` (measured; the `GBGPeriodicFields` radial spectrum, halved) / `spectrum` (model density) |
| ``\langle\varphi^2\rangle`` | scalar variance | `scalar_variance` |
| ``\varepsilon_\varphi`` | scalar dissipation rate ``2\varkappa\langle\lvert\nabla\varphi\rvert^2\rangle`` | `scalar_dissipation` |

## Derived scales

Measured from the resolved state, or derived from it through a `FlowParameters` bundle and its helpers.

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``u'`` | root-mean-square velocity (one component), ``u' = \sqrt{2k/3}`` | `flow_parameters` |
| ``L_{11}`` | longitudinal (parallel) integral length scale, ``\tfrac{3\pi}{4}\int_0^\infty (E/\kappa)\,\mathrm d\kappa / \int_0^\infty E\,\mathrm d\kappa`` (the lateral is ``L_{22} = L_{11}/2``) | `integral_scale` |
| ``\eta`` | Kolmogorov (dissipation) microscale, ``(\nu^3/\varepsilon)^{1/4}`` | `kolmogorov_length` |
| ``\tau_\eta`` | Kolmogorov time, ``(\nu/\varepsilon)^{1/2}`` | `kolmogorov_time` |
| ``\mathrm{Re}_\lambda`` | Taylor-microscale Reynolds number, measured from the flow state | `taylor_reynolds` |
| ``\lambda`` | Taylor microscale, ``\sqrt{15 \nu u'^2/\varepsilon}`` | `taylor_microscale` |

## Numerics

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``N`` | grid points per side | `grid_points_per_axis` |
| ``L`` | box side (``\Omega = [0,L)^3``) | `side_length` |
| ``\Delta t`` | timestep | `dt` |
| ``C`` | advective-CFL ceiling, ``\Delta t = C \Delta x/\max_i\lvert u_i\rvert`` (the derivative-skewness isotropy constant wears the subscripted ``C_S``) | `recommended_cfl` |
| ``\kappa_{\max}`` | dealiased maximum wavenumber, ``\tfrac{2}{3}\cdot\tfrac{N}{2}\cdot\tfrac{2\pi}{L}`` for the default ``2/3`` rule (``\tfrac{\sqrt{2}}{3}N\cdot\tfrac{2\pi}{L}`` for `PhaseShift`; set by the `dealiasing` strategy) | `DealiasingStrategy` |
| ``A_i, B_i, d_i`` | the low-storage Runge–Kutta stage coefficients and node increments | `IFLowStorageRK3` |
| ``T`` | the real element type ([`Float32`](@extref Julia :jl:type:Core.Float32) / [`Float64`](@extref Julia :jl:type:Core.Float64)) | `element_type` |

## Forcing

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``A(\boldsymbol{\kappa})`` | per-mode linear forcing rate, folded into ``\mathcal{E}`` | `set_forcing_rate!` |
| ``\varepsilon_{\text{target}}`` | target energy-injection rate | `ConstantPower(target=…)` |
