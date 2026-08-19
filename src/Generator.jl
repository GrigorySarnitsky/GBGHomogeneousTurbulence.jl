# Generator — the flow's equations of motion: the incompressible Navier–Stokes right-hand side in
# rotational form, the passive-scalar advection, and the exact viscous/diffusive integrating factor.
# In the Mori–Zwanzig reading (ARCHITECTURE §8) this is the generator of the full dynamics — the RHS
# the numerical propagator (Propagator) advances; the `Observables` are the functions of that state.
#
# The momentum equation is advanced as ∂û/∂t = ℙ(u×ω)^ − ν|k|²û (+ forcing), with the viscous term
# integrated exactly through the integrating factor ℰ = exp(-ν|k|²Δt) (built here, applied in
# Propagator). This module owns the nonlinear-term assembly and the integrating factor;
# everything diagonal-in-Fourier is a GBGPeriodicFields operator.

"""
    Generator

The flow's equations of motion — the incompressible Navier–Stokes right-hand side in rotational form
(the dealiased, Leray-projected nonlinear term), the passive-scalar advection, and the exact viscous
integrating factor.

Its contents (each formula lives in the operation's own docstring):
- [`FlowConditions`](@ref) — the physical conditions the right-hand side is built from (the viscosity,
  the Schmidt number, the forcings).
- [`ResolvedGenerator`](@ref) — the generator as one value: the conditions bundled with the assembly
  scratch its evaluations write through, consumed by a scheme through the protocol below.
- [`prepare!`](@ref) — open a step: advance the forcings' internal state and fill the linear rate
  arrays the integrating factor will consume.
- [`velocity_rhs!`](@ref), [`scalar_rhs!`](@ref) — assemble the explicit right-hand sides (the
  dealiased, Leray-projected momentum term and the scalar advection, each plus its additive forcing
  source) at a stage state.
- [`velocity_integrating_factor`](@ref), [`scalar_integrating_factor`](@ref) — supply each field's exact linear subflow (the
  viscous/diffusive integrating factor, with any linear forcing rate folded in).
- [`finalize!`](@ref) — close a step: apply the post-step forcing projections to the advanced state.

The assemblies recover displaced fields in physical representation with the four-argument,
source-preserving form (the extra argument is a scratch field the transform consumes in the source's
place) of [`to_physical!`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.to_physical!)
and with [`vorticity_physical!`](@ref GBGIsotropicTurbulence.Observables.vorticity_physical!).
"""
module Generator

using GBGPeriodicFields
using ..SimulationDomain: FixedDomain, DealiasingStrategy, TwoThirds, HouLi, PhaseShift,
                          new_vector_field_spectral, new_vector_field_physical, new_scalar_field_spectral, new_scalar_field_physical
using ..Observables: vorticity_physical!
using ..Forcing: AbstractForcing, NoForcing,
                 set_forcing_rate!, uses_linear_rate, apply_forcing!, prepare_forcing!,
                 add_forcing_source!

export FlowConditions, ResolvedGenerator,
       prepare!, velocity_rhs!, scalar_rhs!, velocity_integrating_factor, scalar_integrating_factor, finalize!


"""
    FlowConditions(; viscosity, schmidt, velocity_forcing, scalar_forcing)

The physical conditions the generator is built from — the kinematic viscosity ``\\nu`` (`viscosity`;
with the box in units where ``u' = L = 1`` this is ``\\mathrm{Re} = 1/\\nu``; on the shipped
defaults (``u' = 1``, ``L = 2\\pi``) the box-scale value is ``2\\pi/\\nu``, and the integral-scale one
smaller again), the Schmidt number ``\\mathrm{Sc}`` (`schmidt`; the
scalar diffusivity is ``\\varkappa = \\nu/\\mathrm{Sc}``), and the velocity and scalar forcing strategies
(`velocity_forcing`, `scalar_forcing`, both
[`AbstractForcing`](@ref GBGIsotropicTurbulence.Forcing.AbstractForcing)).

Not to be confused with `Phenomenology`'s `FlowParameters`, which shares two field names: this type
holds what a run is **configured with**, that one holds what a run has been **measured to have**.

Read through the [`ResolvedGenerator`](@ref) a scheme is handed —
[`step!`](@ref GBGIsotropicTurbulence.Propagator.step!) never holds conditions itself.

# Arguments
All keyword, all required:
- `viscosity` — the kinematic viscosity ``\\nu``.
- `schmidt` — the Schmidt number ``\\mathrm{Sc}``.
- `velocity_forcing`, `scalar_forcing` — the forcing strategies for the velocity and the scalar, each
  an `AbstractForcing` (pass `NoForcing()` to leave a field undriven). A *stateful* strategy must not
  be the same instance for both fields — its per-step state belongs to one field — and the
  constructor throws an `ArgumentError` naming the strategy if it is; build two.

# Fields
The plain constructor `FlowConditions(viscosity, schmidt, velocity_forcing, scalar_forcing)` takes the
four fields directly, in this order; each holds the value documented for the keyword of the same name
above, with the two numbers stored as `Float64`.
"""
struct FlowConditions{VF<:AbstractForcing, SF<:AbstractForcing}
  viscosity::Float64
  schmidt::Float64
  velocity_forcing::VF
  scalar_forcing::SF
end

function FlowConditions(; viscosity, schmidt, velocity_forcing, scalar_forcing)
  # One instance driving both fields conflates their bookkeeping — but only for a strategy that HAS
  # per-field state to conflate. An immutable forcing (`BandRescaling`, `Linear`, `ConstantPower`)
  # carries only its band and its target, so sharing one is harmless; `===` would not even
  # distinguish two separately-built copies of it, since Julia compares immutables by value. The
  # hazard is exactly the mutable strategies, whose scratch and random stream are per-field. Caught
  # here rather than left to a docstring warning, matching how the sibling misconfiguration (a
  # forcing that fills a rate without declaring it) is handled.
  ismutable(velocity_forcing) && velocity_forcing === scalar_forcing &&
    throw(ArgumentError("the same $(nameof(typeof(velocity_forcing))) instance was given as both " *
                        "`velocity_forcing` and `scalar_forcing`; that strategy carries per-field " *
                        "state, so construct one instance per forced field"))
  return FlowConditions(Float64(viscosity), Float64(schmidt), velocity_forcing, scalar_forcing)
end


# Phase-shift dealiasing scratch + the two translation kernels (present only when `dealiasing isa
# PhaseShift`). The kernels are built once from the half-cell displacement; the scalar fields are
# `nothing` for a velocity-only run.
struct PhaseShiftBuffers{K, KB, VS, VP, SS, SP}
  to_shifted::K                   # translation kernel: recover a field on the grid displaced by +½ cell
  back::K                         # translation kernel: shift a displaced term back to the grid
  back_dealiased::KB              # back ∘ the spherical truncation, composed once — the final averaging convolve's kernel
  velocity_shifted::VS            # û on the displaced grid, then the displaced nonlinear term
  u_shifted::VP                   # velocity recovered on the displaced grid
  omega_shifted::VP               # vorticity recovered on the displaced grid
  scalar_shifted::SS              # φ̂ on the displaced grid, then the displaced flux divergence (or nothing)
  scalar_copy::SS                 # recovery scratch for the displaced scalar (or nothing)
  phi_shifted::SP                 # scalar recovered on the displaced grid (or nothing)
end

# Build the two translation kernels once (offset = half a cell), their composition with the
# spherical truncation (the averaging convolve applies both in one pass), and the
# displaced-evaluation scratch; the scalar fields only when a scalar is evolved. A scalar kernel
# translates a vector or scalar field alike.
function PhaseShiftBuffers(domain::FixedDomain, scalar::Bool)
  δ = 0.5 .* domain.grid.grid_spacing
  reference = new_scalar_field_spectral(domain)
  back = translation_kernel(reference, domain.multipliers, δ)
  return PhaseShiftBuffers(
    translation_kernel(reference, domain.multipliers, .-δ),   # sample on the +½-cell grid (negated offset)
    back,
    convolve(domain.dealias, back),                           # 𝔻 ∘ back — kilobytes, never a field
    new_vector_field_spectral(domain),
    new_vector_field_physical(domain), new_vector_field_physical(domain),
    scalar ? new_scalar_field_spectral(domain) : nothing,
    scalar ? new_scalar_field_spectral(domain) : nothing,
    scalar ? new_scalar_field_physical(domain) : nothing,
  )
end


# A rate array exists only for a forcing that declares one — the storage tracks the physics, not the
# possibility of it. A forcing that fills a rate without declaring it would be handed `nothing` and go
# silently unapplied, so that mismatch is a construction-time error rather than a wrong quiet run.
function _forcing_rate(domain::FixedDomain, forcing)
  if !uses_linear_rate(forcing)
    _overrides_rate_hook(forcing) &&
      throw(ArgumentError("$(nameof(typeof(forcing))) implements set_forcing_rate! but does not " *
                          "declare uses_linear_rate(::$(nameof(typeof(forcing)))) = true, so it " *
                          "would be given no rate array to fill and would never be applied"))
    return nothing
  end
  # A scalar field in spectral representation holding REAL values (the complex container is what the
  # fused exponential's per-mode offset takes), zeroed so an un-set rate acts as no forcing.
  return new_scalar_field_spectral(domain)
end

# Does this forcing define its own `set_forcing_rate!`, rather than inheriting the do-nothing
# fallback? An unresolvable lookup (an ambiguity against the fallback) can only arise from a method
# the forcing itself added, so it answers yes.
_overrides_rate_hook(forcing) =
  try
    which(set_forcing_rate!, Tuple{typeof(forcing), Any, Any, FixedDomain}) !==
      which(set_forcing_rate!, Tuple{AbstractForcing, Any, Any, FixedDomain})
  catch
    true
  end


"""
    ResolvedGenerator(domain, conditions; scalar = false)

The flow's generator as one value a scheme can hold. It carries the
[`FlowConditions`](@ref) parameter record together with the assembly scratch its evaluations write
through: the quadratic-product fields, the per-mode forcing-rate arrays, and — when the domain
dealiases by [`PhaseShift`](@ref GBGIsotropicTurbulence.SimulationDomain.PhaseShift) — the
displaced-evaluation buffers.

That scratch is the **generator's own** storage, distinct from the run's observables cache. The two
do meet at one point: the physical quadratic products are formed *in place over the cache's arrays*,
the Lamb vector over the vorticity slot and the scalar flux over the velocity slot, so no product
field in physical representation is allocated anywhere.

A time-marching scheme consumes the generator through a fixed protocol: [`prepare!`](@ref) once per
step, [`velocity_rhs!`](@ref) / [`scalar_rhs!`](@ref) at each stage state,
[`velocity_integrating_factor`](@ref) / [`scalar_integrating_factor`](@ref) for the exact linear
subflows, and [`finalize!`](@ref) after the completed step. The scheme does only stage arithmetic, so
it can never assemble the right-hand side from a mismatched intermediate state.

# Arguments
- `domain` — the [`FixedDomain`](@ref) the assembly scratch is sized on.
- `conditions` — the [`FlowConditions`](@ref) the generator resolves: the viscosity, the Schmidt
  number, and the two forcing strategies.
- `scalar = false` — pass `true` when the run carries a passive scalar; it allocates the scalar's
  forcing-rate array, required for a scalar-forced run.

The [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) front door builds one for
you.

!!! warning "The constructor rejects a misdeclared forcing"
    A forcing that implements
    [`set_forcing_rate!`](@ref GBGIsotropicTurbulence.Forcing.set_forcing_rate!) without also
    declaring `uses_linear_rate` is given no
    rate array to fill, so its forcing would silently never be applied. Building a
    `ResolvedGenerator` around one throws an `ArgumentError` naming the strategy, rather than letting
    the run proceed quietly wrong.

!!! note "One optimization crosses two verbs"
    Under `PhaseShift`, `velocity_rhs!` leaves the stage's displaced velocity fresh for the same
    stage's `scalar_rhs!` to reuse, through the `displaced_velocity_fresh` flag rather than through
    either signature. It is opportunistic, never load-bearing: a `scalar_rhs!` that finds the flag clear
    rebuilds the displaced velocity itself, value-identically.

# Fields
- `conditions` — the `FlowConditions` parameter record (``\\nu``, ``\\mathrm{Sc}``, the forcings).
- `product_spectral` — the quadratic products' spectral image (the transformed Lamb vector
  ``\\boldsymbol{u}\\times\\boldsymbol{\\omega}``, or the transformed scalar flux
  ``\\boldsymbol{u}\\varphi``). In physical representation each product is formed in place over an
  operand's own array — the Lamb vector over the vorticity's, the flux over the velocity's — so
  no physical product array exists.
- `phase_shift` — the displaced-evaluation scratch and translation kernels (`PhaseShift` dealiasing
  only), else `nothing`.
- `velocity_rate`, `scalar_rate` — the per-mode linear forcing-rate arrays ``A(\\boldsymbol{\\kappa})``.
  `prepare!` fills them at the start of each step; a rate that has been filled is one the
  integrating-factor verbs then return alongside the viscous coefficient, so the forcing rides the
  exact linear solve instead of being added afterwards. Each is `nothing` unless that field's forcing declares
  [`uses_linear_rate`](@ref GBGIsotropicTurbulence.Forcing.uses_linear_rate), so a field driven by
  a post-step projection, a stochastic source, or nothing at
  all carries no rate storage; `scalar_rate` is also `nothing` for a scalar-free generator.
- `displaced_velocity_fresh` — whether `phase_shift.u_shifted` still holds the current stage's
  displaced velocity, left fresh by `velocity_rhs!` for the same stage's
  `scalar_rhs!` to consume (`PhaseShift` only; a bare `scalar_rhs!` finding it stale
  rebuilds the recovery itself).
"""
mutable struct ResolvedGenerator{C<:FlowConditions, PS, PB, RK, SR}
  const conditions::C
  const product_spectral::PS
  const phase_shift::PB
  const velocity_rate::RK
  const scalar_rate::SR
  displaced_velocity_fresh::Bool   # PhaseShift: u_shifted still holds THIS stage's displaced velocity
end

ResolvedGenerator(domain::FixedDomain, conditions::FlowConditions; scalar::Bool = false) =
  ResolvedGenerator(conditions,
                    new_vector_field_spectral(domain),
                    domain.dealiasing isa PhaseShift ? PhaseShiftBuffers(domain, scalar) : nothing,
                    _forcing_rate(domain, conditions.velocity_forcing),
                    scalar ? _forcing_rate(domain, conditions.scalar_forcing) : nothing,
                    false)


"""
    prepare!(generator, state, domain, dt)

Open a step of the [`ResolvedGenerator`](@ref) `generator`: advance each forcing's internal state once (its per-step
[`prepare_forcing!`](@ref GBGIsotropicTurbulence.Forcing.prepare_forcing!) hook) and arm the
per-mode linear forcing rates (fill them, so the factor verbs return them instead of `nothing`)
(its [`set_forcing_rate!`](@ref GBGIsotropicTurbulence.Forcing.set_forcing_rate!) hook,
written into the generator's rate arrays) from the start-of-step `state` (a
[`ResolvedFields`](@ref GBGIsotropicTurbulence.State.ResolvedFields)) over the
timestep `dt`, on the [`FixedDomain`](@ref) `domain`. A scheme calls this once before its Runge–Kutta
stages; the stage evaluations and the integrating factors then consume what it prepared. Returns
`generator`.
"""
function prepare!(generator::ResolvedGenerator, state, domain::FixedDomain, dt::Real)
  generator.displaced_velocity_fresh = false        # a new step opens with the displaced scratch stale
  conditions = generator.conditions
  prepare_forcing!(conditions.velocity_forcing, state.velocity_spectral, domain, dt)
  generator.velocity_rate === nothing ||
    set_forcing_rate!(conditions.velocity_forcing, generator.velocity_rate, state.velocity_spectral, domain)
  if state.scalar_spectral !== nothing
    prepare_forcing!(conditions.scalar_forcing, state.scalar_spectral, domain, dt)
    generator.scalar_rate === nothing ||
      set_forcing_rate!(conditions.scalar_forcing, generator.scalar_rate, state.scalar_spectral, domain)
  end
  return generator
end


"""
    finalize!(generator, state, domain)

Close a step of the [`ResolvedGenerator`](@ref) `generator`: apply each of its forcings' post-step
projections (the [`apply_forcing!`](@ref GBGIsotropicTurbulence.Forcing.apply_forcing!) hook —
e.g. the energy rescale of a [`BandRescaling`](@ref GBGIsotropicTurbulence.Forcing.BandRescaling))
to the advanced `state`, velocity first, then the scalar
when the run carries one, on the [`FixedDomain`](@ref) `domain`. A scheme calls this once after its final stage, so everything that follows
the step — the diagnostics, the derived observables, the tracer advance — sees the forced end-of-step fields.
Returns `state`.
"""
function finalize!(generator::ResolvedGenerator, state, domain::FixedDomain)
  apply_forcing!(generator.conditions.velocity_forcing, state.velocity_spectral, domain)
  state.scalar_spectral === nothing || apply_forcing!(generator.conditions.scalar_forcing, state.scalar_spectral, domain)
  return state
end


"""
    velocity_rhs!(N̂, generator, û, u, ω_consumed, domain)

Assemble the explicit right-hand side of the momentum equation into `N̂` — the dealiased,
Leray-projected rotational nonlinear term plus any additive forcing source — from the stage velocity
`û` in spectral representation and its physical velocity `u` and vorticity `ω_consumed`, on the
[`FixedDomain`](@ref) `domain`, using the [`ResolvedGenerator`](@ref) `generator`'s conditions and
scratch. The vorticity argument is named `ω_consumed` because the assembly overwrites it: on return it no
longer holds the vorticity.

In physical space the rotational form writes the convective term as the Lamb vector, through the identity

```math
(\\boldsymbol{u}\\cdot\\nabla)\\boldsymbol{u} = \\nabla\\bigl(\\tfrac{1}{2}\\lvert\\boldsymbol{u}\\rvert^{2}\\bigr) - \\boldsymbol{u}\\times\\boldsymbol{\\omega},
```

so that, with the Leray–Helmholtz projection ``\\mathbb{P}`` onto divergence-free fields absorbing the
pressure and the ``\\nabla(\\tfrac{1}{2}\\lvert\\boldsymbol{u}\\rvert^{2})`` gradient, the momentum equation
becomes

```math
\\partial_t\\boldsymbol{u} = \\mathbb{P} (\\boldsymbol{u}\\times\\boldsymbol{\\omega}) + \\nu\\nabla^{2}\\boldsymbol{u} + \\boldsymbol{f}.
```

The term computed is the spectral image of ``\\mathbb{P} (\\boldsymbol{u}\\times\\boldsymbol{\\omega})``,
dealiased by the domain's [`DealiasingStrategy`](@ref), plus the per-stage additive source of the
generator's velocity forcing (its
[`add_forcing_source!`](@ref GBGIsotropicTurbulence.Forcing.add_forcing_source!) hook). A **mask**
strategy ([`TwoThirds`](@ref),
[`HouLi`](@ref)) forms the term once from `u`, `ω` and multiplies by the low-pass `domain.dealias`,
leaving `û` unused; [`PhaseShift`](@ref) forms it **twice** — from `u`, `ω`, and from the fields
recovered on a grid displaced by half a cell (using `û` and the generator's displaced-evaluation
scratch) — averages the two to cancel the aliasing, then truncates spherically with `domain.dealias`.

Two linear pieces are deliberately **not** in `N̂`: the viscous term and the exactly-linear part of a
forcing are advanced exactly by the integrating factor ([`velocity_integrating_factor`](@ref)).

Returns `N̂`.

!!! note "The vorticity argument is read and then overwritten"
    The Lamb vector is formed in place over the vorticity's array — the backend's cross product may
    write into one of its operands — so `ω_consumed` must hold the vorticity on entry and no longer
    does on return, while `u` is only read. This is what keeps a product field in physical
    representation from existing at all; passing a copy instead would cost a resident ``N^{3}``
    vector, which the footprint invariant forbids.

    Which operand is consumed follows the **physics**, not the argument position: the Lamb vector
    forms over the vorticity here, and the scalar flux over the velocity in
    [`scalar_rhs!`](@ref) — which is why both name the consumed argument rather than leaving a caller
    to infer it. Only the spectral product scratch remains on the generator, and the operation
    allocates nothing.
"""
velocity_rhs!(N̂, generator::ResolvedGenerator, û, u, ω_consumed, domain::FixedDomain) =
  (_velocity_nonlinear!(domain.dealiasing, N̂, generator, û, u, ω_consumed, domain);
   add_forcing_source!(generator.conditions.velocity_forcing, N̂, domain))

# Mask strategies (TwoThirds / HouLi): one evaluation, the low-pass kernel folded into the
# projection's own pass (the kernel-composed ℙ arity) — one pass fewer than project-then-convolve.
function _velocity_nonlinear!(::DealiasingStrategy, nonlinear, generator, û, u, ω_consumed, domain::FixedDomain)
  _velocity_lamb!(nonlinear, u, ω_consumed, domain, generator.product_spectral, domain.dealias)
  return nonlinear
end

# Phase-shift: average the primary and the half-cell-displaced evaluation (cancels the odd-parity
# aliases); the spherical `domain.dealias` truncation removes the surviving two-axis aliases, folded
# into the passes rather than swept separately — the primary carries it inside its projection, and
# the displaced term picks it up through the composed shift-back∘truncation kernel of the averaging
# convolve, so no whole-field truncation pass remains.
function _velocity_nonlinear!(::PhaseShift, nonlinear, generator, û, u, ω_consumed, domain::FixedDomain)
  phase_shift = generator.phase_shift
  product_spectral = generator.product_spectral
  T = real(eltype(field_data(nonlinear)))
  _velocity_lamb!(nonlinear, u, ω_consumed, domain, product_spectral, domain.dealias)   # primary, truncated
  convolve!(phase_shift.velocity_shifted, û, phase_shift.to_shifted)                                   # û on the displaced grid
  to_physical!(phase_shift.u_shifted, phase_shift.velocity_shifted, domain.velocity_plans, product_spectral)
  vorticity_physical!(phase_shift.omega_shifted, phase_shift.velocity_shifted, domain, product_spectral)
  # The displaced Lamb consumes ω_shifted only, so u_shifted still holds this stage's displaced
  # velocity — left fresh for the scalar assembly of the SAME stage (the freshness contract that
  # deletes its re-recovery, decision 45).
  generator.displaced_velocity_fresh = true
  _velocity_lamb!(phase_shift.velocity_shifted, phase_shift.u_shifted, phase_shift.omega_shifted, domain, product_spectral)
  # Shift-back, two-grid average, and truncation in ONE α/β convolve: ½·(𝔻⊙back)⊙(displaced) +
  # ½·(primary, already truncated) — the composed kernel is built once at construction.
  convolve!(nonlinear, phase_shift.velocity_shifted, phase_shift.back_dealiased, T(1 // 2), T(1 // 2))
  return nonlinear
end

# The pseudospectral ℙ(u×ω) in spectral representation — with an optional dealias kernel folded into
# the projection's own pass (the kernel-composed arity; `nothing` gives the raw projected term).
# The Lamb vector is formed IN PLACE over ω's array: the backend's cross product reads each grid
# point's whole fiber before writing, so the destination may be an operand, and the product needs no
# physical register of its own (ω is dead the instant after the cross — the projection's spectral
# image carries the term from here).
function _velocity_lamb!(out, u, ω, domain::FixedDomain, product_spectral, kernel = nothing)
  cross!(ω, u, ω)
  to_spectral!(product_spectral, ω, domain.velocity_plans)
  kernel === nothing ? helmholtz_projection!(out, product_spectral, domain.multipliers) :
                       helmholtz_projection!(out, product_spectral, domain.multipliers, kernel)
  return out
end


"""
    velocity_integrating_factor(generator, τ)

The velocity's exact linear subflow over a substep ``\\tau`` (`τ`), as the **parameters of its
exponential** rather than a materialized kernel. The linear part of the momentum equation — the
diffusion ``\\partial_t\\boldsymbol{u} = \\nu\\nabla^{2}\\boldsymbol{u}``, plus any linear forcing rate
``A(\\boldsymbol{\\kappa})`` that [`prepare!`](@ref) armed — is solved exactly in spectral
representation by the per-mode multiplier

```math
\\mathcal{E}(\\boldsymbol{\\kappa}) = \\exp\\!\\bigl((A(\\boldsymbol{\\kappa}) - \\nu\\lvert\\boldsymbol{\\kappa}\\rvert^{2}) \\tau\\bigr),
```

with ``A = 0`` when no linear forcing is active, so multiplying a field by ``\\mathcal{E}`` advances its
viscous (and linear-forcing) part exactly — machine-exact, with no stability restriction; only a
scheme's explicit stage combination carries truncation error. Since the multiplier is the exponential
of a radial symbol (plus the armed per-mode rate), a scheme applies it through the backend's fused
exponential convolution
([`exponential_convolve!`](@extref GBGPeriodicFields GBGPeriodicFields.Convolution.exponential_convolve!)),
which evaluates it per mode from the wavenumber arrays: nothing is built,
stored, or swept for it. Accordingly this verb returns the exponential's parameters as a named tuple —
``\\texttt{coefficient} = -\\nu\\tau`` (the factor on ``\\lvert\\boldsymbol{\\kappa}\\rvert^{2}``),
``\\texttt{offset\\_scale} = \\tau`` and ``\\texttt{offset} = A(\\boldsymbol{\\kappa})`` (the armed rate field, or `nothing` when no
linear forcing is active) — exactly the arguments the fused exponential takes.

The `generator` (a [`ResolvedGenerator`](@ref)) supplies ``\\nu`` and the armed rate; `τ` is the
sub-interval the stage advances.
"""
velocity_integrating_factor(generator::ResolvedGenerator, τ::Real) =
  (coefficient = -generator.conditions.viscosity * τ, offset_scale = τ,
   offset = generator.velocity_rate)


"""
    scalar_integrating_factor(generator, τ)

The passive scalar's exact linear subflow over a substep `τ` — the same exponential parameters
[`velocity_integrating_factor`](@ref) returns for `generator`, with the scalar diffusivity
``\\varkappa = \\nu/\\mathrm{Sc}`` in place of
``\\nu`` and the scalar forcing's armed linear rate in place of the velocity's.
"""
scalar_integrating_factor(generator::ResolvedGenerator, τ::Real) =
  (coefficient = -(generator.conditions.viscosity / generator.conditions.schmidt) * τ,
   offset_scale = τ,
   offset = generator.scalar_rate)


"""
    scalar_rhs!(N̂, generator, û, φ̂, u_consumed, φ, domain)

Assemble the explicit right-hand side of the passive-scalar equation into `N̂` — the dealiased
advection term plus any additive forcing source — from the stage velocity `û` and scalar `φ̂` in
spectral representation and their physical `u_consumed`, `φ`, on the [`FixedDomain`](@ref) `domain`,
using the [`ResolvedGenerator`](@ref) `generator`'s conditions and scratch. The velocity argument
is named `u_consumed` because the assembly overwrites it: on return it no longer holds the
velocity.

In conservative form the advection is ``-\\nabla\\cdot(\\boldsymbol{u}\\varphi)`` (equal to
``-\\boldsymbol{u}\\cdot\\nabla\\varphi`` since ``\\nabla\\cdot\\boldsymbol{u} = 0``); the conservative form
conserves the scalar mean exactly — the divergence has no ``\\boldsymbol{\\kappa}=\\boldsymbol{0}``
component, and the dealias kernel `domain.dealias` (the sharp ``2/3`` rule by default) leaves that mode
untouched.

It is computed pseudospectrally as
``- \\operatorname{dealias}\\bigl(\\mathrm{i}\\boldsymbol{\\kappa}\\cdot\\widehat{\\boldsymbol{u}\\varphi}\\bigr)``,
plus the per-stage additive source of the generator's scalar forcing (its
[`add_forcing_source!`](@ref GBGIsotropicTurbulence.Forcing.add_forcing_source!) hook).
The dealiasing strategy controls the aliasing of the quadratic product: a **mask** strategy
([`TwoThirds`](@ref), [`HouLi`](@ref)) forms the flux once from `u_consumed`, `φ`, leaving `û` and `φ̂` unused;
[`PhaseShift`](@ref) instead averages it with the flux recovered on a grid displaced half a cell —
using `φ̂` and the generator's displaced-evaluation scratch, and reading the displaced velocity the
same stage's [`velocity_rhs!`](@ref) left fresh there (a bare `scalar_rhs!` with no preceding
velocity evaluation rebuilds it from `û` instead) — before the spherical truncation.
The diffusion ``\\varkappa\\nabla^{2}\\varphi`` and the exactly-linear part of a forcing are **not** in
`N̂`: they are advanced exactly by [`scalar_integrating_factor`](@ref).

Returns `N̂`.

!!! note "The assembly consumes the velocity argument"
    The assembly **consumes `u_consumed`**: the flux ``\\boldsymbol{u}\\varphi`` is formed
    in place over the velocity's array (a pointwise product may write into an operand), so on return
    `u_consumed` no longer holds the velocity; `φ` is only read. As in `velocity_rhs!`, the
    consumed argument is fixed by the physics rather than by its position in the signature, and is
    named for it. Only the spectral
    product scratch remains on
    the generator, and the operation allocates nothing.
"""
scalar_rhs!(N̂, generator::ResolvedGenerator, û, φ̂, u_consumed, φ, domain::FixedDomain) =
  (_scalar_nonlinear!(domain.dealiasing, N̂, generator, û, φ̂, u_consumed, φ, domain);
   add_forcing_source!(generator.conditions.scalar_forcing, N̂, domain))

# Mask strategies: one flux evaluation, then the divergence with the low-pass kernel AND the −∇·
# sign folded into its own pass (the kernel-composed arity, α = −1) — one pass fewer.
function _scalar_nonlinear!(::DealiasingStrategy, nonlinear, generator, û, φ̂, u_consumed, φ, domain::FixedDomain)
  _scalar_flux_divergence!(nonlinear, u_consumed, φ, domain, generator.product_spectral, domain.dealias, -1)
  return nonlinear
end

# Phase-shift: average the primary and half-cell-displaced flux divergences (cancels the odd-parity
# aliases); the spherical truncation and the −∇· sign fold into the passes — the primary carries
# both inside its divergence, the displaced term picks the truncation up through the composed
# shift-back∘truncation kernel and the sign through the averaging α — so no whole-field truncation
# pass remains.
function _scalar_nonlinear!(::PhaseShift, nonlinear, generator, û, φ̂, u_consumed, φ, domain::FixedDomain)
  phase_shift = generator.phase_shift
  product_spectral = generator.product_spectral
  T = real(eltype(field_data(nonlinear)))
  _scalar_flux_divergence!(nonlinear, u_consumed, φ, domain, product_spectral, domain.dealias, -1)   # primary −𝔻∇·(uφ)
  # The same stage's velocity assembly left the displaced velocity fresh in u_shifted (its displaced
  # Lamb consumes only ω_shifted), so the re-recovery — one shift convolve and three inverse
  # transforms — exists only on the fallback path a hand-run bare `scalar_rhs!` takes (decision 45).
  if !generator.displaced_velocity_fresh
    convolve!(phase_shift.velocity_shifted, û, phase_shift.to_shifted)                                   # û on the displaced grid
    to_physical!(phase_shift.u_shifted, phase_shift.velocity_shifted, domain.velocity_plans, product_spectral)
  end
  generator.displaced_velocity_fresh = false        # the flux below consumes u_shifted
  convolve!(phase_shift.scalar_shifted, φ̂, phase_shift.to_shifted)                                       # φ̂ on the displaced grid
  to_physical!(phase_shift.phi_shifted, phase_shift.scalar_shifted, domain.scalar_plans, phase_shift.scalar_copy)
  _scalar_flux!(product_spectral, phase_shift.u_shifted, phase_shift.phi_shifted, domain)                # (u_s φ_s)^, formed over u_s
  divergence!(phase_shift.scalar_shifted, product_spectral, domain.multipliers)                          # displaced ∇·, still on the displaced grid
  # The shift-back symbol commutes through the iκ· contraction (iκ·(ĝ v̂) = ĝ (iκ·v̂)), so it rides
  # the averaging convolve with the truncation composed in and the sign on α:
  # −½·(𝔻⊙back)⊙(displaced ∇·) + ½·(primary, already −𝔻∇·).
  convolve!(nonlinear, phase_shift.scalar_shifted, phase_shift.back_dealiased, T(-1 // 2), T(1 // 2))
  return nonlinear
end

# ∇·(uφ) in spectral representation — with an optional dealias kernel and sign folded into the
# divergence's own pass (the kernel-composed arity; `nothing` gives the raw divergence).
function _scalar_flux_divergence!(out, u, φ, domain::FixedDomain, product_spectral,
                                  kernel = nothing, α = 1)
  _scalar_flux!(product_spectral, u, φ, domain)
  kernel === nothing ? divergence!(out, product_spectral, domain.multipliers) :
                       divergence!(out, product_spectral, domain.multipliers, kernel, α, 0)
  return out
end

# The flux uφ (a vector), transformed to spectral into `flux_spectral`. The flux is formed IN PLACE
# over u's array (the pointwise multiply writes each grid point from its own operands, so the
# destination may be an operand): u is dead the instant after the multiply, and the flux needs no
# physical register of its own.
function _scalar_flux!(flux_spectral, u, φ, domain::FixedDomain)
  multiply!(u, φ, u)
  to_spectral!(flux_spectral, u, domain.velocity_plans)
  return flux_spectral
end


end # module Generator
