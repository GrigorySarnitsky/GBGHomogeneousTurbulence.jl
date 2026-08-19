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
| Normalized inner product | ``\langle f, g \rangle`` | ``\frac{1}{\lvert\Omega\rvert}\int_\Omega f\cdot g\,\mathrm{d}\boldsymbol{x}``, the box average of the pointwise product. Parseval holds for it in this normalization, which is why the quadratic reductions (``k``, ``\varepsilon``, the variances) take a field in either representation and return the same number. |
| Spatial average | ``\langle \cdot \rangle`` | The box average ``\frac{1}{\lvert\Omega\rvert}\int_\Omega(\cdot)\,\mathrm{d}\boldsymbol{x}`` over the periodic domain ``\Omega`` — the single-realization estimate of the homogeneous ensemble average (exact only in the ergodic, infinite-box limit; at a finite box it retains the large-scale statistical fluctuation). |
| Spectral representation | ``\hat f`` | The field ``f`` in spectral (Fourier) representation, [`to_spectral`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.to_spectral). A field is one physical object; physical and spectral are two representations of it. |
| Wavenumber clash | ``\boldsymbol{\kappa}`` / ``\kappa`` / ``k`` | Kept distinct: **bold** ``\boldsymbol{\kappa}`` is the wavenumber *vector*, ``\kappa = \lvert\boldsymbol{\kappa}\rvert`` its *magnitude* (the spectrum coordinate), and italic scalar ``k`` is the *turbulent kinetic energy*.  |

## Physical variables


The **Code** column gives the name each symbol carries in the package.

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``\boldsymbol{u}`` | the incompressible velocity field, ``\nabla\cdot\boldsymbol{u} = 0`` | the velocity state |
| ``\boldsymbol{\omega}`` | the vorticity ``\nabla\times\boldsymbol{u}`` | [`vorticity_physical!`](@ref GBGIsotropicTurbulence.Observables.vorticity_physical!) |
| ``\varphi`` | the passive scalar (never ``\theta``) | the scalar state |
| ``p`` | the pressure (absorbed by the Leray–Helmholtz projection, never stored) | — |
| ``\boldsymbol{f}`` | a body forcing on the momentum equation | [`AbstractForcing`](@ref GBGIsotropicTurbulence.Forcing.AbstractForcing) |
| ``f_\varphi`` | a body forcing on the passive-scalar equation | [`AbstractForcing`](@ref GBGIsotropicTurbulence.Forcing.AbstractForcing) (via `scalar_forcing`) |
| ``\boldsymbol{x}``, ``t`` | position in the box ``\Omega``; time | — |
| ``\boldsymbol{X}(t)`` | the position of a tracer particle (capitalised, to keep it distinct from the Eulerian coordinate ``\boldsymbol{x}``) | [`particle_positions`](@ref) |
| ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` | the particle velocities — the velocity sampled at each tracer's position at the instant ``t_n`` between iterations | [`particle_velocities`](@ref) |
| ``M`` | the number of tracer particles | [`number_of_particles`](@ref) |

## Parameters

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``\nu`` | kinematic viscosity (sets the Reynolds number) | `conditions.viscosity` |
| ``\mathrm{Sc}`` | Schmidt number | `conditions.schmidt` |
| ``\varkappa`` | scalar diffusivity ``\nu/\mathrm{Sc}`` | `ν / schmidt` |
| ``\mathrm{Re}`` | Reynolds number, set through the viscosity on the box's order-one reference scales (the default initial condition seeds ``u' = 1``, and the large scales are of order the box side — the ``U`` and ``L`` of ``UL/\nu`` are units, not inputs; the measured value is ``\mathrm{Re}_\lambda``) | `1 / ν` (in units where ``u' = L = 1``; on the shipped defaults, where ``L = 2\pi``, the box-scale value is ``2\pi/\nu``) |

*(The scalar diffusivity ``\varkappa`` is a deliberately distinct glyph from the wavenumber
magnitude ``\kappa`` and the turbulent kinetic energy ``k``.)*

## Spectral representation and operators

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``\boldsymbol{\kappa}`` | wavenumber vector, components ``\kappa_a`` | [`FieldSpectralMultipliers`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.FieldSpectralMultipliers) |
| ``\kappa`` | wavenumber magnitude ``\lvert\boldsymbol{\kappa}\rvert`` (spectrum coordinate) | — |
| ``\lvert\boldsymbol{\kappa}\rvert^2`` | squared wavenumber; in spectral space ``-\nabla^{2}`` acts as multiplication by it | `domain.squared_wavenumber_kernel` |
| ``\mathcal F``, ``\mathcal F^{-1}`` | forward / inverse real transform | `to_spectral`, [`to_physical`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.to_physical) |
| ``\nabla\times``, ``\nabla\cdot`` | curl, divergence | [`curl`](@extref GBGPeriodicFields GBGPeriodicFields.DifferentialOperators.curl), [`divergence`](@extref GBGPeriodicFields GBGPeriodicFields.DifferentialOperators.divergence) |
| ``\mathbb{P}`` | the Leray–Helmholtz projection onto divergence-free fields | [`helmholtz_projection`](@extref GBGPeriodicFields GBGPeriodicFields.DifferentialOperators.helmholtz_projection) |
| ``\mathcal{E}(\boldsymbol{\kappa})`` | the diffusive integrating factor ``\exp\!\bigl((A(\boldsymbol{\kappa})-D\lvert\boldsymbol{\kappa}\rvert^2)\tau\bigr)`` over an interval ``\tau`` — a Runge–Kutta stage substep ``d_i\Delta t``, or the whole step ``\Delta t`` (``D`` the diffusivity — ``\nu`` for the velocity, ``\varkappa`` for the scalar; ``A(\boldsymbol{\kappa})`` the linear forcing rate) | [`velocity_integrating_factor`](@ref), [`scalar_integrating_factor`](@ref) |
| ``\star`` | periodic convolution (the dealias/band/envelope kernels) | [`convolve`](@extref GBGPeriodicFields GBGPeriodicFields.Convolution.convolve) |
| ``\widehat{\boldsymbol{N}}`` | a field's assembled explicit right-hand side — the dealiased nonlinear term plus any additive forcing source — in spectral representation | [`velocity_rhs!`](@ref), [`scalar_rhs!`](@ref) |

## Diagnostics

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``k`` | turbulent kinetic energy ``\tfrac{1}{2}\langle\lvert\boldsymbol{u}\rvert^2\rangle`` | [`kinetic_energy`](@ref GBGIsotropicTurbulence.Observables.kinetic_energy) |
| ``\varepsilon`` | mean dissipation rate ``\nu\langle\lvert\boldsymbol{\omega}\rvert^2\rangle`` | [`dissipation`](@ref GBGIsotropicTurbulence.Observables.dissipation) |
| ``E(\kappa)`` | the energy spectrum as a **density** per unit wavenumber, the `Phenomenology` model form: ``k = \int_0^\infty E(\kappa)\,\mathrm{d}\kappa`` (dimensions ``L^3T^{-2}``) | [`spectrum`](@ref GBGIsotropicTurbulence.Phenomenology.spectrum) |
| ``E_n`` | the **measured** spectrum: the energy in wavenumber-magnitude shell ``n`` — a set of Fourier modes one shell width ``\Delta\kappa = 2\pi/L`` thick — so ``k = \sum_n E_n`` (dimensions ``L^2T^{-2}``, a density times ``\Delta\kappa``) | [`energy_spectrum`](@ref GBGIsotropicTurbulence.Observables.energy_spectrum) (the `GBGPeriodicFields` radial spectrum, halved) |
| ``\langle\varphi^2\rangle`` | scalar variance | [`scalar_variance`](@ref GBGIsotropicTurbulence.Observables.scalar_variance) |
| ``\varepsilon_\varphi`` | scalar dissipation rate ``2\varkappa\langle\lvert\nabla\varphi\rvert^2\rangle`` | [`scalar_dissipation`](@ref GBGIsotropicTurbulence.Observables.scalar_dissipation) |

## Derived scales

Measured from the resolved state, or derived from it through a `FlowParameters` bundle and its helpers.

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``u'`` | root-mean-square velocity (one component), ``u' = \sqrt{2k/3}`` | [`flow_parameters`](@ref GBGIsotropicTurbulence.SimulationRun.flow_parameters) |
| ``L_{11}`` | longitudinal (parallel) integral length scale, ``\tfrac{3\pi}{4}\int_0^\infty (E/\kappa)\,\mathrm{d}\kappa / \int_0^\infty E\,\mathrm{d}\kappa`` (the lateral is ``L_{22} = L_{11}/2``) | [`integral_scale`](@ref GBGIsotropicTurbulence.Observables.integral_scale) |
| ``\eta`` | Kolmogorov (dissipation) microscale, ``(\nu^3/\varepsilon)^{1/4}`` | [`kolmogorov_length`](@ref GBGIsotropicTurbulence.Phenomenology.kolmogorov_length) |
| ``\tau_\eta`` | Kolmogorov time, ``(\nu/\varepsilon)^{1/2}`` | [`kolmogorov_time`](@ref GBGIsotropicTurbulence.Phenomenology.kolmogorov_time) |
| ``\mathrm{Re}_\lambda`` | Taylor-microscale Reynolds number, measured from the flow state | [`taylor_reynolds`](@ref GBGIsotropicTurbulence.Phenomenology.taylor_reynolds) |
| ``\lambda`` | Taylor microscale, ``\sqrt{15 \nu u'^2/\varepsilon}`` | [`taylor_microscale`](@ref GBGIsotropicTurbulence.Phenomenology.taylor_microscale) |

## Numerics

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``N`` | grid points per side | `grid_points_per_axis` |
| ``L`` | box side (``\Omega = [0,L)^3``) | `side_length` |
| ``\Delta t`` | timestep | `dt` |
| ``C_{\mathrm{CFL}}`` | advective-CFL (Courant–Friedrichs–Lewy) ceiling, ``\Delta t = C_{\mathrm{CFL}} \Delta x/\max_{\boldsymbol{x}}\lvert\boldsymbol{u}\rvert`` | [`recommended_cfl`](@ref GBGIsotropicTurbulence.Propagator.recommended_cfl) |
| ``\kappa_{\max}`` | dealiased maximum wavenumber, ``\tfrac{2}{3}\cdot\tfrac{N}{2}\cdot\tfrac{2\pi}{L}`` for the default ``2/3`` rule (``\tfrac{\sqrt{2}}{3}N\cdot\tfrac{2\pi}{L}`` for `PhaseShift`; set by the `dealiasing` strategy) | [`DealiasingStrategy`](@ref GBGIsotropicTurbulence.SimulationDomain.DealiasingStrategy) |
| ``A_i, B_i, d_i`` | the low-storage Runge–Kutta stage coefficients and node increments | [`IFLowStorageRK3`](@ref GBGIsotropicTurbulence.Propagator.IFLowStorageRK3) |
| ``y_{\mathrm{s}}`` | a scheme's imaginary-axis stability limit (``\sqrt{3}`` for `IFLowStorageRK3`; ``0`` for the imaginary-axis-unstable `IFRK2`) | [`recommended_cfl`](@ref GBGIsotropicTurbulence.Propagator.recommended_cfl) |
| ``T`` | the real element type ([`Float32`](@extref Julia :jl:type:Core.Float32) / [`Float64`](@extref Julia :jl:type:Core.Float64)) | `element_type` |

## Forcing

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``A(\boldsymbol{\kappa})`` | per-mode linear forcing rate, folded into ``\mathcal{E}`` | [`set_forcing_rate!`](@ref GBGIsotropicTurbulence.Forcing.set_forcing_rate!) |
| ``\varepsilon_{\mathrm{target}}`` | target energy-injection rate | `ConstantPower(injection_rate=…)` |

## Vocabulary

The page above fixes one symbol per physical concept. This section does the same for the package's
**operational** words — the ones that name how a run is organized rather than what it computes. Each
is used throughout the docstrings, and each means exactly this and nothing looser.

| Term | Meaning |
|:---|:---|
| **iteration** | one advance of the run, in this order: choose the timestep, [`step!`](@ref GBGIsotropicTurbulence.Propagator.step!) the fields, [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!) to close them, then advance any tracers and record their sample — the tracers come last because their second velocity sample is interpolated from the field the deposit just made current. Wider than a *step*, which is only the first half, and than a *stage*, which is one Runge–Kutta substep inside it. |
| **deposit** | to write an observable into the cache and mark the moment it belongs to. The closing deposit is the one that ends an iteration; nothing is ever written to the cache on a read. |
| **slot** | one storage place in the [`ObservablesCache`](@ref GBGIsotropicTurbulence.Cache.ObservablesCache) — an array or a number, together with the epoch its value belongs to. |
| **epoch** | a counter of *changes to the state*, one per dynamical factor (the fields, the tracer positions) — and, for a slot, the value that counter held when the slot was filled. A slot is readable exactly while the epoch it records still equals the counter it depends on. Not an iteration number: an announced out-of-band mutation advances an epoch without advancing the clock. |
| **register** | storage a component computes one value into and overwrites at the next, holding nothing a reader should trust in between. A cache slot doubles as its producer's register mid-iteration, which is why a cached field is meaningful only between iterations. |
| **front door** | the [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) constructor that builds every component from a few keywords, as against assembling the pieces yourself. |
| **observation** | the callback a run is driven by: it reads the run once per iteration and its return decides whether to continue. By extension the *occasion* — "computed at an observation" means computed in that callback, between iterations, from what the run already holds. It is never the cache, which is the storage the callback reads. |
| **resolved** | in `ResolvedFields` and `ResolvedGenerator`, *made concrete as one value*. The numerical sense — a scale the grid resolves, as in the resolution criterion ``\kappa_{\max}\eta`` — is the other reading, and the docs write it out in full wherever it is meant. |
