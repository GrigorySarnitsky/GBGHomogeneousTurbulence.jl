# Memory audit: from ledgers to a bound on the whole run

Status: draft 3, 2026-09-30, after two adversarial rounds (coverage, soundness, facts each). Not
started.

## Why

The memory audit claims to bound what a run needs, and it does not. It is a union of ledgers, each
complete within itself, and nothing checks that the union covers every stage of a run.

- The resident ledger (`test/memory_audit.jl`, working set + frame) is derived: it walks every
  field-sized array a live `Simulation` reaches, and a completeness test requires the two ledgers to
  account for all of them. But the walk (`collect_field_arrays!`, `test/audit_ops.jl:58–74`) has
  three blind spots, each confirmed: it skips closures (`!(x isa Function)`, line 66); it tests an
  array as one leaf and never descends into its elements, so an array held by a struct inside a
  `Vector` or a `Dict` is invisible (a `Vector{Holder}` of two field arrays: 0 found); and a
  closure's reassigned capture sits behind a `Core.Box`. The particle sample history is stored in
  exactly the second shape (`src/Cache.jl:151`, a `Vector` of point-value sets); its test counts the
  slots, not their bytes.
- The temporary ledger (`EPISODE_UNITS`, `test/memory_audit.jl:405`) is a hand-written list of six
  episodes. Construction, checkpointing, and every observable added after it were never on it.
- The zero-storage floor for a function of |κ|² is demonstrated only for the `FixedDomain`. A symbol
  stored in the working set, as `Linear`'s rate is, is measured and frozen but never held against
  that floor.
- The liveness bound is built from the unforced step lists (`rk3_ops` and `rk4_ops` take only an
  `ou` forcing keyword); the forcing deltas are "priced on the forcing axis" and never bounded.
- Every scaling statement is in the grid size N. The particle count M, the sample-history depth, and
  a forcing's band (which sizes `StochasticOU`'s companion grid, `src/Forcing.jl:1337`) are never
  scaling axes.
- Every CPU measurement reads Julia's heap. Memory the C libraries allocate themselves — FFTW's
  planner (1.2 MB of resident host memory at 48³ under `FFTW.MEASURE`, against 66 KB on the heap)
  and HDF5's buffers — is invisible to all of them.

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
| `write_simulation` | 4.3 | no |
| `read_simulation` | 25.4 | no |

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
   gap above a floor carries a named holder.
3. **The whole-run bound** — a theorem with named assumptions (below).
4. **The empirical check** — the top-down run, the leg each assumption rests on, and what it does
   not reach, stated in the file.

### The theorem

A run is a sequence of stages: build the domain; build the run (buffers, cache, generator, state,
tracers); seed; step; warm up; observe; checkpoint; restore. For a stage s let R(s) be the ledgered
resident set when s begins, and T(s) the peak of all bytes concurrently live during s beyond R(s) —
including whatever s builds that becomes part of R(s+1). Then, on each memory space (device, host),

    peak ≤ P := max_s ( R(s) + T(s) )

provided:

- **A1 (sequential)** stages do not overlap: the run is single-threaded at the Julia level. CUDA.jl's
  background pool-trimming task only calls `reclaim()`, so it cannot raise a peak.
- **A2 (reclaimed)** the temporaries of a finished stage are not live when a later stage allocates.
  On the GPU, CUDA.jl collects and retries on allocation failure, so the property that matters is
  that the run *fits*.
- **A3 (no fragmentation loss)** a request for B bytes succeeds when B bytes are free.
- **A4 (scaling)** each stage's bytes are a·N³ + b·M + c·(K − 1)·M + d·N_c³ + O(N²), with K the
  multistep order that sets the history depth, N_c a companion grid's size, and the coefficients
  derived from the ledger's shape classes — never fitted to the measurements they are checked
  against. Each axis is checked at three points.
- **A5 (precision and backend)** precision and backend change bytes, never counts. Tested by running
  both precisions, and ROCm on Aiporetne.
- **A6 (outside the heap and the pool)** allocations neither Julia's heap nor the device pool sees —
  cuFFT/rocFFT workspaces and handles on the device; FFTW's planner and HDF5's buffers on the host —
  are measured: the driver's free memory on the device, the process's resident set on the host.
- **A7 (the configuration space)** is derived from the code: the `subtypes` of `AbstractForcing`,
  `AbstractIntegrator`, `DealiasingStrategy`, `AbstractParticleIntegrator` (with `AdamsBashforth`'s
  order K), and every keyword of the constructors a run goes through (`Simulation`, `FixedDomain`,
  `Tracers`, each forcing, `ResolvedGenerator`, `FlowConditions`, `ObservablesCache`,
  `allocate_buffers`, `ResolvedFields`), each classified as a categorical axis, a scaling axis, or
  memory-neutral with a reason — a new keyword fails until classified. Among them:
  `interpolation_scheme` and `fft_flags` are categorical; `number_of_particles` and the band edges
  are scaling axes.
- **A8 (the measurements measure)** every reading is falsified before it is trusted: after a known
  allocation, the pool's used high-water mark must show it. The trap is that a pool handle taken
  before the first allocation is the driver's stock pool, whose statistics never move; the handle is
  taken from `CUDA.memory_pool(device())` after one allocation, public API only. The high-water mark
  is reset by writing 0, which the driver takes as "reset to current". A CPU row's kept-versus-
  transient split is computed with the shared frame excluded, not by subtracting a `summarysize`
  that may count shared storage.

### How the check decides

Measured high-water marks include garbage not yet collected, so they bound the true live peak from
above. That makes the decision one-sided and sound:

- **Pass in process.** A configuration passes when its measured device peak — the pool's used
  high-water mark plus the driver-reported memory outside the pool — is at most P, and likewise on
  the host. An upper estimate below the bound proves the bound holds for that run.
- **Arbitrate in a fresh process.** A configuration whose measured peak exceeds P is inconclusive,
  since the excess may be garbage. It reruns in a fresh `julia` process started with
  `JULIA_CUDA_HARD_MEMORY_LIMIT` set to P plus a stated tolerance, and passes only if it completes.
  The limit is read once per process and baked into the pool at first use (confirmed on the GPU), so
  it cannot be set per configuration within one process. It governs the pool only; the driver
  reading covers the rest.
- **Tightness, so the bound cannot pass by being loose.** A fixed representative set — every
  forcing, and each scaling axis at its largest point — also runs in fresh processes under a limit of
  P minus a stated margin, and must fail with an out-of-memory error. The margin is stated as a
  fraction of P, and a bound that survives at P minus the margin is a finding. The same runs test A3.

## Stage 1 — the instrument, before any fix

1. **Derived temporary ledger.** Replace `EPISODE_UNITS` with a table whose required set is the
   export list (the pattern of `TestHarness.allocation_completeness`). An in-place operation already
   bounded below field scale by `test/allocations.jl` is cited, not repeated; every other export and
   constructor gets a row or an exemption with a reason. An exported operation that calls into the
   unexported `Phenomenology` leaf is measured through its own row; `Phenomenology`'s own functions
   are outside the surface until it is extracted.
2. **The missing rows**, each at three grid sizes with its scaling asserted: `FixedDomain`, per
   `fft_flags`, with the host resident set read beside the heap; `ResolvedGenerator` per forcing;
   `Simulation` per forcing, with seeding separated; `Tracers` and the particle buffers at three
   particle counts and three orders K; `StochasticOU` at three bands; all ten checkpoint functions
   (`write_`/`read_` × `domain`, `state`, `tracers`, `forcing`, `simulation`), each with the host
   resident set read beside the heap; `kinetic_energy_and_dissipation_below_scale`; `warmup!`
   (O(samples) growth, and the skewness temporary when that gate is on).
3. **The walk sees everything reachable.** `collect_field_arrays!` descends into closures'
   captures, unwraps `Core.Box` and `Ref`, and descends into the elements of an array whose element
   type is not a number and into the values of a `Dict`. The particle sample history is then walked
   by bytes, and its test asserts the bytes, not the slot count.
4. **Floors for the working set's symbols.** Extend the frame's zero-storage demonstration to every
   resident array a forcing or the generator adds: an array that is a function of |κ|² is
   reconstructed from the axis multipliers inside the test, and its residency becomes a gap with a
   holder (`Linear`'s rate → the PF request below). The forcing deltas join the liveness bound.
5. **The written bound.** The theorem, A1–A8, and the decision rule head the top-down file, beside
   a function computing P per stage from the ledgers alone, so the check compares numbers of
   independent origin: the ledger sum and a measurement.
6. **The top-down GPU run** (this machine, not CI; before a release and whenever a ledger changes):
   - the configurations: the full product of the categorical axes at one base scaling point, and
     each scaling axis at its three points around that base with the other axes fixed, plus the
     four corners of each pair of scaling axes, so additivity (A4) is tested; both precisions. The
     script prints the enumerated count, and the first full run records its time; the estimate
     today is hours, not minutes, dominated by compiling each new combination of types;
   - one warm-up configuration before any baseline, so first-time kernel compilation and library
     loading are not charged to a configuration;
   - each configuration from a clean baseline: its objects dropped, `GC.gc(true)`, `CUDA.reclaim()`
     (confirmed to return the pool to zero at 32³), and the baseline driver and pool readings
     recorded;
   - at every stage boundary `CUDA.synchronize()`, then `GC.gc(true)`, then the readings: the pool's
     used high-water mark, reset per stage; the driver's free memory; the host heap
     (`Base.gc_live_bytes`) and resident set. `synchronize` completes the device's work but frees
     nothing; the collection is what returns a finished stage's garbage, and a stage's own garbage
     still counts in its reading, which is why the reading is an upper estimate;
   - the decision rule above, with the fresh-process arbitration and the tightness runs;
   - a process-growth check: after the warm-up, the same configuration built and dropped repeatedly
     must return to its baseline, so a cache that outlives its run (FFTW or cuFFT plans, handles) is
     caught;
   - a ROCm leg on Aiporetne, the same script.
7. **Planted defects**, each named with the leg that must catch it, re-planted as a regression test:
   - an unused field-sized array stored in a struct — the resident walk (CPU, every `Pkg.test()`);
   - an unused field-sized local temporary in a constructor, the shape of the real
     `velocity_physical` — the constructor's temporary row (CPU, every `Pkg.test()`);
   - a new export that allocates a field — the derived temporary ledger (CPU, every `Pkg.test()`);
   - a temporary added to the restore path — its row (CPU, every `Pkg.test()`);
   - a resident symbol added to a forcing — the working-set floor (CPU, every `Pkg.test()`);
   - an array held by a closure, including a boxed capture, and one held by a struct inside a
     `Vector` — the walk (CPU, every `Pkg.test()`);
   - an allocation outside the pool — the driver reading (GPU leg only);
   - a host buffer allocated in C and retained across checkpoint calls — the host resident set (CPU
     rows) and the process-growth check (GPU leg);
   - a bound made loose by doubling one ledger coefficient — the tightness runs (GPU leg only).
   The GPU-only plants are exercised only when the GPU leg runs; `Pkg.test()` says so when it skips
   them, and does not report them as passed.

## Stage 2 — the fixes, measured by the instrument

8. `FixedDomain`: delete the unused `velocity_physical`; build the multipliers and the mask from the
   scalar field in spectral representation already allocated; then attribute what remains.
9. `read_simulation`: restore without seeding a state it overwrites (a constructor route that skips
   seeding), and read into the run's own storage rather than through staging where the backend
   allows.
10. The checkpoint staging: measure where it lives on the GPU (host or device); bound it, or stream
    one component at a time.
11. The generator's steadiness probe: probe with buffers the run already allocates.

## Stage 3 — requests and closing

12. **To PF**: let `exponential_convolve!` take its offset as a radial symbol, not only a stored
    field. When it lands, one commit retires everything that records the rate as resident: the
    `Linear` delta in `_forcing_delta` and its comment block in `test/memory_audit.jl`, the
    working-set floor's holder, the traffic audit's two-call rate holder, and the probe's second
    array.
13. **To GBGCodingTools**: the top-down peak check is general, not physics — by the rulebook a
    TestHarness engine HT declares, beside the GPU-timing-against-minimum-traffic check PF is
    raising. HT writes it locally only until the engine exists, then declares it.
14. **Close**: rerun the instrument after each fix; retire each holder in the fix's own commit; an
    independent reviewer (a fresh agent or the GBGCodingTools session) audits the finished
    instrument; the final report states the claim in the form above, with what it does not reach.

## What this will not reach

- Memory a dependency allocates that neither the pool, the driver nor the process's resident set
  attributes to a stage: seen only as a change in free memory, not attributed.
- Multi-GPU and multi-threaded runs: A1 fails there.
- Values of a scaling axis outside its three swept points are covered by the asserted scaling (A4),
  not by measurement; interactions beyond pairs of scaling axes are assumed additive.
- The full categorical product is measured at one base scaling point; the fresh-process arbitration
  and the tightness runs cover a stated subset, not every configuration.
- The GPU-only plants and legs run when someone runs the GPU leg, not on every `Pkg.test()`.

## Review record

Round 1 (2026-09-30), three reviewers, every finding folded in: M, history depth and band as
scaling axes; the checkpoint primitives named; `interpolation_scheme` an axis; plan caches outliving
a configuration; the high-water mark demoted from verdict; the closure blindness fixed; teardown and
synchronization; three sizes; GPU-only plants scoped; T(s) defined; the PF request's retirement set;
a host-leak plant; the background task.

Round 2 (2026-09-30), three reviewers, every finding folded in:
- the hard limit is read once per process (confirmed on the GPU: a limit set after loading is
  ignored; set before, an over-limit allocation raises `OutOfGPUMemoryError`), so the verdict is now
  one-sided in process with fresh-process arbitration, and the sweep's cost estimate is withdrawn
  until measured;
- nothing showed the bound was tight: tightness runs at P minus a margin, and a loosened-bound plant;
- the walk's element and `Core.Box` blind spots, live in today's audit, fixed with the closure one;
- the "unused array" plant split into a stored one and a local one, since the real defect is local;
- A8 corrected: the public pool handle works once taken after the first allocation; reset is a write
  of 0;
- three points on every scaling axis, coefficients derived, never fitted;
- host memory outside Julia's heap (FFTW planner, HDF5) measured through the resident set, and
  `fft_flags` classified;
- `Phenomenology` scoped; a warm-up before baselines; `synchronize` versus collection distinguished;
  the configuration count stated as enumerated by the script.
