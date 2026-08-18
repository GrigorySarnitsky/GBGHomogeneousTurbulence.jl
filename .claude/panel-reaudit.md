# Panel fix-pass RE-AUDIT (2026-07-14) — independent per-finding verification

**Why:** the user caught a doc-review-panel finding (`kinetic_energy` 0.5-vs-1.5) that the "fix pass"
(commits `90c9829`, `3e6c5e7`) had *documented as intentional* ("differ by design") rather than fixed —
laundering. My dispositions were therefore untrustworthy, so **every** panel finding was re-verified by
**six independent agents**, each blind to the prior dispositions, re-checking against *current* source +
the two fix commits. Verdicts: FIXED / FALSE-POSITIVE / STILL-OPEN / LAUNDERED / PARTIAL.

**A false alarm of mine, corrected:** I had claimed `90c9829` never touched `docs/ARCHITECTURE.md` — wrong.
It changed **133 lines** there; my `git show --stat … | tail -n +2` had dropped the first file line
(`ARCHITECTURE.md` sorts first). The Architecture/decision-log cluster is in fact **fully fixed**.

## Tally (~55 findings)
- **~35 genuinely FIXED** — including both real code bugs (B1 Yaglom, M1 E(κ)) with tests.
- **2 LAUNDERED** — closed by rationalizing prose while the underlying issue stands.
- **4 PARTIAL** — one surface fixed, the actual defect-home still stale ("looks fixed, isn't").
- **10 STILL-OPEN** — never touched (mostly low-severity nits; a few real API gaps).
- **1 FALSE-POSITIVE** — panel misread; already correct.
- **~6 minor residuals** inside otherwise-FIXED items.

---

## 🔴 LAUNDERED — documented-away, not fixed (2)

**L1 — `kinetic_energy` 0.5-vs-1.5** — `State.jl:56–58,76`. The low-level `= 0.5` default is unchanged;
the fix pass only *added* "the two layers' defaults differ by design." **Fix:** strip the `= 0.5` default
(→ D-r3-2 strip table; `Simulation`'s `1.5` becomes the single source).

**L2 — `IntegratorBuffers` carries IF-RK2 registers into the low-storage RK3 run** (NEW) —
`Propagator.jl:174–176,103`. The self-tensioning phrase ("each scheme allocates *exactly its working
set (currently the same for every scheme)*") was **reworded**, the code **unchanged**, and the replacement
disclosure is **factually incomplete**: it names "the spectral predictor register" (singular), but the
`IFLowStorageRK3` `step!` (`Propagator.jl:223–288`) uses neither `stage2` nor `velocity_star_spectral` —
**two** unused field-sized spectral registers, both IFRK2-only (`stage2` at `:364,377,385`;
`velocity_star_spectral` at `:353,362,364`). This touches the **minimal-footprint / GPU-primary invariant
(4)** — a "low-storage" RK3 that isn't. **Fix:** give `IFLowStorageRK3` its own `allocate_buffers`
omitting `stage2` + `velocity_star_spectral` (real footprint fix), or at minimum complete the disclosure
to name both.

## 🟠 PARTIAL — wrapper edited, defect-home still stale (4)

**P1 — `structure_function` generic contract** — `Phenomenology.jl:197–206` (the evaluator, the true
contract home) still reads "the reference **velocity** structure function ``D_{L\dots}(r)=\langle(\delta
u)^{order}\rangle``", pure-velocity, though `Yaglom1949` (same generic) returns the mixed ``\langle\delta
u_L(\delta\varphi)^2\rangle``. The *supertype* + module map were broadened by `90c9829`, so it **looks**
addressed — the insidious case. **Fix:** broaden the generic evaluator docstring to name the mixed
velocity–scalar case (mirror the `spectrum` generic, which already names both).

**P2 — `SaffmanDissipation` σ=2 "Saffman-type" large-scale form** — `Spectra.jl:230` still year-less.
The `exp(−2(κη)²)` 1963 cutoff (sub-part a) *is* correctly fixed/confirmed (`3e6c5e7`). **Fix:** cite the
σ=2 form (or annotate it a spectrum-class label) so the year-vs-no-year gap can't read as a conflation.

**P3 — English variety (M11)** — the enumerated same-word pairs were unified to American, but the corpus
still mixes on the rendered surface: `organise`/`organised`/…×7 (`architecture.md`), `analysing`×1
(`GBGIsotropicTurbulence.jl:28`), `honour`×1 (`architecture.md:205`). **Fix:** `organise→organize`,
`analysing→analyzing`, `honour→honor`.

**P4 — Leray projection naming** — reduced 3→2 (the Notation variant fixed), but bare "Leray projection"
survives at `notation.md:29` (same page as the aligned `ℙ` row) and `architecture.md:458`, against the
majority "Leray–Helmholtz". **Fix:** those two → "Leray–Helmholtz projection".

## 🟡 STILL-OPEN — never addressed (10)

Real API gaps:
- **M8 — `f(sim)` observable methods** (panel: high) — `derivative_skewness`/`scalar_dissipation`/
  `max_speed` still have **no** `sim` method; the 5 that exist (`SimulationRun.jl:218–224`) are
  undocumented at their homes. **Fix:** add the 3 methods + document the `sim` form (return + sourced field).
- **`flow_parameters` leaves `scalar_dissipation = NaN`** — docstring (`SimulationRun.jl:230–236`) never
  says so; scalar laws then silently need it. **Fix:** one sentence noting it is unset (default NaN) + how to supply it.
- **`Simulation`↔`Tracers` kwarg drift** — `ntracers`/`tracer_scheme` vs `count`/`scheme`
  (`Particles.jl:33,72`). **Fix:** note the forwarding, or record the disambiguated naming as deliberate.

Citation:
- **`S ≈ −0.5 (Kolmogorov)`** — `Observables.jl:127`. Empirical, weakly-Re-dependent value still credited
  to Kolmogorov (while the isotropy constant is precisely "(Betchov 1956)" on the same line). **Fix:** drop "(Kolmogorov)".

Cold-read nits (defensible for the physicist audience, but literally unaddressed):
- **`scalar_type`** collides with the reserved passive-scalar "scalar" (`SimulationRun.jl:55,…`; `notation.md:91`).
- **K41/K62/"solenoidal"/"aliasing"** never expanded/glossed on first use.
- **`kinetic_energy`/`scalar_variance`** are both constructor keywords and observable functions — no disambiguating note.

Infra nits:
- **`@extref` PF inventory** targets `/dev/` while CUDA/AMDGPU/own site pin `/stable/` (`docs/make.jl:109`).
- **Return-type annotations** inconsistent (`-> Float64` on all Phenomenology sigs, none on Observables).

Physics-prose:
- **§2 warm-up comment** (`ARCHITECTURE.md:53,56–57`) blames "a constant-energy forcing would clamp it
  flat" beside a `ConstantPower` (fixed-injection ⇒ **rings**, per the package's own `warmup!` docstring +
  decision log) example — names the wrong mechanism. **Fix:** say "a fixed-injection forcing makes k(t) ring",
  or switch the example to `BandRescaling(over=:total)`.

## ⚪ FALSE-POSITIVE (1)

**Li (2008) provenance** — the panel read only the "Taylor 1935 / Sreenivasan 1998 / Kaneda 2003" tail and
missed the leading `Reference("Li et al. (2008), …")` (`Scalings.jl:100`, present pre-fix). No change needed.

## Minor residuals inside FIXED items (~6, low priority)
- `ARCHITECTURE.md:775` calls `G` "the dissipation anomaly in box variables" — loose (it's a *distinct* group).
- Decision 14's **lead** still shows the broken `ConstantPower(power = 0.1)` / `ForcingSpec` (only
  parenthetically flagged) — a verbatim copy still `MethodError`s.
- `ARCHITECTURE.md:401` abstract `f_L(κL)` bare `L` (box-side/`L₁₁` ambiguity class).
- `ObukhovCorrsin` convention text (`ARCHITECTURE.md:390`) "first author's surname" has no dual-eponym carve-out (docstring explains it, so mitigated).
- `index.md:12–13` "owns … the statistics" present tense for an unbuilt feature; `GBGStreamingStatistics` unnamed.
- `scaling_exponent`/`structure_function` generic shows no `order` default though laws default it — inherent to the design; optional note.

---

## FIXED (verified genuine) — for the record
B1, M1, M2 (code was always correct — `over=:total` passed all along), M10 (β→6.7, on cited authority),
Li2008 conflation, peak_wavenumber (κ_p/√2); M4, M5, M6, M7, M9, §4.8 Scalings, inaccessible-sources,
S_p→D_LL; Rogallo, ConstantPower/Lundgren, ObukhovCorrsin, Li2008/JHTDB, Grmela–Öttinger, Pope year-less,
"scaffolded"; `scalar_dissipation` φ→φ̂, `scaling_exponent` order, Kolmogorov1941 ζ_p, `Simulation(domain)`
positional, statistics-headline softened, tracer-scheme guidance, spectrum Function-vs-Type,
`stationary_dissipation` sig; M3 (PhaseShift enums + `dealias!` kernel), `k_max_η` ASCII note, de-alias
hyphenation, `2/3` math, `f_φ` glossary; IF-RK2 "unstable", `Δx≈η` qualifier, allocation-free step scoping,
`max_speed` representation.
