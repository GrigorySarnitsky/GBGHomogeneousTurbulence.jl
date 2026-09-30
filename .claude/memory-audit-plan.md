# Memory audit: from ledgers to a bound on the whole run

Status: draft 2, 2026-09-30, after one adversarial round (coverage, soundness, facts). Not started.

## Why

The memory audit claims to bound what a run needs, and it does not. It is a union of ledgers, each
complete within itself, and nothing checks that the union covers every stage of a run.

- The resident ledger (`test/memory_audit.jl`, working set + frame) is derived: it walks every
  field-sized array a live `Simulation` reaches, and a completeness test requires the two ledgers to
  account for all of them. But the walk skips closures (`test/audit_ops.jl:66`,
  `!(x isa Function)`), so an array captured by a closure it reaches is invisible to it.
- The temporary ledger (`EPISODE_UNITS`, `test/memory_audit.jl:405`) is a hand-written list of six
  episodes. Construction, checkpointing, and every observable added after it were never on it.
- The zero-storage floor for a function of |κ|² is demonstrated only for the `FixedDomain`. A symbol
  stored in the working set, as `Linear`'s rate is, is measured and frozen but never held against
  that floor.
- The liveness bound is built from the unforced step lists (`rk3_ops` has no forcing keyword but
  `ou`); the forcing deltas are "priced on the forcing axis" and never bounded.
- Every scaling statement is in the grid size N. The particle count M, the sample-history depth, and
  a forcing's band (which sizes `StochasticOU`'s companion grid, `src/Forcing.jl:1337`) are never
  scaling axes.

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

Causes identified: `src/SimulationDomain.jl:303` allocates `velocity_physical` and never reads it,
and a vector template serves the multipliers and the mask where the scalar one would do;
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
4. **The empirical check** — the top-down run over the derived configuration space, the legs each
   assumption rests on, and what it does not reach, stated in the file.

### The theorem

A run is a sequence of stages: build the domain; build the run (buffers, cache, generator, state,
tracers); seed; step; warm up; observe; checkpoint; restore. For a stage s let R(s) be the ledgered
resident set when s begins, and T(s) the peak of all bytes concurrently live during s beyond R(s) —
including whatever s builds that becomes part of R(s+1). Then

    peak ≤ max_s ( R(s) + T(s) )

provided:

- **A1 (sequential)** stages do not overlap: the run is single-threaded at the Julia level. CUDA.jl's
  background pool-trimming task only releases memory, so it cannot raise a peak.
- **A2 (reclaimed)** the temporaries of a finished stage are not live when a later stage allocates.
  On the GPU, CUDA.jl collects and retries on allocation failure, so the property that matters is
  that the run *fits*, which the hard-limit leg decides; the pool's high-water mark may include
  garbage not yet collected and is attribution, not verdict.
- **A3 (no fragmentation loss)** a request for B bytes succeeds when B bytes are free. Decided by the
  hard-limit leg, not assumed.
- **A4 (scaling)** each stage's bytes are a·N³ + b·M + c·(history depth)·M + d·N_c³ + O(N²), with N_c
  a companion grid's size and the coefficients the ledger states. Tested at three grid sizes, two
  particle counts (one ≳ N³), two history depths, and two bands for `StochasticOU`.
- **A5 (precision and backend)** precision and backend change bytes, never counts. Tested by running
  both precisions, and ROCm on Aiporetne.
- **A6 (outside the pool)** allocations the pool cannot see (cuFFT/rocFFT workspaces, library
  handles, context memory) are measured from the driver's free memory, beside the pool.
- **A7 (the configuration space)** is derived from the code: the `subtypes` of `AbstractForcing`,
  `AbstractIntegrator`, `DealiasingStrategy`, `AbstractParticleIntegrator`; every keyword of the
  constructors a run takes (`Simulation`, `FixedDomain`, `Tracers`, each forcing), each classified as
  a categorical axis, a scaling axis, or memory-neutral with a reason — a new keyword fails until
  classified. `interpolation_scheme` and `history_depth` are axes; `number_of_particles` and the
  band edges are scaling axes.
- **A8 (the measurements measure)** every reading is falsified before it is trusted: the pool
  high-water mark reads nonzero after a known allocation (the public `CUDA.memory_pool(device())`
  reads 0 forever; the working route is the internal `CUDACore.pool_create`, pinned to the CUDA.jl
  version); a CPU row's kept-versus-transient split is computed with the shared frame excluded, not
  by subtracting a `summarysize` that may count shared storage.

## Stage 1 — the instrument, before any fix

1. **Derived temporary ledger.** Replace `EPISODE_UNITS` with a table whose required set is the
   export list (the pattern of `TestHarness.allocation_completeness`). An in-place operation already
   bounded below field scale by `test/allocations.jl` is cited, not repeated; every other export and
   constructor gets a row or an exemption with a reason.
2. **The missing rows**, each at three grid sizes with its scaling asserted: `FixedDomain`;
   `ResolvedGenerator` per forcing; `Simulation` per forcing, with seeding separated; `Tracers` and
   the particle buffers at two particle counts and two history depths; `StochasticOU` at two bands;
   all ten checkpoint functions (`write_`/`read_` × `domain`, `state`, `tracers`, `forcing`,
   `simulation`); `kinetic_energy_and_dissipation_below_scale`; `warmup!` (O(samples) growth, and
   the skewness temporary when that gate is on).
3. **The walk sees closures.** `collect_field_arrays!` descends into a closure's captured fields, so
   an array held by a closure the run reaches is ledgered like any other.
4. **Floors for the working set's symbols.** Extend the frame's zero-storage demonstration to every
   resident array a forcing or the generator adds: an array that is a function of |κ|² is
   reconstructed from the axis multipliers inside the test, and its residency becomes a gap with a
   holder (`Linear`'s rate → the PF request below). The forcing deltas join the liveness bound.
5. **The written bound.** The theorem and A1–A8 head the top-down file, beside a function computing
   the predicted peak per stage from the ledgers, so the check compares numbers of independent
   origin: the ledger sum and a measurement.
6. **The top-down GPU run** (this machine, not CI; before a release and whenever a ledger changes):
   - every point of the derived configuration space, at the sizes of A4, Float32 and Float64;
   - each configuration from a clean baseline: its objects dropped, `GC.gc(true)`, `CUDA.reclaim()`,
     and the baseline driver and pool readings recorded, so no configuration inherits another's
     plans or pool;
   - at every stage boundary `CUDA.synchronize()`, then the readings: the pool's used high-water
     mark (reset to current per stage), the driver's free memory, and host memory
     (`Base.gc_live_bytes` per stage, `Sys.maxrss` per process);
   - **the verdict is the hard-limit leg**: each configuration reruns under
     `JULIA_CUDA_HARD_MEMORY_LIMIT` set to its predicted pool peak plus a stated tolerance and must
     complete, with the driver reading bounding what the limit does not govern (A6). The per-stage
     high-water readings attribute a failure to its stage; they do not decide one;
   - a process-growth check: the same configuration built and dropped repeatedly must return to its
     baseline, so a cache that outlives its run (FFTW or cuFFT plans, handles) is caught;
   - a ROCm leg on Aiporetne, the same script.
   Measured at 32³: 30 s for the first configuration, 8–19 s for one with new settings, 0.1 s for a
   repeated one. The full sweep is estimated, not measured, at under an hour.
7. **Planted defects**, each named with the leg that must catch it, re-planted as a regression test:
   - an unused field-sized array in a constructor — the resident walk (CPU, every `Pkg.test()`);
   - a new export that allocates a field — the derived temporary ledger (CPU, every `Pkg.test()`);
   - a temporary added to the restore path — its row (CPU, every `Pkg.test()`);
   - a resident symbol added to a forcing — the working-set floor (CPU, every `Pkg.test()`);
   - an array held by a closure — the closure-aware walk (CPU), and the top-down run;
   - an allocation outside the pool — the driver reading (GPU leg only);
   - a host buffer retained across checkpoint calls — the host reading (GPU leg) and the
     process-growth check.
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

- Memory a dependency allocates that neither the pool nor the driver attributes to a stage: seen only
  as a change in free memory, not attributed.
- Multi-GPU and multi-threaded runs: A1 fails there.
- A configuration outside the swept values of a scaling axis is covered by the asserted scaling
  (A4), not by measurement.
- The GPU-only plants and legs run when someone runs the GPU leg, not on every `Pkg.test()`.

## Review record, round 1 (2026-09-30)

Three independent reviewers; every finding accepted and folded in above.

- Coverage: M, history depth, and the `StochasticOU` band as scaling axes (A4, item 2);
  the eight checkpoint primitives named (item 2); `interpolation_scheme` an axis (A7); plan caches
  outliving a configuration (item 6, process growth).
- Soundness: the high-water mark demoted to attribution, the hard-limit leg the verdict (A2, item 6);
  the walk's closure blindness fixed, not only planted (item 3); per-configuration teardown and
  stage-boundary synchronization (item 6); three sizes, not two (A4); GPU-only plants scoped
  honestly (item 7); T(s) defined to include what a stage builds (theorem); the PF request's full
  retirement set (item 12); the hard limit governs the pool only (item 6, A6); a host-leak plant
  (item 7); the background trimming task (A1).
- Facts: every table number, cause and API confirmed by re-measurement at 16³/32³/64³ and on the
  GPU; one trap found — the public high-water reading is always 0 (A8, confirmed independently); the
  `summarysize` subtraction is valid only because the frame is empty (A8).
