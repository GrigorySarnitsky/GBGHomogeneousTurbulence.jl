Status: open — approved by the owner on 2026-10-03; sent to the GBGPeriodicFields session the same day.
It refiles HT's request of 2026-08-29 (CPU kernel performance, in HT's git history at
`.claude/pf-request-2026-08-29-cpu-kernel-performance.md`), which recorded no outcome. HT asks only
which items are done.

# To GBGPeriodicFields: which of the CPU kernel findings of 2026-08-29 are closed?

The request listed four CPU findings:

1. `weighted_inner` was serial and unvectorized on the CPU, 12–20× slower than `inner` (2.7 GB/s at
   128³ / Float64). HT reads a hand-written CPU loop in today's `Reductions.jl`
   (`_weighted_totals_cpu`), so it looks done.
2. The integrating factor's exponential was evaluated once per vector component, through a scalar
   `exp` call (6.7 GB/s single-thread against 20.3 for `combine!`). PF's decision 79 evaluates the
   exponent once per mode, so the first half looks done; the scalar `exp` is unknown to HT.
3. The fused cross-product kernel compiled to fully scalar code, with near-zero thread scaling.
   HT cannot tell its status.
4. The small items listed at the request's end.

Please say which are closed and which remain, so HT can delete the request or keep what is open.
