# Memory audit: from ledgers to a bound on the whole run

Status: draft 6, 2026-10-02. The CPU part is built; this draft specifies only the GPU part, revised
after a fifth review against the code as it now is. Draft 5, with the full review record, is in the
git history (the commit before this one).

## What the instrument is

A tool that **lists possible memory defects**: every gap between what a run allocates and the floor
it could reach, with its size, its stage and its evidence. Fixing is decided per entry. Each gap is
claimed by a `Holder` of the one register (`test/audit_ops.jl`): `:FIX`, `:PF_RAISE`, or `:DESIGN`,
which carries its measured cost, what it buys, and the owner's decision. The suite fails on a gap no
holder claims and on a holder whose gap has gone.

## Built (2026-10-01/02)

- **The walk** (`collect_field_arrays!`) reaches closures, boxed captures, arrays of structs and
  `Dict` values, and counts each buffer once by storage.
- **One register** for the compute, memory, synchronization and temporary ledgers, with one admission
  rule (`holder_admissible`).
- **The working set's symbols** are held against the frame's zero floor; `Linear`'s rate became a
  radial symbol (decision 106, PF 92), so no rate is stored.
- **The temporary ledger** (`test/temporary_audit.jl`): every exported function and type, measured
  at 16³, 32³ and 64³ on the CPU; every field-scale row claimed. The fixes it led to: the domain
  11.2 → 3.1 N³ reals (PF 93, 94), seeding 6 → 3, the restore 24.1 → 3.9, checkpoints copy-free.
  Adopted costs: `FULL STRAIN TENSORS`, `SEEDING NOISE FIELD` (decision 108), `TRANSFORM PLANNING`
  (decision 109). The open list of local wins is empty.
- **The seed check**, declared as the harness contract `RULE.TEST.SEED_PARITY` (decision 107).
- **The device hot loop** (`test/device_hot_loop.jl`): a step on the GPU allocates nothing that grows
  with the run. It found a PF defect: an in-place `displace!` copies an (M, 3) array per step on a
  device. Recorded as broken until PF closes it.

## What the GPU part will claim

That the device peak of a run is predicted, and how closely, with every term of the prediction
either derived from a ledger or a constant measured in its own leg.

### The prediction, term by term

For a configuration and a stage, the predicted device peak is

    P_device = P_pool + P_outside,     P_pool = Σ_class count(class) · bytes(class, N, T) + T_device(stage)

- **The resident pool term, derived.** The class counts are the resident ledger's (BASE, the forcing
  and tracer deltas, DEVICE_FRAME); bytes per class come from a table of shapes and element sizes.
  The review measured it against the pool's used high-water mark for the default run, Float32:
  20.44 MiB predicted and measured at 64³, 161.75 at 128³ — 0.01% or better.
- **The O(N²) and O(M) terms**, added to the same sum: the frame's axis multipliers, and the
  tracers' arrays (positions, the cache's sample slots, the scheme's registers, the traversal
  order), each written out in M. The review's 64³ run with 10⁵ tracers left 1.3 MiB unexplained once
  a rough O(M) estimate was added; the derived term must close it.
- **The device temporaries, measured on the device.** The temporary ledger is a CPU measurement and
  does not transfer: seeding's 3 N³ transient is host memory on a GPU run, and the domain's
  planning is 2.0 N³ elements on the device against the CPU's 3.1. So each temporary row gains a
  device value, measured on the GPU with the pool's high-water mark, and a space tag (device, host).
- **The memory outside the pool, a measured constant.** The cuFFT workspace and the loaded kernel
  modules: 10 MiB after the domain and 34 MiB after the run at 128³. They cannot be attributed
  to a stage in process — module loading depends on what the process ran before — so they are
  measured per configuration class in a fresh process, as a constant beside P_pool.
- **The pool's reservation rounding**: the pool reserves in 32 MiB chunks (reserved 192 MiB for
  161.75 used at 128³). It does not enter the prediction of what is used; it enters the tolerance.

### How the check decides

- **In process, the pool term.** Each configuration's used high-water mark, reset per stage and read
  after synchronizing and collecting, must equal P_pool within a stated tolerance in both directions —
  a measured mark above P is an unledgered allocation, one far below it a stale ledger. This is the
  direct comparison the review showed to hold at 0.01%.
- **In a fresh process, fitting.** A representative set reruns under `JULIA_CUDA_HARD_MEMORY_LIMIT`
  (read once per process) set to P_pool + P_outside + one 32 MiB chunk, and must complete; and under
  that minus a margin above one chunk plus the outside constant, and must fail. The margin makes this
  meaningful only where P_pool is several hundred MiB, so it runs at 256³ and above.
- **Host memory** is checked the same way, in a fresh process under a cgroup cap
  (`MemoryMax`, `MemorySwapMax=0`) set to a measured post-load baseline plus the host temporaries.
- **Preconditions**: no other compute process on the GPU, and the desktop's graphics total steady
  across a configuration (the review saw it change while it ran); the hard limit's 32 MiB
  granularity re-measured before use.

### Configurations

The full product of the strategy axes at one base point, at 64³ and 128³, both precisions; each
scaling axis (N, M, the multistep order K, the stochastic band) at three points around it. The M,
K and band axes are not yet measured anywhere: the GPU run is their first and only check, and the
CPU temporary ledger gains them as rows when it is next extended.

### Planted defects (GPU only)

- an allocation outside the pool — the outside constant moves;
- a bound made loose by doubling one ledger coefficient — the in-process comparison fails;
- a device-side allocation per step — the device hot loop (built, and it found a real one).

The two plants of draft 5 that a CPU check was to catch — a host array inside a device run, and a
C-side host buffer — move to this run or are dropped: the per-row host reading was found not to
measure (in one process the resident set cannot separate a C allocation from reused heap pages).

## Order of work, and where it stands (2026-10-02)

1. **Built — the pool term** (`test/device_memory.jl`). The walk's device bytes against the pool's
   used memory, for ten strategy points (the default; a scalar; PhaseShift; HouLi; IFHeun,
   IFLowStorageRK4, IFSSPRK3; Linear; StochasticOU; 4096 tracers) at 64³ and 128³, both precisions:
   equal to the byte, the tracer run 125 bytes off. A step holds at most 26 KB above the run.
   Not yet the full strategy product, and not the M, K and band axes.
2. **Built — the device temporaries** (same file): the domain 2.0 N³ elements, the run's
   construction 3.0 (4.0 with a scalar), the skewness 18.3, the restore 2.6, every other row zero.
3. **Built — the fresh-process legs** (`test/device_limits.jl`), at 256³ / Float32:
   - the device prediction is the largest stage's resident set plus its temporary, 1287 MiB; the run
     completes under P + 64 MiB and runs out of memory under P − 96 MiB;
   - the memory outside the pool is 34 MiB, the same at 128³: library state, not field-sized;
   - the host prediction (a 16³ baseline plus the host draw) is 2060 MiB against 2062 measured, and
     the run completes under it plus 128 MiB. **One-sided, by measurement:** the peak resident set
     overstates the need, since a capped run still completes at P − 512 MiB (the kernel evicts
     file-backed pages); a host tightness run means nothing.
4. **Open — the ROCm leg** on Aiporetne.
5. **Built — breadth of the pool term.** The M, K and band axes (tracers 4096 / 32768 / 262144;
   AdamsBashforth orders 2 and 4; bands 1–2 / 1–4 / 1–8) match the pool within 125 bytes, and the
   full strategy product (144 configurations: scheme × dealiasing × scalar × velocity forcing, at
   64³ and 128³, both precisions, `DEVICE_FULL_SWEEP=1`) passes 1260 of 1280, the 20 broken being
   the tracer step excess of PF's in-place `displace!` (2026-10-02, 26 minutes on the 5070 Ti).
   Those axes in the temporaries (2026-10-03): the order and the band add nothing beyond the noise
   field, on the CPU and the device; the tracer count cost 57 bytes per tracer on the CPU (seeding
   copies and a second traversal scratch) and 9 on the device, fixed the same day. One byte per
   tracer remains on both, PF's order constructor checking the identity order with its own marks
   (TRAVERSAL ORDER CHECK; the owner left it as is, 2026-10-03).

## What this will not reach

- Multi-GPU and multi-threaded runs; a shared GPU.
- Values of a scaling axis beyond the swept points, which rest on the asserted scaling.
- Memory a library allocates that neither the pool nor the driver attributes.
