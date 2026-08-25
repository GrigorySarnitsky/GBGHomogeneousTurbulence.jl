# Open code defects — the /bug-hunt escalation register

## Round 6 (2026-08-25) — one escalation, awaiting the owner

**ESCALATED: `r6-free-hot-path-01` — VarianceController's default `turnover_time` plugs a scalar
variance into Bassenne's kinetic-energy law, breaking the passive scalar's exact amplitude
covariance** (major). The default is tℓ = 2·target/(3·ε∞(target)) with ε∞ = (target/0.9)^{3/2}/L —
dimensionally a kinetic-energy law. Driving the SCALAR, target is ⟨φ²⟩ in arbitrary units, so tℓ
scales as L/√⟨φ²⟩ and the exactly-linear scalar equation loses its φ → s·φ covariance (witnessed:
1.5e-6 violation after 5 steps under the default; exactly 0.0 with an explicit equal turnover_time).
The physically right timescale is the FLOW's turnover time, which the constructor cannot know from
a scalar target. Witness: `witnesses/escalated/`, deliberately NOT promoted. Owner options:
(a) refuse a defaulted turnover_time when the strategy is bound as `scalar_forcing` (needs a
was-derived marker on the struct); (b) same, plus the run layer supplies the flow's tℓ when it
builds a scalar controller; (c) document the caveat and keep the default (breaks the linearity
invariance the empty-band floor was redesigned to preserve — not recommended).

**Still parked (owner, 2026-08-23): `r5-aliasing-and-mutation-01`** — a mutable `StochasticOU`
shared by two `Simulation`s couples their forcing state; the strategy is archived, do not fix.
Witness moved to `witnesses/escalated/` with the round-6 escalation.

---

# Historical register — rounds 4-5 (all closed or parked)

**RE-VERIFIED 2026-08-22 by running every witness.** The witnesses had gone BROKEN on the
`BandRescaling`/`uses_linear_rate`/`apply_forcing!` renames — five of seven reported nothing at all,
which is why this file must never be read without re-running. Renames repaired; verdicts below are
measured, not remembered.

**CLOSED by decision 58** (state-dependent rates moved to the per-stage source):
`r5-free-hot-path-01` and `r4-free-hot-path-01` — both now PASS. The two "first order" entries below
are historical.

**CLOSED 2026-08-23, from the backend (decision 63):** `r5-gpu-and-hot-loop-01` — PF shipped the
requested fix the same day (pre-reshaped axis views held on `FieldSpectralMultipliers`), and the
witness flipped exactly as the request's acceptance predicted: 6/6, `bytes == 0` for both schemes
at N = 8/16/32, with no IT code change. Promoted into `test/regressions/` — step! is now
allocation-free in the strict `== 0` sense, not merely under the audit's ceiling.

**PARKED, not to be repaired (owner, 2026-08-23):** `r5-aliasing-and-mutation-01` — a mutable
`StochasticOU` shared by two `Simulation`s couples their forcing state. The strategy is archived
and the owner does not care about this defect; if a repair were ever to require architecture
changes, the owner would rather DELETE StochasticOU than re-architect for it. Do not fix; do not
count as open work.

**CLOSED 2026-08-23:** `02-r5-aliasing-and-mutation-02` — FlowConditions guards moved into an
inner constructor, every construction path validated; witness 7/7, filed as
`test/regressions/r5-flowconditions-positional-guards.jl`. And `03-r5-free-hot-path-03` —
deposit!'s scalar-pairing guard now covers the buffers leg with a named ArgumentError; witness
4/4, filed as `test/regressions/r5-deposit-buffers-mispairing.jl`.

**CLOSED 2026-08-23 (decision 60):** `01-r5-free-modules-01` — the κ=0 mode is pinned exactly in
both RHS assemblies, between the nonlinear term and the source; witness 9/9, filed as
`test/regressions/r5-free-modules-01-mean-mode.jl`.

---

Each has a failing witness under `.claude/bug-hunt/witnesses/`. None is filed into
`test/regressions/`, so the suite does not read green over any of them.

## [major] FlowConditions's documented plain positional constructor bypasses all three keyword-form guards (shared mutable forcing, viscosity > 0, schmidt > 0)

- witness: `02-r5-aliasing-and-mutation-02.jl`
- evidence: Test Failed at .../02-r5-aliasing-and-mutation-02.jl:80
  Expression: FlowConditions(0.05, 1.0, ou, ou)
    Expected: ArgumentError
  No exception thrown
:81 FlowConditions(-1.0, 1.0, NoForcing(), NoForcing()) — No exception thrown
:82 FlowConditions(0.05, 0.0, NoForcing(), NoForcing()) — No exception thrown
:86 shared_forcing_outcome() === :rejected — Evaluated: dependency_internal === rejected
S

## [major] step! violates invariant 4: a fixed, grid-independent per-call host allocation (1152 B for IFLowStorageRK3, 720 B for IFRK2) with NoForcing and no tracers

- witness: `r5-gpu-and-hot-loop-01.jl`
- evidence: All 6 cases fail (0 passed, 6 failed):

  Test Failed at .../r5-gpu-and-hot-loop-01.jl:45
    Expression: bytes == 0
     Evaluated: 1152 == 0     (IFLowStorageRK3, N = 8, 16, 32)
     Evaluated: 720 == 0      (IFRK2, N = 8, 16, 32)

Byte count constant across N, so not an O(N^3) leak.

## [major] Forced runs — including the front door's default — converge at first order, defeating the schemes' documented second/third order

- witness: `r5-free-hot-path-01.jl`
- evidence: Expression: measured_order(ConstantPower(injection_rate = 0.2)) ≥ 2.5
 Evaluated: 1.0180250123178332 ≥ 2.5
Expression: measured_order(nothing) ≥ 2.5   # front door's default forcing
 Evaluated: 1.0233986541555409 ≥ 2.5
Controls pass: NoForcing 3.010, Linear(rate=0.5) 3.007. src/Forcing.jl:6 claims this route "preserves the scheme's order (no operator splitting)" and names ConstantPower.

## [major] The κ=0 velocity mode is neither conserved nor damped: the exact law ⟨u×ω⟩=0 is not enforced, and the spurious uniform drift grows exponentially (6% of u' after 3000 Float32 steps)

- witness: `01-r5-free-modules-01.jl`
- evidence: "the assembled velocity RHS vanishes identically at κ=0 (⟨u×ω⟩ = 0): Test Failed at 01-r5-free-modules-01.jl:49 / Expression: all(iszero, mean_mode(N̂))" — N̂(0)=[9.66e-13, 3.41e-13, -1.14e-12], |N̂|max=7545. Forced Float32 1000 steps: mean_flow=2.83e-6, u_rms=0.559, ratio=5.06e-6; at 3000 steps mean=0.031 vs u'=0.51. Summary: 3 pass, 6 fail.

## [major] State-dependent forcing rates are frozen at t_n, collapsing IFLowStorageRK3 from third order to first

- witness: `r4-free-hot-path-01.jl`
- evidence: NoForcing 7.9706 (order 2.995); Linear(0.5) 7.9306 (2.987); ConstantPower(0.3) 2.5857 (1.371); BandRescaling(:total) 1.9954 (0.997).
Test Failed at .claude/bug-hunt/witnesses/r4-free-hot-path-01.jl:78
  Expression: 5.0 < constant_ratio < 12.0
   Evaluated: 5.0 < 2.5856521796153094 < 12.0
Refinement ladder, ConstantPower: n=8 2.5857, n=16 2.0607, n=32 2.0160, n=64 2.0081 (order → 1.006).

## [minor] A mutable `StochasticOU` shared by two `Simulation`s silently couples their forcing state — `FlowConditions` guards this only within one build

- witness: `r5-aliasing-and-mutation-01.jl`
- evidence: Witness line 81: `Expression: maximum(abs, alone .- interleaved) == 0` / `Evaluated: 1.56286011572769 == 0`. Three controls pass first: two independently-built, identically-seeded `StochasticOU`s give bit-identical runs, and `sim_a.…velocity_forcing === sim_c.…velocity_forcing` is `true`. Interleaving unrelated `sim_c` moves `sim_a`'s û by 1.56.

## [minor] deposit!'s scalar-pairing guard is one-sided: scalar state + scalar cache + scalar-free IntegratorBuffers dies as MethodError inside the private _recovery_scratch

- witness: `03-r5-free-hot-path-03.jl`
- evidence: Test Failed at .../03-r5-free-hot-path-03.jl:54
  Expression: !(outcome isa MethodError)
   Evaluated: !(MethodError(GBGIsotropicTurbulence.Propagator._recovery_scratch, (nothing,), …) isa MethodError)
Test Failed at :55
  Expression: outcome === nothing || outcome isa ArgumentError
Control (state scalar, cache scalar-free) passed: @test_throws ArgumentError deposit!. Summary: 2 passed, 2 failed.



## [CLOSED 2026-08-22] the adaptive timestep runs away on a decaying flow

Resolved by the RESOLUTION bound, not by a chosen constant. Δt is now the smallest of: the documented
advective rule; `1/(D·κ_min²)`, the decay time of the longest mode the box holds, with `D` the largest
diffusivity carried (ν, or ν/Sc when a scalar diffuses faster); and the caller's `max_dt`, `Inf` by
default.

The earlier `cfl*Δx` ceiling was a units claim — the step the rule gives at UNIT SPEED — and six audit
lanes caught it throttling every sub-unit-speed run. This bound is derived from ν and L, which the run
already has, so there is no nondimensionalisation to defend. Measured: it is permissive by
(N/4π²C)·Re_L — 53x at N=16/Re=65, 8e4 at N=256/Re=6283 — and binds only below Re_L ≈ 1, which is not
turbulence.

hit3d and fluidsim both solve this with a chosen constant instead (a 1% growth limiter with
`min(DT, 0.01)`; a `deltat_max` parameter defaulting to 0.2, its zero-velocity branch returning that
cap). Both are cited at the site as the alternative; this route was taken because it needs no constant.
   changes nothing (the integrating factor has annihilated the resolved band). Diagnoses the actual
   failure rather than proxying it by a number, and costs a comparison.
