# Audit op model — the step as a straight-line program, the single source of truth two audits project
# (ARCHITECTURE decisions 33 and 34):
#
#   * test/memory_audit.jl  — the LIVENESS projection: the peak number of simultaneously live values
#     per shape class, the lower bound on the resident registers the operation order needs.
#   * test/compute_audit.jl — the COST projection: the per-step transform counts and memory-pass
#     counts (the frozen compute ledger, its minimality bounds, and the fusion gap register).
#   * test/optimality_audit.jl — the FLOOR projection (decision 35): the synchronization ledger and
#     the floors, which need the same cost model the compute audit projects.
#
# Three things beyond the op lists live here because more than one audit needs them: the class
# decomposition with its reflective counter (immediately below — it is the operational definition of
# CLASSES, and all three audits measure residency through it), the gap register every audit claims
# its gaps from (`Holder`, before the cost model), and the cost model at the foot of the file
# (OP_COST and the transform / pass / fusion-bound projections, shared by the latter two).
#
# Every op is transcribed from the step! bodies and the generator protocol (src/Propagator.jl,
# src/Generator.jl, the recovery calls — PF's preserving to_physical! arity and
# Observables.vorticity_physical! — and the src/Forcing.jl hooks) — re-derive on any change
# there; a frozen table failing is the reminder. Ops act on SYMBOLIC values (VALUE_CLASS types them);
# an op's NAME keys its cost entry (compute_audit.jl's OP_COST), so a renamed or added op must get a
# cost entry in the same commit.
#
# All three audits share the file by `include` into their own wrapper modules, so each stays
# runnable on its own (`julia --project=. test/<audit>.jl`).

using Random     # the reflective counter below skips a random stream's O(1) internal state

const CLASSES = (:spectral_vector, :physical_vector, :spectral_scalar, :physical_scalar, :real_spectral_scalar)

const ZERO = NamedTuple{CLASSES}((0, 0, 0, 0, 0))
_add(a, b) = NamedTuple{CLASSES}(Tuple(getproperty(a, c) + getproperty(b, c) for c in CLASSES))


# ---------------------------------------------------------------- the class decomposition, applied

# Which class an array belongs to, and the reflective walk that counts a value's field-scale storage
# by class. This is the operational definition of CLASSES above — the residency measurements of both
# the working-set ledger and the frame ledger (memory_audit.jl) and the frame floor
# (optimality_audit.jl) run through it — so it lives beside the class list rather than in one audit.
shape_class(a::AbstractArray, N) =
  eltype(a) <: Complex ? (ndims(a) == 4 ? :spectral_vector : :spectral_scalar) :
                         (ndims(a) == 4 ? :physical_vector :
                          (size(a, 1) == N ? :physical_scalar : :real_spectral_scalar))

# Is this array one of the run's own field-scale arrays? The test is the EXACT shape a field on this
# grid takes, not a threshold: a forcing may hold fields of its own on a coarser grid over the same box
# (`StochasticOU`'s companion, decision 90), whose size is set by its band rather than by N, and a
# threshold read those as residency at the tiny N these audits run at while ignoring them at any real
# one. They are priced as what they are — constant in N — beside the ledger instead.
_is_field_scale(a, N) = length(a) in (N^3, 3 * N^3, N^2 * (N ÷ 2 + 1), 3 * N^2 * (N ÷ 2 + 1))

# The identity of an array's STORAGE, not of the array object: a reshape or a view of a whole array
# is a new object over the same memory, so keying on `objectid` counted one buffer twice. The data
# identifiers name the memory and the pointer names where in it the array starts, so disjoint slices
# of one buffer stay distinct. Hashed, so the walk's `seen` set keeps one element type.
_storage_key(a::AbstractArray) = hash((Base.dataids(a), UInt(pointer(a))))

# Recursively collect every distinct field-sized array reachable from `x`, each counted once by its
# storage — aliasing IS a legitimate footprint optimization. A random stream's internal state is
# O(1) constant memory, not field-scale working memory — skipped, so the audit's tiny N does not
# misread it as a buffer.
#
# What the walk reaches, and why each case is here (the blind spots of the first walk, each pinned
# by a fixture in memory_audit.jl): a struct's fields; a closure's captures, which are its fields —
# a reassigned capture sits in a `Core.Box`, itself a struct; and the elements of an array whose
# element type is not a number, which is how a `Vector` of structs and a `Dict`'s values hold their
# arrays. An array of numbers is a leaf, so a device array is never indexed element by element.
# `keep` decides what counts as storage worth collecting; the default is the run's own field shapes.
# The particle ledgers pass their own, since an (M, 3) array is storage of a different kind.
function collect_field_arrays!(acc, x, seen, N; keep = a -> _is_field_scale(a, N))
  x === nothing && return acc
  x isa Random.AbstractRNG && return acc
  (x isa Type || x isa Module) && return acc
  if x isa AbstractArray
    if eltype(x) <: Number
      key = _storage_key(x)
      if keep(x) && !(key in seen)
        push!(seen, key)
        push!(acc, x)
      end
    else
      objectid(x) in seen && return acc
      push!(seen, objectid(x))
      for i in eachindex(x)
        isassigned(x, i) && collect_field_arrays!(acc, x[i], seen, N; keep)
      end
    end
  elseif isstructtype(typeof(x))
    objectid(x) in seen && return acc
    push!(seen, objectid(x))
    for name in fieldnames(typeof(x))
      isdefined(x, name) && collect_field_arrays!(acc, getfield(x, name), seen, N; keep)
    end
  end
  return acc
end

_counts(owners, N) = begin
  acc = AbstractArray[]
  seen = Set{UInt}()
  for owner in owners
    collect_field_arrays!(acc, owner, seen, N)
  end
  counts = Dict(class => 0 for class in CLASSES)
  for a in acc
    counts[shape_class(a, N)] += 1
  end
  NamedTuple{CLASSES}(Tuple(counts[class] for class in CLASSES))
end


# One primitive field operation of a step: what it reads, what it writes.
struct Op
  name::String
  reads::Vector{Symbol}
  writes::Vector{Symbol}
end

const VALUE_CLASS = Dict(
  :û => :spectral_vector, :ps => :spectral_vector,
  :hu => :spectral_vector, :nl => :spectral_vector, :stage2 => :spectral_vector,
  :ustar_spec => :spectral_vector,
  :s => :spectral_vector, :sb_s => :spectral_scalar,
  :vshift => :spectral_vector,
  :chart_u => :physical_vector, :chart_ω => :physical_vector,
  :ushift => :physical_vector, :ωshift => :physical_vector,
  :φ̂ => :spectral_scalar,
  :sb_nl => :spectral_scalar, :sb_h => :spectral_scalar, :sb_stage2 => :spectral_scalar,
  :φstar_spec => :spectral_scalar, :sshift => :spectral_scalar, :scopy => :spectral_scalar,
  :chart_φ => :physical_scalar, :pshift => :physical_scalar,
)
# Values whose live range is extended past their last use in the op list — live because the DYNAMICS
# of the iteration says so: the state is read and written by every stage and must persist between
# steps, and the cache slots hold the deposited observables the NEXT iteration's first stage reads, so
# their closing deposits must survive the list's end just as their previous deposits precede its start.
# Extending each is a statement of fact, so the set belongs in a lower bound.
#
# (History: decision 37 split a CHART_CONTRACT_LIVE choice out of this set — the charts then survived
# the step UNTOUCHED beside separate substage registers, an assumption that had turned the bound into
# a tautology. The slot=register merge (decision 40) dissolved the choice: one register per chart now
# serves both roles, so the extension no longer stacks registers on top of the stage need.)
const DYNAMICS_LIVE = Set([:û, :φ̂, :chart_u, :chart_ω, :chart_φ])

# The traffic model asks the same question of the same set: a value written and still needed after a
# segment must reach memory.
const CONTRACT_LIVE = DYNAMICS_LIVE


# The closing deposit (deposit! in src/Propagator.jl): the iteration closes by recovering its
# observables into the cache slots — the next iteration's first-stage recoveries moved to the iteration's end —
# and reducing the maximum speed from the just-deposited velocity (the number the next timestep
# choice reads; the once-per-iteration host readback). The spectral working space is a stage register
# that is dead once the step closes: `nl` for RK3, `stage2` for RK2 (`sb_nl` / `sb_stage2` for the
# scalar's copy).
function _closing_deposit(scalar; scratch, sscratch)
  ops = [
    Op("copy û",           [:û],       [scratch]),
    Op("u chart recovery", [scratch],  [:chart_u]),
    Op("curl û",           [:û],       [scratch]),
    Op("ω chart recovery", [scratch],  [:chart_ω]),
  ]
  scalar && append!(ops, [
    Op("copy φ̂",          [:φ̂],      [sscratch]),
    Op("φ chart recovery", [sscratch], [:chart_φ]),
  ])
  push!(ops, Op("max speed", [:chart_u], Symbol[]))
  return ops
end


# The velocity right-hand side at a stage (velocity_rhs! in src/Generator.jl), reading the physical
# (u, ω) named by the caller and writing the dealiased, Leray-projected term into `out`. The negated
# Lamb vector u×ω forms IN PLACE over ω's register (decision 41 — the alias-safe cross), so the assembly
# consumes ω and owns no physical product array. A mask strategy (TwoThirds / HouLi) evaluates once
# and low-passes; PhaseShift also reads the stage's SPECTRAL velocity `uspec` for the
# half-cell-displaced evaluation through the generator's PhaseShiftBuffers registers, averages the
# two grids (the shift-back riding the averaging convolve as one fused α/β pass — the PF-triage free
# win, 2026-07-19), and truncates spherically. `source` appends the additive forcing's per-stage write
# (the OU's add_forcing_source!, a band-sized write into the assembled term).
function _velocity_assembly(uspec, u, ω, out; source = false, phase_shift = false)
  ops = [
    Op("cross u×ω",        [u, ω],        [ω]),
    Op("flux→spectral",    [ω],           [:ps]),
    Op("Leray projection", [:ps],         [out]),
  ]
  if phase_shift
    append!(ops, [
      Op("shift û",            [uspec],            [:vshift]),
      Op("shifted copy",       [:vshift],          [:ps]),
      Op("shifted u recovery", [:ps],              [:ushift]),
      Op("shifted curl",       [:vshift],          [:ps]),
      Op("shifted ω recovery", [:ps],              [:ωshift]),
      Op("cross u×ω",          [:ushift, :ωshift], [:ωshift]),
      Op("flux→spectral",      [:ωshift],          [:ps]),
      Op("Leray projection",   [:ps],              [:vshift]),
      Op("shift-back average", [out, :vshift],     [out]),
    ])
  end
  # No separate dealias op: a mask strategy folds the kernel into the projection's own pass, and
  # PhaseShift's truncation rides the primary projection and the composed shift-back kernel
  # (decision 39) — the kernels are compressed symbols, no field-scale configuration read either way.
  source && push!(ops, Op("add OU source", [out], [out]))
  return ops
end


# The scalar right-hand side at a stage (scalar_rhs! in src/Generator.jl): form the conservative
# flux uφ from the stage's physical scalar, transform, take the divergence into `out`, and dealias.
# At stage 1 the physical scalar is the deposited chart, read as is (`recover = false`); at
# a later stage the caller first recovers the stage scalar into the taken chart slot, through the
# scheme's dead spectral register `sscratch`. PhaseShift adds the displaced flux divergence, reading
# the displaced velocity the SAME stage's velocity assembly left fresh in `ushift` (the freshness
# contract of decision 45 — the re-recovery that once cost three inverse transforms per stage is
# gone, and the transform ledger sits at exactly double the mask cells everywhere).
function _scalar_assembly(uspec, φspec, u, out; recover = false, sscratch = :sb_nl, phase_shift = false)
  ops = Op[]
  recover && append!(ops, [
    Op("copy φ̂",       [φspec],    [sscratch]),
    Op("φ recovery",    [sscratch], [:chart_φ]),
  ])
  # The flux forms IN PLACE over u's register (decision 41), so the assembly consumes u.
  append!(ops, [
    Op("flux uφ",       [u, :chart_φ], [u]),
    Op("flux→spectral", [u],           [:ps]),
    Op("divergence",    [:ps],         [out]),
  ])
  if phase_shift
    append!(ops, [
      Op("shift φ̂",           [φspec],          [:sshift]),
      Op("shifted copy φ̂",    [:sshift],        [:scopy]),
      Op("shifted φ recovery", [:scopy],         [:pshift]),
      Op("flux uφ",            [:ushift, :pshift], [:ushift]),
      Op("flux→spectral",      [:ushift],        [:ps]),
      Op("divergence",         [:ps],            [:sshift]),
      Op("shift-back average", [out, :sshift],   [out]),
    ])
  end
  # No separate dealias op — folded as in the velocity assembly (decision 39).
  return ops
end


# The substage recoveries (PF's preserving to_physical! arity / Observables.vorticity_physical!) from the
# spectral stage state `src` — û itself for the in-place IFLowStorageRK3 stages, the spectral
# predictor for IFHeun's stage 2 — into the cache slots taken as the stage registers, through the
# scheme's dead spectral register `scratch` (`nl` for RK3, `stage2` for RK2). The plain recovery
# copies first (the in-place inverse transform consumes its spectral source); the curl fuses that
# copy into its derivative multiply.
_recoveries(src; scratch) = [
  Op("copy û",       [src],      [scratch]),
  Op("u recovery",   [scratch],  [:chart_u]),
  Op("curl û",       [src],      [scratch]),
  Op("ω recovery",   [scratch],  [:chart_ω]),
]


# The IFLowStorageRK3 stage update, faithful to step!: stage 1 SEEDS the accumulator (`multiply!`,
# no read of the dead register), later stages accumulate; the accumulator's own rotation is skipped
# at the last stage (`i < 3 &&` — it is dead after).
# The stage update and its integrating-factor rotation are ONE fused exponential pass (decision 39):
# E is evaluated per mode from the O(N) wavenumber arrays (plus, when a linear forcing is present, the
# rate field — priced on the forcing axis, not in these unforced base lists), so no factor is built,
# stored, or read.
function _velocity_update(rhs; first = false, last = false)
  ops = [first ? Op("seed hu", [rhs], [:hu]) : Op("accumulate hu", [rhs, :hu], [:hu])]
  push!(ops, Op("û ← E(û+B·hu)", [:û, :hu], [:û]))
  last || push!(ops, Op("rotate hu", [:hu], [:hu]))
  return ops
end
function _scalar_update(; first = false, last = false)
  ops = [first ? Op("seed hφ", [:sb_nl], [:sb_h]) : Op("accumulate hφ", [:sb_nl, :sb_h], [:sb_h])]
  push!(ops, Op("φ̂ ← E(φ̂+B·hφ)", [:φ̂, :sb_h], [:φ̂]))
  last || push!(ops, Op("rotate hφ", [:sb_h], [:sb_h]))
  return ops
end

# The OU forcing has NO field-scale prepare phase (decision 90): its process lives on the band's M
# conjugate mode pairs, is advanced on the host, and is uploaded as an (M, NC) array once per step, so
# nothing it does before the stages touches a field. What remains is the per-stage additive write
# (`source` in the assembly above). The dense form it replaced drew, transformed, band-limited,
# projected and normalized a field of noise every step: three transforms, eight slot-shaped passes and
# one physical write per step, with a spectral and a physical noise vector resident.


# IFLowStorageRK3 as one ITERATION: stage 1 reads the deposited observables the previous closing deposit
# deposited (the charts are live-in), stages 2–3 take the chart slots and recover the stage states
# into them, and the closing deposit closes the iteration (`closing = true`; off for a bare-`step!`
# analysis). `phase_shift` switches the assemblies to the displaced-evaluation form; `ou` adds the
# forcing's prepare phase and per-stage source.
function rk3_ops(scalar::Bool; ou::Bool = false, phase_shift::Bool = false, closing::Bool = true)
  ops = Op[]
  append!(ops, _velocity_assembly(:û, :chart_u, :chart_ω, :nl; source = ou, phase_shift))
  scalar && append!(ops, _scalar_assembly(:û, :φ̂, :chart_u, :sb_nl; phase_shift))
  append!(ops, _velocity_update(:nl; first = true))
  scalar && append!(ops, _scalar_update(; first = true))
  for i in 2:3
    append!(ops, _recoveries(:û; scratch = :nl))
    append!(ops, _velocity_assembly(:û, :chart_u, :chart_ω, :nl; source = ou, phase_shift))
    scalar && append!(ops, _scalar_assembly(:û, :φ̂, :chart_u, :sb_nl; recover = true, sscratch = :sb_nl, phase_shift))
    append!(ops, _velocity_update(:nl; last = i == 3))
    scalar && append!(ops, _scalar_update(; last = i == 3))
  end
  push!(ops, Op("finalize", [:û], [:û]))
  # The advanced state's re-projection (decision 61): one in-place pointwise pass pinning the
  # state's divergence at roundoff — the stage tendencies are projected, the state was not, and its
  # residue compounds in Float32 (measured ×120 per 1500 steps before the pin).
  push!(ops, Op("state re-projection", [:û], [:û]))
  push!(ops, Op("reality projection", [:û], [:û]))
  scalar && push!(ops, Op("scalar reality projection", [:φ̂], [:φ̂]))
  closing && append!(ops, _closing_deposit(scalar; scratch = :nl, sscratch = :sb_nl))
  return ops
end


# IFLowStorageRK4 (decision 85): the SAME 2N iteration as IFLowStorageRK3 — the shared
# `_low_storage_2n_step!` loop in `step!` — carried to five stages with Carpenter–Kennedy's
# coefficients. Two more stage bodies, nothing else.
function rk4_ops(scalar::Bool; ou::Bool = false, phase_shift::Bool = false, closing::Bool = true)
  ops = Op[]
  append!(ops, _velocity_assembly(:û, :chart_u, :chart_ω, :nl; source = ou, phase_shift))
  scalar && append!(ops, _scalar_assembly(:û, :φ̂, :chart_u, :sb_nl; phase_shift))
  append!(ops, _velocity_update(:nl; first = true))
  scalar && append!(ops, _scalar_update(; first = true))
  for i in 2:5
    append!(ops, _recoveries(:û; scratch = :nl))
    append!(ops, _velocity_assembly(:û, :chart_u, :chart_ω, :nl; source = ou, phase_shift))
    scalar && append!(ops, _scalar_assembly(:û, :φ̂, :chart_u, :sb_nl; recover = true, sscratch = :sb_nl, phase_shift))
    append!(ops, _velocity_update(:nl; last = i == 5))
    scalar && append!(ops, _scalar_update(; last = i == 5))
  end
  push!(ops, Op("finalize", [:û], [:û]))
  # The advanced state's re-projection (decision 61): one in-place pointwise pass pinning the
  # state's divergence at roundoff — the stage tendencies are projected, the state was not, and its
  # residue compounds in Float32 (measured ×120 per 1500 steps before the pin).
  push!(ops, Op("state re-projection", [:û], [:û]))
  push!(ops, Op("reality projection", [:û], [:û]))
  scalar && push!(ops, Op("scalar reality projection", [:φ̂], [:φ̂]))
  closing && append!(ops, _closing_deposit(scalar; scratch = :nl, sscratch = :sb_nl))
  return ops
end


# IFSSPRK3 (Shu–Osher, TurTLE's arrangement) as one iteration: the state û holds t_n until the
# final combination, the stage register `s` carries q⁽¹⁾ then q⁽²⁾, and `nl` doubles as the
# right-hand-side register and (spent) recovery scratch — the same two registers as IFLowStorageRK3,
# with the accumulator's role played by the state itself. Stage 2's two terms carry DIFFERENT
# integrating factors, so its combination is three pointwise passes where RK3's is one fused pass;
# against that, no accumulator is ever rotated. Net pointwise passes per field: 7 vs RK3's 8.
function ssprk3_ops(scalar::Bool; phase_shift::Bool = false, closing::Bool = true)
  ops = Op[]
  # stage 1 — RHS at the deposited state; q⁽¹⁾ into `s`, û untouched
  append!(ops, _velocity_assembly(:û, :chart_u, :chart_ω, :nl; phase_shift))
  scalar && append!(ops, _scalar_assembly(:û, :φ̂, :chart_u, :sb_nl; phase_shift))
  push!(ops, Op("s ← E(û+Δt·N̂)", [:û, :nl], [:s]))
  scalar && push!(ops, Op("sφ ← E(φ̂+Δt·N̂)", [:φ̂, :sb_nl], [:sb_s]))
  for i in 2:3
    append!(ops, _recoveries(:s; scratch = :nl))
    append!(ops, _velocity_assembly(:s, :chart_u, :chart_ω, :nl; phase_shift))
    scalar && append!(ops, _scalar_assembly(:s, :sb_s, :chart_u, :sb_nl; recover = true, sscratch = :sb_nl, phase_shift))
    if i == 2   # q⁽²⁾ = ¾ E(Δt/2) û + ¼ E(−Δt/2)(q⁽¹⁾ + Δt N̂) — two factors, three passes
      push!(ops, Op("s ← E⁻(s+Δt·N̂)", [:s, :nl], [:s]))
      push!(ops, Op("nl ← ¾E·û", [:û], [:nl]))
      push!(ops, Op("s ← ¼s+nl", [:s, :nl], [:s]))
      scalar && append!(ops, [
        Op("sφ ← E⁻(sφ+Δt·N̂)", [:sb_s, :sb_nl], [:sb_s]),
        Op("sb_nl ← ¾E·φ̂", [:φ̂], [:sb_nl]),
        Op("sφ ← ¼sφ+sb_nl", [:sb_s, :sb_nl], [:sb_s]),
      ])
    else        # û ← ⅓ E(Δt) û + ⅔ E(Δt/2)(q⁽²⁾ + Δt N̂)
      push!(ops, Op("s ← E(s+Δt·N̂)", [:s, :nl], [:s]))
      push!(ops, Op("û ← ⅓E·û", [:û], [:û]))
      push!(ops, Op("û ← û+⅔s", [:û, :s], [:û]))
      scalar && append!(ops, [
        Op("sφ ← E(sφ+Δt·N̂)", [:sb_s, :sb_nl], [:sb_s]),
        Op("φ̂ ← ⅓E·φ̂", [:φ̂], [:φ̂]),
        Op("φ̂ ← φ̂+⅔sφ", [:φ̂, :sb_s], [:φ̂]),
      ])
    end
  end
  push!(ops, Op("finalize", [:û], [:û]))
  # The advanced state's re-projection (decision 61), identical to the other schemes.
  push!(ops, Op("state re-projection", [:û], [:û]))
  push!(ops, Op("reality projection", [:û], [:û]))
  scalar && push!(ops, Op("scalar reality projection", [:φ̂], [:φ̂]))
  closing && append!(ops, _closing_deposit(scalar; scratch = :nl, sscratch = :sb_nl))
  return ops
end


# IFHeun (Heun) as one iteration: stage 1 through the deposited observables, the predictor
# pair, the stage-2 assembly at the predictor state (recovered into the taken chart slots), the
# corrector combinations, then the closing deposit.
function rk2_ops(scalar::Bool; phase_shift::Bool = false, closing::Bool = true)
  ops = Op[]
  append!(ops, _velocity_assembly(:û, :chart_u, :chart_ω, :nl; phase_shift))     # N̂_u,1 → nl plays stage1's role
  scalar && append!(ops, _scalar_assembly(:û, :φ̂, :chart_u, :sb_nl; phase_shift))
  # Each field's ℰ is at the one substep Δt throughout the step; the predictor combination fuses
  # with its rotation into one exponential pass, and no factor is built (decision 39).
  append!(ops, [
    Op("û* ← E(û+Δt·N̂₁)", [:û, :nl],     [:ustar_spec]),
    Op("rotate N̂_u,1",     [:nl],          [:nl]),
    Op("rotate û",          [:û],           [:û]),
  ])
  scalar && append!(ops, [
    Op("φ̂* ← E(φ̂+Δt·N̂₁)", [:φ̂, :sb_nl], [:φstar_spec]),
    Op("rotate N̂_φ,1",      [:sb_nl],       [:sb_nl]),
    Op("rotate φ̂",           [:φ̂],          [:φ̂]),
  ])
  append!(ops, _recoveries(:ustar_spec; scratch = :stage2))
  append!(ops, _velocity_assembly(:ustar_spec, :chart_u, :chart_ω, :stage2; phase_shift))
  scalar && append!(ops, _scalar_assembly(:ustar_spec, :φstar_spec, :chart_u, :sb_stage2; recover = true, sscratch = :sb_stage2, phase_shift))
  append!(ops, [
    Op("û corrector 1",   [:û, :nl],          [:û]),
    Op("û corrector 2",   [:û, :stage2],      [:û]),
  ])
  scalar && append!(ops, [
    Op("φ̂ corrector 1",  [:φ̂, :sb_nl],      [:φ̂]),
    Op("φ̂ corrector 2",  [:φ̂, :sb_stage2],  [:φ̂]),
  ])
  push!(ops, Op("finalize", [:û], [:û]))
  # The advanced state's re-projection (decision 61): one in-place pointwise pass pinning the
  # state's divergence at roundoff — the stage tendencies are projected, the state was not, and its
  # residue compounds in Float32 (measured ×120 per 1500 steps before the pin).
  push!(ops, Op("state re-projection", [:û], [:û]))
  push!(ops, Op("reality projection", [:û], [:û]))
  scalar && push!(ops, Op("scalar reality projection", [:φ̂], [:φ̂]))
  closing && append!(ops, _closing_deposit(scalar; scratch = :stage2, sscratch = :sb_stage2))
  return ops
end


# Peak simultaneous liveness per shape class: a value is live from its first write (or from the
# start, if extended or read before written) to its last read (or the end, if extended). Only
# DYNAMICS_LIVE values are extended — every extension is a fact of the iteration contract (decision
# 37's charts_live choice dissolved with the slot=register merge, decision 40) — so the result is a
# genuine lower bound on the registers this operation order needs.
function peak_liveness(ops)
  extended = DYNAMICS_LIVE
  first_use = Dict{Symbol, Int}()
  last_use = Dict{Symbol, Int}()
  for (i, op) in enumerate(ops), v in Iterators.flatten((op.reads, op.writes))
    haskey(first_use, v) || (first_use[v] = i)
    last_use[v] = i
  end
  for v in keys(first_use)
    if v in extended
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


# ---------------------------------------------------------------- the gap register

# ONE register for every audit (2026-10-01). Each audit holds a cost against a floor, and every gap
# above a floor must be claimed by a `Holder`; a holder whose gap has gone fails too. The compute
# audit's transform and fusion registers, the memory audit's liveness register and the optimality
# audit's synchronization ledger all claim with these objects, so a gap is listed once whichever
# audit finds it. (The traffic audit's holders are GBGCodingTools's `Traffic` strings, and join
# when the register becomes an engine there.)
#
# The dispositions:
#   :FIX      — a local win, kept on the frozen OPEN_LOCAL_WINS list until taken, retired in the
#               commit that takes it;
#   :PF_RAISE — a recorded request against a backend; the gap is not ours to close;
#   :DESIGN   — a cost the owner adopted, citing its decision, and carrying BOTH measured sides:
#               `cost`, what it costs and where the audit measures it, and `gain`, what it buys — a
#               measured time, or a named property. A trade is legitimate (memory for speed, a
#               crossing for the impossibility of a stale read); an unmeasured one is not a
#               disposition.
struct Holder
  name::String
  disposition::Symbol
  what::String
  cost::String
  gain::String
end
Holder(name, disposition, what) = Holder(name, disposition, what, "", "")

# The register's admission rule, one function so a planted holder exercises the rule itself: a known
# disposition, a cause and not just a label, and for a trade both priced sides and the decision that
# adopted it; a holder that is not a trade carries neither side.
holder_admissible(h::Holder) =
  h.disposition in (:FIX, :PF_RAISE, :DESIGN) && !isempty(h.name) && length(h.what) > 40 &&
  (h.disposition === :DESIGN ?
     occursin("decision", h.what) && !isempty(h.cost) && !isempty(h.gain) :
     isempty(h.cost) && isempty(h.gain))

const UNUSED_FUSION = Holder(
  "UNFUSED STAGE PIPELINE", :PF_RAISE,
  "Leray → dealias → accumulate → update → factor-rotate run as one kernel per operation where one " *
  "fused per-mode kernel could read (product, state) and write (state, accumulator) once. The " *
  "passes between those boundaries are pure intermediate traffic.")

# MATERIALIZED PER-MODE SYMBOLS — RETIRED 2026-08-06 (decisions 38/39), both claims closed by the
# PF adoption: the residency claim when the de-alias mask, the phase-shift translation kernels, and
# |κ|² became lazy kernels (the frame ledger is zero field-scale arrays — 322.5 MiB retired at
# 256³ / Float64), and the traffic claim when the fused exponential replaced the integrating-factor
# register (the pass floor's second tier collapsed onto the fused bound: bound == floor in every
# cell, asserted below). The lazy per-mode symbol apply this holder requested of the backend was
# delivered in full.

const HOST_SIDE_FORCING_SCALARS = Holder(
  "HOST-SIDE FORCING SCALARS", :PF_RAISE,
  "A forcing reduces its band observable to a Julia scalar, branches on it, " *
  "and feeds it back to a kernel as a coefficient — a full round trip for a number that never " *
  "needed to leave the device. Closing it needs a reduction into a device-resident scalar and " *
  "kernels that accept one as a coefficient; the guard branch folds into the same kernel.")

const UNFUSED_QUADRATIC_REDUCTIONS = Holder(
  "UNFUSED QUADRATIC REDUCTIONS", :PF_RAISE,
  "WHAT REMAINS after the multi-weight fused reduction shipped (PF decision 72, requested " *
  "2026-08-23, wired the same day): the scalar variance the stationarity gate samples, and the " *
  "advance! NaN-guard's per-iteration scalar variance, are each a " *
  "traversal of a DIFFERENT operand — φ̂ where the turnover pair sweeps û — and the delivered " *
  "reduction fuses n weights over ONE field, so the φ² crossing cannot join the pair's barrier. " *
  "Closing it needs a cross-FIELD fused reduction (one barrier answering weighted sums over " *
  "several fields at once), a further and much smaller backend ask, deliberately not yet raised. " *
  "The derivative skewness never joins: a cubic reduction over a different operand, its own pass. " *
  "THE FORMER DOMINANT INSTANCE — VarianceController's three same-field reductions per stage, " *
  "nine of the default run's ten crossings — is CLOSED: one fused weighted_inner(f, (1, band, " *
  "|κ|²)) per stage took the default row from ten crossings to four, and the turnover clock's " *
  "(k, ε) pair fused the same way in kinetic_energy_and_dissipation.")

# CHART CONTRACT — RETIRED 2026-08-06 (decision 40), by exactly the closing refresh its text
# prescribed: the iteration now deposits the charts at its end and the step takes the same slots as
# its substage recovery registers, so a chart and its register are one array and every unforced cell
# sits AT its liveness bound (the two physical vectors — 768 MiB at 256³ / Float64 — banked; the
# memory audit asserts the equality).

const UNIFORM_DEPOSIT_SCHEDULE = Holder(
  "UNIFORM DEPOSIT SCHEDULE", :DESIGN,
  "The observables cache deposits every slot at every iteration's end — the schedule is fixed at construction " *
  "and identical on every iteration (decision 40, the no-recompute design the user adopted) — so " *
  "an iteration advanced with a hand-fixed Δt still reduces the maximum speed and reads it back, " *
  "one crossing above that path's zero floor. The uniform schedule is what makes stale reads " *
  "impossible and the frozen ledgers exact; a configuration-dependent deposit set would trade this " *
  "one number for a schedule that varies with how the run is driven.",
  "one host crossing per iteration on a fixed-Δt path, above that path's zero floor — the " *
  "synchronization ledger's fixed-Δt rows",
  "no slot can be read stale, since every slot is deposited at every iteration's end, and the " *
  "frozen ledgers stay exact (a named property, not a time)")

# Found 2026-09-30 when the working set's symbols were first held against the frame's zero floor.
const RESIDENT_LINEAR_RATE = Holder(
  "RESIDENT LINEAR RATE", :PF_RAISE,
  "Linear's steady rate A(κ) is a function of |κ|² alone — the forced band's indicator times A — " *
  "yet it is stored as one scalar field in spectral representation per Linear-forced field (about " *
  "129 MiB at 256³ / Float64), because PF's exponential_convolve! takes its offset only as a " *
  "stored field. Its floor is zero, as for every symbol the frame dropped. Closing it needs the " *
  "offset as a radial symbol; the request is drafted in the memory-audit plan, not yet sent.")

const ALL_HOLDERS = (UNUSED_FUSION, RESIDENT_LINEAR_RATE,
                     HOST_SIDE_FORCING_SCALARS, UNFUSED_QUADRATIC_REDUCTIONS,
                     UNIFORM_DEPOSIT_SCHEDULE)

# A `:FIX` holder is a local win recorded as OPEN, never as accepted. The set is frozen so one
# cannot be added silently, and taking the win means deleting the entry in the same commit.
# (Empty since CHART CONTRACT was taken, 2026-08-06.)
const OPEN_LOCAL_WINS = ()


# ---------------------------------------------------------------- the op cost model

# One cost entry per op NAME: its kind (:transform / :reduction / :pointwise / :noop), its
# scalar-equivalent transform counts, and the field-scale configuration arrays it reads beyond its
# symbolic operands (`extra`, by shape class): the dealias kernel and the translation kernels are
# complex scalar-shaped fields (spectral_scalar), |κ|² and the forcing-rate arrays are real
# spectral-shaped (real_spectral_scalar). O(N) configuration (the axis multipliers, shell vectors)
# is ignored, as in
# the memory ledger. A transform's own input/output traffic lives inside the transform count — the
# FFT's internal passes are FFTW's, not this schedule's.
_ex(; kw...) = merge(ZERO, NamedTuple(kw))
_cost(kind; c2r = 0, r2c = 0, extra = ZERO) = (kind = kind, c2r = c2r, r2c = r2c, extra = extra)

const OP_COST = Dict(
  # transforms — the FFT currency
  "flux→spectral"      => _cost(:transform; r2c = 3),
  "u recovery"         => _cost(:transform; c2r = 3),
  "ω recovery"         => _cost(:transform; c2r = 3),
  "u chart recovery"   => _cost(:transform; c2r = 3),
  "ω chart recovery"   => _cost(:transform; c2r = 3),
  "shifted u recovery" => _cost(:transform; c2r = 3),
  "shifted ω recovery" => _cost(:transform; c2r = 3),
  "φ recovery"         => _cost(:transform; c2r = 1),
  "φ chart recovery"   => _cost(:transform; c2r = 1),
  "shifted φ recovery" => _cost(:transform; c2r = 1),
  # reductions — a fusion barrier like a transform (the scalar result gates the next kernel), but
  # the read passes are real and irreducible
  "max speed"          => _cost(:reduction),
  # Since the PF adoption (decisions 38/39) every kernel a base op applies is a compressed symbol —
  # a radial closure or O(N) per-axis factors — so no op reads a field-scale configuration array and
  # the `extra` column of this table is empty: the pass ledger IS the physical floor.
  # the unforced finalize is a no-op (the forcing deltas price the real hooks)
  "finalize"           => _cost(:noop),
  "state re-projection" => _cost(:pointwise),
  # The reality projection (decision 88) touches the folded axis's one or two self-conjugate planes
  # per component — O(N²), 1/N of a field pass — and this ledger counts traffic in N³ units at
  # leading order in 1/N, so it is priced below the ledger's resolution, like the O(1) mean-mode pin
  # and the tracers' M×3 reads. It stays in the op lists because it is a real in-place read and
  # write of the state (the liveness model sees it) and because a renamed or dropped op must fail
  # here, not vanish. The pass count itself is pinned in the field library's pass audit: each stored
  # plane element read once and written once, both arities.
  "reality projection"        => _cost(:noop),
  "scalar reality projection" => _cost(:noop),
  # The OU source (decision 90) writes the band's M conjugate mode pairs into the assembled term — an
  # O(M) indexed write, below the ledger's resolution like the reality projection above. It stays in
  # the op list for the same two reasons.
  "add OU source"             => _cost(:noop),
)
# Plain pointwise ops — passes are their symbolic reads and writes alone.
for name in ("copy û", "copy φ̂", "shifted copy", "shifted copy φ̂", "curl û", "shifted curl",
             "cross u×ω", "Leray projection", "divergence", "flux uφ",
             "shift û", "shift φ̂", "shift-back average",
             "seed hu", "seed hφ", "accumulate hu", "accumulate hφ",
             "û ← E(û+B·hu)", "φ̂ ← E(φ̂+B·hφ)", "û* ← E(û+Δt·N̂₁)", "φ̂* ← E(φ̂+Δt·N̂₁)",
             "rotate û", "rotate hu", "rotate φ̂", "rotate hφ",
             "rotate N̂_u,1", "rotate N̂_φ,1",
             "û corrector 1", "û corrector 2", "φ̂ corrector 1", "φ̂ corrector 2",
             "s ← E(û+Δt·N̂)", "sφ ← E(φ̂+Δt·N̂)", "s ← E⁻(s+Δt·N̂)", "sφ ← E⁻(sφ+Δt·N̂)",
             "nl ← ¾E·û", "sb_nl ← ¾E·φ̂", "s ← ¼s+nl", "sφ ← ¼sφ+sb_nl",
             "s ← E(s+Δt·N̂)", "sφ ← E(sφ+Δt·N̂)", "û ← ⅓E·û", "φ̂ ← ⅓E·φ̂",
             "û ← û+⅔s", "φ̂ ← φ̂+⅔sφ")
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
  scheme === :RK3 ? rk3_ops(scalar; ou, phase_shift = dealiasing === :PhaseShift) :
  scheme === :RK4 ? rk4_ops(scalar; ou, phase_shift = dealiasing === :PhaseShift) :
  scheme === :SSPRK3 ? ssprk3_ops(scalar; phase_shift = dealiasing === :PhaseShift) :
  rk2_ops(scalar; phase_shift = dealiasing === :PhaseShift)

_evals(scheme)  = scheme === :RK2 ? 2 : scheme === :RK4 ? 5 : 3     # right-hand-side evaluations per step
_applies(scheme) = scheme === :RK3 ? 5 : scheme === :RK4 ? 9 : scheme === :SSPRK3 ? 6 : 3
                                              # fused-exponential applications per field per step
                                              # (RK3: 3 state updates + 2 accumulator rotations;
                                              #  SSPRK3: 3 stage updates + 3 single-operand
                                              #  transports — no rotations;
                                              #  RK2: predictor + first-stage + state rotations)
