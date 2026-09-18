# Request from GBGIsotropicTurbulence (IT) — 2026-08-23, against GBGPeriodicFields 0.1.0

> **DELIVERED IN FULL, 2026-08-23 (same day).** Item 1: the repro prints 0/0 (their radial-symbol
> allocation fix). Item 2: `weighted_inner(f, weights::Tuple)` — their decision 72, measured 2.14×
> at 128³ on this host's card. Item 3: `reality_residual` — their decision 71, a checker by design.
> All three wired into IT (decision 63): sync ledger default row 10 → 4, `kinetic_energy_and_dissipation`
> public, the escape hatch checks the Hermitian contract. This file is now a record.

Three items, priority-ordered. Each was expanded against PF's current exports and measured before
being raised — the evidence and an acceptance criterion are included per item, and IT holds a
failing witness that flips when item 1 ships. Surface design is yours; the requests state the
*need*, not the API.

---

## 1. `_squared_wavenumber_broadcast` allocates 144 B per call — make it allocation-free

**Priority: high (it is the whole of IT's hot-loop allocation).**

**The finding.** Every op that evaluates the ``|\kappa|^2`` radial symbol per mode allocates
exactly 144 B per invocation. Reproduction, pure PF, no IT involved:

```julia
using GBGPeriodicFields
N = 16
grid = Grid3D((N, N, N), (2π, 2π, 2π))
f = VectorFieldSpectral(zeros(ComplexF64, N ÷ 2 + 1, N, N, 3), grid)
g = VectorFieldSpectral(zeros(ComplexF64, N ÷ 2 + 1, N, N, 3), grid)
m = FieldSpectralMultipliers(f)
mexp(a, b, mm) = @allocated exponential_convolve!(a, b, mm, -0.01)
mlap(a, b, mm) = @allocated laplacian!(a, b, mm)
mexp(f, g, m); println(mexp(f, g, m))   # 144
mlap(f, g, m); println(mlap(f, g, m))   # 144
```

(Function-wrapped and warmed — a top-level `@allocated` against non-`const` globals adds dispatch
noise and is not the measurement.)

**The cause.** `_squared_wavenumber_broadcast` (src/Fields.jl:1532–1537) builds three
`reshape(::Vector, …)` wrappers per call — 3 × 48 B = the 144 B — before returning the lazy
`Base.broadcasted` sum. The class is every consumer: measured on `exponential_convolve!`, the
kernel-composed `helmholtz_projection!` (the plain arity is 0 B), and `laplacian!`; presumably
every other caller of the helper.

**Why IT cares.** IT's `step!` makes 8 such calls per `IFLowStorageRK3` step (3 kernel-composed
projections, 3 exponential updates, 2 rotations) and 5 per `IFRK2` step — measured 1152 B and
720 B per step, byte-exact multiples of 144, constant in N. Everything on IT's side of the
boundary measures zero, so this helper is the entirety of IT's violation of its own
"hot loop allocation-free" invariant, and it garbage-drips on the GPU path.

**Suggested shape (yours to decide).** Store the three axis vectors *pre-reshaped* — shapes
`(n₁,1,1)`, `(1,n₂,1)`, `(1,1,n₃)` — in `FieldSpectralMultipliers` at construction, so the helper
returns `Base.broadcasted(+, …)` over stored arrays and allocates nothing. Memoizing the reshaped
views on first use would do as well.

**Acceptance.** The reproduction above prints `0` twice. IT's witness
(`step!` at `@allocated == 0` over N = 8/16/32, both schemes) then flips on IT's side with no IT
code change.

---

## 2. A fused multi-weight spectral reduction — one field, n kernels, n scalars, one traversal

**Priority: high (largest open gap in IT's synchronization ledger).**

**The need.** IT's default velocity forcing (`VarianceController`, Bassenne et al. 2016) reduces
the **same field three times at every RK stage**, each against a different weight:

- ``\langle f, f\rangle`` — the whole-field variance it holds,
- ``\langle f, b\,f\rangle`` — the forced band it normalizes by (`b` a band kernel),
- ``\langle f, |\kappa|^2 f\rangle`` — the dissipation it replaces.

Each reduction returns a Julia scalar, i.e. one blocking device→host readback. Nine of the default
run's ten crossings per step are these; a fused reduction takes the default from **10 crossings to
4** (the remaining being the timestep's irreducible one plus one fused reduction per stage).

**Expanded against your current exports, not assumed.** `inner` and `weighted_inner` carry
single-weight forms only, and `inner(f, f) == weighted_inner(f, unit_radial_kernel)` — verified
numerically on IT's side — so the three calls are **one operation** ``\langle f, w f\rangle`` at
three weights, `w ∈ {1, band, |κ|²}`. The request is therefore uniform: **one traversal of `f`
evaluating n kernels, returning n scalars** (or, stronger, a device-resident n-vector — see the
note). No two-operand generalization is asked for.

**Note on the stronger form.** IT's ledger also holds a `HOST-SIDE FORCING SCALARS` gap: the
scalars are consumed by the very next kernel as coefficients, so they only visit the host because
the reduction returns a Julia number. If the fused reduction can return a device-resident scalar
pack that `convolve!`-style ops accept as a coefficient source, both gaps close at once. If that is
out of scope, the n-scalars form alone still takes IT 10 → 4.

**Acceptance.** IT replaces three `weighted_inner`/`inner` calls in
`Forcing.add_forcing_source!(::VarianceController, …)` with one fused call; the synchronization
ledger's default row re-freezes at 4 (or 1 + 3 device-resident) with the
`UNFUSED QUADRATIC REDUCTIONS` holder retired in the same commit.

---

## 3. `symmetrize!` — enforce (or check) conjugate symmetry of a spectral field

**Priority: low; no IT code waits on it.**

**The need.** On the real-FFT layout, the ``k_x = 0`` plane's paired entries must be complex
conjugates. Everything inside IT preserves this by construction (every stochastic input enters
through an r2c transform of a real field), but IT's `fields_modified!` escape hatch lets a user
hand-write spectral coefficients, and a violation is currently undetectable — spectral diagnostics
silently disagree with the physical images. IT documents the contract ("it is not checked");
TurTLE's `field::symmetrize()` is the reference precedent (0-mode made real, Nyquist planes
zeroed, conjugate pairs reconciled).

**Suggested shape.** Either a repairing `symmetrize!(field)` or a cheap checker returning the
Hermitian residual of the redundant planes (O(N²) work). IT would call it only at the
`fields_modified!` boundary — never in the hot loop.

**Acceptance.** IT adds the call at its escape hatch and a witness: hand-corrupt the ``k_x = 0``
plane, and the violation is either repaired or named, rather than silent.

---

*Provenance note for the PF side: item 1's line numbers refer to the PF tree as of IT's reference
clone on 2026-08-23; the reproduction is version-independent. Items 2 and 3 were checked against
`names(GBGPeriodicFields)` on 0.1.0 — no existing export covers either.*
