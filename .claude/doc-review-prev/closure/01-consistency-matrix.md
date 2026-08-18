# Closure audit — hat: consistency-matrix

## Finding 1 — Rendered Index contradicts stated module include/dependency order

**VERDICT: ABSENT**

**Evidence:** `docs/src/api/GBGIsotropicTurbulence.md:13` now pins the `@index` block's `Modules` list
explicitly: `[GBGIsotropicTurbulence.SimulationDomain, .State, .Observables, .Cache, .Forcing,
.Generator, .Propagator, .Particles, .SimulationRun]`. Rebuilt `docs/build/api/GBGIsotropicTurbulence/index.html`
(mtime Aug 17 22:13, newer than `src/GBGIsotropicTurbulence.jl` at 21:59) renders the Index in exactly
that module order — `SimulationDomain, State, Observables, Cache, Forcing, Generator, Propagator,
Particles, SimulationRun` — verified by extracting the `GBGIsotropicTurbulence.<Module>.` prefixes from
the rendered Index section in first-occurrence order. This matches `src/GBGIsotropicTurbulence.jl`'s
actual `include()` sequence (lines 58–66) and every prose restatement checked (`docs/src/api.md:4`,
`docs/src/architecture.md:167,1593` §4.9/decision log). No remaining divergence found.

---

## Finding 2 — Host-device sync floor stated as zero, then nonzero, for a fixed step

**VERDICT: ABSENT**

**Evidence:** `docs/src/architecture.md:1302-1303` (decision 35) still states the floor as "one such
readback per step under an adaptive CFL … and none under a fixed step" — unchanged. But decision 40's
entry (lines 1486-1489) now explicitly reconciles the two: *"Read that against decision 35's
synchronization floor — one readback per step under an adaptive CFL, none under a fixed step — and note
the two are speaking about different things: 35 states the **floor**, this states what is
**achieved**, and on the fixed-step axis they deliberately differ. That gap is exactly what a named
holder is for."* The `UNIFORM DEPOSIT SCHEDULE` holder it cites is live in
`test/optimality_audit.jl:110`. The reader assembling "what is the current floor" is no longer misled —
the log now cross-references itself and names the floor/achieved distinction inline, exactly what the
finding said was missing.
