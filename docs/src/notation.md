# Notation

The symbols used throughout the docstrings and the design documents, with the code object each one
denotes. All mathematics is rendered LaTeX; a code identifier always appears in backticks and never
inside a math span. An operation family is listed once, by its allocating name; the in-place
sibling appends `!` (`curl` / `curl!`). This page is the single reference — a docstring introduces a symbol on first use
and need not repeat the convention.

The physical conventions are standard turbulence usage — see Pope (2000), *Turbulent Flows*; the field and
spectral conventions follow [`GBGPeriodicFields`](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl),
a direct dependency.

## Conventions

| Concept | Symbol | Convention |
|:---|:---|:---|
| Imaginary unit | ``\mathrm{i}`` | Upright, always — never bare italic ``i``, never ``\imath``. Writing it upright frees ``i`` for use as an index. |
| Indices | ``i, j, a, \dots`` | Indices are italic and taken in order. A repeated index within a term is summed over the three components ``1,2,3`` (Einstein convention). |
| Normalized inner product | ``\langle f, g \rangle`` | ``\frac{1}{\lvert\Omega\rvert}\int_\Omega f\cdot g\,\mathrm{d}\boldsymbol{x}``, the average over the periodic box ``\Omega`` of the pointwise product. Parseval holds for it in this normalization, which is why the quadratic reductions (``k``, ``\varepsilon``, the variances) take a field in either representation and return the same number. |
| Spatial average | ``\langle \cdot \rangle`` | The box average ``\frac{1}{\lvert\Omega\rvert}\int_\Omega(\cdot)\,\mathrm{d}\boldsymbol{x}`` over the periodic domain ``\Omega`` — the single-realization estimate of the homogeneous ensemble average (exact only in the ergodic, infinite-box limit; at a finite box it retains the large-scale statistical fluctuation). |
| Box units | ``\tilde{q}`` | A quantity ``q`` divided by its unit built from the box side ``L`` and the dissipation rate ``\varepsilon``: length ``L``, time ``(L^{2}/\varepsilon)^{1/3}``, velocity ``(\varepsilon L)^{1/3}``. So ``\tilde{k} = k/(\varepsilon L)^{2/3}`` and ``\tilde{\nu} = \nu/(\varepsilon^{1/3}L^{4/3})``. The tilde means this and nothing else; an average is never a tilde (see the box mean below). |
| Box mean | ``\langle \cdot \rangle_l`` | The average over a cube of side ``l`` centred at each point, so ``\langle\boldsymbol{u}\rangle_l`` is a field; the unindexed ``\langle\cdot\rangle`` is the average over the whole box. Averages and filters are always brackets with an index, never an overbar or a tilde. |
| Spectral representation | ``\hat f`` | The field ``f`` in spectral (Fourier) representation, [`to_spectral`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.to_spectral). A field is one physical object; physical and spectral are two representations of it. |
| Wavenumber clash | ``\boldsymbol{\kappa}`` / ``\kappa`` / ``k`` | Kept distinct: bold ``\boldsymbol{\kappa}`` is the wavenumber *vector*, ``\kappa = \lvert\boldsymbol{\kappa}\rvert`` its *magnitude* (the spectrum coordinate), and italic scalar ``k`` is the *turbulent kinetic energy*.  |

## Physical variables


The Code column gives the name each symbol carries in the package.

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``\boldsymbol{u}`` | the incompressible velocity field, ``\nabla\cdot\boldsymbol{u} = 0`` | `velocity_spectral`, a field of [`ResolvedFields`](@ref GBGHomogeneousTurbulence.State.ResolvedFields), in spectral representation |
| ``\boldsymbol{\omega}`` | the vorticity ``\nabla\times\boldsymbol{u}`` | [`vorticity_physical`](@ref GBGHomogeneousTurbulence.Cache.vorticity_physical) (the field held in the [`ObservablesCache`](@ref GBGHomogeneousTurbulence.Cache.ObservablesCache); [`vorticity_physical!`](@ref GBGHomogeneousTurbulence.Observables.vorticity_physical!) recovers it) |
| ``\boldsymbol{\omega}\times\boldsymbol{u}`` | the Lamb vector — vorticity first, the literature's sign, so that ``(\boldsymbol{u}\cdot\nabla)\boldsymbol{u} = \nabla\bigl(\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}\bigr) + \boldsymbol{\omega}\times\boldsymbol{u}``; the rotational form's right-hand side carries its negation, ``\boldsymbol{u}\times\boldsymbol{\omega}``, which is the product the solver forms | never stored: formed in place over the vorticity's array by [`velocity_rhs!`](@ref GBGHomogeneousTurbulence.Generator.velocity_rhs!) |
| ``\varphi`` | the passive scalar (never ``\theta``) | `scalar_spectral`, likewise |
| ``p`` | the pressure (absorbed by the Leray–Helmholtz projection, never stored) | — |
| ``\boldsymbol{f}`` | a body forcing on the momentum equation | [`AbstractForcing`](@ref GBGHomogeneousTurbulence.Forcing.AbstractForcing) |
| ``f_\varphi`` | a body forcing on the passive-scalar equation | [`AbstractForcing`](@ref GBGHomogeneousTurbulence.Forcing.AbstractForcing) (the `scalar_forcing` keyword of [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation)) |
| ``\boldsymbol{x}``, ``t`` | position in the box ``\Omega``; time | — |
| ``\boldsymbol{X}(t)`` | the position of a tracer particle (capitalised, to keep it distinct from the Eulerian coordinate ``\boldsymbol{x}``) | `positions`, a field of [`Tracers`](@ref GBGHomogeneousTurbulence.Particles.Tracers) |
| ``\boldsymbol{u}(t_n, \boldsymbol{X}(t_n))`` | the velocity at the particles — the flow velocity sampled at each tracer's position at the run's current time ``t_n``, between [iterations](#Vocabulary) | [`velocity_at_particles`](@ref GBGHomogeneousTurbulence.Cache.velocity_at_particles) |
| ``M`` | the number of tracer particles | `npoints` of those `positions` |

## Parameters

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``\nu`` | kinematic viscosity (sets the Reynolds number) | `viscosity`, a field of [`FlowConditions`](@ref GBGHomogeneousTurbulence.Generator.FlowConditions) |
| ``\mathrm{Sc}`` | Schmidt number | `schmidt`, likewise |
| ``\varkappa`` | scalar diffusivity ``\nu/\mathrm{Sc}`` | `ν / schmidt` |
| ``\mathrm{Re}`` | a Reynolds number, a velocity times a length over ``\nu``. A run takes none as an input: it is set through ``\nu``, and measured as ``\mathrm{Re}_{\mathrm{box}}`` or ``\mathrm{Re}_\lambda`` below | — |

*(The scalar diffusivity ``\varkappa`` is a deliberately distinct glyph from the wavenumber
magnitude ``\kappa`` and the turbulent kinetic energy ``k``.)*

## Spectral representation and operators

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``\boldsymbol{\kappa}`` | wavenumber vector, components ``\kappa_a`` | [`FieldSpectralMultipliers`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.FieldSpectralMultipliers) |
| ``\kappa`` | wavenumber magnitude ``\lvert\boldsymbol{\kappa}\rvert`` (spectrum coordinate) | — |
| ``\lvert\boldsymbol{\kappa}\rvert^2`` | squared wavenumber; in spectral space ``-\nabla^{2}`` acts as multiplication by it | `squared_wavenumber_kernel`, a field of [`FixedDomain`](@ref GBGHomogeneousTurbulence.SimulationDomain.FixedDomain) |
| ``\mathcal{F}``, ``\mathcal{F}^{-1}`` | forward / inverse real transform | `to_spectral`, [`to_physical`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.to_physical) |
| ``\nabla\times``, ``\nabla\cdot`` | curl, divergence | [`curl`](@extref GBGPeriodicFields GBGPeriodicFields.DifferentialOperators.curl), [`divergence`](@extref GBGPeriodicFields GBGPeriodicFields.DifferentialOperators.divergence) |
| ``\mathbb{P}`` | the Leray–Helmholtz projection onto divergence-free fields | [`helmholtz_projection`](@extref GBGPeriodicFields GBGPeriodicFields.DifferentialOperators.helmholtz_projection) |
| ``\mathcal{E}(\boldsymbol{\kappa})`` | the diffusive integrating factor ``\exp\bigl((A(\boldsymbol{\kappa})-D\lvert\boldsymbol{\kappa}\rvert^2)\delta t\bigr)`` over an interval ``\delta t`` — a Runge–Kutta stage substep ``d_i\Delta t``, with ``d_i`` the stage's node increment, or the whole timestep ``\Delta t`` (``D`` the diffusivity — ``\nu`` for the velocity, ``\varkappa`` for the scalar; ``A(\boldsymbol{\kappa})`` the linear forcing rate) | [`velocity_integrating_factor`](@ref GBGHomogeneousTurbulence.Generator.velocity_integrating_factor), [`scalar_integrating_factor`](@ref GBGHomogeneousTurbulence.Generator.scalar_integrating_factor) |
| ``\star`` | periodic convolution (the dealias/band/envelope kernels) | [`convolve`](@extref GBGPeriodicFields GBGPeriodicFields.Convolution.convolve) |
| ``\widehat{N}`` (``\widehat{\boldsymbol{N}}`` for the velocity) | a field's assembled explicit right-hand side — the dealiased nonlinear term plus any additive forcing source — in spectral representation | [`velocity_rhs!`](@ref GBGHomogeneousTurbulence.Generator.velocity_rhs!), [`scalar_rhs!`](@ref GBGHomogeneousTurbulence.Generator.scalar_rhs!) |

## Diagnostics

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``k`` | turbulent kinetic energy ``\tfrac{1}{2}\langle\lvert\boldsymbol{u}\rvert^2\rangle`` | [`kinetic_energy`](@ref GBGHomogeneousTurbulence.Observables.kinetic_energy) |
| ``\varepsilon`` | mean dissipation rate ``\nu\langle\lvert\boldsymbol{\omega}\rvert^2\rangle`` | [`dissipation`](@ref GBGHomogeneousTurbulence.Observables.dissipation) |
| ``E(\kappa)`` | the energy spectrum as a *density* per unit wavenumber: ``k = \int_0^\infty E(\kappa)\,\mathrm{d}\kappa`` (dimensions ``L^3T^{-2}``) — the form the reference laws are stated in, and the one the measured spectrum below estimates | — |
| ``E(\kappa_n)`` | the measured spectral density at shell ``n``, centred on the wavenumber magnitude ``\kappa_n``: the shell's energy over the shell width ``\Delta\kappa = 2\pi/L``, so ``k = \sum_n E(\kappa_n) \Delta\kappa`` — the same kind of object as a model ``E(\kappa)``, directly comparable | [`energy_spectrum`](@ref GBGHomogeneousTurbulence.Observables.energy_spectrum) (the `GBGPeriodicFields` radial spectrum, halved, over ``\Delta\kappa``) |
| ``l`` | a box side: the cube whose own mean is removed in ``k(l)`` and ``\varepsilon(l)``, from the grid spacing up to the domain side ``L`` | [`kinetic_energy_and_dissipation_below_scale`](@ref GBGHomogeneousTurbulence.Observables.kinetic_energy_and_dissipation_below_scale) (its `scales`) |
| ``W_l(\boldsymbol{\kappa})`` | the transfer function of the box mean of side ``l``, ``\prod_a \operatorname{sinc}(\kappa_a l/2)`` — a function of the wavenumber *vector*, not radial | `tophat_window` (`GBGPeriodicFields`) |
| ``k(l)``, ``\varepsilon(l)`` | the kinetic energy and the dissipation held in scales below ``l``: what a box of side ``l`` measures once its own mean velocity (for ``k``) or vorticity (for ``\varepsilon``) is removed, averaged over its positions; ``k(L) = k``, ``\varepsilon(L) = \varepsilon`` | [`kinetic_energy_and_dissipation_below_scale`](@ref GBGHomogeneousTurbulence.Observables.kinetic_energy_and_dissipation_below_scale) |
| ``\langle\varphi^2\rangle`` | scalar variance | [`scalar_variance`](@ref GBGHomogeneousTurbulence.Observables.scalar_variance) |
| ``\varepsilon_\varphi`` | scalar dissipation rate ``2\varkappa\langle\lvert\nabla\varphi\rvert^2\rangle`` | [`scalar_dissipation`](@ref GBGHomogeneousTurbulence.Observables.scalar_dissipation) |
| ``S`` | the velocity-derivative skewness — the developed-cascade marker, ``\approx -0.5`` for developed turbulence | [`derivative_skewness`](@ref GBGHomogeneousTurbulence.Observables.derivative_skewness) |

## Derived scales

These scales are computed from measured scalars. A row whose Code column is a dash is a quantity the
pages use in prose, with no function of its own.

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``u'`` | root-mean-square velocity (one component), ``u' = \sqrt{2k/3}`` | — |
| ``L_{11}`` | longitudinal (parallel) integral length scale, ``\tfrac{3\pi}{4}\int_0^\infty (E/\kappa)\,\mathrm{d}\kappa / \int_0^\infty E\,\mathrm{d}\kappa`` (the transverse is ``L_{22} = L_{11}/2``) | [`integral_length`](@ref GBGHomogeneousTurbulence.Observables.integral_length) |
| ``\eta`` | Kolmogorov (dissipation) microscale, ``(\nu^3/\varepsilon)^{1/4}`` | [`kolmogorov_length`](@ref GBGHomogeneousTurbulence.Observables.kolmogorov_length) |
| ``\tau_\eta`` | Kolmogorov time, ``(\nu/\varepsilon)^{1/2}``, the turnover time of an eddy of size ``\eta`` | [`kolmogorov_time`](@ref GBGHomogeneousTurbulence.Observables.kolmogorov_time) |
| ``u_\eta`` | Kolmogorov velocity, ``(\varepsilon\nu)^{1/4}``, so that ``\eta = u_\eta\tau_\eta`` | [`kolmogorov_velocity`](@ref GBGHomogeneousTurbulence.Observables.kolmogorov_velocity) |
| ``\tilde{k}`` | the kinetic energy in box units, ``k/(\varepsilon L)^{2/3}``: its ``3/2`` power is the large-eddy length ``k^{3/2}/\varepsilon`` as a fraction of the box side ``L``. A run predicts its stationary state with it, from provisional values per forcing band (the shells a forcing acts on) | [`kinetic_energy_in_box_units`](@ref GBGHomogeneousTurbulence.Forcing.kinetic_energy_in_box_units) |
| ``\mathrm{Re}_{\mathrm{box}}`` | the box Reynolds number ``\varepsilon^{1/3}L^{4/3}/\nu = 1/\tilde{\nu}``. A run whose ``\nu`` is set by ``\kappa_{\max}\eta``, with ``\kappa_{\max}`` the resolved-band edge of *Numerics* below, has ``\mathrm{Re}_{\mathrm{box}} = (L/\eta)^{4/3}`` | [`reynolds_box`](@ref GBGHomogeneousTurbulence.Observables.reynolds_box) |
| ``G`` | [`VarianceController`](@ref GBGHomogeneousTurbulence.Forcing.VarianceController)'s dimensionless gain | — |
| ``\tau`` | eddy-turnover time, ``k/\varepsilon`` — the time scale of the energy-containing eddies, and the unit a run's length is counted in; ``t_\ell`` below is the same scale, normalized differently. Two unrelated quantities wear this glyph: in the integrating-factor row of *Spectral representation and operators* above, ``\tau`` is a Runge–Kutta stage substep, the argument of the integrating-factor functions | [`kinetic_energy_and_dissipation`](@ref GBGHomogeneousTurbulence.Observables.kinetic_energy_and_dissipation) |
| ``t_\ell`` | large-eddy turnover time, ``2k/(3\varepsilon)`` — Bassenne et al.'s convention, the [`VarianceController`](@ref GBGHomogeneousTurbulence.Forcing.VarianceController) default relaxation time; ``t_\ell = u'^{2}/\varepsilon = \tfrac{2}{3}\tau`` | [`VarianceController`](@ref GBGHomogeneousTurbulence.Forcing.VarianceController) |
| ``\mathrm{Re}_\lambda`` | Taylor-microscale Reynolds number ``u'\lambda/\nu = \sqrt{20/3} k/\sqrt{\varepsilon\nu}``, measured from the flow state | [`reynolds_taylor`](@ref GBGHomogeneousTurbulence.Observables.reynolds_taylor) |
| ``\lambda`` | Taylor microscale, ``\sqrt{15 \nu u'^2/\varepsilon} = \sqrt{10\nu k/\varepsilon}`` | [`taylor_length`](@ref GBGHomogeneousTurbulence.Observables.taylor_length) |

## Numerics

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``N`` | grid points per side | `grid_points_per_axis`, a [`FixedDomain`](@ref GBGHomogeneousTurbulence.SimulationDomain.FixedDomain) keyword |
| ``L`` | box side (``\Omega = [0,L)^3``) | `side_length`, likewise |
| ``\Delta t`` | timestep | `dt`, an [`advance!`](@ref GBGHomogeneousTurbulence.SimulationRun.advance!) keyword |
| ``C_{\mathrm{CFL}}`` | advective-CFL (Courant–Friedrichs–Lewy) ceiling, ``\Delta t = C_{\mathrm{CFL}} \Delta x/\max_{\boldsymbol{x}}\lvert\boldsymbol{u}\rvert``, with ``\Delta x`` the grid spacing | [`recommended_cfl`](@ref GBGHomogeneousTurbulence.Propagator.recommended_cfl) |
| ``\kappa_{\mathrm{Ny}}`` | the grid Nyquist wavenumber ``\tfrac{N}{2}\tfrac{2\pi}{L}`` — the highest the grid represents, before dealiasing | — |
| ``\kappa_p`` | the envelope wavenumber of the default random initial condition (the shell-summed spectrum peaks at ``\kappa_p/\sqrt{2}``) | `envelope_wavenumber`, a [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) keyword |
| ``\kappa_{\max}^{\mathrm{ret}}`` | retained-band edge ``f_{\mathrm{ret}}\kappa_{\mathrm{Ny}}``, ``f_{\mathrm{ret}}`` the retained fraction (Lambert, Reneuve & Augier's (2026) ``C_t``, Fluidsim's `coef_dealiasing`) — the highest wavenumber the `dealiasing` strategy keeps energetic (``\tfrac{2}{3}\cdot\tfrac{N}{2}\cdot\tfrac{2\pi}{L}`` for the default ``2/3`` rule, the Nyquist for [`HouLi`](@ref GBGHomogeneousTurbulence.SimulationDomain.HouLi), ``\tfrac{\sqrt{2}}{3}N\cdot\tfrac{2\pi}{L}`` for [`PhaseShift`](@ref GBGHomogeneousTurbulence.SimulationDomain.PhaseShift)); prices the advective-CFL step | [`max_retained_wavenumber`](@ref) |
| ``\kappa_{\max}`` | resolved-band edge ``f_{\mathrm{res}}\kappa_{\mathrm{Ny}}``, with ``f_{\mathrm{res}}`` the resolved fraction — the highest wavenumber whose dynamics is genuine Navier–Stokes, the ``\kappa_{\max}`` of the resolution criterion ``\kappa_{\max}\eta``; equals the retained edge for the sharp-cutoff strategies, ``\tfrac{4}{5}`` of Nyquist for `HouLi` | [`max_resolved_wavenumber`](@ref) |
| ``A_i, B_i, d_i`` | the low-storage Runge–Kutta stage coefficients and node increments | [`IFLowStorageRK3`](@ref GBGHomogeneousTurbulence.Propagator.IFLowStorageRK3) |
| ``y_{\mathrm{s}}`` | a scheme's imaginary-axis stability limit (``\sqrt{3}`` for `IFLowStorageRK3` and [`IFSSPRK3`](@ref GBGHomogeneousTurbulence.Propagator.IFSSPRK3); ``\approx 3.34`` for [`IFLowStorageRK4`](@ref GBGHomogeneousTurbulence.Propagator.IFLowStorageRK4); ``0`` for the imaginary-axis-unstable [`IFHeun`](@ref GBGHomogeneousTurbulence.Propagator.IFHeun)) | [`recommended_cfl`](@ref GBGHomogeneousTurbulence.Propagator.recommended_cfl) |
| ``T`` | the real element type ([`Float32`](@extref Julia :jl:type:Core.Float32) / [`Float64`](@extref Julia :jl:type:Core.Float64)) | the `element_type` keyword of `Simulation` |

## Forcing

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``A(\boldsymbol{\kappa})`` | per-mode linear forcing rate, folded into ``\mathcal{E}`` | [`steady_linear_rate`](@ref GBGHomogeneousTurbulence.Forcing.steady_linear_rate) |
| ``\varepsilon_{\mathrm{target}}`` | the injection rate a [`ConstantPower`](@ref GBGHomogeneousTurbulence.Forcing.ConstantPower) holds: energy for the velocity, scalar variance for the scalar | `ConstantPower(injection_rate=…)` |
| ``\sigma^{2}`` | the stationary mean square of the term a stochastic forcing ADDS — an acceleration for the velocity, a rate of change of ``\varphi`` for the scalar. It is not the variance of the field, which a `VarianceController` holds | `StochasticOU(forcing_variance=…)` |
| ``k_{\mathrm{band}}`` | the energy in the forced band, ``\tfrac{1}{2}\sum_{\text{band}} \lvert\hat{\boldsymbol{u}}\rvert^{2}`` over the shells `lowest_shell` to `highest_shell`: the part of ``k`` the forcing acts on, and for a scalar forcing the band's part of ``\langle\varphi^{2}\rangle``. Its share of the whole is the band energy fraction ``k_{\mathrm{band}}/k`` | [`band_energy_fraction`](@ref GBGHomogeneousTurbulence.Forcing.band_energy_fraction) |
| ``T_L`` | the correlation time of that term: each forced mode's amplitude decays by ``e^{-\Delta t/T_L}`` per step. Short against the eddy-turnover time ``\tau``, the mean injection is close to ``\sigma^{2} T_L`` | `StochasticOU(correlation_time=…)` |

## Vocabulary

The page above fixes one symbol per physical concept. This section does the same for the package's
operational words — the ones that name how a run is organized rather than what it computes. Each
is used throughout the docstrings, and each means exactly this and nothing looser.

| Term | Meaning |
|:---|:---|
| **iteration** | one advance of the run, in this order: choose the timestep, [`step!`](@ref GBGHomogeneousTurbulence.Propagator.step!) the fields, [`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!) to close them, then advance any tracers and record their sample — the tracers come last because their second velocity sample is interpolated from the field the deposit just made current. An iteration is wider than a *step*, which is only the first half, and than a *stage*, which is one Runge–Kutta substep inside it. |
| **deposit** | to write an observable into the cache and mark the moment it belongs to, in one act — the fields and the tracer positions each advance separately, and each advance is closed by its own [`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!) form, the field form after the step and the particle form after the tracer push, inside the same iteration. Nothing is ever written to the cache on a read. |
| **slot** | one storage place in the [`ObservablesCache`](@ref GBGHomogeneousTurbulence.Cache.ObservablesCache) — an array or a number, together with the epoch its value belongs to. |
| **epoch** | a counter of *changes to the state*, one per dynamical factor (the fields, the tracer positions) — and, for a slot, the value that counter held when the slot was filled. A slot is readable exactly while the epoch it records still equals the counter it depends on. Not an iteration number: a change to the state made outside a step and announced through [`fields_modified!`](@ref GBGHomogeneousTurbulence.Cache.fields_modified!) advances an epoch without advancing the clock. |
| **register** | storage a component computes one value into and overwrites at the next use, holding nothing a reader should trust in between. A cache slot doubles as its producer's register mid-iteration, which is why a cached field is meaningful only between iterations. |
| **scratch** | working storage a component owns for its intermediate results — a register, or a named bundle of them (the generator's assembly scratch, a scheme's [`IntegratorBuffers`](@ref GBGHomogeneousTurbulence.Propagator.IntegratorBuffers)). |
| **push** | one advance of the tracer positions — the particle half of an iteration, performed by [`advect!`](@ref GBGHomogeneousTurbulence.Particles.advect!). |
| **front door** | the former name for what current docs call the domain-building [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) constructor: the form that builds every component from a few keywords, as against handing it a pre-built domain. In a wider sense it also names `SimulationRun`, the layer a user enters the package through. |
| **observation** | the callback a run is driven by: it reads the run once at the start and once after every iteration — ``n+1`` readings over a run of ``n`` iterations — and its return decides whether to continue. By extension the *occasion* — "computed at an observation" means computed in that callback, between iterations, from what the run already holds. |
| **holder** | in the test suite's audit of costs against their lower bounds: the named owner of a gap between an achieved cost and its floor — every residual distance must carry one, and closing the gap retires it in the same commit. |
| **ledger** | a frozen table of measured costs (memory, transforms, passes, synchronizations) the test suite holds the code to; a deliberate change re-freezes it consciously, citing its decision. |
| **floor** | the physical lower bound a ledger cell is held against — what the cost *could* be, as opposed to what it *is*. |
| **chart** | a physical-representation view of the state as held in spectral representation — the velocity, vorticity or scalar recovered from it. The cache's field slots are the run's charts; the *chart map* is the recovery itself. |
| **resolved** | in `ResolvedFields` and [`ResolvedGenerator`](@ref GBGHomogeneousTurbulence.Generator.ResolvedGenerator), the Mori–Zwanzig sense: the fully *resolved* dynamics, as opposed to a *filtered* one — the eventual LES sibling would be a `FilteredGenerator`. The numerical sense — a scale the grid resolves, as in the resolution criterion ``\kappa_{\max}\eta`` — is a different reading, and the docs write it out in full wherever it is meant. |
