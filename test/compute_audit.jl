# Compute audit — the compute-cost twin of the memory audit (ARCHITECTURE decision 34): the same
# straight-line op lists (test/audit_ops.jl), projected onto the two compute currencies of a
# pseudospectral step on a GPU:
#
#  1. THE TRANSFORM LEDGER — scalar-equivalent FFT counts (c2r, r2c) per step, frozen per
#     scheme × dealiasing × scalar cell with the chart recomputes amortized in (each chart is
#     recovered once per fields epoch, wherever first read — the step's stage 1, a pre-step tracer
#     read, an observable). Transforms carry essentially all the flops: one scalar transform is
#     ≈ (5/2)·N³·log₂(N³) flops (the standard real-FFT estimate), some 10²–10³ flops per grid point,
#     while every pointwise kernel does O(1–20) flops per point — far below the ~2·10² flops per
#     element a current GPU can afford per memory access (the roofline machine balance). So the flop
#     budget IS the transform count times FFTW's constant, and the number the audit freezes is the
#     count; flops are derived, never an independent invariant.
#
#  2. THE PASS LEDGER — full-field memory passes per shape class for everything between the
#     transforms. Pointwise kernels are bandwidth-bound (the roofline argument above), so what
#     fusion buys is PASSES, not flops: composing kernel-per-op sweeps the fields once per op, a
#     fused kernel once per operand. The FUSION BOUND is the liveness argument transplanted to
#     traffic: within each between-barriers segment (fusion cannot cross a transform or a
#     reduction), a perfectly fused kernel reads each live-in value once, writes each live-out value
#     once, reads each field-scale configuration array once — a pure intermediate (written and
#     consumed inside the segment, dead after) costs nothing. Achieved − bound per class carries a
#     NAMED HOLDER (a PF kernel-granularity boundary, the factor materialization raised to
#     GBGPeriodicFields); an unclaimed gap fails the suite.
#
# Both ledgers are STATIC projections of the op lists; their dynamic anchor is indirect but real —
# the same op lists feed the memory audit's liveness bounds, whose resident ledger and @allocated
# guards fail on structural drift, and decision 33's obligation (re-derive the op lists on any step!
# or protocol change) covers both audits. Kernel-launch counts and achieved bandwidth on the GPU
# hosts are benchmark-side empirics, deliberately outside the suite (decision 33's scope statement).
#
# Regenerating the frozen tables after a deliberate schedule change:
#   AUDIT_PRINT=1 julia --project=. test/compute_audit.jl
# prints every computed cell (and the derived flop estimates); review the diff against the frozen
# tables, then freeze the new values in the same commit, citing the decision.

using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data
using Test

include("audit_ops.jl")     # the op model AND its cost model — shared with the optimality audit



# ---------------------------------------------------------------- the frozen transform ledger

# Scalar-equivalent transforms per step, chart recomputes amortized in. The structure behind the
# cells (asserted below): transforms are strictly per-evaluation — a mask evaluation costs (6, 3)
# for the velocity (u and ω recovered, six component fields, one c2r each; the Lamb product back,
# three r2c) plus (1, 3) for the scalar (φ recovered; the flux vector back); PhaseShift doubles the
# velocity ((12, 6): the displaced recovery and product have no cheaper route than their own
# transforms) and adds (4, 3) for the scalar as implemented — (1, 3) for the displaced flux and
# recovery, plus the 3 c2r re-recovery of the displaced velocity the bound table charges as a gap.
const TRANSFORMS_BASE = Dict(
  (:RK3, :TwoThirds,  false) => (c2r = 18, r2c = 9),
  (:RK3, :TwoThirds,  true)  => (c2r = 21, r2c = 18),
  (:RK3, :HouLi,      false) => (c2r = 18, r2c = 9),
  (:RK3, :HouLi,      true)  => (c2r = 21, r2c = 18),
  (:RK3, :PhaseShift, false) => (c2r = 36, r2c = 18),
  (:RK3, :PhaseShift, true)  => (c2r = 51, r2c = 36),
  (:RK2, :TwoThirds,  false) => (c2r = 12, r2c = 6),
  (:RK2, :TwoThirds,  true)  => (c2r = 14, r2c = 12),
  (:RK2, :HouLi,      false) => (c2r = 12, r2c = 6),
  (:RK2, :HouLi,      true)  => (c2r = 14, r2c = 12),
  (:RK2, :PhaseShift, false) => (c2r = 24, r2c = 12),
  (:RK2, :PhaseShift, true)  => (c2r = 34, r2c = 24),
)

# The per-evaluation transform cost of each right-hand-side family (the derivation above).
_per_eval(dealiasing, scalar) = begin
  velocity = dealiasing === :PhaseShift ? (c2r = 12, r2c = 6) : (c2r = 6, r2c = 3)
  scalar || return velocity
  φ = dealiasing === :PhaseShift ? (c2r = 5, r2c = 6) : (c2r = 1, r2c = 3)
  (c2r = velocity.c2r + φ.c2r, r2c = velocity.r2c + φ.r2c)
end

# The transform LOWER BOUND for the algorithms as chosen (rotational form, conservative flux,
# every right-hand side evaluated at the stage state, shift-averaged PhaseShift): each physical
# component field an evaluation consumes costs one c2r (there is no cheaper route to a displaced or
# underived physical field than its own inverse transform), each spectral product component one r2c.
# Every mask cell and the PhaseShift velocity sit AT the bound. The one gap: under PhaseShift with a
# scalar, scalar_rhs! re-shifts and re-recovers the displaced velocity that velocity_rhs! left
# fresh in the generator's `u_shifted` at the same stage state (3 c2r per evaluation) — reusing it
# needs a same-stage freshness contract on the displaced scratch across the two protocol verbs, a
# recorded candidate, not an oversight.
const TRANSFORM_BOUND = Dict(
  key => (key[2] === :PhaseShift && key[3]) ?
         (c2r = base.c2r - 3 * _evals(key[1]), r2c = base.r2c) : base
  for (key, base) in TRANSFORMS_BASE
)

const TRANSFORM_GAP_HOLDERS = Dict(
  (:RK3, :PhaseShift, true) => "SHIFTED-VELOCITY REUSE (scalar_rhs! re-recovers the displaced velocity, 3 c2r × 3 stages)",
  (:RK2, :PhaseShift, true) => "SHIFTED-VELOCITY REUSE (scalar_rhs! re-recovers the displaced velocity, 3 c2r × 2 stages)",
)


# ---------------------------------------------------------------- the frozen pass ledger

# Full-field passes per shape class and step (reads + writes + configuration reads), transforms
# excluded. Traffic in N³-real units ≈ 3·(SV + PV) + 1·(SS + PS) + ½·R at leading order in 1/N.
# PhaseShift cells re-frozen 2026-07-19: the shift-back now rides the averaging convolve as one
# α/β pass in both displaced chains (the PF-triage free win; for the scalar the shift-back symbol
# commutes through the divergence contraction) — 2 spectral-vector passes fewer per evaluation.
# RK2 cells re-frozen 2026-07-28 (decision 35): every use of a field's integrating factor over an
# IFRK2 step is at the one substep Δt, so each factor is now built once and all of its consumers run
# in that visit — 1 spectral-scalar write and 1 rate read fewer per field per step (verified
# bit-identical). This is the schedule-level half of the redundancy; the value-level half (at
# Sc = 1 with both rates unarmed the two factors are the same field) stays a named floor holder.
const PASSES_BASE = Dict(
  (:RK3, :TwoThirds,  false) => (spectral_vector = 51, physical_vector = 9, spectral_scalar = 11, physical_scalar = 0, rate = 3),
  (:RK3, :TwoThirds,  true)  => (spectral_vector = 54, physical_vector = 15, spectral_scalar = 64, physical_scalar = 3, rate = 6),
  (:RK3, :HouLi,      false) => (spectral_vector = 51, physical_vector = 9, spectral_scalar = 11, physical_scalar = 0, rate = 3),
  (:RK3, :HouLi,      true)  => (spectral_vector = 54, physical_vector = 15, spectral_scalar = 64, physical_scalar = 3, rate = 6),
  (:RK3, :PhaseShift, false) => (spectral_vector = 84, physical_vector = 18, spectral_scalar = 17, physical_scalar = 0, rate = 3),
  (:RK3, :PhaseShift, true)  => (spectral_vector = 102, physical_vector = 30, spectral_scalar = 103, physical_scalar = 6, rate = 6),
  (:RK2, :TwoThirds,  false) => (spectral_vector = 31, physical_vector = 6, spectral_scalar = 6, physical_scalar = 0, rate = 1),
  (:RK2, :TwoThirds,  true)  => (spectral_vector = 33, physical_vector = 10, spectral_scalar = 37, physical_scalar = 2, rate = 2),
  (:RK2, :HouLi,      false) => (spectral_vector = 31, physical_vector = 6, spectral_scalar = 6, physical_scalar = 0, rate = 1),
  (:RK2, :HouLi,      true)  => (spectral_vector = 33, physical_vector = 10, spectral_scalar = 37, physical_scalar = 2, rate = 2),
  (:RK2, :PhaseShift, false) => (spectral_vector = 53, physical_vector = 12, spectral_scalar = 10, physical_scalar = 0, rate = 1),
  (:RK2, :PhaseShift, true)  => (spectral_vector = 65, physical_vector = 20, spectral_scalar = 63, physical_scalar = 4, rate = 2),
)

# Named holders for the fusion gaps, by shape class (the causes are configuration-independent).
# The physical-side and configuration classes sit AT their bounds in every cell — the cross
# products, fluxes, copies, and per-segment kernel reads are already ideal. Every gap lives in the
# two spectral classes, and every one is a PF-kernel-granularity artifact of the numpy model — the
# schedule is already minimal in VALUES (the liveness audit); the passes above the fused ideal are
# re-reads and re-writes between the op-per-kernel boundaries:
#   spectral_vector / spectral_scalar — UNFUSED STAGE PIPELINE: Leray → dealias → accumulate →
#     update → factor-rotate run as one kernel per op where one fused per-mode kernel could read
#     (product, state) and write (state, accumulator) once; and FACTOR MATERIALIZATION — the
#     integrating factor is built into a register and re-read per application where a fused
#     exponential-multiply computes it in-register (the open GBGPeriodicFields request; its passes
#     are pure-intermediate traffic the bound prices at zero).
const FUSION_GAP_HOLDERS = Dict(
  :spectral_vector => "UNFUSED STAGE PIPELINE + FACTOR MATERIALIZATION (PF kernel granularity)",
  :spectral_scalar => "UNFUSED STAGE PIPELINE + FACTOR MATERIALIZATION (PF kernel granularity)",
)

# A VALUE-level residual the schedule model above cannot see, recorded rather than exploited. The
# two integrating factors coincide as fields, ℰ_ν(τ) ≡ ℰ_κ(τ), exactly when the diffusivities agree
# AND both linear forcing rates are unarmed — that is, Sc = 1 with no rate-armed forcing on either
# field, since an armed rate A(κ) enters the exponent and the velocity's and scalar's differ in
# general. So the second build per stage is redundant only on that configuration, and the sound
# O(1) guard is the conjunction, never `Sc == 1` alone: a bare Schmidt test would silently hand the
# scalar the velocity's forcing rate — a physics error no Sc = 1 unforced test could catch.
#
# It is left unexploited by choice. Non-unit Sc is a fully supported configuration, not a fallback,
# and the guard would make the hot loop's schedule depend on a runtime value — one code path fast,
# the other not, and the op model above forced to fork. The saving is one pointwise exponential
# kernel per field per stage, no transform. The general form of the fix (a stamped factor register:
# rebuild only when the full argument tuple (D, τ, rate epoch, armed) changes, the DerivedFields
# epoch pattern) subsumes this case safely and is the route to take if the residual is ever paid
# for; a Schmidt special case is not.
const FACTOR_VALUE_HOLDER =
  "COINCIDENT INTEGRATING FACTORS at Sc = 1 with both rates unarmed — one pointwise exponential per " *
  "field per stage; unexploited (a value-dependent hot-loop branch; see the stamped-register route)"


# ---------------------------------------------------------------- the frozen deltas

# Only the OU forcing transforms — its noise pipeline is the single forcing hook that moves a field
# between representations (src/Forcing.jl prepare_forcing!); every other forcing works through
# reductions, per-mode multiplies, and the integrating-factor rate.
_forcing_transform_delta(tag, slot) =
  tag === :ou ? (slot === :velocity ? (c2r = 0, r2c = 3) : (c2r = 0, r2c = 1)) :
                (c2r = 0, r2c = 0)

# Pass deltas per forcing hook, derived from src/Forcing.jl (the OU-velocity column is
# cross-checked against its op list below; the rest are frozen by derivation):
#   band  — apply_forcing!: weighted_inner(field, band) [field + band] + the in-band rescale
#           convolve [field r/w + band].
#   linear — set_forcing_rate!: rate .= A·mask [mask + rate], then the armed factor build reads the
#           rate once per build.
#   power — set_forcing_rate!: weighted_inner(field, band) + rate .= a·mask + per-build rate reads.
#   ou    — prepare_forcing!: draw + band-limit + project + normalize + state fold (8 slot-shaped
#           passes + 1 kernel read + the physical noise write; the unit-variance rescale folds into
#           the state combination's coefficient), then the per-stage additive source read/accumulate
#           (3 passes × evaluations).
function _forcing_pass_delta(tag, slot, scheme)
  tag === :none && return ZERO
  if tag === :band
    return slot === :velocity ? _ex(spectral_vector = 3, spectral_scalar = 2) :
                                _ex(spectral_scalar = 5)
  elseif tag === :linear
    return _ex(rate = 2 + _builds(scheme))
  elseif tag === :power
    return slot === :velocity ? _ex(spectral_vector = 1, spectral_scalar = 1, rate = 2 + _builds(scheme)) :
                                _ex(spectral_scalar = 2, rate = 2 + _builds(scheme))
  end
  return slot === :velocity ?
    _ex(spectral_vector = 8 + 3 * _evals(scheme), physical_vector = 1, spectral_scalar = 1) :
    _ex(spectral_scalar = 8 + 3 * _evals(scheme), physical_scalar = 1, rate = 0)
end

# Tracers add NO transforms: the Heun endpoints ride the fields-epoch chart cache (the pre-step read
# reuses the previous post-step recompute, and the post-step recompute serves the next step's stage
# 1) — the epoch design's compute dividend. Since 2026-07-28 they add no field-scale PASSES either:
# the start-of-step velocity is interpolated onto the tracers before the step rather than copied out
# of the chart, so all the tracer push touches is O(M) interpolation work, below field scale. Both
# deltas are at the floor an M-point Lagrangian instrument can reach — it must read the velocity
# somewhere, and it now reads only the M points it needs.
const TRACER_TRANSFORM_DELTA = (c2r = 0, r2c = 0)
const TRACER_PASS_DELTA = ZERO


# ---------------------------------------------------------------- regeneration aid

if get(ENV, "AUDIT_PRINT", "") == "1"
  println("— computed compute-ledger cells (review, then freeze) —")
  for scheme in (:RK3, :RK2), dealiasing in DEALIASINGS, scalar in (false, true)
    ops = _ops(scheme, dealiasing, scalar)
    t = _transforms(ops)
    println((scheme, dealiasing, scalar))
    println("  transforms   = ", t)
    println("  passes       = ", _passes(ops))
    println("  fusion bound = ", _fusion_bound(ops))
    # the derived flop estimate: (5/2)·N³·log₂(N³) per scalar transform, N = 256
    N = 256
    println("  flops/step at N = 256 ≈ ", round((t.c2r + t.r2c) * 2.5 * N^3 * log2(N^3) / 1e9; digits = 1), " Gflop (transform term)")
  end
  ou = _ops(:RK3, :TwoThirds, false; ou = true)
  base = _ops(:RK3, :TwoThirds, false)
  println("OU velocity delta: transforms = ",
          (c2r = _transforms(ou).c2r - _transforms(base).c2r, r2c = _transforms(ou).r2c - _transforms(base).r2c),
          "  passes = ", NamedTuple{CLASSES}(Tuple(getproperty(_passes(ou), c) - getproperty(_passes(base), c) for c in CLASSES)))
end


# ---------------------------------------------------------------- the tests

@testset "compute audit" begin
  @testset "every op is priced" begin
    all_ops = vcat((_ops(scheme, dealiasing, scalar; ou)
                    for scheme in (:RK3, :RK2), dealiasing in DEALIASINGS, scalar in (false, true),
                        ou in (false, true) if !(ou && scheme === :RK2))...)
    @test all(op -> haskey(OP_COST, op.name), all_ops)
    @test all(op -> all(v -> haskey(VALUE_CLASS, v), Iterators.flatten((op.reads, op.writes))), all_ops)
  end

  @testset "transform ledger — the frozen base, charts amortized in" begin
    for (key, expected) in TRANSFORMS_BASE
      @test _transforms(_ops(key...)) == expected
    end
  end

  @testset "transforms are per-evaluation × evaluations" begin
    for (scheme, dealiasing, scalar) in keys(TRANSFORMS_BASE)
      per = _per_eval(dealiasing, scalar)
      @test TRANSFORMS_BASE[(scheme, dealiasing, scalar)] ==
            (c2r = per.c2r * _evals(scheme), r2c = per.r2c * _evals(scheme))
    end
    # PhaseShift's price for exact quadratic dealiasing at √2·N/3 modes: exactly double the mask
    # velocity transforms — the displaced evaluation is a full second pipeline.
    for scheme in (:RK3, :RK2)
      mask = TRANSFORMS_BASE[(scheme, :TwoThirds, false)]
      @test TRANSFORMS_BASE[(scheme, :PhaseShift, false)] == (c2r = 2mask.c2r, r2c = 2mask.r2c)
    end
  end

  @testset "transform minimality — bounds and the gap register" begin
    for (key, actual) in TRANSFORMS_BASE
      bound = TRANSFORM_BOUND[key]
      @test bound.c2r <= actual.c2r && bound.r2c <= actual.r2c
      @test (actual == bound) == !haskey(TRANSFORM_GAP_HOLDERS, key)   # every gap has a named holder
    end
  end

  @testset "pass ledger — the frozen base" begin
    for (key, expected) in PASSES_BASE
      @test _passes(_ops(key...)) == expected
    end
  end

  @testset "fusion bounds and the gap register" begin
    for key in keys(PASSES_BASE)
      ops = _ops(key...)
      bound = _fusion_bound(ops)
      achieved = _passes(ops)
      for class in CLASSES
        b = getproperty(bound, class)
        a = getproperty(achieved, class)
        @test b <= a                              # a bound above the ledger is a bookkeeping error
        if a - b > 0
          @test haskey(FUSION_GAP_HOLDERS, class) # every gap carries a named holder (decision 34)
        end
      end
    end
  end

  @testset "forcing deltas — the OU op-list cross-check" begin
    with = _ops(:RK3, :TwoThirds, false; ou = true)
    without = _ops(:RK3, :TwoThirds, false)
    @test (c2r = _transforms(with).c2r - _transforms(without).c2r,
           r2c = _transforms(with).r2c - _transforms(without).r2c) ==
          _forcing_transform_delta(:ou, :velocity)
    @test NamedTuple{CLASSES}(Tuple(getproperty(_passes(with), c) - getproperty(_passes(without), c)
                                    for c in CLASSES)) ==
          _forcing_pass_delta(:ou, :velocity, :RK3)
    for tag in (:none, :band, :linear, :power), slot in (:velocity, :scalar)
      @test _forcing_transform_delta(tag, slot) == (c2r = 0, r2c = 0)
    end
  end

  @testset "tracers ride the chart cache — zero transform delta" begin
    # Frozen intent: an advance! that bypassed the epoch cache for the Heun endpoints would have to
    # flip these constants consciously — 3 c2r per step for a re-recovered chart, 2 physical-vector
    # passes for a retained endpoint field.
    @test TRACER_TRANSFORM_DELTA == (c2r = 0, r2c = 0)
    @test TRACER_PASS_DELTA == ZERO
  end

  @testset "op lists name real displaced registers" begin
    PB = GBGIsotropicTurbulence.Generator.PhaseShiftBuffers
    @test all(f -> f in fieldnames(PB),
              (:to_shifted, :back, :velocity_shifted, :u_shifted, :omega_shifted,
               :scalar_shifted, :scalar_copy, :phi_shifted))
  end

  @testset "the coincident-factor holder names the exact condition" begin
    # Pins FACTOR_VALUE_HOLDER's premise: the two integrating factors coincide as fields under
    # Sc = 1 AND both rates unarmed, and NOT under either relaxation. The third case is the one
    # that matters — it is why the unexploited residual may never be guarded on `Sc == 1` alone.
    domain = FixedDomain(8, 2π; dealiasing = TwoThirds(), element_type = Float64, array_type = Array)
    ℰ_u, ℰ_φ = scalar_spectral(domain), scalar_spectral(domain)
    factors(sc, force) = begin
      conditions = FlowConditions(; viscosity = 0.1, schmidt = sc, scalar_forcing = NoForcing(),
                                  velocity_forcing = force)
      generator = ResolvedGenerator(domain, conditions; scalar = true)
      prepare!(generator, ResolvedFields(domain; scalar = true), domain, 0.01)
      velocity_factor!(ℰ_u, generator, domain, 0.01)
      scalar_factor!(ℰ_φ, generator, domain, 0.01)
      (field_data(ℰ_u), field_data(ℰ_φ), generator)
    end

    a, b, gen = factors(1.0, NoForcing())                         # Sc = 1, no armed rate
    @test !gen.velocity_rate_active && !gen.scalar_rate_active
    @test a == b                                                  # coincide — the recorded residual

    a, b, _ = factors(0.7, NoForcing())                           # Sc ≠ 1 — the supported case
    @test a != b

    a, b, gen = factors(1.0, Linear(domain; rate = 0.5))   # Sc = 1, velocity rate ARMED
    @test gen.velocity_rate_active && !gen.scalar_rate_active
    @test a != b            # a bare `Sc == 1` guard here would apply the velocity's rate to φ
  end
end
