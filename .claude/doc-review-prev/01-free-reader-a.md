# Free Reader A — fresh-eyed, no-checklist pass over the full rendered manuscript

Hat: free-reader-a. Read front to back (Home, api overview, architecture, decisions, notation,
observables_cache, phenomenology overview + Scalings/Spectra/StructureFunctions, and every api/*
module page) with no assigned lens. Findings below are only what actually stopped me on the read,
each with the decisive quote from both sides where it's a contradiction.

---

## Finding 1 — the scalar is called `θ` on the Architecture page, against the package's own hard rule

**Type:** contradiction
**Severity:** blocker
**Confidence:** high

**Locations:**
- PAGE: architecture, §2 "Running a simulation": *"When the scalar is forced, $\langle\theta^2\rangle$ must settle too"*
- PAGE: architecture, §9 "Invariants": *"The scalar is denoted $\varphi$, never $\theta$ — in code, mathematics, and prose."*
- PAGE: notation, "Physical variables" table: *"$\varphi$ | the passive scalar (never $\theta$) | the scalar state"*
- PAGE: decisions (2026-07, `warmup!` entry): *"When the scalar is forced, $\langle\varphi^2\rangle$ must flatten too"* — the same claim, correctly in $\varphi$.

**Contradicts:** itself. §2's own worked description of `StationarityCriterion`'s scalar gate uses $\theta$, in direct violation of §9's own invariant two sections later and of `notation.md`'s explicit "never $\theta$" rule — and the identical claim is stated correctly with $\varphi$ elsewhere in the very same document (the decision log entry for the same feature).

**Description:** This is exactly the class of error the package's naming discipline exists to prevent, and it appears on the architecture page itself, describing the same gate ($\langle\varphi^2\rangle$ flattening) that the decision log states correctly one page later in the same manuscript. A reader who only saw §2 would come away thinking the codebase uses $\theta$.

---

## Finding 2 — Rogallo's dealiasing paper is dated 1981 everywhere except one docstring, which dates it 1984

**Type:** citation
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: api / SimulationDomain, `PhaseShift`: *"combined with the spherical truncation of Rogallo (1984) — Numerical experiments in homogeneous turbulence, NASA TM-81315 (no DOI)"*
- PAGE: architecture, §References: *"Rogallo, R. S. (1981). Numerical experiments in homogeneous turbulence. NASA TM-81315. ... the spherical-truncation dealiasing of the `PhaseShift` strategy, decision 27."*
- PAGE: architecture, decision log, decision 27: *"Patterson & Orszag 1971, Rogallo 1981"*

**Contradicts:** the References entry and the decision log both date the identical work (same title, same NASA TM number, same role — spherical-truncation dealiasing for `PhaseShift`) to 1981; the `PhaseShift` type docstring dates it 1984.

**Description:** Same paper, same purpose, cited with two different years across the document. Rogallo's NASA TM-81315 "Numerical experiments in homogeneous turbulence" is the 1981 report; the docstring's "1984" looks like a simple slip, but it is a citation-correctness defect the package's own doc-review discipline is built to catch.

---

## Finding 3 — decision-log parenthetical gives the developed-cascade skewness as "≈ −0.05" instead of "≈ −0.5" in the same sentence that states 0.5

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: decisions (2026-07, `warmup!` entry): *"...against the $\lvert S\rvert \approx 0.5$ of a developed cascade ($S$ runs from $0$ toward $\approx -0.05$)."*
- PAGE: api / SimulationRun, `StationarityCriterion`: *"a random-phase field starts at $S \approx 0$ and only a developed cascade reaches $S \approx -0.5$."*
- PAGE: api / Observables, `derivative_skewness`: *"fully developed isotropic turbulence has $S \approx -0.5$"*

**Contradicts:** the decision-log sentence states $|S|\approx 0.5$ and then, in the very same parenthetical, gives the value $S$ tends toward as $\approx -0.05$ — a factor of ten off, and inconsistent with the $\approx -0.5$ given twice elsewhere for the identical physical quantity.

**Description:** A one-character/decimal-point slip, but it sits inside the sentence that is explaining the "real turbulence yet" gate's floor value, so a reader checking the arithmetic (skew_floor = 0.1 is "a fifth of" the developed value) would be confused by the wrong number appearing right next to the correct one.

---

## Finding 4 — `add_forcing_source!` docstring still charges `VarianceController` three per-stage host readbacks, after the decision log records them fused to one

**Type:** contradiction
**Severity:** major
**Confidence:** medium

**Locations:**
- PAGE: api / Forcing, `add_forcing_source!`: *"Each reduction costs one blocking device-to-host transfer, at every stage — three per stage for `VarianceController`, one for `ConstantPower`, where `Linear` pays none."*
- PAGE: architecture, decision log (multi-weight fused reduction, 2026-08-23): *"wired at every same-field multi-reduction site: `VarianceController` (three weights per stage — the unit, the band, $\lvert\boldsymbol{\kappa}\rvert^{2}$)... The synchronization ledger re-froze: the default row fell 10 → 4 crossings (one fused reduction per stage plus the $\Delta t$ choice)"*

**Contradicts:** the decision log states the default configuration's synchronization count fell from 10 to 4 crossings specifically *because* `VarianceController`'s three weighted sums per stage are now answered by one fused reduction (one host readback), i.e. one per stage, not three. The Forcing docstring's per-stage readback count was apparently never updated after that fusion landed.

**Description:** This is a documentation-staleness defect rather than a physics error: two places in the same manuscript give different, mutually exclusive answers to "how many blocking transfers does `VarianceController` cost per stage," and the more recent, more specific source (the synchronization-ledger re-freeze) says the older number is wrong.

---

## Finding 5 — the Home page's "build order" component list puts `Phenomenology` last; the API overview and Architecture both say it leads the include order

**Type:** contradiction
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: Home, "Components": *"Listed in build order — each module uses the ones above it."* — the list runs `SimulationDomain, Observables, State, Cache, Forcing, Generator, Propagator, Particles, SimulationRun`, then *last*: *"`Phenomenology`: the reference turbulence laws ..."*
- PAGE: api, overview: *"the extraction-bound `Phenomenology` leaf leads the include order but is not re-exported"*
- PAGE: architecture, §4.9: *"`Phenomenology` (§4.8) leads this order as the dependency-light leaf..."*

**Contradicts:** two other pages state plainly, as a fact about the actual module include order, that `Phenomenology` comes *first*; the Home page's list, explicitly captioned as build order, places it *last*.

**Description:** Because `Phenomenology` has no dependencies, its position doesn't violate the weaker "each module uses only the ones above it" reading, but the Home page is specifically claiming to show build/include order, and the concrete fact "where does `Phenomenology` sit in that order" is answered oppositely on two different pages. A reader who cross-checks will notice the mismatch even though neither claim is physically wrong in isolation.

---

## Notes on scope

I also checked, and found internally consistent (not reported): the transform-count table in `observables_cache` against the decision-log's post-fix numbers; the RKW3/Williamson stage coefficients against the literature; the CFL-ceiling arithmetic ($y_s/(\kappa_{\max}\Delta x)$) for both schemes; the vector-field byte-size arithmetic in `observables_cache` (384 MiB / 192 MiB at $256^3$); the `FlowConditions`/`FlowParameters` "shares two field names" claim; and the Yaglom 4/3-vs-2/3 coefficient conversion (already fixed per the adjudication record, and it checks out here). I looked closely at the frame's "322.5 MiB at $256^3$" figure (three field-scale arrays not obviously summing to that number under a naive per-array estimate) but did not have enough visibility into the underlying storage types to call it a defect with any confidence, so I left it out.
