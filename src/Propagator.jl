# Propagator — the interchangeable time-marching schemes, as concrete `AbstractIntegrator` subtypes
# dispatched by `step!`. All schemes are of the integrating-factor family: the stiff diffusive part
# is advanced exactly through exp(-diffusivity·|k|²Δt), and the nonlinear term is advanced explicitly
# by a Runge–Kutta stage combination. A scheme consumes the physics only through the ResolvedGenerator
# protocol (prepare!/velocity_rhs!/scalar_rhs!/velocity_factor!/scalar_factor!/finalize!) — it does
# stage arithmetic and stage-state recoveries, never assembling the right-hand side itself.
#
# `step!` advances the velocity û and the passive scalar φ̂ *together* through the same RK stages: the
# scalar is passive, so the only time-accurate coupling is to evaluate both nonlinear terms at each
# stage's state — the velocity rotated by its viscous integrating factor E_ν, the scalar by its
# diffusive one E_κ (κ = ν/Sc), both reaching the same lab time each substep. Advancing velocity
# fully and then the scalar would drop the substage velocities and degrade the coupling to first order.
#
# IFLowStorageRK3 (Williamson 2N) is the default workhorse; IFRK2 (Heun) is a cheaper option that is
# imaginary-axis unstable for advection (see its docstring). Each `step!` reads the start-of-step
# physical velocity and vorticity through the `DerivedFields` accessors — recomputed automatically when
# stale, so no caller prefill exists to forget — and advances the cache's fields epoch on completion.

"""
    Propagator

The interchangeable time-marching schemes, concrete `AbstractIntegrator` subtypes; a run chooses one as
the `integrator` of its `Simulation`. All are of the integrating-factor family: the stiff diffusive part
is advanced exactly and the nonlinear term explicitly by a Runge–Kutta stage combination.

- [`IFLowStorageRK3`](@ref) (the default), [`IFRK2`](@ref) — the schemes (RK3 low-storage; IFRK2/Heun a
  cheaper two-stage alternative, imaginary-axis unstable).
- [`IntegratorBuffers`](@ref), [`allocate_buffers`](@ref) — the preallocated per-step scratch.
- [`step!`](@ref) — advance the coupled velocity and passive scalar one timestep.
- [`recommended_cfl`](@ref) — a scheme's advective-CFL ceiling.
"""
module Propagator

using GBGPeriodicFields
using ..SimulationDomain: FixedDomain, _retained_nyquist_fraction,
                          spectral_vector, physical_vector, scalar_spectral, scalar_physical
using ..Generator: ResolvedGenerator, prepare!, finalize!,
                   velocity_rhs!, scalar_rhs!, velocity_factor!, scalar_factor!
using ..State: ResolvedFields, DerivedFields, physical_velocity, physical_vorticity,
               resolved_fields_modified!, spectral_scratch,
               velocity_to_physical!, vorticity_to_physical!, scalar_to_physical!

export AbstractIntegrator, IFRK2, IFLowStorageRK3, IntegratorBuffers, allocate_buffers, step!,
       recommended_cfl


"""
    AbstractIntegrator

Supertype of the time-marching schemes. A scheme implements
[`step!`](@ref)`(integrator, state, generator, domain, buffers, derived, dt)`, advancing the `state`'s
velocity ``\\hat{\\boldsymbol{u}}`` and scalar ``\\hat\\varphi`` (both in spectral representation) by one
timestep in place, and may specialize
[`recommended_cfl`](@ref).
"""
abstract type AbstractIntegrator end


# The passive-scalar step buffers — held by `IntegratorBuffers` only when a scalar is evolved,
# `nothing` otherwise (so a velocity-only run allocates none of them).
struct ScalarBuffers{SS, ST2, SST, NL, SP}
  stage1::SS
  stage2::ST2                    # IFRK2 only (nothing for IFLowStorageRK3)
  star_spectral::SST             # IFRK2 only
  nonlinear::NL                  # IFLowStorageRK3 only (nothing for IFRK2)
  copy::SS
  field::SP
end


"""
    IntegratorBuffers

The preallocated per-step scratch the integrator writes into, sized so a step allocates no field-sized
memory. Built per scheme by [`allocate_buffers`](@ref)`(integrator, domain; scalar)`, which allocates
**exactly** that scheme's working set: a register another scheme would use is left `nothing`, never
allocated.

# Fields
Shared — every scheme allocates these:
- `vorticity_physical`, `velocity_star` — the substage velocity/vorticity registers in physical
  representation (the start-of-step fields come from the run's `DerivedFields` charts).
- `stage1` — the first Runge–Kutta stage register (the accumulator for [`IFLowStorageRK3`](@ref), the
  first stage for [`IFRK2`](@ref)).
- `integrating_factor` — the register the exact linear subflow is written into each substep.

Scheme-specific — allocated only for the scheme that uses it, else `nothing`:
- `nonlinear` — the assembled right-hand side ([`IFLowStorageRK3`](@ref) only).
- `stage2`, `velocity_star_spectral` — the second stage register and the substage velocity predictor
  ``\\hat{\\boldsymbol{u}}^{*}`` in spectral representation ([`IFRK2`](@ref) only).

Nested:
- `scalar` — a `ScalarBuffers` for the passive scalar ``\\varphi`` when `scalar = true`, else `nothing`;
  when `nothing`, the run evolves no scalar and none of its field-sized buffers are allocated.

The right-hand-side **assembly** scratch (the quadratic products, the phase-shift buffers, the
forcing-rate arrays) lives with the generator, on the
[`ResolvedGenerator`](@ref GBGIsotropicTurbulence.Generator.ResolvedGenerator) — the buffers here are
only the scheme's own stage registers.
"""
struct IntegratorBuffers{VS, ST2, VSS, NL, SS, VP, SB}
  stage1::VS
  stage2::ST2                    # IFRK2 only (nothing for IFLowStorageRK3)
  velocity_star_spectral::VSS    # IFRK2 only
  nonlinear::NL                  # IFLowStorageRK3 only (nothing for IFRK2)
  integrating_factor::SS
  vorticity_physical::VP
  velocity_star::VP
  scalar::SB                     # ScalarBuffers, or nothing when no passive scalar is evolved
end

"""
    allocate_buffers(integrator, domain; scalar = false) -> IntegratorBuffers

Allocate the [`IntegratorBuffers`](@ref) `integrator` needs, dispatching on the concrete scheme so it
allocates **exactly** its working set — never a register another scheme would use.
[`IFLowStorageRK3`](@ref) allocates `stage1` and `nonlinear`; [`IFRK2`](@ref) allocates `stage1`,
`stage2`, and `velocity_star_spectral`. `scalar = true` adds the nested `ScalarBuffers`, likewise sized to
the scheme.
A scheme with no method here is a hard error — there is no over-allocating fallback. The run layer calls
this when assembling a `Simulation`.
"""
function allocate_buffers end


"""
    step!(integrator, state, generator, domain, buffers, derived, dt)

Advance the `state` (a `ResolvedFields` holding the velocity ``\\hat{\\boldsymbol{u}}`` and passive scalar
``\\hat\\varphi`` in spectral representation) by one timestep `dt` in place, using the `integrator`, the
reified `generator` (a [`ResolvedGenerator`](@ref GBGIsotropicTurbulence.Generator.ResolvedGenerator) —
the equations of motion, their conditions, and their assembly scratch), the `domain`, the scheme's
`buffers`, and the run's observation cache `derived` (a
[`DerivedFields`](@ref GBGIsotropicTurbulence.State.DerivedFields)). Dispatches on the concrete
`integrator` type (see `IFRK2`, `IFLowStorageRK3`).

A scheme does only stage arithmetic: it opens the step with the generator's `prepare!`, evaluates the
right-hand sides and exact linear factors through the generator protocol at each stage, and closes
with the generator's `finalize!` — it never assembles the physics itself. The start-of-step velocity
and vorticity in physical representation are read through `derived`'s accessors — recomputed
automatically when stale, so a hand-run loop needs no manual refill — and the cache's fields epoch is
advanced when the step completes, marking every derived chart for recomputation on its next read.
"""
function step! end


"""
    IFLowStorageRK3()

Integrating-factor third-order low-storage Runge–Kutta (Williamson 1980, 2N-storage). With the diffusive
integrating factor ``\\mathcal{E}_D(\\tau)`` built by the generator's
[`velocity_factor!`](@ref GBGIsotropicTurbulence.Generator.velocity_factor!) /
[`scalar_factor!`](@ref GBGIsotropicTurbulence.Generator.scalar_factor!) over a substep
interval ``\\tau`` (``D = \\nu`` for the velocity, ``\\varkappa = \\nu/\\mathrm{Sc}`` for the scalar)
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

with ``A = (0, -5/9, -153/128)``, ``B = (1/3, 15/16, 8/15)``, and node increments
``d = (1/3, 5/12, 1/4)`` (abscissae ``c = (0, 1/3, 3/4)``). The velocity and scalar are advanced in
lockstep (the same ``A,B,d``), each with its own diffusivity, and any post-step forcing is applied after
the third stage.
Three nonlinear evaluations per step, two field registers per field — the default workhorse:
third-order and stable on the imaginary axis (limit ``\\sqrt{3}``), unlike [`IFRK2`](@ref).
"""
struct IFLowStorageRK3 <: AbstractIntegrator end


function step!(::IFLowStorageRK3, state::ResolvedFields, generator::ResolvedGenerator,
               domain::FixedDomain, buffers::IntegratorBuffers, derived::DerivedFields, dt::Real)
  û, φ̂ = state.velocity, state.scalar
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
      u = physical_velocity(derived, state, domain)                              # start-of-step charts
      ω = physical_vorticity(derived, state, domain)                             # (fresh or recomputed)
    else
      velocity_to_physical!(buffers.velocity_star, û, domain, spectral_scratch(derived))
      vorticity_to_physical!(buffers.vorticity_physical, û, domain, spectral_scratch(derived))
      u, ω = buffers.velocity_star, buffers.vorticity_physical
    end

    # BOTH right-hand sides are evaluated at the stage state before either field is updated: the
    # PhaseShift displaced evaluations read û (and φ̂), so an assembly after the velocity update
    # would pair u at the next stage with φ at this one — breaking the alias cancellation and
    # degrading the scalar's coupling to first order (caught by the convergence-matrix test).
    velocity_rhs!(buffers.nonlinear, generator, û, u, ω, domain)                  # N̂_u
    if has_scalar
      scalar_to_physical!(sb.field, φ̂, domain, sb.copy)                          # φ at the stage state
      scalar_rhs!(sb.nonlinear, generator, û, φ̂, u, sb.field, domain)            # N̂_φ (N̂_u already banked)
    end

    if i == 1
      multiply!(hu, dt_T, buffers.nonlinear)                                      # A₁ = 0
    else
      combine!(hu, a[i], hu, dt_T, buffers.nonlinear)                             # hu ← Aᵢ hu + Δt N̂_u
    end
    combine!(û, one(T), û, b[i], hu)                                       # ûᵢ ← ûᵢ + Bᵢ hu
    velocity_factor!(buffers.integrating_factor, generator, domain, d[i] * dt)    # E_ν(dᵢΔt)
    convolve!(û, û, buffers.integrating_factor)
    i < 3 && convolve!(hu, hu, buffers.integrating_factor)

    # The passive scalar rides the same stages (skipped, with its buffers unallocated, when absent).
    if has_scalar
      hφ = sb.stage1                                                              # scalar accumulator
      if i == 1
        multiply!(hφ, dt_T, sb.nonlinear)
      else
        combine!(hφ, a[i], hφ, dt_T, sb.nonlinear)
      end
      combine!(φ̂, one(T), φ̂, b[i], hφ)
      scalar_factor!(buffers.integrating_factor, generator, domain, d[i] * dt)    # E_κ(dᵢΔt)
      convolve!(φ̂, φ̂, buffers.integrating_factor)
      i < 3 && convolve!(hφ, hφ, buffers.integrating_factor)
    end
  end

  finalize!(generator, state, domain)             # post-step forcing projections (e.g. BandRescaling)
  resolved_fields_modified!(derived)                     # the step advanced the fields — charts go stale
  return û, φ̂
end


"""
    IFRK2()

Integrating-factor second-order Runge–Kutta (Heun). With the velocity and scalar integrating
factors ``\\mathcal{E}_\\nu`` and ``\\mathcal{E}_\\varkappa`` (the generator's
[`velocity_factor!`](@ref GBGIsotropicTurbulence.Generator.velocity_factor!) /
[`scalar_factor!`](@ref GBGIsotropicTurbulence.Generator.scalar_factor!) at ``D = \\nu`` and
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
               domain::FixedDomain, buffers::IntegratorBuffers, derived::DerivedFields, dt::Real)
  û, φ̂ = state.velocity, state.scalar
  T = real(eltype(field_data(û)))
  dt_T = T(dt)
  half = dt_T / 2
  sb = buffers.scalar                                                            # ScalarBuffers, or nothing
  has_scalar = φ̂ !== nothing

  prepare!(generator, state, domain, dt)          # per-step forcing state advance + armed linear rates

  # stage 1 — right-hand sides at the start-of-step state (read through the derived-field charts)
  u = physical_velocity(derived, state, domain)
  velocity_rhs!(buffers.stage1, generator, û, u, physical_vorticity(derived, state, domain), domain)  # N̂_u,1
  if has_scalar
    scalar_to_physical!(sb.field, φ̂, domain, sb.copy)
    scalar_rhs!(sb.stage1, generator, û, φ̂, u, sb.field, domain)                 # N̂_φ,1
  end

  # predictors û*, φ̂*
  velocity_factor!(buffers.integrating_factor, generator, domain, dt)                            # E_ν
  combine!(buffers.velocity_star_spectral, one(T), û, dt_T, buffers.stage1)                      # û* ← ûₙ + Δt N̂_u,1
  convolve!(buffers.velocity_star_spectral, buffers.velocity_star_spectral, buffers.integrating_factor)
  if has_scalar
    scalar_factor!(buffers.integrating_factor, generator, domain, dt)                            # E_κ
    combine!(sb.star_spectral, one(T), φ̂, dt_T, sb.stage1)                                       # φ̂* ← φ̂ₙ + Δt N̂_φ,1
    convolve!(sb.star_spectral, sb.star_spectral, buffers.integrating_factor)
  end

  # stage 2 — right-hand sides at the predictor state
  velocity_to_physical!(buffers.velocity_star, buffers.velocity_star_spectral, domain, spectral_scratch(derived))
  vorticity_to_physical!(buffers.vorticity_physical, buffers.velocity_star_spectral, domain, spectral_scratch(derived))
  velocity_rhs!(buffers.stage2, generator, buffers.velocity_star_spectral, buffers.velocity_star, buffers.vorticity_physical, domain)  # N̂_u,2
  if has_scalar
    scalar_to_physical!(sb.field, sb.star_spectral, domain, sb.copy)
    scalar_rhs!(sb.stage2, generator, buffers.velocity_star_spectral, sb.star_spectral, buffers.velocity_star, sb.field, domain)       # N̂_φ,2
  end

  # velocity update: ûₙ₊₁ = E_ν ûₙ + (Δt/2)(E_ν N̂_u,1 + N̂_u,2)
  velocity_factor!(buffers.integrating_factor, generator, domain, dt)
  convolve!(buffers.stage1, buffers.stage1, buffers.integrating_factor)
  convolve!(û, û, buffers.integrating_factor)
  combine!(û, one(T), û, half, buffers.stage1)                                             # ûₙ₊₁ += (Δt/2)(E_ν N̂_u,1 + N̂_u,2)
  combine!(û, one(T), û, half, buffers.stage2)

  # scalar update: φ̂ₙ₊₁ = E_κ φ̂ₙ + (Δt/2)(E_κ N̂_φ,1 + N̂_φ,2)
  if has_scalar
    scalar_factor!(buffers.integrating_factor, generator, domain, dt)
    convolve!(sb.stage1, sb.stage1, buffers.integrating_factor)
    convolve!(φ̂, φ̂, buffers.integrating_factor)
    combine!(φ̂, one(T), φ̂, half, sb.stage1)                                  # φ̂ₙ₊₁ += (Δt/2)(E_κ N̂_φ,1 + N̂_φ,2)
    combine!(φ̂, one(T), φ̂, half, sb.stage2)
  end

  finalize!(generator, state, domain)             # post-step forcing projections (e.g. BandRescaling)
  resolved_fields_modified!(derived)                     # the step advanced the fields — charts go stale
  return û, φ̂
end


# Per-scheme scratch — each scheme allocates exactly its working set; there is no `::AbstractIntegrator`
# fallback, so a scheme with no method here is a hard error (never a silent over-allocation).
# IFLowStorageRK3 uses stage1 + nonlinear; IFRK2 uses stage1 + stage2 + velocity_star_spectral; each
# leaves the other scheme's registers `nothing`.
ScalarBuffers(::IFLowStorageRK3, domain::FixedDomain) = ScalarBuffers(
  scalar_spectral(domain), nothing, nothing, scalar_spectral(domain),           # stage1, stage2, star_spectral, nonlinear
  scalar_spectral(domain), scalar_physical(domain),                             # copy, field
)
ScalarBuffers(::IFRK2, domain::FixedDomain) = ScalarBuffers(
  scalar_spectral(domain), scalar_spectral(domain), scalar_spectral(domain), nothing,   # stage1, stage2, star_spectral, nonlinear
  scalar_spectral(domain), scalar_physical(domain),                             # copy, field
)

allocate_buffers(::IFLowStorageRK3, domain::FixedDomain; scalar::Bool = false) = IntegratorBuffers(
  spectral_vector(domain),                                # stage1
  nothing,                                                # stage2 (IFRK2 only)
  nothing,                                                # velocity_star_spectral (IFRK2 only)
  spectral_vector(domain),                                # nonlinear
  scalar_spectral(domain),                                # integrating_factor
  physical_vector(domain), physical_vector(domain),       # vorticity_physical, velocity_star
  scalar ? ScalarBuffers(IFLowStorageRK3(), domain) : nothing,
)

allocate_buffers(::IFRK2, domain::FixedDomain; scalar::Bool = false) = IntegratorBuffers(
  spectral_vector(domain),                                # stage1
  spectral_vector(domain),                                # stage2
  spectral_vector(domain),                                # velocity_star_spectral
  nothing,                                                # nonlinear (IFLowStorageRK3 only)
  scalar_spectral(domain),                                # integrating_factor
  physical_vector(domain), physical_vector(domain),       # vorticity_physical, velocity_star
  scalar ? ScalarBuffers(IFRK2(), domain) : nothing,
)


"""
    recommended_cfl(integrator, domain)

A conservative advective-CFL ceiling ``C`` for the scheme, for a timestep
``\\Delta t = C \\Delta x / \\max_i\\lvert u_i\\rvert``.

The advective eigenvalues of the dealiased system are imaginary, of magnitude up to
``\\kappa_{\\max}\\sup\\lvert\\boldsymbol{u}\\rvert``; stability needs this times ``C`` to stay within the
scheme's imaginary-axis stability limit ``y_{\\mathrm{s}}``. The timestep divides by the cheaply-measured
maximum component ``\\max_i\\lvert u_i\\rvert`` (within a factor ``\\sqrt3`` of ``\\sup\\lvert\\boldsymbol{u}\\rvert``); that gap is absorbed by the conservative factor below, since the eigenvalue bound itself
over-estimates the true spectral radius (not every mode carries the peak speed). The base ceiling is
calibrated for the ``2/3`` rule (``\\kappa_{\\max}\\Delta x = 2\\pi/3 \\approx 2.09``): for
[`IFLowStorageRK3`](@ref) ``y_{\\mathrm{s}} = \\sqrt{3}`` gives ``C \\lesssim 0.83``, taken
conservatively as ``0.5``; [`IFRK2`](@ref) is imaginary-axis unstable (``y_{\\mathrm{s}} = 0``,
relying on viscous damping), so a small ``0.25``.

It scales that base by the domain's dealiasing: a strategy that keeps modes
to a higher ``\\kappa_{\\max}`` (e.g. `HouLi`, out to the Nyquist wavenumber) takes a
proportionally smaller step, ``C \\propto 1/\\kappa_{\\max}``. This is the value `Simulation` uses;
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
