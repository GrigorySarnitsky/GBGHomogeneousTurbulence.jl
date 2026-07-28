# Audit op model — the step as a straight-line program, the single source of truth two audits project
# (ARCHITECTURE decisions 33 and 34):
#
#   * test/memory_audit.jl  — the LIVENESS projection: the peak number of simultaneously live values
#     per shape class, the lower bound on the resident registers the operation order needs.
#   * test/compute_audit.jl — the COST projection: the per-step transform counts and memory-pass
#     counts (the frozen compute ledger, its minimality bounds, and the fusion gap register).
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
# project, normalize (the variance reduction, then the rescale it feeds), and fold the increment into
# the contract-live forcing state f̂.
_ou_prepare() = [
  Op("draw noise",       Symbol[],           [:noise_p]),
  Op("noise→spectral",   [:noise_p],         [:noise_s]),
  Op("band-limit",       [:noise_s],         [:noise_s]),
  Op("project noise",    [:noise_s],         [:noise_s]),
  Op("normalize",        [:noise_s],         Symbol[]),
  Op("rescale ξ",        [:noise_s],         [:noise_s]),
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
