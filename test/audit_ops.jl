# Audit op model — the step as a straight-line program, the single source of truth two audits project
# (ARCHITECTURE decisions 33 and 34):
#
#   * test/memory_audit.jl  — the LIVENESS projection: the peak number of simultaneously live values
#     per shape class, the lower bound on the resident registers the operation order needs.
#   * test/compute_audit.jl — the COST projection: the per-step transform counts and memory-pass
#     counts (the frozen compute ledger, its minimality bounds, and the fusion gap register).
#   * test/optimality_audit.jl — the FLOOR projection (decision 35): the synchronization ledger and
#     the cross-axis holder register, which needs the same cost model the compute audit projects.
#
# The cost model at the foot of this file (OP_COST and the transform / pass / fusion-bound
# projections) lives here rather than in one audit because two now share it.
#
# Every op is transcribed from the step! bodies and the generator protocol (src/Propagator.jl,
# src/Generator.jl, the src/State.jl recoveries, the src/Forcing.jl hooks) — re-derive on any change
# there; a frozen table failing is the reminder. Ops act on SYMBOLIC values (VALUE_CLASS types them);
# an op's NAME keys its cost entry (compute_audit.jl's OP_COST), so a renamed or added op must get a
# cost entry in the same commit.
#
# Both audits share the file by `include` into their own wrapper modules, so each stays runnable on
# its own (`julia --project=. test/<audit>.jl`).

const CLASSES = (:spectral_vector, :physical_vector, :spectral_scalar, :physical_scalar, :rate)

const ZERO = NamedTuple{CLASSES}((0, 0, 0, 0, 0))
_add(a, b) = NamedTuple{CLASSES}(Tuple(getproperty(a, c) + getproperty(b, c) for c in CLASSES))


# One primitive field operation of a step: what it reads, what it writes.
struct Op
  name::String
  reads::Vector{Symbol}
  writes::Vector{Symbol}
end

const VALUE_CLASS = Dict(
  :û => :spectral_vector, :scratch => :spectral_vector, :ps => :spectral_vector,
  :hu => :spectral_vector, :nl => :spectral_vector, :stage2 => :spectral_vector,
  :ustar_spec => :spectral_vector, :ou_state => :spectral_vector, :noise_s => :spectral_vector,
  :vshift => :spectral_vector,
  :chart_u => :physical_vector, :chart_ω => :physical_vector, :pp => :physical_vector,
  :ustar => :physical_vector, :ωstar => :physical_vector, :noise_p => :physical_vector,
  :ushift => :physical_vector, :ωshift => :physical_vector,
  :φ̂ => :spectral_scalar, :fac => :spectral_scalar, :sb_copy => :spectral_scalar,
  :sb_nl => :spectral_scalar, :sb_h => :spectral_scalar, :sb_stage2 => :spectral_scalar,
  :φstar_spec => :spectral_scalar, :sshift => :spectral_scalar, :scopy => :spectral_scalar,
  :sb_field => :physical_scalar, :pshift => :physical_scalar,
)
const CONTRACT_LIVE = Set([:û, :φ̂, :chart_u, :chart_ω, :ou_state])


# The start-of-step chart recomputes (physical_velocity / physical_vorticity in src/State.jl): each
# chart is recovered once per fields epoch — i.e. once per advance! cycle, wherever first read (the
# step's stage 1, a pre-step tracer read, an observable) — and served from the cache after that. The
# liveness projection leaves them off (the charts are contract-live inputs there); the cost
# projection turns them on, so a per-step ledger prices the recoveries exactly once.
_chart_recomputes() = [
  Op("copy û",           [:û],          [:scratch]),
  Op("u chart recovery", [:scratch],    [:chart_u]),
  Op("curl û",           [:û],          [:scratch]),
  Op("ω chart recovery", [:scratch],    [:chart_ω]),
]


# The velocity right-hand side at a stage (velocity_rhs! in src/Generator.jl), reading the physical
# (u, ω) named by the caller and writing the dealiased, Leray-projected term into `out`. A mask
# strategy (TwoThirds / HouLi) evaluates once and low-passes; PhaseShift also reads the stage's
# SPECTRAL velocity `uspec` for the half-cell-displaced evaluation through the generator's
# PhaseShiftBuffers registers, averages the two grids (the shift-back riding the averaging convolve
# as one fused α/β pass — the PF-triage free win, 2026-07-19), and truncates spherically. `source`
# appends the additive-forcing read (the OU's per-stage add_forcing_source!).
function _velocity_assembly(uspec, u, ω, out; source = false, phase_shift = false)
  ops = [
    Op("cross u×ω",        [u, ω],        [:pp]),
    Op("flux→spectral",    [:pp],         [:ps]),
    Op("Leray projection", [:ps],         [out]),
  ]
  if phase_shift
    append!(ops, [
      Op("shift û",            [uspec],            [:vshift]),
      Op("shifted copy",       [:vshift],          [:ps]),
      Op("shifted u recovery", [:ps],              [:ushift]),
      Op("shifted curl",       [:vshift],          [:ps]),
      Op("shifted ω recovery", [:ps],              [:ωshift]),
      Op("cross u×ω",          [:ushift, :ωshift], [:pp]),
      Op("flux→spectral",      [:pp],              [:ps]),
      Op("Leray projection",   [:ps],              [:vshift]),
      Op("shift-back average", [out, :vshift],     [out]),
    ])
  end
  push!(ops, Op("dealias", [out], [out]))
  source && push!(ops, Op("add OU source", [out, :ou_state], [out]))
  return ops
end


# The scalar right-hand side at a stage (scalar_rhs! in src/Generator.jl): recover φ at the stage
# state, form the conservative flux uφ, transform, take the divergence into `out`, and dealias.
# PhaseShift adds the displaced flux divergence — note it RE-recovers the displaced velocity from
# `uspec` even though velocity_rhs! left it fresh in the same stage (the recorded transform gap of
# the compute audit's bound table).
function _scalar_assembly(uspec, φspec, u, out; phase_shift = false)
  ops = [
    Op("copy φ̂",       [φspec],        [:sb_copy]),
    Op("φ recovery",    [:sb_copy],     [:sb_field]),
    Op("flux uφ",       [u, :sb_field], [:pp]),
    Op("flux→spectral", [:pp],          [:ps]),
    Op("divergence",    [:ps],          [out]),
  ]
  if phase_shift
    append!(ops, [
      Op("shift û",            [uspec],          [:vshift]),
      Op("shifted copy",       [:vshift],        [:ps]),
      Op("shifted u recovery", [:ps],            [:ushift]),
      Op("shift φ̂",           [φspec],          [:sshift]),
      Op("shifted copy φ̂",    [:sshift],        [:scopy]),
      Op("shifted φ recovery", [:scopy],         [:pshift]),
      Op("flux uφ",            [:ushift, :pshift], [:pp]),
      Op("flux→spectral",      [:pp],            [:ps]),
      Op("divergence",         [:ps],            [:sshift]),
      Op("shift-back average", [out, :sshift],   [out]),
    ])
  end
  push!(ops, Op("dealias", [out], [out]))
  return ops
end


# The substage recoveries (velocity_to_physical! / vorticity_to_physical! in src/State.jl) from the
# spectral stage state `src` — û itself for the in-place IFLowStorageRK3 stages, the spectral
# predictor for IFRK2's stage 2. The plain recovery copies first (the in-place inverse transform
# consumes its spectral source); the curl fuses that copy into its derivative multiply.
_recoveries(src) = [
  Op("copy û",       [src],       [:scratch]),
  Op("u recovery",   [:scratch],  [:ustar]),
  Op("curl û",       [src],       [:scratch]),
  Op("ω recovery",   [:scratch],  [:ωstar]),
]


# The IFLowStorageRK3 stage update, faithful to step!: stage 1 SEEDS the accumulator (`multiply!`,
# no read of the dead register), later stages accumulate; the accumulator's own rotation is skipped
# at the last stage (`i < 3 &&` — it is dead after).
function _velocity_update(rhs; first = false, last = false)
  ops = [first ? Op("seed hu", [rhs], [:hu]) : Op("accumulate hu", [rhs, :hu], [:hu])]
  append!(ops, [
    Op("û += B·hu",      [:û, :hu],     [:û]),
    Op("build E_ν",      Symbol[],      [:fac]),
    Op("rotate û",       [:û, :fac],    [:û]),
  ])
  last || push!(ops, Op("rotate hu", [:hu, :fac], [:hu]))
  return ops
end
function _scalar_update(; first = false, last = false)
  ops = [first ? Op("seed hφ", [:sb_nl], [:sb_h]) : Op("accumulate hφ", [:sb_nl, :sb_h], [:sb_h])]
  append!(ops, [
    Op("φ̂ += B·hφ",     [:φ̂, :sb_h],  [:φ̂]),
    Op("build E_κ",      Symbol[],      [:fac]),
    Op("rotate φ̂",      [:φ̂, :fac],   [:φ̂]),
  ])
  last || push!(ops, Op("rotate hφ", [:sb_h, :fac], [:sb_h]))
  return ops
end

# The OU forcing's prepare! phase (velocity slot, src/Forcing.jl): generate, transform, band-limit,
# project, normalize, and fold the increment into the contract-live forcing state f̂. The
# unit-variance rescale of ξ is NOT a pass: its only consumer is the fold, so 1/√⟨ξ,ξ⟩ rides in as
# part of that combination's coefficient (2026-07-28, decision 35).
_ou_prepare() = [
  Op("draw noise",       Symbol[],           [:noise_p]),
  Op("noise→spectral",   [:noise_p],         [:noise_s]),
  Op("band-limit",       [:noise_s],         [:noise_s]),
  Op("project noise",    [:noise_s],         [:noise_s]),
  Op("normalize",        [:noise_s],         Symbol[]),
  Op("f̂ ← θf̂ + sξ",    [:ou_state, :noise_s], [:ou_state]),
]


# IFLowStorageRK3: stage 1 reads the charts; stages 2–3 recover into the substage registers.
# `charts` prepends the once-per-epoch chart recomputes (the cost projection); `phase_shift`
# switches the assemblies to the displaced-evaluation form; `ou` adds the forcing's prepare phase
# and per-stage source.
function rk3_ops(scalar::Bool; ou::Bool = false, phase_shift::Bool = false, charts::Bool = false)
  ops = Op[]
  charts && append!(ops, _chart_recomputes())
  ou && append!(ops, _ou_prepare())
  append!(ops, _velocity_assembly(:û, :chart_u, :chart_ω, :nl; source = ou, phase_shift))
  scalar && append!(ops, _scalar_assembly(:û, :φ̂, :chart_u, :sb_nl; phase_shift))
  append!(ops, _velocity_update(:nl; first = true))
  scalar && append!(ops, _scalar_update(; first = true))
  for i in 2:3
    append!(ops, _recoveries(:û))
    append!(ops, _velocity_assembly(:û, :ustar, :ωstar, :nl; source = ou, phase_shift))
    scalar && append!(ops, _scalar_assembly(:û, :φ̂, :ustar, :sb_nl; phase_shift))
    append!(ops, _velocity_update(:nl; last = i == 3))
    scalar && append!(ops, _scalar_update(; last = i == 3))
  end
  push!(ops, Op("finalize", [:û], [:û]))
  return ops
end


# IFRK2 (Heun): stage 1 through the charts, the predictor pair, the stage-2 assembly at the
# predictor state, then the corrector combinations.
function rk2_ops(scalar::Bool; phase_shift::Bool = false, charts::Bool = false)
  ops = Op[]
  charts && append!(ops, _chart_recomputes())
  append!(ops, _velocity_assembly(:û, :chart_u, :chart_ω, :nl; phase_shift))     # N̂_u,1 → nl plays stage1's role
  scalar && append!(ops, _scalar_assembly(:û, :φ̂, :chart_u, :sb_nl; phase_shift))
  # Each field's ℰ is at the one substep Δt throughout the step, so it is built once and all four of
  # its consumers (the predictor, N̂₁, the field itself) run in that one visit to the register.
  append!(ops, [
    Op("build E_ν",       Symbol[],           [:fac]),
    Op("û* predictor",    [:û, :nl],          [:ustar_spec]),
    Op("rotate û*",       [:ustar_spec, :fac],[:ustar_spec]),
    Op("rotate N̂_u,1",   [:nl, :fac],        [:nl]),
    Op("rotate û",        [:û, :fac],         [:û]),
  ])
  scalar && append!(ops, [
    Op("build E_κ",       Symbol[],           [:fac]),
    Op("φ̂* predictor",   [:φ̂, :sb_nl],      [:φstar_spec]),
    Op("rotate φ̂*",      [:φstar_spec, :fac],[:φstar_spec]),
    Op("rotate N̂_φ,1",   [:sb_nl, :fac],     [:sb_nl]),
    Op("rotate φ̂",       [:φ̂, :fac],        [:φ̂]),
  ])
  append!(ops, _recoveries(:ustar_spec))
  append!(ops, _velocity_assembly(:ustar_spec, :ustar, :ωstar, :stage2; phase_shift))
  scalar && append!(ops, _scalar_assembly(:ustar_spec, :φstar_spec, :ustar, :sb_stage2; phase_shift))
  append!(ops, [
    Op("û corrector 1",   [:û, :nl],          [:û]),
    Op("û corrector 2",   [:û, :stage2],      [:û]),
  ])
  scalar && append!(ops, [
    Op("φ̂ corrector 1",  [:φ̂, :sb_nl],      [:φ̂]),
    Op("φ̂ corrector 2",  [:φ̂, :sb_stage2],  [:φ̂]),
  ])
  push!(ops, Op("finalize", [:û], [:û]))
  return ops
end


# Peak simultaneous liveness per shape class: a value is live from its first write (or from the
# start, if contract-live or read before written) to its last read (or the end, if contract-live).
function peak_liveness(ops)
  first_use = Dict{Symbol, Int}()
  last_use = Dict{Symbol, Int}()
  for (i, op) in enumerate(ops), v in Iterators.flatten((op.reads, op.writes))
    haskey(first_use, v) || (first_use[v] = i)
    last_use[v] = i
  end
  for v in keys(first_use)
    if v in CONTRACT_LIVE
      first_use[v] = 0
      last_use[v] = length(ops) + 1
    end
  end
  peaks = Dict(class => 0 for class in CLASSES)
  for i in 1:length(ops)
    live = Dict(class => 0 for class in CLASSES)
    for v in keys(first_use)
      first_use[v] <= i <= last_use[v] && (live[VALUE_CLASS[v]] += 1)
    end
    for class in CLASSES
      peaks[class] = max(peaks[class], live[class])
    end
  end
  return NamedTuple{CLASSES}(Tuple(peaks[class] for class in CLASSES))
end


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
  "shift-back average" => _cost(:pointwise; extra = _ex(spectral_scalar = 1)),
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
             "cross u×ω", "Leray projection", "divergence", "flux uφ",
             "seed hu", "seed hφ", "accumulate hu", "accumulate hφ", "û += B·hu", "φ̂ += B·hφ",
             "rotate û", "rotate hu", "rotate φ̂", "rotate hφ", "rotate û*", "rotate φ̂*",
             "rotate N̂_u,1", "rotate N̂_φ,1", "û* predictor", "φ̂* predictor",
             "û corrector 1", "û corrector 2", "φ̂ corrector 1", "φ̂ corrector 2",
             "draw noise", "project noise", "f̂ ← θf̂ + sξ", "add OU source")
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
# `materialize_symbols = false` gives the PHYSICAL FLOOR rather than the fused ideal: it drops the
# field-scale configuration reads (the dealias mask, the translation kernels, the |κ|² the factor
# build sweeps) on the grounds that a per-mode symbol evaluated IN REGISTER from the O(N) axis
# multipliers moves no field-scale memory at all. The difference between the two is therefore
# exactly the traffic that exists only because those symbols are materialized as N³ arrays.
function _fusion_bound(ops; materialize_symbols::Bool = true)
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
      materialize_symbols && cost.extra !== ZERO && (extras[op.name] = cost.extra)
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


# The audited configuration space, and the op list each cell projects.
const DEALIASINGS = (:TwoThirds, :HouLi, :PhaseShift)

_ops(scheme, dealiasing, scalar; ou = false) =
  scheme === :RK3 ?
    rk3_ops(scalar; ou, phase_shift = dealiasing === :PhaseShift, charts = true) :
    rk2_ops(scalar; phase_shift = dealiasing === :PhaseShift, charts = true)

_evals(scheme)  = scheme === :RK3 ? 3 : 2     # right-hand-side evaluations per step
_builds(scheme) = scheme === :RK3 ? 3 : 2     # integrating-factor builds per field per step
