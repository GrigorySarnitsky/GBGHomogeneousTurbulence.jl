# SimulationRun — the ergonomic run layer. A `Simulation` bundles the domain, buffers, conditions,
# integrator, spectral state (û, φ̂), and any tracers; `advance!`/`run!`/`warmup!` own the
# CFL-adaptive time loop. It holds no physics or numerics of its own — it wires the pieces of
# SimulationDomain/State/Generator/Observables/Forcing/Propagator/Particles so a case is a few lines to
# set up and run, warm-up included, while every piece stays reachable for a hand-run loop.
#
# The loop maintains one invariant: on entry to a step, `buffers.velocity_physical` / `buffers.vorticity_start` hold the
# current physical u / ω — the start-of-step fields `step!` needs and the diagnostics read. A step
# advances û, φ̂ and then refreshes those cached fields from the new û; the refreshed velocity is also
# the end-of-step field used to advect the tracers (Heun on u(tₙ), u(tₙ₊₁)). `step!` only reads the
# cached fields, so they survive the step and the saved copy is exact.

"""
    SimulationRun

The run layer: [`Simulation`](@ref) (the assembled state of a case) and the functions that advance it —
[`advance!`](@ref) (one step), [`run!`](@ref) (advance to a stopping condition, with an optional
per-interval callback), and [`warmup!`](@ref) (spin up to statistical stationarity).
[`current_time`](@ref) and [`current_step`](@ref) report the elapsed time and step count, and the
observables (`kinetic_energy`, `dissipation`, `scalar_variance`, `energy_spectrum`, `integral_scale`)
accept a `Simulation` directly.
"""
module SimulationRun

using GBGPeriodicFields
using Random
using ..SimulationDomain: FixedDomain, spectral_vector, scalar_spectral, physical_vector,
                          DealiasingStrategy, TwoThirds, max_wavenumber
using ..State: ResolvedFields, random_solenoidal_velocity!, random_scalar!
using ..Generator: velocity_to_physical!, vorticity_to_physical!
using ..Observables: max_speed, derivative_skewness
import ..Observables: kinetic_energy, dissipation, scalar_variance, energy_spectrum, integral_scale
using ..Forcing: AbstractForcing, NoForcing, BandRescaling
using ..Propagator: AbstractIntegrator, FlowConditions, IntegratorBuffers, allocate_buffers, step!,
                    recommended_cfl, IFLowStorageRK3
using ..Particles: Tracers, advect!
using ..Phenomenology: FlowParameters
using ..Phenomenology.Spectra: EnergySpectrum, spectrum
using ..Phenomenology.Scalings: Li2008, stationary_dissipation

export Simulation, advance!, run!, warmup!, current_time, current_step, flow_parameters,
       validate_spectrum


mutable struct Clock
  time::Float64
  step::Int
end


"""
    Simulation(; grid_points_per_axis, k_max_η = 2, energy = 1.5, side_length = 2π, scalar_type = Float64,
                 array_type = Array, dealiasing = TwoThirds(), kwargs...)
    Simulation(domain; k_max_η = 2, energy = 1.5, kwargs...)

A ready-to-run case — the [`FixedDomain`](@ref), the [`IntegratorBuffers`](@ref), the
[`FlowConditions`](@ref), the chosen integrator, the [`ResolvedFields`](@ref) state (the spectral velocity
``\\hat{\\boldsymbol u}`` and passive scalar ``\\hat\\varphi``), any [`Tracers`](@ref), and a clock. The first form is the
**front door**: from `grid_points_per_axis` and `side_length` it builds every piece with sensible defaults, seeds a
divergence-free velocity (and, with `scalar = true`, a mean-zero scalar ``\\varphi``), and returns a
`Simulation` at ``t = 0``; the second takes a `FixedDomain` you built yourself. Advance it with
[`advance!`](@ref) / [`run!`](@ref) / [`warmup!`](@ref); read its measured state with the observables
([`kinetic_energy`](@ref), [`dissipation`](@ref), …) and [`flow_parameters`](@ref), and its progress
with [`current_time`](@ref) / [`current_step`](@ref).

# Setting the Reynolds number

By default the run is **forced and stationary** — a `BandRescaling` holds the total energy at `energy` —
and the viscosity is chosen from the grid rather than supplied:

  * **Grid mode** (no `viscosity`): the constructor picks the highest Reynolds number the grid resolves.
    It reads the dissipation the box sustains from the box-normalized dissipation law `Li2008` (in
    `Phenomenology.Scalings`), ``\\varepsilon = (k/G)^{3/2}/L`` with `energy` the kinetic energy ``k`` and
    `side_length` the side ``L``, then sets ``\\nu`` so that ``\\kappa_{\\max}\\eta`` equals `k_max_η` — the
    resolution criterion, with ``\\kappa_{\\max}`` the [`max_wavenumber`](@ref) (the de-aliasing cutoff,
    **not** the grid Nyquist). Since ``\\kappa_{\\max}\\eta = f\\pi\\,\\eta/\\Delta x`` with ``f`` the
    retained-Nyquist fraction, `k_max_η = 2` means ``\\Delta x \\approx \\eta``. `energy` and `side_length` fix
    the units; the grid and `k_max_η` fix ``\\mathrm{Re}_\\lambda \\sim N^{2/3}``. The chosen ``\\nu``,
    ``\\varepsilon``, and ``\\mathrm{Re}_\\lambda`` are logged.
  * **Explicit mode**: pass `viscosity` and it is used directly (`k_max_η` is ignored) — for a decaying
    run (`velocity_forcing = NoForcing()`) or manual control.

# Keywords

The keywords marked *(front door only)* configure the `FixedDomain` and are consumed by the first form;
the rest are forwarded to the `Simulation(domain; …)` form.

- `grid_points_per_axis` — the number of grid points ``N`` along each side (front door only); required.
- `k_max_η = 2` — the resolution criterion ``\\kappa_{\\max}\\eta`` used to set ``\\nu`` in grid mode;
  ``\\ge 1.5`` is well-resolved, higher trades Reynolds number for margin.
- `viscosity` — the kinematic viscosity ``\\nu`` (sets ``\\mathrm{Re} = 1/\\nu``); omit for grid mode.
- `energy = 1.5` — the initial, and when forced the held, kinetic energy ``k``; `1.5` gives ``u' = 1``.
- `side_length = 2π` — the box side ``L`` (front door only).
- `scalar_type = Float64`, `array_type = Array` — the real element type and storage backend (front door).
- `dealiasing = TwoThirds()` — the [`DealiasingStrategy`](@ref) (``2/3`` sharp, or `HouLi` smooth); it
  sets ``\\kappa_{\\max}`` and hence the CFL step (front door only).
- `schmidt = 1.0` — the Schmidt number ``\\mathrm{Sc}`` (scalar diffusivity ``\\nu/\\mathrm{Sc}``).
- `velocity_forcing`, `scalar_forcing` — an [`AbstractForcing`](@ref) (or a `DeferredForcing` from an
  operator-free constructor); `velocity_forcing` defaults to a `BandRescaling` holding the total energy
  at `energy`, `scalar_forcing` to `NoForcing()`. The velocity and scalar are forced independently.
- `scalar = false`, `scalar_variance = 1.0`, `peak_wavenumber = 2.0` — whether to evolve a passive
  scalar (a mean-zero ``\\varphi``), its initial variance, and the large-scale spectral peak of the
  initial condition.
- `initial_spectrum = nothing` — a `Phenomenology` `EnergySpectrum` (e.g. `VonKarman1948()`) to draw the
  initial velocity from, in place of the default large-scale Gaussian; its shape is evaluated at the
  run's state (its integral scale set to `1/peak_wavenumber`) and normalized to `energy`.
- `integrator = IFLowStorageRK3()`, `cfl = recommended_cfl(integrator, domain)` — the
  [`AbstractIntegrator`](@ref) scheme and its advective-CFL ceiling (adapts to `dealiasing`).
- `ntracers = 0`, `tracer_scheme = CatmullRom` — the number of Lagrangian [`Tracers`](@ref) and their
  interpolation scheme.
- `rng` — the random stream for the initial condition and the tracer seeding.
"""
struct Simulation{DOM, FB, IG, VF<:AbstractForcing, SF<:AbstractForcing, RF, TR, TV}
  domain::DOM
  buffers::FB
  conditions::FlowConditions{VF, SF}
  integrator::IG
  state::RF                # ResolvedFields: the evolving (û, φ̂), the single source of truth
  tracers::TR              # Tracers, or nothing
  tracer_velocity::TV      # physical buffer holding u(tₙ) for the Heun advect, or nothing
  cfl::Float64
  clock::Clock
end


# A forcing may be given ready-built (an `AbstractForcing`) or as a factory `domain -> AbstractForcing`
# — the latter lets a banded forcing be named before the domain exists (`domain -> ConstantPower(domain;
# power)`), since a forcing precomputes its band from `domain`.
_resolve_forcing(f::AbstractForcing, ::FixedDomain) = f
_resolve_forcing(f, domain::FixedDomain) = f(domain)


function Simulation(domain::FixedDomain;
                    energy::Real = 1.5, k_max_η::Real = 2, viscosity = nothing,
                    schmidt::Real = 1.0,
                    velocity_forcing = BandRescaling(domain; energy, target = :total),
                    scalar_forcing = NoForcing(),
                    integrator::AbstractIntegrator = IFLowStorageRK3(),
                    cfl::Real = recommended_cfl(integrator, domain),
                    scalar::Bool = false, scalar_variance::Real = 1.0,
                    peak_wavenumber::Real = 2.0, initial_spectrum = nothing,
                    ntracers::Integer = 0, tracer_scheme = CatmullRom,
                    rng = Random.default_rng())
  # The stationary dissipation the box sustains (`Li2008`) — a modelled estimate, not a measurement.
  # It sets ν in grid mode and shapes a `Phenomenology` `initial_spectrum`.
  side_length = domain.grid.domain_size[1]
  ε = stationary_dissipation(Li2008(), energy, side_length)
  if isnothing(viscosity)                                    # grid mode: highest Re the grid resolves
    ν = ε^(1//3) * (k_max_η / max_wavenumber(domain))^(4//3)
    reλ = (2 * energy / 3) * sqrt(15 / (ε * ν))
    @info "Simulation: grid-resolved at κ_max·η = $(k_max_η)" viscosity=ν dissipation=ε Re_λ=reλ
  else
    ν = Float64(viscosity)
  end

  buffers = allocate_buffers(integrator, domain; scalar)
  conditions = FlowConditions(; viscosity = ν, schmidt,
                    velocity_forcing = _resolve_forcing(velocity_forcing, domain),
                    scalar_forcing = _resolve_forcing(scalar_forcing, domain))

  state = ResolvedFields(domain; scalar)
  ic_spectrum = nothing
  if initial_spectrum isa EnergySpectrum       # a `Phenomenology` model → evaluate at the run's state
    fp = FlowParameters(; viscosity = ν, dissipation = ε, rms_velocity = sqrt(2 * energy / 3),
                        integral_scale = inv(peak_wavenumber), schmidt)
    ic_spectrum = κ -> spectrum(initial_spectrum, κ, fp)
  elseif !isnothing(initial_spectrum)
    ic_spectrum = initial_spectrum             # a raw κ -> E(κ) function
  end
  random_solenoidal_velocity!(state.velocity, domain; energy, peak_wavenumber, spectrum = ic_spectrum, rng)
  scalar && random_scalar!(state.scalar, domain; variance = scalar_variance, peak_wavenumber, rng)

  tracers = ntracers > 0 ? Tracers(domain, ntracers; scheme = tracer_scheme, rng) : nothing
  tracer_velocity = ntracers > 0 ? physical_vector(domain) : nothing

  sim = Simulation(domain, buffers, conditions, integrator, state, tracers, tracer_velocity,
                   Float64(cfl), Clock(0.0, 0))
  return _refresh_cached_fields!(sim)
end

function Simulation(; grid_points_per_axis::Integer, side_length::Real = 2π,
                    scalar_type::Type = Float64, array_type = Array,
                    dealiasing::DealiasingStrategy = TwoThirds(), kwargs...)
  return Simulation(FixedDomain(grid_points_per_axis, side_length; dealiasing, scalar_type, array_type); kwargs...)
end


# Recompute the cached physical velocity and vorticity from the current û — the start-of-step fields
# the next `step!` reads and the diagnostics use. Preserves û (the allocating-style transform copies).
_refresh_cached_fields!(sim::Simulation) =
  (velocity_to_physical!(sim.buffers.velocity_physical, sim.state.velocity, sim.domain, sim.buffers.velocity_copy);
   vorticity_to_physical!(sim.buffers.vorticity_start, sim.state.velocity, sim.domain, sim.buffers.vorticity_spectral); sim)


# Observables on a `Simulation` — thin wrappers extending the `Observables` generics by reading the
# spectral state `sim.state` directly: `kinetic_energy`/`scalar_variance`/`energy_spectrum`/`integral_scale`
# are Parseval reductions of û/φ̂; `dissipation` curls û into the spectral-vorticity scratch (used as a
# workspace) and reduces it. None reads the physical scratch as state.
kinetic_energy(sim::Simulation) = kinetic_energy(sim.state.velocity)
dissipation(sim::Simulation) =
  (curl!(sim.buffers.vorticity_spectral, sim.state.velocity, sim.domain.multipliers);
   dissipation(sim.buffers.vorticity_spectral, sim.conditions.viscosity))
scalar_variance(sim::Simulation) = sim.state.scalar === nothing ? NaN : scalar_variance(sim.state.scalar)
energy_spectrum(sim::Simulation) = energy_spectrum(sim.state.velocity, sim.domain)
integral_scale(sim::Simulation) = integral_scale(sim.state.velocity, sim.domain)


"""
    flow_parameters(sim)

The dimensionless flow state of `sim` as a [`FlowParameters`](@ref) — the bridge that lets any
`Phenomenology` reference law be evaluated at the run's measured state. The viscosity ``\\nu`` and the
Schmidt number are read from `sim.conditions`; the dissipation ``\\varepsilon``, the r.m.s. velocity
``u' = \\sqrt{2k/3}`` (from the kinetic energy ``k``), and the integral scale ``L`` are measured from the
current velocity field.
"""
function flow_parameters(sim::Simulation)
  k = kinetic_energy(sim)
  FlowParameters(; viscosity = sim.conditions.viscosity, dissipation = dissipation(sim),
                 rms_velocity = sqrt(2k / 3), integral_scale = integral_scale(sim),
                 schmidt = sim.conditions.schmidt)
end


"""
    validate_spectrum(sim, model)

Compare the measured energy spectrum of `sim` against a `Phenomenology` model spectrum `model` (an
`EnergySpectrum`, e.g. `Pope2000()`), evaluated at the run's [`flow_parameters`](@ref). Returns a named
tuple `(; wavenumbers, measured, predicted, relative_error)`: the resolved shell wavenumbers, the
measured and predicted ``E(\\kappa)``, and the relative L² discrepancy over the resolved (non-empty)
shells.

!!! note
    A developed, well-resolved run agrees with a good model across the inertial range; at low Reynolds
    number or coarse resolution the inertial range is narrow, so a large discrepancy is expected and
    reflects the run, not the model.
"""
function validate_spectrum(sim::Simulation, model::EnergySpectrum)
  fp = flow_parameters(sim)
  κ, measured = energy_spectrum(sim)
  predicted = similar(measured)
  num = zero(eltype(measured))
  den = zero(eltype(measured))
  for i in eachindex(κ, measured)
    predicted[i] = κ[i] > 0 ? spectrum(model, κ[i], fp) : zero(eltype(measured))
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


# The eddy-turnover time τ = k/ε from the current diagnostics — the clock warm-up and run budgets
# count in units of it.
function _turnover_time(sim::Simulation)
  ε = dissipation(sim)
  return ε > 0 ? Float64(kinetic_energy(sim) / ε) : 1.0
end


# The advective-CFL timestep Δt = C·Δx/maxᵢ|uᵢ| for the current velocity (the integrating factor
# makes diffusion exact, so only the advective limit applies).
function cfl_timestep(sim::Simulation)
  N = size(field_data(sim.buffers.velocity_physical), 1)
  Δx = Float64(sim.domain.grid.domain_size[1]) / N
  speed = Float64(max_speed(sim.buffers.velocity_physical))
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
  buffers = sim.buffers
  Δt = dt === nothing ? cfl_timestep(sim) : Float64(dt)

  step!(sim.integrator, sim.state.velocity, sim.state.scalar, sim.domain, buffers, sim.conditions, Δt)

  # u(tₙ) is still cached (step! only reads it); save it, refresh to u(tₙ₊₁), then Heun-advect.
  sim.tracers === nothing || copyto!(field_data(sim.tracer_velocity), field_data(buffers.velocity_physical))
  _refresh_cached_fields!(sim)
  sim.tracers === nothing ||
    advect!(sim.tracers, sim.tracer_velocity, buffers.velocity_physical, sim.domain, Δt)

  sim.clock.time += Δt
  sim.clock.step += 1
  return sim
end


# Shared loop: advance until the single stopping condition is met, firing `callback(sim)` after each
# step (or once per `every` time units, if given).
function _run_loop!(sim::Simulation, callback; turnovers = nothing, time = nothing,
                 steps = nothing, every = nothing, stop = nothing)
  if stop === nothing
    count(!isnothing, (turnovers, time, steps)) == 1 ||
      throw(ArgumentError("give exactly one stopping condition: `turnovers`, `time`, or `steps`"))
  end

  target_time = time  === nothing ? nothing : sim.clock.time + Float64(time)
  target_step = steps === nothing ? nothing : sim.clock.step + Int(steps)
  target_turn = turnovers === nothing ? nothing : Float64(turnovers)
  elapsed_turn = 0.0
  next_output = every === nothing ? nothing : sim.clock.time + Float64(every)

  while true
    target_time !== nothing && sim.clock.time ≥ target_time && break
    target_step !== nothing && sim.clock.step ≥ target_step && break
    target_turn !== nothing && elapsed_turn ≥ target_turn && break
    stop !== nothing && stop(sim, elapsed_turn) && break

    τ = (target_turn === nothing && stop === nothing) ? nothing : _turnover_time(sim)
    Δt = cfl_timestep(sim)
    advance!(sim; dt = Δt)
    τ === nothing || (elapsed_turn += Δt / τ)

    if callback !== nothing
      if every === nothing
        callback(sim)
      elseif sim.clock.time ≥ next_output
        callback(sim)
        next_output += Float64(every)
      end
    end
  end
  return sim
end


"""
    run!(sim; turnovers | time | steps, every = nothing)
    run!(sim; ...) do sim … end

Advance `sim` until exactly one stopping condition is met — a number of eddy-turnover times
(`turnovers`, in units of ``k/\\varepsilon``), a span of simulation `time`, or a number of `steps` —
and return it. A callback (the `do` block, or a first positional function) fires with the current
`Simulation` after every step, or once per `every` units of simulation time if `every` is given —
the place to stream statistics along the run.

# Examples
```julia
run!(sim; turnovers = 10)                        # advance ten eddy-turnover times

energy = Float64[]                               # sample the kinetic energy every 0.1 time units
run!(sim; time = 5.0, every = 0.1) do s
    push!(energy, kinetic_energy(s))
end
```
"""
run!(sim::Simulation; kwargs...) = _run_loop!(sim, nothing; kwargs...)
run!(callback, sim::Simulation; kwargs...) = _run_loop!(sim, callback; kwargs...)


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

# No net drift of the series `y(turn)` across the trailing window `[now-W, now]`:
# ``|mean(2nd half) − mean(1st half)| / |mean| < tol``.
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
function _observe_and_test!(m::StationarityMonitor, sim, elapsed_turn)
  (isempty(m.turn) || elapsed_turn - m.turn[end] ≥ m.sample_gap) || return false
  ε = dissipation(sim)
  φ2 = m.gate_scalar ? scalar_variance(sim) : 0.0
  S = m.gate_skew ? derivative_skewness(sim.state.velocity, sim.domain) : 0.0
  return _push_and_test!(m, elapsed_turn, ε, φ2, S)
end

_scalar_forced(sim::Simulation) = sim.state.scalar !== nothing && !(sim.conditions.scalar_forcing isa NoForcing)


"""
    warmup!(sim; gate_scalar = true, gate_skewness = true, min_turnovers = 5,
            window_turnovers = 4, tol = 0.05, skew_floor = 0.1, max_turnovers = 60)
    warmup!(sim; turnovers | time | steps)

Spin `sim` up to a statistically stationary state before measurement, and return it. By default it
**detects stationarity**: it advances until the running dissipation ``\\varepsilon(t)`` stops drifting
— a two-half-window mean test over the trailing `window_turnovers` eddy-turnover times, relative drift
below `tol`, not tested before `min_turnovers` (past the start-up overshoot) — and gives up at
`max_turnovers` with a warning. ``\\varepsilon`` (the small scales, which settle last) is read rather
than the kinetic energy, which a constant-energy forcing clamps flat and a fixed-injection forcing
makes ring.

Two stricter gates are on by default. With `gate_skewness`, the velocity-derivative skewness
([`derivative_skewness`](@ref)) must also have plateaued *and* reached
``\\lvert S\\rvert \\ge \\texttt{skew\\_floor}`` — the decisive "real turbulence yet" signal, since a
random-phase field starts at ``S \\approx 0`` and only a developed cascade reaches ``S \\approx -0.5``.
With `gate_scalar`, when the
scalar is forced, the scalar variance ``\\langle\\varphi^2\\rangle`` must be flat too (the scalar
reaches stationarity after the velocity); an unforced scalar has no stationary state and is not gated.

Passing an explicit `turnovers`, `time`, or `steps` instead runs a **fixed budget** (no detection) —
the simple spin-up when the transient length is known.
"""
function warmup!(sim::Simulation; turnovers = nothing, time = nothing, steps = nothing,
                 gate_scalar::Bool = true, gate_skewness::Bool = true, min_turnovers::Real = 5,
                 window_turnovers::Real = 4, tol::Real = 0.05, skew_floor::Real = 0.1,
                 max_turnovers::Real = 60)
  if turnovers !== nothing || time !== nothing || steps !== nothing
    return _run_loop!(sim, nothing; turnovers, time, steps)
  end
  monitor = StationarityMonitor(; min_turnovers, window_turnovers, tol,
                                gate_scalar = gate_scalar && _scalar_forced(sim),
                                gate_skew = gate_skewness, skew_floor)
  _run_loop!(sim, nothing; turnovers = Float64(max_turnovers),
          stop = (s, et) -> _observe_and_test!(monitor, s, et))
  monitor.converged ||
    @warn "warmup!: hit the max_turnovers = $(max_turnovers) cap without detecting stationarity"
  return sim
end


end # module SimulationRun
