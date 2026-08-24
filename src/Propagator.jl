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
# IFLowStorageRK3 (Williamson 2N) is the general-purpose workhorse; IFHeun trades a register
# for a transform (cheaper in transforms, dearer in memory) and is an option that is
# imaginary-axis unstable for advection (see its docstring). Each `step!` reads the deposited velocity
# and vorticity from the `ObservablesCache` (deposited by the previous iteration's closing `deposit!`,
# nothing recomputed), takes the same slots as its stage recovery registers from stage 2 on, and
# advances the cache's fields epoch on completion; the caller closes the iteration with `deposit!`.

"""
    Propagator

The interchangeable time-marching schemes, concrete `AbstractIntegrator` subtypes; a run chooses one as
the `field_integration_scheme` of its [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation). All
are of the integrating-factor family: the stiff diffusive part
is advanced exactly and the nonlinear term explicitly by a Runge–Kutta stage combination.

- [`AbstractIntegrator`](@ref) — the scheme supertype a run's `field_integration_scheme` is chosen from.
- [`IFLowStorageRK3`](@ref), [`IFHeun`](@ref) — the schemes (RK3 low-storage; IFHeun a
  two-stage Heun — cheaper in transforms, dearer by one register per field, and
  imaginary-axis unstable).
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
               fields_modified!, advance_fields_epoch!,
               take_velocity!, take_vorticity!, take_scalar!,
               deposit_velocity!, deposit_vorticity!, deposit_scalar!, deposit_max_speed!
using ..Observables: max_speed, vorticity_physical!

export AbstractIntegrator, IFHeun, IFLowStorageRK3, IntegratorBuffers, allocate_buffers, step!,
       deposit!, recommended_cfl


"""
    AbstractIntegrator

Supertype of the time-marching schemes. A scheme implements
[`step!`](@ref)`(scheme, state, generator, domain, buffers, cache, dt)`, advancing the `state`'s
velocity ``\\hat{\\boldsymbol{u}}`` and scalar ``\\hat\\varphi`` (both in spectral representation) by one
timestep in place, and may specialize
[`recommended_cfl`](@ref).
"""
abstract type AbstractIntegrator end


# The passive-scalar step buffers — held by `IntegratorBuffers` only when a scalar is evolved,
# `nothing` otherwise (so a velocity-only run allocates none of them).
struct ScalarBuffers{SS, ST2, SST, NL}
  stage1::SS
  stage2::ST2                    # IFHeun only (nothing for IFLowStorageRK3)
  predictor_spectral::SST             # IFHeun only
  nonlinear::NL                  # IFLowStorageRK3 only (nothing for IFHeun)
end


"""
    IntegratorBuffers

The preallocated per-step scratch the scheme writes into, sized so a step allocates no field-sized
memory. Built per scheme by [`allocate_buffers`](@ref)`(scheme, domain; scalar)`, which allocates
**exactly** that scheme's working set: an array another scheme would use is left `nothing`, never
allocated.

Each such array is a **register**: storage a scheme computes one stage into and overwrites at the
next, holding nothing a caller should read between steps. The observables cache's slots serve the
same purpose mid-iteration — the step computes its stage recoveries into them — which is why a cached
field is meaningful only between iterations.

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

# Fields
- `stage1` — the first Runge–Kutta stage register, allocated by every scheme (the accumulator for
  [`IFLowStorageRK3`](@ref), the first stage for [`IFHeun`](@ref)).
- `nonlinear` — the assembled right-hand side; `IFLowStorageRK3` only, else `nothing`.
- `stage2`, `velocity_predictor_spectral` — the second stage register and the substage velocity predictor
  ``\\hat{\\boldsymbol{u}}^{*}`` in spectral representation; `IFHeun` only, else `nothing`.
- `scalar` — a `ScalarBuffers` for the passive scalar ``\\varphi`` when `scalar = true`, else `nothing`;
  when `nothing`, the run evolves no scalar and none of its field-sized buffers are allocated. Its
  fields mirror the per-scheme breakdown above, sized to the scalar: `stage1` (every scheme),
  `stage2` and `predictor_spectral` (`IFHeun`'s corrector register and predictor state ``\\hat\\varphi^*``),
  and `nonlinear` (`IFLowStorageRK3` only).

"""
struct IntegratorBuffers{VS, ST2, VSS, NL, SB}
  stage1::VS
  stage2::ST2                    # IFHeun only (nothing for IFLowStorageRK3)
  velocity_predictor_spectral::VSS    # IFHeun only
  nonlinear::NL                  # IFLowStorageRK3 only (nothing for IFHeun)
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
    allocate_buffers(scheme, domain; scalar = false) -> IntegratorBuffers
    allocate_buffers(scheme, tracers, cache) -> ParticleIntegratorBuffers

Allocate the per-step registers a scheme needs, dispatching on the concrete scheme so it allocates
**exactly** its working set — never a register another scheme would use. A scheme with no method
here is a hard error; there is no over-allocating fallback. The run layer calls this when assembling
a [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation).

The arguments are:
- `scheme` — the concrete scheme dispatched on: an [`AbstractIntegrator`](@ref) in the field form,
  an
  [`AbstractParticleIntegrator`](@ref GBGIsotropicTurbulence.Particles.AbstractParticleIntegrator)
  in the particle form.
- `domain` — field form: the [`FixedDomain`](@ref), which fixes the grid, precision, and storage
  backend of every register.
- `scalar = false` — field form: `true` adds the nested `ScalarBuffers`, likewise sized to the
  scheme.
- `tracers` — particle form: the tracer set the registers are sized to.
- `cache` — particle form: the
  [`ObservablesCache`](@ref GBGIsotropicTurbulence.Cache.ObservablesCache) whose
  velocity-at-particles slot the scheme consumes and — for a multistep scheme — whose sample
  history it integrates over.

The first form builds the [`IntegratorBuffers`](@ref) the scheme needs:
[`IFLowStorageRK3`](@ref) allocates `stage1` and `nonlinear`; [`IFHeun`](@ref) allocates `stage1`,
`stage2`, and `velocity_predictor_spectral`. The second form builds the
[`ParticleIntegratorBuffers`](@ref GBGIsotropicTurbulence.Particles.ParticleIntegratorBuffers).
One generic covers both because it is one concept, and because every side keeps the same
separation: the evolving state holds no scheme's scratch.
"""
function allocate_buffers end


"""
    step!(scheme, state, generator, domain, buffers, cache, dt)

Advance the velocity ``\\hat{\\boldsymbol{u}}`` and passive scalar ``\\hat\\varphi`` held in `state`
by one timestep `dt` in place. Dispatches on the concrete `scheme` type (see `IFHeun`,
`IFLowStorageRK3`).

The arguments are:
- `scheme` — the stateless dispatch tag naming the scheme.
- `state` — the [`ResolvedFields`](@ref GBGIsotropicTurbulence.State.ResolvedFields) this call
  mutates: the fields in spectral representation.
- `generator` — the [`ResolvedGenerator`](@ref GBGIsotropicTurbulence.Generator.ResolvedGenerator):
  the equations of motion, their conditions, and their assembly scratch.
- `domain` — the [`FixedDomain`](@ref).
- `buffers` — the scheme's [`IntegratorBuffers`](@ref).
- `cache` — the run's [`ObservablesCache`](@ref GBGIsotropicTurbulence.Cache.ObservablesCache).
- `dt` — the timestep.

A scheme does only stage arithmetic: it opens the step with the generator's
[`prepare!`](@ref GBGIsotropicTurbulence.Generator.prepare!), evaluates the right-hand sides and
exact linear factors through the generator protocol at each stage, and closes with the generator's
[`finalize!`](@ref GBGIsotropicTurbulence.Generator.finalize!) — it never assembles the physics
itself.

The first stage reads the deposited velocity, vorticity, and scalar in physical representation from
`cache` — the values of the instant between iterations, deposited by the previous iteration's
[`deposit!`](@ref); nothing is recomputed on a read. The later stages compute their recoveries into
those same slots, so the step allocates nothing and occupies no storage beyond its own spectral
stage registers. The cache's fields epoch — the freshness counter every new deposit is recorded
at — is advanced when the step completes.

The two calls of a hand-run loop align: `step!` leads with the dispatch tag and mutates its second
argument, while `deposit!` leads with `cache`, the object it mutates; after the leader both take
`state`, `domain`, `buffers` in the same order.

Returns `state`.

!!! note "A step alone leaves the cache mid-iteration"
    A `step!` alone leaves the cache mid-iteration (its slots taken as scratch): the caller closes
    the iteration with `deposit!`, which re-fills every slot, at the new epoch, from the advanced
    state — a hand-run loop is `step!` then `deposit!`, and the run layer's [`advance!`](@ref GBGIsotropicTurbulence.SimulationRun.advance!) does both.
"""
function step! end


"""
    IFLowStorageRK3()

Integrating-factor third-order low-storage Runge–Kutta of the Williamson (1980,
[*Low-storage Runge–Kutta schemes*](https://doi.org/10.1016/0021-9991%2880%2990033-9)) 2N-storage family. The
general-purpose workhorse: third-order and stable on the imaginary axis (limit ``\\sqrt{3}``),
unlike [`IFHeun`](@ref).

The diffusive integrating factor ``\\mathcal{E}_D(\\tau)`` over a substep interval ``\\tau``
(``D = \\nu`` for the velocity, ``\\varkappa = \\nu/\\mathrm{Sc}`` for the scalar) takes its
parameters from the generator's
[`velocity_integrating_factor`](@ref GBGIsotropicTurbulence.Generator.velocity_integrating_factor) /
[`scalar_integrating_factor`](@ref GBGIsotropicTurbulence.Generator.scalar_integrating_factor) and
is applied per mode by the backend's fused exponential convolution, never built as a field. With
``\\widehat{\\boldsymbol{N}}`` each field's right-hand side, the step carries a state ``\\hat q``
and a single accumulator ``\\boldsymbol{h}`` through three stages ``i = 1,2,3``,

```math
\\begin{aligned}
\\boldsymbol{h} &\\leftarrow A_i \\boldsymbol{h} + \\Delta t \\widehat{\\boldsymbol{N}}(\\hat q), \\\\
\\hat q &\\leftarrow \\hat q + B_i \\boldsymbol{h}, \\\\
\\hat q &\\leftarrow \\mathcal{E}_D(d_i\\Delta t) \\hat q, \\\\
\\boldsymbol{h} &\\leftarrow \\mathcal{E}_D(d_i\\Delta t) \\boldsymbol{h},
\\end{aligned}
```

(the accumulator's rotation is skipped at the last stage, where nothing reads it again),

with stage coefficients ``A_i = (0, -5/9, -153/128)``, ``B = (1/3, 15/16, 8/15)``, and node
increments ``d = (1/3, 5/12, 1/4)`` (abscissae ``c = (0, 1/3, 3/4)``). The velocity and scalar are
advanced in lockstep (the same ``A,B,d``), each with its own diffusivity, and any post-step forcing
is applied after the third stage.

The cost is three nonlinear evaluations per step and — in Williamson's 2N count, where ``N`` counts
evolved field registers — two registers per field: the state's own array plus one accumulator
(`stage1`). The [`IntegratorBuffers`](@ref) a run allocates also holds `nonlinear`, the register the
right-hand-side assembly and its dealiasing pass write through: the 2N count measures the scheme,
not the solver it is embedded in.
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
      scalar_rhs!(sb.nonlinear, generator, û, φ̂, u, φ, domain;                   # N̂_φ (N̂_u already banked)
                  displaced_velocity_current = true)
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

  finalize!(generator, state, domain)             # post-step forcing projections (e.g. VarianceRescaling)
  # Re-project the advanced STATE. Every stage's tendency is projected, but the state's own
  # divergence — injected at roundoff by the stage combinations — is damped only by exp(−νκ²Δt),
  # nearly nothing at the largest scales, and it compounds: measured in Float32 at 32³, |∇·u| grew
  # ×120 per 1500 steps, reaching 800×eps by step 2000. One in-place pointwise pass (the backend's
  # projection may alias destination and source) pins it at roundoff every step. Placed AFTER
  # finalize! so whatever a post-step forcing did to the state is covered too.
  helmholtz_projection!(û, û, domain.multipliers)
  advance_fields_epoch!(cache)                # the step advanced the fields — the cache goes stale
  # `state`, as the single home docstring says and as the in-place convention requires.
  # Both methods returned the bare `(û, φ̂)` tuple, so a hand-run loop written to the
  # documented shape — `state = step!(...)` — silently rebound `state` to a Tuple and the
  # next call failed on a type nothing in the docs had mentioned.
  return state
end


"""
    IFHeun()

Integrating-factor Heun — the two-stage, second-order Runge–Kutta. With the velocity and scalar integrating
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

!!! note "Unstable on the imaginary axis without viscous damping"
    Every second-order two-stage explicit Runge–Kutta has stability function
    ``R(z) = 1 + z + z^{2}/2``, for which ``\\lvert R(\\mathrm{i}y)\\rvert^{2} = 1 + y^{4}/4 > 1``: the
    scheme is unstable on the imaginary axis, so it is stable only where the viscous damping of the
    integrating factor dominates. It is adequate
    for well-resolved, modest-Reynolds-number runs — prefer
    [`IFLowStorageRK3`](@ref) for high Reynolds number or marginal resolution.
"""
struct IFHeun <: AbstractIntegrator end


function step!(::IFHeun, state::ResolvedFields, generator::ResolvedGenerator,
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
    scalar_rhs!(sb.stage1, generator, û, φ̂, u, scalar_physical(cache), domain;  # N̂_φ,1
                displaced_velocity_current = true)
  end

  # Predictors û*, φ̂*, and the corrector's integrating-factor rotations banked in the same visit.
  # Every use of a field's ℰ over the whole step is at the one substep Δt: the predictor combination
  # fuses with its rotation into one exponential pass, and ûₙ and N̂_u,1 are rotated here rather than
  # after stage 2 (neither is read by the stage-2 assembly, which works off the predictor). The
  # factor is never materialized — the fused exponential evaluates it per mode from its parameters.
  ℰ = velocity_integrating_factor(generator, dt)                                                             # E_ν parameters
  _exponential_update!(buffers.velocity_predictor_spectral, one(T), û, dt_T, buffers.stage1, domain, ℰ)  # û* ← E_ν(ûₙ + Δt N̂_u,1)
  _exponential_rotate!(buffers.stage1, domain, ℰ)                                                # E_ν N̂_u,1
  _exponential_rotate!(û, domain, ℰ)                                                             # E_ν ûₙ
  if has_scalar
    ℰφ = scalar_integrating_factor(generator, dt)                                                            # E_κ parameters
    _exponential_update!(sb.predictor_spectral, one(T), φ̂, dt_T, sb.stage1, domain, ℰφ)               # φ̂* ← E_κ(φ̂ₙ + Δt N̂_φ,1)
    _exponential_rotate!(sb.stage1, domain, ℰφ)                                                  # E_κ N̂_φ,1
    _exponential_rotate!(φ̂, domain, ℰφ)                                                          # E_κ φ̂ₙ
  end

  # stage 2 — right-hand sides at the predictor state. The cache slots are taken as the recovery
  # registers (epochs to scratch); `stage2` is the spectral scratch, written by the assembly just after.
  u_star, ω_star = take_velocity!(cache), take_vorticity!(cache)
  to_physical!(u_star, buffers.velocity_predictor_spectral, domain.velocity_plans, buffers.stage2)
  vorticity_physical!(ω_star, buffers.velocity_predictor_spectral, domain, buffers.stage2)
  velocity_rhs!(buffers.stage2, generator, buffers.velocity_predictor_spectral, u_star, ω_star, domain)  # N̂_u,2
  if has_scalar
    φ_star = take_scalar!(cache)
    to_physical!(φ_star, sb.predictor_spectral, domain.scalar_plans, sb.stage2)
    scalar_rhs!(sb.stage2, generator, buffers.velocity_predictor_spectral, sb.predictor_spectral,   # N̂_φ,2
                u_star, φ_star, domain; displaced_velocity_current = true)
  end

  # velocity update: ûₙ₊₁ = E_ν ûₙ + (Δt/2)(E_ν N̂_u,1 + N̂_u,2) — both rotated halves already banked
  combine!(û, one(T), û, half, buffers.stage1)                                             # ûₙ₊₁ += (Δt/2)(E_ν N̂_u,1 + N̂_u,2)
  combine!(û, one(T), û, half, buffers.stage2)

  # scalar update: φ̂ₙ₊₁ = E_κ φ̂ₙ + (Δt/2)(E_κ N̂_φ,1 + N̂_φ,2)
  if has_scalar
    combine!(φ̂, one(T), φ̂, half, sb.stage1)                                  # φ̂ₙ₊₁ += (Δt/2)(E_κ N̂_φ,1 + N̂_φ,2)
    combine!(φ̂, one(T), φ̂, half, sb.stage2)
  end

  finalize!(generator, state, domain)             # post-step forcing projections (e.g. VarianceRescaling)
  # Re-project the advanced STATE. Every stage's tendency is projected, but the state's own
  # divergence — injected at roundoff by the stage combinations — is damped only by exp(−νκ²Δt),
  # nearly nothing at the largest scales, and it compounds: measured in Float32 at 32³, |∇·u| grew
  # ×120 per 1500 steps, reaching 800×eps by step 2000. One in-place pointwise pass (the backend's
  # projection may alias destination and source) pins it at roundoff every step. Placed AFTER
  # finalize! so whatever a post-step forcing did to the state is covered too.
  helmholtz_projection!(û, û, domain.multipliers)
  advance_fields_epoch!(cache)                # the step advanced the fields — the cache goes stale
  # `state`, as the single home docstring says and as the in-place convention requires.
  # Both methods returned the bare `(û, φ̂)` tuple, so a hand-run loop written to the
  # documented shape — `state = step!(...)` — silently rebound `state` to a Tuple and the
  # next call failed on a type nothing in the docs had mentioned.
  return state
end


# Per-scheme scratch — each scheme allocates exactly its working set; there is no `::AbstractIntegrator`
# fallback, so a scheme with no method here is a hard error (never a silent over-allocation).
# IFLowStorageRK3 uses stage1 + nonlinear; IFHeun uses stage1 + stage2 + velocity_predictor_spectral; each
# leaves the other scheme's registers `nothing`.
ScalarBuffers(::IFLowStorageRK3, domain::FixedDomain) = ScalarBuffers(
  new_scalar_field_spectral(domain), nothing, nothing, new_scalar_field_spectral(domain),           # stage1, stage2, predictor_spectral, nonlinear
)
ScalarBuffers(::IFHeun, domain::FixedDomain) = ScalarBuffers(
  new_scalar_field_spectral(domain), new_scalar_field_spectral(domain), new_scalar_field_spectral(domain), nothing,   # stage1, stage2, predictor_spectral, nonlinear
)

allocate_buffers(::IFLowStorageRK3, domain::FixedDomain; scalar::Bool = false) = IntegratorBuffers(
  new_vector_field_spectral(domain),                                # stage1
  nothing,                                                # stage2 (IFHeun only)
  nothing,                                                # velocity_predictor_spectral (IFHeun only)
  new_vector_field_spectral(domain),                                # nonlinear
  scalar ? ScalarBuffers(IFLowStorageRK3(), domain) : nothing,
)

allocate_buffers(::IFHeun, domain::FixedDomain; scalar::Bool = false) = IntegratorBuffers(
  new_vector_field_spectral(domain),                                # stage1
  new_vector_field_spectral(domain),                                # stage2
  new_vector_field_spectral(domain),                                # velocity_predictor_spectral
  nothing,                                                # nonlinear (IFLowStorageRK3 only)
  scalar ? ScalarBuffers(IFHeun(), domain) : nothing,
)


# The closing deposit's spectral working space is a stage register that is dead once the step closes
# (and, before the first step, merely zeroed): `nonlinear` for IFLowStorageRK3, `stage2` for IFHeun —
# each consumed into its update before `step!` returns.
_recovery_scratch(buffers::IntegratorBuffers) =
  buffers.nonlinear === nothing ? buffers.stage2 : buffers.nonlinear
_recovery_scratch(sb::ScalarBuffers) =
  sb.nonlinear === nothing ? sb.stage2 : sb.nonlinear


"""
    deposit!(cache, state, domain, buffers)
    deposit!(cache, tracers, u)
    deposit!(sim)

Close a producer's advance by depositing the observables it has just made measurable: compute them
from the arguments, write them into `cache` (an
[`ObservablesCache`](@ref GBGIsotropicTurbulence.Cache.ObservablesCache)), and record each slot at
the current epoch (the cache's freshness counter). One generic serves both sides of the run because
it is one concept — each dynamical factor's advance is followed by its own deposit, so an iteration
closes as `step!` then `deposit!`, then
[`advect!`](@ref GBGIsotropicTurbulence.Particles.advect!) then `deposit!` again.

The arguments are:
- `cache` — every form's destination: the cache whose slots receive the deposits.
- `state` — field form: the [`ResolvedFields`](@ref GBGIsotropicTurbulence.State.ResolvedFields)
  the step has just produced.
- `domain` — field form: the [`FixedDomain`](@ref) whose plans run the recoveries.
- `buffers` — field form: the scheme's [`IntegratorBuffers`](@ref), one spectral stage register of
  which — dead at the iteration's end — is the recovery scratch.
- `tracers` — particle form: the [`Tracers`](@ref GBGIsotropicTurbulence.Particles.Tracers) whose
  current positions are sampled, with the set's own interpolation scheme.
- `u` — particle form: the velocity field in physical representation to interpolate — normally the
  field form's own fresh deposit.
- `sim` — `sim` form: the [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) to
  unpack.

The **field form** deposits the field-derived slots — the velocity, vorticity and, when the run
carries one, scalar recoveries in physical representation, then the maximum-speed reduction over
the just-deposited velocity — from the state the step has just produced. Every recovery
is work the next iteration's first stage would have done anyway, so closing the iteration costs no
extra transforms — one extra pass only, the maximum-speed reduction, which runs every iteration
even under a hand-fixed ``\\Delta t`` that never reads it.

The **particle form** deposits the one trajectory-bound slot: it interpolates `u` at the tracer
set's current positions and stamps the slot against **both** counters — the
fields epoch of the interpolated velocity and the particles epoch of the positions, since the
velocity at the particles is a function of the two together. It therefore runs **after** the tracer
push, which itself consumed the field form's deposit.

The deposited values serve twice: they are
the Lagrangian velocity a caller accumulates, and the start-of-step velocity the next `advect!`
reads — ``M \\times 3`` values for ``M`` tracers, where keeping the endpoint field would cost
``N^{3} \\times 3``.

Every iteration ends with these deposits: the run layer's
[`advance!`](@ref GBGIsotropicTurbulence.SimulationRun.advance!) performs them for you, the
`Simulation` constructor makes the seeding
deposits so the first iteration finds the initial state's observables, and a hand-run loop calls
each form itself after the advance it closes. After mutating the state or the positions out of
band, announce it — [`fields_modified!`](@ref GBGIsotropicTurbulence.Cache.fields_modified!) /
[`particles_modified!`](@ref GBGIsotropicTurbulence.Cache.particles_modified!) — and re-deposit
with the **`sim` form**, which performs every deposit the run's configuration carries.

Returns `cache` (or `sim`).
"""
function deposit!(cache::ObservablesCache, state::ResolvedFields, domain::FixedDomain,
                  buffers::IntegratorBuffers)
  # A scalar-carrying state paired with a scalar-less cache used to deposit the velocity and the
  # vorticity and simply SKIP the scalar — leaving no slot to read, no error, and a run whose scalar
  # is never observed. The pairing is a construction mistake, so it is named here rather than
  # discovered later as a missing-slot throw from an accessor.
  # Only this direction is checked. The reverse — a cache slot no state fills — is already caught
  # when the iteration closes, as an undeposited slot; this one is the silent one, because a skipped
  # deposit leaves nothing behind to notice.
  state.scalar_spectral === nothing || cache.scalar_physical !== nothing ||
    throw(ArgumentError("this state carries a passive scalar but the cache has no scalar slot to " *
                        "receive it, so the scalar would be evolved and never observed. Build the " *
                        "cache with `scalar = true`."))
  # …and the same mispairing on the buffers leg: `allocate_buffers` defaults to `scalar = false`,
  # so the hand-assembled route reaches the scalar recovery with no scalar scratch and used to die
  # as a MethodError inside a private helper, naming nothing the caller typed.
  state.scalar_spectral === nothing || cache.scalar_physical === nothing || buffers.scalar !== nothing ||
    throw(ArgumentError("this state and cache carry a passive scalar but the `IntegratorBuffers` " *
                        "were built without one, so the scalar cannot be recovered for the " *
                        "deposit. Build the buffers with `allocate_buffers(scheme, domain; " *
                        "scalar = true)`."))
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
    recommended_cfl(scheme, domain)

A conservative advective-CFL (Courant–Friedrichs–Lewy) ceiling ``C_{\\mathrm{CFL}}`` for the scheme
`scheme` on the [`FixedDomain`](@ref) `domain`, for a timestep
``\\Delta t = C_{\\mathrm{CFL}} \\Delta x / \\max_{\\boldsymbol{x}}\\lvert\\boldsymbol{u}\\rvert``,
with ``\\Delta x = L/N`` the grid spacing.

The advective eigenvalues of the dealiased system are imaginary, of magnitude up to
``\\kappa_{\\max}\\sup\\lvert\\boldsymbol{u}\\rvert`` — a rate. Stability needs that rate times the
step, which once ``\\Delta t`` is substituted is ``C_{\\mathrm{CFL}} \\kappa_{\\max}\\Delta x``, to
stay inside the scheme's imaginary-axis stability limit ``y_{\\mathrm{s}}``, a pure number.

Two loosenesses sit in that estimate and they pull in **opposite** directions. The speed in the
denominator is [`max_speed`](@ref GBGIsotropicTurbulence.Observables.max_speed), a maximum over grid
points, so the continuum supremum between them can be larger — making the computed step too long.
Against it, the eigenvalue bound over-estimates the true spectral radius, since not every mode
carries the peak speed — making the ceiling too small. They are independent, so the second is not
guaranteed to cover the first, which is why the base ceiling carries a margin.

That base is calibrated for the ``2/3`` rule, where ``\\kappa_{\\max}\\Delta x = 2\\pi/3 \\approx 2.09``.
For [`IFLowStorageRK3`](@ref) the limit ``y_{\\mathrm{s}} = \\sqrt{3}`` gives
``C_{\\mathrm{CFL}} \\lesssim 0.83``, taken conservatively as ``0.5``. [`IFHeun`](@ref) is
imaginary-axis unstable (``y_{\\mathrm{s}} = 0``, relying on viscous damping), which makes the
formula degenerate: its ``0.25`` is an empirical margin rather than a computed limit.

!!! warning "The IFHeun margin does not know the viscosity"
    This function takes no ``\\nu``, by design — a CFL ceiling is a property of the scheme and the
    grid — but `IFHeun`'s margin is the one value that depends on a quantity it cannot see.
    The same `0.25` is returned at every Reynolds number while the viscous damping it rests on
    weakens as ``\\nu`` falls. No code-level guard exists — adding one would give a grid-and-scheme
    property a physics argument. The practical course at high Reynolds number is to prefer
    `IFLowStorageRK3`, whose ceiling has no such dependence, or to pass an explicit `cfl` and
    verify stability directly: the run's energy must stay bounded over a trial stretch.

The base is then scaled by the domain's dealiasing: a strategy that keeps modes to a higher
``\\kappa_{\\max}`` (e.g. [`HouLi`](@ref GBGIsotropicTurbulence.SimulationDomain.HouLi), out to the
Nyquist wavenumber) takes a proportionally smaller step,
``C_{\\mathrm{CFL}} \\propto 1/\\kappa_{\\max}``. That scaling applies to both schemes' bases,
`IFHeun`'s empirical one included — the dependence on how much of the band is kept is geometric,
holding whether the base was computed or measured — the scaled value is only as trustworthy as
its base. This is the value [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) uses;
override `cfl` for a specific run.
"""
function recommended_cfl end

# The base (2/3-calibrated) advective-CFL ceiling per scheme — internal; the public `recommended_cfl`
# corrects it for the domain's dealiasing band.
#
# NO `::AbstractIntegrator` FALLBACK, matching `allocate_buffers` on the same supertype: a scheme
# that has not declared its stability limit gets a hard error, not a number. The fallback that stood
# here returned 0.3, which is not a conservative choice — it sits ABOVE `IFHeun`'s 0.25 — so a new
# scheme with a tighter limit would have been handed too large a timestep silently, and 0.3 appeared
# in no docstring or doc page a reader could check it against. A stability limit is a property of the
# scheme, so the scheme states it or the run refuses to guess.
_base_cfl(::IFHeun) = 0.25
_base_cfl(::IFLowStorageRK3) = 0.5

# Scale the base ceiling by the active dealiasing: factor = (2/3)/f, f the retained Nyquist fraction
# (2/3 for TwoThirds ⇒ unchanged, 1 for HouLi ⇒ ×2/3, since it keeps modes to Nyquist).
recommended_cfl(scheme::AbstractIntegrator, domain::FixedDomain) =
  _base_cfl(scheme) * (2 // 3) / _retained_nyquist_fraction(domain.dealiasing)


end # module Propagator
