# SimulationRun — the ergonomic run layer. A `Simulation` bundles the domain, buffers, the reified
# generator (the equations of motion with their conditions and assembly scratch), the integrator, the
# spectral state (û, φ̂), the observables cache, and any tracers;
# `advance!`/`run!`/`warmup!` own the CFL-adaptive time loop. It holds no physics or numerics of its
# own — it wires the pieces of SimulationDomain/State/Generator/Observables/Forcing/Propagator/Particles
# so a case is a few lines to set up and run, warm-up included, while every piece stays reachable for a
# hand-run loop.
#
# The observables cache is deposit-driven (no recompute anywhere): `advance!` runs `step!`, then the
# closing `deposit!` recovers the iteration's observables into the cache and stamps them, and the deposit-
# completeness check closes the iteration. The timestep choice reads the cached maximum speed — scalar
# arithmetic, no grid pass. The tracer push is Heun on the two endpoint velocities: v₁ is the
# particle velocities the PREVIOUS closing deposit deposited (read checked), v₂ interpolates the just-deposited
# u(tₙ₊₁) at the predictor positions, and the new sample is recorded at the new positions from the
# same field, completing the iteration's deposits; only M-sized point values are held, never a second field copy.

"""
    SimulationRun

The run layer:
- [`Simulation`](@ref) — the assembled state of a case.
- [`advance!`](@ref), [`run!`](@ref) — advance one iteration; observe and advance until the
  callback stops the run (the callback is the observation, and its return decides continuation).
- [`StationarityCriterion`](@ref), [`warmup!`](@ref) — the packaged spin-up-to-stationarity
  observation, and its one-line sugar.
- [`velocity_spectral`](@ref), [`scalar_spectral`](@ref) — the uniform reads of the state itself.
- [`current_time`](@ref), [`current_step`](@ref) — the elapsed time and step count.
- [`flow_parameters`](@ref) — the run's measured flow state as a `Phenomenology` `FlowParameters`.
- [`validate_spectrum`](@ref) — compare the run's measured energy spectrum against a `Phenomenology` model.
"""
module SimulationRun

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, new_vector_field_spectral, new_scalar_field_spectral, new_vector_field_physical,
                          DealiasingStrategy, TwoThirds, max_wavenumber
using ..State: ResolvedFields, random_solenoidal_velocity!, random_scalar!
using ..Cache: ObservablesCache, check_deposits, particles_modified!, deposit_sample!
import ..Cache: velocity_physical, vorticity_physical, scalar_physical, max_speed,
                particle_velocities, resolved_fields_modified!
using ..Observables: kinetic_energy, dissipation, scalar_variance, scalar_dissipation, energy_spectrum,
                     integral_scale, derivative_skewness
using ..Forcing: AbstractForcing, NoForcing, BandRescaling
using ..Generator: FlowConditions, ResolvedGenerator
using ..Propagator: AbstractIntegrator, IntegratorBuffers, allocate_buffers, step!,
                    recommended_cfl, IFLowStorageRK3
import ..Propagator: deposit!
using ..Particles: Tracers, record_trajectory_velocity!, advect!
import ..Particles: particle_positions
using ..Phenomenology: FlowParameters
using ..Phenomenology.Spectra: EnergySpectrum, spectrum
using ..Phenomenology.Scalings: Li2008, stationary_dissipation

export Simulation, advance!, run!, warmup!, StationarityCriterion,
       velocity_spectral, scalar_spectral,
       current_time, current_step, flow_parameters, validate_spectrum


mutable struct Clock
  time::Float64
  step::Int
end


"""
    Simulation(; grid_points_per_axis, k_max_η = 2, kinetic_energy = 1.5,
                 side_length = 2π, element_type = Float64, array_type = Array,
                 dealiasing = TwoThirds(), kwargs...)
    Simulation(domain; k_max_η = 2, kinetic_energy = 1.5, kwargs...)

A ready-to-run case — the [`FixedDomain`](@ref), the [`IntegratorBuffers`](@ref), the
[`ResolvedGenerator`](@ref) (the equations of motion, carrying the [`FlowConditions`](@ref) and
the assembly scratch), the chosen integrator, the [`ResolvedFields`](@ref) state (the velocity
``\\hat{\\boldsymbol{u}}`` and passive scalar ``\\hat\\varphi`` in spectral representation), the
[`ObservablesCache`](@ref) observation cache, any [`Tracers`](@ref), and a clock. The first form is the
**front door**: from `grid_points_per_axis` and `side_length` it builds every piece with sensible defaults, seeds a
divergence-free velocity (and, with `scalar = true`, a mean-zero scalar ``\\varphi``), and returns a
`Simulation` at ``t = 0`` ("front door" names exactly this convenience form throughout — the
constructor that builds every component for you); the second takes a `FixedDomain` you built
yourself. Advance it with
[`advance!`](@ref) / [`run!`](@ref) / [`warmup!`](@ref); read its measured state by applying the
observables to its `state` fields (e.g. `kinetic_energy(sim.state.velocity)`) or through the cache's
deposited observables ([`velocity_physical`](@ref)`(sim)`, [`vorticity_physical`](@ref)`(sim)`),
summarize it
with [`flow_parameters`](@ref), and track its progress with [`current_time`](@ref) / [`current_step`](@ref).

# Setting the Reynolds number

By default the run is **forced and stationary** — a `BandRescaling` holds the total (whole-field) energy
at `kinetic_energy` (i.e. `over = :total`) — and the viscosity is chosen from the grid rather than supplied:

!!! note "The default holds ``k`` fixed, so ``k`` is not a measurable of the default run"
    `BandRescaling` is a deterministic clamp: it rescales the band every step to hold the target, which
    pins ``u'`` (hence the scale of ``\\mathrm{Re}_\\lambda``) and suppresses the physical fluctuation of
    the quantity it holds. For fluctuation statistics of the *held* quantity, force with fixed injection
    ([`ConstantPower`](@ref GBGIsotropicTurbulence.Forcing.ConstantPower)) instead and let ``k`` find its own level.

  * **Grid mode** (no `viscosity`): the constructor picks the highest Reynolds number consistent with the
    chosen resolution criterion `k_max_η`.
    It reads the dissipation the box sustains from the box-normalized dissipation law `Li2008` (in
    `Phenomenology.Scalings`), ``\\varepsilon = (k/G)^{3/2}/L`` with `kinetic_energy` the kinetic energy
    ``k``, `side_length` the side ``L``, and ``G`` a dimensionless constant calibrated on
    box-confined DNS (``\\approx 0.9``; Li et al. 2008),
    then sets ``\\nu`` so that ``\\kappa_{\\max}\\eta`` equals `k_max_η` — the
    resolution criterion, with ``\\kappa_{\\max}`` the [`max_wavenumber`](@ref) (the dealiasing cutoff,
    **not** the grid Nyquist) and ``\\eta`` the Kolmogorov (dissipation) microscale. Since ``\\kappa_{\\max}\\eta = f\\pi \\eta/\\Delta x`` — ``\\Delta x = L/N`` the grid spacing — with ``f`` the
    retained-Nyquist fraction, `k_max_η = 2` gives ``\\Delta x \\approx \\eta`` for the default ``2/3`` rule
    (``f = 2/3``); a wider-band strategy (larger ``f``) resolves a finer dissipation scale ``\\eta`` on the
    same grid at the same `k_max_η`. The `kinetic_energy` and `side_length` fix
    the units; the grid and `k_max_η` fix ``\\mathrm{Re}_\\lambda \\sim N^{2/3}``. The chosen ``\\nu``,
    ``\\varepsilon``, and ``\\mathrm{Re}_\\lambda`` are logged.
  * **Explicit mode**: pass `viscosity` and it is used directly (`k_max_η` is ignored) — for a decaying
    run (`velocity_forcing = NoForcing()`) or manual control. Grid mode is calibrated on a *stationary
    forced* balance (`Li2008`'s ``G`` is fitted to forced-isotropic DNS), so a decaying run should set
    ``\\nu`` explicitly: the resolution it buys is only meaningful while the box sustains the energy the
    law assumes.

# Arguments

All keyword except `domain` (below). The ones marked *(front door only)* configure the `FixedDomain` and are consumed by the first form;
the rest are forwarded to the `Simulation(domain; …)` form.

- `grid_points_per_axis` — the number of grid points ``N`` along each side (front door only); required.
- `domain` — a pre-built [`FixedDomain`](@ref). This one is **positional**, not a keyword: it is the
  argument of the second form, `Simulation(domain; …)` (the front door builds one for you from
  `grid_points_per_axis`, `side_length`, `dealiasing`, `element_type`, `array_type`).
- `k_max_η = 2` — the resolution criterion ``\\kappa_{\\max}\\eta`` used to set ``\\nu`` in grid mode (the
  keyword spells ``\\kappa_{\\max}`` in ASCII); ``\\ge 1.5`` is well-resolved, higher trades Reynolds number for margin.
- `viscosity` — the kinematic viscosity ``\\nu`` (sets ``\\mathrm{Re} = 1/\\nu``); omit for grid mode.
- `kinetic_energy = 1.5` — the initial, and when forced the held, kinetic energy ``k``; `1.5` gives
  an r.m.s. velocity ``u' = \\sqrt{2k/3} = 1``.
- `side_length = 2π` — the box side ``L`` (front door only).
- `element_type = Float64`, `array_type = Array` — the real element type and storage backend (front door only).
- `dealiasing = TwoThirds()` — the [`DealiasingStrategy`](@ref) (``2/3`` sharp, `HouLi` smooth, or
  `PhaseShift`); it sets ``\\kappa_{\\max}`` and hence the CFL step (front door only).
- `schmidt = 1.0` — the Schmidt number ``\\mathrm{Sc}`` (scalar diffusivity ``\\varkappa = \\nu/\\mathrm{Sc}``).
- `velocity_forcing`, `scalar_forcing` — an [`AbstractForcing`](@ref) (or a `DeferredForcing` from an
  operator-free constructor); `velocity_forcing` defaults to a `BandRescaling` holding the total
  (whole-field) energy at `kinetic_energy` (`over = :total`), `scalar_forcing` to `NoForcing()`. The
  velocity and scalar are forced independently.
- `scalar = false`, `scalar_variance = 1.0` — whether to evolve a passive scalar (a mean-zero
  ``\\varphi``), and its initial variance.
- `peak_wavenumber = 2.0` — the large-scale envelope wavenumber ``\\kappa_p`` of the initial
  condition, for the **velocity and the scalar alike** (each shell-summed spectrum peaks at
  ``\\kappa_p/\\sqrt{2}``); it also sets the integral scale `initial_spectrum` is evaluated at.
- `initial_spectrum = nothing` — a [`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology)
  `EnergySpectrum` (e.g. `VonKarman1948()`) to draw the
  initial velocity from, in place of the default large-scale Gaussian; its shape is evaluated at the
  run's state (its integral scale set to `1/peak_wavenumber` (which is the Gaussian envelope's characteristic
  wavenumber ``\\kappa_p``, not the shell-spectrum peak — that sits at ``\\kappa_p/\\sqrt{2}``; see
  [`random_solenoidal_velocity!`](@ref))) and normalized to `kinetic_energy`.
- `integrator = IFLowStorageRK3()`, `cfl = recommended_cfl(integrator, domain)` — the
  [`AbstractIntegrator`](@ref) scheme and its advective-CFL ceiling (adapts to `dealiasing`).
- `number_of_tracers = 0`, `tracer_scheme = CatmullRom` — the number of Lagrangian [`Tracers`](@ref) and
  their interpolation scheme, forwarded to the `Tracers` constructor.
- `rng` — the random stream for the initial condition and the tracer seeding (defaults to
  `Random.default_rng()`).

# Examples
```julia
# Grid mode — a 128³ forced-stationary run, ν set from the resolution criterion:
sim = Simulation(grid_points_per_axis = 128)

# Explicit mode — set ν directly, carry a passive scalar, force at constant power:
sim = Simulation(grid_points_per_axis = 128, viscosity = 5e-3;
                 scalar = true, velocity_forcing = ConstantPower(target = 0.1))

# Domain-first — build the frame yourself, then hand it to the second form:
domain = FixedDomain(grid_points_per_axis = 128, side_length = 2π, dealiasing = HouLi(),
                     element_type = Float64, array_type = Array)
sim = Simulation(domain; viscosity = 5e-3)
```

# Fields
- `domain`, `buffers`, `generator`, `integrator` — the [`FixedDomain`](@ref), [`IntegratorBuffers`](@ref),
  the [`ResolvedGenerator`](@ref) (whose `conditions` field is the run's [`FlowConditions`](@ref)), and
  the chosen scheme.
- `state` — the [`ResolvedFields`](@ref) (the evolving `û`, `φ̂`).
- `cache` — the [`ObservablesCache`](@ref): the observables the iteration deposits and stamps at its end.
- `tracers` — the [`Tracers`](@ref) being advected along with the fields, or `nothing`.
- `cfl`, `clock` — the advective-CFL coefficient, and the time/step counter.
"""
struct Simulation{DOM, FB, IG, GN<:ResolvedGenerator, RF, DF, TR}
  domain::DOM
  buffers::FB
  generator::GN            # ResolvedGenerator: the equations of motion + conditions + assembly scratch
  integrator::IG
  state::RF                # ResolvedFields: the evolving (û, φ̂), the single source of truth
  cache::DF              # ObservablesCache: the stamped observation cache over the state
  tracers::TR              # Tracers, or nothing
  cfl::Float64
  clock::Clock
end


# A forcing may be given ready-built (an `AbstractForcing`) or as a factory `domain -> AbstractForcing`
# — the latter lets a banded forcing be named before the domain exists (`domain -> ConstantPower(domain;
# target)`), since a forcing precomputes its band from `domain`.
_materialize_forcing(f::AbstractForcing, ::FixedDomain) = f
_materialize_forcing(f, domain::FixedDomain) = f(domain)


function Simulation(domain::FixedDomain;
                    kinetic_energy::Real = 1.5, k_max_η::Real = 2, viscosity = nothing,
                    schmidt::Real = 1.0,
                    velocity_forcing = BandRescaling(domain; target = kinetic_energy, over = :total),
                    scalar_forcing = NoForcing(),
                    integrator::AbstractIntegrator = IFLowStorageRK3(),
                    cfl::Real = recommended_cfl(integrator, domain),
                    scalar::Bool = false, scalar_variance::Real = 1.0,
                    peak_wavenumber::Real = 2.0, initial_spectrum = nothing,
                    number_of_tracers::Integer = 0, tracer_scheme = CatmullRom,
                    rng = Random.default_rng())
  # The stationary dissipation the box sustains (`Li2008`) — a modeled estimate, not a measurement.
  # It sets ν in grid mode and shapes a `Phenomenology` `initial_spectrum`.
  side_length = domain.grid.domain_size[1]
  ε = stationary_dissipation(Li2008(), kinetic_energy, side_length)
  if isnothing(viscosity)                                    # grid mode: highest Re the grid resolves
    ν = ε^(1//3) * (k_max_η / max_wavenumber(domain))^(4//3)
    reλ = (2 * kinetic_energy / 3) * sqrt(15 / (ε * ν))
    @info "Simulation: grid-resolved at κ_max·η = $(k_max_η)" viscosity=ν dissipation=ε Re_λ=reλ
  else
    ν = Float64(viscosity)
  end

  buffers = allocate_buffers(integrator, domain; scalar)
  conditions = FlowConditions(; viscosity = ν, schmidt,
                    velocity_forcing = _materialize_forcing(velocity_forcing, domain),
                    scalar_forcing = _materialize_forcing(scalar_forcing, domain))

  state = ResolvedFields(domain; scalar)
  ic_spectrum = nothing
  if initial_spectrum isa EnergySpectrum       # a `Phenomenology` model → evaluate at the run's state
    fp = FlowParameters(; viscosity = ν, dissipation = ε, rms_velocity = sqrt(2 * kinetic_energy / 3),
                        integral_scale = inv(peak_wavenumber), schmidt)
    ic_spectrum = κ -> spectrum(initial_spectrum, κ, fp)
  elseif !isnothing(initial_spectrum)
    ic_spectrum = initial_spectrum             # a raw κ -> E(κ) function
  end
  random_solenoidal_velocity!(state.velocity, domain; kinetic_energy, peak_wavenumber, spectrum = ic_spectrum, rng)
  scalar && random_scalar!(state.scalar, domain; scalar_variance, peak_wavenumber, rng)

  tracers = number_of_tracers > 0 ? Tracers(domain, number_of_tracers; scheme = tracer_scheme, rng) : nothing

  cache = ObservablesCache(domain; scalar,
                             particle_velocities = tracers === nothing ? nothing : tracers.trajectory_velocity)
  deposit!(cache, state, domain, buffers)        # the seeding deposit: the first instant observed is t₀
  tracers === nothing ||
    (record_trajectory_velocity!(tracers, velocity_physical(cache)); deposit_sample!(cache))
  return Simulation(domain, buffers, ResolvedGenerator(domain, conditions; scalar), integrator, state, cache,
                    tracers, Float64(cfl), Clock(0.0, 0))
end

function Simulation(; grid_points_per_axis::Integer, side_length::Real = 2π,
                    element_type::Type = Float64, array_type = Array,
                    dealiasing::DealiasingStrategy = TwoThirds(), kwargs...)
  return Simulation(FixedDomain(; grid_points_per_axis, side_length, dealiasing, element_type, array_type); kwargs...)
end


# Observables are functions of the state, not the `Simulation`: to diagnose a run, the caller supplies
# the state fields and parameters explicitly — `kinetic_energy(sim.state.velocity)`. The run-layer
# functions below do exactly that; the observable generics themselves never take a `Simulation`. (The
# `sim` methods below are thin forwarders to the cache accessors, whose docstrings are the home: the
# user's callback receives `sim` and reads the run, never the machinery path inside it.)


"""
    velocity_spectral(sim)

The velocity ``\\hat{\\boldsymbol{u}}`` in spectral representation of the run `sim` — the evolving
state itself, always current (it is what the run advances, not a cached observable). Treat it as read-only: to
mutate the state out of band, write through `sim.state` and announce it with
[`resolved_fields_modified!`](@ref).
"""
velocity_spectral(sim::Simulation) = sim.state.velocity


"""
    scalar_spectral(sim)

The scalar ``\\hat\\varphi`` in spectral representation of the run `sim` — the evolving state
itself, always current, with exactly [`velocity_spectral`](@ref)'s contract. Throws an `ArgumentError` when the run carries
no passive scalar.
"""
function scalar_spectral(sim::Simulation)
  sim.state.scalar === nothing &&
    throw(ArgumentError("this run carries no passive scalar"))
  return sim.state.scalar
end


particle_positions(sim::Simulation) =
  sim.tracers === nothing ?
    throw(ArgumentError("this run advects no tracers")) : particle_positions(sim.tracers)


velocity_physical(sim::Simulation) = velocity_physical(sim.cache)
vorticity_physical(sim::Simulation) = vorticity_physical(sim.cache)
scalar_physical(sim::Simulation) = scalar_physical(sim.cache)
max_speed(sim::Simulation) = max_speed(sim.cache)
particle_velocities(sim::Simulation) = particle_velocities(sim.cache)
resolved_fields_modified!(sim::Simulation) = (resolved_fields_modified!(sim.cache); sim)

function deposit!(sim::Simulation)
  deposit!(sim.cache, sim.state, sim.domain, sim.buffers)
  # The particle velocities ride the same re-deposit: the positions are unchanged, so re-recording
  # from the freshly deposited velocity restores the values the announcement made stale.
  sim.tracers === nothing ||
    (record_trajectory_velocity!(sim.tracers, velocity_physical(sim.cache));
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
  k = kinetic_energy(sim.state.velocity)
  ε = dissipation(sim.state.velocity, sim.domain, sim.generator.conditions.viscosity)
  εφ = sim.state.scalar === nothing ? NaN :
    scalar_dissipation(sim.state.scalar, sim.domain, sim.generator.conditions.viscosity / sim.generator.conditions.schmidt)
  FlowParameters(; viscosity = sim.generator.conditions.viscosity, dissipation = ε,
                 rms_velocity = sqrt(2k / 3),
                 integral_scale = integral_scale(sim.state.velocity, sim.domain),
                 schmidt = sim.generator.conditions.schmidt, scalar_dissipation = εφ)
end


"""
    validate_spectrum(sim, model)

Compare the measured energy spectrum of `sim` against a
[`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology) model spectrum `model` (an
`EnergySpectrum`, e.g. `Pope2000()`), evaluated at the run's [`flow_parameters`](@ref). The measured
[`energy_spectrum`](@ref) is a per-shell energy (``k = \\sum_\\kappa E(\\kappa)``) while the model is a
spectral density (``k = \\int_0^\\infty E(\\kappa)\\,\\mathrm d\\kappa``), so the density is multiplied by the
shell width ``\\Delta\\kappa = 2\\pi/L`` before comparison — making the two agree at any box side ``L`` (not
only the default ``L = 2\\pi``, where ``\\Delta\\kappa = 1``). Returns a named tuple
`(; wavenumbers, measured, predicted, relative_error)`: the resolved shell wavenumbers, the measured and
predicted per-shell ``E(\\kappa)``, and the relative ``L^{2}`` discrepancy over the resolved (non-empty) shells.

!!! note
    A developed, well-resolved run agrees with a good model across the inertial range; at low Reynolds
    number or coarse resolution the inertial range is narrow, so a large discrepancy is expected and
    reflects the run, not the model.
"""
function validate_spectrum(sim::Simulation, model::EnergySpectrum)
  fp = flow_parameters(sim)
  κ, measured = energy_spectrum(sim.state.velocity, sim.domain)
  # Measured is a per-shell energy (k = Σ E); the model is a density (k = ∫ E dκ). Bring the density to a
  # per-shell energy by the shell width Δκ = 2π/L so the comparison is correct at any box side L.
  Δκ = 2π / sim.domain.grid.domain_size[1]
  predicted = similar(measured)
  num = zero(eltype(measured))
  den = zero(eltype(measured))
  for i in eachindex(κ, measured)
    predicted[i] = κ[i] > 0 ? spectrum(model, κ[i], fp) * Δκ : zero(eltype(measured))
    if measured[i] > 0
      num += (measured[i] - predicted[i])^2
      den += measured[i]^2
    end
  end
  return (; wavenumbers = κ, measured, predicted, relative_error = sqrt(num / den))
end


"""
    current_time(sim)

The elapsed simulation time of `sim`.
"""
current_time(sim::Simulation) = sim.clock.time

"""
    current_step(sim)

The number of steps `sim` has taken.
"""
current_step(sim::Simulation) = sim.clock.step


# The advective-CFL timestep Δt = C·Δx/maxᵢ|uᵢ| for the current velocity (the integrating factor
# makes diffusion exact, so only the advective limit applies). The maximum speed is the cache's
# deposited number — the previous closing deposit measured it — so choosing Δt is scalar arithmetic, not a pass.
function cfl_timestep(sim::Simulation)
  N = size(field_data(sim.cache.velocity), 1)
  Δx = Float64(sim.domain.grid.domain_size[1]) / N
  speed = max_speed(sim.cache)
  isfinite(speed) || error("non-finite velocity at step $(sim.clock.step): the run appears to have blown up")
  return speed > 0 ? sim.cfl * Δx / speed : sim.cfl * Δx
end


"""
    advance!(sim; dt = nothing)

Advance `sim` by one timestep in place and return it. With `dt = nothing` the step size is the
advective-CFL value for the current velocity; pass `dt` to force a fixed step. Advects the tracers,
if any, by Heun-in-time on the start- and end-of-step velocities, and updates the clock.
"""
function advance!(sim::Simulation; dt = nothing)
  Δt = dt === nothing ? cfl_timestep(sim) : Float64(dt)

  # The checked read at the iteration's start: the push's v₁ must be the particle velocities the previous
  # closing deposit deposited. They are consumed mid-iteration (after the step, as the solver's own scratch), so
  # the stamp is verified here, at tₙ, where they are the current epoch observable.
  sim.tracers === nothing || particle_velocities(sim.cache)

  step!(sim.integrator, sim.state, sim.generator, sim.domain, sim.buffers, sim.cache, Δt)

  # The closing deposit: fill and stamp every slot from the state the step just produced; the tracer
  # push then completes its Heun pair — the head-checked sample as v₁, the just-deposited u(tₙ₊₁)
  # interpolated at the predictor positions as v₂ — and the new sample is recorded at the new
  # positions from the same deposited field, completing the iteration's deposits.
  deposit!(sim.cache, sim.state, sim.domain, sim.buffers)
  if sim.tracers !== nothing
    advect!(sim.tracers, velocity_physical(sim.cache), sim.domain, Δt)
    particles_modified!(sim.cache)
    record_trajectory_velocity!(sim.tracers, velocity_physical(sim.cache))
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
to stop (any other return throws — the decision may not be left implicit). Only then does the next
iteration run: the timestep from the cached maximum speed, the step, the tracer push, and the closing
deposits. The schedule never varies with how the run is driven, so the closing deposit's maximum-speed
reduction and its host readback happen every iteration even under a fixed `dt` that never reads them. A run of ``n`` iterations therefore observes ``n + 1`` instants — the first before any
step, the last after the final one, with statistics recorded before the stop.

Stopping is the observation's decision on observables, never a run option: a budget is a callback
that accumulates what it budgets. A span of simulation time compares [`current_time`](@ref) against
a target; a step budget compares [`current_step`](@ref); an eddy-turnover budget accumulates
``\\Delta t \\varepsilon/k`` from the observables it computes; spin-up to stationarity is the
packaged [`StationarityCriterion`](@ref). Whatever the callback needs beyond the cached observables
it computes itself, at its own cadence, with the exported reductions and recoveries.

# Examples
```julia
run!(sim) do s
    current_time(s) < 5.0                        # a span of simulation time
end

history = Float64[]                              # record k at every observation; stop at 200 steps
run!(sim) do s
    push!(history, kinetic_energy(s.state.velocity))
    current_step(s) < 200
end

run!(StationarityCriterion(), sim)               # spin up to statistical stationarity
```
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
  φ2 = m.gate_scalar ? (sim.state.scalar === nothing ? NaN : scalar_variance(sim.state.scalar)) : 0.0
  S = m.gate_skew ? derivative_skewness(sim.state.velocity, sim.domain) : 0.0
  return _push_and_test!(m, elapsed_turn, ε, φ2, S)
end

_scalar_forced(sim::Simulation) = sim.state.scalar !== nothing && !(sim.generator.conditions.scalar_forcing isa NoForcing)


"""
    StationarityCriterion(; gate_scalar = true, gate_skewness = true, min_turnovers = 5,
                            window_turnovers = 4, tol = 0.05, skew_floor = 0.1,
                            max_turnovers = 60)

The packaged spin-up observation for [`run!`](@ref): a callback that watches the run settle into
statistical stationarity and stops it there — `run!(StationarityCriterion(), sim)` is the detecting
spin-up, and [`warmup!`](@ref) is its one-line sugar. Use it before measurement on any freshly
seeded run; write your own callback instead when the transient length is known (a fixed budget is a
three-line callback — see `run!`).

At each observation it measures the dissipation ``\\varepsilon`` — the small scales
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
  ``S \\approx -0.5``. The transform-heavy skewness is sampled at the storage cadence, not every
  observation.
- `min_turnovers`, `window_turnovers`, `tol` — do not test before `min_turnovers` eddy-turnover
  times (past the start-up overshoot); flatness is a two-half-window mean comparison over the
  trailing `window_turnovers`, relative drift below `tol`.
- `skew_floor` — the minimum ``\\lvert S\\rvert`` for a plateau to count as developed turbulence.
- `max_turnovers` — the give-up cap: reaching it stops the run with a warning rather than spinning
  forever.

The criterion carries its own observation state (the sampled signals and the turnover clock), so
build a fresh one per run.

# Fields
The plain constructor `StationarityCriterion(monitor, max_turnovers, gate_scalar, elapsed_turn,
last_time, started)` is internal:
- `monitor` — the sampled signals and gates.
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
  ε = dissipation(sim.state.velocity, sim.domain, sim.generator.conditions.viscosity)
  Δt = current_time(sim) - criterion.last_time
  criterion.last_time = current_time(sim)
  ε > 0 && (criterion.elapsed_turn += Δt * ε / Float64(kinetic_energy(sim.state.velocity)))
  _observe_and_test!(criterion.monitor, sim, criterion.elapsed_turn, ε) && return false
  if criterion.elapsed_turn ≥ criterion.max_turnovers
    @warn "StationarityCriterion: hit the max_turnovers = $(criterion.max_turnovers) cap without detecting stationarity"
    return false
  end
  return true
end


"""
    warmup!(sim; kwargs...)

Sugar, and nothing more: `warmup!(sim; kwargs...)` is exactly

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
"""
warmup!(sim::Simulation; kwargs...) = run!(StationarityCriterion(; kwargs...), sim)


end # module SimulationRun
