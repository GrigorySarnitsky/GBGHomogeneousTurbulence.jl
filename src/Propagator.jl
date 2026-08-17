# Propagator — the interchangeable time-marching schemes, as concrete `AbstractIntegrator` subtypes
# dispatched by `step!`. All schemes are of the integrating-factor family: the stiff diffusive part
# is advanced exactly through exp(-diffusivity·|k|²Δt), and the nonlinear term is advanced explicitly
# by a Runge–Kutta stage combination. A scheme consumes the physics only through the ResolvedGenerator
# protocol (prepare!/velocity_rhs!/scalar_rhs!/velocity_integrating_factor/scalar_integrating_factor/finalize!) — it does
# stage arithmetic and stage-state recoveries, never assembling the right-hand side itself.
#
# `step!` advances the velocity û and the passive scalar φ̂ *together* through the same RK stages: the
# scalar is passive, so the only time-accurate coupling is to evaluate both nonlinear terms at each
# stage's state — the velocity rotated by its viscous integrating factor E_ν, the scalar by its
# diffusive one E_κ (κ = ν/Sc), both reaching the same lab time each substep. Advancing velocity
# fully and then the scalar would drop the substage velocities and degrade the coupling to first order.
#
# IFLowStorageRK3 (Williamson 2N) is the default workhorse; IFRK2 (Heun) is a cheaper option that is
# imaginary-axis unstable for advection (see its docstring). Each `step!` reads the deposited velocity
# and vorticity from the `ObservablesCache` (deposited by the previous iteration's closing `deposit!`,
# nothing recomputed), takes the same slots as its stage recovery registers from stage 2 on, and
# advances the cache's fields epoch on completion; the caller closes the iteration with `deposit!`.

"""
    Propagator

The interchangeable time-marching schemes, concrete `AbstractIntegrator` subtypes; a run chooses one as
the `integrator` of its [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) . All
are of the integrating-factor family: the stiff diffusive part
is advanced exactly and the nonlinear term explicitly by a Runge–Kutta stage combination.

- [`AbstractIntegrator`](@ref) — the scheme supertype a run's `integrator` is chosen from.
- [`IFLowStorageRK3`](@ref) (the default), [`IFRK2`](@ref) — the schemes (RK3 low-storage; IFRK2/Heun a
  cheaper two-stage alternative, imaginary-axis unstable).
- [`IntegratorBuffers`](@ref), [`allocate_buffers`](@ref) — the preallocated per-step scratch.
- [`step!`](@ref) — advance the coupled velocity and passive scalar one timestep.
- [`deposit!`](@ref) — close the iteration: recover the observables into the cache at the new epoch.
- [`recommended_cfl`](@ref) — a scheme's advective-CFL ceiling.
"""
module Propagator

using GBGPeriodicFields
using ..SimulationDomain: FixedDomain, _retained_nyquist_fraction,
                          new_vector_field_spectral, new_vector_field_physical, new_scalar_field_spectral, new_scalar_field_physical
using ..Generator: ResolvedGenerator, prepare!, finalize!,
                   velocity_rhs!, scalar_rhs!, velocity_integrating_factor, scalar_integrating_factor
using ..State: ResolvedFields
using ..Cache: ObservablesCache, velocity_physical, vorticity_physical, scalar_physical,
               fields_modified!,
               take_velocity!, take_vorticity!, take_scalar!,
               deposit_velocity!, deposit_vorticity!, deposit_scalar!, deposit_max_speed!
using ..Observables: max_speed, vorticity_physical!

export AbstractIntegrator, IFRK2, IFLowStorageRK3, IntegratorBuffers, allocate_buffers, step!,
       deposit!, recommended_cfl


"""
    AbstractIntegrator

Supertype of the time-marching schemes. A scheme implements
[`step!`](@ref)`(integrator, state, generator, domain, buffers, cache, dt)`, advancing the `state`'s
velocity ``\\hat{\\boldsymbol{u}}`` and scalar ``\\hat\\varphi`` (both in spectral representation) by one
timestep in place, and may specialize
[`recommended_cfl`](@ref).
"""
abstract type AbstractIntegrator end


# The passive-scalar step buffers — held by `IntegratorBuffers` only when a scalar is evolved,
# `nothing` otherwise (so a velocity-only run allocates none of them).
struct ScalarBuffers{SS, ST2, SST, NL}
  stage1::SS
  stage2::ST2                    # IFRK2 only (nothing for IFLowStorageRK3)
  star_spectral::SST             # IFRK2 only
  nonlinear::NL                  # IFLowStorageRK3 only (nothing for IFRK2)
end


"""
    IntegratorBuffers

The preallocated per-step scratch the integrator writes into, sized so a step allocates no field-sized
memory. Built per scheme by [`allocate_buffers`](@ref)`(integrator, domain; scalar)`, which allocates
**exactly** that scheme's working set: an array another scheme would use is left `nothing`, never
allocated.

Each such array is a **register**: storage a scheme computes one stage into and overwrites at the
next, holding nothing a caller should read between steps. The word is used in that sense throughout
the package — including for the observables cache's slots, which double as the step's registers
mid-iteration.

# Fields
Shared — every scheme allocates this:
- `stage1` — the first Runge–Kutta stage register (the accumulator for [`IFLowStorageRK3`](@ref), the
  first stage for [`IFRK2`](@ref)).

Scheme-specific — allocated only for the scheme that uses it, else `nothing`:
- `nonlinear` — the assembled right-hand side ([`IFLowStorageRK3`](@ref) only).
- `stage2`, `velocity_star_spectral` — the second stage register and the substage velocity predictor
  ``\\hat{\\boldsymbol{u}}^{*}`` in spectral representation ([`IFRK2`](@ref) only).

Nested:
- `scalar` — a `ScalarBuffers` for the passive scalar ``\\varphi`` when `scalar = true`, else `nothing`;
  when `nothing`, the run evolves no scalar and none of its field-sized buffers are allocated. Its
  fields mirror the per-scheme breakdown above, sized to the scalar: `stage1` (every scheme),
  `stage2` and `star_spectral` (`IFRK2`'s corrector register and predictor state ``\\hat\\varphi^*``),
  and `nonlinear` (`IFLowStorageRK3` only).

There are deliberately **no physical-representation registers** here: the substage velocity,
vorticity, and scalar recoveries write into the run's
[`ObservablesCache`](@ref GBGIsotropicTurbulence.Cache.ObservablesCache) slots, taken as scratch
mid-iteration and re-deposited at the iteration's end by [`deposit!`](@ref) — a slot IS its producer's register.
Likewise there is **no integrating-factor register**: the exact linear subflow is applied by the
backend's fused exponential convolution
([`exponential_convolve!`](@extref GBGPeriodicFields GBGPeriodicFields.Convolution.exponential_convolve!)),
evaluated per mode from the factor's parameters, so no
kernel field is ever built or stored. The right-hand-side **assembly** scratch (the quadratic
products, the phase-shift buffers, the forcing-rate fields) lives with the generator, on the
[`ResolvedGenerator`](@ref GBGIsotropicTurbulence.Generator.ResolvedGenerator) — the buffers here
are
only the scheme's own spectral stage registers.
"""
struct IntegratorBuffers{VS, ST2, VSS, NL, SB}
  stage1::VS
  stage2::ST2                    # IFRK2 only (nothing for IFLowStorageRK3)
  velocity_star_spectral::VSS    # IFRK2 only
  nonlinear::NL                  # IFLowStorageRK3 only (nothing for IFRK2)
  scalar::SB                     # ScalarBuffers, or nothing when no passive scalar is evolved
end


# The two shapes the fused exponential serves in a stage, branching once on whether a linear forcing
# rate is armed (the factor's `offset`): the update fuses a weighted combination with the factor —
# dest ← E ⊙ (α a + β b) — and the rotation applies the factor alone. Both evaluate
# E = exp(coefficient·|κ|² [+ offset_scale·Â]) per mode from the wavenumber arrays; no kernel field
# exists.
function _exponential_update!(dest, α, a, β, b, domain::FixedDomain, ℰ)
  ℰ.offset === nothing ?
    exponential_convolve!(dest, α, a, β, b, domain.multipliers, ℰ.coefficient) :
    exponential_convolve!(dest, α, a, β, b, domain.multipliers, ℰ.coefficient, ℰ.offset_scale, ℰ.offset)
  return dest
end

function _exponential_rotate!(field, domain::FixedDomain, ℰ)
  ℰ.offset === nothing ?
    exponential_convolve!(field, field, domain.multipliers, ℰ.coefficient) :
    exponential_convolve!(field, field, domain.multipliers, ℰ.coefficient, ℰ.offset_scale, ℰ.offset)
  return field
end

"""
    allocate_buffers(integrator, domain; scalar = false) -> IntegratorBuffers
    allocate_buffers(pusher, tracers) -> ParticleIntegratorBuffers

Allocate the per-step registers a scheme needs, dispatching on the concrete scheme so it allocates
**exactly** its working set — never a register another scheme would use. A scheme with no method
here is a hard error; there is no over-allocating fallback. The run layer calls this when assembling
a [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation).

The first form serves the field schemes: it builds the [`IntegratorBuffers`](@ref) `integrator`
needs, sized to the `domain` (a [`FixedDomain`](@ref), which fixes the grid, precision, and storage
backend of every register). [`IFLowStorageRK3`](@ref) allocates `stage1` and `nonlinear`;
[`IFRK2`](@ref) allocates `stage1`, `stage2`, and `velocity_star_spectral`. Passing `scalar = true`
adds the nested `ScalarBuffers`, likewise sized to the scheme.

The second serves the trajectory schemes: it builds the
[`ParticleIntegratorBuffers`](@ref GBGIsotropicTurbulence.Particles.ParticleIntegratorBuffers) the
`pusher` (an
[`AbstractParticleIntegrator`](@ref GBGIsotropicTurbulence.Particles.AbstractParticleIntegrator))
needs, sized to the tracer set `tracers`. One generic covers both because it is one concept, and
because both sides keep the same separation: the evolving state holds no scheme's scratch.
"""
function allocate_buffers end


"""
    step!(integrator, state, generator, domain, buffers, cache, dt)

Advance the `state` (a [`ResolvedFields`](@ref GBGIsotropicTurbulence.State.ResolvedFields) holding the velocity ``\\hat{\\boldsymbol{u}}`` and passive scalar
``\\hat\\varphi`` in spectral representation) by one timestep `dt` in place, using the `integrator`, the
reified `generator` (a
[`ResolvedGenerator`](@ref GBGIsotropicTurbulence.Generator.ResolvedGenerator) —
the equations of motion, their conditions, and their assembly scratch), the `domain` (a
[`FixedDomain`](@ref)), the scheme's `buffers` (an [`IntegratorBuffers`](@ref)), and the run's
observables cache `cache` (an
[`ObservablesCache`](@ref GBGIsotropicTurbulence.Cache.ObservablesCache) ). Dispatches on the
concrete
`integrator` type (see `IFRK2`, `IFLowStorageRK3`).

A scheme does only stage arithmetic: it opens the step with the generator's
[`prepare!`](@ref GBGIsotropicTurbulence.Generator.prepare!) , evaluates the
right-hand sides and exact linear factors through the generator protocol at each stage, and closes
with the generator's [`finalize!`](@ref GBGIsotropicTurbulence.Generator.finalize!) — it never
assembles the physics itself. The first stage reads the
deposited velocity, vorticity, and scalar in physical representation from `cache` — the values of
the instant between iterations, where the cache's deposits are current, deposited there
by the previous iteration's [`deposit!`](@ref); nothing is recomputed on a read — and the later
stages compute their recoveries into those same slots, so the step allocates and resides nothing
beyond its own spectral stage registers. The cache's fields epoch — the freshness counter every new
deposit is recorded at — is advanced when the step completes.

The argument order is shared with [`deposit!`](@ref), the call that closes the iteration: the
dispatch object leads (the scheme here, the cache there), the common arguments follow in the fixed
order `state`, `domain`, `buffers` (with `generator` after `state` and `cache`, `dt` closing this
signature), so the chained pair transposes nothing.

!!! note
    A `step!` alone leaves the cache mid-iteration (its slots taken as scratch): the caller closes
    the iteration with [`deposit!`](@ref), which re-fills every slot, at the new epoch, from the advanced
    state — a hand-run loop is `step!` then `deposit!`, and the run layer's [`advance!`](@ref GBGIsotropicTurbulence.SimulationRun.advance!) does both.

Returns `state`.
"""
function step! end


"""
    IFLowStorageRK3()

Integrating-factor third-order low-storage Runge–Kutta (Williamson 1980, [doi:10.1016/0021-9991(80)90033-9](https://doi.org/10.1016/0021-9991%2880%2990033-9); 2N-storage). With the diffusive
integrating factor ``\\mathcal{E}_D(\\tau)`` — its parameters supplied by the generator's
[`velocity_integrating_factor`](@ref GBGIsotropicTurbulence.Generator.velocity_integrating_factor) /
[`scalar_integrating_factor`](@ref GBGIsotropicTurbulence.Generator.scalar_integrating_factor) over
a substep
interval ``\\tau`` (``D = \\nu`` for the velocity, ``\\varkappa = \\nu/\\mathrm{Sc}`` for the scalar) and
applied per mode by the backend's fused exponential convolution, never built as a field —
and ``\\widehat{\\boldsymbol{N}}`` each field's right-hand side, the step carries a state
``\\hat q`` and a single accumulator
``\\boldsymbol{h}`` through three stages ``i = 1,2,3``,

```math
\\begin{aligned}
\\boldsymbol{h} &\\leftarrow A_i \\boldsymbol{h} + \\Delta t \\widehat{\\boldsymbol{N}}(\\hat q), \\\\
\\hat q &\\leftarrow \\hat q + B_i \\boldsymbol{h}, \\\\
\\hat q &\\leftarrow \\mathcal{E}_D(d_i\\Delta t) \\hat q, \\\\
\\boldsymbol{h} &\\leftarrow \\mathcal{E}_D(d_i\\Delta t) \\boldsymbol{h},
\\end{aligned}
```

(the accumulator's rotation is skipped at the last stage, where nothing reads it again),

with ``A = (0, -5/9, -153/128)``, ``B = (1/3, 15/16, 8/15)``, and node increments
``d = (1/3, 5/12, 1/4)`` (abscissae ``c = (0, 1/3, 3/4)``). The velocity and scalar are advanced in
lockstep (the same ``A,B,d``), each with its own diffusivity, and any post-step forcing is applied after
the third stage.
Three nonlinear evaluations per step, and — in Williamson's 2N-storage count, whose ``N`` counts
evolved field registers, not the grid points ``N`` of the rest of the documentation — two field registers
per field: the state's own array plus one accumulator (`stage1`; the raw-assembly register
`nonlinear` is the dealiasing seam's addition, not the scheme's). The default workhorse:
third-order and stable on the imaginary axis (limit ``\\sqrt{3}``), unlike [`IFRK2`](@ref).
"""
struct IFLowStorageRK3 <: AbstractIntegrator end


function step!(::IFLowStorageRK3, state::ResolvedFields, generator::ResolvedGenerator,
               domain::FixedDomain, buffers::IntegratorBuffers, cache::ObservablesCache, dt::Real)
  û, φ̂ = state.velocity_spectral, state.scalar_spectral
  T = real(eltype(field_data(û)))
  dt_T = T(dt)
  a = (zero(T), T(-5 // 9), T(-153 // 128))
  b = (T(1 // 3), T(15 // 16), T(8 // 15))
  d = (T(1 // 3), T(5 // 12), T(1 // 4))
  hu = buffers.stage1                                                             # velocity accumulator
  sb = buffers.scalar                                                             # ScalarBuffers, or nothing
  has_scalar = φ̂ !== nothing

  prepare!(generator, state, domain, dt)          # per-step forcing state advance + armed linear rates

  for i in 1:3
    if i == 1
      u = velocity_physical(cache)                     # the deposited observables, deposited by the
      ω = vorticity_physical(cache)                    # previous iteration's closing deposit (never recomputed)
      take_vorticity!(cache)                           # the assembly forms the Lamb vector in ω's register
      has_scalar && take_velocity!(cache)              # …and, with a scalar, the flux in u's register
    else
      # From stage 2 on the cache slots ARE the recovery registers: take them (their epochs go to
      # scratch, so a mid-iteration read throws) and recover the stage state into them. The spectral
      # scratch is `nonlinear` — dead here, consumed into the accumulator at the previous stage.
      u, ω = take_velocity!(cache), take_vorticity!(cache)
      to_physical!(u, û, domain.velocity_plans, buffers.nonlinear)
      vorticity_physical!(ω, û, domain, buffers.nonlinear)
    end

    # BOTH right-hand sides are evaluated at the stage state before either field is updated: the
    # PhaseShift displaced evaluations read û (and φ̂), so an assembly after the velocity update
    # would pair u at the next stage with φ at this one — breaking the alias cancellation and
    # degrading the scalar's coupling to first order (caught by the convergence-matrix test).
    velocity_rhs!(buffers.nonlinear, generator, û, u, ω, domain)                  # N̂_u
    if has_scalar
      if i == 1
        φ = scalar_physical(cache)                                             # the deposited scalar
      else
        φ = take_scalar!(cache)
        to_physical!(φ, φ̂, domain.scalar_plans, sb.nonlinear)                          # φ at the stage state
      end
      scalar_rhs!(sb.nonlinear, generator, û, φ̂, u, φ, domain)                   # N̂_φ (N̂_u already banked)
    end

    if i == 1
      multiply!(hu, dt_T, buffers.nonlinear)                                      # A₁ = 0
    else
      combine!(hu, a[i], hu, dt_T, buffers.nonlinear)                             # hu ← Aᵢ hu + Δt N̂_u
    end
    # The stage update and its integrating-factor rotation fuse into ONE pass: the fused exponential
    # evaluates E(dᵢΔt) per mode from the factor's parameters — nothing built, stored, or swept.
    ℰ = velocity_integrating_factor(generator, d[i] * dt)
    _exponential_update!(û, one(T), û, b[i], hu, domain, ℰ)                       # ûᵢ ← E_ν (ûᵢ + Bᵢ hu)
    i < 3 && _exponential_rotate!(hu, domain, ℰ)

    # The passive scalar rides the same stages (skipped, with its buffers unallocated, when absent).
    if has_scalar
      hφ = sb.stage1                                                              # scalar accumulator
      if i == 1
        multiply!(hφ, dt_T, sb.nonlinear)
      else
        combine!(hφ, a[i], hφ, dt_T, sb.nonlinear)
      end
      ℰφ = scalar_integrating_factor(generator, d[i] * dt)
      _exponential_update!(φ̂, one(T), φ̂, b[i], hφ, domain, ℰφ)                    # φ̂ᵢ ← E_κ (φ̂ᵢ + Bᵢ hφ)
      i < 3 && _exponential_rotate!(hφ, domain, ℰφ)
    end
  end

  finalize!(generator, state, domain)             # post-step forcing projections (e.g. BandRescaling)
  fields_modified!(cache)                     # the step advanced the fields — the cache goes stale
  return û, φ̂
end


"""
    IFRK2()

Integrating-factor second-order Runge–Kutta (Heun). With the velocity and scalar integrating
factors ``\\mathcal{E}_\\nu`` and ``\\mathcal{E}_\\varkappa`` (the generator's
[`velocity_integrating_factor`](@ref GBGIsotropicTurbulence.Generator.velocity_integrating_factor) /
[`scalar_integrating_factor`](@ref GBGIsotropicTurbulence.Generator.scalar_integrating_factor) at ``D = \\nu`` and
``D = \\varkappa = \\nu/\\mathrm{Sc}`` over the step
``\\Delta t``) and ``\\widehat{\\boldsymbol{N}}`` each field's right-hand side, one step of a
field ``\\hat q`` with
integrating factor ``\\mathcal{E}`` is

```math
\\begin{aligned}
\\hat q^{*} &= \\mathcal{E} (\\hat q_n + \\Delta t \\widehat{\\boldsymbol{N}}_1), \\\\
\\hat q_{n+1} &= \\mathcal{E} \\hat q_n + \\tfrac{\\Delta t}{2}(\\mathcal{E} \\widehat{\\boldsymbol{N}}_1 + \\widehat{\\boldsymbol{N}}_2),
\\end{aligned}
```

with ``\\widehat{\\boldsymbol{N}}_1`` at ``\\hat q_n`` and ``\\widehat{\\boldsymbol{N}}_2`` at the predictor
``\\hat q^{*}``; velocity and scalar use ``\\mathcal{E}_\\nu`` and ``\\mathcal{E}_\\varkappa``
respectively, then the forcings are applied. Two nonlinear evaluations per step.

!!! note
    Every second-order two-stage explicit Runge–Kutta has stability function
    ``R(z) = 1 + z + z^{2}/2``, for which ``\\lvert R(\\mathrm{i}y)\\rvert^{2} = 1 + y^{4}/4 > 1``: the
    scheme is unstable on the imaginary axis, so it is stable only where the viscous damping of the
    integrating factor dominates. It is adequate
    for well-resolved, modest-Reynolds-number runs but is **not** the default — prefer
    [`IFLowStorageRK3`](@ref) for high Reynolds number or marginal resolution.
"""
struct IFRK2 <: AbstractIntegrator end


function step!(::IFRK2, state::ResolvedFields, generator::ResolvedGenerator,
               domain::FixedDomain, buffers::IntegratorBuffers, cache::ObservablesCache, dt::Real)
  û, φ̂ = state.velocity_spectral, state.scalar_spectral
  T = real(eltype(field_data(û)))
  dt_T = T(dt)
  half = dt_T / 2
  sb = buffers.scalar                                                            # ScalarBuffers, or nothing
  has_scalar = φ̂ !== nothing

  prepare!(generator, state, domain, dt)          # per-step forcing state advance + armed linear rates

  # stage 1 — right-hand sides at the state between iterations, read from the cache (deposited by the previous
  # iteration's closing deposit; never recomputed). The assemblies consume the chart registers — the Lamb vector
  # forms in the vorticity's, and the scalar flux in the velocity's — so those slots are taken first.
  u = velocity_physical(cache)
  ω = vorticity_physical(cache)
  take_vorticity!(cache)
  has_scalar && take_velocity!(cache)
  velocity_rhs!(buffers.stage1, generator, û, u, ω, domain)                      # N̂_u,1
  if has_scalar
    scalar_rhs!(sb.stage1, generator, û, φ̂, u, scalar_physical(cache), domain)  # N̂_φ,1
  end

  # Predictors û*, φ̂*, and the corrector's integrating-factor rotations banked in the same visit.
  # Every use of a field's ℰ over the whole step is at the one substep Δt: the predictor combination
  # fuses with its rotation into one exponential pass, and ûₙ and N̂_u,1 are rotated here rather than
  # after stage 2 (neither is read by the stage-2 assembly, which works off the predictor). The
  # factor is never materialized — the fused exponential evaluates it per mode from its parameters.
  ℰ = velocity_integrating_factor(generator, dt)                                                             # E_ν parameters
  _exponential_update!(buffers.velocity_star_spectral, one(T), û, dt_T, buffers.stage1, domain, ℰ)  # û* ← E_ν(ûₙ + Δt N̂_u,1)
  _exponential_rotate!(buffers.stage1, domain, ℰ)                                                # E_ν N̂_u,1
  _exponential_rotate!(û, domain, ℰ)                                                             # E_ν ûₙ
  if has_scalar
    ℰφ = scalar_integrating_factor(generator, dt)                                                            # E_κ parameters
    _exponential_update!(sb.star_spectral, one(T), φ̂, dt_T, sb.stage1, domain, ℰφ)               # φ̂* ← E_κ(φ̂ₙ + Δt N̂_φ,1)
    _exponential_rotate!(sb.stage1, domain, ℰφ)                                                  # E_κ N̂_φ,1
    _exponential_rotate!(φ̂, domain, ℰφ)                                                          # E_κ φ̂ₙ
  end

  # stage 2 — right-hand sides at the predictor state. The cache slots are taken as the recovery
  # registers (epochs to scratch); `stage2` is the spectral scratch, written by the assembly just after.
  u_star, ω_star = take_velocity!(cache), take_vorticity!(cache)
  to_physical!(u_star, buffers.velocity_star_spectral, domain.velocity_plans, buffers.stage2)
  vorticity_physical!(ω_star, buffers.velocity_star_spectral, domain, buffers.stage2)
  velocity_rhs!(buffers.stage2, generator, buffers.velocity_star_spectral, u_star, ω_star, domain)  # N̂_u,2
  if has_scalar
    φ_star = take_scalar!(cache)
    to_physical!(φ_star, sb.star_spectral, domain.scalar_plans, sb.stage2)
    scalar_rhs!(sb.stage2, generator, buffers.velocity_star_spectral, sb.star_spectral, u_star, φ_star, domain)  # N̂_φ,2
  end

  # velocity update: ûₙ₊₁ = E_ν ûₙ + (Δt/2)(E_ν N̂_u,1 + N̂_u,2) — both rotated halves already banked
  combine!(û, one(T), û, half, buffers.stage1)                                             # ûₙ₊₁ += (Δt/2)(E_ν N̂_u,1 + N̂_u,2)
  combine!(û, one(T), û, half, buffers.stage2)

  # scalar update: φ̂ₙ₊₁ = E_κ φ̂ₙ + (Δt/2)(E_κ N̂_φ,1 + N̂_φ,2)
  if has_scalar
    combine!(φ̂, one(T), φ̂, half, sb.stage1)                                  # φ̂ₙ₊₁ += (Δt/2)(E_κ N̂_φ,1 + N̂_φ,2)
    combine!(φ̂, one(T), φ̂, half, sb.stage2)
  end

  finalize!(generator, state, domain)             # post-step forcing projections (e.g. BandRescaling)
  fields_modified!(cache)                     # the step advanced the fields — the cache goes stale
  return û, φ̂
end


# Per-scheme scratch — each scheme allocates exactly its working set; there is no `::AbstractIntegrator`
# fallback, so a scheme with no method here is a hard error (never a silent over-allocation).
# IFLowStorageRK3 uses stage1 + nonlinear; IFRK2 uses stage1 + stage2 + velocity_star_spectral; each
# leaves the other scheme's registers `nothing`.
ScalarBuffers(::IFLowStorageRK3, domain::FixedDomain) = ScalarBuffers(
  new_scalar_field_spectral(domain), nothing, nothing, new_scalar_field_spectral(domain),           # stage1, stage2, star_spectral, nonlinear
)
ScalarBuffers(::IFRK2, domain::FixedDomain) = ScalarBuffers(
  new_scalar_field_spectral(domain), new_scalar_field_spectral(domain), new_scalar_field_spectral(domain), nothing,   # stage1, stage2, star_spectral, nonlinear
)

allocate_buffers(::IFLowStorageRK3, domain::FixedDomain; scalar::Bool = false) = IntegratorBuffers(
  new_vector_field_spectral(domain),                                # stage1
  nothing,                                                # stage2 (IFRK2 only)
  nothing,                                                # velocity_star_spectral (IFRK2 only)
  new_vector_field_spectral(domain),                                # nonlinear
  scalar ? ScalarBuffers(IFLowStorageRK3(), domain) : nothing,
)

allocate_buffers(::IFRK2, domain::FixedDomain; scalar::Bool = false) = IntegratorBuffers(
  new_vector_field_spectral(domain),                                # stage1
  new_vector_field_spectral(domain),                                # stage2
  new_vector_field_spectral(domain),                                # velocity_star_spectral
  nothing,                                                # nonlinear (IFLowStorageRK3 only)
  scalar ? ScalarBuffers(IFRK2(), domain) : nothing,
)


# The closing deposit's spectral working space is a stage register that is dead once the step closes
# (and, before the first step, merely zeroed): `nonlinear` for IFLowStorageRK3, `stage2` for IFRK2 —
# each consumed into its update before `step!` returns.
_recovery_scratch(buffers::IntegratorBuffers) =
  buffers.nonlinear === nothing ? buffers.stage2 : buffers.nonlinear
_recovery_scratch(sb::ScalarBuffers) =
  sb.nonlinear === nothing ? sb.stage2 : sb.nonlinear


"""
    deposit!(cache, state, domain, buffers)
    deposit!(sim)

Close an iteration: deposit every observable the cache's fixed schedule carries — every slot its
configuration holds, the same set every iteration — into `cache` (an
[`ObservablesCache`](@ref GBGIsotropicTurbulence.Cache.ObservablesCache)), from the `state` (a
[`ResolvedFields`](@ref GBGIsotropicTurbulence.State.ResolvedFields) ) the step has just produced,
and record each slot at the current epoch (the cache's freshness counter). The
deposits are the next iteration's first-stage work moved to the iteration's end — the velocity, vorticity, and
(when the run carries one) scalar recoveries in physical representation, then the maximum-speed
reduction over the just-deposited velocity — so an iteration's transform counts are unchanged by
caching, and its pass counts are unchanged but for one: the maximum-speed reduction runs every
iteration, including under a hand-fixed ``\\Delta t`` that never reads it; the recoveries run on the [`FixedDomain`](@ref) `domain`'s plans, through a
spectral stage register of `buffers` (an [`IntegratorBuffers`](@ref)) that is dead at the iteration's end.

Every iteration ends with this call: the run layer's
[`advance!`](@ref GBGIsotropicTurbulence.SimulationRun.advance!) performs it after `step!` , a
hand-run loop calls it itself, and the
[`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) constructor makes the seeding
deposit so the
first iteration finds the initial state's observables. The argument order is shared with `step!` —
the mutated dispatch object (here the cache) leads, and `state`, `domain`, `buffers` follow in the
same fixed order as there. After mutating the state out of band, announce
it with [`fields_modified!`](@ref) and re-deposit with the second form, which unpacks `sim`.

Returns `cache` (or `sim`).
"""
function deposit!(cache::ObservablesCache, state::ResolvedFields, domain::FixedDomain,
                  buffers::IntegratorBuffers)
  u = take_velocity!(cache)
  to_physical!(u, state.velocity_spectral, domain.velocity_plans, _recovery_scratch(buffers))
  deposit_velocity!(cache)
  ω = take_vorticity!(cache)
  vorticity_physical!(ω, state.velocity_spectral, domain, _recovery_scratch(buffers))
  deposit_vorticity!(cache)
  if state.scalar_spectral !== nothing && cache.scalar_physical !== nothing
    φ = take_scalar!(cache)
    to_physical!(φ, state.scalar_spectral, domain.scalar_plans, _recovery_scratch(buffers.scalar))
    deposit_scalar!(cache)
  end
  deposit_max_speed!(cache, max_speed(u))
  return cache
end


"""
    recommended_cfl(integrator, domain)

A conservative advective-CFL (Courant–Friedrichs–Lewy) ceiling ``C_{\\mathrm{CFL}}`` for the scheme
`integrator` on the [`FixedDomain`](@ref) `domain`, for a timestep
``\\Delta t = C_{\\mathrm{CFL}} \\Delta x / \\max_{\\boldsymbol{x}}\\lvert\\boldsymbol{u}\\rvert``,
with ``\\Delta x = L/N`` the grid spacing.

The advective eigenvalues of the dealiased system are imaginary, of magnitude up to
``\\kappa_{\\max}\\sup\\lvert\\boldsymbol{u}\\rvert``; stability needs this times
``C_{\\mathrm{CFL}}`` to stay within the scheme's imaginary-axis stability limit
``y_{\\mathrm{s}}``. Two loosenesses justify the conservative factor below, and they pull the same
way. The speed in the denominator is
[`max_speed`](@ref GBGIsotropicTurbulence.Observables.max_speed), a maximum over grid points, so the
continuum ``\\sup\\lvert\\boldsymbol{u}\\rvert`` between them can be larger; and the eigenvalue
bound over-estimates the true spectral radius, since not every mode carries the peak speed. The base
ceiling is calibrated for the ``2/3`` rule (``\\kappa_{\\max}\\Delta x = 2\\pi/3 \\approx 2.09``): for
[`IFLowStorageRK3`](@ref) ``y_{\\mathrm{s}} = \\sqrt{3}`` gives ``C_{\\mathrm{CFL}} \\lesssim 0.83``,
taken conservatively as ``0.5``; [`IFRK2`](@ref) is imaginary-axis unstable (``y_{\\mathrm{s}} = 0``,
relying on viscous damping), which makes the formula degenerate — its ``0.25`` is an empirical
margin, not a computed limit, and the damping it leans on weakens as ``\\nu`` falls.

It scales that base by the domain's dealiasing: a strategy that keeps modes
to a higher ``\\kappa_{\\max}`` (e.g. [`HouLi`](@ref GBGIsotropicTurbulence.SimulationDomain.HouLi), out to the Nyquist wavenumber) takes a
proportionally smaller step, ``C_{\\mathrm{CFL}} \\propto 1/\\kappa_{\\max}``. This is the value [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) uses;
override `cfl` for a specific run.
"""
function recommended_cfl end

# The base (2/3-calibrated) advective-CFL ceiling per scheme — internal; the public `recommended_cfl`
# corrects it for the domain's dealiasing band.
_base_cfl(::AbstractIntegrator) = 0.3
_base_cfl(::IFRK2) = 0.25
_base_cfl(::IFLowStorageRK3) = 0.5

# Scale the base ceiling by the active dealiasing: factor = (2/3)/f, f the retained Nyquist fraction
# (2/3 for TwoThirds ⇒ unchanged, 1 for HouLi ⇒ ×2/3, since it keeps modes to Nyquist).
recommended_cfl(integrator::AbstractIntegrator, domain::FixedDomain) =
  _base_cfl(integrator) * (2 // 3) / _retained_nyquist_fraction(domain.dealiasing)


end # module Propagator
