# Panel round — 2026-08-14/15 (Enteropia) — 85 findings across 11 hats

Run: `/check-consistency`, economy mode (9 Sonnet lanes + 2 full-strength physics anchors), against the
docs built at commit `ebfde77` — i.e. **after** decisions 46–48 (the Observables/Cache reorder, the
recovery move to PF's arity, the closing-deposit vocabulary sweep) and after the `/check-docs` battery.
Sequential, collect-only, 11/11 hats returned, 0 errors, ~104 min.

**STATUS: CLOSED — 85/85 dispositioned. 75 fixed, 10 adjudicated as not defects.**
Commits `0baddf3` (Tier 1 + Tier 2), `e8fba92` (Tier 3: citations, argument sections, K41),
`c1d2fcc` (the remainder). Dashboard: https://claude.ai/code/artifact/e3216b09-781a-4b79-8d68-eeeed43a0fcc
Suite green, docs build exit 0, both lints clean, surface 4 re-audited after every batch.

> The per-hat `NN-*.md` files are the work list. This summary is a **lossy** reading aid — a fix pass
> must enumerate every finding in every hat by number and close it there, never from this file. A
> severity here never overrides the hat's own.

Counts per hat: 01:2 · 02:7 · 03:10 · 04:5 · 05:12 · 06:6 · 07:8 · 08:9 · 09:4 · 10:7 · 11:15 = **85**

---

## Tier 1 — verified at source, unambiguous defects (5)

Each was confirmed against current `src/` or the built HTML in the main thread before being listed here.

**T1-1. The rendered module Index still carries the pre-decision-46 order.** (hat 01#1)
Five prose surfaces state `… State → Observables → Cache → Forcing → Generator …`; the rendered Index
groups `State, Cache, Generator, Observables, Forcing`. **Verified cause:** `docs/make.jl:121–129`'s
`modules = [...]` list — which drives the Index grouping — was never updated. My decision-46 commit
fixed the pages and the sidebar and missed this one. *(One-line fix; also explains why hat 01 ranked it
major — five statements against the machine-generated truth.)*

**T1-2. The bare `C` in the skewness formula — found by FOUR hats.** (03#6, 06#2, 08#4, 10#2)
`ARCHITECTURE.md:318` and `:886` write `3C\langle\det S\rangle/…` and then name the constant `C_S` in
the same sentence; `notation.md` explicitly reserves bare `C` for the CFL ceiling, and the
`derivative_skewness` docstring uses `C_S` throughout. **Verified:** both sites present. The strongest
corroboration signal in the round.

**T1-3. The Particles "tracking loop" intro describes the retired pre-cache mechanism.** (hat 10#1)
`docs/src/api/Particles.md:25–29`: *"put the start-of-step velocity on record … the start-of-step values
are taken off it **before the state advances**."* **Verified false:** `SimulationRun.jl:414–418` calls
`deposit!`, then `advect!`, then `record_trajectory_velocity!` — at the iteration's **end**, on the
just-deposited velocity. The function's own docstring and `advect!`'s Note both state the current order;
only this section intro is stale (decision 42 moved it).

**T1-4. "Spectral fields" / "the spectral velocity" — the package's own banned category error.** (03#4)
`notation.md` states the rule ("a field is one physical object; physical and spectral are two
representations"), §10 names the class. **Verified 6 sites:** `ARCHITECTURE.md:192, 365, 420, 1007, 1592`
and — the one that matters most — `src/Cache.jl:272`, a **rendered docstring**
(`resolved_fields_modified!`). Same class as the "spectral differential operators" fix in `01fdeb4`.

**T1-5. "Every diagnostic is dimensionless" is false.** (03#5)
`ARCHITECTURE.md:734` (invariant list). ε, k, u′, L₁₁, η, τ_η, λ all carry dimensions in box units; what
is dimensionless is the *control* (Re, Sc) and the reference *constants*. Collides with `FlowParameters`,
documented as carrying "the independent **dimensional** quantities".

---

## Tier 2 — real, needing a judgment call or a decision (13)

**T2-1. `E(κ)` is one glyph for two dimensionally distinct objects.** (08#7, adjacent 03)
Measured = energy per shell (L²T⁻²); model = spectral density (L³T⁻²). `notation.md` binds both to `E(κ)`
and annotates the difference in prose. This is precisely the "per-κ density vs an energy" category error
the doc policy names. **Decision needed:** distinguish the measured one glyph-wise, or accept the
annotation as sufficient.

**T2-2. The default run is driven by the forcing the docs call unfit for measurement.** (03#1)
`Simulation` says "forced and stationary"; `BandRescaling` says "a deterministic clamp, not a faithful
stationary sampler … when the held quantity is itself measured, prefer `ConstantPower`". The clamped
quantity is `kinetic_energy` — what a validation run measures. **Escalation:** a caveat at the front
door, or reconsider the default. Not a wording fix.

**T2-3. "Caching costs nothing on any axis" vs the recorded +1 pass/iteration.** (08#3, 04#2, 01#2 — three hats)
The cache page and `deposit!` claim unchanged pass counts; the decision log records a once-per-iteration
max-speed pass and host readback in **every** cell, held by `UNIFORM DEPOSIT SCHEDULE`, paid even under a
fixed Δt. Also a live GPU cost invisible on the two pages a performance-minded caller reads (`advance!`,
`deposit!`).

**T2-4. `Li2008`'s three numbers don't satisfy its own identity.** (08#1 — corroborates my own check-docs flag)
`G = (3/2)C_ε^{-2/3}(L₁₁/L)^{2/3}` with the quoted `C_ε = 0.5`, `L/L₁₁ ≈ 5` gives `G = 0.814`, not the
quoted `0.9`; consistency needs `L/L₁₁ ≈ 4.3`. The passage exists to let a reader close the two groups.

**T2-5. In-place protocol verbs never document their return value.** (07#1)
`velocity_rhs!`, `scalar_rhs!`, `step!`, `deposit!`, `dealias!` — while `prepare!`, `finalize!`,
`vorticity_physical!`, `resolved_fields_modified!` and all four Forcing hooks state theirs explicitly.
The docs invite hand-run loops, so this is a real gap.

**T2-6. `velocity_rhs!`/`scalar_rhs!` clobber different, unpredictable argument positions.** (02#1, 07 adjacent)
`velocity_rhs!` destroys the last physical arg (`ω`, keeps `u`); `scalar_rhs!` destroys a non-last one
(`u`, keeps `φ`). Two halves of one protocol disagreeing. **Escalation** — an API-shape question, not a
doc fix.

**T2-7. `max_wavenumber`: "the modes above it are zeroed each step" is false for `HouLi`.** (08#6)
`SimulationDomain.jl:257`. HouLi has `f = 1`, so corner modes out to √3·κ_Ny are *damped*, not zeroed.
`HouLi`'s and `dealias!`'s own docstrings state the correct weaker claim.

**T2-8. HouLi's `f = 1` "resolves a finer η" credit assumes clean bandwidth its own page disclaims.** (04#1)
The grid-mode viscosity formula credits a wider retained band with a finer η at equal `k_max_η`, treating
HouLi's band as trustworthy resolved signal where HouLi documents it as only damped.

**T2-9. No `particles_modified!` counterpart to `resolved_fields_modified!`.** (02#2)
The cache is explicitly two-axis (`fields_epoch`, `particles_epoch`) and the architecture generalizes
"writing stays on the dot path", but only the fields axis has an announce verb.

**T2-10. `FlowParameters.scalar_dissipation` uses `NaN` as the unset sentinel.** (02#3)
Against the package's own throw-don't-degrade discipline; `NaN` propagates silently where `nothing`
would fail loudly at the point of misuse.

**T2-11. Cold-read: four load-bearing terms unglossed where they first appear.** (11#1–#4)
"front door" (Home, first sentence of Quick start; re-glossed three times later, defined on a fourth
page); "iteration"/"deposit"/"stamp" (Home, before the Cache page defines them); "scratch arity" (used
verbatim twice, defined nowhere); "2N-storage" (reuses `N`, which `notation.md` fixes as grid points).

**T2-12. Exception types are never named on the surfaces that throw.** (07#3, 07#6)
The checked reads document *that* they throw; only `ObservablesCache`'s type docstring names
`ErrorException`. Same for the `StructureFunctions` "any other order throws".

**T2-13. `IFRK2`'s CFL 0.25 is presented inside a derivation it isn't derived from.** (04#3)
`y_s = 0` makes the stated formula vanish; 0.25 is substituted with no derivation and no ν-dependence,
beside a stability argument that is explicitly ν-dependent.

---

## Tier 3 — nits, style, and structure (≈67 remaining)

- **Structure (hat 05, 12 findings)** — four different shapes for "enumerate the constructor arguments"
  (`Arguments:` / `Keywords:` / unheaded bullets / prose-only); citation placement front-loaded in ~10
  types, deferred in 3; two module maps whose bullet order doesn't track their page's sections (Cache,
  Particles); two documented operations missing from their module's map (`DeferredForcing`,
  `stationary_dissipation`); the "plain constructor" preamble on 8 types and absent on 14.
- **Typesetting (hat 06)** — `\frac{\partial u}{\partial t}` on the cache page vs `\partial_t u` in seven
  other restatements of the same equation; mixed `\tfrac`/`\frac` inside one `Lundgren2002` display;
  `\mathrm d` vs `\mathrm{d}`; `\kappa^4` unbraced 4×/braced 1× in one file; the Home scalar equation
  spelling `ν/Sc` where ϰ is the reserved glyph.
- **Citations (hat 09)** — `Kolmogorov1941` carries both the 2/3 law (Dokl. **30**) and the exact 4/5 law
  (historically Dokl. **32**) under one Reference; `TwoThirds` alone of the three strategies carries no
  inline citation (Orszag 1971 exists in §References); eight inline-only Spectra citations unresolvable
  while the one named exemplar gets full detail; a 301 vs 301–305 page-range split.
- **`StationarityCriterion`** (11#7, 05#6, 10#7 — three hats) — 7 keywords vs a 6-entry Fields list; five
  keywords vanish into an opaque `monitor`, and only `gate_scalar` of the two sibling gates gets a bullet.
- **Vocabulary** (11#5, 10#3 — two hats) — Home says "the instant between **steps**"; decision 48 settled
  on "between iterations", and step ⊂ iteration is a distinction the corpus otherwise keeps.
- Plus: `2.51` should be `2.52 GiB` (08#9); the 10-flops/24-bytes pair describing two different kernels
  (08#8, 04#4); `peak_wavenumber` is √2 off the peak it names and doubles as `1/L₁₁` (08#5); the CFL √3
  gap not actually absorbed by 0.83→0.5 (08#2); `Phenomenology` a peer bullet on Home, a subordinate
  clause on api.md (05#8); PascalCase factory functions (02#7); `integrator` as a SciML false cognate
  (02#6); a decision-log sentence opening with a lowercase identifier (10#6); `Simulation`'s "Keywords"
  section listing a positional argument (07#7); no end-to-end tracer example (07#4).

---

## Self-inflicted, found in verification (not a hat finding)

The decision-48 vocabulary sweep left two `#`-comment artifacts: `SimulationRun.jl:10`
("recovers **the deposited** observables") and `:410` ("deposit **the deposited** observables"), both
from the mechanical `boundary observables → deposited observables` substitution. Not rendered, but
wrong. Fix with the pass.

## Verified clean (batteries the panel ran and closed)

- **All physics.** Both anchors re-derived, independently: `C_S = (4/7)√(15/2)` against **both** stated
  isotropy relations and Betchov's identities; the ε Dirichlet route; `ε_φ = 2ϰ⟨|∇φ|²⟩`; Yaglom's
  −(2/3)ε_φ r from the KHM balance; `L₁₁`/`L_E`/`L₂₂` from `R_ii(r)`; the RK3 coefficients (Σd = 1) and
  IFRK2's `|R(iy)|² = 1 + y⁴/4`; the phase-shift `2√2/3 κ_Ny` and ×2.8 modes in all six places;
  `κ_max η = fπη/Δx`, `Re_λ ~ N^{2/3}`; the alias condition `2κ_max < N`; every memory figure and every
  transform-ledger cell (18/9, 21/18, 36/18, 42/36; 51→42, 34→28); She–Lévêque, K62, Pope/von Kármán/
  Pao/Obukhov–Corrsin.
- **Citations** — no fabricated or unverifiable reference across ~28 checked; no citation to the
  gitignored `inspiration/`; no unsubstantiated "exact"/"allocation-free"/"optimal" claim.
- **Typesetting** — no `\left`/`\right` anywhere; no unbraced `\boldsymbol u`/`\tfrac12`; every code
  identifier inside a math span `\texttt{}`-wrapped; `\mathrm{i}` everywhere; operators upright.
- **Raw HTML** — the pipe-tables and glued admonition titles in the manuscript are extraction artifacts;
  they render as real `<table>`s and Documenter admonitions. `Fields` renders uniformly on all 10 pages.
- **The decision-48 rename** — hat 10 swept for `trajectory_sample`, `tracer_positions`, "tail deposit",
  "boundary velocity/observables" and found none outside the decision-log entries recording the old
  names (exempt).

## False positives / adjudicated

- Manuscript-extraction artifacts (tables, admonition titles) — confirmed clean in the built HTML by
  hat 10 itself; already in `doc-review-adjudicated.md` from the prior round.
- `Lundgren2002` "missing" from StructureFunctions' References — re-checked present, correctly
  **not** re-flagged (the adjudication file did its job).
- 11#8 (`PointSet`/`*PointValues` undefined) — self-flagged low confidence; these are `@extref`-linked
  backend types the text extraction can't show. Not a defect.
