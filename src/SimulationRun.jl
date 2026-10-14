# SimulationRun — the ergonomic run layer. A `Simulation` bundles the domain, buffers, the
# generator (the equations of motion with their conditions and assembly scratch), the scheme, the
# spectral state (û, φ̂), the observables cache, and any tracers;
# `advance!`/`run!`/`warmup!` own the time loop (CFL-adaptive, or fixed-step via `dt`). It holds no physics or numerics of its
# own — it wires the pieces of SimulationDomain/State/Generator/Observables/Forcing/Propagator/Particles
# so a case is a few lines to set up and run, warm-up included, while every piece stays reachable for a
# hand-run loop.
#
# The observables cache is deposit-driven (no recompute anywhere): `advance!` runs `step!`, then the
# closing `deposit!` recovers the iteration's observables into the cache at the new epoch, and the deposit-
# completeness check closes the iteration. The timestep choice reads the cached maximum speed — scalar
# arithmetic, no grid pass. The tracer advance is Heun on the two endpoint velocities: v₁ is the
# velocity sample the PREVIOUS closing deposit left (read checked), v₂ interpolates the just-deposited
# u(tₙ₊₁) at the predictor positions, and the new sample is recorded at the new positions from the
# same field, completing the iteration's deposits; only M-sized point values are held, never a second field copy.

"""
    SimulationRun

The run layer:

- [`Simulation`](@ref) — everything the next iteration needs, in one value: the domain, the
  fields at the current instant, the observables cache, the equations of motion with their
  forcing, the integration schemes with their scratch, any tracers, and the clock — built with
  defaults from a few numbers. It holds the present instant — plus the one bounded look-back a
  multistep particle scheme needs, the cache's Lagrangian sample history of earlier tracer
  velocities — and past instants exist only in what an observation recorded.
- [`PassiveScalar`](@ref) — the passive scalar a run carries, with its Schmidt number, variance
  and forcing, as `Simulation`'s `scalar` setting.
- [`predicted_stationary_state`](@ref) — the stationary state a forced run is set up for.
- [`advance!`](@ref), [`run!`](@ref) — advance one iteration; observe and advance until the
  callback stops the run (the callback *is* the observation — the function the loop calls to read the run each
  iteration — and its return decides continuation).
- [`StationarityCriterion`](@ref), [`warmup!`](@ref) — the packaged spin-up-to-stationarity
  observation, and its one-line shorthand.
- [`current_time`](@ref), [`current_step`](@ref) — the elapsed time and step count;
  [`every_steps`](@ref), [`every_time`](@ref) — the cadence predicates a callback acts
  periodically on.
- [`flow_parameters`](@ref) — the run's measured flow state as a `Phenomenology` `FlowParameters`.
- [`write_simulation`](@ref) / [`read_simulation`](@ref) — checkpoint and restore: the restartable
  run as one self-describing HDF5 group (available once `HDF5` is loaded).

Read a run's state through `sim.state` and the observables each iteration
[deposits](@ref GBGHomogeneousTurbulence.Propagator.deposit!) through `sim.cache`, with the
observables and cache accessors that own them; the run layer adds no forwarding methods.
"""
module SimulationRun

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, new_vector_field_spectral, new_scalar_field_spectral, new_vector_field_physical,
                          DealiasingStrategy, TwoThirds, max_resolved_wavenumber, _real_type
using ..State: ResolvedFields, random_solenoidal_velocity_spectral!, random_scalar_spectral!,
                  DEFAULT_ENVELOPE_WAVENUMBER
import ..Cache: particles_modified!, fields_modified!
using ..Cache: ObservablesCache, check_deposits,
               advance_fields_epoch!,
               velocity_physical, max_speed, velocity_at_particles
using ..Observables: kinetic_energy, dissipation, kinetic_energy_and_dissipation, scalar_variance,
                     scalar_dissipation, energy_spectrum, integral_scale, derivative_skewness,
                     reynolds_box, reynolds_taylor
using ..Forcing: AbstractForcing, DeferredForcing, NoForcing, ConstantPower, VarianceRescaling,
                 VarianceController, StochasticOU, StochasticOUState, initial_forcing_state,
                 kinetic_energy_in_box_units, band_energy_fraction, _uncovered_reason, _stated_state,
                 _takes_design
using ..Generator: FlowConditions, ResolvedGenerator, scalar_diffusivity
using ..Propagator: AbstractIntegrator, IntegratorBuffers, allocate_buffers, step!,
                    recommended_cfl, IFLowStorageRK3
import ..Propagator: deposit!
using ..Particles: Tracers, AbstractParticleIntegrator, Heun, advect!,
                   restart!, history_depth, ParticleTraversal
import ..Particles: rebuild_traversal!
using ..Phenomenology: FlowParameters, taylor_reynolds, kolmogorov_length
using ..Phenomenology.Spectra: EnergySpectrum, spectrum

export Simulation, advance!, run!, warmup!, StationarityCriterion,
       current_time, current_step, flow_parameters, every_steps, every_time,
       predicted_stationary_state


mutable struct Clock
  time::Float64
  step::Int
end


"""
    PassiveScalar(; schmidt = 1.0, variance = 1.0, forcing = NoForcing())

The passive scalar ``\\varphi`` a run carries, given as the `scalar` setting of
[`Simulation`](@ref): the run then advects a mean-zero scalar beside the velocity. A run built
with `scalar = nothing` carries none, and no scalar setting can be given to it.

# Arguments
- `schmidt = 1.0` — the Schmidt number ``\\mathrm{Sc}`` (scalar diffusivity
  ``\\varkappa = \\nu/\\mathrm{Sc}``). **The run's resolution criterion covers the velocity, not the
  scalar**, whose cutoff at ``\\mathrm{Sc} > 1`` is the finer Batchelor scale
  ``\\eta_B = \\eta/\\sqrt{\\mathrm{Sc}}`` — under-resolved by ``\\sqrt{\\mathrm{Sc}}`` on the same
  grid, with [`scalar_dissipation`](@ref GBGHomogeneousTurbulence.Observables.scalar_dissipation)
  then measuring a truncated field. The package targets ``\\mathrm{Sc} = O(1)``, with no
  Batchelor-range machinery. `Simulation` **warns** when the run's ``\\kappa_{\\max}\\eta_B`` falls
  below the ``1.5`` well-resolved floor — in either viscosity mode, since the check reads the
  resolved ``\\nu`` however it was obtained — a warning, not an error, so a deliberately
  under-resolved scalar stays reachable but not silent; the remedy is `κ_max_η` raised by
  ``\\sqrt{\\mathrm{Sc}}``, or `viscosity` set by hand.
- `variance = 1.0` — the scalar variance ``\\langle\\varphi^{2}\\rangle``: the value the scalar is
  seeded at, and the target a `forcing` holding the whole field's variance takes when its own is
  left out — a [`VarianceController`](@ref GBGHomogeneousTurbulence.Forcing.VarianceController)
  or a `VarianceRescaling(over = :total)` — as the velocity's `kinetic_energy` fills its forcing
  (see [`DeferredForcing`](@ref GBGHomogeneousTurbulence.Forcing.DeferredForcing)). An adopted
  `state` keeps the variance it holds.
- `forcing = NoForcing()` — the scalar's forcing, an [`AbstractForcing`](@ref) or a
  `DeferredForcing`; the velocity and the scalar are forced independently. No scalar stationary
  state is modelled, so a forcing needing one — a `VarianceRescaling(over = :band)` target, a
  `Linear` rate, a `StochasticOU` variance — states it. A deferred `StochasticOU` takes the
  flow's box time for a correlation time in box units.

# Fields
- `schmidt`, `variance`, `forcing` — the settings above.
"""
struct PassiveScalar{F}
  schmidt::Float64
  variance::Float64
  forcing::F
end

function PassiveScalar(; schmidt::Real = 1.0, variance::Real = 1.0, forcing = NoForcing())
  # Both are checked where they are named: the diffusivity is ν/Sc, and the seeder scales the draw
  # by √(variance/current), so a bad value would otherwise surface as a DomainError far downstream.
  schmidt > 0 ||
    throw(ArgumentError("`schmidt` must be positive, got $schmidt: the scalar diffusivity is ν/Sc"))
  variance >= 0 ||
    throw(ArgumentError("`variance` must be non-negative, got $variance: it is ⟨φ²⟩"))
  return PassiveScalar(Float64(schmidt), Float64(variance), forcing)
end

# Display (the convention is stated once, at `SimulationDomain`'s display section): the
# round-tripping constructor call, the forcing through its own display.
Base.show(io::IO, scalar::PassiveScalar) =
  print(io, "PassiveScalar(schmidt = ", scalar.schmidt, ", variance = ", scalar.variance,
        ", forcing = ", scalar.forcing, ")")


"""
    Simulation(; grid_points_per_axis, κ_max_η = nothing, kinetic_energy = nothing,
                 dissipation = nothing, side_length = 2π, dealiasing = TwoThirds(),
                 element_type = Float64, array_family = Array, kwargs...)
    Simulation(domain; κ_max_η = nothing, kinetic_energy = nothing, dissipation = nothing,
               kwargs...)

A `Simulation` bundles everything the next iteration needs: the [`FixedDomain`](@ref), the [`IntegratorBuffers`](@ref), the
[`ResolvedGenerator`](@ref) (the equations of motion, carrying the [`FlowConditions`](@ref) and the
assembly scratch), the chosen field integration scheme, the [`ResolvedFields`](@ref) state (the velocity
``\\hat{\\boldsymbol{u}}`` and passive scalar ``\\hat\\varphi`` in spectral representation), the
[`ObservablesCache`](@ref) holding what the last iteration deposited, any [`Tracers`](@ref), and a
clock.

The two forms differ only in where the `FixedDomain` comes from. The first is
**domain-building**: from `grid_points_per_axis` and `side_length` it builds the domain and every
piece above it, seeds a divergence-free velocity (and, given a `scalar`, a mean-zero scalar
``\\varphi``), and returns a `Simulation` at ``t = 0``. The second is
**domain-taking**: the same assembly on a `FixedDomain` you built yourself.

Advance it with [`advance!`](@ref) / [`run!`](@ref) / [`warmup!`](@ref). Read its measured state by
applying the observables to `sim.state` (e.g. `kinetic_energy(sim.state.velocity_spectral)`) or
through the cache's deposited observables (`velocity_physical(sim.cache)`); summarize it with
[`flow_parameters`](@ref), and track its progress with [`current_time`](@ref) /
[`current_step`](@ref).

# Setting the Reynolds number

By default the run is **forced and stationary**, set up for the stationary state it is predicted to
settle in: the kinetic energy ``k`` and the dissipation rate ``\\varepsilon``.

State that state **once** — by `kinetic_energy`, by `dissipation`, or by the target of a velocity
forcing that holds one of the two — and the other member is predicted; stating it twice is an
`ArgumentError`, and stating nothing means ``k = 1.5``. The prediction is
[`predicted_stationary_state`](@ref)'s. It goes through the kinetic energy in box units (lengths
in the box side ``L``, velocities in ``(\\varepsilon L)^{1/3}``),
``\\tilde{k} = k/(\\varepsilon L)^{2/3}``, of the velocity forcing
([`kinetic_energy_in_box_units`](@ref GBGHomogeneousTurbulence.Forcing.kinetic_energy_in_box_units)),
with ``L`` the box side, and the share of the energy in the forced band, the shells the forcing acts on
([`band_energy_fraction`](@ref GBGHomogeneousTurbulence.Forcing.band_energy_fraction)).

A velocity forcing whose strength is left out takes it from that state (see
[`DeferredForcing`](@ref GBGHomogeneousTurbulence.Forcing.DeferredForcing)). The default,
[`ConstantPower`](@ref GBGHomogeneousTurbulence.Forcing.ConstantPower) with its injection rate filled
so, holds ``\\varepsilon``. The viscosity is then chosen from the grid rather than supplied:

  * When no `viscosity` is passed, the viscosity is **derived**: ``\\nu`` is set so that
    ``\\kappa_{\\max}\\eta`` equals `κ_max_η`, the highest Reynolds number the grid resolves, with
    ``\\kappa_{\\max}`` the [`max_resolved_wavenumber`](@ref) and ``\\eta = (\\nu^{3}/\\varepsilon)^{1/4}`` the
    Kolmogorov length.

    The resolution fixes ``\\eta``, hence the box Reynolds number
    ``\\mathrm{Re}_{\\mathrm{box}} = (L/\\eta)^{4/3}``, at which ``\\tilde{k}`` is read, and then
    ``\\nu = \\varepsilon^{1/3}\\eta^{4/3}``. Since ``\\kappa_{\\max}\\eta = f_{\\mathrm{res}}\\pi\\eta/\\Delta x`` with ``f_{\\mathrm{res}}`` the
    resolved-Nyquist fraction and ``\\Delta x = L/N`` the spacing of ``N`` grid points per side, `κ_max_η = 2` gives ``\\Delta x \\approx \\eta`` under the default
    ``2/3`` rule. The chosen ``\\nu``, ``k``, ``\\varepsilon`` and ``\\mathrm{Re}_\\lambda`` are logged, with what
    the forcing guarantees.

    !!! note "The criterion measures the resolved band, strategy by strategy"
        ``\\kappa_{\\max}`` here is each strategy's **resolved** cutoff — for
        [`HouLi`](@ref GBGHomogeneousTurbulence.SimulationDomain.HouLi) that is
        ``\\tfrac{4}{5}\\kappa_{\\mathrm{Ny}}``, with ``\\kappa_{\\mathrm{Ny}} = N\\pi/L`` the Nyquist
        wavenumber, where its per-step damping overtakes viscosity,
        not the Nyquist its energetic band reaches — so equal `κ_max_η` means equally trusted
        dynamics across strategies. Strategies still reach different Reynolds numbers on the same
        grid, but for the honest reason that their resolved bands differ: with
        ``\\nu \\propto f^{-4/3}``, `HouLi` gives ``\\mathrm{Re}_\\lambda`` about 13% and
        [`PhaseShift`](@ref GBGHomogeneousTurbulence.SimulationDomain.PhaseShift) about 26% above the
        ``2/3`` rule.

    What is guaranteed follows what the forcing holds. A forcing holding ``\\varepsilon``, as the
    default does, meets `κ_max_η` in the stationary mean whatever ``\\tilde{k}`` truly is, and leaves
    ``k`` the prediction. One holding ``k`` makes ``\\varepsilon``, and with it the resolution, the
    prediction. One holding neither, given its own strength — a [`Linear`](@ref GBGHomogeneousTurbulence.Forcing.Linear) rate, a [`StochasticOU`](@ref GBGHomogeneousTurbulence.Forcing.StochasticOU)
    variance, a `VarianceRescaling(over = :band)` target — draws a warning, since ``\\nu`` then
    describes a state the run may not reach.

    A forcing the prediction does not cover has no stationary state to derive ``\\nu`` from, and is
    refused with an `ArgumentError`: an unforced run (`velocity_forcing = NoForcing()`), and a band
    that does not start at shell 1 or ends at shell 1.

  * When `viscosity` is **supplied**, it is used directly; the two are alternatives, and
    passing both raises an `ArgumentError`. A covered forcing's state is still predicted, at the
    ``\\mathrm{Re}_{\\mathrm{box}} = \\varepsilon^{1/3}L^{4/3}/\\nu`` the given ``\\nu`` gives. For a run the prediction
    does not cover, nothing is predicted: the velocity is seeded at the stated ``k``, and an unforced
    run may state ``\\varepsilon`` as well, since a decaying initial state has no balance tying the two.

# Arguments

All keyword except `domain`. The keywords split as the two forms do: the **domain group** is
consumed by the domain-building form, and the domain-taking form replaces the whole group with its
one positional argument; the **run group** is accepted by both.

The domain group:

- `domain` — a pre-built `FixedDomain`: the **positional** argument of the domain-taking form,
  standing in for every other keyword of this group.
- `grid_points_per_axis` — the number of grid points ``N`` along each side; required.
- `side_length = 2π` — the box side ``L``.
- `dealiasing = TwoThirds()` — the [`DealiasingStrategy`](@ref) (``2/3`` sharp, `HouLi` smooth, or
  `PhaseShift`); it sets the retained band (hence the CFL step) and the resolved band (hence the
  ``\\kappa_{\\max}`` of `κ_max_η`).
- `element_type = Float64`, `array_family = Array` — the real element type and storage backend
  ([Memory footprint on a GPU](@ref) sizes a run).
- `fft_flags = nothing`, `fft_timelimit = Inf` — the FFT planner request, forwarded to the
  `FixedDomain` being built (pass `FFTW.MEASURE` for a long CPU run — the planner note
  there explains why; inert on a GPU backend).

The run group, `kwargs...` in both signatures
([keyword arguments](https://docs.julialang.org/en/v1/manual/functions/#Keyword-Arguments)):

- `κ_max_η` — the resolution criterion ``\\kappa_{\\max}\\eta`` a derived ``\\nu`` is set from;
  ``\\ge 1.5`` is well-resolved, higher trades Reynolds number for margin. It defaults to `nothing`
  and the derivation then uses `2`; the sentinel is what lets the constructor tell an omitted keyword from
  an explicit one, so that giving both it and `viscosity` is an error rather than a silent drop.
- `viscosity` — the kinematic viscosity ``\\nu``, which is how the Reynolds number is set (it is
  ``1/\\nu`` only in units where ``u' = L = 1``; measure ``\\mathrm{Re}_\\lambda`` for the run's actual value); omit to derive ``\\nu`` from the grid.
- `kinetic_energy = nothing`, `dissipation = nothing` — the run's stationary state, as its kinetic
  energy ``k`` or its dissipation rate ``\\varepsilon``. Give at most one, or neither and let the
  velocity forcing's target state it; with no source at all ``k = 1.5``, an r.m.s. velocity
  ``u' = \\sqrt{2k/3} = 1``. The member not given is predicted through ``\\tilde{k}``. An unforced run
  may give both, as its initial state. The velocity is seeded at the state's ``k``; to start from
  another energy, adopt a `state`.
- `scalar = nothing` — the passive scalar the run carries, a [`PassiveScalar`](@ref) with its
  Schmidt number, seeded variance and forcing; `nothing` carries none, and no scalar setting can
  then be given.
- `velocity_forcing = ConstantPower()` — the velocity forcing, an [`AbstractForcing`](@ref) (or a
  `DeferredForcing`, a forcing named by its keywords before the domain exists); the default injects
  the state's ``\\varepsilon``. A deferred forcing may leave its strength out for the state to fill.
  A stated target is a statement of the run's state, so giving `kinetic_energy` or `dissipation`
  beside it is refused; under a derived ``\\nu``, a forcing that holds neither quantity draws the
  warning above.
- `envelope_wavenumber = 2.0` — the large-scale envelope wavenumber ``\\kappa_p`` of the initial
  condition, for the **velocity and the scalar alike** (each shell-summed spectrum peaks at
  ``\\kappa_p/\\sqrt{2}``); it does **not** shape the profile when `initial_spectrum` is given (the model does), but it still
  sets the integral scale of the *assumed state* that model is evaluated at. Keep ``\\kappa_p`` well
  below the dealias cutoff: a value near or above it concentrates the seed, before its energy
  rescale, in shells the dealiasing holds empty; the seeders warn when the envelope's peak reaches the cutoff (a
  model-spectrum seed is shaped by its model instead and is not guarded).
- `initial_spectrum = nothing` — draw the initial velocity from a
  [`Phenomenology`](@ref GBGHomogeneousTurbulence.Phenomenology) `EnergySpectrum` (say
  `VonKarman1948()`) instead of the default large-scale Gaussian. A model spectrum needs a flow
  state, and at ``t = 0`` there is nothing measured yet, so one is *assumed* — a stand-in, not a
  measurement of the field about to be seeded. The assumed state reads: ``\\varepsilon`` and ``u'``
  from the run's stationary state, ``\\nu`` as resolved above, and `1/envelope_wavenumber` for the integral scale
  (rather than the ``L_{11}`` the seeded field will actually have). A run with nothing predicted,
  such as an unforced one, must state `dissipation` for the model to be evaluated at, and is refused
  otherwise.
  The seeded field is then normalized to the state's ``k``, so the model fixes the *shape* and the
  assumed state only positions it. This shapes the **velocity** only; a scalar is always seeded from
  the default Gaussian envelope, and a scalar-spectrum initial condition is reached by calling
  [`random_scalar_spectral!`](@ref GBGHomogeneousTurbulence.State.random_scalar_spectral!) on the
  built run and announcing the change with
  [`fields_modified!`](@ref GBGHomogeneousTurbulence.Cache.fields_modified!).
- `field_integration_scheme = IFLowStorageRK3()`, `cfl = recommended_cfl(field_integration_scheme, domain)` — the
  [`AbstractIntegrator`](@ref) scheme (its docstring catalogues the alternatives) and its
  advective-CFL ceiling (adapts to `dealiasing`).
- `max_dt = Inf` — a further ceiling on the adaptive timestep, stated in the run's own time units,
  and off unless set. The adaptive step is the smallest of three bounds:
  the advective rule ``\\Delta t = C\\Delta x / u_{\\max}`` (``C`` the `cfl` coefficient, ``u_{\\max}``
  the largest velocity-component magnitude in the box), the longest mode's diffusive-decay
  time ``1/(D\\kappa_{\\min}^{2})`` — with ``\\kappa_{\\min} = 2\\pi/L`` the box's fundamental
  wavenumber and ``D`` the **larger** of the run's diffusivities (``\\nu``,
  and ``\\varkappa = \\nu/\\mathrm{Sc}`` when a scalar rides), since the faster-diffusing field
  decays first — and this. The advective
  rule alone diverges as a decaying flow approaches rest — past some step the integrating factor
  annihilates every mode and the clock advances by a number that means nothing — and it is the
  diffusive-decay bound that stops that, needing no constant from the caller. The `max_dt`
  setting is for a ceiling only the caller knows, since any *default* constant would be a claim about the velocity
  scale they happened to choose.
- `number_of_particles = 0`, `interpolation_scheme = nothing`, `unwrapped = false` — the number
  of Lagrangian `Tracers`, the **spatial** scheme that evaluates a field at their positions
  (`nothing` means the default `CatmullRom`), and whether to also track the winding-preserving
  unwrapped positions (read with
  [`unwrapped_positions`](@ref GBGHomogeneousTurbulence.Particles.unwrapped_positions) — what a
  mean-square-displacement diagnostic needs); all three forwarded to the `Tracers` constructor.
  A particle-only setting given on a particle-free run is refused rather than silently discarded.
- `particle_integration_scheme = nothing` — the scheme that advances the trajectories in time, an
  [`AbstractParticleIntegrator`](@ref GBGHomogeneousTurbulence.Particles.AbstractParticleIntegrator)
  (`nothing` means the default [`Heun`](@ref GBGHomogeneousTurbulence.Particles.Heun));
  its **registers** — the per-step scratch that scheme needs, meaningless to read between calls —
  are allocated for you. Pass
  [`AdamsBashforth()`](@ref GBGHomogeneousTurbulence.Particles.AdamsBashforth) when trajectory
  accuracy in time limits a measurement: it costs one stored array per extra order and saves an
  interpolation per step.
- `ordered_interpolation = nothing` — whether the gathers at the tracers (the velocity for the
  advance and the Lagrangian sample, and any field the caller samples) visit them in the
  memory-locality order of a
  [`ParticleTraversal`](@ref GBGHomogeneousTurbulence.Particles.ParticleTraversal). The order
  changes no value — a run with and without it is bitwise identical — only the time the gathers
  take. The default `nothing` means `true` whenever the run carries tracers: the order is built at seeding and
  rebuilt from the start-of-step positions every iteration, a cost small against the gather it
  accelerates. `:manual` builds it and leaves every rebuild to the caller, through
  [`rebuild_traversal!`](@ref GBGHomogeneousTurbulence.Particles.rebuild_traversal!) in the `run!`
  callback at a cadence of their choosing ([`every_steps`](@ref) / [`every_time`](@ref)); `false`
  holds no order and gathers in tracer order. The order and its rebuild scratch hold three
  integer or Boolean vectors of the tracer count and two of the number of grid tiles the order
  groups tracers by — small beside the
  `(M, 3)` positions of the ``M`` tracers — and nothing of it is persisted: a restored run rebuilds it from the
  restored positions.
- `rng` — the random stream for the initial condition, the tracer seeding, and the seed of a
  `StochasticOU` forcing named without one (defaults to `Random.default_rng()`).
- `state = nothing` — an existing `ResolvedFields` to **adopt** as the run's state in place of the
  random seed, which is how a run continues from a stored or externally imported field. Its arrays
  become the run's own and are not copied, so two runs must not adopt one state object. Four rules
  apply to it:
    - it must live on the domain's grid and storage backend, and agree with `scalar`;
    - `initial_spectrum` cannot be given with it, since the field is no longer being seeded;
    - a forcing state it carries in its `modeled` entry — as a checkpoint of a
      `StochasticOU` run does — continues where it
      left off, while a forcing whose entry is empty starts a fresh one. An entry that does not fit
      the forcing given is refused with an `ArgumentError`;
    - with a derived ``\\nu``, the constructor measures the adopted state's kinetic energy and warns
      when it is far from the ``k`` of the run's stationary state. Adopting a state is also how a run
      starts from an energy other than the one it will hold.
- `tracers = nothing` — an existing `Tracers` set to adopt in place of seeding
  `number_of_particles` fresh ones. The interpolation scheme and the unwrapped record are then
  properties of the given set, so `interpolation_scheme` and `unwrapped` cannot be given with it.
  A multistep `particle_integration_scheme` takes its first pushes under `Heun` until its history
  fills — restoring a stored sample
  history alongside the positions is [`read_simulation`](@ref)'s job.

# Examples
The two ways in, and the two ways to set the Reynolds number:

```julia
# Derived viscosity — a 128³ forced-stationary run, ν set from the resolution criterion:
sim = Simulation(grid_points_per_axis = 128)

# The same, stated by its dissipation rate, or held at k by a controller
# taking k from the state:
sim = Simulation(grid_points_per_axis = 128, dissipation = 0.4)
sim = Simulation(grid_points_per_axis = 128, velocity_forcing = VarianceController())

# Supplied viscosity — set ν directly, carry a passive scalar, force at constant power:
sim = Simulation(grid_points_per_axis = 128, viscosity = 1e-2;
                 scalar = PassiveScalar(), velocity_forcing = ConstantPower(injection_rate = 0.1))

# Domain-taking — build the domain yourself, then hand it over:
domain = FixedDomain(; grid_points_per_axis = 128, side_length = 2π,
                       dealiasing = HouLi(), element_type = Float64, array_family = Array)
sim = Simulation(domain; viscosity = 1e-2)
```

Displaying the run — a bare `sim` at the REPL, or the constructor without a trailing `;` in a
notebook — prints where each part lives, then what a `run!` callback may read without computing,
each as the callback writes it: the state's spectral representations, the cache's deposited reads,
and the tracer positions.

!!! note "The default holds the injection rate, so the kinetic energy is free"
    `ConstantPower` injects the state's ``\\varepsilon`` at every stage and never measures ``k``,
    which settles where the true ``\\tilde{k}`` puts it and fluctuates with the cascade. It was chosen as the
    default because it has no gain or settling time to choose. To hold ``k`` instead, force with a
    `VarianceController` whose target is
    left out: it takes the target from the state and restores ``k`` exponentially, its gain setting
    the fluctuation it leaves.

!!! warning "The prediction rests on placeholder values"
    ``\\tilde{k}`` and the band's share of ``k`` are provisional, the same for every forcing strategy,
    and not yet dependent on the Reynolds number; the values per band are listed at
    `kinetic_energy_in_box_units`. A forcing that holds ``k`` or ``\\varepsilon`` exactly meets that
    member; the rest of the state, and a filled strength, are as good as the model.

# Fields
Three of these are what a user reads — `state`, `cache`, and `tracers`. The rest are the machinery the step runs
on: they hold partial values while a step is in flight, so read them only between steps, and treat
their contents as the scheme's business rather than the run's state.

- `state` — the `ResolvedFields` (the evolving ``\\hat{\\boldsymbol{u}}``, ``\\hat\\varphi``).
- `cache` — the `ObservablesCache`: the observables the iteration deposits at its end.
- `domain`, `buffers`, `generator`, `field_integration_scheme` — the `FixedDomain`, `IntegratorBuffers`,
  the `ResolvedGenerator` (whose `conditions` field is the run's `FlowConditions`), and
  the chosen scheme.
- `tracers`, `particle_integration_scheme`, `particle_buffers`, `particle_traversal` — the
  `Tracers` being advected along with the fields, the scheme advancing them along their
  trajectories, that scheme's registers, and the `ParticleTraversal` the gathers visit the tracers
  in (`nothing` under `ordered_interpolation = false`). All `nothing` when the run carries no
  tracers.
- `cfl`, `max_dt`, `clock` — the advective-CFL coefficient, the caller's ceiling on the adaptive
  step in the run's own time units (`Inf` when none), and the time/step counter.
"""
struct Simulation{DOM, FB, IG, GN<:ResolvedGenerator, RF, DF, TR, PI, PB, PT}
  domain::DOM
  buffers::FB
  generator::GN            # ResolvedGenerator: the equations of motion + conditions + assembly scratch
  field_integration_scheme::IG
  state::RF                # ResolvedFields: the evolving (û, φ̂), the single source of truth
  cache::DF                # ObservablesCache: what the last iteration deposited, for an observation to read
  tracers::TR              # Tracers, or nothing — trajectory STATE only
  particle_integration_scheme::PI  # AbstractParticleIntegrator, or nothing
  particle_buffers::PB     # ParticleIntegratorBuffers for that scheme, or nothing
  particle_traversal::PT   # ParticleTraversal — the gathers' memory-locality order — or nothing (decision 86)
  cfl::Float64
  max_dt::Float64          # a ceiling on the adaptive step, in the caller's own units; Inf = none
  clock::Clock
end


# A forcing may be given ready-built (an `AbstractForcing`), deferred (a `DeferredForcing`, which may
# take its target from the run's stationary state `design`), or as a factory `domain -> AbstractForcing`
# — the last two let a banded forcing be named before the domain exists, since a forcing precomputes
# its band from `domain`.
_materialize_forcing(f::AbstractForcing, ::FixedDomain, design) = f
_materialize_forcing(f::DeferredForcing, domain::FixedDomain, design) = f(domain, design)
_materialize_forcing(f, domain::FixedDomain, design) = f(domain)

# A deferred `StochasticOU` named without a seed takes one from the run's `rng`, so that one stream
# varies or repeats the whole run — the fields, the tracers and the forcing together (decision 107).
_seeded(spec, rng) = spec
_seeded(d::DeferredForcing{StochasticOU}, rng) =
  d.parameters.seed === nothing ?
    DeferredForcing{StochasticOU}(merge(d.parameters, (; seed = rand(rng, Int)))) : d


# The member of the run's state the velocity forcing holds exactly — whether it states it or takes it
# from the state: `:dissipation`, `:kinetic_energy`, or `nothing`.
_held_quantity(spec) = let stated = _stated_state(spec)
  stated !== nothing ? only(keys(stated)) :
  spec isa DeferredForcing{ConstantPower} && _takes_design(spec) ? :dissipation :
  (spec isa DeferredForcing{VarianceController} || spec isa DeferredForcing{VarianceRescaling}) &&
    _takes_design(spec) ? :kinetic_energy : nothing
end


# How many times a quantity was stated; a forced run's balance ties k to ε, so it may state one.
function _state_sources(kinetic_energy, dissipation, stated)
  sources = String[]
  kinetic_energy === nothing || push!(sources, "`kinetic_energy`")
  dissipation === nothing || push!(sources, "`dissipation`")
  stated === nothing || push!(sources, "the velocity forcing's own target")
  return sources
end

function _require_one_source(sources)
  length(sources) <= 1 ||
    throw(ArgumentError("the run's stationary state is stated twice, by " * join(sources, " and ") *
                        ". State it once — the kinetic energy k, the dissipation rate ε, or the " *
                        "forcing's target — and the other quantity is predicted from it; leave the " *
                        "forcing's target out to have it filled from the state."))
  return nothing
end

function _positive(value, name, meaning)
  (isfinite(value) && value > 0) ||
    throw(ArgumentError("$name must be positive and finite, got $value: $meaning"))
  return Float64(value)
end


"""
    predicted_stationary_state(domain; velocity_forcing = ConstantPower(),
                               kinetic_energy = nothing, dissipation = nothing,
                               κ_max_η = nothing, viscosity = nothing)

The stationary state a forced run on `domain` is predicted to settle in: the kinetic energy ``k``,
the dissipation rate ``\\varepsilon``, the energy ``k_{\\mathrm{band}}`` held in the forced band, the
viscosity ``\\nu`` and the two Reynolds numbers. It is what [`Simulation`](@ref) sets a run up for, so
calling it first shows what a run will be given, and it serves a study that plans its runs. The
prediction goes through the kinetic energy in box units — lengths in the box side ``L``,
velocities in ``(\\varepsilon L)^{1/3}`` —
([`kinetic_energy_in_box_units`](@ref GBGHomogeneousTurbulence.Forcing.kinetic_energy_in_box_units)),
``k = \\tilde{k} (\\varepsilon L)^{2/3}``, and the band's share of it
([`band_energy_fraction`](@ref GBGHomogeneousTurbulence.Forcing.band_energy_fraction)), both taken at
the run's box Reynolds number ``\\mathrm{Re}_{\\mathrm{box}} = \\varepsilon^{1/3}L^{4/3}/\\nu``.

# Arguments
- `domain` — the [`FixedDomain`](@ref GBGHomogeneousTurbulence.SimulationDomain.FixedDomain), which fixes
  the box side ``L`` and the largest resolved wavenumber ``\\kappa_{\\max}``.
- `velocity_forcing` — the velocity forcing, built, or named before its domain exists as a
  [`DeferredForcing`](@ref GBGHomogeneousTurbulence.Forcing.DeferredForcing). A forcing that
  states its own target (a [`ConstantPower`](@ref GBGHomogeneousTurbulence.Forcing.ConstantPower) injection rate, a [`VarianceController`](@ref GBGHomogeneousTurbulence.Forcing.VarianceController) or
  `VarianceRescaling(over = :total)` target) states the state through it.
- `kinetic_energy`, `dissipation` — the state, stated once: ``k``, ``\\varepsilon``, or neither when the
  forcing states it. With none of the three, ``k = 1.5``.
- `κ_max_η`, `viscosity` — at most one. A resolution ``\\kappa_{\\max}\\eta`` (default 2) fixes the
  Kolmogorov length ``\\eta``, hence ``\\mathrm{Re}_{\\mathrm{box}} = (L/\\eta)^{4/3}``, and ``\\nu`` follows
  from ``\\varepsilon`` as ``\\nu = \\varepsilon^{1/3}\\eta^{4/3}``. A given `viscosity` is kept, and
  ``\\kappa_{\\max}\\eta`` follows instead.

Returns a named tuple `(; kinetic_energy, dissipation, band_kinetic_energy, viscosity, reynolds_box,
reynolds_taylor, kinetic_energy_in_box_units, κ_max_η)` in the domain's element type. A forcing the prediction does not
cover (an unforced run, a band that does not start at shell 1) has no stationary state to predict,
and it throws an `ArgumentError`, as does a state stated twice or both `κ_max_η` and `viscosity`.

!!! warning "A prediction, not a measurement"
    The values rest on the model's placeholder ``\\tilde{k}`` and ``k_{\\mathrm{band}}/k``, which are
    provisional and do not yet depend on the Reynolds number. A forcing that holds ``\\varepsilon`` or
    ``k`` exactly meets that member in the stationary mean; the rest is as good as the model.
"""
function predicted_stationary_state(domain::FixedDomain; velocity_forcing = ConstantPower(),
                                    kinetic_energy = nothing, dissipation = nothing,
                                    κ_max_η = nothing, viscosity = nothing)
  prediction = _predicted_stationary_state(domain; velocity_forcing, kinetic_energy, dissipation,
                                           κ_max_η, viscosity)
  return map(_real_type(domain), prediction)
end

# The prediction in Float64, whatever the domain's precision: `Simulation` sets ν from it, and a
# Float32 run's ν must not be the Float64 value rounded through Float32.
function _predicted_stationary_state(domain::FixedDomain; velocity_forcing = ConstantPower(),
                                     kinetic_energy = nothing, dissipation = nothing,
                                     κ_max_η = nothing, viscosity = nothing)
  reason = _uncovered_reason(velocity_forcing)
  reason === nothing || throw(ArgumentError("predicted_stationary_state: $reason"))
  stated = _stated_state(velocity_forcing)
  sources = _state_sources(kinetic_energy, dissipation, stated)
  _require_one_source(sources)
  viscosity === nothing || κ_max_η === nothing ||
    throw(ArgumentError("`viscosity` and `κ_max_η` are two ways to set ν — `viscosity` fixes it " *
                        "directly, `κ_max_η` derives it from the grid. Pass one, not both."))
  source = isempty(sources) ? "the default kinetic energy" :
           only(sources) == "the velocity forcing's own target" ? "the velocity forcing's target" :
           only(sources)
  ε_stated = dissipation !== nothing ? dissipation :
             stated !== nothing && haskey(stated, :dissipation) ? stated.dissipation : nothing
  k_stated = kinetic_energy !== nothing ? kinetic_energy :
             stated !== nothing && haskey(stated, :kinetic_energy) ? stated.kinetic_energy : nothing
  ε_stated === nothing ||
    (ε_stated = _positive(ε_stated, source, "it is the dissipation rate ε = ν⟨|ω|²⟩ the run holds"))
  ε_stated === nothing &&
    (k_stated = _positive(k_stated === nothing ? 1.5 : k_stated, source,
                          "it is the kinetic energy k = ½⟨|u|²⟩, and a zero-energy field has no spectrum"))
  L = Float64(domain.grid.domain_size[1])
  κ_max = Float64(max_resolved_wavenumber(domain))
  k̃_at(re) = kinetic_energy_in_box_units(velocity_forcing; reynolds_box = re)

  if viscosity === nothing
    resolution = _positive(κ_max_η === nothing ? 2 : κ_max_η, "`κ_max_η`",
                           "it is the resolution criterion κ_max·η, from which the viscosity is solved")
    η = resolution / κ_max
    re = (L / η)^(4 / 3)
    k̃ = k̃_at(re)
    ε = ε_stated !== nothing ? ε_stated : (k_stated / k̃)^(3 / 2) / L
    k = ε_stated !== nothing ? k̃ * (ε * L)^(2 / 3) : k_stated
    ν = cbrt(ε) * η^(4 / 3)
  else
    ν = _positive(viscosity, "`viscosity`", "it is the kinematic viscosity ν")
    if ε_stated !== nothing
      ε = ε_stated
    else
      # k = k̃(Re_box(ε)) (εL)^{2/3}, solved for ε by bisection in log ε: the right side increases with
      # ε whenever d ln k̃/d ln Re_box > −2, far beyond any measured slope.
      energy(log_ε) = k̃_at(reynolds_box(L, exp(log_ε), ν)) * (exp(log_ε) * L)^(2 / 3)
      low, high = log(1e-30), log(1e30)
      for _ in 1:300
        middle = (low + high) / 2
        energy(middle) < k_stated ? (low = middle) : (high = middle)
        high - low < 1e-13 && break
      end
      ε = exp((low + high) / 2)
    end
    re = reynolds_box(L, ε, ν)
    k̃ = k̃_at(re)
    k = ε_stated !== nothing ? k̃ * (ε * L)^(2 / 3) : k_stated
    resolution = κ_max * (ν^3 / ε)^(1 / 4)
  end
  band = band_energy_fraction(velocity_forcing; reynolds_box = re) * k
  return (; kinetic_energy = k, dissipation = ε, band_kinetic_energy = band, viscosity = ν,
          reynolds_box = re, reynolds_taylor = reynolds_taylor(k, ε, ν),
          kinetic_energy_in_box_units = k̃, κ_max_η = resolution)
end


# The state an UNCOVERED run is set up with (decision 105): nothing is predicted, and a derived ν is
# refused before this is reached. The seed takes the stated k (default 1.5); ε is kept only when
# stated. An unforced run may state both, since a decaying initial state has no balance tying them.
function _unmodelled_state(kinetic_energy, dissipation, stated, forcing)
  sources = _state_sources(kinetic_energy, dissipation, stated)
  forcing isa NoForcing || forcing isa DeferredForcing{NoForcing} || _require_one_source(sources)
  ε = dissipation !== nothing ? dissipation :
      stated !== nothing && haskey(stated, :dissipation) ? stated.dissipation : nothing
  k = kinetic_energy !== nothing ? kinetic_energy :
      stated !== nothing && haskey(stated, :kinetic_energy) ? stated.kinetic_energy : 1.5
  ε === nothing || (ε = _positive(ε, "`dissipation`", "it is the dissipation rate ε = ν⟨|ω|²⟩"))
  k = _positive(k, "`kinetic_energy`", "it is the kinetic energy k = ½⟨|u|²⟩, and a zero-energy field has no spectrum")
  return (; kinetic_energy = k, dissipation = ε, band_kinetic_energy = nothing, box_time = nothing)
end


# At module scope, so the `dissipation` keyword of `Simulation` cannot shadow the reduction.
_seeded_dissipation(state, domain, ν) = dissipation(state.velocity_spectral, domain, ν)


# The adopted-state sibling of the forcing check below: ν was derived assuming k =
# `kinetic_energy`, and an injected state may hold something else entirely. Measured (one
# reduction at construction, module scope so the `kinetic_energy` KEYWORD cannot shadow the
# reduction), never trusted; the 10% tolerance leaves stationary fluctuations silent.
function _warn_adopted_state_energy_mismatch(state::ResolvedFields, target)
  k_state = kinetic_energy(state.velocity_spectral)
  abs(k_state - target) <= 0.1 * target ||
    @warn "Simulation (derived viscosity): ν was calibrated for k = $target (`kinetic_energy`), " *
          "but the adopted `state` holds k = $(round(k_state, sigdigits = 4)). κ_max·η / Re_λ " *
          "will not match the calibration. Pass the state's energy as `kinetic_energy`, or set " *
          "`viscosity` yourself."
  return nothing
end


# A derived ν is solved from the run's stationary ε. A forcing that holds k or ε, or takes its strength
# from that state, agrees with it by construction (a second, conflicting statement is refused in
# `_design_state`); one that holds neither — a band, a fixed rate, a stated stochastic strength —
# leaves ν calibrated against a state the run may not reach, and this names it at construction.
_warn_derived_viscosity_forcing_mismatch(vf::VarianceRescaling, design) =
  (@warn "Simulation (derived viscosity): ν was calibrated for the whole-field state " *
         "(k ≈ $(round(design.kinetic_energy, sigdigits = 4)), ε ≈ $(round(design.dissipation, sigdigits = 4))), " *
         "but this `VarianceRescaling(over = :band)` holds only the band and lets both settle " *
         "elsewhere. Use `over = :total`, or set `viscosity` yourself.";
   nothing)

_warn_derived_viscosity_forcing_mismatch(vf::AbstractForcing, design) =
  (@warn "Simulation (derived viscosity): ν was calibrated for the state (k ≈ " *
         "$(round(design.kinetic_energy, sigdigits = 4)), ε ≈ $(round(design.dissipation, sigdigits = 4))), " *
         "which a $(nameof(typeof(vf))) given its own strength does not hold (k and ε settle " *
         "wherever its balance puts them). The κ_max·η / Re_λ the constructor reports are then " *
         "estimates for a state the run may not reach; set `viscosity` yourself for a calibrated " *
         "run.";
   nothing)


function Simulation(domain::FixedDomain;
                    kinetic_energy::Union{Nothing, Real} = nothing,
                    dissipation::Union{Nothing, Real} = nothing,
                    κ_max_η = nothing, viscosity = nothing,
                    velocity_forcing = ConstantPower(),
                    field_integration_scheme::AbstractIntegrator = IFLowStorageRK3(),
                    cfl::Real = recommended_cfl(field_integration_scheme, domain), max_dt::Real = Inf,
                    scalar::Union{Nothing, PassiveScalar} = nothing,
                    envelope_wavenumber::Real = DEFAULT_ENVELOPE_WAVENUMBER, initial_spectrum = nothing,
                    state::Union{Nothing, ResolvedFields} = nothing,
                    number_of_particles::Integer = 0, interpolation_scheme = nothing,
                    unwrapped::Bool = false,
                    tracers::Union{Nothing, Tracers} = nothing,
                    particle_integration_scheme::Union{Nothing, AbstractParticleIntegrator} = nothing,
                    ordered_interpolation::Union{Nothing, Bool, Symbol} = nothing,
                    rng = Random.default_rng())
  # Validated first: the symbol form has exactly one admissible value, and a typo would otherwise
  # be read as "resident, rebuilt by the caller" — a silently wrong mode.
  ordered_interpolation in (nothing, true, false, :manual) ||
    throw(ArgumentError("`ordered_interpolation` must be `nothing`, `true`, `false`, or `:manual`; " *
                        "got $(repr(ordered_interpolation))"))
  # The scalar's settings travel as one value, so a run without a scalar can be given none of them;
  # a scalar-free run's conditions carry the inert Sc = 1 and no scalar forcing.
  carries_scalar = scalar !== nothing
  schmidt = carries_scalar ? scalar.schmidt : 1.0
  # The injection door (decision 83): an existing state or tracer set is ADOPTED — its arrays
  # become the run's own, no copy — so a continuation or an external import skips the seeding.
  # Validated here, before anything is built from the settings the adoption overrides.
  if state !== nothing
    initial_spectrum === nothing ||
      throw(ArgumentError("`initial_spectrum` and `state` are two ways to set the initial " *
                          "condition — `initial_spectrum` shapes the random seed, `state` adopts " *
                          "an existing field set. Pass one, not both."))
    (state.scalar_spectral !== nothing) == carries_scalar ||
      throw(ArgumentError(carries_scalar ?
        "`scalar` was given but the given `state` carries no scalar: the run would advect a " *
        "scalar the state does not hold. Build the state with a scalar, or drop `scalar`." :
        "the given `state` carries a scalar but no `scalar` was given: the run would silently " *
        "ignore it. Give `scalar = PassiveScalar()`, or hand over a velocity-only state."))
    state.velocity_spectral.grid == domain.grid ||
      throw(ArgumentError("the given `state` lives on a different grid than `domain`: grid " *
                          "size, box size, and element type must all agree for the state to be " *
                          "adopted."))
    state.velocity_spectral.fourier_coefficients isa domain.array_family ||
      throw(ArgumentError("the given `state` lives on a different storage backend than " *
                          "`domain`: move it, or build the domain, on the matching backend."))
  end
  if tracers !== nothing
    number_of_particles == 0 ||
      throw(ArgumentError("`number_of_particles` and `tracers` are two ways to ask for " *
                          "particles — the count seeds a fresh set, `tracers` adopts an " *
                          "existing one. Pass one, not both."))
    interpolation_scheme === nothing ||
      throw(ArgumentError("`interpolation_scheme` was given together with `tracers`, but the " *
                          "interpolation scheme is a property of the given tracer set. Drop " *
                          "the setting."))
    !unwrapped ||
      throw(ArgumentError("`unwrapped = true` was given together with `tracers`, but the " *
                          "unwrapped record is a property of the given tracer set. Drop the " *
                          "setting."))
    point_positions(tracers.positions) isa domain.array_family ||
      throw(ArgumentError("the given `tracers` live on a different storage backend than " *
                          "`domain`: move them, or build the domain, on the matching backend."))
  end
  # k = ½⟨|u|²⟩ is non-negative by construction, and the seeder rescales by √(k/current), so a
  # negative value surfaced far downstream as a DomainError out of `sqrt` with nothing naming the
  # argument that caused it.
  number_of_particles >= 0 ||
    throw(ArgumentError("`number_of_particles` must be non-negative, got $number_of_particles: a " *
                        "negative count was silently routed to the tracer-free branch, so the run " *
                        "carried no tracers and never said so"))
  max_dt > 0 ||
    throw(ArgumentError("`max_dt` must be positive, got $max_dt"))
  cfl > 0 ||
    throw(ArgumentError("`cfl` must be positive, got $cfl: it scales the advective timestep " *
                        "Δt = cfl·Δx/u_max, so a non-positive value stops or reverses the clock"))
  side_length = domain.grid.domain_size[1]
  # A forcing given as a function of the domain is built now, so the model can read the strategy it
  # returns; a built strategy states its own strength.
  velocity_spec = velocity_forcing isa Union{AbstractForcing, DeferredForcing} ? velocity_forcing :
                  velocity_forcing(domain)
  velocity_spec = _seeded(velocity_spec, rng)
  # Both arguments set ν, by different routes, so accepting both would silently honour one of them.
  if !isnothing(viscosity) && !isnothing(κ_max_η)
    throw(ArgumentError("`viscosity` and `κ_max_η` are two ways to set ν — `viscosity` fixes it \
directly, `κ_max_η` derives it from the grid. Pass one, not both."))
  end
  uncovered = _uncovered_reason(velocity_spec)
  if uncovered === nothing
    # The model covers this forcing: the state is predicted, and a derived ν is solved from it.
    prediction = _predicted_stationary_state(domain; velocity_forcing = velocity_spec, kinetic_energy,
                                             dissipation, κ_max_η, viscosity)
    ν = prediction.viscosity
    design = (; prediction.kinetic_energy, prediction.dissipation, prediction.band_kinetic_energy,
              box_time = cbrt(side_length^2 / prediction.dissipation))
    if isnothing(viscosity)
      # ν is SET here from the predicted ε. Which member of (k, ε) is guaranteed depends on what the
      # forcing holds, so the line says so. Nothing here is a measurement — `flow_parameters` measures.
      resolution = prediction.κ_max_η
      held = _held_quantity(velocity_spec)
      guarantee = held === :dissipation ?
        "the forcing holds ε, so κ_max·η = $(resolution) holds in the stationary mean; k is predicted" :
        held === :kinetic_energy ?
        "the forcing holds k; ε, and with it κ_max·η ≈ $(resolution), is predicted" :
        "the forcing holds neither k nor ε; both, and κ_max·η ≈ $(resolution), are predicted"
      @info "Simulation: ν is set from ε; $guarantee (k̃ = $(prediction.kinetic_energy_in_box_units), placeholder)" viscosity=ν kinetic_energy=prediction.kinetic_energy dissipation=prediction.dissipation expected_Re_λ=prediction.reynolds_taylor
    end
  else
    # No stationary state to predict: a derived ν has nothing to be solved from, and is refused.
    isnothing(viscosity) &&
      throw(ArgumentError("Simulation: a derived viscosity is solved from the predicted stationary " *
                          "state, and there is none here: $uncovered. Set `viscosity`."))
    ν = Float64(viscosity)
    design = _unmodelled_state(kinetic_energy, dissipation, _stated_state(velocity_spec), velocity_spec)
  end
  k_design, ε = design.kinetic_energy, design.dissipation
  # An adopted state can void the derived-ν calibration the same way a hand-built forcing can:
  # the stationary estimate assumed k = `kinetic_energy`, and the state handed over may hold
  # something else. Measured, not trusted; explicit-ν runs stay silent.
  viscosity === nothing && state !== nothing &&
    _warn_adopted_state_energy_mismatch(state, k_design)

  buffers = allocate_buffers(field_integration_scheme, domain; scalar = carries_scalar)
  # The velocity forcing is built against the run's predicted state, filling an omitted strength from
  # it. The scalar has no modelled state: its forcing takes an omitted whole-field target from the
  # stated `variance`, and from the velocity's state only the box time a correlation time in box
  # units is converted with. A derived ν warns only for a forcing that neither holds a member of
  # the state nor takes its strength from it (owner-ruled 2026-08-24).
  design = merge(design, (; variance = design.kinetic_energy))
  vf = _materialize_forcing(velocity_spec, domain, design)
  viscosity === nothing && _held_quantity(velocity_spec) === nothing && !_takes_design(velocity_spec) &&
    _warn_derived_viscosity_forcing_mismatch(vf, design)
  conditions = FlowConditions(; viscosity = ν, schmidt,
                    velocity_forcing = vf,
                    scalar_forcing = carries_scalar ?
                      _materialize_forcing(_seeded(scalar.forcing, rng), domain,
                                           (; variance = scalar.variance, box_time = design.box_time)) :
                      NoForcing())
  # The scalar's resolution check — AFTER `FlowConditions`, whose guard validates `schmidt > 0`
  # first (the √Sc below would turn a negative Sc into an unnamed DomainError otherwise).
  # The velocity's criterion does not cover it. ν was derived or supplied
  # against the VELOCITY cutoff κ_max·η, but a scalar at Sc > 1 lives
  # down to the finer Batchelor scale η_B = η/√Sc, so the same grid resolves it worse by √Sc and
  # `scalar_dissipation` then measures a truncated field. Both modes know ν and the stationary ε
  # estimate here, so the actual κ_max·η_B is computable and is CHECKED rather than left to a
  # docstring bullet the reader may skip. The floor is the same 1.5 the docstring calls
  # well-resolved for the velocity — below it the scalar is clearly under-resolved, and the warning
  # carries the measured numbers and the remedies. A warning, never an error: the value stays legal
  # (a deliberately under-resolved scalar is a legitimate experiment), it just cannot be silent.


  if state === nothing
    state = ResolvedFields(domain; scalar = carries_scalar)
    ic_spectrum = nothing
    if initial_spectrum isa EnergySpectrum     # a `Phenomenology` model → evaluate at the run's state
      ε === nothing &&
        throw(ArgumentError("a `Phenomenology` `initial_spectrum` is evaluated at the run's dissipation " *
                            "rate, and this run has none predicted ($uncovered). State `dissipation`."))
      fp = FlowParameters(; viscosity = ν, dissipation = ε, rms_velocity = sqrt(2 * k_design / 3),
                          integral_scale = inv(envelope_wavenumber), schmidt)
      ic_spectrum = κ -> spectrum(initial_spectrum, κ, fp)
    elseif !isnothing(initial_spectrum)
      ic_spectrum = initial_spectrum           # a raw κ -> E(κ) function
    end
    random_solenoidal_velocity_spectral!(state.velocity_spectral, domain, k_design;
                                         envelope_wavenumber, initial_spectrum = ic_spectrum, rng)
    carries_scalar &&
      random_scalar_spectral!(state.scalar_spectral, domain, scalar.variance; envelope_wavenumber, rng)
  end
  state = _with_forcing_states(state, conditions, domain)
  if carries_scalar
    # The predicted stationary ε where there is one; the seeded field's own ε where nothing is predicted.
    ε_check = ε !== nothing ? ε : _seeded_dissipation(state, domain, ν)
    η = kolmogorov_length(FlowParameters(; viscosity = ν, dissipation = ε_check,
                                         rms_velocity = sqrt(2 * k_design / 3),
                                         integral_scale = inv(envelope_wavenumber), schmidt))
    κ_max_η = max_resolved_wavenumber(domain) * η
    κ_max_η_B = κ_max_η / sqrt(schmidt)
    if κ_max_η_B < 1.5
      # The velocity clause must agree with the number it quotes: claim resolution only when the
      # velocity actually clears the same floor the sentence applies to the scalar.
      velocity_clause = κ_max_η >= 1.5 ?
        "The grid resolves the velocity (κ_max·η = $(round(κ_max_η, digits = 2))), but at " *
        "Sc = $(schmidt) the scalar's Batchelor scale η_B = η/√Sc is finer by √Sc, and " :
        "The velocity is under-resolved too (κ_max·η = $(round(κ_max_η, digits = 2)) against " *
        "the same floor), the scalar's Batchelor scale η_B = η/√Sc being no coarser, so "
      @warn "Simulation: the scalar is under-resolved — κ_max·η_B = $(round(κ_max_η_B, digits = 2)) " *
            "against the well-resolved floor of 1.5. " * velocity_clause *
            "`scalar_dissipation` will measure a truncated field. Raise `κ_max_η` by √Sc, lower " *
            "`schmidt`, or set `viscosity` yourself if the truncation is deliberate. (η here uses " *
            (ε !== nothing ? "the run's stationary dissipation rate; a decaying run resolves better " *
            "than this as it decays.)" : "the seeded field's dissipation rate.)")
    end
  end


  # A particle-only setting configured on a particle-free run would be silently discarded, which is
  # the quiet-wrong-configuration shape `ResolvedGenerator` refuses for a scalar forcing without a
  # scalar; the `nothing` defaults exist so that "given at all" is detectable here.
  if number_of_particles == 0 && tracers === nothing
    for (name, value) in (("interpolation_scheme", interpolation_scheme),
                          ("particle_integration_scheme", particle_integration_scheme),
                          ("ordered_interpolation", ordered_interpolation))
      value === nothing ||
        throw(ArgumentError("`$name` was given but `number_of_particles = 0`: the run advects no " *
                            "tracers, so the setting would be silently discarded. Ask for " *
                            "particles, or drop the setting."))
    end
    unwrapped &&
      throw(ArgumentError("`unwrapped = true` but `number_of_particles = 0`: the run advects no " *
                          "tracers, so there are no positions to unwrap. Ask for particles, or " *
                          "drop the setting."))
  end
  pscheme = particle_integration_scheme === nothing ? Heun() : particle_integration_scheme
  tracers = tracers !== nothing ? tracers :
            number_of_particles > 0 ?
    Tracers(domain; number_of_particles,
            interpolation_scheme = interpolation_scheme === nothing ? CatmullRom : interpolation_scheme,
            unwrapped, rng) : nothing
  # The cache is built first: it carries the Lagrangian sample history a multistep particle integration scheme
  # integrates over, so the scheme's registers are allocated against it.
  cache = ObservablesCache(domain; scalar = carries_scalar,
                           number_of_particles = tracers === nothing ? 0 : npoints(tracers.positions),
                           history_depth = history_depth(pscheme))
  particle_buffers = tracers === nothing ? nothing :
                     allocate_buffers(pscheme, tracers, cache)
  # The traversal order is on by default (decision 86): a value-preserving accelerator whose
  # every-iteration rebuild costs a small fraction of the gather it speeds up. `:manual` keeps it
  # resident and leaves the rebuild cadence to the caller's callback; `false` allocates nothing.
  particle_traversal = (tracers === nothing || ordered_interpolation === false) ? nothing :
                       ParticleTraversal(domain, tracers; automatic = ordered_interpolation !== :manual)
  deposit!(cache, state, domain, buffers)        # the seeding deposit: the first instant observed is t₀
  tracers === nothing ||
    deposit!(cache, tracers, velocity_physical(cache); traversal = particle_traversal)
  return Simulation(domain, buffers, ResolvedGenerator(domain, conditions; scalar = carries_scalar),
                    field_integration_scheme, state, cache,
                    tracers, tracers === nothing ? nothing : pscheme, particle_buffers, particle_traversal,
                    Float64(cfl), Float64(max_dt), Clock(0.0, 0))
end


# The run's state carries each forcing's evolving state (decision 23(c)). A fresh one is given the
# state its forcing starts; an adopted one keeps the state it carries when that state fits the forcing
# — the continuation a checkpoint exists for — and is refused by name when it does not, since a
# process silently restarted or silently misapplied is a different run. The fields are never copied.
function _with_forcing_states(state::ResolvedFields, conditions::FlowConditions, domain::FixedDomain)
  velocity = _forcing_state(conditions.velocity_forcing, state.modeled.velocity_forcing,
                            state.velocity_spectral, domain, "velocity_forcing")
  scalar = state.scalar_spectral === nothing ? state.modeled.scalar_forcing :
           _forcing_state(conditions.scalar_forcing, state.modeled.scalar_forcing,
                          state.scalar_spectral, domain, "scalar_forcing")
  modeled = (velocity_forcing = velocity, scalar_forcing = scalar)
  modeled.velocity_forcing === state.modeled.velocity_forcing &&
    modeled.scalar_forcing === state.modeled.scalar_forcing && return state
  return ResolvedFields(state.velocity_spectral, state.scalar_spectral, modeled)
end

function _forcing_state(forcing, carried, field, domain, name)
  started = initial_forcing_state(forcing, field, domain)
  carried === nothing && return started
  _fits(started, carried) && return carried
  throw(ArgumentError("the adopted state carries a $(nameof(typeof(carried))) for `$name`, which " *
                      "does not fit the $(nameof(typeof(forcing))) given: " *
                      (started === nothing ? "that strategy evolves no state. " :
                       "it belongs to a different forcing, band, or precision. ") *
                      "Adopt `ResolvedFields(state.velocity_spectral, state.scalar_spectral)` to " *
                      "start the forcing afresh."))
end

_fits(started, carried) = typeof(started) === typeof(carried)
_fits(started::StochasticOUState, carried::StochasticOUState) =
  typeof(started) === typeof(carried) &&
  field_grid(started.process).grid_size == field_grid(carried.process).grid_size


function Simulation(; grid_points_per_axis::Integer, side_length::Real = 2π,
                    dealiasing::DealiasingStrategy = TwoThirds(),
                    element_type::Type = Float64, array_family = Array,
                    fft_flags = nothing, fft_timelimit::Real = Inf, kwargs...)
  return Simulation(FixedDomain(; grid_points_per_axis, side_length, dealiasing, element_type,
                                  array_family, fft_flags, fft_timelimit); kwargs...)
end


# A `Simulation` is a container, not a reading surface: it holds the state, the cache, and the run
# machinery, and the user reads each of those directly — `kinetic_energy(sim.state.velocity_spectral)`
# for a state observable, `velocity_physical(sim.cache)` for a deposited one. The run layer adds no
# forwarding methods, so there is exactly one way to reach each quantity and no second docstring to
# drift from the first.


function deposit!(sim::Simulation)
  deposit!(sim.cache, sim.state, sim.domain, sim.buffers)
  # The velocity sample rides the same re-deposit: the positions are unchanged, so re-depositing
  # from the freshly deposited velocity restores the values the announcement made stale.
  sim.tracers === nothing ||
    deposit!(sim.cache, sim.tracers, velocity_physical(sim.cache); traversal = sim.particle_traversal)
  return sim
end


"""
    flow_parameters(sim)

The measured flow state of `sim` as a [`FlowParameters`](@ref) — the bridge that lets any
[`Phenomenology`](@ref GBGHomogeneousTurbulence.Phenomenology) reference law be evaluated at the run's
measured state. The viscosity ``\\nu`` and the
Schmidt number are read from the run's
[`FlowConditions`](@ref GBGHomogeneousTurbulence.Generator.FlowConditions); the dissipation ``\\varepsilon``, the r.m.s. velocity
``u' = \\sqrt{2k/3}`` (from the kinetic energy ``k``), the longitudinal integral scale ``L_{11}``, and —
when the run carries a scalar — the scalar dissipation ``\\varepsilon_\\varphi`` are measured from the
current state (the scalar dissipation is left `NaN` only for a scalar-free run, where the scalar reference
laws do not apply).
"""
function flow_parameters(sim::Simulation)
  k = kinetic_energy(sim.state.velocity_spectral)
  ε = dissipation(sim.state.velocity_spectral, sim.domain, sim.generator.conditions.viscosity)
  εφ = sim.state.scalar_spectral === nothing ? NaN :
    scalar_dissipation(sim.state.scalar_spectral, sim.domain, scalar_diffusivity(sim.generator.conditions))
  FlowParameters(; viscosity = sim.generator.conditions.viscosity, dissipation = ε,
                 rms_velocity = sqrt(2k / 3),
                 integral_scale = integral_scale(sim.state.velocity_spectral, sim.domain),
                 schmidt = sim.generator.conditions.schmidt, scalar_dissipation = εφ)
end


"""
    current_time(sim)

The elapsed simulation time of `sim`.
"""
current_time(sim::Simulation) = sim.clock.time

"""
    current_step(sim)

The number of steps `sim` has taken — how far the run has gone.

Distinct from the observables cache's **epoch**, which counts *changes to the state* rather than
advances of the run: a completed step advances the epoch, but so does any state change announced
with [`fields_modified!`](@ref GBGHomogeneousTurbulence.Cache.fields_modified!). The constructor's
deposit of the seeded fields already leaves their epoch at 1, so after two steps
and one announced change the clock reads
step 2 and the fields epoch reads 4. Use this to ask how far the run has gone, and the epoch to ask
whether a cached value is still the right one.
"""
current_step(sim::Simulation) = sim.clock.step


# The REPL / notebook display of a run. Every row is spelled as a callback would type it: first
# where each part of the run lives — the domain, the flow conditions the viscosity and forcings are
# stored in, the schemes, the step settings, the clock with its values — each part through its own
# display; then what a `run!` callback may read WITHOUT computation: the state's representations of
# record, the cache's deposited reads (served as the closing deposit left them, never recomputed),
# and the tracer positions. Nothing that would compute (an observable, `flow_parameters`) is listed,
# and a run without a scalar or without particles shows no row about them. Names only: nothing here
# touches a device array, and nothing reads a cache slot (a checked read could throw on a stale slot;
# the display must never).
function Base.show(io::IO, ::MIME"text/plain", sim::Simulation)
  conditions = sim.generator.conditions
  has_scalar = !isnothing(sim.state.scalar_spectral)
  has_tracers = !isnothing(sim.tracers)
  has_unwrapped = has_tracers && !isnothing(sim.tracers.unwrapped_positions)
  row(name, value) = print(io, "\n  ", rpad(name, 43), value)
  print(io, "Simulation")
  row("sim.domain", sim.domain)
  row("sim.generator.conditions.viscosity", conditions.viscosity)
  has_scalar && row("sim.generator.conditions.schmidt", conditions.schmidt)
  row("sim.generator.conditions.velocity_forcing", conditions.velocity_forcing)
  has_scalar && row("sim.generator.conditions.scalar_forcing", conditions.scalar_forcing)
  row("sim.field_integration_scheme", sim.field_integration_scheme)
  row("sim.cfl", sim.cfl)
  row("sim.max_dt", sim.max_dt)
  has_tracers && row("sim.tracers", sim.tracers)
  has_tracers && row("sim.particle_integration_scheme", sim.particle_integration_scheme)
  row("current_time(sim), current_step(sim)", "$(current_time(sim)), $(current_step(sim))")
  print(io, "\nReadable in a `run!` callback (its argument named `sim`) without computation:")
  row("sim.state.velocity_spectral", "û — the velocity in spectral representation, the source of truth")
  has_scalar && row("sim.state.scalar_spectral", "φ̂ — the scalar, likewise")
  row("velocity_physical(sim.cache)", "u — the velocity, as deposited at the end of the last iteration")
  row("vorticity_physical(sim.cache)", "ω — the vorticity, likewise")
  has_scalar && row("scalar_physical(sim.cache)", "φ — the scalar, likewise")
  row("max_speed(sim.cache)", "maxᵢ|uᵢ| over the box, a host number, likewise")
  has_tracers && row("velocity_at_particles(sim.cache)", "u at the tracers, an M × 3 array, likewise")
  has_tracers && row("sim.tracers.positions", "the tracers' positions, a PointSet (read via point_positions)")
  has_unwrapped && row("unwrapped_positions(sim.tracers)", "the unwrapped positions, a PointSet")
end

# The one line: the grid in the field library's spelling, and the clock — what distinguishes two
# runs a caller could confuse in a container.
function Base.show(io::IO, sim::Simulation)
  print(io, "Simulation(")
  join(io, field_physical_shape(sim.domain.grid, Val(0)), "×")
  print(io, " grid, time $(current_time(sim)), step $(current_step(sim)))")
end


# The advective-CFL timestep Δt = C·Δx/maxᵢ|uᵢ| for the current velocity (the integrating factor
# makes diffusion exact, so only the advective limit applies). The maximum speed is the cache's
# deposited number — the previous closing deposit measured it — so choosing Δt is scalar arithmetic, not a pass.
function cfl_timestep(sim::Simulation)
  grid = sim.domain.grid
  Δx = minimum(Float64.(grid.domain_size) ./ grid.grid_size)
  speed = max_speed(sim.cache)
  # Kept for a direct `cfl_timestep(sim)` call; `advance!` guards its own path independently, since
  # a hand-fixed `dt` never reaches here.
  isfinite(speed) || error("non-finite velocity at step $(sim.clock.step): the run appears to have blown up")
  # Three bounds, and the step is the smallest.
  #
  # ADVECTIVE — the documented rule, Δt = C·Δx/u_max. It is a CONSTRAINT, not a target: it answers
  # "how far can I step before advection carries information across a cell?" As a decaying flow
  # approaches rest that answer becomes "no limit at all", which is true and useless, and the step
  # runs away — measured reaching ~1e15, at which point the integrating factor annihilates every
  # mode, the state stops moving, and the clock advances by a number that means nothing. Worse, the
  # annihilated state has a smaller u_max still, so the runaway feeds itself.
  #
  # RESOLUTION — the missing term, and it is not a stability limit: diffusion is advanced EXACTLY by
  # the integrating factor, so it constrains nothing. It is a statement about what a step can still
  # resolve. The slowest thing the box holds is the decay of its longest mode, κ_min = 2π/L, at rate
  # D·κ_min²; a step longer than 1/(D·κ_min²) decays that mode by more than a factor e in ONE step,
  # which is the precise sense in which the state "stops moving". `D` is the largest diffusivity the
  # run carries — ν for the velocity, ν/Sc for the scalar — so a scalar with Sc < 1 diffuses faster
  # than the velocity and sets the tighter bound.
  #
  # It is permissive where it should be. The ratio to the advective step is (N/4π²C)·Re_L with
  # Re_L = L·u_max/ν, so it grows with resolution AND Reynolds number: measured 53x at N = 16,
  # Re_L = 65, and 8e4 at N = 256, Re_L = 6283. It binds only below Re_L ≈ 1, which is not
  # turbulence — exactly the dying flow the runaway comes from.
  #
  # Other codes solve this differently and neither derives a bound: hit3d nudges Δt multiplicatively
  # with a 1% growth limiter and a hard `min(DT, 0.01)`, and fluidsim caps at a `deltat_max`
  # parameter (default 0.2) with its zero-velocity branch returning that cap outright. A dimensionless
  # growth limiter would also bound the runaway without asserting anything about units; this route was
  # taken instead because it needs no constant at all — ν and L are already the run's own.
  #
  # MAX_DT — the caller's own ceiling, in their own units. `Inf` by default: nothing is imposed that
  # the run's parameters do not already imply.
  advective = speed > 0 ? sim.cfl * Δx / speed : sim.cfl * Δx
  conditions = sim.generator.conditions
  diffusivity = sim.state.scalar_spectral === nothing ? conditions.viscosity :
                max(conditions.viscosity, scalar_diffusivity(conditions))
  κ_min = 2π / Float64(sim.domain.grid.domain_size[1])
  resolution = 1 / (diffusivity * κ_min^2)
  return min(advective, resolution, sim.max_dt)
end


"""
    advance!(sim; dt = nothing)

Advance `sim` by one timestep in place and return it.

# Arguments
- `sim` — the [`Simulation`](@ref) to advance.
- `dt = nothing` — pass a value to force a fixed step; `nothing` picks the adaptive step, the
  smallest of the advective-CFL value for the current velocity, the longest mode's diffusive-decay
  time (the same diffusive-decay bound the `Simulation` docstring states), and `max_dt`.

Each call closes the iteration with [`deposit!`](@ref GBGHomogeneousTurbulence.Propagator.deposit!), so
the cache is readable when it returns. It advects the tracers, if any, under the run's chosen particle
integration scheme — first rebuilding the run's
[`ParticleTraversal`](@ref GBGHomogeneousTurbulence.Particles.ParticleTraversal) from the
start-of-step positions when the run was built with `ordered_interpolation = true` (the default
with tracers) — and updates the clock.

Returns `sim`.
"""
function advance!(sim::Simulation; dt = nothing)
  # A step must be positive whichever route set it. `AdamsBashforth` already refuses a non-positive
  # step where it would poison the sample history, but a one-step scheme silently no-ops on `dt = 0`
  # and integrates backwards on a negative one, so the front door checks it for every scheme.
  Δt = dt === nothing ? cfl_timestep(sim) : Float64(dt)
  # Whichever route set it. Checking only the explicit `dt` left the ADAPTIVE branch — the default
  # one — unguarded: a negative `cfl` yields a negative Δt every step, and the integrating factor and
  # the RK stages are algebraically fine with it, so nothing throws, nothing goes NaN, and the run
  # marches BACKWARDS in time. A zero `cfl` freezes the clock while the step counter keeps climbing,
  # so a loop gated on the step count runs forever accumulating no simulated time.
  Δt > 0 ||
    throw(ArgumentError("the timestep must be positive, got $Δt" *
                        (dt === nothing ? " from the adaptive CFL rule (check `cfl`)" : "")))

  # The checked read at the iteration's start: the advance's v₁ must be the velocity sample the previous
  # closing deposit deposited. They are consumed mid-iteration (after the step, as the solver's own scratch), so
  # the epoch is verified here, at tₙ, where they are the current-epoch observable.
  sim.tracers === nothing || velocity_at_particles(sim.cache)

  step!(sim.field_integration_scheme, sim.state, sim.generator, sim.domain, sim.buffers, sim.cache, Δt)

  # The closing deposit: fill every slot, at the new epoch, from the state the step just produced; the tracer
  # push then completes its Heun pair — the head-checked sample as v₁, the just-deposited u(tₙ₊₁)
  # interpolated at the predictor positions as v₂ — and the new sample is recorded at the new
  # positions from the same deposited field, completing the iteration's deposits.
  deposit!(sim.cache, sim.state, sim.domain, sim.buffers)
  if sim.tracers !== nothing
    # The traversal order is rebuilt from the START-of-step positions, before the push: the
    # predictor gather and the closing deposit at the pushed positions both read it, and a step's
    # displacement stays inside the tiles it groups. Under `:manual` the callback owns the cadence.
    traversal = sim.particle_traversal
    (traversal !== nothing && traversal.automatic) && rebuild_traversal!(traversal, sim.domain, sim.tracers)
    advect!(sim.particle_integration_scheme, sim.tracers, velocity_physical(sim.cache), sim.domain,
            sim.particle_buffers, Δt; traversal)
    # `advect!` announced the push itself (decision 76), so the previous sample already reads
    # stale; the closing particle deposit refreshes it at the new positions.
    deposit!(sim.cache, sim.tracers, velocity_physical(sim.cache); traversal)
  end
  check_deposits(sim.cache)

  # The blow-up guard belongs to the ADVANCE, and it belongs AFTER the closing deposit. It lived only
  # inside `cfl_timestep`, so a run driven with a hand-fixed `dt` — the documented way to take a fixed
  # step — never reached it at all. Checking on entry is not enough either: the step that first
  # produces a non-finite field deposits it and returns normally, and only the NEXT call would notice.
  # Here the iteration refuses to report success on a state it has just made non-finite.
  isfinite(max_speed(sim.cache)) ||
    error("non-finite velocity at step $(sim.clock.step + 1): the run appears to have blown up")
  # The state is the PAIR (û, φ̂), and the speed reduces the velocity alone. A passive scalar cannot
  # feed back into the velocity, so a scalar that has gone non-finite leaves the guarded quantity
  # perfectly finite and the iteration reports success on a ruined field. This costs one extra
  # reduction and one readback, and only on a run that carries a scalar.
  sim.state.scalar_spectral === nothing ||
    isfinite(scalar_variance(sim.state.scalar_spectral)) ||
    error("non-finite scalar at step $(sim.clock.step + 1): the run appears to have blown up")

  sim.clock.time += Δt
  sim.clock.step += 1
  return sim
end


# Pure forwarding: the cache does the whole job, including discarding the sample history it owns.
# This exists so a caller holding a run need not reach through it to announce a reposition.
function particles_modified!(sim::Simulation)
  particles_modified!(sim.cache)
  # Dispatch the scheme's own restart rather than relying on the cache's inline clear. They coincide
  # today only because this scheme's history IS the cache's; a scheme carrying registers of its own
  # would need them cleared here, and `Cache` — included before `Particles` — can never reach it.
  sim.particle_buffers === nothing || restart!(sim.particle_integration_scheme, sim.particle_buffers)
  # The unwrapped record restarts at the new positions: winding is a property of the trajectory
  # just abandoned, and a record continued across a reposition would splice two unrelated paths.
  sim.tracers === nothing || sim.tracers.unwrapped_positions === nothing ||
    copyto!(point_positions(sim.tracers.unwrapped_positions), point_positions(sim.tracers.positions))
  return sim
end


# The fields twin, for the same reason its particle counterpart exists: an out-of-band replacement of
# the state invalidates the Lagrangian sample history a multistep particle integration scheme integrates over,
# and the cache form is what discards it. Added because the particle form was and this one was not —
# a caller holding a run should not have to know which of the two verbs happens to have the
# convenience method.
#
# This form also SEES the state, so it is where the conjugate-symmetry contract is enforced (the
# cache form cannot check what it cannot reach). The tolerance is scale-aware: hand-written partners
# computed through different operation orders may disagree at roundoff, which is not a violation;
# an O(1) inconsistency is. `reality_residual` sweeps only the folded axis's self-mirrored planes —
# O(N²), and this verb is out-of-band, never the hot loop.
function fields_modified!(sim::Simulation)
  _check_reality(sim.state.velocity_spectral, "velocity")
  sim.state.scalar_spectral === nothing || _check_reality(sim.state.scalar_spectral, "scalar")
  fields_modified!(sim.cache)
  # Dispatch the scheme's own restart, exactly as the particles twin does: the cache form discards
  # the sample history it owns, but a scheme carrying registers of its own would need them cleared
  # here too, and `Cache` — included before `Particles` — can never reach it.
  sim.particle_buffers === nothing || restart!(sim.particle_integration_scheme, sim.particle_buffers)
  return sim
end

function _check_reality(field, name)
  residual = reality_residual(field)
  scale = maximum(abs, field_data(field))
  T = field_scalar_type(field)
  residual <= sqrt(eps(T)) * scale ||
    throw(ArgumentError("fields_modified!: the $name coefficients are not the spectrum of a real " *
                        "field — the conjugate-symmetry residual is $residual against a field scale " *
                        "of $scale. On the real-to-complex layout the folded axis's zero plane (and " *
                        "its Nyquist plane, for an even grid) stores both members of each " *
                        "conjugate pair, so hand-written coefficients must satisfy " *
                        "f̂(-κ) = conj(f̂(κ)) there; a violation makes every spectral diagnostic " *
                        "silently disagree with the physical field. Repair with " *
                        "`reality_projection!` — the field library's projector onto the nearest " *
                        "real field's spectrum, one or two planes — or fix the write."))
  return nothing
end


# The run form of the rebuild verb (the docstring is the generic's, in `Particles`): the callback's
# handle under `ordered_interpolation = :manual`. A run without an order refuses by name rather than
# silently doing nothing — the caller asked for a cadence the run cannot honour.
function rebuild_traversal!(sim::Simulation)
  sim.particle_traversal === nothing &&
    throw(ArgumentError("this run carries no particle traversal order to rebuild: it was built " *
                        (sim.tracers === nothing ? "without tracers" :
                         "with `ordered_interpolation = false`") *
                        ". Build it with `ordered_interpolation = :manual` to rebuild by hand, " *
                        "or leave the default, which rebuilds every iteration."))
  rebuild_traversal!(sim.particle_traversal, sim.domain, sim.tracers)
  return sim
end


"""
    every_steps(n)

A predicate on a run that is `true` on every `n`-th step — the cadence test a
[`run!`](@ref) callback uses to do something periodically: rebuild the tracer traversal order under
`ordered_interpolation = :manual`, record a spectrum, write a checkpoint.

The argument `n` is the period in steps, a positive integer; the returned function `fires(sim)` is
`true` when [`current_step(sim)`](@ref GBGHomogeneousTurbulence.SimulationRun.current_step) is a multiple of `n` — including at step `0`, the seeded
state `run!` observes first. For a cadence in simulation time use [`every_time`](@ref). The example
passes the callback as a
[`do` block](https://docs.julialang.org/en/v1/manual/functions/#Do-Block-Syntax-for-Function-Arguments).

```julia
rebuild = every_steps(50)
run!(sim) do s
    rebuild(s) && rebuild_traversal!(s)
    current_time(s) < 5.0
end
```
"""
function every_steps(n::Integer)
  n >= 1 || throw(ArgumentError("`every_steps` needs a positive period in steps, got $n"))
  period = Int(n)
  return sim -> current_step(sim) % period == 0
end


"""
    every_time(period)

A predicate on a run that is `true` once each time the run crosses a multiple of `period` in
simulation time — the cadence test a [`run!`](@ref) callback uses to do something at (roughly)
fixed intervals of time under the adaptive step: sample a Lagrangian statistic every so much time,
record a spectrum, rebuild the tracer traversal order under `ordered_interpolation = :manual`.

The argument `period` is the interval in simulation time, positive. The returned function
`fires(sim)` is `true` at the first observation at or past each multiple
``0, \\Delta T, 2\\Delta T, \\ldots`` of the period ``\\Delta T`` — at the seeded state first, since
it lies on ``0`` — so the firing instants land within one step past the multiples, never before
them. A step that jumps over two multiples fires once, not twice, and the next firing is at the next
multiple ahead.

The predicate carries its own record of the next multiple to fire on, so it serves **one** run: make
a fresh one per run. For a cadence in steps use [`every_steps`](@ref). The example passes the
callback as a
[`do` block](https://docs.julialang.org/en/v1/manual/functions/#Do-Block-Syntax-for-Function-Arguments).

```julia
record = every_time(0.25)
run!(sim) do s
    record(s) && push!(spectra, energy_spectrum(s.state.velocity_spectral, s.domain))
    current_time(s) < 5.0
end
```
"""
function every_time(period::Real)
  period > 0 || throw(ArgumentError("`every_time` needs a positive period in simulation time, got $period"))
  return EveryTime(Float64(period), 0.0)
end

# Stateful on purpose: the clock knows only the current time, so "did the run cross a multiple
# since I last fired?" needs a record the predicate keeps itself. `next` is the smallest multiple
# not yet fired on; after firing it jumps PAST the current time, so a step over several multiples
# fires once.
mutable struct EveryTime
  period::Float64
  next::Float64
end

function (fires::EveryTime)(sim::Simulation)
  t = current_time(sim)
  t >= fires.next || return false
  fires.next = (floor(t / fires.period) + 1) * fires.period
  return true
end


"""
    run!(callback, sim; dt = nothing)
    run!(sim; dt = nothing) do sim … end

Observe and advance `sim` until the observation stops it. The second form passes the callback as a
[`do` block](https://docs.julialang.org/en/v1/manual/functions/#Do-Block-Syntax-for-Function-Arguments).

After every iteration — and once at the seeded initial state, before any advance — the `callback`
**observes** the run as `callback(sim)`: it reads the state and the cached observables, records
what it wants, and returns `true` to continue or `false` to stop. Any other return throws an
`ArgumentError`.

Only then does the next iteration run: the timestep from the cached maximum speed, the step, the
tracer advance, and the closing deposits. A run of ``n`` iterations therefore observes ``n + 1``
instants — the first before any step, the last after the final one, with statistics recorded
before the stop.

Stopping is the observation's decision on observables, never a run option. A span of simulation
time compares [`current_time`](@ref) against a target; a step budget compares
[`current_step`](@ref); an eddy-turnover budget accumulates ``\\Delta t \\varepsilon/k`` over each timestep ``\\Delta t`` from the
observables it computes; spin-up to stationarity is the packaged [`StationarityCriterion`](@ref).
Whatever the callback needs beyond the cached observables it computes itself, at its own cadence,
with the exported reductions and recoveries; [`every_steps`](@ref) and [`every_time`](@ref) are
the cadence tests for that.

# Arguments
- `callback` — the observation, called as `callback(sim)`; returns `true` to continue, `false` to
  stop.
- `sim` — the [`Simulation`](@ref) to observe and advance.
- `dt = nothing` — pass a value to force that fixed timestep on every iteration (a code-to-code
  comparison, a convergence study); `nothing` keeps the adaptive step, chosen anew each iteration.

# Examples
```julia
run!(sim) do s
    current_time(s) < 5.0                        # a span of simulation time
end

# record k every iteration; stop at 200 steps
history = Float64[]
run!(sim) do s
    push!(history, kinetic_energy(s.state.velocity_spectral))
    current_step(s) < 200
end

run!(StationarityCriterion(), sim)               # spin up to statistical stationarity
```

Returns `sim`.
"""
function run!(callback, sim::Simulation; dt = nothing)
  while true
    keep = callback(sim)
    keep isa Bool ||
      throw(ArgumentError("the observation callback must return a Bool — true to continue the " *
                          "run, false to stop it; it returned a $(typeof(keep))"))
    keep || break
    advance!(sim; dt)
  end
  return sim
end


# Stationarity detector. Warm-up completes when the running dissipation ``ε(t)`` — and, for a forced
# scalar, the scalar variance ``⟨φ²⟩(t)`` — stop drifting. ε (equivalently enstrophy) is used rather
# than the kinetic energy ``k(t)``, which is clamped flat by constant-energy forcing and rings under
# fixed-injection forcing; the small scales settle last, so a flat ε is the strict indicator. Flatness
# is a two-half-window mean comparison over a trailing window in eddy-turnover units. The strict gate
# is the velocity-derivative skewness S(t) (≈0 for a random-phase field, →−0.5 for a developed
# cascade): a flat S with |S| ≥ skewness_floor marks real turbulence. The transform-heavy skewness is
# sampled only at the storage cadence.
mutable struct StationarityMonitor
  min_turnovers::Float64        # do not test before this (past the start-up overshoot)
  window_turnovers::Float64     # trailing window for the flatness test
  tolerance::Float64                  # relative-drift threshold
  gate_scalar::Bool             # also require ⟨φ²⟩ to be flat
  gate_skewness::Bool               # also require S to have plateaued (and |S| ≥ skewness_floor)
  skewness_floor::Float64           # minimum |S| for a plateau to count as developed turbulence
  sample_gap::Float64           # min turnover spacing between stored samples
  turn::Vector{Float64}
  eps::Vector{Float64}
  phi2::Vector{Float64}
  skew::Vector{Float64}
  converged::Bool
end

StationarityMonitor(; min_turnovers, window_turnovers, tolerance, gate_scalar, gate_skewness, skewness_floor) =
  StationarityMonitor(Float64(min_turnovers), Float64(window_turnovers), Float64(tolerance),
                      gate_scalar, gate_skewness, Float64(skewness_floor), Float64(window_turnovers) / 40,
                      Float64[], Float64[], Float64[], Float64[], false)

# No net drift of the series y(turn) across the trailing window [now−W, now]:
# |mean(2nd half) − mean(1st half)| / |mean| < tolerance.
function _is_flat(turn, y, now, W, tolerance)
  mid = now - W / 2
  s1 = 0.0; n1 = 0; s2 = 0.0; n2 = 0
  @inbounds for i in eachindex(turn)
    turn[i] < now - W && continue
    if turn[i] < mid
      s1 += y[i]; n1 += 1
    else
      s2 += y[i]; n2 += 1
    end
  end
  (n1 == 0 || n2 == 0) && return false
  mean_all = (s1 + s2) / (n1 + n2)
  abs(mean_all) < 1e-30 && return true
  return abs(s2 / n2 - s1 / n1) / abs(mean_all) < tolerance
end

# Mean of the series `y(turn)` over the trailing window `[now-W, now]`.
function _window_mean(turn, y, now, W)
  s = 0.0; n = 0
  @inbounds for i in eachindex(turn)
    turn[i] < now - W && continue
    s += y[i]; n += 1
  end
  return n == 0 ? 0.0 : s / n
end

# Downsample-store the signals at `elapsed_turn` and report whether warm-up is complete (the testable
# core — takes precomputed signals).
function _push_and_test!(m::StationarityMonitor, elapsed_turn, ε, φ2, S)
  if isempty(m.turn) || elapsed_turn - m.turn[end] ≥ m.sample_gap
    push!(m.turn, elapsed_turn); push!(m.eps, ε); push!(m.phi2, φ2); push!(m.skew, S)
    while length(m.turn) > 2 && m.turn[1] < elapsed_turn - m.window_turnovers - m.sample_gap
      popfirst!(m.turn); popfirst!(m.eps); popfirst!(m.phi2); popfirst!(m.skew)
    end
  end
  elapsed_turn ≥ m.min_turnovers || return false
  m.turn[1] ≤ elapsed_turn - m.window_turnovers || return false
  flat_v = _is_flat(m.turn, m.eps, elapsed_turn, m.window_turnovers, m.tolerance)
  flat_s = !m.gate_scalar || _is_flat(m.turn, m.phi2, elapsed_turn, m.window_turnovers, m.tolerance)
  flat_k = !m.gate_skewness ||
           (_is_flat(m.turn, m.skew, elapsed_turn, m.window_turnovers, m.tolerance) &&
            abs(_window_mean(m.turn, m.skew, elapsed_turn, m.window_turnovers)) ≥ m.skewness_floor)
  m.converged = flat_v && flat_s && flat_k
  return m.converged
end

# Compute the signals from `sim` (only when a sample is due — the skewness inverse-transforms a
# NINE-component rank-2 field, and is the only observation here that does) and test.
function _observe_and_test!(m::StationarityMonitor, sim, elapsed_turn, ε)
  (isempty(m.turn) || elapsed_turn - m.turn[end] ≥ m.sample_gap) || return false
  φ2 = m.gate_scalar ? (sim.state.scalar_spectral === nothing ? NaN : scalar_variance(sim.state.scalar_spectral)) : 0.0
  S = m.gate_skewness ? derivative_skewness(sim.state.velocity_spectral, sim.domain) : 0.0
  return _push_and_test!(m, elapsed_turn, ε, φ2, S)
end

_scalar_forced(sim::Simulation) = sim.state.scalar_spectral !== nothing && !(sim.generator.conditions.scalar_forcing isa NoForcing)


"""
    StationarityCriterion(; gate_scalar = true, gate_skewness = false,
                            min_turnovers = 5, window_turnovers = 4, tolerance = 0.05,
                            skewness_floor = 0.1, max_turnovers = 60)

The packaged spin-up observation for [`run!`](@ref): a callback that watches the run settle into
statistical stationarity and stops it there — `run!(StationarityCriterion(), sim)` is the detecting
spin-up, and [`warmup!`](@ref) is the one-line shorthand for exactly that call. Use it before measurement on any freshly
seeded **forced** run. A freely decaying run (`NoForcing()`) has no stationary state to detect — its
``\\varepsilon`` never plateaus — so the criterion can only run to `max_turnovers` and warn; give a
decaying run a fixed-length loop instead, which is a three-line callback (see `run!`).

At each iteration it measures the dissipation ``\\varepsilon`` and the kinetic energy ``k``, accumulates
the eddy-turnover clock ``\\Delta t \\varepsilon/k`` over the timestep ``\\Delta t``, and tests ``\\varepsilon`` for flatness over a
trailing window; it stops the run when every gate holds, or gives up with a warning at
`max_turnovers`. The gate reads ``\\varepsilon`` alone: the small scales settle last, so a flat
``\\varepsilon`` is the strict indicator — where ``k`` is whatever the forcing shapes: clamped by a
rescale, driven toward its target by a controller, ringing under fixed injection — so its
flatness would certify the forcing, not the flow.

# Arguments
- `gate_scalar` — when the run's scalar is forced, also require the scalar variance
  ``\\langle\\varphi^2\\rangle`` to be flat (the scalar settles after the velocity; an unforced
  scalar has no stationary state and is never gated).
- `gate_skewness` — also require the velocity-derivative skewness ``S`` to have plateaued **and** reached
  ``\\lvert S\\rvert \\ge \\texttt{skewness\\_floor}`` — the "real turbulence yet" signal, exactly as
  strict as its floor (see `skewness_floor` below): a
  random-phase field starts at ``S \\approx 0`` and only a developed cascade reaches
  ``S \\approx -0.5``. It is **off by default**, and turning it on is the stricter spin-up: the
  ``\\varepsilon`` gate alone can be satisfied by a field whose cascade is not yet developed, so a
  run whose measurement depends on the small scales should set it. The cost is why it is not the
  default — the skewness is the only observation here that transforms a rank-2 field, nine
  component transforms and a per-call tensor allocation larger than the resident working set (see
  [`derivative_skewness`](@ref GBGHomogeneousTurbulence.Observables.derivative_skewness)). When it
  is on, the skewness is measured on the criterion's own sampling interval — one
  sample per `window_turnovers / 40` of turnover time, giving about forty samples across the
  trailing window — rather than every iteration.
- `min_turnovers`, `window_turnovers`, `tolerance` — do not test before `min_turnovers` eddy-turnover
  times (past the start-up overshoot); flatness is a two-half-window mean comparison over the
  trailing `window_turnovers`, relative drift below `tolerance`.
- `skewness_floor` — the minimum ``\\lvert S\\rvert`` for a plateau to count as developed turbulence.
  The default `0.1` is a **floor against a random-phase field**, which starts at ``S \\approx 0``; it
  is a fifth of the ``\\lvert S\\rvert \\approx 0.5`` of a developed cascade, so clearing it means
  "no longer Gaussian", not "fully developed". Raise it toward `0.4` when the run's statistics
  depend on the cascade being mature.
- `max_turnovers` — the give-up cap: reaching it stops the run with a warning rather than spinning
  forever.

The criterion carries its own observation state (the sampled signals and the turnover clock), so
build a fresh one per run.

# Fields
The fields are not the keywords: `gate_skewness`, `min_turnovers`, `window_turnovers`, `tolerance` and
`skewness_floor` all live inside `monitor`, which holds the sampled series together with the thresholds
that judge them. Build one through the keyword constructor above.
- `monitor` — the sampled signal series (``\\varepsilon``, the scalar variance, the skewness — not
  ``k``, which this criterion deliberately never gates on), each recorded against the turnover
  clock's readings, and the gate settings and tolerances that test them.
- `max_turnovers` — the give-up cap.
- `gate_scalar` — the requested scalar gate (applied only when the run's scalar is forced).
- `elapsed_turn`, `last_time`, `started` — the turnover clock itself: the accumulated turnovers,
  the instant last read, and whether the clock has started.
"""
mutable struct StationarityCriterion
  const monitor::StationarityMonitor
  const max_turnovers::Float64
  const gate_scalar::Bool
  elapsed_turn::Float64
  last_time::Float64
  started::Bool
end

function StationarityCriterion(; gate_scalar::Bool = true, gate_skewness::Bool = false,
                               min_turnovers::Real = 5, window_turnovers::Real = 4,
                               tolerance::Real = 0.05, skewness_floor::Real = 0.1,
                               max_turnovers::Real = 60)
  monitor = StationarityMonitor(; min_turnovers, window_turnovers, tolerance,
                                gate_scalar, gate_skewness = gate_skewness, skewness_floor)
  return StationarityCriterion(monitor, Float64(max_turnovers), gate_scalar, 0.0, NaN, false)
end

# Display (the convention is stated once, at `SimulationDomain`'s display section). The monitor's
# sample histories grow with the run, so it prints its settings and the count of samples banked,
# never the series; the criterion nests it and adds its own cap and progress.
function Base.show(io::IO, monitor::StationarityMonitor)
  print(io, "StationarityMonitor(min_turnovers ", monitor.min_turnovers, ", window_turnovers ",
        monitor.window_turnovers, ", tolerance ", monitor.tolerance, ", gate_scalar ", monitor.gate_scalar,
        ", gate_skewness ", monitor.gate_skewness, ", skewness_floor ", monitor.skewness_floor,
        ", ", length(monitor.turn), " samples", monitor.converged ? ", converged" : "", ")")
end

function Base.show(io::IO, criterion::StationarityCriterion)
  print(io, "StationarityCriterion(", criterion.monitor, ", max_turnovers ", criterion.max_turnovers)
  print(io, criterion.started ? ", elapsed_turnovers $(criterion.elapsed_turn)" : ", not started", ")")
end

function (criterion::StationarityCriterion)(sim::Simulation)
  if !criterion.started
    # The scalar gate binds only when the run's scalar is forced — resolved at the first observation,
    # where the criterion first sees the run it observes.
    criterion.monitor.gate_scalar = criterion.gate_scalar && _scalar_forced(sim)
    criterion.last_time = current_time(sim)
    criterion.started = true
  end
  # The clock's pair (k, ε) rides ONE fused traversal — one device readback per iteration, not two.
  k, ε = kinetic_energy_and_dissipation(sim.state.velocity_spectral, sim.domain,
                                        sim.generator.conditions.viscosity)
  Δt = current_time(sim) - criterion.last_time
  criterion.last_time = current_time(sim)
  if ε > 0
    criterion.elapsed_turn += Δt * ε / Float64(k)
  else
    # No dissipation means no eddy-turnover clock, and `max_turnovers` is denominated in exactly the
    # units that have stopped advancing — so the give-up cap below could never be reached and the
    # loop would run forever. A run that is not dissipating also cannot reach the developed cascade
    # this criterion tests for, so the honest outcome is to stop and say why.
    @warn "StationarityCriterion: the dissipation rate is not positive (ε = $ε), so the " *
          "eddy-turnover clock cannot advance and stationarity can never be detected — " *
          "stopping. A run with no dissipation has no cascade to become stationary."
    return false
  end
  _observe_and_test!(criterion.monitor, sim, criterion.elapsed_turn, ε) && return false
  if criterion.elapsed_turn ≥ criterion.max_turnovers
    @warn "StationarityCriterion: hit the max_turnovers = $(criterion.max_turnovers) cap without detecting stationarity"
    return false
  end
  return true
end


"""
    warmup!(sim; dt = nothing, kwargs...)

A one-line shorthand, and nothing more: `warmup!(sim; dt, kwargs...)` is exactly

```julia
run!(StationarityCriterion(; kwargs...), sim; dt)
```

— it spins `sim` up to a statistically stationary state before measurement and returns it, by
running `run!`'s loop, which observes the seeded state and then each completed iteration, with the
packaged stationarity observation. For a fixed spin-up
budget, write the three-line budget callback instead (see [`run!`](@ref)).

# Arguments
- `sim` — the run.
- `dt = nothing` — `run!`'s: a value forces that fixed timestep, `nothing` keeps the adaptive step.
- `kwargs...` — every other keyword, passed through to [`StationarityCriterion`](@ref) untouched
  ([keyword arguments](https://docs.julialang.org/en/v1/manual/functions/#Keyword-Arguments)); its
  docstring is the home for what is detected (the flat dissipation, the scalar-variance and
  derivative-skewness gates, the give-up cap) and for every option.

# Examples
```julia
warmup!(sim)                         # detect stationarity on the ε-plateau gate
# also require a developed cascade (stricter, and costlier)
warmup!(sim; gate_skewness = true)
```

Returns `sim`.
"""
warmup!(sim::Simulation; dt = nothing, kwargs...) =
  run!(StationarityCriterion(; kwargs...), sim; dt)




# ————————————————————————————————————————————————————————————————————————————————————————————————
# HDF5 persistence. The bare generics live here so the docstrings and the docs build work without
# HDF5 in the environment; the methods live in the `GBGHomogeneousTurbulenceHDF5Ext` weak-dependency
# extension, loaded automatically alongside the HDF5 package (the arrangement the field library's
# persistence pairs established).

export write_simulation, read_simulation


"""
    write_simulation(parent::HDF5.H5DataStore, name::AbstractString, sim::Simulation)

Checkpoint the run: write everything needed to restore `sim` (a [`Simulation`](@ref)) as one
self-describing HDF5 group — the domain's parameters, the state in spectral representation, the
tracer set, both forcing strategies, the Lagrangian sample history a multistep particle
integration scheme integrates over, the scheme and timestep settings, and the clock. Nothing
derivable is stored: the physical-representation observables, the current velocity sample, and
every per-step buffer and transform plan are recomputed on read. A stochastic forcing's evolving
state is part of the run's state and is stored with it, so continuation is exact for every forcing.

Available once the `HDF5` package is loaded; opening and closing the file is the caller's job,
and `parent[name] = sim` is equivalent sugar.

# Arguments
- `parent` — the open HDF5 file or group to write under.
- `name` — the created group's name.
- `sim` — the run to checkpoint.

Returns the created group. Restore with [`read_simulation`](@ref).
"""
function write_simulation end


"""
    read_simulation(parent::HDF5.H5DataStore, name::AbstractString;
                    array_family = Array, ordered_interpolation = nothing) -> Simulation

Restore a run from the group [`write_simulation`](@ref) wrote. The [`Simulation`](@ref) is rebuilt
through its own constructor from the recorded parameters, adopting the stored state rather than
seeding one; the positions, the deposited observables, the Lagrangian sample history (a scheme
of a different order keeps what fits and takes the missing first pushes under [`Heun`](@ref GBGHomogeneousTurbulence.Particles.Heun)) and the clock follow. The
next [`advance!`](@ref) continues the run, a stochastic forcing's realization included.

A group not written by `write_simulation`, or written by a newer schema version, is refused with an
`ArgumentError`. Available once the `HDF5` package is loaded.

# Arguments
- `parent` — the open HDF5 file or group holding the checkpoint group.
- `name` — the group's name.
- `array_family = Array` — the storage backend the restored run lives on; the reader names it, so a
  checkpoint written on one backend loads on any other.
- `ordered_interpolation = nothing` — the tracer traversal-order setting of the restored run,
  forwarded to `Simulation`. The order is a derived accelerator, not state: nothing of it is
  stored, and the restored run rebuilds it from the restored positions under whatever setting the
  reader names.
"""
function read_simulation end


end # module SimulationRun
