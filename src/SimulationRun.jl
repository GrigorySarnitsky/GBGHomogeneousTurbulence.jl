# SimulationRun — the ergonomic run layer. A `Simulation` bundles the domain, buffers, the
# generator (the equations of motion with their conditions and assembly scratch), the scheme, the
# spectral state (û, φ̂), the observables cache, and any tracers;
# `advance!`/`run!`/`warmup!` own the CFL-adaptive time loop. It holds no physics or numerics of its
# own — it wires the pieces of SimulationDomain/State/Generator/Observables/Forcing/Propagator/Particles
# so a case is a few lines to set up and run, warm-up included, while every piece stays reachable for a
# hand-run loop.
#
# The observables cache is deposit-driven (no recompute anywhere): `advance!` runs `step!`, then the
# closing `deposit!` recovers the iteration's observables into the cache at the new epoch, and the deposit-
# completeness check closes the iteration. The timestep choice reads the cached maximum speed — scalar
# arithmetic, no grid pass. The tracer advance is Heun on the two endpoint velocities: v₁ is the
# particle velocities the PREVIOUS closing deposit left (read checked), v₂ interpolates the just-deposited
# u(tₙ₊₁) at the predictor positions, and the new sample is recorded at the new positions from the
# same field, completing the iteration's deposits; only M-sized point values are held, never a second field copy.

"""
    SimulationRun

The run layer:
- [`Simulation`](@ref) — the assembled state of a case.
- [`advance!`](@ref), [`run!`](@ref) — advance one iteration; observe and advance until the
  callback stops the run (the callback *is* the observation — the function the loop calls to read the run each
  iteration — and its return decides continuation).
- [`StationarityCriterion`](@ref), [`warmup!`](@ref) — the packaged spin-up-to-stationarity
  observation, and `warmup!`, the one-line shorthand that runs it.
- [`current_time`](@ref), [`current_step`](@ref) — the elapsed time and step count.
- [`flow_parameters`](@ref) — the run's measured flow state as a `Phenomenology` `FlowParameters`.

Read a run's state through `sim.state` and its deposited observables through `sim.cache`, with the
observables and cache accessors that own them; the run layer adds no forwarding methods of its own.
"""
module SimulationRun

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, new_vector_field_spectral, new_scalar_field_spectral, new_vector_field_physical,
                          DealiasingStrategy, TwoThirds, max_wavenumber
using ..State: ResolvedFields, random_solenoidal_velocity_spectral!, random_scalar_spectral!
using ..Cache: ObservablesCache, particles_modified!, check_deposits, deposit_sample!, advance_particles_epoch!,
               velocity_physical, max_speed, particle_velocities
using ..Observables: kinetic_energy, dissipation, scalar_variance, scalar_dissipation, energy_spectrum,
                     integral_scale, derivative_skewness
using ..Forcing: AbstractForcing, NoForcing, BandRescaling
using ..Generator: FlowConditions, ResolvedGenerator
using ..Propagator: AbstractIntegrator, IntegratorBuffers, allocate_buffers, step!,
                    recommended_cfl, IFLowStorageRK3
import ..Propagator: deposit!
using ..Particles: Tracers, AbstractParticleIntegrator, EndpointHeun, record_particle_velocities!, advect!,
                   restart!, history_depth
using ..Phenomenology: FlowParameters
using ..Phenomenology.Spectra: EnergySpectrum, spectrum
using ..Phenomenology.Scalings: Li2008, stationary_dissipation

export Simulation, advance!, run!, warmup!, StationarityCriterion,
       current_time, current_step, flow_parameters


mutable struct Clock
  time::Float64
  step::Int
end


"""
    Simulation(; grid_points_per_axis, κ_max_η = nothing, kinetic_energy = 1.5,
                 side_length = 2π, element_type = Float64, array_type = Array,
                 dealiasing = TwoThirds(), kwargs...)
    Simulation(domain; κ_max_η = nothing, kinetic_energy = 1.5, kwargs...)

A ready-to-run case: the [`FixedDomain`](@ref), the [`IntegratorBuffers`](@ref), the
[`ResolvedGenerator`](@ref) (the equations of motion, carrying the [`FlowConditions`](@ref) and the
assembly scratch), the chosen scheme, the [`ResolvedFields`](@ref) state (the velocity
``\\hat{\\boldsymbol{u}}`` and passive scalar ``\\hat\\varphi`` in spectral representation), the
[`ObservablesCache`](@ref) holding what the last iteration deposited, any [`Tracers`](@ref), and a
clock.

The first form is the **front door**: from `grid_points_per_axis` and `side_length` it builds every
piece with sensible defaults, seeds a divergence-free velocity (and, with `scalar = true`, a
mean-zero scalar ``\\varphi``), and returns a `Simulation` at ``t = 0``. The second takes a
`FixedDomain` you built yourself.

Advance it with [`advance!`](@ref) / [`run!`](@ref) / [`warmup!`](@ref). Read its measured state by
applying the observables to `sim.state` (e.g. `kinetic_energy(sim.state.velocity_spectral)`) or
through the cache's deposited observables (`velocity_physical(sim.cache)`); summarize it with
[`flow_parameters`](@ref), and track its progress with [`current_time`](@ref) /
[`current_step`](@ref).

# Setting the Reynolds number

By default the run is **forced and stationary** — a
[`BandRescaling`](@ref GBGIsotropicTurbulence.Forcing.BandRescaling) holds the whole-field kinetic
energy at the value given by the
[`kinetic_energy`](@ref GBGIsotropicTurbulence.Observables.kinetic_energy) keyword (`over = :total`)
— and the viscosity is
chosen from the grid rather than supplied:

# Arguments

All keyword except `domain` (below). The ones marked *(front door only)* configure the `FixedDomain` and are consumed by the first form;
the rest are forwarded to the `Simulation(domain; …)` form.

- `grid_points_per_axis` — the number of grid points ``N`` along each side (front door only); required.
- `domain` — a pre-built `FixedDomain`. This one is **positional**, not a keyword: it is the
  argument of the second form, `Simulation(domain; …)` (the front door builds one for you from
  `grid_points_per_axis`, `side_length`, `dealiasing`, `element_type`, `array_type`).
- `κ_max_η` — the resolution criterion ``\\kappa_{\\max}\\eta`` used to set ``\\nu`` in grid mode;
  ``\\ge 1.5`` is well-resolved, higher trades Reynolds number for margin. It defaults to `nothing`
  and grid mode then uses `2`; the sentinel is what lets the constructor tell an omitted keyword from
  an explicit one, so that giving both it and `viscosity` is an error rather than a silent drop.
- `viscosity` — the kinematic viscosity ``\\nu``, which is how the Reynolds number is set (it is
  ``1/\\nu`` only in units where ``u' = L = 1``; measure ``\\mathrm{Re}_\\lambda`` for the run's actual value); omit for grid mode.
- `kinetic_energy = 1.5` — the initial, and when forced the held, kinetic energy ``k``; `1.5` gives
  an r.m.s. velocity ``u' = \\sqrt{2k/3} = 1``.
- `side_length = 2π` — the box side ``L`` (front door only).
- `element_type = Float64`, `array_type = Array` — the real element type and storage backend (front door only).
- `dealiasing = TwoThirds()` — the [`DealiasingStrategy`](@ref) (``2/3`` sharp, `HouLi` smooth, or
  `PhaseShift`); it sets ``\\kappa_{\\max}`` and hence the CFL step (front door only).
- `schmidt = 1.0` — the Schmidt number ``\\mathrm{Sc}`` (scalar diffusivity ``\\varkappa = \\nu/\\mathrm{Sc}``).
- `velocity_forcing`, `scalar_forcing` — an [`AbstractForcing`](@ref) (or a
  [`DeferredForcing`](@ref GBGIsotropicTurbulence.Forcing.DeferredForcing) from an
  operator-free constructor); `velocity_forcing` defaults to a `BandRescaling` holding the total
  (whole-field) energy at the value given by the `kinetic_energy` keyword (`over = :total`), and
  `scalar_forcing` to `NoForcing()`. The
  velocity and scalar are forced independently.
- `scalar = false`, `scalar_variance = 1.0` — whether to evolve a passive scalar (a mean-zero
  ``\\varphi``), and its initial variance.
- `envelope_wavenumber = 2.0` — the large-scale envelope wavenumber ``\\kappa_p`` of the initial
  condition, for the **velocity and the scalar alike** (each shell-summed spectrum peaks at
  ``\\kappa_p/\\sqrt{2}``); it does **not** shape the profile when `initial_spectrum` is given (the model does), but it still
  sets the integral scale of the *assumed state* that model is evaluated at.
- `initial_spectrum = nothing` — draw the initial velocity from a
  [`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology) `EnergySpectrum` (say
  `VonKarman1948()`) instead of the default large-scale Gaussian. A model spectrum needs a flow
  state, and at ``t = 0`` there is nothing measured yet, so one is *assumed* — a stand-in state, not a measurement of the field about to be seeded, so its
  integral scale is `1/envelope_wavenumber` rather than the ``L_{11}`` the seeded field will have:
  ``\\varepsilon`` from the
  `Li2008` stationary-dissipation law at the requested `kinetic_energy` and box side, ``u'`` from
  that same energy, ``\\nu`` as resolved above, and the integral scale as `1/envelope_wavenumber`.
  The seeded field is then normalized to `kinetic_energy`, so the model fixes the *shape* and the
  assumed state only positions it. This shapes the **velocity** only; a scalar is always seeded from
  the default Gaussian envelope, and a scalar-spectrum initial condition is reached by calling
  [`random_scalar_spectral!`](@ref GBGIsotropicTurbulence.State.random_scalar_spectral!) on the
  built run and announcing the change with
  [`fields_modified!`](@ref GBGIsotropicTurbulence.Cache.fields_modified!).
- `scheme = IFLowStorageRK3()`, `cfl = recommended_cfl(scheme, domain)` — the
  [`AbstractIntegrator`](@ref) scheme and its advective-CFL ceiling (adapts to `dealiasing`).
- `number_of_particles = 0`, `interpolation_scheme = CatmullRom` — the number of Lagrangian `Tracers` and
  the **spatial** scheme that evaluates a field at their positions, forwarded to the `Tracers`
  constructor as its `interpolation_scheme`.
- `trajectory_scheme = EndpointHeun()` — the scheme that advances the trajectories in time, an
  [`AbstractParticleIntegrator`](@ref GBGIsotropicTurbulence.Particles.AbstractParticleIntegrator);
  its **registers** — the per-step scratch that scheme needs, meaningless to read between calls —
  are allocated for you. Pass
  [`AdamsBashforth`](@ref GBGIsotropicTurbulence.Particles.AdamsBashforth)`()` when trajectory
  accuracy in time limits a measurement: it costs one stored array per extra order and saves an
  interpolation per step.
- `rng` — the random stream for the initial condition and the tracer seeding (defaults to
  `Random.default_rng()`).

!!! note "The default holds the kinetic energy fixed, so it is not a measurable of the default run"
    `BandRescaling` is a deterministic clamp: it rescales the band every step to hold the kinetic
    energy at the target **value**, which pins ``u'`` (hence the scale of ``\\mathrm{Re}_\\lambda``) and
    suppresses the physical fluctuation of the quantity it holds. For fluctuation statistics of the *held* quantity, force with fixed injection
    ([`ConstantPower`](@ref GBGIsotropicTurbulence.Forcing.ConstantPower)) instead and let ``k`` find its own level.

  * **Grid mode** (no `viscosity`): the constructor picks the highest Reynolds number consistent with
    the resolution criterion `κ_max_η`, in two steps.

    First it estimates the dissipation the box sustains, from the box-normalized law `Li2008` (in
    `Phenomenology.Scalings`): ``\\varepsilon = (k/G)^{3/2}/L``, with `kinetic_energy` the energy
    ``k``, `side_length` the side ``L``, and ``G \\approx 0.9`` a dimensionless constant. ``G``
    carries ``C_\\varepsilon^{-2/3}`` and the ratio ``L_{11}/L``, and that ratio is set by *where* a
    run is forced — so the estimate assumes forcing in the same low shells as the runs it was
    calibrated on, and a forcing moved higher invalidates it.

    Then it sets ``\\nu`` so that ``\\kappa_{\\max}\\eta`` equals `κ_max_η`, with
    ``\\kappa_{\\max}`` the [`max_wavenumber`](@ref) and ``\\eta`` the Kolmogorov microscale. Since
    ``\\kappa_{\\max}\\eta = f\\pi\\eta/\\Delta x`` with ``f`` the retained-Nyquist fraction,
    `κ_max_η = 2` gives ``\\Delta x \\approx \\eta`` under the default ``2/3`` rule.

    !!! note "The criterion is not equally strict across dealiasing strategies"
        It treats the whole retained band as clean signal — exact for `TwoThirds` and
        [`PhaseShift`](@ref GBGIsotropicTurbulence.SimulationDomain.PhaseShift), approximate for
        [`HouLi`](@ref GBGIsotropicTurbulence.SimulationDomain.HouLi), whose top of band is damped
        rather than dealiased. The gap is not cosmetic: ``f = 1`` puts
        ``\\eta \\approx 0.64\\,\\Delta x`` at `κ_max_η = 2` against ``0.96\\,\\Delta x`` for ``2/3``,
        and since ``\\nu \\propto f^{-4/3}`` that hands `HouLi` a ``\\mathrm{Re}_\\lambda`` about 31%
        higher on the same grid. Raise `κ_max_η` when comparing across strategies.

    The grid and `κ_max_η` together fix ``\\mathrm{Re}_\\lambda \\sim N^{2/3}``; `kinetic_energy` and
    `side_length` fix the units. The chosen ``\\nu``, ``\\varepsilon`` and ``\\mathrm{Re}_\\lambda``
    are logged.

    One precondition: the choice is self-consistent only if the run really holds ``k`` at
    `kinetic_energy`, which the front door's `BandRescaling(over = :total)` guarantees and `:band`
    does not. Give the velocity a forcing that lets ``k`` float and the ``\\nu`` chosen here no
    longer matches the run.

  * **Explicit mode**: pass `viscosity` and it is used directly; the two are alternatives, and
    passing both raises an `ArgumentError` rather than dropping one — for a decaying
    run (`velocity_forcing = NoForcing()`) or manual control. Grid mode is calibrated on a *stationary
    forced* balance (`Li2008`'s ``G`` is fitted to forced-isotropic DNS), so a decaying run should set
    ``\\nu`` explicitly: the resolution it buys is only meaningful while the box sustains the energy the
    law assumes.
# Examples
The two ways in, and the two ways to set the Reynolds number:

```julia
# Grid mode — a 128³ forced-stationary run, ν set from the resolution criterion:
sim = Simulation(grid_points_per_axis = 128)

# Explicit mode — set ν directly, carry a passive scalar, force at constant power:
sim = Simulation(grid_points_per_axis = 128, viscosity = 1e-2;
                 scalar = true, velocity_forcing = ConstantPower(injection_rate = 0.1))

# Domain-first — build the frame yourself, then hand it to the second form:
domain = FixedDomain(; grid_points_per_axis = 128, side_length = 2π, dealiasing = HouLi(),
                     element_type = Float64, array_type = Array)
sim = Simulation(domain; viscosity = 1e-2)
```

# Fields
Three of these are what a user reads — `state`, `cache`, and `tracers`. The rest are the machinery the step runs
on: they hold partial values while a step is in flight, so read them only between steps, and treat
their contents as the scheme's business rather than the run's state.

- `state` — the `ResolvedFields` (the evolving `û`, `φ̂`).
- `cache` — the `ObservablesCache`: the observables the iteration deposits at its end.
- `domain`, `buffers`, `generator`, `scheme` — the `FixedDomain`, `IntegratorBuffers`,
  the `ResolvedGenerator` (whose `conditions` field is the run's `FlowConditions`), and
  the chosen scheme.
- `tracers`, `trajectory_scheme`, `particle_buffers` — the `Tracers` being advected along with the
  fields, the scheme advancing them along their trajectories, and that scheme's registers. All `nothing` when the run carries no tracers.
- `cfl`, `clock` — the advective-CFL coefficient, and the time/step counter.
"""
struct Simulation{DOM, FB, IG, GN<:ResolvedGenerator, RF, DF, TR, PI, PB}
  domain::DOM
  buffers::FB
  generator::GN            # ResolvedGenerator: the equations of motion + conditions + assembly scratch
  scheme::IG
  state::RF                # ResolvedFields: the evolving (û, φ̂), the single source of truth
  cache::DF                # ObservablesCache: what the last iteration deposited, for an observation to read
  tracers::TR              # Tracers, or nothing — trajectory STATE only
  trajectory_scheme::PI  # AbstractParticleIntegrator, or nothing
  particle_buffers::PB     # ParticleIntegratorBuffers for that scheme, or nothing
  cfl::Float64
  clock::Clock
end


# A forcing may be given ready-built (an `AbstractForcing`) or as a factory `domain -> AbstractForcing`
# — the latter lets a banded forcing be named before the domain exists (`domain -> ConstantPower(domain;
# injection_rate)`), since a forcing precomputes its band from `domain`.
_materialize_forcing(f::AbstractForcing, ::FixedDomain) = f
_materialize_forcing(f, domain::FixedDomain) = f(domain)


function Simulation(domain::FixedDomain;
                    kinetic_energy::Real = 1.5, κ_max_η = nothing, viscosity = nothing,
                    schmidt::Real = 1.0,
                    velocity_forcing = BandRescaling(domain; target = kinetic_energy, over = :total),
                    scalar_forcing = NoForcing(),
                    scheme::AbstractIntegrator = IFLowStorageRK3(),
                    cfl::Real = recommended_cfl(scheme, domain),
                    scalar::Bool = false, scalar_variance::Real = 1.0,
                    envelope_wavenumber::Real = 2.0, initial_spectrum = nothing,
                    number_of_particles::Integer = 0, interpolation_scheme = CatmullRom,
                    trajectory_scheme::AbstractParticleIntegrator = EndpointHeun(),
                    rng = Random.default_rng())
  # The stationary dissipation the box sustains (`Li2008`) — a modeled estimate, not a measurement.
  # It sets ν in grid mode and shapes a `Phenomenology` `initial_spectrum`.
  side_length = domain.grid.domain_size[1]
  ε = stationary_dissipation(Li2008(), kinetic_energy, side_length)
  # Both arguments set ν, by different routes, so accepting both would silently honour one of them.
  if !isnothing(viscosity) && !isnothing(κ_max_η)
    throw(ArgumentError("`viscosity` and `κ_max_η` are two ways to set ν — `viscosity` fixes it \
directly, `κ_max_η` derives it from the grid. Pass one, not both."))
  end
  if isnothing(viscosity)                                    # grid mode: highest Re the grid resolves
    resolution = isnothing(κ_max_η) ? 2 : κ_max_η
    ν = ε^(1//3) * (resolution / max_wavenumber(domain))^(4//3)
    reλ = (2 * kinetic_energy / 3) * sqrt(15 / (ε * ν))
    @info "Simulation: grid-resolved at κ_max·η = $(resolution)" viscosity=ν dissipation=ε Re_λ=reλ
  else
    ν = Float64(viscosity)
  end

  buffers = allocate_buffers(scheme, domain; scalar)
  conditions = FlowConditions(; viscosity = ν, schmidt,
                    velocity_forcing = _materialize_forcing(velocity_forcing, domain),
                    scalar_forcing = _materialize_forcing(scalar_forcing, domain))

  state = ResolvedFields(domain; scalar)
  ic_spectrum = nothing
  if initial_spectrum isa EnergySpectrum       # a `Phenomenology` model → evaluate at the run's state
    fp = FlowParameters(; viscosity = ν, dissipation = ε, rms_velocity = sqrt(2 * kinetic_energy / 3),
                        integral_scale = inv(envelope_wavenumber), schmidt)
    ic_spectrum = κ -> spectrum(initial_spectrum, κ, fp)
  elseif !isnothing(initial_spectrum)
    ic_spectrum = initial_spectrum             # a raw κ -> E(κ) function
  end
  random_solenoidal_velocity_spectral!(state.velocity_spectral, domain; kinetic_energy, envelope_wavenumber, initial_spectrum = ic_spectrum, rng)
  scalar && random_scalar_spectral!(state.scalar_spectral, domain; scalar_variance, envelope_wavenumber, rng)

  tracers = number_of_particles > 0 ?
    Tracers(domain; number_of_particles, interpolation_scheme = interpolation_scheme, rng) : nothing
  # The cache is built first: it carries the Lagrangian sample history a multistep trajectory scheme
  # integrates over, so the scheme's registers are allocated against it.
  cache = ObservablesCache(domain; scalar,
                           particle_velocities = tracers === nothing ? nothing : tracers.particle_velocities,
                           history_depth = history_depth(trajectory_scheme))
  particle_buffers = tracers === nothing ? nothing :
                     allocate_buffers(trajectory_scheme, tracers, cache)
  deposit!(cache, state, domain, buffers)        # the seeding deposit: the first instant observed is t₀
  tracers === nothing ||
    (record_particle_velocities!(tracers, velocity_physical(cache)); deposit_sample!(cache))
  return Simulation(domain, buffers, ResolvedGenerator(domain, conditions; scalar), scheme, state, cache,
                    tracers, tracers === nothing ? nothing : trajectory_scheme, particle_buffers,
                    Float64(cfl), Clock(0.0, 0))
end

function Simulation(; grid_points_per_axis::Integer, side_length::Real = 2π,
                    element_type::Type = Float64, array_type = Array,
                    dealiasing::DealiasingStrategy = TwoThirds(), kwargs...)
  return Simulation(FixedDomain(; grid_points_per_axis, side_length, dealiasing, element_type, array_type); kwargs...)
end


# A `Simulation` is a container, not a reading surface: it holds the state, the cache, and the run
# machinery, and the user reads each of those directly — `kinetic_energy(sim.state.velocity_spectral)`
# for a state observable, `velocity_physical(sim.cache)` for a deposited one. The run layer adds no
# forwarding methods, so there is exactly one way to reach each quantity and no second docstring to
# drift from the first.


function deposit!(sim::Simulation)
  deposit!(sim.cache, sim.state, sim.domain, sim.buffers)
  # The particle velocities ride the same re-deposit: the positions are unchanged, so re-recording
  # from the freshly deposited velocity restores the values the announcement made stale.
  sim.tracers === nothing ||
    (record_particle_velocities!(sim.tracers, velocity_physical(sim.cache));
     deposit_sample!(sim.cache))
  return sim
end


"""
    flow_parameters(sim)

The measured flow state of `sim` as a [`FlowParameters`](@ref) — the bridge that lets any
[`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology) reference law be evaluated at the run's
measured state. The viscosity ``\\nu`` and the
Schmidt number are read from the generator's conditions; the dissipation ``\\varepsilon``, the r.m.s. velocity
``u' = \\sqrt{2k/3}`` (from the kinetic energy ``k``), the longitudinal integral scale ``L_{11}``, and —
when the run carries a scalar — the scalar dissipation ``\\varepsilon_\\varphi`` are measured from the
current state (the scalar dissipation is left `NaN` only for a scalar-free run, where the scalar reference
laws do not apply).
"""
function flow_parameters(sim::Simulation)
  k = kinetic_energy(sim.state.velocity_spectral)
  ε = dissipation(sim.state.velocity_spectral, sim.domain, sim.generator.conditions.viscosity)
  εφ = sim.state.scalar_spectral === nothing ? NaN :
    scalar_dissipation(sim.state.scalar_spectral, sim.domain, sim.generator.conditions.viscosity / sim.generator.conditions.schmidt)
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
advances of the run: a completed step advances the epoch, but so does any announced out-of-band
mutation. The constructor's seeding deposit already leaves the fields epoch at 1, so after two steps
and one announced mutation the clock reads
step 2 and the fields epoch reads 4. Use this to ask how far the run has gone, and the epoch to ask
whether a cached value is still the right one.
"""
current_step(sim::Simulation) = sim.clock.step


# The advective-CFL timestep Δt = C·Δx/maxᵢ|uᵢ| for the current velocity (the integrating factor
# makes diffusion exact, so only the advective limit applies). The maximum speed is the cache's
# deposited number — the previous closing deposit measured it — so choosing Δt is scalar arithmetic, not a pass.
function cfl_timestep(sim::Simulation)
  N = size(field_data(sim.cache.velocity_physical), 1)
  Δx = Float64(sim.domain.grid.domain_size[1]) / N
  speed = max_speed(sim.cache)
  isfinite(speed) || error("non-finite velocity at step $(sim.clock.step): the run appears to have blown up")
  return speed > 0 ? sim.cfl * Δx / speed : sim.cfl * Δx
end


"""
    advance!(sim; dt = nothing)

Advance `sim` by one timestep in place and return it. With `dt = nothing` the step size is the
advective-CFL value for the current velocity; pass `dt` to force a fixed step. Closes the iteration
with [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!), so the cache is readable when it
returns. Advects the tracers,
if any, by Heun-in-time on the start- and end-of-step velocities, and updates the clock.

Returns `sim`.
"""
function advance!(sim::Simulation; dt = nothing)
  Δt = dt === nothing ? cfl_timestep(sim) : Float64(dt)

  # The checked read at the iteration's start: the advance's v₁ must be the particle velocities the previous
  # closing deposit deposited. They are consumed mid-iteration (after the step, as the solver's own scratch), so
  # the epoch is verified here, at tₙ, where they are the current-epoch observable.
  sim.tracers === nothing || particle_velocities(sim.cache)

  step!(sim.scheme, sim.state, sim.generator, sim.domain, sim.buffers, sim.cache, Δt)

  # The closing deposit: fill every slot, at the new epoch, from the state the step just produced; the tracer
  # push then completes its Heun pair — the head-checked sample as v₁, the just-deposited u(tₙ₊₁)
  # interpolated at the predictor positions as v₂ — and the new sample is recorded at the new
  # positions from the same deposited field, completing the iteration's deposits.
  deposit!(sim.cache, sim.state, sim.domain, sim.buffers)
  if sim.tracers !== nothing
    advect!(sim.trajectory_scheme, sim.tracers, velocity_physical(sim.cache), sim.domain,
            sim.particle_buffers, Δt)
    # The run's own advance, not an out-of-band reposition: the epoch moves so the previous sample
    # reads stale, but the history the advance just extended stays intact.
    advance_particles_epoch!(sim.cache)
    record_particle_velocities!(sim.tracers, velocity_physical(sim.cache))
    deposit_sample!(sim.cache)
  end
  check_deposits(sim.cache)

  sim.clock.time += Δt
  sim.clock.step += 1
  return sim
end



"""
    run!(callback, sim)
    run!(sim) do sim … end

Observe and advance `sim` until the observation stops it, and return it. After every iteration —
and once at the seeded initial state, before any advance —
the `callback` **observes** the run as `callback(sim)`: it reads the
state and the cached observables, records what it wants, and returns `true` to continue or `false`
to stop (any other return throws an `ArgumentError` — the decision may not be left implicit). Only then does the next
iteration run: the timestep from the cached maximum speed, the step, the tracer advance, and the closing
deposits. A run of ``n`` iterations therefore observes ``n + 1`` instants — the first before any
step, the last after the final one, with statistics recorded before the stop.

Stopping is the observation's decision on observables, never a run option: a fixed-length run is a callback
that accumulates elapsed turnovers and stops at a chosen total. A span of simulation time compares [`current_time`](@ref) against
a target; a step budget compares [`current_step`](@ref); an eddy-turnover budget accumulates
``\\Delta t \\varepsilon/k`` from the observables it computes; spin-up to stationarity is the
packaged [`StationarityCriterion`](@ref). Whatever the callback needs beyond the cached observables
it computes itself, at its own cadence, with the exported reductions and recoveries.

# Examples
```julia
run!(sim) do s
    current_time(s) < 5.0                        # a span of simulation time
end

history = Float64[]                              # record k every iteration; stop at 200 steps
run!(sim) do s
    push!(history, kinetic_energy(s.state.velocity_spectral))
    current_step(s) < 200
end

run!(StationarityCriterion(), sim)               # spin up to statistical stationarity
```

Returns `sim`.
"""
function run!(callback, sim::Simulation)
  while true
    keep = callback(sim)
    keep isa Bool ||
      throw(ArgumentError("the observation callback must return a Bool — true to continue the " *
                          "run, false to stop it; it returned a $(typeof(keep))"))
    keep || break
    advance!(sim)
  end
  return sim
end


# Stationarity detector. Warm-up completes when the running dissipation ``ε(t)`` — and, for a forced
# scalar, the scalar variance ``⟨φ²⟩(t)`` — stop drifting. ε (equivalently enstrophy) is used rather
# than the kinetic energy ``k(t)``, which is clamped flat by constant-energy forcing and rings under
# fixed-injection forcing; the small scales settle last, so a flat ε is the strict indicator. Flatness
# is a two-half-window mean comparison over a trailing window in eddy-turnover units. The strict gate
# is the velocity-derivative skewness S(t) (≈0 for a random-phase field, →−0.5 for a developed
# cascade): a flat S with |S| ≥ skew_floor marks real turbulence. The transform-heavy skewness is
# sampled only at the storage cadence.
mutable struct StationarityMonitor
  min_turnovers::Float64        # do not test before this (past the start-up overshoot)
  window_turnovers::Float64     # trailing window for the flatness test
  tol::Float64                  # relative-drift threshold
  gate_scalar::Bool             # also require ⟨φ²⟩ to be flat
  gate_skew::Bool               # also require S to have plateaued (and |S| ≥ skew_floor)
  skew_floor::Float64           # minimum |S| for a plateau to count as developed turbulence
  sample_gap::Float64           # min turnover spacing between stored samples
  turn::Vector{Float64}
  eps::Vector{Float64}
  phi2::Vector{Float64}
  skew::Vector{Float64}
  converged::Bool
end

StationarityMonitor(; min_turnovers, window_turnovers, tol, gate_scalar, gate_skew, skew_floor) =
  StationarityMonitor(Float64(min_turnovers), Float64(window_turnovers), Float64(tol),
                      gate_scalar, gate_skew, Float64(skew_floor), Float64(window_turnovers) / 40,
                      Float64[], Float64[], Float64[], Float64[], false)

# No net drift of the series y(turn) across the trailing window [now−W, now]:
# |mean(2nd half) − mean(1st half)| / |mean| < tol.
function _is_flat(turn, y, now, W, tol)
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
  return abs(s2 / n2 - s1 / n1) / abs(mean_all) < tol
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
  flat_v = _is_flat(m.turn, m.eps, elapsed_turn, m.window_turnovers, m.tol)
  flat_s = !m.gate_scalar || _is_flat(m.turn, m.phi2, elapsed_turn, m.window_turnovers, m.tol)
  flat_k = !m.gate_skew ||
           (_is_flat(m.turn, m.skew, elapsed_turn, m.window_turnovers, m.tol) &&
            abs(_window_mean(m.turn, m.skew, elapsed_turn, m.window_turnovers)) ≥ m.skew_floor)
  m.converged = flat_v && flat_s && flat_k
  return m.converged
end

# Compute the signals from `sim` (only when a sample is due — the skewness costs three inverse
# transforms) and test.
function _observe_and_test!(m::StationarityMonitor, sim, elapsed_turn, ε)
  (isempty(m.turn) || elapsed_turn - m.turn[end] ≥ m.sample_gap) || return false
  φ2 = m.gate_scalar ? (sim.state.scalar_spectral === nothing ? NaN : scalar_variance(sim.state.scalar_spectral)) : 0.0
  S = m.gate_skew ? derivative_skewness(sim.state.velocity_spectral, sim.domain) : 0.0
  return _push_and_test!(m, elapsed_turn, ε, φ2, S)
end

_scalar_forced(sim::Simulation) = sim.state.scalar_spectral !== nothing && !(sim.generator.conditions.scalar_forcing isa NoForcing)


"""
    StationarityCriterion(; gate_scalar = true, gate_skewness = true, min_turnovers = 5,
                            window_turnovers = 4, tol = 0.05, skew_floor = 0.1,
                            max_turnovers = 60)

The packaged spin-up observation for [`run!`](@ref): a callback that watches the run settle into
statistical stationarity and stops it there — `run!(StationarityCriterion(), sim)` is the detecting
spin-up, and [`warmup!`](@ref) is the one-line shorthand for exactly that call. Use it before measurement on any freshly
seeded **forced** run. A freely decaying run (`NoForcing()`) has no stationary state to detect — its
``\\varepsilon`` never plateaus — so the criterion can only run to `max_turnovers` and warn; give a
decaying run a fixed-length loop instead, which is a three-line callback (see `run!`).

At each iteration it measures the dissipation ``\\varepsilon`` — the small scales
settle last, so a flat ``\\varepsilon`` is the strict indicator, where a constant-energy forcing
clamps ``k`` flat and a fixed-injection forcing makes it ring, which is why ``k`` is kept out of the
**gate** — and the kinetic energy ``k``, which normalizes the eddy-turnover clock
``\\Delta t \\varepsilon/k`` it accumulates, and tests flatness over a trailing window; it stops the run when
every gate holds, or gives up with a warning at `max_turnovers`.

# Arguments
All keyword:
- `gate_scalar` — when the run's scalar is forced, also require the scalar variance
  ``\\langle\\varphi^2\\rangle`` to be flat (the scalar settles after the velocity; an unforced
  scalar has no stationary state and is never gated).
- `gate_skewness` — also require the velocity-derivative skewness to have plateaued **and** reached
  ``\\lvert S\\rvert \\ge \\texttt{skew\\_floor}`` — the decisive "real turbulence yet" signal: a
  random-phase field starts at ``S \\approx 0`` and only a developed cascade reaches
  ``S \\approx -0.5``. The skewness costs transforms, so it is measured on the criterion's own
  sampling interval — one sample per `window_turnovers / 40` of turnover time, giving about forty
  samples across the trailing window — rather than every iteration.
- `min_turnovers`, `window_turnovers`, `tol` — do not test before `min_turnovers` eddy-turnover
  times (past the start-up overshoot); flatness is a two-half-window mean comparison over the
  trailing `window_turnovers`, relative drift below `tol`.
- `skew_floor` — the minimum ``\\lvert S\\rvert`` for a plateau to count as developed turbulence.
  The default `0.1` is a **floor against a random-phase field**, which starts at ``S \\approx 0``; it
  is a fifth of the ``\\lvert S\\rvert \\approx 0.5`` of a developed cascade, so clearing it means
  "no longer Gaussian", not "fully developed". Raise it toward `0.4` when the run's statistics
  depend on the cascade being mature.
- `max_turnovers` — the give-up cap: reaching it stops the run with a warning rather than spinning
  forever.

The criterion carries its own observation state (the sampled signals and the turnover clock), so
build a fresh one per run.

# Fields
The fields are not the keywords: `gate_skew`, `min_turnovers`, `window_turnovers`, `tol` and
`skew_floor` all live inside `monitor`, which holds the sampled series together with the thresholds
that judge them. Build one through the keyword constructor above.
- `monitor` — the sampled signals (the turnover clock, ``\\varepsilon``, the scalar variance, the
  skewness — not ``k``, which this criterion deliberately never gates on) and the
  gate settings and tolerances that test them.
- `max_turnovers` — the give-up cap.
- `gate_scalar` — the requested scalar gate (applied only when the run's scalar is forced).
- `elapsed_turn`, `last_time`, `started` — the turnover clock's state.
"""
mutable struct StationarityCriterion
  const monitor::StationarityMonitor
  const max_turnovers::Float64
  const gate_scalar::Bool
  elapsed_turn::Float64
  last_time::Float64
  started::Bool
end

function StationarityCriterion(; gate_scalar::Bool = true, gate_skewness::Bool = true,
                               min_turnovers::Real = 5, window_turnovers::Real = 4,
                               tol::Real = 0.05, skew_floor::Real = 0.1,
                               max_turnovers::Real = 60)
  monitor = StationarityMonitor(; min_turnovers, window_turnovers, tol,
                                gate_scalar, gate_skew = gate_skewness, skew_floor)
  return StationarityCriterion(monitor, Float64(max_turnovers), gate_scalar, 0.0, NaN, false)
end

function (criterion::StationarityCriterion)(sim::Simulation)
  if !criterion.started
    # The scalar gate binds only when the run's scalar is forced — resolved at the first observation,
    # where the criterion first sees the run it observes.
    criterion.monitor.gate_scalar = criterion.gate_scalar && _scalar_forced(sim)
    criterion.last_time = current_time(sim)
    criterion.started = true
  end
  ε = dissipation(sim.state.velocity_spectral, sim.domain, sim.generator.conditions.viscosity)
  Δt = current_time(sim) - criterion.last_time
  criterion.last_time = current_time(sim)
  if ε > 0
    criterion.elapsed_turn += Δt * ε / Float64(kinetic_energy(sim.state.velocity_spectral))
  else
    # No dissipation means no eddy-turnover clock, and `max_turnovers` is denominated in exactly the
    # units that have stopped advancing — so the give-up cap below could never be reached and the
    # loop would run forever. A run that is not dissipating also cannot reach the developed cascade
    # this criterion tests for, so the honest outcome is to stop and say why.
    @warn "StationarityCriterion: the dissipation rate is not positive (ε = $ε), so the eddy-turnover            clock cannot advance and stationarity can never be detected — stopping. A run with no            dissipation has no cascade to become stationary."
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
    warmup!(sim; kwargs...)

A one-line shorthand, and nothing more: `warmup!(sim; kwargs...)` is exactly

```julia
run!(StationarityCriterion(; kwargs...), sim)
```

— it spins `sim` up to a statistically stationary state before measurement and returns it, by
running the observation-first loop with the packaged stationarity observation. Every keyword is
passed through to [`StationarityCriterion`](@ref) untouched; its docstring is the home for what is
detected (the flat dissipation, the scalar-variance and derivative-skewness gates, the give-up cap)
and for every option. For a fixed spin-up budget, write the three-line budget callback instead
(see [`run!`](@ref)).

# Examples
```julia
warmup!(sim)                          # detect stationarity (ε- and skewness-plateau gates)
warmup!(sim; gate_skewness = false)   # relax the skewness gate (a shorter, looser spin-up)
```

Returns `sim`.
"""
warmup!(sim::Simulation; kwargs...) = run!(StationarityCriterion(; kwargs...), sim)


end # module SimulationRun
