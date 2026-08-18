# Panel review — Performance-focused DNS practitioner

Hat: a practitioner who writes and optimizes pseudospectral DNS codes. Focus:
numerical methods (rotational form, exact integrating factor, dealiasing bands,
IF-RK2 / low-storage RK3, particle interpolation, forcing) and performance claims
(allocation-free hot loop, in-place, GPU-agnostic storage, minimal footprint, CFL
scaling, the "2× transforms" of phase-shift).

## Headline verification (no defect — recorded for the panel)

The dealias-band numbers are **mutually consistent everywhere**, which was the
single thing this hat was told to verify especially:

- `TwoThirds`: κ_max = (2/3)κ_Ny = (2/3)(N/2)(2π/L) — Notation, TwoThirds docstring,
  max_wavenumber (f = 2/3) all agree.
- `HouLi`: f = 1, κ_max = κ_Ny — consistent.
- `PhaseShift`: κ_max = (√2/3)N·(2π/L) = (2√2/3)κ_Ny ≈ 0.94 κ_Ny — Notation,
  PhaseShift docstring, max_wavenumber (f = 2√2/3), §7, decision log all agree.
  "√2 wider", "≈2.8× the modes" ((√2)³ = 2√2 = 2.83), and "≈0.94 κ_Ny" all check out.

Also independently checked and **correct**: Williamson RK3 coefficients
A=(0,−5/9,−153/128), B=(1/3,15/16,8/15), d=(1/3,5/12,1/4) with Σd=1 and abscissae
(0,1/3,3/4); IF-Heun formula; RK2 |R(iy)|²=1+y⁴/4>1; RK3 imaginary-axis limit √3;
CFL C ≲ 3√3/(2π)=0.83; κ_max Δx = 2π/3; C ∝ 1/κ_max; Betchov constant
C=(4/7)√(15/2)=1.5649 and tr S³=3 det S for traceless symmetric S; Re_λ~N^{2/3};
ε=(k/G)^{3/2}/L inversion of Li2008; VonKarmanLarge 17/6 → κ⁴; Pope/Pao forms;
u'=√(2k/3), k=1.5→u'=1; HouLi strength = −log(eps) ≈ 36/16.

---

## Finding 1 — Measured spectrum is a per-shell energy (k = Σ E), model spectrum is a density (k = ∫ E dκ); compared directly by `validate_spectrum`

- type: dimensional
- severity: major
- confidence: medium

**Locations (exact rendered text):**
- PAGE: Notation — Diagnostics: "`$E(\kappa)$` | energy spectrum (**energy per unit
  wavenumber**), `$k = \sum_\kappa E(\kappa)$` | `energy_spectrum` (the
  `GBGPeriodicFields` radial spectrum, halved)".
- PAGE: API — Observables — `energy_spectrum`: "the turbulent kinetic energy resolved
  over wavenumber-magnitude shells, `$k = \sum_\kappa E(\kappa)$` … the field reduction
  sums `$\lvert\hat{\boldsymbol u}\rvert^2$` while the kinetic energy carries the `$\tfrac12$`".
- PAGE: Phenomenology — Reference laws — `spectrum`: "the **density in wavenumber** of
  the kinetic energy, `$k = \int_0^\infty E(\kappa)\,d\kappa$`".
- PAGE: Phenomenology — Spectra — `ModelSpectrum`:
  `$E(\kappa) = C_K\,\varepsilon^{2/3}\,\kappa^{-5/3}\,f_L(\kappa L)\,f_\eta(\kappa\eta)$`.
- PAGE: API — SimulationRun — `validate_spectrum`: "Returns a named tuple
  `(; wavenumbers, measured, predicted, relative_error)`: … the measured and predicted
  `$E(\kappa)$`, and the relative L² discrepancy".
- PAGE: Architecture §10 (category-error class) warns against exactly this:
  "a **spectral density `$E(\kappa)$` with an energy**".

**Contradicts:** the *measured* `E(κ)` is a per-shell energy (`k = Σ E(κ)`, units of
energy) while the *model* `E(κ)` is a spectral density (`k = ∫ E dκ`, units of
energy × length — check: `ε^{2/3}κ^{-5/3}` has units L³/T², a density). These differ by
the shell width Δκ = 2π/L. Axis of disagreement: **Σ vs ∫ / per-shell energy vs density**.

**Description:** The Notation entry is internally inconsistent on its own line: "energy
per unit wavenumber" (a density) with `k = Σ_κ E(κ)` (a sum) can only both be true when
the shell width is 1, i.e. L = 2π. `validate_spectrum` places the per-shell measured
`E` and the density model `E` side-by-side and reports a "relative L² discrepancy"; for
any box with side_length ≠ 2π the two objects differ by a constant factor Δκ = 2π/L, so
a perfectly matching run would still report a systematic error (or the model must be
multiplied by Δκ, which the docs never state). Since `side_length` is a documented
front-door option (defaulting to 2π, but overridable), the discrepancy is silently
box-size-dependent. `integral_scale` is immune because its ∫(E/κ)/∫E ratio cancels the
factor — but the direct spectrum comparison is not. This is the very "density-vs-energy"
category error §10 lists as its own correctness class.

**resolution_hint (advisory):** State whether the measured `E(κ)` is a per-shell energy
or a density, use one convention for both, and if they differ insert the explicit Δκ =
2π/L in `validate_spectrum`. For the default box (L = 2π, Δκ = 1) the numbers coincide,
which is likely why it has gone unnoticed.

---

## Finding 2 — `DealiasingStrategy` docstring (and two sibling texts) list only TwoThirds + HouLi, omitting the exported, fully-documented `PhaseShift`

- type: api-gap
- severity: minor
- confidence: high

**Locations (exact rendered text):**
- PAGE: API — SimulationDomain — `DealiasingStrategy` type: "**Concrete strategies:
  `TwoThirds` (the sharp `$2/3$` rule, the default) and `HouLi` (the smooth Hou–Li
  filter).**"
- PAGE: API — SimulationDomain — "## De-aliasing strategies" section intro: "the
  supertype, then the sharp 2/3-rule default and the smooth Hou–Li filter."
- PAGE: API — SimulationDomain — `dealias!`: "The kernel is whatever the run's
  `DealiasingStrategy` built: the sharp `$2/3$` cutoff (`TwoThirds`…) or the smooth
  `HouLi` filter…".

**Contradicts:**
- PAGE: API — SimulationDomain — module docstring: "`DealiasingStrategy` — the
  aliasing-control strategy, **`TwoThirds`, `HouLi`, or `PhaseShift`**".
- PAGE: API — SimulationDomain — `FixedDomain` arg `dealiasing`: lists all three
  ("… while `PhaseShift` averages a half-cell-displaced evaluation…").
- PAGE: API — SimulationDomain — `max_wavenumber`: "(`$2/3$` for `TwoThirds`, `$1$` for
  `HouLi`, `$2\sqrt2/3$` for `PhaseShift`)".
- `PhaseShift` has its own full type docstring rendered **inside the very same
  "De-aliasing strategies" section**.

**Description:** The supertype's own docstring is the natural place a user looks for the
concrete-strategy roster, and it names only two of three. Axis: **completeness of the
concrete-strategy list**. It is stale relative to the rest of the page, which knows
`PhaseShift` is a first-class `DealiasingStrategy`. (For `dealias!`, PhaseShift's kernel
is the spherical truncation at (2√2/3)κ_Ny — neither "the sharp 2/3 cutoff" nor "the
smooth HouLi filter" — so that docstring is incomplete for a PhaseShift domain too.)

---

## Finding 3 — IF-RK2 called "marginally-stable" in one place, "imaginary-axis unstable" everywhere else

- type: contradiction
- severity: minor
- confidence: high

**Locations (exact rendered text):**
- PAGE: API — Propagator — "## Integrator schemes" section intro: "the default
  third-order low-storage RK3, then the cheaper, **marginally-stable** second-order Heun."

**Contradicts:**
- PAGE: API — Propagator — module docstring: "`IFRK2`/Heun a cheaper two-stage
  alternative, **imaginary-axis unstable**".
- PAGE: API — Propagator — `IFRK2` Note: "`$\lvert R(\mathrm{i}y)\rvert^{2} = 1 +
  y^{4}/4 > 1$`: the scheme is **unstable on the imaginary axis**".
- PAGE: Architecture §4.5: "`IFRK2` (Heun) … is **imaginary-axis unstable** and leans
  on viscous damping".

**Description:** "Marginally stable" is a distinct stability category — the boundary
case |R(iy)| = 1 — whereas the scheme has |R(iy)|² = 1 + y⁴/4 **strictly greater than 1**
for every y ≠ 0, i.e. it is genuinely (weakly) unstable, as the other three passages
correctly state. Axis: **marginal (|R|=1) vs unstable (|R|>1)**. The lone "marginally-
stable" is the incorrect outlier for a scheme the docs elsewhere lean on viscous damping
to stabilize.

---

## Finding 4 — Default `velocity_forcing` said to hold the **total** energy, but the standalone `BandRescaling` default (`over = :band`) holds the **band** and lets the total float

- type: contradiction
- severity: minor
- confidence: medium

**Locations (exact rendered text):**
- PAGE: API — SimulationRun — `Simulation` "Setting the Reynolds number": "By default
  the run is forced and stationary — **a `BandRescaling` holds the total energy at
  `kinetic_energy`**".
- PAGE: API — SimulationRun — keyword `velocity_forcing`: "`velocity_forcing` defaults
  to **a `BandRescaling` holding the total energy at `kinetic_energy`**".
- PAGE: Architecture decision log: "a `BandRescaling` **holds the total energy** at
  `energy`, default `1.5`, i.e. `$u'=1$`".

**Contradicts:**
- PAGE: API — Forcing — `BandRescaling`: constructor "`BandRescaling(domain; target,
  **over = :band**, …)`"; and "`:band` (default) — **hold the band's own value; the
  whole-field value then floats**".

**Description:** Holding the *total* energy is the `over = :total` behaviour ("rescale
the band to … the whole-field value equals `target` … pins the r.m.s. velocity `$u'$`
and hence `$\mathrm{Re}_\lambda$`"), which is the **non-default** setting. The grid-mode
viscosity logic indeed *requires* `:total` (it fixes Re_λ from N and holds k =
kinetic_energy for the Li2008 prediction), so Simulation must be silently passing
`over = :total` — but that override is never stated, so a reader combining the two
docstrings gets a direct contradiction (default forcing "holds the total" vs
`BandRescaling` default "lets the total float"). Axis: **which `over` the default
forcing uses**.

**resolution_hint (advisory):** Say explicitly that the default `velocity_forcing` is
`BandRescaling(target = kinetic_energy, over = :total)`, distinguishing it from the
type's own `:band` default.

---

## Finding 5 — Scheme-independent buffer allocation carries IF-RK2's predictor registers into the default low-storage RK3 run

- type: performance
- severity: minor
- confidence: low

**Locations (exact rendered text):**
- PAGE: API — Propagator — `IntegratorBuffers` Fields: "`velocity_star_spectral` — the
  substage velocity predictor `$\hat{\boldsymbol{u}}^{*}$` in spectral representation
  (**the `IFRK2` update writes it** before the inverse transform)."
- PAGE: API — Propagator — `allocate_buffers`: "each scheme allocates **exactly its
  working set (currently the same for every scheme)**".
- PAGE: Home / Architecture invariant 4: "minimal memory footprint trumps compute cost";
  `IFLowStorageRK3` is "third-order and stable … **two field registers per field**" and
  "the lean, GPU-friendly default".

**Description:** The IF-RK2 predictor registers (`velocity_star`, `velocity_star_spectral`,
explicitly attributed to the IFRK2 update) live in the shared `IntegratorBuffers`, and
`allocate_buffers` is "the same for every scheme", so a run using the default low-storage
`IFLowStorageRK3` allocates these Heun-only field-sized buffers it does not use. The
phrase "each scheme allocates **exactly** its working set (currently the same for every
scheme)" is self-tensioning — "exactly its working set" and "the same for every scheme"
cannot both be tight when the schemes differ. For a design whose stated axis is "minimal
memory footprint trumps compute cost", allocating the union of all schemes' registers is
a (small, disclosed) footprint compromise on the default path. Marked low-confidence
because the docstring does not fully specify whether RK3 reuses `velocity_star` as generic
substage scratch.

---

## Finding 6 — §2 example forces with `ConstantPower` (fixed-injection → k rings) but the adjacent warm-up comment justifies reading ε via "a constant-energy forcing would clamp it flat"

- type: clarity
- severity: nit
- confidence: low

**Locations (exact rendered text):**
- PAGE: Architecture §2 code block: "`velocity_forcing = ConstantPower(target = 0.1)`"
  then the comment "`# Spin past the transient: advance until the running dissipation
  ε(t) stops drifting` / `# (k(t) is deliberately not used — a constant-energy forcing
  would clamp it flat).`"

**Contradicts (same package, different passage):**
- PAGE: API — Forcing — `ConstantPower`: "**Constant-injection-rate forcing**".
- PAGE: API — SimulationRun — `warmup!`: "a constant-energy forcing clamps it flat and
  **a fixed-injection forcing makes it ring**".

**Description:** `ConstantPower` is a fixed-injection forcing, which per the `warmup!`
docstring makes k(t) **ring**, not clamp. The example's justification for reading ε
instead of k invokes the *constant-energy* case (that is `BandRescaling(:total)`, not the
example's forcing). The general point (read ε, which settles last) holds either way, but
the example-specific reasoning names the wrong forcing behaviour. Axis: **fixed-injection
vs constant-energy** clamping.

---

## Finding 7 — Decision log uses stale forcing/energy API names (`ConstantPower(power=…)`, `ForcingSpec`, `energy`) with the `power → target` rename recorded nowhere

- type: organization
- severity: minor
- confidence: high

**Locations (exact rendered text):**
- PAGE: Architecture decision log: "**`ConstantPower(power = 0.1)`** (and the other
  banded forcings) return a **`ForcingSpec`** …".
- PAGE: Architecture decision log: "a `BandRescaling` holds the total energy at
  **`energy`**, default `1.5`".

**Contradicts:**
- PAGE: API — Forcing — `ConstantPower(domain; **target**, …)`; PAGE: Architecture §2 /
  §4.4 use "`ConstantPower(target = 0.1)`" and "a **`DeferredForcing`**".
- PAGE: API — SimulationRun — the keyword is **`kinetic_energy`** (default 1.5), not
  `energy`.
- The `ForcingSpec → DeferredForcing` rename **is** recorded in a later decision entry;
  the `power → target` keyword rename and the `energy → kinetic_energy` naming are **not**.

**Description:** The log is append-only, so the historical `ForcingSpec` name is
defensible (a later entry records its rename). But the `power → target` parameter rename
has no recorded entry anywhere, so `ConstantPower(power = 0.1)` reads as a currently-valid
call that would not work against the documented `target` keyword; and `energy` never
matches the public `kinetic_energy`. Axis: **current public keyword names vs the names in
the log**.

---

## Finding 8 — Public keyword `k_max_η` uses ASCII `k` for κ_max, colliding with the notation's emphatic k (kinetic energy) vs κ (wavenumber) rule

- type: clarity
- severity: minor
- confidence: medium

**Locations (exact rendered text):**
- PAGE: API — SimulationRun — `Simulation` constructor and keywords: "`k_max_η = 2`";
  and the body "sets `$\nu$` so that **`$\kappa_{\max}\eta$` equals `k_max_η`**".

**Contradicts:**
- PAGE: Notation — Conventions: "Wavenumber clash | `$\boldsymbol{\kappa}$` / `$\kappa$`
  / `$k$` | **Kept distinct**: bold `$\boldsymbol{\kappa}$` is the wavenumber vector,
  `$\kappa = \lvert\boldsymbol{\kappa}\rvert$` its magnitude …, and **italic scalar
  `$k$` is the turbulent kinetic energy**".

**Description:** The keyword names the resolution criterion κ_max·η but spells it with an
ASCII `k` (kinetic-energy glyph in the house notation), and the same docstring literally
equates "`$\kappa_{\max}\eta$` = `k_max_η`" — binding a κ quantity to a `k`-prefixed
name. The identifier also mixes ASCII `k` with a Unicode `η` (they clearly can spell
Unicode in identifiers), so `κ_max_η` was available. Axis: **the package's own κ-vs-k
distinction vs a public keyword that violates it**.

---

## Finding 9 — Phase-shift citation "Patterson & Orszag (1971)" is used but has no entry in the References list

- type: citation
- severity: minor
- confidence: high

**Locations (exact rendered text):**
- PAGE: API — SimulationDomain — `PhaseShift`: "Phase-shift de-aliasing follows
  **Patterson & Orszag (1971)**; the combination with spherical truncation is Rogallo
  (1981)."
- PAGE: Architecture decision log: "(a single half-cell shift is exact only in 1-D;
  **Patterson & Orszag 1971, Rogallo 1981**)".

**Contradicts:**
- PAGE: Architecture — References: lists "**Orszag, S. A. & Patterson, G. S. (1972)**.
  Numerical simulation of three-dimensional homogeneous isotropic turbulence…" and
  "Rogallo, R. S. (1981)…", but has **no `Patterson & Orszag (1971)` entry**.

**Description:** These are two genuinely different papers with reversed author order and
different years — Patterson & Orszag (1971, phase-shift dealiasing) vs Orszag & Patterson
(1972, the pseudospectral DNS) — and the docs correctly distinguish them, so this is not
a mixed-up citation. But the References preamble says "Cited author–year above; full
entries here", and the 1971 work (the primary phase-shift reference) is cited without a
full entry. (Related, lower: the "Orszag 1971" 2/3-rule reference appears only
parenthetically inside the 1972 entry.) Axis: **cited-but-unlisted reference**.
