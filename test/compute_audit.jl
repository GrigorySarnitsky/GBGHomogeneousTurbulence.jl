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
using Test

include("audit_ops.jl")


# ---------------------------------------------------------------- the op cost model

# One cost entry per op NAME: its kind (:transform / :reduction / :pointwise / :noop), its
# scalar-equivalent transform counts, and the field-scale configuration arrays it reads beyond its
# symbolic operands (`extra`, by shape class): the dealias kernel and the translation kernels are
# complex scalar-shaped fields (spectral_scalar), |κ|² and the forcing-rate arrays are real
# spectral-shaped (rate). O(N) configuration (the axis multipliers, shell vectors) is ignored, as in
# the memory ledger. A transform's own input/output traffic lives inside the transform count — the
# FFT's internal passes are FFTW's, not this schedule's.
_ex(; kw...) = merge(ZERO, NamedTuple(kw))
_cost(kind; c2r = 0, r2c = 0, extra = ZERO) = (kind = kind, c2r = c2r, r2c = r2c, extra = extra)

const OP_COST = Dict(
  # transforms — the FFT currency
  "flux→spectral"      => _cost(:transform; r2c = 3),
  "noise→spectral"     => _cost(:transform; r2c = 3),
  "u recovery"         => _cost(:transform; c2r = 3),
  "ω recovery"         => _cost(:transform; c2r = 3),
  "u chart recovery"   => _cost(:transform; c2r = 3),
  "ω chart recovery"   => _cost(:transform; c2r = 3),
  "shifted u recovery" => _cost(:transform; c2r = 3),
  "shifted ω recovery" => _cost(:transform; c2r = 3),
  "φ recovery"         => _cost(:transform; c2r = 1),
  "shifted φ recovery" => _cost(:transform; c2r = 1),
  # reductions — a fusion barrier like a transform (the scalar result gates the next kernel), but
  # the read passes are real and irreducible
  "normalize"          => _cost(:reduction),
  # pointwise ops with a field-scale configuration read
  "dealias"            => _cost(:pointwise; extra = _ex(spectral_scalar = 1)),
  "shift û"            => _cost(:pointwise; extra = _ex(spectral_scalar = 1)),
  "shift φ̂"           => _cost(:pointwise; extra = _ex(spectral_scalar = 1)),
  "shift back"         => _cost(:pointwise; extra = _ex(spectral_scalar = 1)),
  "band-limit"         => _cost(:pointwise; extra = _ex(spectral_scalar = 1)),
  "build E_ν"          => _cost(:pointwise; extra = _ex(rate = 1)),
  "build E_κ"          => _cost(:pointwise; extra = _ex(rate = 1)),
  # the unforced finalize is a no-op (the forcing deltas price the real hooks)
  "finalize"           => _cost(:noop),
)
# Plain pointwise ops — passes are their symbolic reads and writes alone. ("project noise" prices
# the aliased-projection CONTRACT; that the aliased path allocates today is the episode ledger's
# recorded defect, raised to GBGPeriodicFields.)
for name in ("copy û", "copy φ̂", "shifted copy", "shifted copy φ̂", "curl û", "shifted curl",
             "cross u×ω", "Leray projection", "divergence", "flux uφ", "average grids",
             "seed hu", "seed hφ", "accumulate hu", "accumulate hφ", "û += B·hu", "φ̂ += B·hφ",
             "rotate û", "rotate hu", "rotate φ̂", "rotate hφ", "rotate û*", "rotate φ̂*",
             "rotate N̂_u,1", "rotate N̂_φ,1", "û* predictor", "φ̂* predictor",
             "û corrector 1", "û corrector 2", "φ̂ corrector 1", "φ̂ corrector 2",
             "draw noise", "project noise", "rescale ξ", "f̂ ← θf̂ + sξ", "add OU source")
  OP_COST[name] = _cost(:pointwise)
end

_op_cost(op) = get(OP_COST, op.name) do
  error("unpriced op \"$(op.name)\" — a new or renamed op needs an OP_COST entry in the same commit")
end


function _transforms(ops)
  c2r = 0
  r2c = 0
  for op in ops
    cost = _op_cost(op)
    c2r += cost.c2r
    r2c += cost.r2c
  end
  return (c2r = c2r, r2c = r2c)
end

function _passes(ops)
  acc = Dict(class => 0 for class in CLASSES)
  for op in ops
    cost = _op_cost(op)
    (cost.kind === :transform || cost.kind === :noop) && continue
    for v in Iterators.flatten((op.reads, op.writes))
      acc[VALUE_CLASS[v]] += 1
    end
    for class in CLASSES
      acc[class] += getproperty(cost.extra, class)
    end
  end
  return NamedTuple{CLASSES}(Tuple(acc[class] for class in CLASSES))
end

# The fused ideal per between-barriers segment: live-in values read once, live-out values written
# once, each distinct configuration array read once; pure intermediates cost nothing. A reduction
# contributes its (irreducible) read passes and breaks the segment.
function _fusion_bound(ops)
  barrier(op) = (kind = _op_cost(op).kind; kind === :transform || kind === :reduction)
  acc = Dict(class => 0 for class in CLASSES)
  n = length(ops)
  i = 1
  while i <= n
    if barrier(ops[i])
      if _op_cost(ops[i]).kind === :reduction
        for v in ops[i].reads
          acc[VALUE_CLASS[v]] += 1
        end
      end
      i += 1
      continue
    end
    j = i
    while j < n && !barrier(ops[j + 1])
      j += 1
    end
    live_in = Set{Symbol}()
    written = Set{Symbol}()
    extras = Dict{String, NamedTuple}()
    for k in i:j
      op = ops[k]
      cost = _op_cost(op)
      cost.kind === :noop && continue
      for v in op.reads
        v in written || push!(live_in, v)
      end
      for v in op.writes
        push!(written, v)
      end
      cost.extra === ZERO || (extras[op.name] = cost.extra)
    end
    for v in live_in
      acc[VALUE_CLASS[v]] += 1
    end
    for v in written
      if v in CONTRACT_LIVE || any(k -> v in ops[k].reads, (j + 1):n)
        acc[VALUE_CLASS[v]] += 1
      end
    end
    for extra in values(extras), class in CLASSES
      acc[class] += getproperty(extra, class)
    end
    i = j + 1
  end
  return NamedTuple{CLASSES}(Tuple(acc[class] for class in CLASSES))
end


const DEALIASINGS = (:TwoThirds, :HouLi, :PhaseShift)

_ops(scheme, dealiasing, scalar; ou = false) =
  scheme === :RK3 ?
    rk3_ops(scalar; ou, phase_shift = dealiasing === :PhaseShift, charts = true) :
    rk2_ops(scalar; phase_shift = dealiasing === :PhaseShift, charts = true)

_evals(scheme)  = scheme === :RK3 ? 3 : 2     # right-hand-side evaluations per step
_builds(scheme) = scheme === :RK3 ? 3 : 2     # integrating-factor builds per field per step


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
const PASSES_BASE = Dict(
  (:RK3, :TwoThirds,  false) => (spectral_vector = 51, physical_vector = 9, spectral_scalar = 11, physical_scalar = 0, rate = 3),
  (:RK3, :TwoThirds,  true)  => (spectral_vector = 54, physical_vector = 15, spectral_scalar = 64, physical_scalar = 3, rate = 6),
  (:RK3, :HouLi,      false) => (spectral_vector = 51, physical_vector = 9, spectral_scalar = 11, physical_scalar = 0, rate = 3),
  (:RK3, :HouLi,      true)  => (spectral_vector = 54, physical_vector = 15, spectral_scalar = 64, physical_scalar = 3, rate = 6),
  (:RK3, :PhaseShift, false) => (spectral_vector = 90, physical_vector = 18, spectral_scalar = 17, physical_scalar = 0, rate = 3),
  (:RK3, :PhaseShift, true)  => (spectral_vector = 114, physical_vector = 30, spectral_scalar = 103, physical_scalar = 6, rate = 6),
  (:RK2, :TwoThirds,  false) => (spectral_vector = 31, physical_vector = 6, spectral_scalar = 7, physical_scalar = 0, rate = 2),
  (:RK2, :TwoThirds,  true)  => (spectral_vector = 33, physical_vector = 10, spectral_scalar = 39, physical_scalar = 2, rate = 4),
  (:RK2, :HouLi,      false) => (spectral_vector = 31, physical_vector = 6, spectral_scalar = 7, physical_scalar = 0, rate = 2),
  (:RK2, :HouLi,      true)  => (spectral_vector = 33, physical_vector = 10, spectral_scalar = 39, physical_scalar = 2, rate = 4),
  (:RK2, :PhaseShift, false) => (spectral_vector = 57, physical_vector = 12, spectral_scalar = 11, physical_scalar = 0, rate = 2),
  (:RK2, :PhaseShift, true)  => (spectral_vector = 73, physical_vector = 20, spectral_scalar = 65, physical_scalar = 4, rate = 4),
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
#   ou    — prepare_forcing!: draw + band-limit + project + normalize + rescale + state fold
#           (10 slot-shaped passes + 1 kernel read + the physical noise write), then the per-stage
#           additive source read/accumulate (3 passes × evaluations).
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
    _ex(spectral_vector = 10 + 3 * _evals(scheme), physical_vector = 1, spectral_scalar = 1) :
    _ex(spectral_scalar = 10 + 3 * _evals(scheme), physical_scalar = 1, rate = 0)
end

# Tracers add NO transforms: the Heun endpoints ride the fields-epoch chart cache
# (src/SimulationRun.jl advance!: the pre-step read reuses the previous post-step recompute, and the
# post-step recompute serves the next step's stage 1) — the epoch design's compute dividend. What
# they do add per step is the endpoint copy (one physical-vector read + write) and O(M) interpolation
# work, below field scale.
const TRACER_TRANSFORM_DELTA = (c2r = 0, r2c = 0)
const TRACER_PASS_DELTA = _ex(physical_vector = 2)


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
    # flip this constant consciously (and pay 3 c2r per step).
    @test TRACER_TRANSFORM_DELTA == (c2r = 0, r2c = 0)
    @test TRACER_PASS_DELTA == _ex(physical_vector = 2)
  end

  @testset "op lists name real displaced registers" begin
    PB = GBGIsotropicTurbulence.Generator.PhaseShiftBuffers
    @test all(f -> f in fieldnames(PB),
              (:to_shifted, :back, :velocity_shifted, :u_shifted, :omega_shifted,
               :scalar_shifted, :scalar_copy, :phi_shifted))
  end
end
