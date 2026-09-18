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
#     never a drive-by. (The particle-scheme axis carries two points: `Heun`, which enters as
#     on/off, and `AdamsBashforth{K}`, whose sample history adds K−1 (M, 3) arrays — priced below,
#     since they scale with the ORDER and not with the grid; precision, backend, and the
#     interpolation scheme change bytes, never counts.)
#
#  2. THE FRAME LEDGER — the same walk over what a run does NOT evolve: the read-only `FixedDomain`
#     and its per-mode symbols. This storage sat outside every ledger until 2026-07-30 and is not
#     small (322.5 MiB at 256³ / Float64, ~8 % on top of the default working set), so the audit
#     claimed to bound residency while measuring only part of it. The two ledgers are kept apart
#     because they answer different questions — the working set is what the schedule needs live, the
#     frame is what the discretization costs to have precomputed — and a COMPLETENESS test then
#     requires their sum to account for every field-scale array a live `Simulation` can reach, so
#     nothing can fall between them again. The gap that survives is not one of REACH — the walk
#     recurses through any struct's fields and would descend into a transform plan's buffer — but
#     one of BACKEND: every domain built below passes `array_type = Array`, and the plan buffers
#     exist only on a GPU. See the named exclusion at the frame ledger; the once-open item G2 was closed by decision 79 (the DEVICE_FRAME leg below).
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
using GBGPeriodicFields: npoints
using GBGPeriodicFields: field_data, CatmullRom
using Random
using Test


# The shared op model (CLASSES, the class decomposition and its reflective counter, Op, the step op
# lists, peak_liveness) — one source of truth for this audit's residency and liveness projections
# and test/compute_audit.jl's cost projection.
include("audit_ops.jl")

const N_AUDIT = 8


# ---------------------------------------------------------------- the working-set ledger

# Build one combination's working set and measure it. The state record carries each forcing's started
# state, as a run's does, so a forcing's state is walked wherever it lives.
function ledger(domain, scheme, scalar::Bool, velocity_forcing, scalar_forcing, tracers::Bool)
  conditions = FlowConditions(; viscosity = 0.1, schmidt = 1.0, velocity_forcing, scalar_forcing)
  fields = ResolvedFields(domain; scalar)
  modeled = (velocity_forcing = initial_forcing_state(velocity_forcing, fields.velocity_spectral, domain),
             scalar_forcing = scalar ? initial_forcing_state(scalar_forcing, fields.scalar_spectral, domain) : nothing)
  state = ResolvedFields(fields.velocity_spectral, fields.scalar_spectral, modeled)
  owners = Any[state, ObservablesCache(domain; scalar), ResolvedGenerator(domain, conditions; scalar),
               allocate_buffers(scheme, domain; scalar)]
  if tracers
    push!(owners, Tracers(domain; number_of_particles = 4, interpolation_scheme = CatmullRom, rng = MersenneTwister(1)))
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
# array exists only where a forcing declares `uses_steady_linear_rate`, so an unforced field — and the
# default configuration, whose VarianceRescaling is a post-step projection — carries none. It used to
# read 1 (2 with a scalar) for arrays that were never written and never read.
const BASE = Dict(
  (:RK3, :TwoThirds,  false) => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK3, :TwoThirds,  true)  => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 3, physical_scalar = 1, real_spectral_scalar = 0),
  (:RK3, :HouLi,      false) => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK3, :HouLi,      true)  => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 3, physical_scalar = 1, real_spectral_scalar = 0),
  (:RK3, :PhaseShift, false) => (spectral_vector = 5, physical_vector = 4, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK3, :PhaseShift, true)  => (spectral_vector = 5, physical_vector = 4, spectral_scalar = 5, physical_scalar = 2, real_spectral_scalar = 0),
  # IFSSPRK3 (decision 80): the SAME cells as :RK3 in every configuration, and the equality is the
  # point — the scheme was designed into RK3's register shape (stage state + nonlinear; the
  # accumulator's role played by the state itself), so TurTLE's tableau costs nothing over the
  # low-storage one. A divergence here would mean that design claim failed.
  (:SSPRK3, :TwoThirds,  false) => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:SSPRK3, :TwoThirds,  true)  => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 3, physical_scalar = 1, real_spectral_scalar = 0),
  (:SSPRK3, :HouLi,      false) => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:SSPRK3, :HouLi,      true)  => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 3, physical_scalar = 1, real_spectral_scalar = 0),
  (:SSPRK3, :PhaseShift, false) => (spectral_vector = 5, physical_vector = 4, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:SSPRK3, :PhaseShift, true)  => (spectral_vector = 5, physical_vector = 4, spectral_scalar = 5, physical_scalar = 2, real_spectral_scalar = 0),
  # IFLowStorageRK4 (decision 85): the SAME cells as :RK3 in every configuration — the
  # Carpenter–Kennedy 2N pair adds stages, not registers; the equality IS the claim.
  (:RK4, :TwoThirds,  false) => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK4, :TwoThirds,  true)  => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 3, physical_scalar = 1, real_spectral_scalar = 0),
  (:RK4, :HouLi,      false) => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK4, :HouLi,      true)  => (spectral_vector = 4, physical_vector = 2, spectral_scalar = 3, physical_scalar = 1, real_spectral_scalar = 0),
  (:RK4, :PhaseShift, false) => (spectral_vector = 5, physical_vector = 4, spectral_scalar = 0, physical_scalar = 0, real_spectral_scalar = 0),
  (:RK4, :PhaseShift, true)  => (spectral_vector = 5, physical_vector = 4, spectral_scalar = 5, physical_scalar = 2, real_spectral_scalar = 0),
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

# What the stochastic forcing holds instead of field-scale arrays: its process and draw scratch live on
# a companion grid sized by the forced band, so their cost is constant in N and vanishes against the run
# as the grid grows. Pinned below at a realistic grid rather than at this file's tiny audit size.
const OU_COMPANION_SHARE_AT_64 = 0.01

# The frozen forcing DELTAS, per slot. Every band kernel is now a lazy radial symbol (PF adoption,
# 2026-08-05 — PF decision 51), so a band-selecting forcing stores no field-scale kernel. The OU is
# ZERO since decision 90: its process, its draw scratch and its uploaded amplitudes are all sized by
# the band's M conjugate mode pairs, not the grid — a reduction of two spectral vectors and one
# physical vector from the dense form (velocity slot), which held its force and a noise pair.
function _forcing_delta(tag, slot)
  tag === :none && return ZERO
  tag === :band && return ZERO
  tag === :linear && return (spectral_vector = 0, physical_vector = 0, spectral_scalar = 1, physical_scalar = 0, real_spectral_scalar = 1)
  tag === :power && return ZERO
  tag === :controller && return ZERO
  tag === :ou && return ZERO
  error("unmodelled forcing tag $tag — price it here in the same commit that adds it")
end
# Only a STEADY-rate forcing carries the generator's rate array, plus the materialized real band
# indicator its rate fill reads (the band kernel being lazy, there are no stored coefficients to read
# from). Today that is `Linear` alone.
#
# `ConstantPower` and `VarianceController` are ZERO as of 2026-08-22, and the change is a REDUCTION
# of two field-scale arrays each. Their rates depend on the state, so folding them into the
# integrating factor evaluated ∫A dt by a left-endpoint rectangle rule and collapsed a third-order
# scheme to first (measured 1.018 against 2.995 unforced). They moved to the per-stage source, where
# `convolve!` reads the lazy band kernel directly — so neither the rate array nor the indicator is
# allocated at all. The footprint fell out of the accuracy fix rather than being traded for it.
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
  tag === :band  ? VarianceRescaling(domain; target = 0.5, over = :band) :
  tag === :linear ? Linear(domain; rate = 0.1) :
  tag === :power ? ConstantPower(domain; injection_rate = 0.1) :
  # Explicit turnover_time: the scalar slot refuses the derived (kinetic-energy-law) default,
  # and the value is memory-inert — this sweep audits storage, not physics.
  tag === :controller ? VarianceController(domain; target = 0.5, turnover_time = 1.0) :
  tag === :ou ? StochasticOU(domain; forcing_variance = 0.1, correlation_time = 0.5, seed = 1) :
  error("unmodelled forcing tag $tag")

_scheme(tag) = tag === :RK3 ? IFLowStorageRK3() : tag === :RK4 ? IFLowStorageRK4() :
               tag === :SSPRK3 ? IFSSPRK3() : IFHeun()
const FORCING_TAGS = (:none, :band, :linear, :power, :controller, :ou)


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

# Named exclusion, so it is recorded rather than merely absent: the per-plan device storage a
# transform backend holds. It is reachable from no Julia field the walk visits, so it is outside
# both ledgers by construction — but unlike the O(N) axis multipliers and shell vectors it groups
# with, it is NOT small on GPU: measured 2026-08-25/26 on CUDA and ROCm it is COMPARABLE TO THE
# WHOLE WORKING SET. Precisely, excess/ledger is 1.45 under TwoThirds (both grids) and 0.97 under
# PhaseShift, whose ledger is larger — 9 field-scale arrays against 6 — while the plan set is not.
# The plan set depends on the field TYPES a run transforms, never on the scheme or the dealiasing.
#
# WHAT IT IS (established 2026-08-26 by reading CUDA.jl and then MEASURING ON THE CARD, after three
# days of believing otherwise — see the postmortem below). It is not the vendor FFT work area. It is
# the GPU backend's own per-plan buffers, allocated in Julia at plan construction:
#
#   plan_rfft   → `buffer = CuArray{complex(T)}(undef, ydims...)`   ydims is the SPECTRAL shape
#   plan_brfft  → `buffer = CuArray{T}(undef, size(X))`             T complex, X the SPECTRAL input
#
# BOTH are spectral-sized — the buffer holds the transform's complex side in each case. They exist
# because an out-of-place complex-to-real transform always overwrites its input, so `mul!` copies
# the input into the buffer before executing. IT therefore builds TWO spectral-sized device arrays
# PER PLAN COMPONENT: velocity 3 + scalar 1 + tensor 9 = 13 components, 26 buffers.
#
# The prediction is 26 × one spectral scalar, and it holds across every configuration measured:
#
#   128³  TwoThirds  F32     predicted  211.25 MiB   measured  211.25 MiB   exact
#   192³  PhaseShift F32     predicted  709.3  MiB   measured  709.6  MiB   +0.04%
#   256³  TwoThirds  F32     predicted 1677.0  MiB   measured 1677.5  MiB   +0.03%
#   192³  PhaseShift F64     predicted 1418.6  MiB   measured 1418.2  MiB   −0.03%
#   384³  PhaseShift F32 + scalar + 10⁶ tracers: ledger 7366.5 + buffers 5645.25 = 13011.75 MiB
#                                                 against 13058 measured, the 46 MiB residual being
#                                                 the tracers' O(M) arrays.
#
# (An earlier version of this note read the second buffer as physical-sized and carried a uniform
# +0.4…0.8% residual. A residual with STRUCTURE is a wrong model, not pool rounding; reading the
# two allocation sites properly removed it.)
#
# The residual few MiB is the actual cuFFT work area plus pool rounding — so the vendor scratch is
# real but SMALL, which is what a 3-D transform that can work in its output buffer should cost.
# CUDA.jl declines to manage it explicitly and says so ("we currently do not use the worksize to
# allocate our own workarea, instead relying on the automatic allocation strategy"), though it does
# bind `cufftSetWorkArea` and `cufftSetAutoAllocation` for a caller that wants to.
#
# ROCm lands on the identical total to the displayed digit (192³ PhaseShift: 1.409 GiB in F32,
# 2.817 GiB in F64, both matching CUDA exactly). AMDGPU.jl's fft.jl is line-for-line the same
# design — `buffer = ROCArray{complex(T)}(undef, ydims)` in plan_rfft, `ROCArray{T}(undef, size(X))`
# in plan_brfft, and the same `z = p.buffer; copyto!(z, x)` in `mul!` — so the identity is structural,
# not a coincidence.
#
# DIRECTLY MEASURED 2026-08-26 on the RTX 5070 Ti, `CUDA.@allocated` around plan construction at
# 64³/Float32 — the check this note twice deferred as a formality:
#
#   scalar plans (1 component)    2.06 MiB  =  2.000 × (components × one spectral scalar)
#   velocity plans (3 components) 6.19 MiB  =  2.000 × (components × one spectral scalar)
#   tensor plans (9 components)  18.56 MiB  =  2.000 × (components × one spectral scalar)
#
# Exactly two spectral-sized buffers per component, on the nose, for all three families. Note this
# also localizes the vendor work area: `@allocated` sees only Julia-side allocations, while the pool
# figure the runs report is the same quantity — so cuFFT's own work area, allocated by the library
# outside CUDA.jl's pool, appears in `nvidia-smi` and in "Effective GPU memory usage" but in neither
# of the numbers modelled here.
#
# TWO CONSEQUENCES THIS AUDIT CANNOT SEE.
#
#   1. CLOSED 2026-08-26, decision 78. `tensor_plans` carries 9 of the 13 components and has exactly
#      ONE consumer, the strain-tensor diagnostic in Observables — 3.81 GiB at 384³/Float32 held for
#      the life of a run. It is now built on first use, and the skewness gate that would have built
#      it during every default warm-up is off by default. The velocity and scalar plans stay eager:
#      the time loop transforms both every step, so there is nothing to defer.
#
#   2. HALF THE BUFFERS ARE NEVER USED, and the preserving copy is redundant on GPU. Both measured
#      on the card 2026-08-26; open item G4. The forward plan's buffer serves `ldiv!` alone, which PF
#      never calls — a sentinel filled into both buffers survives a forward AND an inverse transform
#      in the forward plan's, so 13 of the 26 are dead weight (4 of the remaining 8 after decision
#      78, 868 MiB at 384³/Float32). And the THREE-argument `to_physical!`, the one PF documents as
#      consuming its source, was measured to PRESERVE it on CUDA and destroy it on CPU — so the
#      four-argument form's copy buys, on GPU, a guarantee the backend already provides, at 14.7% of
#      inverse-transform time. Both fixes are upstream of IT, which is invariant 2's shape one level
#      further out.
#
# POSTMORTEM, kept because the failure is the instructive part. From 2026-08-25 this note asserted
# the storage was the vendor work area, and grew three rounds of confirmation: the N³ scaling over
# three grids, the count 26 = 13 × 2 over two dealiasing strategies with different ledgers, and
# element-size scaling over a precision pair — each round strengthening the claim, none testing it.
# All three are properties of ANY per-plan field-sized allocation. They pinned the SIZE and were
# read as pinning the CAUSE. The note even named the check that would have settled it and deferred
# it as a formality, having mistaken accumulated fit for identification. What actually settled it
# was reading the allocation site in CUDA.jl, prompted by the owner pointing out that CUDA and ROCm
# have their own options rather than inheriting FFTW.jl's. A model that predicts out of sample
# constrains the magnitude of a mechanism; it does not name one.
frame_ledger(domain) = _counts((domain,), N_AUDIT)


# ---------------------------------------------------------------- the device backend

# Every ledger above is measured with `array_type = Array`, and the frame's all-zero table is a
# CPU FACT: an FFTW plan reaches no Julia array, so the walk finds nothing to count. On a GPU
# backend the same walk, over the same objects, finds the transform plans' staging buffers — one
# spectral-shaped device array per plan, allocated eagerly by the backend's plan constructor. The
# audit was blind to that for as long as it only ever built CPU domains, which is exactly the
# failure decision 36 was written to prevent, displaced one level: not storage hanging off an
# unwalked owner, but an owner never instantiated on the backend where it holds anything.
#
# So the device frame is ledgered here rather than excluded. It is NOT zero, and the register is
# bidirectional like every other in this file: when the backend stops allocating eagerly (the
# upstream request), this table must fall to `FRAME` in the same commit that closes it.
#
# RE-FROZEN 2026-08-28 (decision 81, on PF's decision 76): the plans are rank-blind and the domain
# holds ONE pair, so the per-plan buffers are two COMPONENT-sized spectral arrays, forward and
# inverse, however many field types the run transforms:
#
#   transform_plans: forward + inverse, one spectral SCALAR buffer each  → spectral_scalar = 2
#
# Down from (spectral_vector = 2, spectral_scalar = 2) = 8 scalar-equivalents to 2. The superseded
# cell is kept in the note below as the record of what was measured. The forward buffer is STILL
# dead weight (allocated for an `ldiv!` route this package never takes — open item G4-A, upstream),
# but the stake fell from 4 scalar-equivalents to 1.
const DEVICE_FRAME = (spectral_vector = 0, physical_vector = 0, spectral_scalar = 2,
                      physical_scalar = 0, real_spectral_scalar = 0)

# A GPU is hardware, so this leg cannot be a plain `@test`. It must not be a SILENT skip either:
# a conditional that quietly passes on a CPU-only runner rebuilds the blindness it exists to
# remove, in a new form. `@test_skip` records a visibly unfulfilled test in the summary, and the
# warning names why.
# Resolved at INCLUDE time, not inside the testset: `Base.require` loads the backend into a new
# world age, so a `functional()` called from the same function that loaded it is invisible — hence
# `invokelatest` here, and hence the testset (a later top-level expression) can then call the
# backend's constructors normally.
const DEVICE_BACKEND = let found = nothing
  for (mod, arr) in (("CUDA", :CuArray), ("AMDGPU", :ROCArray))
    id = Base.identify_package(mod)
    id === nothing && continue
    m = try Base.require(id) catch; nothing end
    m === nothing && continue
    ok = try Base.invokelatest(getproperty(m, :functional)) catch; false end
    if ok
      found = (mod, getproperty(m, arr))
      break
    end
  end
  found
end


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
# Every cell now sits AT its liveness bound in every class, forced ones included. The last gap was
# the archived OU's spectral noise, which could alias the generator's spectral registers but lived on
# the forcing across an ownership boundary; its holder (OWNERSHIP, OU noise ↔ nonlinear/product)
# retired with decision 90, which removed the noise from field scale altogether.
const GAP_HOLDERS = Dict{Tuple{Symbol, Bool}, Dict{Symbol, String}}()



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
#                                  DOMINANT episode (~ +55 % over the default resident set), reached
#                                  whenever the skewness gate is enabled — OFF by default since
#                                  decision 78, so this is the binding device peak of a warm-up that
#                                  opts in, not of the default one. Invariant
#                                  4's per-call-diagnostic trade, priced. (PF stores full 9-component
#                                  tensors; symmetric 6-component storage is the recorded reduction.)
#   energy_spectrum       ≈ 0.0 (1.6) — GBGPeriodicFields fused its radial_spectrum staging into the
#                                  binning kernel (its decision 34); only the O(N) shell vectors
#                                  remain. integral_scale and flow_parameters inherit the zero.
# The dense StochasticOU's prepare! projected its noise aliased per step; the band-sparse form of
# decision 90 has no field-scale episode at all (its per-step allocation is the reseed's fixed few
# hundred bytes, pinned by regression 02-gpu-and-hot-loop-02).
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
    for scheme in (:RK3, :RK4, :SSPRK3, :RK2), dealiasing in (:TwoThirds, :HouLi, :PhaseShift), scalar in (false, true),
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

  @testset "the frame ledger on a device backend — the plans' staging buffers, named" begin
    backend = DEVICE_BACKEND
    if backend === nothing
      @warn "memory audit: the DEVICE frame ledger did not run — no functional GPU backend in " *
            "this environment. The CPU tables above do NOT bound device residency: the frame is " *
            "all-zero on CPU and $(DEVICE_FRAME) on a GPU. This leg is SKIPPED, not passed."
      @test_skip false
    else
      name, array_type = backend
      for tag in (:TwoThirds, :PhaseShift), T in (Float64, Float32)
        domain = FixedDomain(grid_points_per_axis = N_AUDIT, side_length = 2π, element_type = T,
                             array_type = array_type,
                             dealiasing = tag === :TwoThirds ? TwoThirds() : PhaseShift())
        @test frame_ledger(domain) == DEVICE_FRAME
      end
      # The completeness invariant, on the backend that has something to complete: working set plus
      # the DEVICE frame must still account for every field-scale array a live run reaches.
      domain = FixedDomain(grid_points_per_axis = N_AUDIT, side_length = 2π, element_type = Float64,
                           array_type = array_type, dealiasing = TwoThirds())
      sim = Simulation(domain; viscosity = 0.1, velocity_forcing = NoForcing(),
                       rng = MersenneTwister(1))
      @test _counts((sim,), N_AUDIT) ==
            _add(DEVICE_FRAME, BASE[(:RK3, :TwoThirds, false)])
      @info "memory audit: the device frame ledger ran on $name"
    end
  end

  @testset "no field-scale storage escapes both ledgers" begin
    # The closure that keeps the frame hole shut. Walk a whole live `Simulation` — frame, state,
    # observation cache, generator, scheme registers, tracers — and require the total to equal
    # frame + working set, cell by cell. A future buffer that neither table names fails here
    # whichever object it hangs off, so residency can no longer be added anywhere unnoticed.
    for scheme in (:RK3, :RK4, :SSPRK3, :RK2), dealiasing in (:TwoThirds, :HouLi, :PhaseShift),
        scalar in (false, true), tracers in (0, 4)
      sim = Simulation(domains[dealiasing]; viscosity = 0.1, scalar,
                       velocity_forcing = NoForcing(), field_integration_scheme = _scheme(scheme),
                       number_of_particles = tracers, rng = MersenneTwister(1))
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

  @testset "tracer storage scales with M, not N — and splits state from observable from scheme" begin
    # Four (M, 3) arrays in total, owned by THREE different values, and WHICH owns which is the
    # invariant (decisions 50 and 67). The tracer set holds trajectory STATE only — the positions;
    # the recorded Lagrangian velocity is an OBSERVABLE, so its slot is the cache's like every
    # other slot; the predictor pair belongs to the scheme's registers, so a different scheme
    # changes that count and neither of the others.
    tracers = Tracers(domains[:TwoThirds]; number_of_particles = 4, interpolation_scheme = CatmullRom, rng = MersenneTwister(1))
    tcache = ObservablesCache(domains[:TwoThirds]; number_of_particles = 4)
    buffers = allocate_buffers(Heun(), tracers, tcache)
    _m_arrays(owner) = (acc = AbstractArray[];
                        collect_field_arrays!(acc, owner, Set{UInt}(), 2; keep = a -> length(a) >= 4);
                        [a for a in acc if size(a) == (4, 3)])
    @test length(_m_arrays(tracers)) == 1                  # positions — state, nothing else
    @test length(_m_arrays(tcache)) == 1                   # velocity_at_particles — the cache's slot
    # The scheme's OWN registers: walked from `buffers` the count includes the cache it references,
    # so the cache's arrays are subtracted by identity.
    cache_ids = Set(objectid.(_m_arrays(tcache)))
    @test length([a for a in _m_arrays(buffers) if !(objectid(a) in cache_ids)]) == 2
    # The split moved storage; it did not add any: 1 + 1 + 2 unique arrays.
    @test length(unique(objectid, vcat(_m_arrays(tracers), _m_arrays(tcache), _m_arrays(buffers)))) == 4
    # And neither a scheme register nor the observable hides in the state.
    @test isempty(intersect((:predictor, :predictor_points, :velocity_predictor, :velocity_at_particles),
                            fieldnames(Tracers)))
  end

  @testset "the traversal order is O(M) + O(tiles), owned by the run's ParticleTraversal alone" begin
    # Decision 86: the gathers' memory-locality order is a fourth owner, and its storage is bounded
    # by the tracer count and the tile count, never the grid — three M-vectors (the Int32 order, the
    # Int64 tile keys, the Bool validation mask) and two vectors of the tile count (the counting
    # sort's counts and offsets, (N/4)³ + 2 entries each at the default tile size 4). No (M, 3)
    # array joins the four above, and no field-scale array appears: the `FRAME + BASE + TRACER_DELTA`
    # ledger over a tracked run holds with TRACER_DELTA still ZERO (asserted above).
    M = 4
    sim = Simulation(domains[:TwoThirds]; viscosity = 0.1, number_of_particles = M,
                     rng = MersenneTwister(1))
    traversal = sim.particle_traversal
    @test traversal isa ParticleTraversal && traversal.automatic
    _m_arrays(owner) = (acc = AbstractArray[];
                        collect_field_arrays!(acc, owner, Set{UInt}(), 2; keep = a -> length(a) >= M);
                        [a for a in acc if length(a) >= M])
    owned = _m_arrays(traversal)
    tiles = ntuple(_ -> cld(N_AUDIT, 4), 3)
    expected = ((Int32, (M,)), (Int64, (M,)), (Bool, (M,)),
                (Int32, (prod(tiles) + 2,)), (Int32, (prod(tiles) + 2,)))
    @test sort(map(a -> (string(eltype(a)), size(a)), owned)) ==
          sort(map(t -> (string(t[1]), t[2]), collect(expected)))
    @test any(a -> a === traversal.order.indices, owned)      # the order itself is among them
    # The order is a permutation of the tracers — a stale order is never wrong, only less useful.
    @test sort(Int.(Array(traversal.order.indices))) == 1:M
    # No other owner reaches the traversal's arrays: the tracers, the cache, and the scheme's registers
    # hold exactly the four (M, 3) arrays counted above and nothing of the order.
    traversal_ids = Set(objectid.(owned))
    for owner in (sim.tracers, sim.cache, sim.particle_buffers)
      @test isempty([a for a in _m_arrays(owner) if objectid(a) in traversal_ids])
    end
    # Opted out, the run holds nothing of it.
    off = Simulation(domains[:TwoThirds]; viscosity = 0.1, number_of_particles = M,
                     ordered_interpolation = false, rng = MersenneTwister(1))
    @test off.particle_traversal === nothing
  end

  # The multistep scheme's extra storage is its SAMPLE HISTORY, and the history is a deposited
  # observable — so it is priced on the cache, not on the scheme's registers, and it scales with the
  # order rather than with the grid. Nothing else about the scheme costs storage: its weight solve
  # works in two `order`-element host vectors and its bootstrap reuses the one-step registers.
  @testset "the multistep particle integration scheme prices its history, and nothing else" begin
    domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π, element_type = Float64,
                         array_type = Array, dealiasing = TwoThirds())
    tracers = Tracers(domain; number_of_particles = 4, interpolation_scheme = CatmullRom)
    m_arrays(owner) = (acc = AbstractArray[];
                       collect_field_arrays!(acc, owner, Set{UInt}(), 2; keep = a -> length(a) >= 4);
                       [a for a in acc if size(a) == (4, 3)])
    for K in (1, 2, 4, 8)
      cache = ObservablesCache(domain; number_of_particles = npoints(tracers.positions),
                               history_depth = K)
      buffers = allocate_buffers(AdamsBashforth(order = K), tracers, cache)
      @test length(cache.velocity_at_particles_history) == K - 1     # the whole of the order's cost
      # The scheme's OWN registers are the bootstrap pair and nothing else. Walked from `buffers`
      # the count would be one higher, because the buffers now reach the cache holding the history —
      # which is the point of the refactor, and is priced on the line above, not here.
      startup_own = [a for a in m_arrays(buffers)
                     if !(objectid(a) in Set(objectid.(m_arrays(cache))))]
      @test length(startup_own) == 2
      @test length(cache.history_steps) == K - 1                  # host scalars, one per past sample
    end
  end

  @testset "op lists name real registers" begin
    # The symbolic values must correspond to actual storage: the chart slots on ObservablesCache,
    # products on ResolvedGenerator, spectral stage registers on IntegratorBuffers/ScalarBuffers.
    @test all(f -> f in fieldnames(ObservablesCache),
              (:velocity_physical, :vorticity_physical, :scalar_physical, :max_speed))
    @test :product_spectral in fieldnames(ResolvedGenerator)
    # The physical product register is gone (decision 41): the Lamb vector forms over the vorticity
    # slot and the scalar flux over the velocity slot — in place, alias-safe.
    @test !(:product_physical in fieldnames(ResolvedGenerator))
    IB = GBGIsotropicTurbulence.Propagator.IntegratorBuffers
    SB = GBGIsotropicTurbulence.Propagator.ScalarBuffers
    @test all(f -> f in fieldnames(IB), (:stage1, :stage2, :velocity_predictor_spectral, :nonlinear))
    # The integrating factor has NO register (decision 39), and the physical-representation
    # registers moved onto the cache slots (decision 40) — a step recovers INTO the charts it takes.
    @test !(:integrating_factor in fieldnames(IB))
    @test isempty(intersect((:velocity_star, :vorticity_physical), fieldnames(IB)))
    @test all(f -> f in fieldnames(SB), (:stage1, :stage2, :predictor_spectral, :nonlinear))
    @test isempty(intersect((:copy, :field), fieldnames(SB)))
    # The OU holds no evolving state and no noise field (decision 90): its process is in the record.
    @test isempty(intersect((:state, :noise_physical, :noise_spectral), fieldnames(StochasticOU)))
    @test :modeled in fieldnames(ResolvedFields)
  end

  @testset "the stochastic forcing's storage is set by its band, not by the grid" begin
    # Decision 90: the process is a field on a companion grid over the same box, so nothing it holds
    # scales with N. Measured against ONE of the run's own spectral vectors at a realistic grid.
    N = 64
    domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, element_type = Float64,
                         dealiasing = TwoThirds(), array_type = Array)
    ou = StochasticOU(domain; forcing_variance = 0.1, correlation_time = 0.5, seed = 1)
    û = new_vector_field_spectral(domain)
    state = initial_forcing_state(ou, û, domain)
    field_bytes = Base.summarysize(û)
    @test Base.summarysize(state) + Base.summarysize(ou) < OU_COMPANION_SHARE_AT_64 * field_bytes
    # …and none of it is counted as the run's residency, because none of it has the run's shape.
    @test _counts(Any[state, ou], N) == ZERO
  end

  @testset "liveness bounds and the gap register" begin
    # Every unforced cell sits AT its bound in every class (decision 40): the slot=register merge
    # closed the chart gap, deleting the cache's spectral scratch closed the ownership gap, and
    # deleting the scalar copy register closed the scalar gap — each holder retired in the same
    # commit. This equality CAN fail: extend a register's life past the schedule's need (or add a
    # resident buffer) and the ledger rises off the bound with no holder to claim it.
    for (scheme, ops_of) in ((:RK3, rk3_ops), (:SSPRK3, ssprk3_ops), (:RK2, rk2_ops)), scalar in (false, true)
      @test peak_liveness(ops_of(scalar)) == BASE[(scheme, :TwoThirds, scalar)]
    end
    # PhaseShift's displaced-evaluation registers are working values like any other, and its cells
    # sit at the bound too.
    @test peak_liveness(rk3_ops(true; phase_shift = true)) == BASE[(:RK3, :PhaseShift, true)]

    # The OU-forced cell sits at its bound too (decision 90): nothing of the forcing is field-scale,
    # so the ledger and the bound are the unforced cell's, and the gap register is empty.
    ou_ops = rk3_ops(false; ou = true)
    ou_achieved = _add(BASE[(:RK3, :TwoThirds, false)], _forcing_delta(:ou, :velocity))
    @test peak_liveness(ou_ops) == ou_achieved
    @test isempty(GAP_HOLDERS)

    # The physical-vector floor, in numbers: TWO registers — the chart slots, doubling as the
    # substage recovery registers AND as the quadratic products' in-place targets (decision 41) —
    # with the three vectors retired since decision 37 (the two-chart gap + the product register,
    # 1.15 GiB at 256³ / Float64) banked, not held.
    for (scheme, ops_of) in ((:RK3, rk3_ops), (:SSPRK3, ssprk3_ops), (:RK2, rk2_ops)), scalar in (false, true)
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
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5, envelope_wavenumber = 2.0, rng = MersenneTwister(1))
    φ̂ = new_scalar_field_spectral(domain)
    random_scalar_spectral!(φ̂, domain; scalar_variance = 1.0, envelope_wavenumber = 2.0, rng = MersenneTwister(2))
    sim = Simulation(grid_points_per_axis = N, viscosity = 0.05; scalar = true, rng = MersenneTwister(3))
    episodes = Dict(
      "seed velocity" => () -> random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5,
                                                           envelope_wavenumber = 2.0, rng = MersenneTwister(1)),
      "seed scalar" => () -> random_scalar_spectral!(φ̂, domain; scalar_variance = 1.0,
                                            envelope_wavenumber = 2.0, rng = MersenneTwister(2)),
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
    for dealiasing in (TwoThirds(), HouLi(), PhaseShift()), scheme in (IFLowStorageRK3(), IFHeun()),
        scalar in (false, true)
      sim = Simulation(grid_points_per_axis = N, viscosity = 0.05; dealiasing, scalar,
                       field_integration_scheme = scheme, rng = MersenneTwister(1))
      advance!(sim; dt = 1e-3); advance!(sim; dt = 1e-3)          # warm before measuring
      @test (@allocated advance!(sim; dt = 1e-3)) < 0.5 * unit
    end
  end
end
