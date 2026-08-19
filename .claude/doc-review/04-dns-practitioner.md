# Fresh-eyed review — hat: performance-focused DNS practitioner

Scope: numerical methods (rotational form, integrating factor, dealiasing bands, IF-RK2/RK3,
deposit-driven cache schedule, particle Heun push, forcing) and performance claims (allocation-free
hot loop, GPU-agnostic storage, per-scheme exact allocation, CFL scaling, PhaseShift "exactly 2×
transforms" claim). Read the full consolidated manuscript (ARCHITECTURE, notation, observables_cache
design page, and every rendered API page).

**Overall finding**: this corpus is unusually self-consistent on the performance/numerics axis. I
cross-checked every dealiasing-band number (2/3, HouLi-to-Nyquist, PhaseShift's √2/3·N ≡ (2√2/3)κ_Ny
≈0.94κ_Ny ≈2.8× the modes), every transform count in the observables_cache page's table against the
decision log's compute-audit figures (RK3 mask 18/9, with-scalar 21/18; PhaseShift exactly 2× in both
cases, RK3 42 c2r / RK2 28 c2r), the CFL-ceiling arithmetic (y_s/(κ_maxΔx) = √3/2.094 ≈ 0.827, rounded
to "≲0.83"), the resolution-criterion algebra (κ_maxη = fπη/Δx), and the Re_λ ~ N^(2/3) scaling — all
of it checks out arithmetically. The findings below are the residue: places where two passages use
different accounting bases for the same headline number, and one methodological transparency gap.

---

## Finding 1 — "IFLowStorageRK3's two registers" is defined two different ways across the corpus

**Type**: contradiction
**Severity**: minor
**Confidence**: medium

**Locations**:
- ARCHITECTURE.md §4.5: "`IFRK2` (Heun) is a two-stage option... three spectral registers per field
  against the low-storage scheme's two, counting the same way on both sides: **the scheme's own
  registers plus the dealiasing seam's assembly register**."
- `Propagator.IFLowStorageRK3` docstring: "in Williamson's 2N-storage count... **two field registers
  per field: the state's own array plus one accumulator (stage1)**. The `IntegratorBuffers` a run
  allocates can hold more than that count — for this scheme it adds `nonlinear`..."

**Contradicts**: ARCHITECTURE's "two" is explicitly `{stage1, nonlinear}` — the `IntegratorBuffers`
content alone, excluding the state array (this reading is independently confirmed by the
`observables_cache` design page's own tally: "a velocity-only run under `TwoThirds` or `HouLi` carries
six vector-shaped fields — four in spectral representation" = state + stage1 + nonlinear +
`product_spectral`, i.e. `IntegratorBuffers` contributes exactly 2). Propagator's own docstring instead
defines its "two" as `{state, stage1}`, explicitly *not* including `nonlinear` in that count. The two
"twos" are different pairs of arrays (only `stage1` is common to both) that happen to share a
cardinality by coincidence.

**Description**: A reader trying to reconcile "IFRK2 costs one more register than RK3" (architecture)
against "RK3's two registers are the state plus the accumulator" (Propagator) will not find the same
two arrays in both accounts. Neither individual sentence is wrong, but placed side by side under the
same headline number they teach two incompatible countings.

---

## Finding 2 — The quickstart's default forcing is a deterministic clamp, undisclosed at first contact

**Type**: clarity
**Severity**: minor
**Confidence**: medium

**Locations**:
- Home page: "`sim = Simulation(grid_points_per_axis = 64)`   # a 64³ forced-stationary run; ... ν is set
  so the grid resolves the dissipation scale" — no mention of what forcing is used or its statistical
  character.
- `SimulationRun.Simulation` docstring, elsewhere in the same corpus: "**a deterministic clamp**: it
  rescales the band every step to hold the kinetic energy at the target value... and **suppresses the
  physical fluctuation of the quantity it holds**."
- `BandRescaling` docstring: "**A deterministic clamp, not a stationary sampler**... Such a scheme has
  no conserved quantity, is not associated with a well-defined ensemble except in limiting cases."

**Description**: The flagship one-line quickstart example silently produces a flow whose kinetic
energy — and hence whose Re_λ — is pinned by a deterministic rescale with suppressed physical
fluctuations (extensively and honestly caveated three modules away). A practitioner copying the
quickstart to gather amplitude-fluctuation statistics would get contaminated results with no signal at
the point of first contact that anything unusual is happening. The caveat exists; it just never
reaches the page that most needs it.

---

## Finding 3 — PhaseShift's per-term scratch-buffer count is stated only vaguely

**Type**: clarity
**Severity**: nit
**Confidence**: low

**Locations**:
- `SimulationDomain.PhaseShift` docstring: "a second nonlinear-term transform per stage (2× the
  transforms) and **the displaced-evaluation scratch** (a field-scale spectral-representation buffer
  **per phase-shifted term**)."
- `Generator.ResolvedGenerator` Fields: "`phase_shift` — **the displaced-evaluation scratch** and
  translation kernels (`PhaseShift` dealiasing only), else `nothing`."

**Description**: "Per phase-shifted term" (velocity/Lamb, scalar/flux) implies at least two, plausibly
three, buffers (u_shifted, ω_shifted, and — when scalar is carried — φ_shifted), consistent with the
same-stage `u_shifted` reuse contract described in the decision log. But no page states the count
explicitly, so a reader pricing PhaseShift's memory delta against a mask strategy has to infer the
buffer count rather than read it. Low confidence because this may simply be a level-of-detail choice
(the `# Fields` entry names the bundle, not its cardinality) rather than an omission.

---

## Finding 4 — "Setting the Reynolds number" doesn't state what happens if `κ_max_η` is passed together with an explicit dealiasing strategy whose `f` changes the achievable Re at fixed N

**Type**: clarity
**Severity**: nit
**Confidence**: low

**Locations**:
- `SimulationRun.Simulation` docstring: "a wider-band strategy (larger f) resolves a finer dissipation
  scale η on the same grid at the same `κ_max_η`... The `kinetic_energy` and `side_length` fix the
  units; the grid and `κ_max_η` fix Re_λ ~ N^(2/3)."

**Description**: The scaling law Re_λ ~ N^(2/3) is stated as though it depends only on N and
`κ_max_η`, immediately after establishing that the achievable η (and hence ν and Re) also depends on
the dealiasing strategy's retained-Nyquist fraction f (HouLi's f=1 vs TwoThirds' f=2/3 vs PhaseShift's
f=2√2/3 ≈0.943). The N^(2/3) proportionality's hidden constant therefore itself depends on which
`dealiasing` strategy is chosen — true and derivable from the surrounding prose, but the headline
scaling-law sentence reads as strategy-independent when it isn't. A worked comparison (e.g. "HouLi
buys ~1.5× the Re_λ of TwoThirds at fixed N and κ_max_η") would close the gap; this is a nit since the
information to derive it is present two sentences earlier.

---

## Notes on what I verified and did *not* flag (for the record)

- PhaseShift band/transform-cost consistency (√2/3·N, 2√2/3·κ_Ny, ≈2.8× modes, exactly 2× transforms
  for velocity *and* scalar, RK3 42 c2r / RK2 28 c2r) is internally consistent across ARCHITECTURE,
  the decision log, `SimulationDomain.PhaseShift`, and the `observables_cache` transform table — no
  contradiction found despite dedicated adversarial cross-checking, which is the item my brief
  specifically asked me to hunt hardest for.
- The IFLowStorageRK3 stability limit y_s=√3 and the IFRK2 instability proof
  (|R(iy)|² = 1+y⁴/4 > 1) are both textbook-correct.
- The CFL-ceiling arithmetic (0.827 rounded to "≲0.83", scaled to 0.5) and the resolution-criterion
  algebra (κ_maxη = fπη/Δx) both check out by direct computation.
- The quadratic-reduction alias-freedom condition (2κ_max < N) and its HouLi exception (κ_max = N/2,
  exactly at the boundary, machine-precision-damped rather than exactly zero) is stated correctly and
  consistently.
- Memory figures (384 MiB / 768 MiB / 2.3 GiB at 256³/Float64, and the 322.5 MiB → 2.52 GiB frame
  scaling from 256³ to 512³) all reproduce exactly under direct calculation.
