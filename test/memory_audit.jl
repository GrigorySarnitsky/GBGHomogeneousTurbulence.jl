# Memory audit — the enforcement of "minimal footprint" (ARCHITECTURE §9 invariant 4, decision 33).
#
# Two instruments, both run in the standard suite:
#
#  1. THE LEDGER — a reflective walk over every resident field-sized buffer a run owns (state, the
#     observation cache, the generator, the integrator buffers, forcing-owned kernels), counted per
#     shape class and asserted against a frozen table for every (scheme × dealiasing × scalar)
#     combination. Adding or removing a buffer anywhere fails this test: a footprint change must be a
#     conscious, recorded decision, never a drive-by.
#
#  2. THE LIVENESS AUDIT — the step as a straight-line program: each op's reads and writes, taken
#     from the step! bodies, give every value a live range; the peak number of simultaneously live
#     values per shape class is the LOWER BOUND on the buffers the implemented operation order needs.
#     The frozen gap register records achieved − bound per class with a NAMED HOLDER for every
#     nonzero gap (an ownership boundary, a survive-the-step contract, a PF-kernel granularity).
#     A gap without a holder is an optimization left on the table; a bound crossing achieved is a
#     bookkeeping error. Re-derive the op lists whenever a step! body or the generator protocol
#     changes — the ledger failing is the reminder.
#
# Shape classes (Float64 sizes per unit, in units of N³ reals): spectral_vector ≈ 3·(1+1/N),
# physical_vector = 3, spectral_scalar ≈ 1+1/N, physical_scalar = 1, rate ≈ ½·(1+1/N).

using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data
using Random
using Test


const N_AUDIT = 8
const CLASSES = (:spectral_vector, :physical_vector, :spectral_scalar, :physical_scalar, :rate)


# ---------------------------------------------------------------- the reflective ledger

shape_class(a::AbstractArray, N) =
  eltype(a) <: Complex ? (ndims(a) == 4 ? :spectral_vector : :spectral_scalar) :
                         (ndims(a) == 4 ? :physical_vector :
                          (size(a, 1) == N ? :physical_scalar : :rate))

# Recursively collect every distinct field-sized array reachable from `x` (dedup by identity, so an
# aliased buffer is counted once — aliasing IS a legitimate footprint optimization).
function collect_field_arrays!(acc, x, seen, N)
  x === nothing && return acc
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

function ledger(scheme, dealiasing, scalar::Bool)
  domain = FixedDomain(N_AUDIT, 2π; element_type = Float64, dealiasing, array_type = Array)
  conditions = FlowConditions(viscosity = 0.1, schmidt = 1.0,
                              velocity_forcing = BandRescaling(domain; target = 0.5),
                              scalar_forcing = NoForcing())
  state = ResolvedFields(domain; scalar)
  derived = DerivedFields(domain)
  generator = ResolvedGenerator(domain, conditions; scalar)
  buffers = allocate_buffers(scheme, domain; scalar)

  acc = AbstractArray[]
  seen = Set{UInt}()
  for owner in (state, derived, generator, buffers)
    collect_field_arrays!(acc, owner, seen, N_AUDIT)
  end
  counts = Dict(class => 0 for class in CLASSES)
  for a in acc
    counts[shape_class(a, N_AUDIT)] += 1
  end
  return NamedTuple{CLASSES}(Tuple(counts[class] for class in CLASSES))
end

# The frozen table — the standard-procedure guard. A deliberate footprint change updates this table
# (and, for a structural change, the op lists below) in the same commit, citing the decision.
# Columns: spectral_vector, physical_vector, spectral_scalar, physical_scalar, rate.
const LEDGER_EXPECTED = Dict(
  (:RK3, :TwoThirds,  false) => (spectral_vector = 5, physical_vector = 5, spectral_scalar = 2, physical_scalar = 0, rate = 1),
  (:RK3, :TwoThirds,  true)  => (spectral_vector = 5, physical_vector = 5, spectral_scalar = 6, physical_scalar = 1, rate = 2),
  (:RK3, :HouLi,      false) => (spectral_vector = 5, physical_vector = 5, spectral_scalar = 2, physical_scalar = 0, rate = 1),
  (:RK3, :HouLi,      true)  => (spectral_vector = 5, physical_vector = 5, spectral_scalar = 6, physical_scalar = 1, rate = 2),
  (:RK3, :PhaseShift, false) => (spectral_vector = 6, physical_vector = 7, spectral_scalar = 4, physical_scalar = 0, rate = 1),
  (:RK3, :PhaseShift, true)  => (spectral_vector = 6, physical_vector = 7, spectral_scalar = 10, physical_scalar = 2, rate = 2),
  (:RK2, :TwoThirds,  false) => (spectral_vector = 6, physical_vector = 5, spectral_scalar = 2, physical_scalar = 0, rate = 1),
  (:RK2, :TwoThirds,  true)  => (spectral_vector = 6, physical_vector = 5, spectral_scalar = 7, physical_scalar = 1, rate = 2),
  (:RK2, :HouLi,      false) => (spectral_vector = 6, physical_vector = 5, spectral_scalar = 2, physical_scalar = 0, rate = 1),
  (:RK2, :HouLi,      true)  => (spectral_vector = 6, physical_vector = 5, spectral_scalar = 7, physical_scalar = 1, rate = 2),
  (:RK2, :PhaseShift, false) => (spectral_vector = 7, physical_vector = 7, spectral_scalar = 4, physical_scalar = 0, rate = 1),
  (:RK2, :PhaseShift, true)  => (spectral_vector = 7, physical_vector = 7, spectral_scalar = 11, physical_scalar = 2, rate = 2),
)

_scheme(tag) = tag === :RK3 ? IFLowStorageRK3() : IFRK2()
_dealiasing(tag) = tag === :TwoThirds ? TwoThirds() : (tag === :HouLi ? HouLi() : PhaseShift())


# ---------------------------------------------------------------- the liveness audit

# One primitive field operation of a step: what it reads, what it writes. Transcribed from the
# step! bodies and the generator protocol (src/Propagator.jl, src/Generator.jl) — re-derive on any
# change there. Values are symbolic; VALUE_CLASS types them; CONTRACT_LIVE marks the values that
# must survive the whole step (the state record; the charts under the current epoch-at-end design).
struct Op
  name::String
  reads::Vector{Symbol}
  writes::Vector{Symbol}
end

const VALUE_CLASS = Dict(
  :û => :spectral_vector, :scratch => :spectral_vector, :ps => :spectral_vector,
  :hu => :spectral_vector, :nl => :spectral_vector, :stage2 => :spectral_vector,
  :ustar_spec => :spectral_vector,
  :chart_u => :physical_vector, :chart_ω => :physical_vector, :pp => :physical_vector,
  :ustar => :physical_vector, :ωstar => :physical_vector,
  :φ̂ => :spectral_scalar, :fac => :spectral_scalar, :sb_copy => :spectral_scalar,
  :sb_nl => :spectral_scalar, :sb_h => :spectral_scalar, :sb_stage2 => :spectral_scalar,
  :φstar_spec => :spectral_scalar,
  :sb_field => :physical_scalar,
)
const CONTRACT_LIVE = Set([:û, :φ̂, :chart_u, :chart_ω])

# The velocity assembly at a stage (mask strategies), reading physical (u, ω) named by the caller.
_assembly(u, ω) = [
  Op("cross u×ω",        [u, ω],        [:pp]),
  Op("flux→spectral",    [:pp],         [:ps]),
  Op("Leray projection", [:ps],         [:nl]),
  Op("dealias",          [:nl],         [:nl]),
]
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

# IFLowStorageRK3, mask dealiasing: stage 1 reads the charts; stages 2–3 recover into the substage
# registers. (hu is seeded at stage 1 by `multiply` — modeled as accumulate with hu initially dead.)
function rk3_ops(scalar::Bool)
  ops = Op[]
  append!(ops, _assembly(:chart_u, :chart_ω))
  scalar && append!(ops, _scalar_assembly(:chart_u))
  append!(ops, _velocity_update(:nl))
  scalar && append!(ops, _scalar_update())
  for _ in 2:3
    append!(ops, _recoveries())
    append!(ops, _assembly(:ustar, :ωstar))
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

# The gap register: achieved (working buffers the op list can touch — kernels and rate arrays,
# constant configuration rather than working values, are excluded) minus the liveness bound, with a
# named holder for every nonzero gap. Empty holder = unclaimed gap = a finding, and the test fails.
# Recorded holders (decision 33): OWNERSHIP — the recovery scratch (State/DerivedFields) and the
# generator's product/assembly registers could alias in this schedule, but live across an ownership
# boundary kept deliberately; CHART CONTRACT — the charts must survive the step under the
# epoch-at-end design (the epoch-at-start reuse is the recorded candidate); SHARED FACTOR — the
# factor register could be deleted by a fused exponential-convolve (raised to GBGPeriodicFields);
# SCALAR REGISTERS — the scalar's copy/nonlinear/factor registers could share one transient slot.
const GAP_HOLDERS = Dict(
  (:RK3, false) => Dict(:spectral_vector => "OWNERSHIP (scratch ↔ product/nonlinear)",
                        :spectral_scalar => "SHARED FACTOR (PF fused-exponential request)"),
  (:RK3, true)  => Dict(:spectral_vector => "OWNERSHIP (scratch ↔ product/nonlinear)",
                        :spectral_scalar => "SHARED FACTOR + SCALAR REGISTERS"),
  (:RK2, false) => Dict(:spectral_vector => "OWNERSHIP (scratch ↔ product/nonlinear)",
                        :spectral_scalar => "SHARED FACTOR (PF fused-exponential request)"),
  (:RK2, true)  => Dict(:spectral_vector => "OWNERSHIP (scratch ↔ product/nonlinear)",
                        :spectral_scalar => "SHARED FACTOR + SCALAR REGISTERS"),
)


@testset "memory audit" begin
  @testset "ledger — every resident buffer, frozen per combination" begin
    for ((scheme, dealiasing, scalar), expected) in LEDGER_EXPECTED
      counts = ledger(_scheme(scheme), _dealiasing(dealiasing), scalar)
      @test counts == expected
    end
  end

  @testset "op lists name real registers" begin
    # The symbolic values must correspond to actual storage: charts + scratch on DerivedFields,
    # products on ResolvedGenerator, registers on IntegratorBuffers/ScalarBuffers.
    @test :spectral_scratch in fieldnames(DerivedFields)
    @test all(f -> f in fieldnames(ResolvedGenerator), (:product_physical, :product_spectral))
    IB = GBGIsotropicTurbulence.Propagator.IntegratorBuffers
    SB = GBGIsotropicTurbulence.Propagator.ScalarBuffers
    @test all(f -> f in fieldnames(IB),
              (:stage1, :stage2, :velocity_star_spectral, :nonlinear, :integrating_factor,
               :vorticity_physical, :velocity_star))
    @test all(f -> f in fieldnames(SB), (:stage1, :stage2, :star_spectral, :nonlinear, :copy, :field))
  end

  @testset "liveness bounds and the gap register" begin
    for (scheme, ops_of) in ((:RK3, rk3_ops), (:RK2, rk2_ops)), scalar in (false, true)
      bound = peak_liveness(ops_of(scalar))
      achieved = LEDGER_EXPECTED[(scheme, :TwoThirds, scalar)]
      holders = GAP_HOLDERS[(scheme, scalar)]
      for class in (:spectral_vector, :physical_vector, :spectral_scalar, :physical_scalar)
        # kernels/rates are configuration, not working values: subtract the band kernel from the
        # spectral-scalar ledger before comparing against the working-value bound.
        working = getproperty(achieved, class) - (class === :spectral_scalar ? 1 : 0)
        b = getproperty(bound, class)
        @test b <= working                        # a bound above the ledger is a bookkeeping error
        gap = working - b
        if gap > 0
          @test haskey(holders, class)            # every gap carries a named holder (decision 33)
        end
      end
      # The physical-vector count is exactly at its bound under the chart contract: the charts are
      # contract-live, and the substage registers + product peak alongside them.
      @test peak_liveness(ops_of(scalar)).physical_vector ==
            LEDGER_EXPECTED[(scheme, :TwoThirds, scalar)].physical_vector
    end
  end
end
