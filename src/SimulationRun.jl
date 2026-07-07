# SimulationRun — the ergonomic run layer. A `Simulation` bundles the operators, workspace, physics,
# integrator, spectral state (û, φ̂), and any tracers; `advance!`/`run!`/`warmup!` own the
# CFL-adaptive time loop. It holds no physics or numerics of its own — it wires the pieces of
# SimulationState/Dynamics/Observables/Forcing/TimeIntegration/Particles so a case is a few lines to
# set up and run, warm-up included, while every piece stays reachable for a hand-driven loop.
#
# The loop maintains one invariant: on entry to a step, `ws.velocity` / `ws.vorticity_start` hold the
# current physical u / ω — the start-of-step fields `step!` needs and the diagnostics read. A step
# advances û, φ̂ and then refreshes those cached fields from the new û; the refreshed velocity is also
# the end-of-step field used to advect the tracers (Heun on u(tₙ), u(tₙ₊₁)). `step!` only reads the
# cached fields, so they survive the step and the saved copy is exact.

"""
    SimulationRun

The run layer: [`Simulation`](@ref) (the assembled state of a case) and the functions that advance it —
[`advance!`](@ref) (one step), [`run!`](@ref) (advance to a stopping condition, with an optional
per-interval callback), and [`warmup!`](@ref) (spin up to statistical stationarity). The observables
`kinetic_energy`, `dissipation`, and `scalar_variance` accept a `Simulation` directly.
"""
module SimulationRun

using GBGPeriodicFields
using Random
using ..SimulationState: SpectralOperators, Workspace, spectral_vector, scalar_spectral,
                         physical_vector, random_solenoidal_velocity!, random_scalar!,
                         DealiasingStrategy, TwoThirds
using ..Dynamics: velocity_vorticity!
using ..Observables: max_speed, derivative_skewness
import ..Observables: kinetic_energy, dissipation, scalar_variance
using ..Forcing: AbstractForcing, NoForcing
using ..TimeIntegration: AbstractIntegrator, Physics, step!, recommended_cfl, default_integrator
using ..Particles: Tracers, advect!

export Simulation, advance!, run!, warmup!, current_time, current_step


mutable struct Clock
  time::Float64
  step::Int
end


"""
    Simulation

A ready-to-run case: the [`SpectralOperators`](@ref) machinery, the [`Workspace`](@ref) scratch, the
[`Physics`](@ref), the chosen integrator, the velocity ``\\hat{\\boldsymbol u}`` and passive scalar
``\\hat\\varphi`` in spectral representation, any [`Tracers`](@ref), and a clock. Build it with the
constructors below and advance it with [`advance!`](@ref) / [`run!`](@ref) / [`warmup!`](@ref).
"""
struct Simulation{OPS, WS, IG, VF<:AbstractForcing, SF<:AbstractForcing, UH, PH, TR, TV}
  operators::OPS
  workspace::WS
  physics::Physics{VF, SF}
  integrator::IG
  velocity::UH             # û in spectral representation
  scalar::PH               # φ̂ in spectral representation
  tracers::TR              # Tracers, or nothing
  tracer_velocity::TV      # physical buffer holding u(tₙ) for the Heun advect, or nothing
  cfl::Float64
  clock::Clock
end


# A forcing may be given ready-built (an `AbstractForcing`) or as a factory `ops -> AbstractForcing`
# — the latter lets a banded forcing be named before the operators exist (`ops -> ConstantPower(ops;
# power)`), since a forcing precomputes its band from `ops`.
_resolve_forcing(f::AbstractForcing, ::SpectralOperators) = f
_resolve_forcing(f, ops::SpectralOperators) = f(ops)


"""
    Simulation(operators; viscosity, kwargs...)
    Simulation(; resolution, viscosity, box = 2π, scalar_type = Float64, array_type = Array, dealiasing = TwoThirds(), kwargs...)

Assemble a ready-to-run case. The second form is the front door: from a `resolution` and a
`viscosity` it builds the `SpectralOperators` (in the box `box`, on element type `scalar_type` and
backend `array_type`) and every other piece with sensible defaults, seeds a divergence-free velocity
and (unless `scalar = false`) a mean-zero scalar ``\\varphi``, and returns a `Simulation` at
``t = 0``. The first form takes operators you built yourself.

# Keywords
- `viscosity` — the kinematic viscosity ``\\nu`` (sets the Reynolds number); required.
- `schmidt = 1.0` — the Schmidt number ``\\mathrm{Sc}`` (scalar diffusivity ``\\nu/\\mathrm{Sc}``).
- `velocity_forcing`, `scalar_forcing` — an `AbstractForcing`, or a factory `ops -> AbstractForcing`
  (e.g. `ops -> ConstantPower(ops; power = 0.1)`); default `NoForcing()` (free decay).
- `integrator = default_integrator()`, `cfl = recommended_cfl(integrator, ops)` — the scheme and its
  advective-CFL ceiling (the ceiling adapts to `dealiasing`).
- `dealiasing = TwoThirds()` — the de-aliasing strategy (`TwoThirds` sharp ``2/3``, or `HouLi`
  smooth); it also sets ``\\kappa_{\\max}`` and hence the CFL step.
- `scalar = true`, `energy = 0.5`, `scalar_variance = 1.0`, `peak_wavenumber = 2.0` — whether to seed
  the scalar, the initial kinetic energy ``k`` and scalar variance, and the large-scale spectral peak.
- `ntracers = 0`, `tracer_scheme = CatmullRom` — the number of Lagrangian tracers and their
  interpolation scheme.
- `rng` — the random stream for the initial condition and the tracer seeding.
"""
function Simulation(ops::SpectralOperators;
                    viscosity::Real, schmidt::Real = 1.0,
                    velocity_forcing = NoForcing(), scalar_forcing = NoForcing(),
                    integrator::AbstractIntegrator = default_integrator(),
                    cfl::Real = recommended_cfl(integrator, ops),
                    scalar::Bool = true, energy::Real = 0.5, scalar_variance::Real = 1.0,
                    peak_wavenumber::Real = 2.0,
                    ntracers::Integer = 0, tracer_scheme = CatmullRom,
                    rng = Random.default_rng())
  ws = Workspace(ops)
  physics = Physics(; viscosity, schmidt,
                    velocity_forcing = _resolve_forcing(velocity_forcing, ops),
                    scalar_forcing = _resolve_forcing(scalar_forcing, ops))

  uh = spectral_vector(ops)
  random_solenoidal_velocity!(uh, ops; energy, peak_wavenumber, rng)
  phih = scalar_spectral(ops)
  scalar && random_scalar!(phih, ops; variance = scalar_variance, peak_wavenumber, rng)

  tracers = ntracers > 0 ? Tracers(ops, ntracers; scheme = tracer_scheme, rng) : nothing
  tracer_velocity = ntracers > 0 ? physical_vector(ops) : nothing

  sim = Simulation(ops, ws, physics, integrator, uh, phih, tracers, tracer_velocity,
                   Float64(cfl), Clock(0.0, 0))
  return _refresh_cached_fields!(sim)
end

function Simulation(; resolution::Integer, box::Real = 2π,
                    scalar_type::Type = Float64, array_type = Array,
                    dealiasing::DealiasingStrategy = TwoThirds(), kwargs...)
  return Simulation(SpectralOperators(resolution, box; dealiasing, scalar_type, array_type); kwargs...)
end


# Recompute the cached physical velocity and vorticity from the current û — the start-of-step fields
# the next `step!` reads and the diagnostics use. Preserves û (the allocating-style transform copies).
_refresh_cached_fields!(sim::Simulation) =
  (velocity_vorticity!(sim.workspace.velocity, sim.workspace.vorticity_start,
                       sim.velocity, sim.operators, sim.workspace); sim)


# Observables on a `Simulation`'s current (cached) state — extend the `Observables` generics, so
# `kinetic_energy(sim)` (``k``), `dissipation(sim)` (``\varepsilon``), and `scalar_variance(sim)`
# (``\langle\varphi^2\rangle``) read from the workspace fields (valid between steps).
kinetic_energy(sim::Simulation) = kinetic_energy(sim.workspace.velocity)
dissipation(sim::Simulation) = dissipation(sim.workspace.vorticity_start, sim.physics.viscosity)
scalar_variance(sim::Simulation) = scalar_variance(sim.scalar)


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
  N = size(field_data(sim.workspace.velocity), 1)
  Δx = Float64(sim.operators.grid.domain_size[1]) / N
  speed = Float64(max_speed(sim.workspace.velocity))
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
  ws = sim.workspace
  Δt = dt === nothing ? cfl_timestep(sim) : Float64(dt)

  step!(sim.integrator, sim.velocity, sim.scalar, sim.operators, ws, sim.physics, Δt)

  # u(tₙ) is still cached (step! only reads it); save it, refresh to u(tₙ₊₁), then Heun-advect.
  sim.tracers === nothing || copyto!(field_data(sim.tracer_velocity), field_data(ws.velocity))
  _refresh_cached_fields!(sim)
  sim.tracers === nothing ||
    advect!(sim.tracers, sim.tracer_velocity, ws.velocity, sim.operators, Δt)

  sim.clock.time += Δt
  sim.clock.step += 1
  return sim
end


# Shared loop: advance until the single stopping condition is met, firing `callback(sim)` after each
# step (or once per `every` time units, if given).
function _drive!(sim::Simulation, callback; turnovers = nothing, time = nothing,
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
the hook for streaming statistics along the run.
"""
run!(sim::Simulation; kwargs...) = _drive!(sim, nothing; kwargs...)
run!(callback, sim::Simulation; kwargs...) = _drive!(sim, callback; kwargs...)


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
  S = m.gate_skew ? derivative_skewness(sim.velocity, sim.operators) : 0.0
  return _push_and_test!(m, elapsed_turn, ε, φ2, S)
end

_scalar_forced(sim::Simulation) = !(sim.physics.scalar_forcing isa NoForcing)


"""
    warmup!(sim; gate_scalar = true, gate_skewness = true, min_turnovers = 5, window_turnovers = 4,
            tol = 0.05, skew_floor = 0.1, max_turnovers = 60)
    warmup!(sim; turnovers | time | steps)

Spin `sim` up to a statistically stationary state before measurement, and return it. By default it
**detects stationarity**: it advances until the running dissipation ``\\varepsilon(t)`` stops drifting
— a two-half-window mean test over the trailing `window_turnovers` eddy-turnover times, relative drift
below `tol`, not tested before `min_turnovers` (past the start-up overshoot) — and gives up at
`max_turnovers` with a warning. ``\\varepsilon`` (the small scales, which settle last) is read rather
than the kinetic energy, which a constant-energy forcing clamps flat and a fixed-injection forcing
makes ring.

Two stricter gates are on by default. With `gate_skewness`, the velocity-derivative skewness
([`derivative_skewness`](@ref)) must also have plateaued *and* reached ``\\lvert S\\rvert \\ge``
`skew_floor` — the decisive "real turbulence yet" signal, since a random-phase field starts at
``S \\approx 0`` and only a developed cascade reaches ``S \\approx -0.5``. With `gate_scalar`, when the
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
    return _drive!(sim, nothing; turnovers, time, steps)
  end
  monitor = StationarityMonitor(; min_turnovers, window_turnovers, tol,
                                gate_scalar = gate_scalar && _scalar_forced(sim),
                                gate_skew = gate_skewness, skew_floor)
  _drive!(sim, nothing; turnovers = Float64(max_turnovers),
          stop = (s, et) -> _observe_and_test!(monitor, s, et))
  monitor.converged ||
    @warn "warmup!: hit the max_turnovers = $(max_turnovers) cap without detecting stationarity"
  return sim
end


end # module SimulationRun
