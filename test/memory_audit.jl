# Memory audit — the enforcement of "minimal footprint" (ARCHITECTURE §9 invariant 4, decision 33).
#
# Three instruments, all run in the standard suite:
#
#  1. THE WORKING-SET LEDGER — a reflective walk over every resident field-sized buffer a run
#     EVOLVES, counted per shape class. The full combination space is a product of five axes —
#     scheme × dealiasing × scalar × (velocity forcing × scalar forcing) × tracers — and the
#     footprint is COMPOSITIONAL: the frozen spec is the unforced, tracer-free BASE table (12 cells)
#     plus a per-forcing DELTA table and a tracer DELTA, and an exhaustive sweep over the whole
#     product (~360 combinations) asserts measured = base + deltas, cell by cell. Adding or removing
#     a buffer anywhere fails the suite: a footprint change must be a conscious, recorded decision,
#     never a drive-by. (The particle-integrator axis has one point today — the Heun pusher — so it
#     enters as on/off; precision, backend, and the interpolation scheme change bytes, never counts.)
#
#  2. THE FRAME LEDGER — the same walk over what a run does NOT evolve: the read-only `FixedDomain`
#     and its per-mode symbols. This storage sat outside every ledger until 2026-07-30 and is not
#     small (322.5 MiB at 256³ / Float64, ~8 % on top of the default working set), so the audit
#     claimed to bound residency while measuring only part of it. The two ledgers are kept apart
#     because they answer different questions — the working set is what the schedule needs live, the
#     frame is what the discretization costs to have precomputed — and a COMPLETENESS test then
#     requires their sum to account for every field-scale array a live `Simulation` can reach, so
#     nothing can fall between them again.
#
#  3. THE LIVENESS AUDIT — the step as a straight-line program: each op's reads and writes, taken
#     from the step! bodies and the generator protocol, give every value a live range; the peak
#     number of simultaneously live values per shape class is the LOWER BOUND on the buffers the
#     implemented operation order needs. The gap register records achieved − bound per class with a
#     NAMED HOLDER for every nonzero gap (an ownership boundary, a survive-the-step contract, a
#     PF-kernel granularity). A gap without a holder is an optimization left on the table, and the
#     test fails; a bound crossing achieved is a bookkeeping error. Re-derive the op lists whenever
#     a step! body or the generator protocol changes — the ledger failing is the reminder.
#
# Shape classes (Float64 sizes per unit, in units of N³ reals): spectral_vector ≈ 3·(1+1/N),
# physical_vector = 3, spectral_scalar ≈ 1+1/N, physical_scalar = 1,
# real_spectral_scalar ≈ ½·(1+1/N) — the shape |κ|², the de-alias mask and a forcing rate all share.

using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Forcing: StochasticOU   # archived (un-exported); audited for the re-add
using GBGPeriodicFields: field_data, CatmullRom
using Random
using Test


# The shared op model (CLASSES, the class decomposition and its reflective counter, Op, the step op
# lists, peak_liveness) — one source of truth for this audit's residency and liveness projections
# and test/compute_audit.jl's cost projection.
include("audit_ops.jl")

const N_AUDIT = 8


# ---------------------------------------------------------------- the working-set ledger

# Build one combination's working set and measure it. A stateful forcing (the OU) is materialized by
# one prepare_forcing! call, since its state and noise scratch allocate lazily on first use.
function ledger(domain, scheme, scalar::Bool, velocity_forcing, scalar_forcing, tracers::Bool)
  conditions = FlowConditions(; viscosity = 0.1, schmidt = 1.0, velocity_forcing, scalar_forcing)
  state = ResolvedFields(domain; scalar)
  velocity_forcing isa StochasticOU && prepare_forcing!(velocity_forcing, state.velocity, domain, 0.01)
  scalar_forcing isa StochasticOU && prepare_forcing!(scalar_forcing, state.scalar, domain, 0.01)
  owners = Any[state, ObservablesCache(domain; scalar), ResolvedGenerator(domain, conditions; scalar),
               allocate_buffers(scheme, domain; scalar)]
  if tracers
    push!(owners, Tracers(domain, 4; scheme = CatmullRom, rng = MersenneTwister(1)))
  end
  return _counts(owners, N_AUDIT)
end

# The frozen BASE table — unforced (NoForcing/NoForcing), tracer-free. A deliberate footprint change
# updates this spec (and, for a structural change, the op lists below) in the same commit, citing the
# decision. Columns: spectral_vector, physical_vector, spectral_scalar, physical_scalar,
# real_spectral_scalar.
# Re-frozen 2026-08-06 (decisions 40 and 41 — the deposit-driven cache, then the in-place quadratic
# products: the Lamb vector forms over the vorticity register and the scalar flux over the
# velocity's, so `product_physical` is deleted outright, −1 pv in every cell on top of the merge):
# the cache's chart slots ARE the step's substage recovery registers, so the two physical vectors
# the old IntegratorBuffers carried beside the charts are gone (−2 pv in every cell, 768 MiB at
# 256³ / Float64 — exactly the gap decision 37 uncovered); the cache's spectral scratch is gone
# (−1 sv — the closing and substage recoveries write through a dead stage register); the scalar's
# copy register is gone (−1 ss) and its physical field register IS the scalar chart now (φ moved
# from the buffers to the cache, net zero). The PhaseShift cells still carry the displaced-
# evaluation scratch on top (+1 sv, +2 pv; scalar +2 ss +1 ps).
# The real_spectral_scalar column is ZERO throughout, and the zero is the point (2026-07-28,
# decision 35): a rate
# array exists only where a forcing declares `uses_linear_rate`, so an unforced field — and the
# default configuration, whose BandRescaling is a post-step projection — carries none. It used to
# read 1 (2 with a scalar) for arrays that were never written and never read.
const BASE = Dict(
  (:RK3, :TwoThirds,  false) => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK3, :TwoThirds,  true)  => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 3, physical_scalar = 1, real_spectral_scalar = 0),
  (:RK3, :HouLi,      false) => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK3, :HouLi,      true)  => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 3, physical_scalar = 1, real_spectral_scalar = 0),
  (:RK3, :PhaseShift, false) => (spectral_vector = 5, physical_vector = 4, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK3, :PhaseShift, true)  => (spectral_vector = 5, physical_vector = 4, spectral_scalar = 5, physical_scalar = 2, real_spectral_scalar = 0),
  (:RK2, :TwoThirds,  false) => (spectral_vector = 5, physical_vector = 2, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK2, :TwoThirds,  true)  => (spectral_vector = 5, physical_vector = 2, spectral_scalar = 4, physical_scalar = 1, real_spectral_scalar = 0),
  (:RK2, :HouLi,      false) => (spectral_vector = 5, physical_vector = 2, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK2, :HouLi,      true)  => (spectral_vector = 5, physical_vector = 2, spectral_scalar = 4, physical_scalar = 1, real_spectral_scalar = 0),
  (:RK2, :PhaseShift, false) => (spectral_vector = 6, physical_vector = 4, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK2, :PhaseShift, true)  => (spectral_vector = 6, physical_vector = 4, spectral_scalar = 6, physical_scalar = 2, real_spectral_scalar = 0),
)
# (History: the PhaseShift displaced-velocity register was once tried on the generator's spent
# product scratch and REVERTED (2026-07-31) — the then-guarded `cross!` allocated per stage; the
# alias-safe kernel has since landed PF-side and the retake is the Lamb-into-vorticity candidate of
# the cache strand. PF adoption 2026-08-05/06: the stored translation kernels and the
# integrating-factor register left the cells (PF decision 50, IT decision 39).)

# The frozen forcing DELTAS, per slot. Every band kernel is now a lazy radial symbol (PF adoption,
# 2026-08-05 — PF decision 51), so a band-selecting forcing stores no field-scale kernel; the OU's
# state and noise scratch take the forced field's shape.
_forcing_delta(tag, slot) =
  tag === :none  ? ZERO :
  tag === :band  ? ZERO :
  tag === :linear ? (spectral_vector = 0, physical_vector = 0, spectral_scalar = 1, physical_scalar = 0, real_spectral_scalar = 1) :
  tag === :power ? (spectral_vector = 0, physical_vector = 0, spectral_scalar = 1, physical_scalar = 0, real_spectral_scalar = 1) :
  slot === :velocity ? (spectral_vector = 2, physical_vector = 1, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0) :
                       (spectral_vector = 0, physical_vector = 0, spectral_scalar = 2, physical_scalar = 1, real_spectral_scalar = 0)
# (:ou — in the forced field's shape, the OU state f̂ and the two noise buffers; its band is lazy.)
# Each rate-driven forcing carries the generator's rate array — which now exists precisely because
# such a forcing is present, so the storage appears on the axis that causes it instead of
# unconditionally in the base. `Linear` and `ConstantPower` each add a materialized real band
# indicator on top: with the band kernel lazy there are no stored coefficients for the rate fill to
# read, so the indicator is built once at construction (half the complex field the stored band once
# was; the pre-adoption ConstantPower read its indicator lazily from that stored kernel instead).
# The rate itself is a scalar FIELD in spectral representation since decision 39 — the complex
# container the fused exponential's per-mode offset takes — so a rate-armed forcing shows one
# spectral scalar (the rate) plus one real array (the indicator/mask).

# Tracers cost NOTHING at field scale: everything they hold is O(M) — positions, the Heun predictor,
# and the two interpolated point-value sets. The start-of-step endpoint velocity is recorded onto the
# tracers as M interpolated vectors rather than retained as a field, so a tracked run adds no resident
# field to an untracked one. This zero is the assertion, not a placeholder.
const TRACER_DELTA = ZERO

# There is no observables axis any more (decision 40): the cache's contents are automatic — exactly
# what the configuration's iteration computes, materializes, and leaves at the iteration's end — so the
# only degree of freedom it carries is the scalar slot, which follows the run's `scalar` axis.

_build_forcing(tag, domain) =
  tag === :none  ? NoForcing() :
  tag === :band  ? BandRescaling(domain; target = 0.5) :
  tag === :linear ? Linear(domain; rate = 0.1) :
  tag === :power ? ConstantPower(domain; target = 0.1) :
  StochasticOU(domain; variance = 0.1, correlation_time = 0.5, seed = 1)

_scheme(tag) = tag === :RK3 ? IFLowStorageRK3() : IFRK2()
const FORCING_TAGS = (:none, :band, :linear, :power, :ou)


# ---------------------------------------------------------------- the frame ledger

# The read-only frame the run lives on — the `FixedDomain` — measured with the same reflective walk.
# It holds NO field-scale array: every per-mode symbol it once stored — |κ|² as a real array, |κ|²
# as the Dirichlet-energy weight, and the de-alias mask — is now a lazy kernel evaluated per mode
# from the O(N) per-axis multipliers (PF adoption, 2026-08-05: `RadialKernel`, PF decisions 51/60).
# The frame's zero floor, which optimality_audit.jl once held as a DEMONSTRATED reconstruction
# against the resident arrays (decision 36), is thereby ACHIEVED: 322.5 MiB at 256³ / Float64
# retired, |κ|² no longer resident twice in two element types.
#
# The frame is invariant across the dealiasing strategy and the precision, and that invariance is
# part of the assertion: every strategy's mask is a symbol whatever its profile (sharp, smooth, or
# spherical), and no strategy stores one.
const FRAME = (spectral_vector = 0, physical_vector = 0, spectral_scalar = 0,
               physical_scalar = 0, real_spectral_scalar = 0)

# Named exclusion, so it is recorded rather than merely absent: a backend FFT plan's work area is
# owned by the vendor library (FFTW, rocFFT, cuFFT), reachable from no Julia field, and observable
# only by a device query. Like the O(N) axis multipliers and shell vectors it is outside both
# ledgers — but unlike them it is not small on GPU, so it belongs on the benchmark-side empirics
# (decision 33's scope statement) rather than in this static projection.
frame_ledger(domain) = _counts((domain,), N_AUDIT)


# ---------------------------------------------------------------- the liveness audit

# The op lists (rk3_ops / rk2_ops and their builders) and peak_liveness live in audit_ops.jl —
# shared with the compute audit; re-derive them there whenever a step! body or the generator
# protocol changes.

# The gap register: achieved working buffers (kernels, masks, and rate arrays are configuration, not
# working values, and are excluded on both sides) minus the liveness bound, with a named holder for
# every nonzero gap. An unclaimed gap is a finding, and the test fails; a holder left behind after
# its gap closes fails too (the register works in both directions).
#
# Retired 2026-08-06 (decision 40 — the deposit-driven cache), all three in the same commit that
# closed their gaps:
#   CHART CONTRACT   — the charts survived the step BESIDE separate substage registers; the slot=
#                      register merge made the charts the registers, closing exactly the two
#                      physical vectors decision 37 uncovered (768 MiB at 256³ / Float64).
#   OWNERSHIP        — the cache's recovery scratch sat across a kept seam from the generator's
#                      registers; the scratch is deleted (recoveries write through a dead stage
#                      register), so there is no boundary left to hold a gap open.
#   SCALAR REGISTERS — the scalar's copy register could share a slot; it is deleted outright.
#   (SHARED FACTOR was retired 2026-08-06 with decision 39.)
# Every unforced cell now sits AT its liveness bound in every class. The one remaining gap is the
# archived OU's spectral noise: it could alias the generator's spectral registers but lives on the
# forcing across an ownership boundary — one spectral vector. (Its physical twin closed with
# decision 41: there is no physical product register left for the noise to alias, so the bound rose
# to meet the ledger and the holder retired.)
const GAP_HOLDERS = Dict(
  (:RK3_OU, false) => Dict(:spectral_vector => "OWNERSHIP (OU noise ↔ nonlinear/product)"),
)



# ---------------------------------------------------------------- the episode ledger
#
# Peak memory = resident + the transients of whatever episode is running. The hot loop is
# allocation-free (the step!/advance! guards), so during production stepping peak equals the resident
# ledger above. Outside it, the transient episodes are few, sequential (single-threaded — episodes
# never overlap, so the run-phase peak is resident + the LARGEST episode), and frozen here in units
# of N³ reals, measured mechanically via @allocated (warmed calls; generous bands for library drift).
# Attribution (re-measured 2026-08-05 at the PF adoption; the 2026-07-18 numbers in parentheses):
#   seeding (velocity)    ≈ 6.1 (10.3) — noise vector 3.0 + host randn staging 3.1. The envelope
#                                  (was 1.06) is now a lazy radial kernel, and the ALIASED
#                                  helmholtz_projection!(û, û, …) transient (was 3.2) is gone — the
#                                  raise to GBGPeriodicFields landed as its guard-free one-pass
#                                  projection. Construction-time only.
#   seeding (scalar)      ≈ 2.1 (3.1) — noise scalar 1.0 + host randn staging 1.0; envelope lazy.
#   derivative_skewness   ≈ 18.6 (19.6) — spectral tensor 9 × 1.06 + physical tensor 9; the det
#                                  field (was 1) is gone — ⟨det S⟩ is the fused mapped mean now: the
#                                  DOMINANT episode (~ +55 % over the default resident set), and ON
#                                  BY DEFAULT during warmup!'s skewness gate — the binding device
#                                  peak of a default warm-up at the largest N that fits. Invariant
#                                  4's per-call-diagnostic trade, priced. (PF stores full 9-component
#                                  tensors; symmetric 6-component storage is the recorded reduction.)
#   energy_spectrum       ≈ 0.0 (1.6) — GBGPeriodicFields fused its radial_spectrum staging into the
#                                  binning kernel (its decision 34); only the O(N) shell vectors
#                                  remain. integral_scale and flow_parameters inherit the zero.
# The archived StochasticOU's prepare! projects its noise ALIASED; with the projection now
# guard-free that path should be allocation-free too — re-measure on the de-archival gate.
const EPISODE_UNITS = [
  ("seed velocity",       6.1, 1.0),
  ("seed scalar",         2.1, 0.5),
  ("derivative_skewness", 18.6, 1.0),
  ("energy_spectrum",     0.0, 0.2),
  ("integral_scale",      0.0, 0.2),
  ("flow_parameters",     0.0, 0.2),
]


@testset "memory audit" begin
  domains = Dict(tag => FixedDomain(grid_points_per_axis = N_AUDIT, side_length = 2π, element_type = Float64,
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

  @testset "frame ledger — the frozen per-mode symbols, invariant in strategy and precision" begin
    for tag in (:TwoThirds, :HouLi, :PhaseShift), T in (Float64, Float32)
      domain = FixedDomain(grid_points_per_axis = N_AUDIT, side_length = 2π, element_type = T, array_type = Array,
                           dealiasing = tag === :TwoThirds ? TwoThirds() :
                                        tag === :HouLi ? HouLi() : PhaseShift())
      @test frame_ledger(domain) == FRAME
    end
    # The frame holds nothing at field scale in ANY class — the zero floor achieved, not merely
    # demonstrated (see the FRAME comment above). Stated positively so the all-zero table cannot be
    # read as unfilled cells.
    @test all(class -> getproperty(FRAME, class) == 0, keys(FRAME))

    # The phase-shift translation kernels are frame-natured — built once from the grid spacing,
    # never written again — and are now per-axis `SeparableKernel`s (three O(N) factors each, PF
    # decision 50), below field scale on either ledger: the PhaseShift base cells differ from a mask
    # strategy's spectral scalars only by the displaced-evaluation scratch, which a velocity-only
    # run does not carry.
    @test BASE[(:RK3, :PhaseShift, false)].spectral_scalar ==
          BASE[(:RK3, :TwoThirds, false)].spectral_scalar
  end

  @testset "no field-scale storage escapes both ledgers" begin
    # The closure that keeps the frame hole shut. Walk a whole live `Simulation` — frame, state,
    # observation cache, generator, integrator registers, tracers — and require the total to equal
    # frame + working set, cell by cell. A future buffer that neither table names fails here
    # whichever object it hangs off, so residency can no longer be added anywhere unnoticed.
    for scheme in (:RK3, :RK2), dealiasing in (:TwoThirds, :HouLi, :PhaseShift),
        scalar in (false, true), tracers in (0, 4)
      sim = Simulation(domains[dealiasing]; viscosity = 0.1, scalar,
                       velocity_forcing = NoForcing(), integrator = _scheme(scheme),
                       number_of_tracers = tracers, rng = MersenneTwister(1))
      @test _counts((sim,), N_AUDIT) ==
            _add(FRAME, _add(BASE[(scheme, dealiasing, scalar)],
                             tracers > 0 ? TRACER_DELTA : ZERO))
    end

    # And the configuration a user actually gets from the front door, forcing included: the default
    # `Simulation` is RK3 × TwoThirds, velocity-only, band-rescaled over the total energy.
    default = Simulation(domains[:TwoThirds]; viscosity = 0.1, rng = MersenneTwister(1))
    @test _counts((default,), N_AUDIT) ==
          _add(FRAME, _add(BASE[(:RK3, :TwoThirds, false)], _forcing_delta(:band, :velocity)))
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
    # The symbolic values must correspond to actual storage: the chart slots on ObservablesCache,
    # products on ResolvedGenerator, spectral stage registers on IntegratorBuffers/ScalarBuffers,
    # the OU's state and noise on the forcing.
    @test all(f -> f in fieldnames(ObservablesCache), (:velocity, :vorticity, :scalar, :max_speed))
    @test :product_spectral in fieldnames(ResolvedGenerator)
    # The physical product register is gone (decision 41): the Lamb vector forms over the vorticity
    # slot and the scalar flux over the velocity slot — in place, alias-safe.
    @test !(:product_physical in fieldnames(ResolvedGenerator))
    IB = GBGIsotropicTurbulence.Propagator.IntegratorBuffers
    SB = GBGIsotropicTurbulence.Propagator.ScalarBuffers
    @test all(f -> f in fieldnames(IB), (:stage1, :stage2, :velocity_star_spectral, :nonlinear))
    # The integrating factor has NO register (decision 39), and the physical-representation
    # registers moved onto the cache slots (decision 40) — a step recovers INTO the charts it takes.
    @test !(:integrating_factor in fieldnames(IB))
    @test isempty(intersect((:velocity_star, :vorticity_physical), fieldnames(IB)))
    @test all(f -> f in fieldnames(SB), (:stage1, :stage2, :star_spectral, :nonlinear))
    @test isempty(intersect((:copy, :field), fieldnames(SB)))
    @test all(f -> f in fieldnames(StochasticOU), (:state, :noise_physical, :noise_spectral))
  end

  @testset "liveness bounds and the gap register" begin
    # Every unforced cell sits AT its bound in every class (decision 40): the slot=register merge
    # closed the chart gap, deleting the cache's spectral scratch closed the ownership gap, and
    # deleting the scalar copy register closed the scalar gap — each holder retired in the same
    # commit. This equality CAN fail: extend a register's life past the schedule's need (or add a
    # resident buffer) and the ledger rises off the bound with no holder to claim it.
    for (scheme, ops_of) in ((:RK3, rk3_ops), (:RK2, rk2_ops)), scalar in (false, true)
      @test peak_liveness(ops_of(scalar)) == BASE[(scheme, :TwoThirds, scalar)]
    end
    # PhaseShift's displaced-evaluation registers are working values like any other, and its cells
    # sit at the bound too.
    @test peak_liveness(rk3_ops(true; phase_shift = true)) == BASE[(:RK3, :PhaseShift, true)]

    # The one remaining gap: the archived OU's noise pair lives on the forcing, across an ownership
    # boundary from the generator registers it could alias — one spectral and one physical vector,
    # both held.
    ou_ops = rk3_ops(false; ou = true)
    ou_achieved = _add(BASE[(:RK3, :TwoThirds, false)], _forcing_delta(:ou, :velocity))
    ou_bound = peak_liveness(ou_ops)
    holders = GAP_HOLDERS[(:RK3_OU, false)]
    for class in (:spectral_vector, :physical_vector, :spectral_scalar, :physical_scalar)
      working = getproperty(ou_achieved, class)
      b = getproperty(ou_bound, class)
      @test b <= working                        # a bound above the ledger is a bookkeeping error
      if working - b > 0
        @test haskey(holders, class)            # every gap carries a named holder (decision 33)
      end
    end
    @test ou_achieved.spectral_vector - ou_bound.spectral_vector == 1
    @test ou_achieved.physical_vector == ou_bound.physical_vector

    # The physical-vector floor, in numbers: TWO registers — the chart slots, doubling as the
    # substage recovery registers AND as the quadratic products' in-place targets (decision 41) —
    # with the three vectors retired since decision 37 (the two-chart gap + the product register,
    # 1.15 GiB at 256³ / Float64) banked, not held.
    for (scheme, ops_of) in ((:RK3, rk3_ops), (:RK2, rk2_ops)), scalar in (false, true)
      @test peak_liveness(ops_of(scalar)).physical_vector == 2
    end
  end

  @testset "the bound still encodes a falsifiable contract" begin
    # Decision 37's lesson, restated for the merged design: the charts' extension in DYNAMICS_LIVE
    # is a FACT only while the schedule really deposits them at the iteration's end — the extension asserts the
    # deposits must persist to the next iteration's first stage. Pin the structure that makes it a
    # fact: the op lists end with the closing deposits (so the extension covers a real write), and the
    # charts are read at the head before any write (so the previous deposit is really consumed).
    for ops_of in (rk3_ops, rk2_ops), scalar in (false, true)
      ops = ops_of(scalar)
      @test any(op -> op.name == "u chart recovery", ops)
      @test any(op -> op.name == "ω chart recovery", ops)
      @test ops[end].name == "max speed"                 # the closing deposit ends the iteration
      first_touch = findfirst(op -> :chart_u in op.reads || :chart_u in op.writes, ops)
      @test :chart_u in ops[first_touch].reads           # read as the deposited value, not scratch
    end
    @test issubset(Set([:chart_u, :chart_ω]), DYNAMICS_LIVE)
    @test CONTRACT_LIVE == DYNAMICS_LIVE                 # no choice-extension set remains
  end

  @testset "episode ledger — transient peaks, frozen and attributed" begin
    N = 32
    domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, element_type = Float64, dealiasing = TwoThirds(), array_type = Array)
    unit = 8 * N^3
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity!(û, domain; kinetic_energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(1))
    φ̂ = new_scalar_field_spectral(domain)
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

  @testset "the hot loop is allocation-free on EVERY dealiasing strategy" begin
    # The coverage hole that let a regression ship (2026-07-31). The guard above runs one cell —
    # RK3 × TwoThirds, velocity-only — so an allocation introduced on a strategy-specific code path
    # was invisible to it. A `PhaseShift` run had been aliasing the destination of the displaced
    # cross product onto one of its operands; the backend guards that case by allocating a temporary
    # and copying back, at a full physical vector per stage, and nothing failed.
    #
    # The scope of this test is the point: the axes a step's code path actually branches on, not one
    # representative configuration. A per-stage transient of one field-scale array reads as ≈ 3 units
    # here, so the 0.5-unit ceiling separates "allocation-free" from "one field per stage" by a wide
    # margin without being brittle about small run-layer bookkeeping.
    N = 16
    unit = 8 * N^3
    for dealiasing in (TwoThirds(), HouLi(), PhaseShift()), scheme in (IFLowStorageRK3(), IFRK2()),
        scalar in (false, true)
      sim = Simulation(grid_points_per_axis = N, viscosity = 0.05; dealiasing, scalar,
                       integrator = scheme, rng = MersenneTwister(1))
      advance!(sim; dt = 1e-3); advance!(sim; dt = 1e-3)          # warm before measuring
      @test (@allocated advance!(sim; dt = 1e-3)) < 0.5 * unit
    end
  end
end
