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
# velocity sample the PREVIOUS closing deposit left (read checked), v₂ interpolates the just-deposited
# u(tₙ₊₁) at the predictor positions, and the new sample is recorded at the new positions from the
# same field, completing the iteration's deposits; only M-sized point values are held, never a second field copy.

"""
    SimulationRun

The run layer:
- [`Simulation`](@ref) — everything the next iteration needs, in one value: the domain, the
  fields at the current instant, the observables cache, the equations of motion with their
  forcing, the integration schemes with their scratch, any tracers, and the clock — built with
  defaults from a few numbers. It holds the present instant only; past instants exist only in
  what an observation recorded as the run advanced.
- [`advance!`](@ref), [`run!`](@ref) — advance one iteration; observe and advance until the
  callback stops the run (the callback *is* the observation — the function the loop calls to read the run each
  iteration — and its return decides continuation).
- [`StationarityCriterion`](@ref), [`warmup!`](@ref) — the packaged spin-up-to-stationarity
  observation, and `warmup!`, the one-line shorthand that runs it.
- [`current_time`](@ref), [`current_step`](@ref) — the elapsed time and step count.
- [`flow_parameters`](@ref) — the run's measured flow state as a `Phenomenology` `FlowParameters`.
- [`write_simulation`](@ref) / [`read_simulation`](@ref) — checkpoint and restore: the restartable
  run as one self-describing HDF5 group (available once `HDF5` is loaded).

Read a run's state through `sim.state` and its deposited observables through `sim.cache`, with the
observables and cache accessors that own them; the run layer adds no forwarding methods of its own.
"""
module SimulationRun

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, new_vector_field_spectral, new_scalar_field_spectral, new_vector_field_physical,
                          DealiasingStrategy, TwoThirds, max_wavenumber
using ..State: ResolvedFields, random_solenoidal_velocity_spectral!, random_scalar_spectral!
import ..Cache: particles_modified!, fields_modified!
using ..Cache: ObservablesCache, check_deposits, advance_particles_epoch!,
               advance_fields_epoch!,
               velocity_physical, max_speed, velocity_at_particles
using ..Observables: kinetic_energy, dissipation, kinetic_energy_and_dissipation, scalar_variance,
                     scalar_dissipation, energy_spectrum, integral_scale, derivative_skewness
using ..Forcing: AbstractForcing, NoForcing, VarianceRescaling, VarianceController
using ..Generator: FlowConditions, ResolvedGenerator
using ..Propagator: AbstractIntegrator, IntegratorBuffers, allocate_buffers, step!,
                    recommended_cfl, IFLowStorageRK3
import ..Propagator: deposit!
using ..Particles: Tracers, AbstractParticleIntegrator, Heun, advect!,
                   restart!, history_depth
using ..Phenomenology: FlowParameters, taylor_reynolds
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

Everything the next iteration needs, bundled: the [`FixedDomain`](@ref), the [`IntegratorBuffers`](@ref), the
[`ResolvedGenerator`](@ref) (the equations of motion, carrying the [`FlowConditions`](@ref) and the
assembly scratch), the chosen field integration scheme, the [`ResolvedFields`](@ref) state (the velocity
``\\hat{\\boldsymbol{u}}`` and passive scalar ``\\hat\\varphi`` in spectral representation), the
[`ObservablesCache`](@ref) holding what the last iteration deposited, any [`Tracers`](@ref), and a
clock.

The two forms differ only in where the `FixedDomain` comes from. The first is
**domain-building**: from `grid_points_per_axis` and `side_length` it builds the domain and every
piece above it with sensible defaults, seeds a divergence-free velocity (and, with `scalar = true`,
a mean-zero scalar ``\\varphi``), and returns a `Simulation` at ``t = 0``. The second is
**domain-taking**: the same assembly on a `FixedDomain` you built yourself.

Advance it with [`advance!`](@ref) / [`run!`](@ref) / [`warmup!`](@ref). Read its measured state by
applying the observables to `sim.state` (e.g. `kinetic_energy(sim.state.velocity_spectral)`) or
through the cache's deposited observables (`velocity_physical(sim.cache)`); summarize it with
[`flow_parameters`](@ref), and track its progress with [`current_time`](@ref) /
[`current_step`](@ref).

# Setting the Reynolds number

By default the run is **forced and stationary** — a
[`VarianceController`](@ref GBGIsotropicTurbulence.Forcing.VarianceController) drives the whole-field
kinetic energy to the value given by the
[`kinetic_energy`](@ref GBGIsotropicTurbulence.Observables.kinetic_energy) keyword and holds it
there — and the viscosity is chosen from the grid rather than supplied:

  * **Derived viscosity** (no `viscosity` passed explicitly): the constructor picks the highest
    Reynolds number consistent with the resolution criterion `κ_max_η`, in two steps.

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
        ``\\eta \\approx 0.64\\Delta x`` at `κ_max_η = 2` against ``0.96\\Delta x`` for ``2/3``,
        and since ``\\nu \\propto f^{-4/3}`` that hands `HouLi` a ``\\mathrm{Re}_\\lambda`` about 31%
        higher on the same grid. Raise `κ_max_η` when comparing across strategies.

    The grid and `κ_max_η` together fix ``\\mathrm{Re}_\\lambda \\sim N^{2/3}``; `kinetic_energy` and
    `side_length` fix the units. The chosen ``\\nu``, ``\\varepsilon`` and ``\\mathrm{Re}_\\lambda``
    are logged.

    One precondition: the choice is self-consistent only if the run holds ``k`` near
    `kinetic_energy`. The default `VarianceController` does, to the tolerance its gain sets — its
    restoring term measures the whole-field ``k``, which is the quantity assumed here. Give the
    velocity a forcing that lets ``k`` float, or one holding some *other* quantity (a
    `VarianceRescaling(over = :band)` holds the band instead), and the ``\\nu`` chosen here no
    longer matches the run.

  * **Supplied viscosity**: pass `viscosity` and it is used directly; the two are alternatives, and
    passing both raises an `ArgumentError` rather than dropping one — for a decaying
    run (`velocity_forcing = NoForcing()`) or manual control. The derived viscosity is calibrated on a *stationary
    forced* balance (`Li2008`'s ``G`` is fitted to forced-isotropic DNS), so a decaying run should set
    ``\\nu`` explicitly: the resolution it buys is only meaningful while the box sustains the energy the
    law assumes.

# Arguments

All keyword except `domain`. The keywords split as the two forms do: the **domain group** is
consumed by the domain-building form, and the domain-taking form replaces the whole group with its
one positional argument; the **run group** is accepted by both.

The domain group:
- `domain` — a pre-built `FixedDomain`: the **positional** argument of the domain-taking form,
  standing in for every other keyword of this group.
- `grid_points_per_axis` — the number of grid points ``N`` along each side; required.
- `side_length = 2π` — the box side ``L``.
- `element_type = Float64`, `array_type = Array` — the real element type and storage backend.
- `dealiasing = TwoThirds()` — the [`DealiasingStrategy`](@ref) (``2/3`` sharp, `HouLi` smooth, or
  `PhaseShift`); it sets ``\\kappa_{\\max}`` and hence the CFL step.

The run group:
- `κ_max_η` — the resolution criterion ``\\kappa_{\\max}\\eta`` a derived ``\\nu`` is set from;
  ``\\ge 1.5`` is well-resolved, higher trades Reynolds number for margin. It defaults to `nothing`
  and the derivation then uses `2`; the sentinel is what lets the constructor tell an omitted keyword from
  an explicit one, so that giving both it and `viscosity` is an error rather than a silent drop.
- `viscosity` — the kinematic viscosity ``\\nu``, which is how the Reynolds number is set (it is
  ``1/\\nu`` only in units where ``u' = L = 1``; measure ``\\mathrm{Re}_\\lambda`` for the run's actual value); omit to derive ``\\nu`` from the grid.
- `kinetic_energy = 1.5` — the initial, and when forced the held, kinetic energy ``k``; `1.5` gives
  an r.m.s. velocity ``u' = \\sqrt{2k/3} = 1``.
- `schmidt = 1.0` — the Schmidt number ``\\mathrm{Sc}`` (scalar diffusivity
  ``\\varkappa = \\nu/\\mathrm{Sc}``). **The resolution criterion covers the velocity, not the
  scalar**, whose cutoff at ``\\mathrm{Sc} > 1`` is the finer Batchelor scale
  ``\\eta_B = \\eta/\\sqrt{\\mathrm{Sc}}`` — under-resolved by ``\\sqrt{\\mathrm{Sc}}`` on the same
  grid, with `scalar_dissipation` then measuring a truncated field. The package targets
  ``\\mathrm{Sc} = O(1)``, with no Batchelor-range machinery. The constructor **warns** when the
  run's ``\\kappa_{\\max}\\eta_B`` falls below the ``1.5`` well-resolved floor — in **either**
  viscosity mode, since the check reads the resolved ``\\nu`` however it was obtained — a warning,
  not an error, so a deliberately under-resolved scalar stays reachable but not silent; the remedy
  is `κ_max_η` raised by ``\\sqrt{\\mathrm{Sc}}``, or `viscosity` set by hand.
- `scalar = false`, `scalar_variance = 1.0` — whether to evolve a passive scalar (a mean-zero
  ``\\varphi``), and its initial variance.
- `velocity_forcing`, `scalar_forcing` — an [`AbstractForcing`](@ref) (or a
  [`DeferredForcing`](@ref GBGIsotropicTurbulence.Forcing.DeferredForcing) from an
  operator-free constructor); `velocity_forcing` left at `nothing` means the default — a
  `VarianceController` driving the whole-field kinetic energy to the `kinetic_energy` value — and
  `scalar_forcing` defaults to `NoForcing()`. The velocity and scalar are forced independently.
  Under a derived ν a hand-built velocity forcing is **checked against the ν calibration**: one that
  holds a different target, a band instead of the whole field, or nothing at all draws a warning,
  since the chosen ν then describes a state the run never reaches.
- `envelope_wavenumber = 2.0` — the large-scale envelope wavenumber ``\\kappa_p`` of the initial
  condition, for the **velocity and the scalar alike** (each shell-summed spectrum peaks at
  ``\\kappa_p/\\sqrt{2}``); it does **not** shape the profile when `initial_spectrum` is given (the model does), but it still
  sets the integral scale of the *assumed state* that model is evaluated at. Keep ``\\kappa_p`` well
  below the dealias cutoff: a value near or above it concentrates the pre-rescale seed in shells
  the mask holds empty, and no guard checks this — unlike a forcing band, which warns.
- `initial_spectrum = nothing` — draw the initial velocity from a
  [`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology) `EnergySpectrum` (say
  `VonKarman1948()`) instead of the default large-scale Gaussian. A model spectrum needs a flow
  state, and at ``t = 0`` there is nothing measured yet, so one is *assumed* — a stand-in, not a
  measurement of the field about to be seeded. The assumed state reads: ``\\varepsilon`` from the
  `Li2008` stationary-dissipation law at the requested `kinetic_energy` and box side, ``u'`` from
  that same energy, ``\\nu`` as resolved above, and `1/envelope_wavenumber` for the integral scale
  (rather than the ``L_{11}`` the seeded field will actually have). Note the ``\\varepsilon`` half:
  it is the *stationary forced* estimate, so on a decaying run — where the explicit-``\\nu`` advice
  above exists precisely because that balance does not hold — the model's dissipation-range
  placement inherits the same mismatch.
  The seeded field is then normalized to `kinetic_energy`, so the model fixes the *shape* and the
  assumed state only positions it. This shapes the **velocity** only; a scalar is always seeded from
  the default Gaussian envelope, and a scalar-spectrum initial condition is reached by calling
  [`random_scalar_spectral!`](@ref GBGIsotropicTurbulence.State.random_scalar_spectral!) on the
  built run and announcing the change with
  [`fields_modified!`](@ref GBGIsotropicTurbulence.Cache.fields_modified!).
- `field_integration_scheme = IFLowStorageRK3()`, `cfl = recommended_cfl(field_integration_scheme, domain)` — the
  [`AbstractIntegrator`](@ref) scheme and its advective-CFL ceiling (adapts to `dealiasing`).
- `max_dt = Inf` — a further ceiling on the adaptive timestep, stated in the run's own time units,
  and off unless set. The adaptive step is the smallest of three bounds:
  the advective rule ``\\Delta t = C\\Delta x / u_{\\max}``, the longest mode's diffusive-decay
  time ``1/(D\\kappa_{\\min}^{2})`` — with ``D`` the **larger** of the run's diffusivities (``\\nu``,
  and ``\\varkappa = \\nu/\\mathrm{Sc}`` when a scalar rides), since the faster-diffusing field
  decays first — and this. The advective
  rule alone diverges as a decaying flow approaches rest — past some step the integrating factor
  annihilates every mode and the clock advances by a number that means nothing — and it is the
  diffusive-decay bound that stops that, needing no constant from the caller. `max_dt` is for a
  ceiling only the caller knows, since any *default* constant would be a claim about the velocity
  scale they happened to choose.
- `number_of_particles = 0`, `interpolation_scheme = CatmullRom`, `unwrapped = false` — the number
  of Lagrangian `Tracers`, the **spatial** scheme that evaluates a field at their positions, and
  whether to also track the winding-preserving unwrapped positions (read with
  [`unwrapped_positions`](@ref GBGIsotropicTurbulence.Particles.unwrapped_positions) — what a
  mean-square-displacement diagnostic needs); all three forwarded to the `Tracers` constructor.
- `particle_integration_scheme = Heun()` — the scheme that advances the trajectories in time, an
  [`AbstractParticleIntegrator`](@ref GBGIsotropicTurbulence.Particles.AbstractParticleIntegrator);
  its **registers** — the per-step scratch that scheme needs, meaningless to read between calls —
  are allocated for you. Pass
  [`AdamsBashforth`](@ref GBGIsotropicTurbulence.Particles.AdamsBashforth)`()` when trajectory
  accuracy in time limits a measurement: it costs one stored array per extra order and saves an
  interpolation per step.
- `rng` — the random stream for the initial condition and the tracer seeding (defaults to
  `Random.default_rng()`).

!!! note "The default drives the kinetic energy to a set value, so read it as a control target"
    `VarianceController` restores ``k`` exponentially to `kinetic_energy`, pinning ``u'`` and the
    scale of ``\\mathrm{Re}_\\lambda``. It does not *impose* the value step by step as a rescale
    does, so the fluctuation it leaves is genuine — but it is a controlled variable's fluctuation,
    with the gain setting its amplitude. For the free fluctuation of ``k``, force with fixed
    injection ([`ConstantPower`](@ref GBGIsotropicTurbulence.Forcing.ConstantPower)) instead.

# Examples
The two ways in, and the two ways to set the Reynolds number:

```julia
# Derived viscosity — a 128³ forced-stationary run, ν set from the resolution criterion:
sim = Simulation(grid_points_per_axis = 128)

# Supplied viscosity — set ν directly, carry a passive scalar, force at constant power:
sim = Simulation(grid_points_per_axis = 128, viscosity = 1e-2;
                 scalar = true, velocity_forcing = ConstantPower(injection_rate = 0.1))

# Domain-taking — build the frame yourself, then hand it over:
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
- `domain`, `buffers`, `generator`, `field_integration_scheme` — the `FixedDomain`, `IntegratorBuffers`,
  the `ResolvedGenerator` (whose `conditions` field is the run's `FlowConditions`), and
  the chosen scheme.
- `tracers`, `particle_integration_scheme`, `particle_buffers` — the `Tracers` being advected along with the
  fields, the scheme advancing them along their trajectories, and that scheme's registers. All `nothing` when the run carries no tracers.
- `cfl`, `clock` — the advective-CFL coefficient, and the time/step counter.
"""
struct Simulation{DOM, FB, IG, GN<:ResolvedGenerator, RF, DF, TR, PI, PB}
  domain::DOM
  buffers::FB
  generator::GN            # ResolvedGenerator: the equations of motion + conditions + assembly scratch
  field_integration_scheme::IG
  state::RF                # ResolvedFields: the evolving (û, φ̂), the single source of truth
  cache::DF                # ObservablesCache: what the last iteration deposited, for an observation to read
  tracers::TR              # Tracers, or nothing — trajectory STATE only
  particle_integration_scheme::PI  # AbstractParticleIntegrator, or nothing
  particle_buffers::PB     # ParticleIntegratorBuffers for that scheme, or nothing
  cfl::Float64
  max_dt::Float64          # a ceiling on the adaptive step, in the caller's own units; Inf = none
  clock::Clock
end


# A forcing may be given ready-built (an `AbstractForcing`) or as a factory `domain -> AbstractForcing`
# — the latter lets a banded forcing be named before the domain exists (`domain -> ConstantPower(domain;
# injection_rate)`), since a forcing precomputes its band from `domain`.
_materialize_forcing(f::AbstractForcing, ::FixedDomain) = f
_materialize_forcing(f, domain::FixedDomain) = f(domain)


# The ν derivation assumed the run HOLDS k = `kinetic_energy`. A hand-built forcing that holds a
# different target, holds a band instead of the whole field, or holds nothing at all leaves that ν
# calibrated against a state the run never reaches — the docstring names the precondition, and this
# names the violation at the one moment it is checkable (the band's shells are not recoverable from
# a built forcing, so only what the strategy itself records is compared).
function _warn_grid_mode_forcing_mismatch(vf::VarianceController, kinetic_energy)
  isapprox(vf.target, kinetic_energy; rtol = 1e-8) ||
    @warn "Simulation (derived viscosity): ν was calibrated for k = $kinetic_energy (`kinetic_energy`), " *
          "but the velocity forcing holds target = $(vf.target). The run will settle at the " *
          "forcing's target, and κ_max·η / Re_λ will not match the calibration. Pass the same " *
          "value to both, or set `viscosity` yourself."
  return nothing
end

function _warn_grid_mode_forcing_mismatch(vf::VarianceRescaling, kinetic_energy)
  if vf.over !== :total
    @warn "Simulation (derived viscosity): ν was calibrated assuming the run holds the WHOLE-field " *
          "k = $kinetic_energy, but this `VarianceRescaling(over = :band)` holds only the band " *
          "and lets k settle elsewhere. Use `over = :total` with the same target, or set " *
          "`viscosity` yourself."
  elseif !isapprox(vf.target, kinetic_energy; rtol = 1e-8)
    @warn "Simulation (derived viscosity): ν was calibrated for k = $kinetic_energy (`kinetic_energy`), " *
          "but the velocity forcing holds target = $(vf.target). Pass the same value to both, " *
          "or set `viscosity` yourself."
  end
  return nothing
end

_warn_grid_mode_forcing_mismatch(vf::NoForcing, kinetic_energy) =
  (@warn "Simulation (derived viscosity): ν was calibrated assuming a forcing holds k = $kinetic_energy, " *
         "but the run is unforced and will decay away from that state. The derived viscosity is calibrated " *
         "on a stationary forced balance — a decaying run should set `viscosity` explicitly.";
   nothing)

_warn_grid_mode_forcing_mismatch(vf::AbstractForcing, kinetic_energy) =
  (@warn "Simulation (derived viscosity): ν was calibrated assuming the run holds k = $kinetic_energy, " *
         "which a $(nameof(typeof(vf))) does not hold (it drives a rate or a band, and k settles " *
         "wherever the balance puts it). The κ_max·η / Re_λ the constructor reports are then " *
         "estimates for a state the run may not reach; set `viscosity` yourself for a calibrated " *
         "run.";
   nothing)


function Simulation(domain::FixedDomain;
                    kinetic_energy::Real = 1.5, κ_max_η = nothing, viscosity = nothing,
                    schmidt::Real = 1.0,
                    velocity_forcing = nothing,
                    scalar_forcing = NoForcing(),
                    field_integration_scheme::AbstractIntegrator = IFLowStorageRK3(),
                    cfl::Real = recommended_cfl(field_integration_scheme, domain), max_dt::Real = Inf,
                    scalar::Bool = false, scalar_variance::Real = 1.0,
                    envelope_wavenumber::Real = 2.0, initial_spectrum = nothing,
                    number_of_particles::Integer = 0, interpolation_scheme = CatmullRom,
                    unwrapped::Bool = false,
                    particle_integration_scheme::AbstractParticleIntegrator = Heun(),
                    rng = Random.default_rng())
  # The stationary dissipation the box sustains (`Li2008`) — a modeled estimate, not a measurement.
  # It sets the derived ν and shapes a `Phenomenology` `initial_spectrum`.
  # k = ½⟨|u|²⟩ is non-negative by construction, and the seeder rescales by √(k/current), so a
  # negative value surfaced far downstream as a DomainError out of `sqrt` with nothing naming the
  # argument that caused it. Likewise a scalar variance, ⟨φ²⟩ ≥ 0.
  number_of_particles >= 0 ||
    throw(ArgumentError("`number_of_particles` must be non-negative, got $number_of_particles: a " *
                        "negative count was silently routed to the tracer-free branch, so the run " *
                        "carried no tracers and never said so"))
  max_dt > 0 ||
    throw(ArgumentError("`max_dt` must be positive, got $max_dt"))
  cfl > 0 ||
    throw(ArgumentError("`cfl` must be positive, got $cfl: it scales the advective timestep " *
                        "Δt = cfl·Δx/u_max, so a non-positive value stops or reverses the clock"))
  kinetic_energy > 0 ||
    throw(ArgumentError("`kinetic_energy` must be positive, got $kinetic_energy: it is " *
                        "k = ½⟨|u|²⟩, which cannot be negative, and a zero-energy field has no " *
                        "spectrum to seed"))
  scalar_variance >= 0 ||
    throw(ArgumentError("`scalar_variance` must be non-negative, got $scalar_variance: it is ⟨φ²⟩"))
  side_length = domain.grid.domain_size[1]
  ε = stationary_dissipation(Li2008(), kinetic_energy, side_length)
  # Both arguments set ν, by different routes, so accepting both would silently honour one of them.
  if !isnothing(viscosity) && !isnothing(κ_max_η)
    throw(ArgumentError("`viscosity` and `κ_max_η` are two ways to set ν — `viscosity` fixes it \
directly, `κ_max_η` derives it from the grid. Pass one, not both."))
  end
  if isnothing(viscosity)                              # no ν supplied: derive the highest Re resolved
    resolution = isnothing(κ_max_η) ? 2 : κ_max_η
    # ν is solved from this, so a non-positive or non-finite resolution yields ν = 0, NaN or Inf and
    # a run that is not a run. κ_max·η is a positive, finite resolution criterion by construction.
    (isfinite(resolution) && resolution > 0) ||
      throw(ArgumentError("`κ_max_η` must be positive and finite, got $κ_max_η: it is the " *
                          "resolution criterion κ_max·η, from which the viscosity is solved"))
    # `kolmogorov_length`'s η = (ν³/ε)^(1/4), inverted: with κ_max·η fixed at `resolution`,
    # η = resolution/κ_max and ν = (ε η⁴)^(1/3). No inverse of that law exists to call, so the
    # arithmetic stays here — but the two are pinned against each other by a round-trip test
    # (solve for ν, then measure η through `kolmogorov_length` and recover `resolution`), so neither
    # can drift from the other in silence.
    ν = ε^(1//3) * (resolution / max_wavenumber(domain))^(4//3)
    # Through the canonical reduction, not a second spelling of it: `integral_scale` does not enter
    # Re_λ, so any positive value serves — the measured-state bridge is what owns this formula.
    reλ = taylor_reynolds(FlowParameters(; viscosity = ν, dissipation = ε,
                                         rms_velocity = sqrt(2 * kinetic_energy / 3),
                                         integral_scale = one(ν), schmidt))
    @info "Simulation: grid-resolved at κ_max·η = $(resolution)" viscosity=ν dissipation=ε Re_λ=reλ
  else
    ν = Float64(viscosity)
  end

  buffers = allocate_buffers(field_integration_scheme, domain; scalar)
  # `nothing` means the default controller holding `kinetic_energy` — a sentinel rather than a
  # default closure, so a HAND-BUILT forcing is detectable: a derived ν was calibrated on the
  # assumption that the run holds k = `kinetic_energy`, and a forcing that holds something else
  # (or nothing) silently voids that calibration. The check below warns exactly there
  # (owner-ruled 2026-08-24); explicit-ν runs and the default forcing stay silent.
  vf = _materialize_forcing(velocity_forcing === nothing ?
                              VarianceController(domain; target = kinetic_energy) :
                              velocity_forcing, domain)
  viscosity === nothing && velocity_forcing !== nothing &&
    _warn_grid_mode_forcing_mismatch(vf, kinetic_energy)
  conditions = FlowConditions(; viscosity = ν, schmidt,
                    velocity_forcing = vf,
                    scalar_forcing = _materialize_forcing(scalar_forcing, domain))
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
  if scalar
    η = (ν^3 / ε)^(1//4)
    κ_max_η_B = max_wavenumber(domain) * η / sqrt(schmidt)
    if κ_max_η_B < 1.5
      @warn "Simulation: the scalar is under-resolved — κ_max·η_B = $(round(κ_max_η_B, digits = 2)) " *
            "against the well-resolved floor of 1.5. The grid resolves the velocity " *
            "(κ_max·η = $(round(max_wavenumber(domain) * η, digits = 2))), but at Sc = $(schmidt) " *
            "the scalar's Batchelor scale η_B = η/√Sc is finer by √Sc, and `scalar_dissipation` " *
            "will measure a truncated field. Raise `κ_max_η` by √Sc, lower `schmidt`, or set " *
            "`viscosity` yourself if the truncation is deliberate. (η here uses the stationary " *
            "dissipation estimate at the requested `kinetic_energy`; a decaying run resolves " *
            "better than this as it decays.)"
    end
  end


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
    Tracers(domain; number_of_particles, interpolation_scheme = interpolation_scheme, unwrapped, rng) : nothing
  # The cache is built first: it carries the Lagrangian sample history a multistep particle integration scheme
  # integrates over, so the scheme's registers are allocated against it.
  cache = ObservablesCache(domain; scalar,
                           number_of_particles = tracers === nothing ? 0 : Int(number_of_particles),
                           history_depth = history_depth(particle_integration_scheme))
  particle_buffers = tracers === nothing ? nothing :
                     allocate_buffers(particle_integration_scheme, tracers, cache)
  deposit!(cache, state, domain, buffers)        # the seeding deposit: the first instant observed is t₀
  tracers === nothing || deposit!(cache, tracers, velocity_physical(cache))
  return Simulation(domain, buffers, ResolvedGenerator(domain, conditions; scalar), field_integration_scheme, state, cache,
                    tracers, tracers === nothing ? nothing : particle_integration_scheme, particle_buffers,
                    Float64(cfl), Float64(max_dt), Clock(0.0, 0))
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
  # The velocity sample rides the same re-deposit: the positions are unchanged, so re-depositing
  # from the freshly deposited velocity restores the values the announcement made stale.
  sim.tracers === nothing ||
    deposit!(sim.cache, sim.tracers, velocity_physical(sim.cache))
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
                max(conditions.viscosity, conditions.viscosity / conditions.schmidt)
  κ_min = 2π / Float64(sim.domain.grid.domain_size[1])
  resolution = 1 / (diffusivity * κ_min^2)
  return min(advective, resolution, sim.max_dt)
end


"""
    advance!(sim; dt = nothing)

Advance `sim` by one timestep in place and return it. Pass `dt` to force a fixed step; with
`dt = nothing` the step is adaptive — the smallest of the advective-CFL value for the current
velocity, the longest mode's diffusive-decay time (the same diffusive-decay bound the `Simulation`
docstring states), and `max_dt`.

Closes the iteration with [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!), so the cache
is readable when it returns. Advects the tracers, if any, under the run's chosen particle
integration scheme, and updates the clock.

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
    advect!(sim.particle_integration_scheme, sim.tracers, velocity_physical(sim.cache), sim.domain,
            sim.particle_buffers, Δt)
    # The run's own advance, not an out-of-band reposition: the epoch moves so the previous sample
    # reads stale, but the history the advance just extended stays intact.
    advance_particles_epoch!(sim.cache)
    deposit!(sim.cache, sim.tracers, velocity_physical(sim.cache))
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
    copyto!(point_coordinates(sim.tracers.unwrapped_positions), point_coordinates(sim.tracers.positions))
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
                        "silently disagree with the physical field. Repair by a physical round " *
                        "trip — `to_physical` then `to_spectral` projects onto the nearest real " *
                        "field's spectrum — or fix the write."))
  return nothing
end



"""
    run!(callback, sim)
    run!(sim) do sim … end

Observe and advance `sim` until the observation stops it.

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
[`current_step`](@ref); an eddy-turnover budget accumulates ``\\Delta t \\varepsilon/k`` from the
observables it computes; spin-up to stationarity is the packaged [`StationarityCriterion`](@ref).
Whatever the callback needs beyond the cached observables it computes itself, at its own cadence,
with the exported reductions and recoveries.

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
  gate_skewness::Bool               # also require S to have plateaued (and |S| ≥ skew_floor)
  skew_floor::Float64           # minimum |S| for a plateau to count as developed turbulence
  sample_gap::Float64           # min turnover spacing between stored samples
  turn::Vector{Float64}
  eps::Vector{Float64}
  phi2::Vector{Float64}
  skew::Vector{Float64}
  converged::Bool
end

StationarityMonitor(; min_turnovers, window_turnovers, tol, gate_scalar, gate_skewness, skew_floor) =
  StationarityMonitor(Float64(min_turnovers), Float64(window_turnovers), Float64(tol),
                      gate_scalar, gate_skewness, Float64(skew_floor), Float64(window_turnovers) / 40,
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
  flat_k = !m.gate_skewness ||
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
  S = m.gate_skewness ? derivative_skewness(sim.state.velocity_spectral, sim.domain) : 0.0
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

At each iteration it measures the dissipation ``\\varepsilon`` and the kinetic energy ``k``, accumulates
the eddy-turnover clock ``\\Delta t \\varepsilon/k``, and tests ``\\varepsilon`` for flatness over a
trailing window; it stops the run when every gate holds, or gives up with a warning at
`max_turnovers`. The gate reads ``\\varepsilon`` alone: the small scales settle last, so a flat
``\\varepsilon`` is the strict indicator — where ``k`` is whatever the forcing shapes: clamped by a
rescale, driven toward its target by the default controller, ringing under fixed injection — so its
flatness would certify the forcing, not the flow.

# Arguments
- `gate_scalar` — when the run's scalar is forced, also require the scalar variance
  ``\\langle\\varphi^2\\rangle`` to be flat (the scalar settles after the velocity; an unforced
  scalar has no stationary state and is never gated).
- `gate_skewness` — also require the velocity-derivative skewness to have plateaued **and** reached
  ``\\lvert S\\rvert \\ge \\texttt{skew\\_floor}`` — the "real turbulence yet" signal, exactly as
  strict as its floor (see `skew_floor` below): a
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
The fields are not the keywords: `gate_skewness`, `min_turnovers`, `window_turnovers`, `tol` and
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
                                gate_scalar, gate_skewness = gate_skewness, skew_floor)
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




# ————————————————————————————————————————————————————————————————————————————————————————————————
# HDF5 persistence. The bare generics live here so the docstrings and the docs build work without
# HDF5 in the environment; the methods live in the `GBGIsotropicTurbulenceHDF5Ext` weak-dependency
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
every register and plan are recomputed on read. A stochastic forcing's evolving state is
deliberately not stored (its parameters are), so continuation is exact for deterministic
forcings. Available once the `HDF5` package is loaded; opening and closing the file is the
caller's job, and `parent[name] = sim` is equivalent sugar.

The arguments are:
- `parent` — the open HDF5 file or group to write under.
- `name` — the created group's name.
- `sim` — the run to checkpoint.

Returns the created group. Restore with [`read_simulation`](@ref).
"""
function write_simulation end


"""
    read_simulation(parent::HDF5.H5DataStore, name::AbstractString;
                    array_type = Array) -> Simulation

Restore a run from the group [`write_simulation`](@ref) wrote: rebuild the [`Simulation`](@ref)
through its own constructor from the recorded parameters, overwrite the freshly seeded state and
positions with the stored ones, re-deposit every observable the schedule carries, restore the
Lagrangian sample history fill-aware (a scheme of a different order keeps what fits and
bootstraps the rest), and set the clock — the next [`advance!`](@ref) continues the checkpointed
run. The one deliberate divergence is a stochastic forcing, which resumes on a fresh stream. A
group not written by `write_simulation`, or written by a newer schema version, is refused with an
`ArgumentError`. Available once the `HDF5` package is loaded.

The arguments are:
- `parent` — the open HDF5 file or group holding the checkpoint group.
- `name` — the group's name.
- `array_type = Array` — the storage backend the restored run lives on; the reader names it, so a
  checkpoint written on one backend loads on any other.
"""
function read_simulation end


end # module SimulationRun
