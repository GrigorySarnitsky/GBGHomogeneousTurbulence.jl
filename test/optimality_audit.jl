# Optimality audit — the floor discipline over the shared op model (ARCHITECTURE decision 35).
#
# The memory and compute audits MEASURE: they freeze what a run costs and fail when the number
# drifts. That certifies stability, not minimality — a frozen cell records what *is*, never what
# *should be*, and a cost with no lower bound held against it is unexamined rather than optimal.
# This file supplies the missing half. Every quantity it audits is held against a FLOOR — the cost
# the work cannot go below on physical grounds, not the cost the current operation set happens to
# reach — and every unit of residual distance must be CLAIMED by a named holder.
#
# The discipline is deliberately BIDIRECTIONAL, and the second direction is the point:
#
#   * no unclaimed gap  — a cell above its floor with no holder fails the suite, so a cost cannot be
#     absorbed silently;
#   * no stale holder   — a holder that no longer names a live gap ALSO fails, so a holder cannot
#     outlive the problem it describes. Retiring it is part of taking the win.
#
# And the rule decision 37 added, which the two above cannot enforce on their own: AN ASSUMPTION MAY
# NEVER BE AN INPUT TO THE BOUND IT IS MEASURED AGAINST. The liveness projection used to extend the
# observation charts' live range across the whole step and then report the result as a lower bound;
# since the ledger carries exactly those observables, `achieved == bound` was true by construction and the
# suite asserted it, hiding two physical vectors. When a projection needs an assumption to reach the
# achieved number, that assumption is a HOLDER, not a modelling input.
#
# A holder carries its disposition: `:FIX` (a local win, to be taken and the holder retired) or
# `:PF_RAISE` (a recorded request against GBGPeriodicFields — the gap is not ours to close).
#
# Three instruments here; the ledgers themselves stay in memory_audit.jl and compute_audit.jl.
#
#  1. THE PASS FLOOR — the compute audit holds achieved passes against the FUSION BOUND, the best a
#     perfectly fused schedule of the CURRENT operations could reach. That bound is not the floor:
#     it still charges a full field-scale read for every per-mode symbol (the de-alias mask, the
#     phase-shift translation kernels, |κ|² swept by each integrating-factor build) because those
#     symbols are materialized as N³ arrays. A symbol evaluated in register from the O(N) axis
#     multipliers moves no field-scale memory at all, so the floor drops them. The gap therefore
#     splits into two tiers with different owners:
#         achieved − bound   UNUSED FUSION        (kernel granularity)
#         bound   − floor    MATERIALIZED SYMBOLS (no lazy per-mode symbol apply exists)
#
#  2. THE FRAME FLOOR — the residency counterpart of instrument 1, over the read-only `FixedDomain`
#     the memory audit's frame ledger measures. Its floor is ZERO field-scale arrays, and here the
#     floor is not argued but DEMONSTRATED: each resident symbol is reconstructed from the O(N) axis
#     multipliers inside the test, so "this storage is materialization, not information" is a
#     checked property rather than a claim. Whatever remains is held by the same symbol holder as
#     the pass floor's second tier, and retires with it.
#
#  3. THE SYNCHRONIZATION LEDGER — the axis neither ledger can see. On GPU-primary code a reduction
#     whose result becomes a Julia scalar is a blocking device-to-host transfer: the queue drains,
#     and nothing launches until it lands. Footprint and traffic counts are blind to a barrier. The
#     floor is not zero in general — an adaptive timestep genuinely has to reach the host, because
#     Δt parameterizes every kernel of the step it opens — but it is far below what a step issues.
#
# Like the transform and pass ledgers, both instruments are STATIC projections: the synchronization
# sites are transcribed from the sources named beside them, under decision 33's standing obligation
# to re-derive on any change there. A CPU-backend run cannot observe a device barrier, so there is
# nothing to measure dynamically; what is checked here is the schedule, which is where the count is
# decided.

using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data, materialize_kernel
using Test

include("audit_ops.jl")


# ---------------------------------------------------------------- the holder register

struct Holder
  name::String
  disposition::Symbol      # :FIX — a local win, retire on taking it; :PF_RAISE — a backend request;
                           # :DESIGN — a user-adopted design cost, citing its decision
  what::String
end

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
  "A forcing reduces its band observable (or the noise variance) to a Julia scalar, branches on it, " *
  "and feeds it back to a kernel as a coefficient — a full round trip for a number that never " *
  "needed to leave the device. Closing it needs a reduction into a device-resident scalar and " *
  "kernels that accept one as a coefficient; the guard branch folds into the same kernel.")

const UNFUSED_QUADRATIC_REDUCTIONS = Holder(
  "UNFUSED QUADRATIC REDUCTIONS", :PF_RAISE,
  "The quadratic diagnostics a budgeted or warming run needs on the host — k and ε for the turnover " *
  "clock, the scalar variance for the stationarity detector — are independent sweeps of the same " *
  "state, one barrier each, where a single multi-output reduction would cost one barrier for all of " *
  "them. The derivative skewness does not join them: it is a cubic reduction over a different " *
  "operand and needs its own pass.")

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
  "one number for a schedule that varies with how the run is driven.")

const ALL_HOLDERS = (UNUSED_FUSION,
                     HOST_SIDE_FORCING_SCALARS, UNFUSED_QUADRATIC_REDUCTIONS,
                     UNIFORM_DEPOSIT_SCHEDULE)

# A `:FIX` holder is a local win recorded as OPEN, never as accepted. The set is frozen so one
# cannot be added silently, and taking the win means deleting the entry in the same commit.
# (Empty since CHART CONTRACT was taken, 2026-08-06.)
const OPEN_LOCAL_WINS = ()


# ---------------------------------------------------------------- the synchronization ledger

# One blocking device-to-host readback, and the floor it is held against.
struct Sync
  site::String             # the reduction whose scalar result crosses to the host
  floor::Int               # how many of these crossings are irreducible
  holder::Union{Holder, Nothing}
end

# Per-step synchronization sites, by configuration. Transcribed from:
#   deposit!                (src/Propagator.jl)    — the closing max-speed reduction, read back into the
#                                                    cache's host number (cfl_timestep then does
#                                                    scalar arithmetic on it — no crossing of its own)
#   StationarityCriterion   (src/SimulationRun.jl) — the packaged observation's ε and k reductions
#                                                    (a turnover-budget callback pays the same two)
#   project_forcing!          (src/Forcing.jl)       — VarianceRescaling's band observable, and the whole-field
#                                                    observable as well when `over = :total`
#   set_forcing_rate!       (src/Forcing.jl)       — ConstantPower's band observable → the amplitude
#   prepare_forcing!        (src/Forcing.jl)       — the stochastic forcing's noise variance → the rescale
#   _observe_and_test!      (src/SimulationRun.jl) — the stationarity detector's sampled signals: the
#                                                    derivative skewness, and the scalar variance when
#                                                    the scalar gate is on. ε is NOT counted twice
#                                                    here: the loop measures it once and hands it to
#                                                    both the detector and the turnover clock.
#
# The adaptive timestep is the one crossing with a nonzero floor: Δt is chosen on the host and
# parameterizes every kernel of the step it opens, so the reduction that sets it must land before
# anything launches. A fixed timestep needs none. Every other scalar here is consumed by a following
# device kernel and only visits the host because it is written as a Julia number.
# `stages` is the number of right-hand-side evaluations a step makes (3 for IFLowStorageRK3, 2 for
# IFRK2). It multiplies the readbacks of a STATE-DEPENDENT forcing, because such a forcing is
# evaluated at every stage rather than armed once per step. That is a deliberate cost, taken in
# exchange for the scheme's order: `ConstantPower` and `VarianceController` have rates that track the
# band observable, and folding a varying rate into the integrating factor integrates ∫A dt by a
# left-endpoint rectangle rule — measured collapsing IFLowStorageRK3 from 2.995 to 1.018. A
# steady-rate forcing (`Linear`) is unaffected: it is still armed once and costs no readback here.
function _syncs(; adaptive_dt::Bool, velocity_forcing::Symbol, scalar_forcing::Symbol = :none,
                  turnover_budget::Bool = false, monitor::Symbol = :none, stages::Int = 1)
  syncs = Sync[]
  # The closing deposit reduces the maximum speed on EVERY iteration (the uniform schedule): with an
  # adaptive timestep the crossing is the irreducible Δt choice; with a hand-fixed Δt its floor is
  # zero and the design holder claims it.
  push!(syncs, Sync("closing max-speed deposit", adaptive_dt ? 1 : 0,
                    adaptive_dt ? nothing : UNIFORM_DEPOSIT_SCHEDULE))
  if turnover_budget || monitor !== :none
    # One barrier serves the whole quadratic family if the reduction is fused; the first carries the
    # floor, the rest are the unfused remainder.
    push!(syncs, Sync("turnover ε", 1, nothing))
    push!(syncs, Sync("turnover k", 0, UNFUSED_QUADRATIC_REDUCTIONS))
  end
  if monitor !== :none
    # The skewness is a cubic reduction over the strain tensor — its own operand, its own barrier.
    push!(syncs, Sync("derivative skewness", 1, nothing))
    monitor === :skew_scalar &&
      push!(syncs, Sync("scalar variance", 0, UNFUSED_QUADRATIC_REDUCTIONS))
  end
  for (tag, slot) in ((velocity_forcing, :velocity), (scalar_forcing, :scalar))
    if tag === :band
      push!(syncs, Sync("VarianceRescaling band observable ($slot)", 0, HOST_SIDE_FORCING_SCALARS))
    elseif tag === :band_total
      push!(syncs, Sync("VarianceRescaling band observable ($slot)", 0, HOST_SIDE_FORCING_SCALARS))
      push!(syncs, Sync("VarianceRescaling total observable ($slot)", 0, HOST_SIDE_FORCING_SCALARS))
    elseif tag === :power
      for _ in 1:stages   # per STAGE: the rate tracks the band observable, so it cannot be frozen
        push!(syncs, Sync("ConstantPower band observable ($slot)", 0, HOST_SIDE_FORCING_SCALARS))
      end
    elseif tag === :controller
      for _ in 1:stages   # the controller reads the band variance AND the dissipation, each stage
        push!(syncs, Sync("VarianceController band variance ($slot)", 0, HOST_SIDE_FORCING_SCALARS))
        push!(syncs, Sync("VarianceController dissipation ($slot)", 0, HOST_SIDE_FORCING_SCALARS))
      end
    elseif tag === :ou
      push!(syncs, Sync("OU noise variance ($slot)", 0, HOST_SIDE_FORCING_SCALARS))
    end
  end
  return syncs
end

_achieved_syncs(syncs) = length(syncs)
_floor_syncs(syncs) = sum(s -> s.floor, syncs; init = 0)

# The frozen synchronization ledger: (achieved, floor) per step. The default run configuration is
# the first row — an adaptive timestep and a whole-field VarianceRescaling — and it issues three
# blocking readbacks per step where one is irreducible.
const SYNC_LEDGER = (
  (name = "default (adaptive dt, VarianceRescaling :total)",
   cfg = (; adaptive_dt = true, velocity_forcing = :band_total),                 achieved = 3, floor = 1),
  (name = "adaptive dt, VarianceRescaling :band",
   cfg = (; adaptive_dt = true, velocity_forcing = :band),                       achieved = 2, floor = 1),
  (name = "fixed dt, unforced",
   cfg = (; adaptive_dt = false, velocity_forcing = :none),                      achieved = 1, floor = 0),
  (name = "adaptive dt, unforced",
   cfg = (; adaptive_dt = true, velocity_forcing = :none),                       achieved = 1, floor = 1),
  (name = "adaptive dt, ConstantPower",
   cfg = (; adaptive_dt = true, velocity_forcing = :power),                      achieved = 2, floor = 1),
  (name = "adaptive dt, stochastic velocity + scalar",
   cfg = (; adaptive_dt = true, velocity_forcing = :ou, scalar_forcing = :ou),   achieved = 3, floor = 1),
  (name = "turnover-budgeted, VarianceRescaling :total",
   cfg = (; adaptive_dt = true, velocity_forcing = :band_total,
            turnover_budget = true),                                             achieved = 5, floor = 2),
  (name = "turnover-budgeted, fixed dt, unforced",
   cfg = (; adaptive_dt = false, velocity_forcing = :none, turnover_budget = true), achieved = 3, floor = 1),
  # The warm-up surface — past step!, where the stationarity detector samples. ε is measured once
  # per iteration and shared with the turnover clock, so it appears here once, not twice.
  (name = "warm-up sample, VarianceRescaling :total",
   cfg = (; adaptive_dt = true, velocity_forcing = :band_total, monitor = :skew),
   achieved = 6, floor = 3),
  (name = "warm-up sample, scalar gate, unforced",
   cfg = (; adaptive_dt = true, velocity_forcing = :none, monitor = :skew_scalar),
   achieved = 5, floor = 3),
)


@testset "optimality audit" begin

  @testset "the pass floor — two tiers, each claimed" begin
    # achieved ≥ bound ≥ floor everywhere, and each positive tier carries its holder. The floor is
    # the fused ideal with the per-mode symbols evaluated in register instead of swept from memory.
    for scheme in (:RK3, :RK2), dealiasing in DEALIASINGS, scalar in (false, true)
      ops = _ops(scheme, dealiasing, scalar)
      achieved = _passes(ops)
      bound    = _fusion_bound(ops)
      floor    = _fusion_bound(ops; materialize_symbols = false)
      for class in CLASSES
        a, b, f = getproperty(achieved, class), getproperty(bound, class), getproperty(floor, class)
        @test a >= b >= f
        # Every unit above the floor is claimed: the fusion tier by kernel granularity. The symbol
        # tier is CLOSED — the lazy per-mode apply landed (decisions 38/39), so the fused bound IS
        # the physical floor, and that closure is asserted as an equality rather than held open.
        @test a == b || UNUSED_FUSION in ALL_HOLDERS
        @test b == f
      end
    end
  end

  @testset "the symbol tier stays closed" begin
    # The retired MATERIALIZED_SYMBOLS holder's closure, held as an invariant: with every per-mode
    # symbol lazy, the fused bound equals the physical floor in every class and every cell, and the
    # real-spectral-scalar class — once entirely |κ|² swept per factor build — is empty outright. A
    # future op that reads a field-scale configuration array reopens the tier and must bring a new
    # holder with it.
    for scheme in (:RK3, :RK2), dealiasing in DEALIASINGS, scalar in (false, true)
      ops = _ops(scheme, dealiasing, scalar)
      @test _fusion_bound(ops) == _fusion_bound(ops; materialize_symbols = false)
      @test _passes(ops).real_spectral_scalar == 0
    end
  end

  @testset "the frame floor — zero field-scale arrays, ACHIEVED; the lazy symbols pinned" begin
    # The frame's floor is zero field-scale arrays, and since the PF adoption (2026-08-05, PF
    # decisions 50/51/60) it is ACHIEVED rather than demonstrated: |κ|², the Dirichlet weight, and
    # every strategy's de-alias mask are lazy radial kernels evaluated per mode from the O(N) axis
    # multipliers, and the PhaseShift translation kernels are per-axis factors. What this testset
    # once verified by reconstructing the resident arrays it now verifies the other way round: the
    # lazy symbols, materialized on demand, must equal the explicit reconstruction — the correctness
    # pin that the compression changed storage, never values. If a future symbol enters the frame
    # that is genuinely N³ of information, the walk below stops being zero and the floor must move.
    N = 8
    for strategy in (TwoThirds(), HouLi(), PhaseShift())
      domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, dealiasing = strategy, element_type = Float64, array_type = Array)
      m = domain.multipliers

      # (a) The frame holds nothing at field scale — the achieved floor, per strategy.
      @test all(class -> getproperty(_counts((domain,), N), class) == 0, CLASSES)

      # (b) The lazy |κ|² symbol equals the outer sum of the three axis vectors — the
      #     reconstruction the stored array once pinned, now pinning the kernel's evaluation.
      κ²_kernel = field_data(materialize_kernel(domain.squared_wavenumber_kernel).field)
      κ² = [m.squared_wavenumber_1[i] + m.squared_wavenumber_2[j] + m.squared_wavenumber_3[k]
            for i in axes(κ²_kernel, 1), j in axes(κ²_kernel, 2), k in axes(κ²_kernel, 3)]
      @test κ²_kernel == complex.(κ²)

      # (c) The de-alias mask is radial — constant on the level sets of |κ|² — for every strategy,
      #     sharp, smooth, or spherical alike: the property that makes it a symbol of one scalar
      #     argument, evaluable in register with no stored field.
      mask = field_data(materialize_kernel(domain.dealias).field)
      @test all(iszero, imag.(mask))                    # real-valued content in a complex container
      by_level = Dict{Float64, Float64}()
      radial = true
      for i in eachindex(mask, κ²)
        level, v = κ²[i], real(mask[i])
        haskey(by_level, level) ? (radial &= by_level[level] ≈ v) : (by_level[level] = v)
      end
      @test radial
      @test length(by_level) < length(mask)             # non-vacuous: levels genuinely collapse modes
    end

    # The symbol holder is retired in full (decisions 38/39): residency closed here, traffic closed
    # by the fused exponential — the "symbol tier stays closed" testset holds the equality.
  end

  @testset "no stale holder — every holder still names a live gap" begin
    # The direction that keeps the register honest. A holder whose gap has been closed everywhere
    # must be retired in the commit that closes it; leaving it would let a solved problem go on
    # looking like an accepted cost.
    cells = [(s, d, sc) for s in (:RK3, :RK2) for d in DEALIASINGS for sc in (false, true)]
    fusion_live = false
    for (scheme, dealiasing, scalar) in cells
      ops = _ops(scheme, dealiasing, scalar)
      achieved, bound = _passes(ops), _fusion_bound(ops)
      for class in CLASSES
        getproperty(achieved, class) > getproperty(bound, class) && (fusion_live = true)
      end
    end
    @test fusion_live                       # else retire UNUSED_FUSION
    # (MATERIALIZED_SYMBOLS retired 2026-08-06 — its former liveness check is now the
    # "symbol tier stays closed" equality above.)

    # (CHART_CONTRACT retired 2026-08-06: the closing refresh landed, and the memory audit now
    # asserts achieved == bound in every unforced cell — the equality this register demanded.)

    sync_holders = Set{String}()
    for row in SYNC_LEDGER, s in _syncs(; row.cfg...)
      s.holder === nothing || push!(sync_holders, s.holder.name)
    end
    @test HOST_SIDE_FORCING_SCALARS.name in sync_holders
    @test UNFUSED_QUADRATIC_REDUCTIONS.name in sync_holders
    @test UNIFORM_DEPOSIT_SCHEDULE.name in sync_holders
  end

  @testset "retired holders stay retired" begin
    # Living proof that the discipline above does its job — these two gaps were recorded costs that
    # no bound had ever been held against, and both are now zero. A regression here would mean a
    # closed gap has reopened without a holder being written for it.
    #
    domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π, dealiasing = TwoThirds(), element_type = Float64, array_type = Array)

    # (a) Tracers cost nothing at field scale: the start-of-step velocity is interpolated onto the
    #     tracers before the step rather than retained as a field, so nothing the instrument owns
    #     scales with the grid and the run holds no second velocity field for it.
    tracer_count = 8
    sim = Simulation(domain; viscosity = 0.1, number_of_particles = tracer_count)
    @test :tracers in fieldnames(typeof(sim))                    # the check below is not vacuous
    @test !(:tracer_velocity in fieldnames(typeof(sim)))
    owned = (getfield(sim.tracers, f) for f in fieldnames(typeof(sim.tracers)))
    @test all(a -> !(a isa AbstractArray) || length(a) <= 3 * tracer_count, owned)
    # …including the point-value buffers, which is where a retained field would have to hide: the
    # recorded start-of-step velocity is M interpolated vectors, read back through the public readout.
    @test size(particle_positions(sim.tracers)) == (tracer_count, 3)
    @test size(particle_velocities(sim.cache)) == (tracer_count, 3)

    # (b) An unforced field carries no linear-rate array: the storage tracks the physics.
    unforced = ResolvedGenerator(domain, FlowConditions(; viscosity = 0.1, schmidt = 1.0,
                   velocity_forcing = NoForcing(), scalar_forcing = NoForcing()); scalar = true)
    @test unforced.velocity_rate === nothing && unforced.scalar_rate === nothing
  end

  @testset "the synchronization ledger — the frozen count and its floor" begin
    for row in SYNC_LEDGER
      syncs = _syncs(; row.cfg...)
      @test _achieved_syncs(syncs) == row.achieved
      @test _floor_syncs(syncs) == row.floor
      @test row.achieved >= row.floor
      # every crossing above its floor is claimed
      for s in syncs
        @test s.floor > 0 || (s.holder !== nothing && s.holder in ALL_HOLDERS)
      end
    end
  end

  @testset "the synchronization floor is argued, not assumed" begin
    # An adaptive timestep is the ONE irreducible crossing: Δt is chosen on the host from the speed
    # bound and parameterizes every kernel of the step it opens. Fix the timestep and the floor is
    # zero — the property that makes this a floor rather than a frozen number.
    @test _floor_syncs(_syncs(; adaptive_dt = true, velocity_forcing = :none)) == 1
    @test _floor_syncs(_syncs(; adaptive_dt = false, velocity_forcing = :none)) == 0

    # No forcing raises the floor: a forcing's scalar is consumed by the next device kernel.
    for tag in (:band, :band_total, :power, :ou)
      @test _floor_syncs(_syncs(; adaptive_dt = false, velocity_forcing = tag)) == 0
      @test _achieved_syncs(_syncs(; adaptive_dt = false, velocity_forcing = tag)) > 0
    end

    # The default configuration pays three crossings for one — the headline of this axis.
    default = _syncs(; adaptive_dt = true, velocity_forcing = :band_total)
    @test _achieved_syncs(default) == 3 && _floor_syncs(default) == 1
  end

  @testset "every holder is dispositioned and described" begin
    for h in ALL_HOLDERS
      @test h.disposition in (:FIX, :PF_RAISE, :DESIGN)
      @test !isempty(h.name) && length(h.what) > 40      # a holder names the cause, not just a label
    end
    # A `:DESIGN` holder must cite the decision that adopted the cost — it records a user choice,
    # never a silent acceptance.
    for h in ALL_HOLDERS
      h.disposition === :DESIGN && @test occursin("decision", h.what)
    end
    # A `:FIX` holder is a local win left open, and the frozen list is what stops it becoming an
    # accepted cost by default: adding one requires editing OPEN_LOCAL_WINS, and taking the win
    # requires deleting the entry in the same commit.
    @test Set(h.name for h in ALL_HOLDERS if h.disposition === :FIX) == Set(OPEN_LOCAL_WINS)
  end
end
