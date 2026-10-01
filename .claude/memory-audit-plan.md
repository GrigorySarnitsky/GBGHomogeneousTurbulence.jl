# Memory audit: from ledgers to a bound on the whole run

Status: draft 5, 2026-10-01, after four adversarial rounds. Not started.

## What the instrument is

A tool that **lists possible memory defects**: every gap between what a run allocates and the floor
it could reach, with its size, its stage, its configuration, and the evidence, ranked by bytes.
Fixing them is a separate matter, decided per entry. A gap can be a legitimate trade — 10% more
memory for 10% more speed is a fair exchange.

This is not a new shape. `test/optimality_audit.jl` already holds every compute and synchronization
cell against a floor, and every gap above it needs a `Holder` with a disposition, in a register that
fails both ways — on a gap no holder claims, and on a holder whose gap has gone. The same rule is
implemented three more times with other spellings: the transform and fusion gap dictionaries of
`test/compute_audit.jl`, the traffic audit's holder strings (`test/pass_audit.jl`, through
GBGCodingTools), and the memory liveness gap register. The memory entries join that register; they
do not start a parallel list.

The dispositions are the existing three:

- **`:FIX`** — a local win, kept on the frozen open list until taken, then retired in the same
  commit;
- **`:PF_RAISE`** — a request against a backend, the gap not ours to close (generalised to name the
  backend, since GBGCodingTools requests exist too);
- **`:DESIGN`** — a cost the owner adopted, citing its decision. Strengthened for every audit, not
  only memory: the holder carries both measured sides — what it costs (bytes, passes, transforms,
  host crossings) and what it buys, either a measured time or a named property (the one existing
  `:DESIGN` holder, the uniform deposit schedule, buys the impossibility of a stale read, not
  speed). A `:DESIGN` holder without its measured cost and its stated gain fails the register.

The suite fails only on a gap no holder claims, or a holder whose gap has gone. A recorded gap is a
listed item, not a failure. The report is one list across every audit — memory, compute, traffic,
synchronization — ranked within each by its own unit. Everything below exists to make the memory
part of that list complete: a gap the instrument cannot see is a gap missing from the list.

## Why

The memory audit claims to bound what a run needs, and it does not. It is a union of ledgers, each
complete within itself, and nothing checks that the union covers every stage of a run.

- The resident ledger (`test/memory_audit.jl`, working set + frame) is derived: it walks every
  field-sized array a live `Simulation` reaches, and a completeness test requires the two ledgers to
  account for all of them. The walk (`collect_field_arrays!`, `test/audit_ops.jl:58–74`) has four
  blind spots, each reproduced on a fixture: closures (`!(x isa Function)`, line 66), the elements
  of an array whose element type is not a number (a `Vector` of structs; a `Dict`'s values, which
  sit in such a vector), a closure's reassigned capture behind a `Core.Box`, and a view counted
  again beside its parent. An extended walk run on five live CPU configurations finds exactly what
  the current one finds, so these hide no field-scale array today; they are holes the next storage
  choice falls into. The particle sample history (`src/Cache.jl:151`) is stored in the second shape,
  and its test (`test/memory_audit.jl:592`) counts the slots, not their bytes.
- The temporary ledger (`EPISODE_UNITS`, `test/memory_audit.jl:405`) is a hand-written list of six
  episodes. Construction, checkpointing, and every observable added after it were never on it.
- The zero-storage floor for a function of |κ|² is demonstrated only for the `FixedDomain`. A symbol
  stored in the working set, as `Linear`'s rate is, is measured and frozen but never held against
  that floor.
- The liveness bound is built from the unforced step lists (`rk3_ops` and `rk4_ops` take only an
  `ou` forcing keyword); the forcing deltas are "priced on the forcing axis" and never bounded.
- Every scaling statement is in the grid size N. The particle count M, the multistep order K, and a
  forcing's band (which sizes `StochasticOU`'s companion grid, `src/Forcing.jl:1337`) are never
  scaling axes.
- Every CPU measurement reads Julia's heap. Memory the C libraries allocate themselves is invisible
  to them: under `FFTW.MEASURE` a 48³ domain raises the resident set by 1.2 MB against 0.07–0.17 MB
  on the heap.

Measured on the CPU at 32³, Float64, in N³ reals (default resident set ≈ 19); re-measured
independently at 16³, 32³, 64³, every row but one flat in these units:

| stage | transient | ledgered |
|---|---|---|
| scalar observables | ≈ 0 | — |
| `derivative_skewness` | 18.6 | yes |
| seeding inside `Simulation` | 6.2 (8.2 with a scalar) | yes |
| `kinetic_energy_and_dissipation_below_scale` | 0.7 at 32³, sub-cubic in N | no |
| `FixedDomain` construction | 11.4 | no |
| `ResolvedGenerator` with `Linear` | 4.3, plus resident 1.06 with no floor | no |
| `write_simulation` | 4.3 on the heap; its resident-set rise is flat in N | no |
| `read_simulation` | 25.4 (independently: 49.8 MB over a plain build at 64³, within 7%) | no |

Causes identified: `src/SimulationDomain.jl:303` builds a local `velocity_physical` and never reads
it, and a vector template serves the multipliers and the mask where the scalar one would do;
`read_simulation` builds a `Simulation` that seeds a state it then overwrites
(`ext/GBGHomogeneousTurbulenceHDF5Ext.jl:426–448`) and reads each field through a host staging
array; the rate probe (`src/Generator.jl:234–250`) allocates a vector probe and a second rate that
are discarded.

## What will be claimed at the end, and what will not

Not "everything is covered": no procedure decides that for a program in general. The claim will be
exactly this, each part checked:

1. **Coverage of the public surface** — every exported function and constructor has a temporary
   row, or a stated exemption. Exhaustive over a finite set derived from the export list.
2. **Floors** — every resident cost is held against a floor argued from the mathematics, and every
   gap above a floor is a listed entry with its disposition.
3. **The whole-run bound** — a theorem with named assumptions (below). P is what the ledgers say a
   run needs, every listed gap included; the theorem's role is to show the ledgers miss nothing,
   which is what makes the list complete.
4. **The empirical check** — the top-down run, the leg each assumption rests on, and what it does
   not reach, stated in the file.

### The theorem

A run is a sequence of stages: build the domain; build the run (buffers, cache, generator, state,
tracers); seed; step; warm up; observe; checkpoint; restore. For a stage s and a memory space σ
(device or host) let R_σ(s) be the ledgered resident bytes in σ when s begins, and T_σ(s) the peak
of all bytes concurrently live in σ during s beyond R_σ(s) — including whatever s builds that
becomes part of R_σ(s+1). Then, in each space,

    peak_σ ≤ P_σ := max_s ( R_σ(s) + T_σ(s) )

provided:

- **A1 (sequential)** stages do not overlap: the run is single-threaded at the Julia level. CUDA.jl's
  background pool-trimming task only calls `reclaim()`, so it cannot raise a peak.
- **A2 (reclaimed)** the temporaries of a finished stage are not live when a later stage allocates.
  Leg: the collection at every stage boundary, and the process-growth checks. Named exception:
  cuFFT keeps a released plan in a process-wide cache (`idle_handles`,
  `~/.julia/packages/cuFFT/*/src/wrappers.jl`), so its workspace survives `GC.gc(true)` and
  `CUDA.reclaim()` (measured at 128³: 8.4 MB of 41.9 MB not returned; a second plan of the same
  shape then cost only the difference). That retention is resident memory, and is itself a listed
  entry.
- **A3 (no fragmentation loss)** a request for B bytes succeeds when B bytes are free. Leg: the
  limit runs.
- **A4a (resident scaling)** R_σ is a·N³ + b·M + c·(K − 1)·M + d·N_c³ + O(N²), with N_c a companion
  grid's size and coefficients derived in closed form from the ledger's shape classes.
- **A4b (temporary scaling)** T_σ has the same form, with coefficients *measured* at three points on
  each axis and asserted to fit that form within a stated tolerance. This is an empirical fit
  against a form chosen beforehand, not a derivation; the fit is never refitted to the top-down
  measurements it is checked against.
- **A5 (precision and backend)** precision and backend change bytes, never counts. Leg: both
  precisions, and the ROCm run on Aiporetne.
- **A6 (outside the heap and the pool)** allocations neither Julia's heap nor the device pool sees
  are measured: on the device, cuFFT workspaces and library handles, read from the driver; on the
  host, FFTW's planner and HDF5's buffers, read from the process's resident set.
- **A7 (the configuration space)** is derived from the code where the code defines it, and stated
  by convention where it does not:
  - derived: the `subtypes` of `AbstractForcing`, `AbstractIntegrator`, `DealiasingStrategy`,
    `AbstractParticleIntegrator`; scalar off, or on with each scalar forcing the constructor accepts
    (all six but `VarianceController` with its default `turnover_time`); tracers off, `Heun`, or
    `AdamsBashforth` with its order K;
  - by convention: `interpolation_scheme` is a family with parameters (`CatmullRom`,
    `LalescuSpline(n, m)`, `LagrangeSpline(n)`), swept as one representative of each and the widest
    stencil in use; `fft_flags` takes FFTW's planner modes (`nothing`, `ESTIMATE`, `MEASURE`), named
    here because FFTW owns them;
  - every keyword of every constructor a run goes through (`Simulation`, `FixedDomain`, `Tracers`,
    `ParticleTraversal`, each forcing, `ResolvedGenerator`, `FlowConditions`, `ObservablesCache`,
    `allocate_buffers`, `ResolvedFields`) is classified as a categorical axis, a scaling axis, or
    memory-neutral with a reason — a new keyword fails until classified. `ObservablesCache`'s
    `history_depth` and `AdamsBashforth`'s order are one axis, K, since the code requires them to
    agree.
- **A8 (the measurements measure)** every reading is falsified before it is trusted:
  - device: the pool's used high-water mark must show a known allocation. A pool handle taken before
    the first allocation is the driver's stock pool, whose statistics never move; the handle is taken
    from `CUDA.memory_pool(device())` after one allocation. Writing 0 resets the mark to the current
    use (confirmed);
  - device limit: the effective limit is the requested one rounded up to a multiple of 32 MiB
    (measured 2026-10-01: 16 MiB admits 24 and refuses 40; 64 admits 40 and refuses 72; 256 admits
    136 and refuses 264). The script re-measures the granularity on each machine before using a
    limit;
  - host: the peak resident set (`VmHWM`) must show a known allocation, and writing `5` to
    `/proc/self/clear_refs` resets it to the current resident set (confirmed);
  - CPU rows split kept from transient with the shared frame excluded, never by subtracting a
    `summarysize` that may count shared storage.
- **A9 (no other use of the GPU changes during a reading)** the driver's free memory is
  device-wide, and on this workstation the desktop holds about 280 MiB of the GPU in graphics
  processes, which `nvidia-smi --query-compute-apps` does not list (it returned no rows while
  `gnome-shell`, `nautilus`, `Xwayland` and others were resident). Leg: before and after the run,
  and around each configuration, the full `nvidia-smi` process table — graphics and compute — is
  recorded; any compute process but the run's own fails the pre-flight; the graphics total must
  stay within a stated tolerance across each configuration, or that configuration's device reading
  is discarded and repeated. A run on a session without a display removes the term.

### How the check decides

Both high-water marks — the device pool's and the host's peak resident set — include garbage not
yet collected and compiled code, so they bound the live peak from above. That makes the decision
one-sided, in each space separately:

- **Pass in process.** A configuration passes when its measured peak is at most P_σ, with the
  device peak the pool's used high-water mark plus the memory outside the pool, defined exactly as
  (total − free) − the pool's reserved bytes − the baseline taken before the configuration. The
  baseline holds the CUDA context and handles, 630–690 MiB on this machine, which dwarfs a small
  grid's fields, so a reading is always a difference over the baseline, never an absolute value.
- **Arbitrate in a fresh process.** A configuration over P_σ in either space is inconclusive, since
  the excess may be garbage. It reruns in a fresh process: on the device under
  `JULIA_CUDA_HARD_MEMORY_LIMIT` set to P_device plus a tolerance (the limit is read once per
  process, so never set inside one), with the driver's outside-pool reading also compared to its
  share of P, since the limit governs the pool only; on the host under a cgroup cap
  (`systemd-run --user --scope -p MemoryMax=… -p MemorySwapMax=0`, confirmed to kill a process above
  the cap). The host cap cannot be P_host alone: loading Julia, the package, CUDA and HDF5 already
  takes about 1.5 GB of resident memory (measured: 268 MB bare, 358 MB with the package, 1522 MB
  with CUDA, 1546 MB with HDF5), far above a small configuration's P_host. So a first fresh process
  under the same cap loads everything the arbitration run loads and stops, its peak resident set is
  the host baseline, and the arbitration cap is that baseline plus P_host plus the tolerance. It
  passes only if it completes and the outside-pool reading holds.
- **Tightness, so the bound cannot pass by being loose.** A fixed representative set also runs in
  fresh processes under P_σ minus a margin and must fail. The margin is a stated fraction of P_σ and
  must exceed the device limit's granularity several times over, so the tightness runs are at grids
  where that holds (about 192³ and above for the default run), not at the small sweep sizes. A
  bound that survives at P_σ minus the margin is a finding.
- **Tolerance and margin are fixed before the run,** in the file, and changing either is a commit
  of its own with its reason.

## Stage 1 — the instrument, before any fix

1. **Derived temporary ledger.** Replace `EPISODE_UNITS` with a table whose required set is the
   export list (the pattern of `TestHarness.allocation_completeness`). An in-place operation already
   bounded below field scale by `test/allocations.jl` is cited, not repeated; every other export and
   constructor gets a row or an exemption with a reason. An exported operation that calls into the
   unexported `Phenomenology` leaf is measured through its own row; `Phenomenology`'s own functions
   are outside the surface until it is extracted. The unexported `StationarityMonitor` is reached
   through `warmup!`'s row; its histories are trimmed to a window of about 40 entries, so the row
   asserts a bound independent of the run's length.
2. **The missing rows**, each at three grid sizes with its scaling asserted, and each reading the
   host resident set beside the heap: `FixedDomain` per `fft_flags` mode; `ResolvedGenerator` per
   forcing; `Simulation` per forcing, with seeding separated; `Tracers`, `ParticleTraversal` and the
   particle buffers at three particle counts and three orders K; `StochasticOU` at three bands; all
   ten checkpoint functions (`write_`/`read_` × `domain`, `state`, `tracers`, `forcing`,
   `simulation`); `kinetic_energy_and_dissipation_below_scale`; `warmup!`.
3. **The walk sees everything reachable, once, in the right space.** `collect_field_arrays!`
   descends into closures' captures, unwraps `Core.Box` and `Ref`, and descends into the elements of
   an array whose element type is not a number and into a `Dict`'s values. It counts an array once
   by its storage (a view and its parent are one), and tags each array by its storage type, so a host
   array inside a GPU run — `StochasticOU`'s draw buffer, a host `Array` by design
   (`src/Forcing.jl:1360–1367`) — is ledgered as host memory. The field and particle ledgers are
   partitioned by the root each array is reached from, not by a length threshold, which can collide
   at small grids. The particle sample history is then walked by bytes, and its test asserts the
   bytes, not the slot count.
4. **Floors for the working set's symbols.** Extend the frame's zero-storage demonstration to every
   resident array a forcing or the generator adds: an array that is a function of |κ|² is
   reconstructed from the axis multipliers inside the test, and its residency becomes a listed entry
   (`Linear`'s rate, with the PF request below as its candidate remedy). The forcing deltas join the
   liveness bound.
4a. **One register.** The memory entries use `Holder` and its two-way test. The compute audit's
   dictionaries and the memory liveness register move onto `Holder` too, so every audit's gaps are
   one type with one test, and `:DESIGN` is strengthened as above for all of them; the existing
   `:DESIGN` holder gains its measured cost (one host crossing per iteration on a fixed-Δt path) and
   its named gain. The report function prints the whole register, ranked, with each holder's
   evidence.
5. **The written bound.** The theorem, A1–A9, and the decision rule head the top-down file, beside
   a function computing P_σ per stage from the ledgers alone.
6. **The top-down GPU run** (this machine, not CI; before a release and whenever a ledger changes):
   - pre-flight: no other compute process on the GPU and the graphics total recorded (A9); the
     limit granularity re-measured (A8);
   - the configurations: the full product of the categorical axes at one base scaling point; each
     scaling axis at its three points around that base; the four corners of each pair of scaling
     axes; and each value of each categorical axis at each scaling axis's largest point, so that both
     scaling × scaling and categorical × scaling additivity are tested; both precisions. The script
     prints the enumerated count, and the first full run records its time. Today's estimate is hours,
     dominated by compiling each new combination of types;
   - each configuration runs twice in the same process. The pool and heap readings are taken on the
     second run, so compiled code is not charged to the configuration. The outside-pool reading of
     the domain-build stage is taken on the *first* run that builds each distinct transform shape,
     and charged to that stage, since the cuFFT workspace is a real cost a production run pays once
     per shape and the second run would find it already cached (A2's exception);
   - each from a clean baseline: its objects dropped, `GC.gc(true)`, `CUDA.reclaim()` (confirmed to
     return the pool to zero at 32³), and the baseline readings recorded;
   - at every stage boundary `CUDA.synchronize()`, then `GC.gc(true)`, then the readings — the pool's
     used high-water mark and the host's peak resident set, each reset at the boundary; the driver's
     free memory; the pool's reserved bytes; the heap. `synchronize` completes the device's work but
     frees nothing; the collection is what returns a finished stage's garbage;
   - the decision rule above, with the fresh-process arbitration and the tightness runs;
   - process-growth checks: after the warm-up, the same configuration built and dropped repeatedly,
     and a sequence of distinct configurations, must each return to the baseline, so a cache that
     outlives its run (FFTW or cuFFT plans, handles) is caught;
   - a ROCm leg on Aiporetne, the same script with that backend's readings.
7. **Planted defects**, each named with the leg that must catch it, re-planted as a regression test:
   - an unused field-sized array stored in a struct — the resident walk (CPU, every `Pkg.test()`);
   - an unused field-sized local temporary in a constructor, the shape of the real
     `velocity_physical` — the constructor's temporary row (CPU, every `Pkg.test()`);
   - a new export that allocates a field — the derived temporary ledger (CPU, every `Pkg.test()`);
   - a temporary added to the restore path — its row (CPU, every `Pkg.test()`);
   - a resident symbol added to a forcing — the working-set floor (CPU, every `Pkg.test()`);
   - arrays held by a closure over two captures, one of them boxed; by a struct inside a `Vector`; by
     a `Dict`; and a view beside its parent, which must count once — the walk (CPU, every
     `Pkg.test()`);
   - a host array inside a device run — the storage-type tag (CPU, every `Pkg.test()`);
   - a stage that throws partway, after allocating — the baseline must still be restored after the
     caught exception (CPU rows, and the GPU leg);
   - an allocation outside the pool — the driver reading (GPU leg only);
   - a host buffer allocated in C and retained across checkpoint calls — the host peak resident set
     (CPU rows) and the process-growth checks (GPU leg);
   - a bound made loose by doubling one ledger coefficient — the tightness runs (GPU leg only).
   The GPU-only plants are exercised only when the GPU leg runs; `Pkg.test()` says so when it skips
   them, and does not report them as passed.

## Stage 2 — the first entries on the list (outside this plan)

The gaps found while drafting are the list's first entries, recorded with candidate remedies and no
disposition; each is decided on its own, after the instrument measures it:

8. `FixedDomain`: the unused local `velocity_physical`, and the vector template where the scalar
   one would do. Candidate: delete it; build from the scalar field.
9. `read_simulation`: a seeded state that is then overwritten, and reading through host staging.
   Candidate: a constructor route that skips seeding; read into the run's own storage.
10. The checkpoint staging on the GPU: where it lives (host or device) is not yet measured.
    Candidate: bound it, or stream one component at a time.
11. The generator's steadiness probe: a vector probe and a second rate, discarded. Candidate: probe
    with buffers the run already allocates.
12. `Linear`'s resident rate (below), and cuFFT's process-wide plan cache (A2): each a candidate
    trade-off, to be listed with both sides measured.

## Stage 3 — requests and closing

13. **To PF**: let `exponential_convolve!` take its offset as a radial symbol, not only a stored
    field — the remedy `Linear`'s entry would need if its disposition is "fix". If it lands and is
    taken, one commit retires everything that records the rate as resident: the `Linear` delta in
    `_forcing_delta` and its comment block in `test/memory_audit.jl`, the working-set floor's entry,
    the traffic audit's two-call rate holder, and the probe's second array.
14. **To GBGCodingTools**: two engines, both general, not physics — by the rulebook TestHarness
    engines HT declares. First, the gap register: floor, achieved, holder with disposition, the
    two-way test, the strengthened `:DESIGN` rule, and the ranked report, one engine for every audit
    and every package (the traffic audit's holders are already there in a narrower form). Second,
    the top-down peak check, beside the GPU-timing-against-minimum-traffic check PF is raising. HT
    builds both locally only until the engines exist, then declares them.
15. **Close**: an independent reviewer (a fresh agent or the GBGCodingTools session) audits the
    finished instrument; the first report is the list itself, ranked by bytes, with the claim in the
    form above and what it does not reach.

## What this will not reach

- Memory a dependency allocates that neither the pool, the driver nor the process's resident set
  attributes to a stage: seen only as a change in free memory, not attributed.
- Multi-GPU and multi-threaded runs (A1 fails), and a shared GPU (A9 fails).
- Values of a scaling axis outside its three swept points are covered by the asserted scaling (A4),
  not by measurement; interactions beyond pairs of axes are assumed additive.
- Parameter values of an interpolation family beyond the representatives swept.
- The full categorical product is measured at one base scaling point; the fresh-process arbitration
  and the tightness runs cover a stated subset, and tightness only at grids large enough for the
  device limit's granularity.
- The GPU-only plants and legs run when someone runs the GPU leg, not on every `Pkg.test()`.

## Review record

Round 1 (2026-09-30): M, history depth and band as scaling axes; the checkpoint primitives named;
`interpolation_scheme` an axis; plan caches outliving a configuration; the high-water mark demoted
from verdict; the closure blindness fixed; teardown and synchronization; three sizes; GPU-only plants
scoped; T(s) defined; the PF request's retirement set; a host-leak plant; the background task.

Round 2 (2026-09-30): the hard limit is read once per process, so the verdict became one-sided in
process with fresh-process arbitration; tightness runs; the walk's element and `Core.Box` blind
spots; the "unused array" plant split; the pool-handle trap corrected; three points per axis; host
memory outside the heap; `Phenomenology` scoped; a warm-up; the configuration count enumerated.

Round 3 (2026-10-01), every finding folded in:
- the device limit has a 32 MiB granularity (measured), so tightness runs only at large grids, and
  the granularity is re-measured before use;
- the host reading was a snapshot, not a high-water mark: now the peak resident set, reset per stage
  (confirmed), with a cgroup-capped fresh process as the host's arbitration (confirmed);
- the arbitration re-reads the memory outside the pool, whose definition is now exact, as a
  difference over a baseline that holds the 630–690 MiB context;
- exclusive use of the GPU is an assumption with a pre-flight check (A9);
- A4 split into the derived resident half and the measured temporary half;
- categorical × scaling corners added;
- A2 given its legs;
- compiled code kept out of the readings by measuring each configuration's second run;
- the walk counts a view once, tags arrays by storage (a host array inside a GPU run), and
  partitions field and particle ledgers by root;
- `ParticleTraversal` added to the constructors; K made one axis; `interpolation_scheme` and
  `fft_flags` given conventions, since the code does not enumerate them;
- `StationarityMonitor`'s histories bounded by their window, not by the run's length;
- an exception-path plant, a multi-capture closure plant, and a process-growth check across
  distinct configurations;
- the "Why" corrected: the walk's blind spots hide no field-scale array today.

Round 4 (2026-10-01), one combined reviewer; three substantive findings, each verified on this
machine, all folded in:
- cuFFT keeps released plans in a process-wide cache that `GC.gc` and `CUDA.reclaim` do not empty,
  so measuring only the second run would delete a real cost: the domain-build stage's outside-pool
  reading now comes from the first run of each transform shape, and the cache is a listed entry;
- the host cap had no baseline, and loading the stack alone takes about 1.5 GB: the cap is now a
  measured post-load baseline plus P_host plus the tolerance;
- the compute-only process query misses the desktop's graphics processes (about 280 MiB here): the
  full process table is recorded, and the graphics total must hold steady across a configuration.

Reframed the same day by the owner: the instrument lists possible defects; fixing them is separate,
and a measured trade-off (memory for speed) is a legitimate disposition. Stage 2 became the list's
first entries, without dispositions.

Amended the same day, owner-ruled: the defect list is the shape the compute side already has. The
memory entries join `test/optimality_audit.jl`'s `Holder` register rather than a parallel list;
every audit's register moves onto that one type; `:DESIGN` must carry its measured cost and its
measured or named gain; and the register becomes a GBGCodingTools engine request.
