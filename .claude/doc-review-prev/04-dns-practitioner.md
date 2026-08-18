# DNS-practitioner (performance/numerics) hat — findings

Reviewed the full rendered manuscript (Home, api overview, ARCHITECTURE.md, notation.md,
observables_cache.md, phenomenology.md, and every `api/*` docstring page) against practitioner
knowledge of pseudospectral DNS codes, cross-checking dealiasing bands, transform/pass counts, CFL
derivations, and the deposit-driven cache's cost claims for internal agreement. The document is
unusually self-consistent — I independently re-derived the 2/3 and √2/3·N phase-shift cutoffs, the
2.8× mode-count ratio, the RKW3 (Williamson) coefficients, the IFRK2 stability polynomial
|R(iy)|²=1+y⁴/4, the Re_λ~N^(2/3) resolution scaling, the Taylor-microscale identities, the
Li2008↔Sreenivasan1998 conversion G=3/2·C_ε^(-2/3), and every transform-count table cell (18/9,
21/18, 36/18, 42/36 inverse/forward) against the per-evaluation operation breakdown and the decision
log's "RK3 51→42, RK2 34→28" c2r figures — all checked out exactly. The findings below are the
residue after that pass.

---

## Finding 1 — HouLi's f=1 "resolves a finer η" claim leans on spectral content its own docstring calls inexact

**Type:** method
**Severity:** major
**Confidence:** medium

**Locations:**
- PAGE: api / SimulationRun, `Simulation` docstring, "Setting the Reynolds number": *"a wider-band strategy (larger $f$) resolves a finer dissipation scale $\eta$ on the same grid at the same `k_max_η`"*
- PAGE: api / SimulationDomain, `HouLi` docstring: *"It keeps more modes than the $2/3$ rule but only damps aliasing rather than removing it exactly — a stabilization"*
- PAGE: api / SimulationDomain, `max_wavenumber` docstring: *"$f$ ... ($2/3$ for `TwoThirds`, $1$ for `HouLi`, ...)"*

**Description:** The grid-mode viscosity selection (`Simulation`'s `k_max_η` criterion) computes
$\eta = k_{\max\eta}\,\Delta x/(f\pi)$ and credits a larger retained-Nyquist fraction $f$ — HouLi's
$f=1$, all the way to Nyquist — with resolving a *smaller, finer* $\eta$ (i.e. a higher trustworthy
Reynolds number) than TwoThirds' exact $f=2/3$, on the *same* grid. That treats HouLi's $\kappa_{\max}$
as equally trustworthy resolved bandwidth. But HouLi's own docstring states the retained band beyond
$2/3\,\kappa_{\mathrm{Ny}}$ is only damped, not exactly dealiased (exact suppression is guaranteed only
asymptotically at $\kappa_{\mathrm{Ny}}$ itself, via the `strength` calibration). The resolution formula
does not caveat that the "finer $\eta$" HouLi is credited with partly rests on spectral content whose
own page disclaims exactness — an apples-to-oranges comparison folded into one formula with no
warning.

**Resolution hint:** Either note in `Simulation`'s "Setting the Reynolds number" section that the
$f$-credit assumes the retained band is clean signal (true for `TwoThirds`/`PhaseShift`, approximate
for `HouLi`), or state the practical residual aliasing HouLi leaves at, say, $0.9\,\kappa_{\mathrm{Ny}}$
for its default `order`/`strength`.

---

## Finding 2 — `max_speed`'s reduction + device readback is unconditional even under a fixed `dt`, and this isn't stated where a user would look

**Type:** performance
**Severity:** minor
**Confidence:** medium-high

**Locations:**
- PAGE: api / SimulationRun, `advance!` docstring: *"pass `dt` to force a fixed step"*
- PAGE: api / Propagator, `deposit!` docstring: *"the maximum-speed reduction over the just-deposited velocity"*
- PAGE: architecture, decision log (2026-08, "The observables cache is deposit-driven"): *"a hand-fixed-$\Delta t$ iteration still pays it — held by the new `UNIFORM DEPOSIT SCHEDULE` design holder, the price of a schedule that never varies with how the run is driven"*

**Description:** `advance!`'s `dt` keyword reads as an opt-out of the CFL machinery. Nothing in
`advance!` or `deposit!`'s rendered docstrings tells the reader that the cache's fixed, uniform
schedule computes and stamps `max_speed` — a full-field reduction and (per the architecture's own
host-device-synchronization axis) a blocking device-to-host readback — on *every* iteration
regardless, even one driven entirely by an explicit fixed `dt` that never reads it. This is a real,
currently-true GPU pipeline-stall cost (the decision log names it explicitly as a live, accepted
holder), yet it surfaces nowhere on the two public-surface pages a performance-conscious caller would
read to decide whether fixing `dt` avoids that cost.

**Resolution hint:** A one-line note on `advance!` or `deposit!`: "the maximum-speed reduction and its
host readback run every iteration regardless of whether `dt` is fixed or adaptive."

---

## Finding 3 — `IFRK2`'s CFL ceiling (0.25) is presented inside the same derivation as RK3's but isn't actually derived, and carries no stated ν-dependence

**Type:** method
**Severity:** minor
**Confidence:** low-medium

**Locations:**
- PAGE: api / Propagator, `recommended_cfl` docstring: *"`IFRK2` is imaginary-axis unstable ($y_{\mathrm{s}} = 0$, relying on viscous damping), so a small $0.25$"*

**Description:** The docstring frames every scheme's ceiling through $C \lesssim y_{\mathrm s}/(\kappa_{\max}\Delta x)$; for `IFLowStorageRK3` this is shown worked out ($C\lesssim0.83$). For `IFRK2`, $y_{\mathrm s}=0$ makes that formula vanish identically, so `0.25` is substituted with no derivation — yet the same sentence says stability there depends on viscous damping, i.e. on $\nu\lvert\boldsymbol\kappa\rvert^2\Delta t$, a quantity that shrinks as $\nu\to0$ (higher Reynolds number). A flat constant independent of $\nu$ sits oddly next to a stability argument that is explicitly $\nu$-dependent; nothing in the ceiling's derivation or in `IFRK2`'s own docstring states what Reynolds-number or resolution regime `0.25` was calibrated for.

**Resolution hint:** Either derive the constant (e.g. from the viscous term's own stability boundary at the retained $\kappa_{\max}$) or note explicitly that `0.25` is an empirical safety margin, not a stability-limit computation, unlike the RK3 value beside it.

---

## Finding 4 — the "24 bytes moved" traffic estimate is silently Float64-only

**Type:** performance
**Severity:** nit
**Confidence:** low

**Locations:**
- PAGE: observables_cache, §1.1: *"a pointwise multiplication over a grid costs about ten arithmetic operations per point against twenty-four bytes moved"*

**Description:** 24 bytes = 3 arrays × 8 bytes/element is exact only for `Float64`; under `Float32` (documented elsewhere as an equally first-class, GPU-friendly precision — "no privileged precision or backend") the same pointwise kernel moves 12 bytes, halving the byte-to-flop ratio the bandwidth-bound argument rests on. The page states the figure as a flat fact with no precision qualifier, in a document that otherwise treats precision as a first-class studied axis.

**Resolution hint:** Qualify as "twenty-four bytes moved in double precision (twelve in single)."

---

## Finding 5 — "five operations" doesn't cleanly match the four semicolon-delimited clauses that follow it

**Type:** clarity
**Severity:** nit
**Confidence:** low

**Locations:**
- PAGE: observables_cache, §2.3: *"one evaluation of the velocity term proceeds in five operations"* followed by exactly four semicolon-separated clauses (recover **u**; form ω̂ and recover ω; multiply and transform back; apply the projection and the mask).

**Description:** Depending on how the compound clauses are split, the enumerated list reads as four, six, or (with one specific split) five items — the "five" is not self-evidently traceable to the prose that follows it. Low-confidence because natural-language operation counts are inherently a little elastic and a plausible 5-way split does exist.

**Resolution hint:** Number the clauses explicitly, or drop the "five operations" lead-in.
