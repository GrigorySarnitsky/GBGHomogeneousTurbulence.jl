# PF request (2026-08-29): CPU kernel performance — one pathology, two codegen misses, small items

**From**: GBGIsotropicTurbulence, out of an owner-directed codegen/profiling analysis (LLVM/native
inspection + per-kernel bandwidth on the i7-12700K; rocprofv3 kernel census on the RX 7900 XTX).
GPU verdict for context: PF's device kernels are clean — proper `v_fma_f64`, zero spills, full
occupancy; nothing GPU-side is bug-grade. The CPU lane is where the findings are. Evidence
artifacts (IR dumps, ISA, timings) were produced in the IT session; numbers quoted below.

## 1. `weighted_inner` on CPU is serial and unvectorized — bug-grade

12–20× slower than the same-size `inner`: at 128³ F64 the same 51 MB read costs 19.2 ms
(`weighted_inner`) vs 1.7 ms (`inner`); achieved bandwidth **2.7 GB/s = 3.5% of the DDR5
ceiling** (Float32 is worse still, 1.5 GB/s). Cause, read from `Reductions.jl`: the reduction
ends in a plain Base `sum(instantiate(broadcasted(*, weight, density)))` — a lazy mixed-shape
(3-D weight × 4-D field) `Broadcasted` that Base folds single-threaded with cartesian indexing.
It never reaches the threaded `_indexed_tree_reduce` machinery `inner` uses; the multi-weight
tuple form has the same serial CPU path. The design was GPU-first (`mapreducedim!`) and the CPU
leg fell through to Base's fallback. **This sits in the default hot loop** — `VarianceController`
calls the multi-weight form per stage (~7% of a 128³ CPU step) — and under every `dissipation`
read. Fix shape: route the weighted reduction through the same threaded/vectorized indexed-reduce
path as `inner`, materializing nothing.

## 2. The integrating-factor exponential: scalar libm call, evaluated per fiber component

In `exponential_convolve!`'s CPU lowering the IR shows `call double @j_exp_...` per element, and
the factor is re-evaluated for each of the 3 fiber components although it is fiber-constant.
Single-thread throughput 6.7 GB/s vs 20.3 for the shape-identical plain `combine!` (~3.5×
compute penalty; 20 threads roughly hide it, low thread counts do not; Float32 gains almost
nothing since the cost is instructions). Fix shape: evaluate `exp(c·|κ|² [+ s·ŵ])` once per mode
(hoist over the fiber), and/or a vectorized exp (SLEEF-class or a poly kernel). With ~6–10
exponential passes per IF-RK step this is the dominant pointwise cost at low thread counts.

## 3. The fused fiberwise cross (Lamb vector) kernel compiles fully scalar

No vector IR at all in F64 or F32; near-zero thread scaling (23 → 30 GB/s from 1 → 8 threads —
instruction-capped, not bandwidth-capped). Cause: the `map(array -> array[n], arrays)` closures
block `@inbounds` propagation (bounds checks survive to LLVM; IRCE hoists them but the residual
multi-branch CFG plus the deliberate may-alias `targets`/`arrays` contract stops the loop
vectorizer). Fix shape: propagated-inbounds element accessors (index the tuples without a fresh
closure) plus a no-alias fast path when `targets` don't overlap `arrays`.

## Smaller, take-or-leave

- **No FMA anywhere on CPU**: no `muladd`/`@fastmath` in PF, and Julia won't contract on its own —
  zero `vfmadd` in any inspected kernel. Free win for the compute-leaning kernels (cross,
  projection arithmetic, interpolation weights); irrelevant where bandwidth-saturated.
- **KA CPU threading allocates ~1.8 MB/step at 128³** (Task spawns, ~30 passes × ~20 tasks) — not
  field-scale, but "allocation-free" claims downstream now say "at field scale" because of it.
- **GPU, minor**: KA's launch heuristic picks 975-thread workgroups on 65-wide spectral grids
  (~5.5% idle lanes); the 18 per-inverse-transform `lmul` normalization passes and the 18
  source-preserving pre-C2R `copyBuffer` blits cost ~1.1 ms of a 13.4 ms 128³ F64 step — rocFFT's
  native scale-factor support could fold the former.
- Context for prioritizing: the standing device-resident-forcing-scalars residual is ~1 ms/step
  of GPU idle at the per-stage readbacks — same magnitude as the items above.

Priority from IT's seat: **1 (bug-grade, default hot loop) ≫ 2 > 3 > the rest.**
