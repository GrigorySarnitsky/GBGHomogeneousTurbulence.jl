# Memory audit — the enforcement of "minimal footprint" (ARCHITECTURE §9 invariant 4, decision 33).
#
# Two instruments, both run in the standard suite:
#
#  1. THE LEDGER — a reflective walk over every resident field-sized buffer a run owns, counted per
#     shape class. The full combination space is a product of five axes — scheme × dealiasing ×
#     scalar × (velocity forcing × scalar forcing) × tracers — and the footprint is COMPOSITIONAL:
#     the frozen spec is the unforced, tracer-free BASE table (12 cells) plus a per-forcing DELTA
#     table and a tracer DELTA, and an exhaustive sweep over the whole product (~360 combinations)
#     asserts measured = base + deltas, cell by cell. Adding or removing a buffer anywhere fails the
#     suite: a footprint change must be a conscious, recorded decision, never a drive-by. (The
#     particle-integrator axis has one point today — the Heun pusher — so it enters as on/off;
#     precision, backend, and the interpolation scheme change bytes, never counts.)
#
#  2. THE LIVENESS AUDIT — the step as a straight-line program: each op's reads and writes, taken
#     from the step! bodies and the generator protocol, give every value a live range; the peak
#     number of simultaneously live values per shape class is the LOWER BOUND on the buffers the
#     implemented operation order needs. The gap register records achieved − bound per class with a
#     NAMED HOLDER for every nonzero gap (an ownership boundary, a survive-the-step contract, a
#     PF-kernel granularity). A gap without a holder is an optimization left on the table, and the
#     test fails; a bound crossing achieved is a bookkeeping error. Re-derive the op lists whenever
#     a step! body or the generator protocol changes — the ledger failing is the reminder.
#
# Shape classes (Float64 sizes per unit, in units of N³ reals): spectral_vector ≈ 3·(1+1/N),
# physical_vector = 3, spectral_scalar ≈ 1+1/N, physical_scalar = 1, rate ≈ ½·(1+1/N).

using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Forcing: StochasticOU   # archived (un-exported); audited for the re-add
using GBGPeriodicFields: field_data, CatmullRom
using Random
using Test


const N_AUDIT = 8
const CLASSES = (:spectral_vector, :physical_vector, :spectral_scalar, :physical_scalar, :rate)

const ZERO = NamedTuple{CLASSES}((0, 0, 0, 0, 0))
_add(a, b) = NamedTuple{CLASSES}(Tuple(getproperty(a, c) + getproperty(b, c) for c in CLASSES))


# ---------------------------------------------------------------- the reflective ledger

shape_class(a::AbstractArray, N) =
  eltype(a) <: Complex ? (ndims(a) == 4 ? :spectral_vector : :spectral_scalar) :
                         (ndims(a) == 4 ? :physical_vector :
                          (size(a, 1) == N ? :physical_scalar : :rate))

# Recursively collect every distinct field-sized array reachable from `x` (dedup by identity, so an
# aliased buffer is counted once — aliasing IS a legitimate footprint optimization). A random
# stream's internal state is O(1) constant memory, not field-scale working memory — skipped, so the
# audit's tiny N does not misread it as a buffer.
function collect_field_arrays!(acc, x, seen, N)
  x === nothing && return acc
  x isa Random.AbstractRNG && return acc
  if x isa AbstractArray
    if length(x) >= N^3 ÷ 2 && !(objectid(x) in seen)
      push!(seen, objectid(x))
      push!(acc, x)
    end
  elseif isstructtype(typeof(x)) && !(x isa Function) && !(x isa Type)
    objectid(x) in seen && return acc
    push!(seen, objectid(x))
    for name in fieldnames(typeof(x))
      isdefined(x, name) && collect_field_arrays!(acc, getfield(x, name), seen, N)
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

# Build one combination's working set and measure it. A stateful forcing (the OU) is materialized by
# one prepare_forcing! call, since its state and noise scratch allocate lazily on first use.
function ledger(domain, scheme, scalar::Bool, velocity_forcing, scalar_forcing, tracers::Bool;
                charts = (:velocity, :vorticity))
  conditions = FlowConditions(; viscosity = 0.1, schmidt = 1.0, velocity_forcing, scalar_forcing)
  state = ResolvedFields(domain; scalar)
  velocity_forcing isa StochasticOU && prepare_forcing!(velocity_forcing, state.velocity, domain, 0.01)
  scalar_forcing isa StochasticOU && prepare_forcing!(scalar_forcing, state.scalar, domain, 0.01)
  owners = Any[state, DerivedFields(domain; charts), ResolvedGenerator(domain, conditions; scalar),
               allocate_buffers(scheme, domain; scalar)]
  if tracers
    push!(owners, Tracers(domain, 4; scheme = CatmullRom, rng = MersenneTwister(1)))
    push!(owners, physical_vector(domain))            # the run layer's Heun endpoint buffer u(tₙ)
  end
  return _counts(owners, N_AUDIT)
end

# The frozen BASE table — unforced (NoForcing/NoForcing), tracer-free. A deliberate footprint change
# updates this spec (and, for a structural change, the op lists below) in the same commit, citing the
# decision. Columns: spectral_vector, physical_vector, spectral_scalar, physical_scalar, rate.
const BASE = Dict(
  (:RK3, :TwoThirds,  false) => (spectral_vector = 5, physical_vector = 5, spectral_scalar = 1, physical_scalar = 0, rate = 1),
  (:RK3, :TwoThirds,  true)  => (spectral_vector = 5, physical_vector = 5, spectral_scalar = 5, physical_scalar = 1, rate = 2),
  (:RK3, :HouLi,      false) => (spectral_vector = 5, physical_vector = 5, spectral_scalar = 1, physical_scalar = 0, rate = 1),
  (:RK3, :HouLi,      true)  => (spectral_vector = 5, physical_vector = 5, spectral_scalar = 5, physical_scalar = 1, rate = 2),
  (:RK3, :PhaseShift, false) => (spectral_vector = 6, physical_vector = 7, spectral_scalar = 3, physical_scalar = 0, rate = 1),
  (:RK3, :PhaseShift, true)  => (spectral_vector = 6, physical_vector = 7, spectral_scalar = 9, physical_scalar = 2, rate = 2),
  (:RK2, :TwoThirds,  false) => (spectral_vector = 6, physical_vector = 5, spectral_scalar = 1, physical_scalar = 0, rate = 1),
  (:RK2, :TwoThirds,  true)  => (spectral_vector = 6, physical_vector = 5, spectral_scalar = 6, physical_scalar = 1, rate = 2),
  (:RK2, :HouLi,      false) => (spectral_vector = 6, physical_vector = 5, spectral_scalar = 1, physical_scalar = 0, rate = 1),
  (:RK2, :HouLi,      true)  => (spectral_vector = 6, physical_vector = 5, spectral_scalar = 6, physical_scalar = 1, rate = 2),
  (:RK2, :PhaseShift, false) => (spectral_vector = 7, physical_vector = 7, spectral_scalar = 3, physical_scalar = 0, rate = 1),
  (:RK2, :PhaseShift, true)  => (spectral_vector = 7, physical_vector = 7, spectral_scalar = 10, physical_scalar = 2, rate = 2),
)

# The frozen forcing DELTAS, per slot. Band/Linear/ConstantPower carry the same (scalar-shaped)
# kernels and masks for either slot; the OU's state and noise scratch take the forced field's shape.
_forcing_delta(tag, slot) =
  tag === :none  ? ZERO :
  tag === :band  ? (spectral_vector = 0, physical_vector = 0, spectral_scalar = 1, physical_scalar = 0, rate = 0) :
  tag === :linear ? (spectral_vector = 0, physical_vector = 0, spectral_scalar = 0, physical_scalar = 0, rate = 1) :
  tag === :power ? (spectral_vector = 0, physical_vector = 0, spectral_scalar = 1, physical_scalar = 0, rate = 1) :
  slot === :velocity ? (spectral_vector = 2, physical_vector = 1, spectral_scalar = 1, physical_scalar = 0, rate = 0) :
                       (spectral_vector = 0, physical_vector = 0, spectral_scalar = 3, physical_scalar = 1, rate = 0)
# (:ou — the band kernel plus, in the forced field's shape, the OU state f̂ and the two noise buffers.)

const TRACER_DELTA = (spectral_vector = 0, physical_vector = 1, spectral_scalar = 0, physical_scalar = 0, rate = 0)

# The charts axis of the observation layer: each declared chart is one resident physical vector; the
# spectral scratch is unconditional. The base table pins the default (both charts) — the rotational
# generator's declared working set requires both to step, so for a stepping run the axis is pinned by
# the physics; it is live at the API level (observation-only uses) and becomes a run axis when
# per-component chart declarations or further charts land.
_chart_delta(charts) = (spectral_vector = 0, physical_vector = length(charts) - 2,
                        spectral_scalar = 0, physical_scalar = 0, rate = 0)

_build_forcing(tag, domain) =
  tag === :none  ? NoForcing() :
  tag === :band  ? BandRescaling(domain; target = 0.5) :
  tag === :linear ? Linear(domain; rate = 0.1) :
  tag === :power ? ConstantPower(domain; target = 0.1) :
  StochasticOU(domain; variance = 0.1, correlation_time = 0.5, seed = 1)

_scheme(tag) = tag === :RK3 ? IFLowStorageRK3() : IFRK2()
const FORCING_TAGS = (:none, :band, :linear, :power, :ou)


# ---------------------------------------------------------------- the liveness audit

# One primitive field operation of a step: what it reads, what it writes. Transcribed from the
# step! bodies and the generator protocol (src/Propagator.jl, src/Generator.jl, src/Forcing.jl) —
# re-derive on any change there. Values are symbolic; VALUE_CLASS types them; CONTRACT_LIVE marks
# the values that must survive the whole step (the state record, the OU forcing state, and the
# charts under the current epoch-at-end design).
struct Op
  name::String
  reads::Vector{Symbol}
  writes::Vector{Symbol}
end

const VALUE_CLASS = Dict(
  :û => :spectral_vector, :scratch => :spectral_vector, :ps => :spectral_vector,
  :hu => :spectral_vector, :nl => :spectral_vector, :stage2 => :spectral_vector,
  :ustar_spec => :spectral_vector, :ou_state => :spectral_vector, :noise_s => :spectral_vector,
  :chart_u => :physical_vector, :chart_ω => :physical_vector, :pp => :physical_vector,
  :ustar => :physical_vector, :ωstar => :physical_vector, :noise_p => :physical_vector,
  :φ̂ => :spectral_scalar, :fac => :spectral_scalar, :sb_copy => :spectral_scalar,
  :sb_nl => :spectral_scalar, :sb_h => :spectral_scalar, :sb_stage2 => :spectral_scalar,
  :φstar_spec => :spectral_scalar,
  :sb_field => :physical_scalar,
)
const CONTRACT_LIVE = Set([:û, :φ̂, :chart_u, :chart_ω, :ou_state])

# The velocity assembly at a stage (mask strategies), reading physical (u, ω) named by the caller;
# `source` appends the additive-forcing source read (the OU) when present.
_assembly(u, ω; source = false) = begin
  ops = [
    Op("cross u×ω",        [u, ω],        [:pp]),
    Op("flux→spectral",    [:pp],         [:ps]),
    Op("Leray projection", [:ps],         [:nl]),
    Op("dealias",          [:nl],         [:nl]),
  ]
  source && push!(ops, Op("add OU source", [:nl, :ou_state], [:nl]))
  ops
end
_scalar_assembly(u) = [
  Op("copy φ̂",          [:φ̂],          [:sb_copy]),
  Op("φ recovery",       [:sb_copy],    [:sb_field]),
  Op("flux uφ",          [u, :sb_field],[:pp]),
  Op("flux→spectral",    [:pp],         [:ps]),
  Op("divergence",       [:ps],         [:sb_nl]),
  Op("dealias",          [:sb_nl],      [:sb_nl]),
]
_recoveries() = [
  Op("copy û",           [:û],          [:scratch]),
  Op("u recovery",       [:scratch],    [:ustar]),
  Op("curl û",           [:û],          [:scratch]),
  Op("ω recovery",       [:scratch],    [:ωstar]),
]
_velocity_update(rhs) = [
  Op("accumulate hu",    [rhs, :hu],    [:hu]),
  Op("û += B·hu",        [:û, :hu],     [:û]),
  Op("build E_ν",        Symbol[],      [:fac]),
  Op("rotate û",         [:û, :fac],    [:û]),
  Op("rotate hu",        [:hu, :fac],   [:hu]),
]
_scalar_update() = [
  Op("accumulate hφ",    [:sb_nl, :sb_h], [:sb_h]),
  Op("φ̂ += B·hφ",       [:φ̂, :sb_h],  [:φ̂]),
  Op("build E_κ",        Symbol[],      [:fac]),
  Op("rotate φ̂",        [:φ̂, :fac],   [:φ̂]),
  Op("rotate hφ",        [:sb_h, :fac], [:sb_h]),
]
# The OU forcing's prepare! phase (velocity slot): generate, transform, band-limit, project,
# normalize, and fold the increment into the contract-live forcing state f̂.
_ou_prepare() = [
  Op("draw noise",       Symbol[],           [:noise_p]),
  Op("noise→spectral",   [:noise_p],         [:noise_s]),
  Op("band-limit",       [:noise_s],         [:noise_s]),
  Op("project noise",    [:noise_s],         [:noise_s]),
  Op("normalize",        [:noise_s],         Symbol[]),
  Op("f̂ ← θf̂ + sξ",    [:ou_state, :noise_s], [:ou_state]),
]

# IFLowStorageRK3, mask dealiasing: stage 1 reads the charts; stages 2–3 recover into the substage
# registers. (hu is seeded at stage 1 by `multiply` — modeled as accumulate with hu initially dead.)
function rk3_ops(scalar::Bool; ou::Bool = false)
  ops = Op[]
  ou && append!(ops, _ou_prepare())
  append!(ops, _assembly(:chart_u, :chart_ω; source = ou))
  scalar && append!(ops, _scalar_assembly(:chart_u))
  append!(ops, _velocity_update(:nl))
  scalar && append!(ops, _scalar_update())
  for _ in 2:3
    append!(ops, _recoveries())
    append!(ops, _assembly(:ustar, :ωstar; source = ou))
    scalar && append!(ops, _scalar_assembly(:ustar))
    append!(ops, _velocity_update(:nl))
    scalar && append!(ops, _scalar_update())
  end
  push!(ops, Op("finalize (band rescale)", [:û], [:û]))
  return ops
end

# IFRK2 (Heun), mask dealiasing.
function rk2_ops(scalar::Bool)
  ops = Op[]
  append!(ops, _assembly(:chart_u, :chart_ω))                      # N̂_u,1 → nl plays stage1's role
  scalar && append!(ops, _scalar_assembly(:chart_u))
  append!(ops, [
    Op("build E_ν",       Symbol[],           [:fac]),
    Op("û* predictor",    [:û, :nl],          [:ustar_spec]),
    Op("rotate û*",       [:ustar_spec, :fac],[:ustar_spec]),
  ])
  scalar && append!(ops, [
    Op("build E_κ",       Symbol[],           [:fac]),
    Op("φ̂* predictor",   [:φ̂, :sb_nl],      [:φstar_spec]),
    Op("rotate φ̂*",      [:φstar_spec, :fac],[:φstar_spec]),
  ])
  append!(ops, [
    Op("copy û*",         [:ustar_spec],      [:scratch]),
    Op("u* recovery",     [:scratch],         [:ustar]),
    Op("curl û*",         [:ustar_spec],      [:scratch]),
    Op("ω* recovery",     [:scratch],         [:ωstar]),
  ])
  append!(ops, [
    Op("cross u*×ω*",     [:ustar, :ωstar],   [:pp]),
    Op("flux→spectral",   [:pp],              [:ps]),
    Op("Leray projection",[:ps],              [:stage2]),
    Op("dealias",         [:stage2],          [:stage2]),
  ])
  scalar && append!(ops, [
    Op("copy φ̂*",        [:φstar_spec],      [:sb_copy]),
    Op("φ* recovery",     [:sb_copy],         [:sb_field]),
    Op("flux u*φ*",       [:ustar, :sb_field],[:pp]),
    Op("flux→spectral",   [:pp],              [:ps]),
    Op("divergence",      [:ps],              [:sb_stage2]),
    Op("dealias",         [:sb_stage2],       [:sb_stage2]),
  ])
  append!(ops, [
    Op("build E_ν",       Symbol[],           [:fac]),
    Op("rotate N̂_u,1",   [:nl, :fac],        [:nl]),
    Op("rotate û",        [:û, :fac],         [:û]),
    Op("û corrector 1",   [:û, :nl],          [:û]),
    Op("û corrector 2",   [:û, :stage2],      [:û]),
  ])
  scalar && append!(ops, [
    Op("build E_κ",       Symbol[],           [:fac]),
    Op("rotate N̂_φ,1",   [:sb_nl, :fac],     [:sb_nl]),
    Op("rotate φ̂",       [:φ̂, :fac],        [:φ̂]),
    Op("φ̂ corrector 1",  [:φ̂, :sb_nl],      [:φ̂]),
    Op("φ̂ corrector 2",  [:φ̂, :sb_stage2],  [:φ̂]),
  ])
  push!(ops, Op("finalize (band rescale)", [:û], [:û]))
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

# The gap register: achieved working buffers (kernels, masks, and rate arrays are configuration, not
# working values, and are excluded on both sides) minus the liveness bound, with a named holder for
# every nonzero gap. An unclaimed gap is a finding, and the test fails. Recorded holders
# (decision 33): OWNERSHIP — buffers that could alias in this schedule but live across a
# deliberately kept boundary (the cache's recovery scratch vs the generator's product/nonlinear
# registers; the OU's noise buffers vs the generator's products); CHART CONTRACT — the charts must
# survive the step under the epoch-at-end design (the epoch-at-start reuse is the recorded
# candidate); SHARED FACTOR — the factor register could be deleted by a fused exponential-convolve
# (raised to GBGPeriodicFields); SCALAR REGISTERS — the scalar's copy/nonlinear/factor registers
# could share one transient slot.
const GAP_HOLDERS = Dict(
  (:RK3, false) => Dict(:spectral_vector => "OWNERSHIP (scratch ↔ product/nonlinear)",
                        :spectral_scalar => "SHARED FACTOR (PF fused-exponential request)"),
  (:RK3, true)  => Dict(:spectral_vector => "OWNERSHIP (scratch ↔ product/nonlinear)",
                        :spectral_scalar => "SHARED FACTOR + SCALAR REGISTERS"),
  (:RK2, false) => Dict(:spectral_vector => "OWNERSHIP (scratch ↔ product/nonlinear)",
                        :spectral_scalar => "SHARED FACTOR (PF fused-exponential request)"),
  (:RK2, true)  => Dict(:spectral_vector => "OWNERSHIP (scratch ↔ product/nonlinear)",
                        :spectral_scalar => "SHARED FACTOR + SCALAR REGISTERS"),
  (:RK3_OU, false) => Dict(:spectral_vector => "OWNERSHIP (scratch, OU noise ↔ product/nonlinear)",
                           :physical_vector => "OWNERSHIP (OU noise ↔ product)",
                           :spectral_scalar => "SHARED FACTOR (PF fused-exponential request)"),
)



# ---------------------------------------------------------------- the episode ledger
#
# Peak memory = resident + the transients of whatever episode is running. The hot loop is
# allocation-free (the step!/advance! guards), so during production stepping peak equals the resident
# ledger above. Outside it, the transient episodes are few, sequential (single-threaded — episodes
# never overlap, so the run-phase peak is resident + the LARGEST episode), and frozen here in units
# of N³ reals, measured mechanically via @allocated (warmed calls; generous bands for library drift).
# Attribution (measured op by op, 2026-07-18):
#   seeding (velocity)    ≈ 10.3 — noise vector 3.0 + host randn staging 3.1 + envelope 1.06 +
#                                  an ALIASED helmholtz_projection!(û, û, …) transient 3.2 (the
#                                  aliased path allocates; the hot loop's non-aliased calls do not —
#                                  raised to GBGPeriodicFields). Construction-time only.
#   seeding (scalar)      ≈ 3.1  — noise scalar 1.0 + host randn staging 1.0 + envelope 1.06.
#   derivative_skewness   ≈ 19.6 — spectral tensor 9 × 1.06 + physical tensor 9 + det field 1: the
#                                  DOMINANT episode (~ +55 % over the default resident set), and ON
#                                  BY DEFAULT during warmup!'s skewness gate — the binding device
#                                  peak of a default warm-up at the largest N that fits. Invariant
#                                  4's per-call-diagnostic trade, priced. (PF stores full 9-component
#                                  tensors; symmetric 6-component storage is the recorded reduction.)
#   energy_spectrum       ≈ 1.6  — GBGPeriodicFields radial_spectrum internal staging (not the O(N)
#                                  shell vectors); integral_scale and flow_parameters inherit it.
# The archived StochasticOU's prepare! also projects its noise ALIASED — an OU-forced step is NOT
# allocation-free today (~3 units/step); recorded on the de-archival gate.
const EPISODE_UNITS = [
  ("seed velocity",      10.3, 1.0),
  ("seed scalar",         3.1, 0.5),
  ("derivative_skewness", 19.6, 1.0),
  ("energy_spectrum",     1.6, 0.5),
  ("integral_scale",      1.6, 0.5),
  ("flow_parameters",     1.6, 0.5),
]


@testset "memory audit" begin
  domains = Dict(tag => FixedDomain(N_AUDIT, 2π; element_type = Float64,
                                    dealiasing = tag === :TwoThirds ? TwoThirds() :
                                                 tag === :HouLi ? HouLi() : PhaseShift(),
                                    array_type = Array)
                 for tag in (:TwoThirds, :HouLi, :PhaseShift))

  @testset "ledger — the frozen base (unforced, tracer-free)" begin
    for ((scheme, dealiasing, scalar), expected) in BASE
      counts = ledger(domains[dealiasing], _scheme(scheme), scalar, NoForcing(), NoForcing(), false)
      @test counts == expected
    end
  end

  @testset "ledger — the full five-axis product is compositional" begin
    # scheme × dealiasing × scalar × velocity forcing × scalar forcing × tracers: every combination
    # must equal base + velocity-forcing delta + scalar-forcing delta + tracer delta. A cross-term
    # (a buffer whose existence depends on two axes at once) fails here and must be recorded.
    for scheme in (:RK3, :RK2), dealiasing in (:TwoThirds, :HouLi, :PhaseShift), scalar in (false, true),
        vtag in FORCING_TAGS, stag in (scalar ? FORCING_TAGS : (:none,)), tracers in (false, true)
      domain = domains[dealiasing]
      counts = ledger(domain, _scheme(scheme), scalar,
                      _build_forcing(vtag, domain), _build_forcing(stag, domain), tracers)
      expected = _add(_add(_add(BASE[(scheme, dealiasing, scalar)],
                                _forcing_delta(vtag, :velocity)),
                           _forcing_delta(stag, :scalar)),
                      tracers ? TRACER_DELTA : ZERO)
      @test counts == expected
    end
  end

  @testset "ledger — the charts axis (API-level; pinned to both charts for a stepping run)" begin
    for scheme in (:RK3, :RK2), scalar in (false, true),
        charts in ((), (:velocity,), (:velocity, :vorticity))
      counts = ledger(domains[:TwoThirds], _scheme(scheme), scalar, NoForcing(), NoForcing(), false; charts)
      @test counts == _add(BASE[(scheme, :TwoThirds, scalar)], _chart_delta(charts))
    end
  end

  @testset "tracer storage scales with M, not N" begin
    # The Tracers value carries exactly four (M, 3) arrays (positions, predictor, and the two
    # point-value registers) — per-tracer memory, audited in its own units.
    tracers = Tracers(domains[:TwoThirds], 4; scheme = CatmullRom, rng = MersenneTwister(1))
    acc = AbstractArray[]
    collect_field_arrays!(acc, tracers, Set{UInt}(), 2)   # threshold 4 elements: catch the M-arrays
    m_arrays = [a for a in acc if size(a) == (4, 3)]
    @test length(m_arrays) == 4
  end

  @testset "op lists name real registers" begin
    # The symbolic values must correspond to actual storage: charts + scratch on DerivedFields,
    # products on ResolvedGenerator, registers on IntegratorBuffers/ScalarBuffers, the OU's state
    # and noise on the forcing.
    @test :spectral_scratch in fieldnames(DerivedFields)
    @test all(f -> f in fieldnames(ResolvedGenerator), (:product_physical, :product_spectral))
    IB = GBGIsotropicTurbulence.Propagator.IntegratorBuffers
    SB = GBGIsotropicTurbulence.Propagator.ScalarBuffers
    @test all(f -> f in fieldnames(IB),
              (:stage1, :stage2, :velocity_star_spectral, :nonlinear, :integrating_factor,
               :vorticity_physical, :velocity_star))
    @test all(f -> f in fieldnames(SB), (:stage1, :stage2, :star_spectral, :nonlinear, :copy, :field))
    @test all(f -> f in fieldnames(StochasticOU), (:state, :noise_physical, :noise_spectral))
  end

  @testset "liveness bounds and the gap register" begin
    cases = [(:RK3, rk3_ops(false), BASE[(:RK3, :TwoThirds, false)], (:RK3, false)),
             (:RK3, rk3_ops(true),  BASE[(:RK3, :TwoThirds, true)],  (:RK3, true)),
             (:RK2, rk2_ops(false), BASE[(:RK2, :TwoThirds, false)], (:RK2, false)),
             (:RK2, rk2_ops(true),  BASE[(:RK2, :TwoThirds, true)],  (:RK2, true)),
             (:RK3, rk3_ops(false; ou = true),
              _add(BASE[(:RK3, :TwoThirds, false)], _forcing_delta(:ou, :velocity)), (:RK3_OU, false))]
    for (scheme, ops, achieved, holder_key) in cases
      bound = peak_liveness(ops)
      holders = GAP_HOLDERS[holder_key]
      for class in (:spectral_vector, :physical_vector, :spectral_scalar, :physical_scalar)
        # Kernels/masks/rates are configuration, not working values: the OU delta's band kernel is
        # the one configuration entry inside a forcing delta — subtract it for the OU case.
        working = getproperty(achieved, class) -
                  (holder_key === (:RK3_OU, false) && class === :spectral_scalar ? 1 : 0)
        b = getproperty(bound, class)
        @test b <= working                        # a bound above the ledger is a bookkeeping error
        if working - b > 0
          @test haskey(holders, class)            # every gap carries a named holder (decision 33)
        end
      end
    end
    # The physical-vector count sits exactly at its bound under the chart contract for the unforced
    # cases: the charts are contract-live, and the substage registers + product peak alongside them.
    for (scheme, ops_of) in ((:RK3, rk3_ops), (:RK2, rk2_ops)), scalar in (false, true)
      @test peak_liveness(ops_of(scalar)).physical_vector ==
            BASE[(scheme, :TwoThirds, scalar)].physical_vector
    end
  end

  @testset "episode ledger — transient peaks, frozen and attributed" begin
    N = 32
    domain = FixedDomain(N, 2π; element_type = Float64, dealiasing = TwoThirds(), array_type = Array)
    unit = 8 * N^3
    û = spectral_vector(domain)
    random_solenoidal_velocity!(û, domain; kinetic_energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(1))
    φ̂ = scalar_spectral(domain)
    random_scalar!(φ̂, domain; scalar_variance = 1.0, peak_wavenumber = 2.0, rng = MersenneTwister(2))
    sim = Simulation(grid_points_per_axis = N, viscosity = 0.05; scalar = true, rng = MersenneTwister(3))
    episodes = Dict(
      "seed velocity" => () -> random_solenoidal_velocity!(û, domain; kinetic_energy = 0.5,
                                                           peak_wavenumber = 2.0, rng = MersenneTwister(1)),
      "seed scalar" => () -> random_scalar!(φ̂, domain; scalar_variance = 1.0,
                                            peak_wavenumber = 2.0, rng = MersenneTwister(2)),
      "derivative_skewness" => () -> derivative_skewness(û, domain),
      "energy_spectrum" => () -> energy_spectrum(û, domain),
      "integral_scale" => () -> integral_scale(û, domain),
      "flow_parameters" => () -> flow_parameters(sim),
    )
    measured = Dict{String, Float64}()
    for (name, expected, tolerance) in EPISODE_UNITS
      f = episodes[name]
      f(); f()                                          # warm (compile) before measuring
      measured[name] = (@allocated f()) / unit
      @test abs(measured[name] - expected) <= tolerance
    end
    # The skewness is the dominant episode — the run-phase peak driver a default warm-up pays.
    @test measured["derivative_skewness"] == maximum(values(measured))

    # The hot loop stays allocation-free at the run layer too, so stepping-phase peak = resident.
    advance!(sim; dt = 1e-3); advance!(sim; dt = 1e-3)
    @test (@allocated advance!(sim; dt = 1e-3)) < 0.2 * unit
  end
end
