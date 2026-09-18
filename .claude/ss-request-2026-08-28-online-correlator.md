# SS request (2026-08-28): an online lag-correlation estimator

**From**: GBGIsotropicTurbulence (the TurTLE validation work). **Invariant-2 raise**: a
time-correlation function accumulated sample-by-sample is an *online statistic* — it belongs in
GBGStreamingStatistics, not hand-rolled in a run script (which is what IT's comparison leg did
this once, batch-FFT over callback-collected samples; the estimator was right, the home was not).

## The estimand

For a stream of vector samples ``v_n ∈ R^{M×3}`` (M tracers, one sample per callback instant,
uniform spacing Δs), the normalized autocorrelation

    ρ(τ_j) = ⟨v(t+τ_j)·v(t)⟩ / ⟨|v|²⟩,

dot product over components, mean over the M tracers, **unbiased** time average over the stream
(divide the lag-j accumulator by its own pair count), ρ(0) = 1. This exact estimator (linear lags)
is what TurTLE's post-hoc reference uses — parity matters for the validation page.

## Two forms, both wanted

1. **Linear-lag ring buffer** (exact): fixed maximum lag L; state = ring of the last L samples
   (M×3 each) + L+1 scalar accumulators + pair counts. Per sample: one dot-product row against
   the ring. Memory O(L·M), constant in stream length. This is the estimator-parity form.
2. **Multiple-tau (order-n) correlator** (economical): the MD-standard hierarchical correlator —
   p slots per level, each level coarse-grained by n; quasi-log lag spacing, memory O(p·log N),
   exact at level 0, controlled pre-averaging attenuation at long lags. References: Frenkel &
   Smit (Understanding Molecular Simulation, the order-n scheme); Ramírez, Sukumaran, Vorselaars
   & Likhtman (2010), *Efficient on the fly calculation of time correlation functions in computer
   simulations*, J. Chem. Phys. 133, 154103, doi:10.1063/1.3491098.

Backend-generic like the rest of SS (the samples arrive as device arrays on GPU runs; the
accumulators may live host-side — M×3 per sample is small). Estimand-first docs per SS house
style. The consumer loop is IT's `run!` observation callback: one `observe!(corr, v)` per sample
instant, one `correlation(corr)` read at the end.

## Why not keep the batch form

The architecture's statistics philosophy (and the owner's explicit ruling) is streaming: no
flow-state storage, no reruns. Holding the full sample history in RAM is trajectory storage in
disguise; a fixed-max-lag or multiple-tau correlator is O(1) in run length and is how "VACF
computed in the callback" is honestly true.

---
**POSTSCRIPT (same day, owner ruling)**: the TurTLE comparison does NOT need this — the owner's
estimator is the single-origin ensemble VACF (freeze v₀, one scalar per sample, O(M) state, no
correlator machinery). This request stands only as OPTIONAL future work for time-averaged /
multi-origin correlations where variance reduction earns the state. No urgency; do not build
without a concrete consumer.
