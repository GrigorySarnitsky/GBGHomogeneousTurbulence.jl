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

using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data
using Test

include("audit_ops.jl")     # the op model AND its cost model — shared with the optimality audit



# ---------------------------------------------------------------- the frozen transform ledger

# Scalar-equivalent transforms per step, chart recomputes amortized in. The structure behind the
# cells (asserted below): transforms are strictly per-evaluation — a mask evaluation costs (6, 3)
# for the velocity (u and ω recovered, six component fields, one c2r each; the Lamb product back,
# three r2c) plus (1, 3) for the scalar (φ recovered; the flux vector back); PhaseShift doubles the
# velocity ((12, 6): the displaced recovery and product have no cheaper route than their own
# transforms) and exactly doubles the scalar too ((2, 6): the displaced φ recovery and flux — the
# displaced velocity is the same stage's, left fresh by velocity_rhs! under decision 45's
# freshness contract, so no re-recovery exists).
const TRANSFORMS_BASE = Dict(
  (:RK3, :TwoThirds,  false) => (c2r = 18, r2c = 9),
  # IFLowStorageRK4 (decision 85): 5/3 of :RK3's stage-scaled transforms — the same iteration
  # carried to five stages; the closing deposit's share is unchanged. AUDIT_PRINT-generated.
  (:RK4, :TwoThirds,  false) => (c2r = 30, r2c = 15),
  (:RK4, :TwoThirds,  true)  => (c2r = 35, r2c = 30),
  (:RK4, :HouLi,      false) => (c2r = 30, r2c = 15),
  (:RK4, :HouLi,      true)  => (c2r = 35, r2c = 30),
  (:RK4, :PhaseShift, false) => (c2r = 60, r2c = 30),
  (:RK4, :PhaseShift, true)  => (c2r = 70, r2c = 60),
  (:RK3, :TwoThirds,  true)  => (c2r = 21, r2c = 18),
  (:RK3, :HouLi,      false) => (c2r = 18, r2c = 9),
  (:RK3, :HouLi,      true)  => (c2r = 21, r2c = 18),
  (:RK3, :PhaseShift, false) => (c2r = 36, r2c = 18),
  (:RK3, :PhaseShift, true)  => (c2r = 42, r2c = 36),
  # IFSSPRK3 (decision 80): transform cells IDENTICAL to :RK3 — same three stages, same recovery
  # and assembly schedule; the tableau changes the pointwise combinations alone.
  (:SSPRK3, :TwoThirds,  false) => (c2r = 18, r2c = 9),
  (:SSPRK3, :TwoThirds,  true)  => (c2r = 21, r2c = 18),
  (:SSPRK3, :HouLi,      false) => (c2r = 18, r2c = 9),
  (:SSPRK3, :HouLi,      true)  => (c2r = 21, r2c = 18),
  (:SSPRK3, :PhaseShift, false) => (c2r = 36, r2c = 18),
  (:SSPRK3, :PhaseShift, true)  => (c2r = 42, r2c = 36),
  (:RK2, :TwoThirds,  false) => (c2r = 12, r2c = 6),
  (:RK2, :TwoThirds,  true)  => (c2r = 14, r2c = 12),
  (:RK2, :HouLi,      false) => (c2r = 12, r2c = 6),
  (:RK2, :HouLi,      true)  => (c2r = 14, r2c = 12),
  (:RK2, :PhaseShift, false) => (c2r = 24, r2c = 12),
  (:RK2, :PhaseShift, true)  => (c2r = 28, r2c = 24),
)

# The per-evaluation transform cost of each right-hand-side family (the derivation above).
_per_eval(dealiasing, scalar) = begin
  velocity = dealiasing === :PhaseShift ? (c2r = 12, r2c = 6) : (c2r = 6, r2c = 3)
  scalar || return velocity
  φ = dealiasing === :PhaseShift ? (c2r = 2, r2c = 6) : (c2r = 1, r2c = 3)
  (c2r = velocity.c2r + φ.c2r, r2c = velocity.r2c + φ.r2c)
end

# The transform LOWER BOUND for the algorithms as chosen (rotational form, conservative flux,
# every right-hand side evaluated at the stage state, shift-averaged PhaseShift): each physical
# component field an evaluation consumes costs one c2r (there is no cheaper route to a displaced or
# underived physical field than its own inverse transform), each spectral product component one r2c.
# EVERY cell sits AT the bound since decision 45 closed the last gap: the SHIFTED-VELOCITY REUSE
# holder — scalar_rhs! re-recovering the displaced velocity velocity_rhs! left fresh at the same
# stage (3 c2r per evaluation) — retired when the same-stage freshness contract landed on the
# displaced scratch, and PhaseShift now costs exactly double its mask cell for the velocity and the
# scalar alike (the memory↔compute trade priced clean on both sides).
const TRANSFORM_BOUND = Dict(key => base for (key, base) in TRANSFORMS_BASE)

# (SHIFTED-VELOCITY REUSE retired 2026-08-06, decision 45 — the register empty is the assertion.)
const TRANSFORM_GAP_HOLDERS = Dict{Tuple{Symbol, Symbol, Bool}, String}()


# ---------------------------------------------------------------- the frozen pass ledger

# Full-field passes per shape class and step (reads + writes), transforms excluded. Traffic in
# N³-real units ≈ 3·(SV + PV) + 1·(SS + PS) + ½·R at leading order in 1/N.
# ALL cells re-frozen 2026-08-06 at the PF adoption (decision 39): the stage update fuses with its
# integrating-factor rotation into one exponential pass evaluated per mode (no factor built, stored,
# or read — the register and its builds are gone); every dealias/truncation pass folds into the
# kernel-composed projection/divergence or the composed shift-back kernel; and every kernel a base
# op applies is a compressed symbol, so no op reads a field-scale configuration array. A
# velocity-only step now moves NOTHING scalar-shaped at all — the zero columns are the assertion.
# Re-frozen 2026-08-06 (decision 40, the deposit-driven cache): the op lists now model the full
# ITERATION (step! + the closing deposit!), so the once-per-iteration maximum-speed reduction — always
# performed, previously the run layer's un-audited pass — enters the ledger as +1 physical_vector in
# every cell. Transforms froze IDENTICAL: the closing deposits are the former first-stage recoveries
# relocated, never added.
const PASSES_BASE = Dict(
  # Re-frozen 2026-08-23 (+2 spectral_vector everywhere): decision 61's state re-projection — one
  # in-place pointwise pass per step pinning the advanced state's divergence at roundoff.
  (:RK3, :TwoThirds,  false) => (spectral_vector = 41, physical_vector = 10, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  # IFLowStorageRK4 (decision 85): the RK3 pass structure at five stages. AUDIT_PRINT-generated.
  (:RK4, :TwoThirds,  false) => (spectral_vector = 69, physical_vector = 16, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK4, :TwoThirds,  true)  => (spectral_vector = 74, physical_vector = 26, spectral_scalar = 52, physical_scalar = 5, real_spectral_scalar = 0),
  (:RK4, :HouLi,      false) => (spectral_vector = 69, physical_vector = 16, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK4, :HouLi,      true)  => (spectral_vector = 74, physical_vector = 26, spectral_scalar = 52, physical_scalar = 5, real_spectral_scalar = 0),
  (:RK4, :PhaseShift, false) => (spectral_vector = 124, physical_vector = 31, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK4, :PhaseShift, true)  => (spectral_vector = 134, physical_vector = 51, spectral_scalar = 92, physical_scalar = 10, real_spectral_scalar = 0),
  (:RK3, :TwoThirds,  true)  => (spectral_vector = 44, physical_vector = 16, spectral_scalar = 30, physical_scalar = 3, real_spectral_scalar = 0),
  (:RK3, :HouLi,      false) => (spectral_vector = 41, physical_vector = 10, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK3, :HouLi,      true)  => (spectral_vector = 44, physical_vector = 16, spectral_scalar = 30, physical_scalar = 3, real_spectral_scalar = 0),
  (:RK3, :PhaseShift, false) => (spectral_vector = 74, physical_vector = 19, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK3, :PhaseShift, true)  => (spectral_vector = 80, physical_vector = 31, spectral_scalar = 54, physical_scalar = 6, real_spectral_scalar = 0),
  # IFSSPRK3 (decision 80): two spectral passes FEWER than :RK3 per field (41→39, 30→28 scalar
  # spectral) — stage 2 pays three passes where RK3's fused update pays one, but no accumulator is
  # ever rotated, and the rotations cost more than the extra combinations. AUDIT_PRINT-generated,
  # reviewed against the step! body.
  (:SSPRK3, :TwoThirds,  false) => (spectral_vector = 39, physical_vector = 10, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:SSPRK3, :TwoThirds,  true)  => (spectral_vector = 42, physical_vector = 16, spectral_scalar = 28, physical_scalar = 3, real_spectral_scalar = 0),
  (:SSPRK3, :HouLi,      false) => (spectral_vector = 39, physical_vector = 10, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:SSPRK3, :HouLi,      true)  => (spectral_vector = 42, physical_vector = 16, spectral_scalar = 28, physical_scalar = 3, real_spectral_scalar = 0),
  (:SSPRK3, :PhaseShift, false) => (spectral_vector = 72, physical_vector = 19, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:SSPRK3, :PhaseShift, true)  => (spectral_vector = 78, physical_vector = 31, spectral_scalar = 52, physical_scalar = 6, real_spectral_scalar = 0),
  (:RK2, :TwoThirds,  false) => (spectral_vector = 27, physical_vector = 7, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK2, :TwoThirds,  true)  => (spectral_vector = 29, physical_vector = 11, spectral_scalar = 19, physical_scalar = 2, real_spectral_scalar = 0),
  (:RK2, :HouLi,      false) => (spectral_vector = 27, physical_vector = 7, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK2, :HouLi,      true)  => (spectral_vector = 29, physical_vector = 11, spectral_scalar = 19, physical_scalar = 2, real_spectral_scalar = 0),
  (:RK2, :PhaseShift, false) => (spectral_vector = 49, physical_vector = 13, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK2, :PhaseShift, true)  => (spectral_vector = 53, physical_vector = 21, spectral_scalar = 35, physical_scalar = 4, real_spectral_scalar = 0),
)

# Named holders for the fusion gaps, by shape class (the causes are configuration-independent).
# The physical-side and configuration classes sit AT their bounds in every cell — the cross
# products, fluxes, copies, and per-segment kernel reads are already ideal. Every gap lives in the
# two spectral classes, and every one is a PF-kernel-granularity artifact of the numpy model — the
# schedule is already minimal in VALUES (the liveness audit); the passes above the fused ideal are
# re-reads and re-writes between the op-per-kernel boundaries:
#   spectral_vector / spectral_scalar — UNFUSED STAGE PIPELINE: projection⊙dealias → accumulate →
#     fused-exponential update still run as one kernel per op where one fused per-mode kernel could
#     read (product, state) and write (state, accumulator) once. FACTOR MATERIALIZATION is RETIRED
#     (decision 39): the fused exponential computes the factor in register, exactly what the holder
#     asked of the backend — the pre-registered round-3 candidate (the two-output stage kernel) is
#     what remains of this class.
const FUSION_GAP_HOLDERS = Dict(
  :spectral_vector => "UNFUSED STAGE PIPELINE (PF kernel granularity)",
  :spectral_scalar => "UNFUSED STAGE PIPELINE (PF kernel granularity)",
)

# The COINCIDENT-FACTORS residual (Sc = 1, both rates unarmed ⇒ ℰ_ν ≡ ℰ_κ) is RETIRED with the
# factor itself (decision 39): no factor field is built for the coincidence to save — each fused
# exponential evaluates its own parameters in register, and two coincident parameter tuples cost
# nothing extra to "build twice". The retired holder's guard lesson stays worth its line: any future
# value-level dedup must key on the FULL argument tuple (D, τ, rate epoch, armed), never Sc alone.


# ---------------------------------------------------------------- the frozen deltas

# No forcing transforms. The last that did was the dense OU, whose noise pipeline moved a field of
# noise to spectral representation every step (three transforms for the velocity); the band-sparse
# form of decision 90 draws its process on the band's modes directly. Every forcing works through
# reductions, per-mode multiplies, the integrating-factor rate, or a band-sized write.
_forcing_transform_delta(tag, slot) = (c2r = 0, r2c = 0)

# Pass deltas per forcing hook, derived from src/Forcing.jl (the OU-velocity column is
# cross-checked against its op list below; the rest are frozen by derivation). Every band kernel is
# a lazy radial symbol since the PF adoption, so no hook reads a stored kernel; an ARMED rate is a
# spectral-scalar field the fused exponential reads once per application (_applies below).
#   band  — project_forcing!: weighted_inner(field, band) [field read] + the in-band rescale
#           convolve [field r/w].
#   linear — set_forcing_rate!: rate .= A·mask [mask (real) read + rate (spectral scalar) write],
#           then the armed exponential reads the rate once per application.
#   power — add_forcing_source!, at EVERY right-hand-side evaluation (the amplitude tracks the band
#           observable, so it cannot be armed once per step): weighted_inner(field, band)
#           [1 field read; the band kernel is lazy, so no configuration array is read] + the
#           accumulating convolve! [N̂ read, field read, N̂ write = 3] = 4 slot-shaped passes per
#           evaluation. No rate array and no materialized indicator: both went with the rate route.
#   controller — the same shape: since the multi-weight fused reduction (PF decision 72, wired
#           2026-08-23), its three weighted sums — whole-field variance, band variance, |κ|²
#           dissipation — share ONE traversal, weighted_inner(field, (1, band, |κ|²))
#           [1 field read, all three kernels lazy] + the accumulating convolve! [3] = 4 slot-shaped
#           passes per evaluation, the same count as `power`.
#   ou    — nothing at field scale (decision 90): the process is advanced on the host over the band's
#           M conjugate mode pairs, and the per-stage source is an O(M) indexed write, below this
#           ledger's resolution. The dense form paid 8 slot-shaped passes and a physical write per
#           step plus 3 passes per evaluation.
function _forcing_pass_delta(tag, slot, scheme)
  tag === :none && return ZERO
  if tag === :band
    return slot === :velocity ? _ex(spectral_vector = 3) : _ex(spectral_scalar = 3)
  elseif tag === :linear
    return _ex(spectral_scalar = 1 + _applies(scheme), real_spectral_scalar = 1)
  elseif tag === :power
    return slot === :velocity ? _ex(spectral_vector = 4 * _evals(scheme)) :
                                _ex(spectral_scalar = 4 * _evals(scheme))
  elseif tag === :controller
    return slot === :velocity ? _ex(spectral_vector = 4 * _evals(scheme)) :
                                _ex(spectral_scalar = 4 * _evals(scheme))
  elseif tag === :ou
    return ZERO
  end
  error("unmodelled forcing tag $tag — price it here in the same commit that adds it")
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
  for scheme in (:RK3, :RK4, :SSPRK3, :RK2), dealiasing in DEALIASINGS, scalar in (false, true)
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
                    for scheme in (:RK3, :RK4, :SSPRK3, :RK2), dealiasing in DEALIASINGS, scalar in (false, true),
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
    for scheme in (:RK3, :RK4, :SSPRK3, :RK2)
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
    for tag in (:none, :band, :linear, :power, :controller, :ou), slot in (:velocity, :scalar)
      @test _forcing_transform_delta(tag, slot) == (c2r = 0, r2c = 0)
    end
    # Every tag must be MODELLED: an unlisted tag throws rather than falling through to a catch-all,
    # the drift an earlier round found in the `:power` cell, silently priced as a stochastic forcing.
    @test_throws ErrorException _forcing_pass_delta(:unlisted, :velocity, :RK3)
  end

  @testset "tracers ride the chart cache — zero transform delta" begin
    # Frozen intent: an advance! that bypassed the epoch cache for the Heun endpoints would have to
    # flip these constants consciously — 3 c2r per step for a re-recovered chart, 2 physical-vector
    # passes for a retained endpoint field.
    @test TRACER_TRANSFORM_DELTA == (c2r = 0, r2c = 0)
    @test TRACER_PASS_DELTA == ZERO
  end

  @testset "op lists name real displaced registers" begin
    PB = GBGHomogeneousTurbulence.Generator.PhaseShiftBuffers
    @test all(f -> f in fieldnames(PB),
              (:to_shifted, :back, :back_dealiased, :velocity_shifted, :u_shifted, :omega_shifted,
               :scalar_shifted, :scalar_copy, :phi_shifted))
    # `u_shifted` remains a register the displaced evaluation needs today. The backend's cross
    # product is now alias-safe by construction (its former guard is retired), so landing displaced
    # values on spent registers is no longer blocked — that reuse is scheduled with the cache's
    # slot-register merges (the closing-refresh design), not as a drive-by here.
  end

  @testset "the factor verbs supply parameters, never a field (decision 39)" begin
    # The protocol's factor half is now a parameter supplier: it returns the exponential's
    # (coefficient, offset_scale, offset) and touches no storage. The armed-rate branch is the one
    # behavioral fork, so it is pinned here: unarmed gives `offset === nothing`; an armed velocity
    # rate reaches ONLY the velocity's parameters (the guard lesson of the retired coincident-factor
    # holder — a bare `Sc == 1` dedup would have handed the velocity's rate to φ).
    domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π, dealiasing = TwoThirds(), element_type = Float64, array_type = Array)
    factors(sc, force) = begin
      conditions = FlowConditions(; viscosity = 0.1, schmidt = sc, scalar_forcing = NoForcing(),
                                  velocity_forcing = force)
      generator = ResolvedGenerator(domain, conditions; scalar = true)
      prepare!(generator, ResolvedFields(domain; scalar = true), domain, 0.01)
      (velocity_integrating_factor(generator, 0.01), scalar_integrating_factor(generator, 0.01), generator)
    end

    fu, fφ, gen = factors(1.0, NoForcing())                       # Sc = 1, no armed rate
    @test gen.velocity_rate === nothing && gen.scalar_rate === nothing
    @test fu.offset === nothing && fφ.offset === nothing
    @test fu.coefficient == fφ.coefficient                        # Sc = 1 ⇒ equal parameters

    fu, fφ, _ = factors(0.7, NoForcing())                         # Sc ≠ 1 — the supported case
    @test fu.coefficient != fφ.coefficient

    fu, fφ, gen = factors(1.0, Linear(domain; rate = 0.5))        # Sc = 1, velocity rate ARMED
    @test gen.velocity_rate !== nothing && gen.scalar_rate === nothing
    @test fu.offset !== nothing && fφ.offset === nothing          # the rate reaches only its field
  end
end
