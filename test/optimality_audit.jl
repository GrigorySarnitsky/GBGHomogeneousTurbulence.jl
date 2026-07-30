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
# A holder carries its disposition: `:FIX` (a local win, to be taken and the holder retired) or
# `:PF_RAISE` (a recorded request against GBGPeriodicFields — the gap is not ours to close).
#
# Two instruments here; the ledgers themselves stay in memory_audit.jl and compute_audit.jl.
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
#  2. THE SYNCHRONIZATION LEDGER — the axis neither ledger can see. On GPU-primary code a reduction
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
using Test

include("audit_ops.jl")


# ---------------------------------------------------------------- the holder register

struct Holder
  name::String
  disposition::Symbol      # :FIX — a local win, retire on taking it; :PF_RAISE — a backend request
  what::String
end

const UNUSED_FUSION = Holder(
  "UNFUSED STAGE PIPELINE", :PF_RAISE,
  "Leray → dealias → accumulate → update → factor-rotate run as one kernel per operation where one " *
  "fused per-mode kernel could read (product, state) and write (state, accumulator) once. The " *
  "passes between those boundaries are pure intermediate traffic.")

const MATERIALIZED_SYMBOLS = Holder(
  "MATERIALIZED PER-MODE SYMBOLS", :PF_RAISE,
  "The de-alias mask, the phase-shift translation kernels, and |κ|² are stored as N³ arrays and " *
  "swept once per use, though each is a closed-form function of the O(N) axis multipliers. A lazy " *
  "per-mode symbol apply would evaluate them in register and move no field-scale memory.")

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

const ALL_HOLDERS = (UNUSED_FUSION, MATERIALIZED_SYMBOLS,
                     HOST_SIDE_FORCING_SCALARS, UNFUSED_QUADRATIC_REDUCTIONS)


# ---------------------------------------------------------------- the synchronization ledger

# One blocking device-to-host readback, and the floor it is held against.
struct Sync
  site::String             # the reduction whose scalar result crosses to the host
  floor::Int               # how many of these crossings are irreducible
  holder::Union{Holder, Nothing}
end

# Per-step synchronization sites, by configuration. Transcribed from:
#   cfl_timestep            (src/SimulationRun.jl) — Float64(max_speed(u)), then isfinite / > 0 on the host
#   _turnover_time          (src/SimulationRun.jl) — dissipation and kinetic_energy, then ε > 0 and k/ε
#   apply_forcing!          (src/Forcing.jl)       — BandRescaling's band observable, and the whole-field
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
function _syncs(; adaptive_dt::Bool, velocity_forcing::Symbol, scalar_forcing::Symbol = :none,
                  turnover_budget::Bool = false, monitor::Symbol = :none)
  syncs = Sync[]
  adaptive_dt && push!(syncs, Sync("cfl max_speed", 1, nothing))
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
      push!(syncs, Sync("BandRescaling band observable ($slot)", 0, HOST_SIDE_FORCING_SCALARS))
    elseif tag === :band_total
      push!(syncs, Sync("BandRescaling band observable ($slot)", 0, HOST_SIDE_FORCING_SCALARS))
      push!(syncs, Sync("BandRescaling total observable ($slot)", 0, HOST_SIDE_FORCING_SCALARS))
    elseif tag === :power
      push!(syncs, Sync("ConstantPower band observable ($slot)", 0, HOST_SIDE_FORCING_SCALARS))
    elseif tag === :ou
      push!(syncs, Sync("OU noise variance ($slot)", 0, HOST_SIDE_FORCING_SCALARS))
    end
  end
  return syncs
end

_achieved_syncs(syncs) = length(syncs)
_floor_syncs(syncs) = sum(s -> s.floor, syncs; init = 0)

# The frozen synchronization ledger: (achieved, floor) per step. The default run configuration is
# the first row — an adaptive timestep and a whole-field BandRescaling — and it issues three
# blocking readbacks per step where one is irreducible.
const SYNC_LEDGER = (
  (name = "default (adaptive dt, BandRescaling :total)",
   cfg = (; adaptive_dt = true, velocity_forcing = :band_total),                 achieved = 3, floor = 1),
  (name = "adaptive dt, BandRescaling :band",
   cfg = (; adaptive_dt = true, velocity_forcing = :band),                       achieved = 2, floor = 1),
  (name = "fixed dt, unforced",
   cfg = (; adaptive_dt = false, velocity_forcing = :none),                      achieved = 0, floor = 0),
  (name = "adaptive dt, unforced",
   cfg = (; adaptive_dt = true, velocity_forcing = :none),                       achieved = 1, floor = 1),
  (name = "adaptive dt, ConstantPower",
   cfg = (; adaptive_dt = true, velocity_forcing = :power),                      achieved = 2, floor = 1),
  (name = "adaptive dt, stochastic velocity + scalar",
   cfg = (; adaptive_dt = true, velocity_forcing = :ou, scalar_forcing = :ou),   achieved = 3, floor = 1),
  (name = "turnover-budgeted, BandRescaling :total",
   cfg = (; adaptive_dt = true, velocity_forcing = :band_total,
            turnover_budget = true),                                             achieved = 5, floor = 2),
  (name = "turnover-budgeted, fixed dt, unforced",
   cfg = (; adaptive_dt = false, velocity_forcing = :none, turnover_budget = true), achieved = 2, floor = 1),
  # The warm-up surface — past step!, where the stationarity detector samples. ε is measured once
  # per iteration and shared with the turnover clock, so it appears here once, not twice.
  (name = "warm-up sample, BandRescaling :total",
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
        # Every unit above the floor is claimed: the fusion tier by kernel granularity, the symbol
        # tier by the absent lazy per-mode apply. Deleting a holder from the register while its gap
        # is still open fails here — an unclaimed gap is a silent cost.
        @test a == b || UNUSED_FUSION in ALL_HOLDERS
        @test b == f || MATERIALIZED_SYMBOLS in ALL_HOLDERS
      end
    end
  end

  @testset "the two tiers have different owners" begin
    # The decomposition is informative, not decorative: it says WHICH change closes WHICH cost.
    # Spectral-vector traffic is entirely a fusion question — its bound already sits at its floor,
    # so no lazy symbol would help it. The real-spectral-scalar class is the mirror image: achieved sits AT
    # the fused bound (nothing to fuse) and the whole of it is |κ|² swept once per factor build, so
    # a lazy symbol deletes the class outright. Losing either property means the holders above have
    # stopped describing the code.
    for scheme in (:RK3, :RK2), dealiasing in DEALIASINGS, scalar in (false, true)
      ops = _ops(scheme, dealiasing, scalar)
      bound = _fusion_bound(ops)
      floor = _fusion_bound(ops; materialize_symbols = false)
      @test bound.spectral_vector == floor.spectral_vector      # no materialized symbol in this class
      @test floor.real_spectral_scalar == 0                                     # …and this class is nothing else
      @test _passes(ops).real_spectral_scalar == bound.real_spectral_scalar                     # already perfectly fused, still N³ traffic
    end
  end

  @testset "no stale holder — every holder still names a live gap" begin
    # The direction that keeps the register honest. A holder whose gap has been closed everywhere
    # must be retired in the commit that closes it; leaving it would let a solved problem go on
    # looking like an accepted cost.
    cells = [(s, d, sc) for s in (:RK3, :RK2) for d in DEALIASINGS for sc in (false, true)]
    fusion_live = false
    symbols_live = false
    for (scheme, dealiasing, scalar) in cells
      ops = _ops(scheme, dealiasing, scalar)
      achieved, bound = _passes(ops), _fusion_bound(ops)
      floor = _fusion_bound(ops; materialize_symbols = false)
      for class in CLASSES
        getproperty(achieved, class) > getproperty(bound, class) && (fusion_live = true)
        getproperty(bound, class) > getproperty(floor, class) && (symbols_live = true)
      end
    end
    @test fusion_live                       # else retire UNUSED_FUSION
    @test symbols_live                      # else retire MATERIALIZED_SYMBOLS

    sync_holders = Set{String}()
    for row in SYNC_LEDGER, s in _syncs(; row.cfg...)
      s.holder === nothing || push!(sync_holders, s.holder.name)
    end
    @test HOST_SIDE_FORCING_SCALARS.name in sync_holders
    @test UNFUSED_QUADRATIC_REDUCTIONS.name in sync_holders
  end

  @testset "retired holders stay retired" begin
    # Living proof that the discipline above does its job — these two gaps were recorded costs that
    # no bound had ever been held against, and both are now zero. A regression here would mean a
    # closed gap has reopened without a holder being written for it.
    #
    domain = FixedDomain(8, 2π; dealiasing = TwoThirds(), element_type = Float64, array_type = Array)

    # (a) Tracers cost nothing at field scale: the start-of-step velocity is interpolated onto the
    #     tracers before the step rather than retained as a field, so nothing the instrument owns
    #     scales with the grid and the run holds no second velocity field for it.
    tracer_count = 8
    sim = Simulation(domain; viscosity = 0.1, number_of_tracers = tracer_count)
    @test :tracers in fieldnames(typeof(sim))                    # the check below is not vacuous
    @test !(:tracer_velocity in fieldnames(typeof(sim)))
    owned = (getfield(sim.tracers, f) for f in fieldnames(typeof(sim.tracers)))
    @test all(a -> !(a isa AbstractArray) || length(a) <= 3 * tracer_count, owned)
    # …including the point-value buffers, which is where a retained field would have to hide: the
    # recorded start-of-step velocity is M interpolated vectors, read back through the public readout.
    @test size(tracer_positions(sim.tracers)) == (tracer_count, 3)
    @test size(tracer_velocities(sim.tracers)) == (tracer_count, 3)

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
      @test h.disposition in (:FIX, :PF_RAISE)
      @test !isempty(h.name) && length(h.what) > 40      # a holder names the cause, not just a label
    end
    # Nothing in the register is a local win today: every live gap is a backend capability question.
    # A :FIX holder appearing here is the signal to take it and retire it, not to freeze it.
    @test all(h -> h.disposition === :PF_RAISE, ALL_HOLDERS)
  end
end
