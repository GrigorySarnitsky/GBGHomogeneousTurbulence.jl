# Generator — the flow's equations of motion: the incompressible Navier–Stokes right-hand side in
# rotational form, the passive-scalar advection, and the exact viscous/diffusive integrating factor.
# In the Mori–Zwanzig reading (ARCHITECTURE §8) this is the generator of the full dynamics — the RHS
# the numerical propagator (Propagator) advances; the `Observables` are the functions of that state.
#
# The momentum equation is advanced as ∂û/∂t = −ℙ(ω×u)^ − ν|κ|²û (+ forcing), ω×u the Lamb vector, with the viscous term
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
- [`ResolvedGenerator`](@ref) — the conditions bundled with the assembly scratch, consumed
  through the protocol below.
- [`prepare!`](@ref) — open a step: advance the forcings' internal state and fill the linear rate
  arrays the integrating factors consume.
- [`velocity_rhs!`](@ref), [`scalar_rhs!`](@ref) — assemble the explicit right-hand sides (each
  dealiased term plus its additive forcing source) at a stage state.
- [`velocity_integrating_factor`](@ref), [`scalar_integrating_factor`](@ref) — supply each field's
  viscous/diffusive integrating factor, with any linear forcing rate folded in.
- [`finalize!`](@ref) — apply the post-step forcing projections; the *iteration* closes later, at the deposit.

The assemblies recover displaced fields in physical representation with the four-argument,
source-preserving form of
[`to_physical!`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.to_physical!) — the extra
argument is a scratch field the transform consumes in the source's place — and with
[`vorticity_physical!`](@ref GBGHomogeneousTurbulence.Observables.vorticity_physical!).
"""
module Generator

using GBGPeriodicFields
using ..SimulationDomain: FixedDomain, DealiasingStrategy, TwoThirds, HouLi, PhaseShift,
                          new_vector_field_spectral, new_vector_field_physical, new_scalar_field_spectral, new_scalar_field_physical
using ..Observables: vorticity_physical!
using ..Forcing: AbstractForcing, NoForcing, VarianceController,
                 set_forcing_rate!, uses_steady_linear_rate, project_forcing!, prepare_forcing!,
                 add_forcing_source!

export FlowConditions, ResolvedGenerator,
       prepare!, velocity_rhs!, scalar_rhs!, velocity_integrating_factor, scalar_integrating_factor, finalize!


"""
    FlowConditions(; viscosity, schmidt, velocity_forcing, scalar_forcing)

The physical conditions the generator is built from — the kinematic viscosity ``\\nu`` (`viscosity`;
``\\mathrm{Re} = u'L/\\nu``: with ``u' = 1`` and the shipped ``L = 2\\pi`` the box-scale value is
``2\\pi/\\nu``, and ``1/\\nu`` when lengths are measured in box units; the Reynolds number
built on the integral scale is smaller still), the Schmidt number ``\\mathrm{Sc}`` (`schmidt`; the
scalar diffusivity is ``\\varkappa = \\nu/\\mathrm{Sc}``), and the velocity and scalar forcing strategies
(`velocity_forcing`, `scalar_forcing`, both
[`AbstractForcing`](@ref GBGHomogeneousTurbulence.Forcing.AbstractForcing)).

Not to be confused with `Phenomenology`'s `FlowParameters`, which shares two field names: this type
holds what a run is **configured with**, that one holds what a run has been **measured to have**.

Read through the [`ResolvedGenerator`](@ref) a scheme is handed —
[`step!`](@ref GBGHomogeneousTurbulence.Propagator.step!) never holds conditions itself.

# Arguments
All keyword, all required:
- `viscosity` — the kinematic viscosity ``\\nu``.
- `schmidt` — the Schmidt number ``\\mathrm{Sc}``.
- `velocity_forcing`, `scalar_forcing` — the forcing strategies for the velocity and the scalar, each
  an `AbstractForcing` (pass `NoForcing()` to leave a field undriven).

!!! warning "A strategy with mutable bookkeeping cannot drive both fields"
    Its bookkeeping belongs to one field, so passing the same *mutable* strategy instance as both
    `velocity_forcing` and `scalar_forcing` throws an `ArgumentError` naming it. Build two. The
    package's own strategies carry nothing between calls and may be shared.

!!! warning "A defaulted controller settling time never drives the scalar"
    A [`VarianceController`](@ref GBGHomogeneousTurbulence.Forcing.VarianceController) whose
    `turnover_time` was left at its default derives the settling time from a kinetic-energy law,
    which is meaningless for a scalar variance — passed as `scalar_forcing` with a positive gain
    it throws an `ArgumentError`. Pass the flow's turnover time explicitly.

# Fields
The plain constructor `FlowConditions(viscosity, schmidt, velocity_forcing, scalar_forcing)` takes the
four fields directly, in the order shown; each holds the value documented for the keyword of the same name
above, with the two numbers stored as `Float64`.
"""
struct FlowConditions{VF<:AbstractForcing, SF<:AbstractForcing}
  viscosity::Float64
  schmidt::Float64
  velocity_forcing::VF
  scalar_forcing::SF

  # The guards live in the INNER constructor so that no construction path skips them — the docstring
  # advertises the plain positional form alongside the keyword one, and both must honour the same
  # contract (the auto-generated positional form once bypassed all three; a run built through it
  # could carry ν ≤ 0, Sc ≤ 0, or one mutable forcing driving both fields, and each failed far from
  # the call that caused it).
  function FlowConditions(viscosity::Float64, schmidt::Float64, velocity_forcing::VF,
                          scalar_forcing::SF) where {VF<:AbstractForcing, SF<:AbstractForcing}
    # Both set a diffusivity, and a non-positive one is not a physical regime: ν is the inverse
    # Reynolds number, and the scalar diffusivity is ν/Sc, so Sc = 0 divides by zero and NaNs the
    # scalar on the first step. Nothing downstream notices — the run's blow-up guard reads the
    # velocity, which stays perfectly finite while the scalar is entirely NaN — so the check belongs
    # here, where the value arrives.
    viscosity > 0 ||
      throw(ArgumentError("`viscosity` must be positive, got $viscosity: it sets the Reynolds number " *
                          "through Re = 1/ν, and a non-positive value has no dissipation scale"))
    schmidt > 0 ||
      throw(ArgumentError("`schmidt` must be positive, got $schmidt: the scalar diffusivity is ν/Sc, " *
                          "so a non-positive Schmidt number makes it infinite or negative"))
    # One instance driving both fields conflates their bookkeeping — but only for a strategy that HAS
    # per-field state to conflate. An immutable forcing (`VarianceRescaling`, `Linear`, `ConstantPower`)
    # carries only its band and its target, so sharing one is harmless; `===` would not even
    # distinguish two separately-built copies of it, since Julia compares immutables by value. The
    # hazard is exactly the mutable strategies, whose scratch and random stream are per-field. Caught
    # here rather than left to a docstring warning, matching how the sibling misconfiguration (a
    # forcing that fills a rate without declaring it) is handled.
    ismutable(velocity_forcing) && velocity_forcing === scalar_forcing &&
      throw(ArgumentError("the same $(nameof(typeof(velocity_forcing))) instance was given as both " *
                          "`velocity_forcing` and `scalar_forcing`; that strategy carries per-field " *
                          "state, so construct one instance per forced field"))
    # A defaulted controller settling time is Bassenne's kinetic-energy law — valid only when the
    # target IS a kinetic energy. Bound to the scalar, the derived tℓ would scale with the scalar's
    # amplitude unit and break the scalar equation's exact linearity in φ (owner-ruled 2026-08-25).
    # At gain = 0 the restoring term vanishes and tℓ never enters the dynamics, so the marginal
    # law stays legal whatever the provenance.
    scalar_forcing isa VarianceController && scalar_forcing.turnover_time_derived &&
      scalar_forcing.gain > 0 &&
      throw(ArgumentError("this `VarianceController` is bound as `scalar_forcing` but its " *
                          "`turnover_time` was left at the default, which derives the settling " *
                          "time from a kinetic-energy law; a scalar variance is not an energy, so " *
                          "the derived value would depend on the scalar's amplitude unit. Pass " *
                          "`turnover_time` explicitly — the flow's large-eddy turnover time " *
                          "2k/(3ε) is the physical choice."))
    return new{VF, SF}(viscosity, schmidt, velocity_forcing, scalar_forcing)
  end
end

# The positional form with non-Float64 diffusivities promotes, then runs the same inner guards.
FlowConditions(viscosity::Real, schmidt::Real, velocity_forcing::AbstractForcing,
               scalar_forcing::AbstractForcing) =
  FlowConditions(Float64(viscosity), Float64(schmidt), velocity_forcing, scalar_forcing)


"""
    scalar_diffusivity(conditions) -> Float64

The scalar diffusivity ``\\varkappa = \\nu/\\mathrm{Sc}`` the [`FlowConditions`](@ref) `conditions`
imply for the passive scalar.
"""
scalar_diffusivity(conditions::FlowConditions) = conditions.viscosity / conditions.schmidt

FlowConditions(; viscosity, schmidt, velocity_forcing, scalar_forcing) =
  FlowConditions(Float64(viscosity), Float64(schmidt), velocity_forcing, scalar_forcing)


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
  back = translation_kernel(domain.multipliers, δ)
  return PhaseShiftBuffers(
    translation_kernel(domain.multipliers, .-δ),              # sample on the +½-cell grid (negated offset)
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
function _forcing_rate(domain::FixedDomain, forcing, allocate_probe = new_vector_field_spectral)
  if !uses_steady_linear_rate(forcing)
    _overrides_rate_hook(forcing) &&
      throw(ArgumentError("$(nameof(typeof(forcing))) implements set_forcing_rate! but does not " *
                          "declare uses_steady_linear_rate(::$(nameof(typeof(forcing)))) = true, so it " *
                          "would be given no rate array to fill and would never be applied"))
    return nothing
  end
  # The mirror of the guard below: a forcing DECLARING the rate without IMPLEMENTING the hook
  # inherits the do-nothing default, whose untouched (zeroed) rate is trivially steady — the probe
  # cannot see the difference between "steady" and "absent", so absence is checked first.
  _overrides_rate_hook(forcing) ||
    throw(ArgumentError("$(nameof(typeof(forcing))) declares uses_steady_linear_rate = true but " *
                        "does not implement set_forcing_rate!, so its rate array would stay zero " *
                        "and the forcing would silently never act. Implement the hook, or declare " *
                        "false."))
  # A steady rate does not depend on the state, so the one the probe filled is THE rate: it is filled
  # here, once, and never again. A scalar field in spectral representation holding REAL values — the
  # complex container is what the fused exponential's per-mode offset takes.
  return _check_rate_is_steady(domain, forcing, allocate_probe)
end


# The declaration says the rate is STEADY, and steadiness is the property that makes folding it into
# the integrating factor exact. Unlike the arity guards this one is semantic, so it is measured
# rather than trusted: the hook is filled from two different states, and a rate that tracks the state
# gives two different answers. Letting it lie is not a cosmetic error — a state-dependent rate frozen
# for the step is the left-endpoint rectangle rule on ∫A dt, which drops a third-order scheme to
# first order and does so silently, because every value in sight stays finite and plausible.
#
# The probes are all-ones and a spatially varying ramp, so the pair differs in BOTH magnitude and
# shape: a rate keyed to the field's amplitude and one keyed to its distribution across modes are
# each caught. Twice at construction, never in the loop; the first fill is returned as the rate.
function _check_rate_is_steady(domain::FixedDomain, forcing, allocate_probe)
  probe = allocate_probe(domain)
  first_rate, second_rate = new_scalar_field_spectral(domain), new_scalar_field_spectral(domain)

  fill!(field_data(probe), 1)
  set_forcing_rate!(forcing, first_rate, probe, domain)
  data = field_data(probe)
  data .= reshape(1:length(data), size(data)) ./ length(data)
  set_forcing_rate!(forcing, second_rate, probe, domain)

  first_rate == second_rate ||
    throw(ArgumentError("$(nameof(typeof(forcing))) declares uses_steady_linear_rate = true, but " *
                        "the rate it supplies changes with the field, so it is not steady in time. " *
                        "A state-dependent rate folded into the integrating factor is frozen for " *
                        "the whole step, which costs the scheme its order — a third-order scheme " *
                        "measures 1.0. Supply it through add_forcing_source! instead, where every " *
                        "stage evaluates it, and leave uses_steady_linear_rate at false."))
  return first_rate
end

# Does this forcing define a hook the run cannot call — one written to an earlier, shorter form of it?
# `add_forcing_source!` gained the stage field and the diffusivity, `prepare_forcing!` the forcing's
# evolving state. The arity is the whole question, so the method table is enumerated exactly as the
# rate probe does it, and for the same reason: `which` resolves a call, not a definition.
function _defines_stale_hook(hook, forcing, arguments::Int)
  overrides = false
  callable = false
  for m in methods(hook, Tuple{typeof(forcing), Vararg{Any}})
    signature = Base.unwrap_unionall(m.sig)
    length(signature.parameters) >= 2 || continue
    accepted = signature.parameters[2]
    accepted isa TypeVar && (accepted = accepted.ub)
    accepted === AbstractForcing && continue        # the do-nothing fallback itself
    overrides = true
    # the function type plus the hook's arguments, or a vararg that can absorb them
    (m.isva || length(signature.parameters) >= arguments + 1) && (callable = true)
  end
  # The question is whether a callable method EXISTS, not whether every method is one. Julia
  # auto-generates a short stub for an optional trailing argument, and a strategy may keep an old
  # overload for its own harness; both dispatch correctly on the run-shaped call, and an
  # every-method test locks them out of building a generator at all.
  return overrides && !callable
end


# Does this forcing define its own `set_forcing_rate!`, rather than inheriting the do-nothing
# fallback? The question is about the FORCING argument alone, so it is asked of the method table
# directly. A `which` probe cannot ask it: `which` resolves a call at specific argument types, and
# passing `Any` for the remaining parameters matches nothing when an override annotates them — so an
# override written `set_forcing_rate!(f::MyForcing, rate::AbstractArray, …)` looked identical to no
# override at all, and the misdeclaration this guard exists to catch became a silently unapplied
# forcing. Enumerating the table instead is indifferent to how the other parameters are spelled.
function _overrides_rate_hook(forcing)
  for m in methods(set_forcing_rate!, Tuple{typeof(forcing), Vararg{Any}})
    signature = Base.unwrap_unionall(m.sig)
    length(signature.parameters) >= 2 || continue
    accepted = signature.parameters[2]
    accepted isa TypeVar && (accepted = accepted.ub)
    accepted === AbstractForcing && continue        # the do-nothing fallback itself
    return true
  end
  return false
end


"""
    ResolvedGenerator(domain, conditions; scalar = false)

The flow's generator as one value a scheme can hold. It carries the
[`FlowConditions`](@ref) parameter record together with the assembly scratch its evaluations write
through: the quadratic-product fields, the per-mode forcing-rate arrays, and — when the domain
dealiases by [`PhaseShift`](@ref GBGHomogeneousTurbulence.SimulationDomain.PhaseShift) — the
displaced-evaluation buffers.

That scratch is the **generator's own** storage, distinct from the run's observables cache. The two
do meet at one point: the physical quadratic products are formed *in place over the cache's arrays*,
the negated Lamb vector ``\\boldsymbol{u}\\times\\boldsymbol{\\omega}`` over the vorticity slot and the scalar flux over the
velocity slot, so no product field in physical representation is allocated anywhere.

A time-marching scheme consumes the generator through a fixed protocol: [`prepare!`](@ref) once per
step, [`velocity_rhs!`](@ref) / [`scalar_rhs!`](@ref) at each stage state,
[`velocity_integrating_factor`](@ref) / [`scalar_integrating_factor`](@ref) for the exact linear
subflows, and [`finalize!`](@ref) after the completed step. The scheme does only stage arithmetic, so
it can never assemble the right-hand side from a mismatched intermediate state.

# Arguments
- `domain` — the [`FixedDomain`](@ref) the assembly scratch is sized on.
- `conditions` — the `FlowConditions` the generator resolves: the viscosity, the Schmidt
  number, and the two forcing strategies.
- `scalar = false` — pass `true` when the run carries a passive scalar; it allocates the scalar's
  forcing-rate array, required for a scalar-forced run.

[`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) builds one for
you.

!!! warning "The constructor rejects a misdeclared forcing"
    A forcing that implements
    [`set_forcing_rate!`](@ref GBGHomogeneousTurbulence.Forcing.set_forcing_rate!) without also
    declaring `uses_steady_linear_rate` is given no
    rate array to fill, so its forcing would silently never be applied. Building a
    `ResolvedGenerator` around one throws an `ArgumentError` naming the strategy, rather than letting
    the run proceed quietly wrong.

!!! note "One optimization crosses two verbs"
    Under `PhaseShift`, `velocity_rhs!` leaves the stage's displaced velocity fresh for the same
    stage's `scalar_rhs!` to reuse. Neither verb's signature carries the handoff: the generator
    records which `û` the displaced velocity was taken of, and `scalar_rhs!` reuses the scratch only
    when that record matches its own `û` **and** its caller promises through
    `displaced_velocity_current` that the scratch is still fresh. The record is opportunistic,
    never load-bearing — a
    mismatch only forces a redundant rebuild with the same value: a `scalar_rhs!` handed a different
    `û` than the recorded one rebuilds the displaced velocity itself, value-identically.

# Fields
- `conditions` — the `FlowConditions` parameter record (``\\nu``, ``\\mathrm{Sc}``, the forcings).
- `product_spectral` — the quadratic products' spectral image (the transformed negated Lamb vector
  ``\\boldsymbol{u}\\times\\boldsymbol{\\omega}``, or the transformed scalar flux
  ``\\boldsymbol{u}\\varphi``). In physical representation each product is formed in place over an
  operand's own array — the negated Lamb vector over the vorticity's, the flux over the velocity's —
  so no physical product array exists.
- `phase_shift` — the displaced-evaluation scratch and translation kernels (`PhaseShift` dealiasing
  only), else `nothing`.
- `velocity_rate`, `scalar_rate` — the per-mode linear forcing-rate arrays ``A(\\boldsymbol{\\kappa})``,
  filled once when the generator is built (the rate is steady, so it never changes). The
  integrating-factor verbs return them alongside the viscous coefficient, so the forcing rides the
  exact linear solve instead of being added afterwards. Each is `nothing` unless that field's forcing declares
  [`uses_steady_linear_rate`](@ref GBGHomogeneousTurbulence.Forcing.uses_steady_linear_rate), so a field driven by
  a post-step projection, a stochastic source, or nothing at
  all carries no rate storage; `scalar_rate` is also `nothing` for a scalar-free generator.
- `displaced_velocity_source` — the `û` whose displaced velocity `phase_shift.u_shifted` holds,
  left fresh by `velocity_rhs!` for the same stage's `scalar_rhs!` (`PhaseShift` only). Reuse takes
  two conditions together: this record must match the caller's `û`, **and** the caller must promise
  through `displaced_velocity_current` that the scratch is still fresh. The record alone can only
  force a rebuild.
"""
mutable struct ResolvedGenerator{C<:FlowConditions, PS, PB, RK, SR}
  const conditions::C
  const product_spectral::PS
  const phase_shift::PB
  const velocity_rate::RK
  const scalar_rate::SR
  # PhaseShift: WHICH û the displaced velocity in u_shifted was built from, or `nothing` when the
  # scratch is stale. Identity rather than a bare freshness flag, because the reuse is only valid for
  # the very field the shift was taken of — a flag says "fresh" just as readily about a different
  # stage's velocity, and the mismatch is silent.
  displaced_velocity_source::Any
  # Each forcing's evolving state for the step `prepare!` opened, taken from the run's state so the
  # per-stage source hook can read it: the right-hand-side verbs are handed a stage FIELD, not the
  # record it came from. Refreshed every step beside the scratch above, and `nothing` for a strategy
  # with no state of its own.
  velocity_forcing_state::Any
  scalar_forcing_state::Any
end

function ResolvedGenerator(domain::FixedDomain, conditions::FlowConditions; scalar::Bool = false)
  # `scalar = false` means this generator assembles no scalar right-hand side, so a scalar forcing
  # given alongside it has nowhere to act — it is never prepared, never applied, and never says so.
  # A run built this way integrates a scalar the forcing was supposed to drive and reports nothing
  # wrong, which is the quiet-wrong-answer this constructor already refuses in its sibling case.
  scalar || conditions.scalar_forcing isa NoForcing ||
    throw(ArgumentError("a $(nameof(typeof(conditions.scalar_forcing))) scalar forcing was given, " *
                        "but this generator is built with `scalar = false` and assembles no scalar " *
                        "right-hand side, so the forcing could never be applied. Pass " *
                        "`scalar = true`, or leave `scalar_forcing` at `NoForcing()`."))
  # The source hook gained the stage field and the diffusivity when state-dependent forcings moved
  # onto it, and the prepare hook the forcing's evolving state when that state moved into the run's
  # state. A strategy still written to an old form defines a method the run never calls —
  # dispatch simply falls through to the do-nothing default — so the forcing goes silently
  # unapplied, exactly the failure the rate guard above exists to prevent. Refuse at construction.
  for forcing in (conditions.velocity_forcing, conditions.scalar_forcing)
    _defines_stale_hook(prepare_forcing!, forcing, 5) &&
      throw(ArgumentError("$(nameof(typeof(forcing))) defines prepare_forcing! with fewer than " *
                          "five arguments. The hook is now " *
                          "`prepare_forcing!(forcing, forcing_state, field, domain, dt)` — it is " *
                          "handed the forcing's evolving state, which the run's `ResolvedFields` keeps " *
                          "(see `initial_forcing_state`). A method written to the old form is never " *
                          "called, so the forcing would be silently ignored."))
    _defines_stale_hook(add_forcing_source!, forcing, 6) &&
      throw(ArgumentError("$(nameof(typeof(forcing))) defines add_forcing_source! with fewer than " *
                          "six arguments. The hook is now " *
                          "`add_forcing_source!(forcing, forcing_state, N̂, field, domain, diffusivity)` " *
                          "— it is called at every Runge-Kutta stage and is handed the forcing's " *
                          "evolving state, that stage's own field, and the diffusivity acting on it. " *
                          "A method written to an old form is never called, so the forcing would be " *
                          "silently ignored."))
  end
  return ResolvedGenerator(conditions,
                    new_vector_field_spectral(domain),
                    domain.dealiasing isa PhaseShift ? PhaseShiftBuffers(domain, scalar) : nothing,
                    _forcing_rate(domain, conditions.velocity_forcing),
                    scalar ? _forcing_rate(domain, conditions.scalar_forcing,
                                           new_scalar_field_spectral) : nothing,
                    nothing, nothing, nothing)
end


"""
    prepare!(generator, state, domain, dt)

Open a step of the generator: advance each forcing's evolving state, kept in the run's state, once
(its per-step [`prepare_forcing!`](@ref GBGHomogeneousTurbulence.Forcing.prepare_forcing!) hook). A
scheme calls this once before its Runge–Kutta stages; the stage evaluations then consume what it
prepared. The steady per-mode linear forcing rates are not touched here: they were filled once, when
the generator was built.

The arguments are:
- `generator` — the [`ResolvedGenerator`](@ref) being opened.
- `state` — the start-of-step [`ResolvedFields`](@ref GBGHomogeneousTurbulence.State.ResolvedFields)
  the forcing hooks read, whose forcing states they advance.
- `domain` — the [`FixedDomain`](@ref) the rates are formed on.
- `dt` — the timestep the forcings prepare for.

Returns `generator`.
"""
function prepare!(generator::ResolvedGenerator, state, domain::FixedDomain, dt::Real)
  generator.displaced_velocity_source = nothing     # a new step opens with the displaced scratch stale
  generator.velocity_forcing_state = state.modeled.velocity_forcing
  generator.scalar_forcing_state = state.modeled.scalar_forcing
  conditions = generator.conditions
  prepare_forcing!(conditions.velocity_forcing, state.modeled.velocity_forcing, state.velocity_spectral, domain, dt)
  state.scalar_spectral === nothing ||
    prepare_forcing!(conditions.scalar_forcing, state.modeled.scalar_forcing, state.scalar_spectral, domain, dt)
  return generator
end


"""
    finalize!(generator, state, domain)

Close a step of the generator: apply each of its forcings' post-step projections (the
[`project_forcing!`](@ref GBGHomogeneousTurbulence.Forcing.project_forcing!) hook — e.g. the energy
rescale of a [`VarianceRescaling`](@ref GBGHomogeneousTurbulence.Forcing.VarianceRescaling)) to the
advanced state, velocity first, then the scalar when the run carries one. A scheme calls this once
after its final stage, so everything that follows the step — the diagnostics, the derived
observables, the tracer advance — sees the forced end-of-step fields. The name is this protocol's
step-closing verb, unrelated to `Base.finalize`, Julia's garbage-collection finalizer vocabulary.

The arguments are:
- `generator` — the [`ResolvedGenerator`](@ref) whose forcings project.
- `state` — the advanced [`ResolvedFields`](@ref GBGHomogeneousTurbulence.State.ResolvedFields) the
  projections act on.
- `domain` — the [`FixedDomain`](@ref) they act over.

Returns `state`.
"""
function finalize!(generator::ResolvedGenerator, state, domain::FixedDomain)
  project_forcing!(generator.conditions.velocity_forcing, state.velocity_spectral, domain)
  state.scalar_spectral === nothing || project_forcing!(generator.conditions.scalar_forcing, state.scalar_spectral, domain)
  return state
end





# The κ = 0 (mean) mode of the assembled advective term is removed EXACTLY. The continuous law is
# momentum conservation on a periodic box: ⟨ω×u⟩ = 0, since ω×u is a gradient plus a divergence.
# Discretely it holds only to roundoff, and the mode has no restoring term — the Leray projection
# legitimately keeps constants (ℙ(0) = I) and the integrating factor is exp(0) = 1 there — so the
# residual is integrated undamped and, the flow being chaotic, grows at the Lyapunov rate: measured 3%
# of u′ after 3000 Float32 steps. Every reference DNS pins this mode. The projection sits BETWEEN the
# nonlinear assembly and the forcing source on purpose: the exact law covers the advective term alone,
# so a forcing that deliberately drives a mean remains expressible and honest. An O(1) write, below
# field scale — outside the pass ledgers by the same rule as the tracers' M×3 reads.
"""
    velocity_rhs!(N̂, generator, û, u, ω_consumed, domain)

Assemble the explicit right-hand side of the momentum equation into `N̂` — the dealiased,
Leray-projected rotational nonlinear term plus any additive forcing source. Two arguments are
written, not one: `N̂` receives the result, and `ω_consumed` is consumed in place — the
`_consumed` suffix marks it, since Julia's `!` convention flags only the first.

The arguments are:
- `N̂` — the field in spectral representation receiving the assembled term.
- `generator` — the [`ResolvedGenerator`](@ref) whose conditions and assembly scratch are used.
- `û` — the stage velocity in spectral representation, consulted by `PhaseShift`'s displaced
  evaluation; a mask strategy leaves it unused.
- `u` — the stage velocity in physical representation, only read.
- `ω_consumed` — the stage vorticity in physical representation, consumed (see the note below).
- `domain` — the [`FixedDomain`](@ref) whose dealiasing strategy and transforms assemble the term.

In physical space the rotational form writes the convective term through the Lamb vector
``\\boldsymbol{\\omega}\\times\\boldsymbol{u}``, by the identity

```math
(\\boldsymbol{u}\\cdot\\nabla)\\boldsymbol{u} = \\nabla\\bigl(\\tfrac{1}{2}\\lvert\\boldsymbol{u}\\rvert^{2}\\bigr) + \\boldsymbol{\\omega}\\times\\boldsymbol{u},
```

so that, with the Leray–Helmholtz projection ``\\mathbb{P}`` onto divergence-free fields absorbing the
pressure and the ``\\nabla\\bigl(\\tfrac{1}{2}\\lvert\\boldsymbol{u}\\rvert^{2}\\bigr)`` gradient, the momentum equation
becomes

```math
\\partial_t\\boldsymbol{u} = -\\mathbb{P} (\\boldsymbol{\\omega}\\times\\boldsymbol{u}) + \\nu\\nabla^{2}\\boldsymbol{u} + \\boldsymbol{f}.
```

The term computed is the spectral image of ``-\\mathbb{P} (\\boldsymbol{\\omega}\\times\\boldsymbol{u})``,
dealiased by the domain's [`DealiasingStrategy`](@ref), plus the per-stage additive source of the
generator's velocity forcing (its
[`add_forcing_source!`](@ref GBGHomogeneousTurbulence.Forcing.add_forcing_source!) hook). Its minus
sign costs nothing: the product is formed as the negated Lamb vector
``\\boldsymbol{u}\\times\\boldsymbol{\\omega}``, operands in the order that carries the sign.

A **mask**
strategy ([`TwoThirds`](@ref),
[`HouLi`](@ref)) forms the term once from `u`, `ω` and multiplies by the low-pass `domain.dealias`,
leaving `û` unused; [`PhaseShift`](@ref) forms it **twice** — from `u`, `ω`, and from the fields
recovered on a grid displaced by half a cell (using `û` and the generator's displaced-evaluation
scratch) — averages the two to cancel the aliasing, then truncates spherically with `domain.dealias`.

Two linear pieces are deliberately **not** in `N̂`: the viscous term and the exactly-linear part of a
forcing are advanced exactly by the integrating factor ([`velocity_integrating_factor`](@ref)).

The advective term's ``\\kappa = 0`` mode is zeroed exactly
(``\\langle\\boldsymbol{\\omega}\\times\\boldsymbol{u}\\rangle = 0`` holds discretely only to
roundoff, and the mean mode has no viscous damping); the forcing source, added after, may carry a mean.

Returns `N̂`.

!!! note "The vorticity argument is read and then overwritten"
    The negated Lamb vector is formed in place over the vorticity's array — the backend's cross product may
    write into one of its operands — so `ω_consumed` must hold the vorticity on entry and no longer
    does on return, while `u` is only read. This is what keeps a product field in physical
    representation from existing at all; passing a copy instead would cost a resident ``N^{3}``
    vector, which the package's preference for the smallest working set forbids.

    Which operand is consumed follows the **physics**, not the argument position: the negated Lamb
    vector forms over the vorticity here, and the scalar flux over the velocity in
    [`scalar_rhs!`](@ref) — which is why both name the consumed argument rather than leaving a caller
    to infer it. Only the spectral product scratch remains on the generator, and the operation
    allocates nothing.
"""
velocity_rhs!(N̂, generator::ResolvedGenerator, û, u, ω_consumed, domain::FixedDomain) =
  (_velocity_nonlinear!(domain.dealiasing, N̂, generator, û, u, ω_consumed, domain);
   mean_free_projection!(N̂);
   add_forcing_source!(generator.conditions.velocity_forcing, generator.velocity_forcing_state, N̂, û,
                       domain, generator.conditions.viscosity))

# Mask strategies (TwoThirds / HouLi): one evaluation, the low-pass kernel folded into the
# projection's own pass (the kernel-composed ℙ arity) — one pass fewer than project-then-convolve.
function _velocity_nonlinear!(::DealiasingStrategy, nonlinear, generator, û, u, ω_consumed, domain::FixedDomain)
  _velocity_advective_term!(nonlinear, u, ω_consumed, domain, generator.product_spectral, domain.dealias)
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
  T = field_scalar_type(nonlinear)
  _velocity_advective_term!(nonlinear, u, ω_consumed, domain, product_spectral, domain.dealias)   # primary, truncated
  convolve!(phase_shift.velocity_shifted, û, phase_shift.to_shifted)                                   # û on the displaced grid
  to_physical!(phase_shift.u_shifted, phase_shift.velocity_shifted, domain.transform_plans, product_spectral)
  vorticity_physical!(phase_shift.omega_shifted, phase_shift.velocity_shifted, domain, product_spectral)
  # The displaced assembly consumes ω_shifted only, so u_shifted still holds this stage's displaced
  # velocity — left fresh for the scalar assembly of the SAME stage (the freshness contract that
  # deletes its re-recovery, decision 45).
  generator.displaced_velocity_source = û
  _velocity_advective_term!(phase_shift.velocity_shifted, phase_shift.u_shifted, phase_shift.omega_shifted, domain, product_spectral)
  # Shift-back, two-grid average, and truncation in ONE α/β convolve: ½·(𝔻⊙back)⊙(displaced) +
  # ½·(primary, already truncated) — the composed kernel is built once at construction.
  convolve!(nonlinear, phase_shift.velocity_shifted, phase_shift.back_dealiased, T(1 // 2), T(1 // 2))
  return nonlinear
end

# The pseudospectral −ℙ(ω×u) in spectral representation, taken as ℙ(u×ω): the Lamb vector is ω×u, and
# the operand order below is the whole of the sign — no negation pass. An optional dealias kernel folds
# into the projection's own pass (the kernel-composed arity; `nothing` gives the raw projected term).
# The negated Lamb vector is formed IN PLACE over ω's array: the backend's cross product reads each grid
# point's whole fiber before writing, so the destination may be an operand, and the product needs no
# physical register of its own (ω is dead the instant after the cross — the projection's spectral
# image carries the term from here).
function _velocity_advective_term!(out, u, ω, domain::FixedDomain, product_spectral, kernel = nothing)
  cross!(ω, u, ω)
  to_spectral!(product_spectral, ω, domain.transform_plans)
  kernel === nothing ? helmholtz_projection!(out, product_spectral, domain.multipliers) :
                       helmholtz_projection!(out, product_spectral, domain.multipliers, kernel)
  return out
end


"""
    velocity_integrating_factor(generator, τ)

The velocity's exact linear subflow over a substep ``\\tau`` (`τ`), as the **parameters of its
exponential** rather than a materialized kernel. The `generator` (a [`ResolvedGenerator`](@ref))
supplies the viscosity ``\\nu`` and the linear forcing rate; `τ` is the sub-interval the stage advances.

The linear part of the momentum equation — the diffusion
``\\partial_t\\boldsymbol{u} = \\nu\\nabla^{2}\\boldsymbol{u}``, plus any linear forcing rate
``A(\\boldsymbol{\\kappa})``, filled once when the generator was built — is solved exactly in spectral
representation by the per-mode multiplier

```math
\\mathcal{E}(\\boldsymbol{\\kappa}) = \\exp\\!\\bigl((A(\\boldsymbol{\\kappa}) - \\nu\\lvert\\boldsymbol{\\kappa}\\rvert^{2}) \\tau\\bigr),
```

with ``A = 0`` when no linear forcing is active. Multiplying a field by ``\\mathcal{E}`` advances its
viscous (and linear-forcing) part exactly — machine-exact, with no stability restriction; only a
scheme's explicit stage combination carries truncation error.

Since the multiplier is the exponential of a radial symbol plus the per-mode rate, a scheme
applies it through the backend's fused exponential convolution
([`exponential_convolve!`](@extref GBGPeriodicFields GBGPeriodicFields.Convolution.exponential_convolve!)),
which evaluates it per mode from the wavenumber arrays: nothing is built, stored, or swept for it.
Returns a named tuple `(; coefficient, offset_scale, offset)` — exactly the arguments that
fused exponential takes:
``\\texttt{coefficient} = -\\nu\\tau`` (the factor on ``\\lvert\\boldsymbol{\\kappa}\\rvert^{2}``),
``\\texttt{offset\\_scale} = \\tau``, and ``\\texttt{offset} = A(\\boldsymbol{\\kappa})`` (the
rate field, or `nothing` when no linear forcing is active).
"""
velocity_integrating_factor(generator::ResolvedGenerator, τ::Real) =
  (coefficient = -generator.conditions.viscosity * τ, offset_scale = τ,
   offset = generator.velocity_rate)


"""
    scalar_integrating_factor(generator, τ)

The passive scalar's exact linear subflow over a substep `τ` — the same exponential parameters
[`velocity_integrating_factor`](@ref) returns for `generator`, with the scalar diffusivity
``\\varkappa = \\nu/\\mathrm{Sc}`` in place of
``\\nu`` and the scalar forcing's linear rate in place of the velocity's.
"""
scalar_integrating_factor(generator::ResolvedGenerator, τ::Real) =
  (coefficient = -scalar_diffusivity(generator.conditions) * τ,
   offset_scale = τ,
   offset = generator.scalar_rate)


"""
    scalar_rhs!(N̂, generator, û, φ̂, u_consumed, φ, domain;
                displaced_velocity_current = false)

Assemble the explicit right-hand side of the passive-scalar equation into `N̂` — the dealiased
advection term plus any additive forcing source. Two arguments are written, not one: `N̂` receives
the result, and `u_consumed` is consumed in place — the `_consumed` suffix marks it, since Julia's
`!` convention flags only the first.

The arguments are:
- `N̂` — the field in spectral representation receiving the assembled term.
- `generator` — the [`ResolvedGenerator`](@ref) whose conditions and assembly scratch are used.
- `û`, `φ̂` — the stage velocity and scalar in spectral representation, consulted by `PhaseShift`;
  a mask strategy leaves both unused.
- `u_consumed` — the stage velocity in physical representation, consumed (see the note below).
- `φ` — the stage scalar in physical representation, only read.
- `domain` — the [`FixedDomain`](@ref) whose dealiasing strategy and transforms assemble the term.
- `displaced_velocity_current = false` — the reuse promise for `PhaseShift`'s displaced velocity,
  explained below.

In conservative form the advection is ``-\\nabla\\cdot(\\boldsymbol{u}\\varphi)`` (equal to
``-\\boldsymbol{u}\\cdot\\nabla\\varphi`` since ``\\nabla\\cdot\\boldsymbol{u} = 0``). The conservative
form conserves the scalar mean exactly: the divergence has no ``\\boldsymbol{\\kappa}=\\boldsymbol{0}``
component, and the dealias kernel `domain.dealias` (the sharp ``2/3`` rule by default) leaves that
mode untouched.

The term is computed pseudospectrally as
``- \\operatorname{dealias}\\bigl(\\mathrm{i}\\boldsymbol{\\kappa}\\cdot\\widehat{\\boldsymbol{u}\\varphi}\\bigr)``,
plus the per-stage additive source of the generator's scalar forcing (its
[`add_forcing_source!`](@ref GBGHomogeneousTurbulence.Forcing.add_forcing_source!) hook).

The dealiasing strategy controls the aliasing of the quadratic product. A **mask** strategy
([`TwoThirds`](@ref), [`HouLi`](@ref)) forms the flux once from `u_consumed`, `φ`, leaving `û` and
`φ̂` unused. [`PhaseShift`](@ref) instead averages it with the flux recovered on a grid displaced
half a cell — using `φ̂` and the generator's displaced-evaluation scratch, and reading the displaced
velocity the same stage's [`velocity_rhs!`](@ref) left fresh there (a bare `scalar_rhs!` with no
preceding velocity evaluation rebuilds it from `û` instead) — before the spherical truncation.

The diffusion ``\\varkappa\\nabla^{2}\\varphi`` and the exactly-linear part of a forcing are **not** in
`N̂`: they are advanced exactly by [`scalar_integrating_factor`](@ref).

Pass `displaced_velocity_current = true` only if nothing has changed since this generator's
`velocity_rhs!` was called on the same `û` — a time-stepping scheme knows this because it evaluates
both right-hand sides at one stage before updating either field; a hand-written caller generally
does not. Reuse needs **both** the keyword and the generator's recorded source matching `û`. The
record alone can only force a rebuild, never a wrong reuse; the keyword is the load-bearing half —
containers are rewritten in place, so a false promise over the *same* container is quietly wrong,
where the default merely rebuilds (one shift, three inverse transforms) and stays correct.

The advective term's ``\\kappa = 0`` mode is zero exactly by construction, under every dealiasing
strategy: the divergence multiplier ``\\mathrm{i}\\boldsymbol{\\kappa}`` vanishes identically at
``\\boldsymbol{\\kappa} = \\boldsymbol{0}``, so no further step removes it. That exactness matters,
since the mean of ``\\varphi`` has no diffusive damping. The forcing source, added after, may carry
a mean.

Returns `N̂`.

!!! note "The assembly consumes the velocity argument"
    The flux ``\\boldsymbol{u}\\varphi`` is formed in place over the velocity's array (a pointwise
    product may write into an operand), so on return `u_consumed` no longer holds the velocity; `φ`
    is only read. As in `velocity_rhs!`, the consumed argument is fixed by the physics rather than
    by its position in the signature, and is named for it. Only the spectral product scratch remains
    on the generator, and the operation allocates nothing.
"""
scalar_rhs!(N̂, generator::ResolvedGenerator, û, φ̂, u_consumed, φ, domain::FixedDomain;
            displaced_velocity_current::Bool = false) =
  (_scalar_nonlinear!(domain.dealiasing, N̂, generator, û, φ̂, u_consumed, φ, domain,
                      displaced_velocity_current);
   add_forcing_source!(generator.conditions.scalar_forcing, generator.scalar_forcing_state, N̂, φ̂, domain,
                       scalar_diffusivity(generator.conditions)))

# Mask strategies: one flux evaluation, then the divergence with the low-pass kernel AND the −∇·
# sign folded into its own pass (the kernel-composed arity, α = −1) — one pass fewer.
function _scalar_nonlinear!(::DealiasingStrategy, nonlinear, generator, û, φ̂, u_consumed, φ, domain::FixedDomain,
                            displaced_velocity_current::Bool = false)
  _scalar_flux_divergence!(nonlinear, u_consumed, φ, domain, generator.product_spectral, domain.dealias, -1)
  return nonlinear
end

# Phase-shift: average the primary and half-cell-displaced flux divergences (cancels the odd-parity
# aliases); the spherical truncation and the −∇· sign fold into the passes — the primary carries
# both inside its divergence, the displaced term picks the truncation up through the composed
# shift-back∘truncation kernel and the sign through the averaging α — so no whole-field truncation
# pass remains.
function _scalar_nonlinear!(::PhaseShift, nonlinear, generator, û, φ̂, u_consumed, φ, domain::FixedDomain,
                            displaced_velocity_current::Bool = false)
  phase_shift = generator.phase_shift
  # The generator's `scalar` keyword gates the displaced-scalar scratch as well as the forcing-rate
  # array, so a generator built without it has nowhere to recover φ̂ on the displaced grid. Reaching
  # that here surfaced as a `MethodError` from inside the field library, naming a dependency's
  # internals rather than the keyword the caller set.
  phase_shift.scalar_shifted === nothing &&
    throw(ArgumentError("this generator was built with `scalar = false`, so it carries no " *
                        "displaced-scalar scratch and cannot assemble a scalar right-hand side " *
                        "under `PhaseShift` dealiasing. Rebuild it with `scalar = true`."))
  product_spectral = generator.product_spectral
  T = field_scalar_type(nonlinear)
  _scalar_flux_divergence!(nonlinear, u_consumed, φ, domain, product_spectral, domain.dealias, -1)   # primary −𝔻∇·(uφ)
  # The same stage's velocity assembly left the displaced velocity fresh in u_shifted (its displaced
  # assembly consumes only ω_shifted), so the re-recovery — one shift convolve and three inverse
  # transforms — exists only on the fallback path a hand-run bare `scalar_rhs!` takes (decision 45).
  # The reuse needs BOTH: the caller's assurance that no field has changed since `velocity_rhs!`
  # (only a scheme evaluating both right-hand sides at one stage can give it), and a matching `û`.
  # Identity alone is not enough — these containers are written in place, so the same object holds a
  # different stage's velocity a moment later and `===` cannot tell the two apart. Defaulting to the
  # rebuild makes a hand-run pairing correct rather than quietly wrong.
  if !(displaced_velocity_current && generator.displaced_velocity_source === û)
    convolve!(phase_shift.velocity_shifted, û, phase_shift.to_shifted)                                   # û on the displaced grid
    to_physical!(phase_shift.u_shifted, phase_shift.velocity_shifted, domain.transform_plans, product_spectral)
  end
  generator.displaced_velocity_source = nothing     # the flux below consumes u_shifted
  convolve!(phase_shift.scalar_shifted, φ̂, phase_shift.to_shifted)                                       # φ̂ on the displaced grid
  to_physical!(phase_shift.phi_shifted, phase_shift.scalar_shifted, domain.transform_plans, phase_shift.scalar_copy)
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
  if kernel === nothing
    # No kernel to fold `α` into, so it is applied here. Dropping it — as this branch did — silently
    # returned +∇·(uφ) to a caller who asked for the −∇· the scalar equation needs.
    divergence!(out, product_spectral, domain.multipliers)
    isone(α) || multiply!(out, α, out)
  else
    divergence!(out, product_spectral, domain.multipliers, kernel, α, 0)
  end
  return out
end

# The flux uφ (a vector), transformed to spectral into `flux_spectral`. The flux is formed IN PLACE
# over u's array (the pointwise multiply writes each grid point from its own operands, so the
# destination may be an operand): u is dead the instant after the multiply, and the flux needs no
# physical register of its own.
function _scalar_flux!(flux_spectral, u, φ, domain::FixedDomain)
  multiply!(u, φ, u)
  to_spectral!(flux_spectral, u, domain.transform_plans)
  return flux_spectral
end


# ————————————————————————————————————————————————————————————————————————————————————————————————
# Display (the convention is stated once, at `SimulationDomain`'s display section). The conditions
# print their two numbers and nest each forcing's own display; the generator prints its conditions,
# its assembly scratch through the field library's `show` (the grid and storage it was built on),
# and the two things a caller is refused on — whether it carries the displaced-grid scratch of
# `PhaseShift` and whether that scratch extends to a scalar. The rate slots exist only under a
# `Linear` forcing (`uses_steady_linear_rate`), so their absence is a fact of the conditions, not of
# the moment. An optional part prints through its own display when present and as `no …` when not.

Base.show(io::IO, conditions::FlowConditions) =
  print(io, "FlowConditions(viscosity ", conditions.viscosity, ", schmidt ", conditions.schmidt,
        ", velocity_forcing ", conditions.velocity_forcing, ", scalar_forcing ", conditions.scalar_forcing, ")")

function Base.show(io::IO, buffers::PhaseShiftBuffers)
  print(io, "PhaseShiftBuffers(", buffers.velocity_shifted)
  isnothing(buffers.scalar_shifted) ? print(io, ", no scalar") :
    print(io, ", scalar_shifted ", buffers.scalar_shifted)
  print(io, ")")
end

_show_optional(io::IO, name, value, absent) =
  isnothing(value) ? print(io, ", no ", absent) : print(io, ", ", name, " ", value)

function Base.show(io::IO, generator::ResolvedGenerator)
  print(io, "ResolvedGenerator(", generator.conditions, ", product_spectral ", generator.product_spectral)
  _show_optional(io, "phase_shift", generator.phase_shift, "phase-shift scratch")
  _show_optional(io, "velocity_rate", generator.velocity_rate, "velocity-rate slot")
  _show_optional(io, "scalar_rate", generator.scalar_rate, "scalar-rate slot")
  print(io, ")")
end


end # module Generator
