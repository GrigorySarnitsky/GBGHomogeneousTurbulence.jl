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
  end
  return _counts(owners, N_AUDIT)
end

# The frozen BASE table — unforced (NoForcing/NoForcing), tracer-free. A deliberate footprint change
# updates this spec (and, for a structural change, the op lists below) in the same commit, citing the
# decision. Columns: spectral_vector, physical_vector, spectral_scalar, physical_scalar,
# real_spectral_scalar.
# The PhaseShift cells carry a register of their own for the displaced velocity. Landing it on the
# generator's spent physical product scratch instead was tried and REVERTED (2026-07-31): the
# backend's `cross!` guards destination/operand aliasing by allocating a temporary and copying back,
# so the saved register cost a full physical vector of TRANSIENT allocation per stage and broke the
# allocation-free hot loop. Retaking it needs an alias-safe kernel from the backend, not a rewiring
# here — the allocation guard below is what now holds the claim.
# The real_spectral_scalar column is ZERO throughout, and the zero is the point (2026-07-28,
# decision 35): a rate
# array exists only where a forcing declares `uses_linear_rate`, so an unforced field — and the
# default configuration, whose BandRescaling is a post-step projection — carries none. It used to
# read 1 (2 with a scalar) for arrays that were never written and never read.
const BASE = Dict(
  (:RK3, :TwoThirds,  false) => (spectral_vector = 5, physical_vector = 5, spectral_scalar = 1, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK3, :TwoThirds,  true)  => (spectral_vector = 5, physical_vector = 5, spectral_scalar = 5, physical_scalar = 1, real_spectral_scalar = 0),
  (:RK3, :HouLi,      false) => (spectral_vector = 5, physical_vector = 5, spectral_scalar = 1, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK3, :HouLi,      true)  => (spectral_vector = 5, physical_vector = 5, spectral_scalar = 5, physical_scalar = 1, real_spectral_scalar = 0),
  (:RK3, :PhaseShift, false) => (spectral_vector = 6, physical_vector = 7, spectral_scalar = 3, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK3, :PhaseShift, true)  => (spectral_vector = 6, physical_vector = 7, spectral_scalar = 9, physical_scalar = 2, real_spectral_scalar = 0),
  (:RK2, :TwoThirds,  false) => (spectral_vector = 6, physical_vector = 5, spectral_scalar = 1, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK2, :TwoThirds,  true)  => (spectral_vector = 6, physical_vector = 5, spectral_scalar = 6, physical_scalar = 1, real_spectral_scalar = 0),
  (:RK2, :HouLi,      false) => (spectral_vector = 6, physical_vector = 5, spectral_scalar = 1, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK2, :HouLi,      true)  => (spectral_vector = 6, physical_vector = 5, spectral_scalar = 6, physical_scalar = 1, real_spectral_scalar = 0),
  (:RK2, :PhaseShift, false) => (spectral_vector = 7, physical_vector = 7, spectral_scalar = 3, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK2, :PhaseShift, true)  => (spectral_vector = 7, physical_vector = 7, spectral_scalar = 10, physical_scalar = 2, real_spectral_scalar = 0),
)

# The frozen forcing DELTAS, per slot. Band/Linear/ConstantPower carry the same (scalar-shaped)
# kernels and masks for either slot; the OU's state and noise scratch take the forced field's shape.
_forcing_delta(tag, slot) =
  tag === :none  ? ZERO :
  tag === :band  ? (spectral_vector = 0, physical_vector = 0, spectral_scalar = 1, physical_scalar = 0, real_spectral_scalar = 0) :
  tag === :linear ? (spectral_vector = 0, physical_vector = 0, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 2) :
  tag === :power ? (spectral_vector = 0, physical_vector = 0, spectral_scalar = 1, physical_scalar = 0, real_spectral_scalar = 1) :
  slot === :velocity ? (spectral_vector = 2, physical_vector = 1, spectral_scalar = 1, physical_scalar = 0, real_spectral_scalar = 0) :
                       (spectral_vector = 0, physical_vector = 0, spectral_scalar = 3, physical_scalar = 1, real_spectral_scalar = 0)
# (:ou — the band kernel plus, in the forced field's shape, the OU state f̂ and the two noise buffers.)
# Each rate-driven forcing carries the generator's rate array — which now exists precisely because
# such a forcing is present, so the storage appears on the axis that causes it instead of
# unconditionally in the base. `Linear` adds its own real band indicator on top; `ConstantPower`
# does not, since the indicator is the real part of the kernel it already holds for the band
# observable, taken lazily in the rate fill rather than stored twice (2026-07-28, decision 35).

# Tracers cost NOTHING at field scale: everything they hold is O(M) — positions, the Heun predictor,
# and the two interpolated point-value sets. The start-of-step endpoint velocity is recorded onto the
# tracers as M interpolated vectors rather than retained as a field, so a tracked run adds no resident
# field to an untracked one. This zero is the assertion, not a placeholder.
const TRACER_DELTA = ZERO

# The charts axis of the observation layer: each declared chart is one resident physical vector; the
# spectral scratch is unconditional. The base table pins the default (both charts) — the rotational
# generator's declared working set requires both to step, so for a stepping run the axis is pinned by
# the physics; it is live at the API level (observation-only uses) and becomes a run axis when
# per-component chart declarations or further charts land.
_chart_delta(charts) = (spectral_vector = 0, physical_vector = length(charts) - 2,
                        spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0)

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
# It holds three field-scale arrays, and every one of them is a per-mode symbol: a closed-form
# function of the O(N) per-axis multipliers, precomputed once and swept from memory thereafter.
#
#   |κ|² as a real array               → real_spectral_scalar   (the envelope, integrating-factor,
#                                                                and HouLi-profile broadcasts, and
#                                                                the `similar` storage template)
#   |κ|² as a `weighted_inner` weight  → spectral_scalar        (the Dirichlet-energy route)
#   the de-alias mask                  → spectral_scalar        (every strategy's kernel)
#
# Two things the cells make visible that no other surface stated. First, |κ|² is resident TWICE, in
# two element types, because `weighted_inner` takes a spectral-scalar-typed weight while the
# broadcasts want the real array — 193.5 MiB of one radial function at 256³ / Float64. Second, both
# spectral-scalar entries are real-valued symbols in COMPLEX containers, so each costs 2× its
# information content. Both are absorbed by a lazy per-mode symbol apply, which is why the frame's
# floor (optimality_audit.jl) is zero field-scale arrays rather than three.
#
# The frame is invariant across the dealiasing strategy and the precision, and that invariance is
# part of the assertion: every strategy's mask is one complex spectral scalar whatever its profile
# (sharp, smooth, or spherical), and Float32 changes bytes, never counts.
const FRAME = (spectral_vector = 0, physical_vector = 0, spectral_scalar = 2,
               physical_scalar = 0, real_spectral_scalar = 1)

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
# every nonzero gap. An unclaimed gap is a finding, and the test fails. Recorded holders
# (decision 33): OWNERSHIP — buffers that could alias in this schedule but live across a
# deliberately kept boundary (the cache's recovery scratch vs the generator's product/nonlinear
# registers; the OU's noise buffers vs the generator's products); CHART CONTRACT — the charts are
# required to survive the whole step under the epoch-at-end design, which costs TWO physical vectors
# against the bound (768 MiB at 256³ / Float64); SHARED FACTOR — the factor register could be deleted
# by a fused exponential-convolve (raised to GBGPeriodicFields); SCALAR REGISTERS — the scalar's
# copy/nonlinear/factor registers could share one transient slot.
#
# CHART CONTRACT was recorded in this comment from the start and never bound to a cell, because the
# liveness projection extended the charts' live range across the step and then reported the result as
# the bound (decision 37). That made `achieved == bound` a tautology in the physical-vector class and
# the suite asserted it. The projection now extends only DYNAMICS_LIVE, so the assumption shows up
# where it belongs — as a claimed gap.
const GAP_HOLDERS = Dict(
  (:RK3, false) => Dict(:physical_vector => "CHART CONTRACT (charts survive the step; boundary refresh is the candidate)",
                        :spectral_vector => "OWNERSHIP (scratch ↔ product/nonlinear)",
                        :spectral_scalar => "SHARED FACTOR (PF fused-exponential request)"),
  (:RK3, true)  => Dict(:physical_vector => "CHART CONTRACT (charts survive the step; boundary refresh is the candidate)",
                        :spectral_vector => "OWNERSHIP (scratch ↔ product/nonlinear)",
                        :spectral_scalar => "SHARED FACTOR + SCALAR REGISTERS"),
  (:RK2, false) => Dict(:physical_vector => "CHART CONTRACT (charts survive the step; boundary refresh is the candidate)",
                        :spectral_vector => "OWNERSHIP (scratch ↔ product/nonlinear)",
                        :spectral_scalar => "SHARED FACTOR (PF fused-exponential request)"),
  (:RK2, true)  => Dict(:physical_vector => "CHART CONTRACT (charts survive the step; boundary refresh is the candidate)",
                        :spectral_vector => "OWNERSHIP (scratch ↔ product/nonlinear)",
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

  @testset "frame ledger — the frozen per-mode symbols, invariant in strategy and precision" begin
    for tag in (:TwoThirds, :HouLi, :PhaseShift), T in (Float64, Float32)
      domain = FixedDomain(N_AUDIT, 2π; element_type = T, array_type = Array,
                           dealiasing = tag === :TwoThirds ? TwoThirds() :
                                        tag === :HouLi ? HouLi() : PhaseShift())
      @test frame_ledger(domain) == FRAME
    end
    # The frame holds no field of the evolving classes: it is symbols, not state. Stating it
    # separately keeps the three zeros above from reading as unfilled cells.
    @test FRAME.spectral_vector == 0 && FRAME.physical_vector == 0 && FRAME.physical_scalar == 0

    # The phase-shift translation kernels are frame-natured — built once from the grid spacing,
    # never written again — but they hang off the generator's buffers, so the WORKING-SET ledger is
    # where they appear (the +2 spectral scalars in every PhaseShift base cell). The split is by
    # owner, not by nature, which is exactly why the completeness test below is the real closure.
    @test BASE[(:RK3, :PhaseShift, false)].spectral_scalar -
          BASE[(:RK3, :TwoThirds, false)].spectral_scalar == 2
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
    # The physical-vector class, stated as the numbers rather than as an equality that cannot fail.
    # The bound is three — the two substage recoveries plus the product register — and the ledger
    # carries five, because the charts are additionally required to survive the step. That difference
    # is the CHART CONTRACT holder, and it is two physical vectors: 768 MiB at 256³ / Float64.
    for (scheme, ops_of) in ((:RK3, rk3_ops), (:RK2, rk2_ops)), scalar in (false, true)
      ops = ops_of(scalar)
      @test peak_liveness(ops).physical_vector == 3
      @test BASE[(scheme, :TwoThirds, scalar)].physical_vector - peak_liveness(ops).physical_vector == 2
      @test haskey(GAP_HOLDERS[(scheme, scalar)], :physical_vector)
    end
  end

  @testset "the liveness bound is not self-fulfilling" begin
    # The guard decision 37 exists to install. Extending the charts' live range across the whole step
    # and calling the result a bound made `achieved == bound` true by construction in this class —
    # the assumption under test was an input to the test. Assert that the assumption is LOAD-BEARING
    # (adding it back changes the number, and changes it exactly onto the ledger), so a future
    # re-merge of the two sets fails here rather than silently re-certifying the tautology.
    for (scheme, ops_of) in ((:RK3, rk3_ops), (:RK2, rk2_ops)), scalar in (false, true)
      ops = ops_of(scalar)
      bound    = peak_liveness(ops)                      # DYNAMICS_LIVE only — the honest floor
      described = peak_liveness(ops; charts_live = true)  # + the chart contract — the present design
      @test described.physical_vector > bound.physical_vector
      @test described.physical_vector == BASE[(scheme, :TwoThirds, scalar)].physical_vector
      # …and the split is confined to that class: the state's extension is a fact, not a choice, so
      # it changes nothing when the charts are excluded.
      @test bound.spectral_vector == described.spectral_vector
      @test bound.spectral_scalar == described.spectral_scalar
    end
    @test isempty(intersect(DYNAMICS_LIVE, CHART_CONTRACT_LIVE))
    @test CONTRACT_LIVE == union(DYNAMICS_LIVE, CHART_CONTRACT_LIVE)
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
