# Free-eyed reader panel — Hat B

No checklist; read the full consolidated manuscript (Home, api overview, ARCHITECTURE.md, the
decision log, notation.md, observables_cache design page, Phenomenology overview, and every
per-module API page) as a demanding physicist-programmer deciding whether to trust this package
with real research. Findings below are the ones that made me stop and re-read.

Extensive numeric cross-checking was done in passing (CFL constants, κ_max·η algebra, the ν∝f^-4/3
/ 31%-higher-Re_λ claim, the VarianceController dk/dt derivation, the transform-count tables, the
L11/ℓ0 integral-scale ratios, the Betchov constant) — all of it checked out exactly, which is a
genuinely good sign for the corpus's numerical discipline. The findings below are the residue that
did *not* check out, plus two low-confidence "smells."

---

## Finding 1 — Rogallo's report is dated both 1981 and 1984 for the identical work

- **Type:** citation
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: api / SimulationDomain, `PhaseShift` docstring: "combined with the spherical truncation
    of Rogallo (1984) — Numerical experiments in homogeneous turbulence, NASA TM-81315 (no DOI)"
  - PAGE: architecture, §References: "Rogallo, R. S. (1981). Numerical experiments in homogeneous
    turbulence. NASA TM-81315."
  - PAGE: architecture, decision log (2026-07, phase-shift entry): "Patterson & Orszag 1971,
    Rogallo 1981"
- **Contradicts:** same title, same NASA TM number, same no-DOI status — cited as 1981 in two
  places and 1984 in the third.
- **Description:** This is the same report (Rogallo's well-known NASA TM-81315, "Numerical
  experiments in homogeneous turbulence") cited with two different years for an identical
  title/TM-number pair. One of the three citations is wrong. The doc policy requires every
  citation to be verified, not asserted; this slipped through. (External check: the real report is
  dated 1981, so the `PhaseShift` docstring's "1984" is the outlier.)

## Finding 2 — The warm-up gate's own sentence states the developed-cascade skewness as both ≈−0.5 and ≈−0.05

- **Type:** contradiction
- **Severity:** blocker
- **Confidence:** high
- **Locations:** PAGE: architecture, decision log (2026-07, `warmup!` stationarity entry): "...
  against the $\lvert S\rvert \approx 0.5$ of a developed cascade ($S$ runs from $0$ toward
  $\approx -0.05$)."
- **Contradicts:** itself, within one sentence — $\lvert S\rvert \approx 0.5$ immediately followed
  by "$S$ runs ... toward $\approx -0.05$" (a factor of ten off). Every other mention of the
  developed-turbulence skewness in the manuscript (the `Observables` page, `derivative_skewness`'s
  own docstring, `StationarityCriterion`'s `skew_floor` argument doc: "a fifth of the
  $\lvert S\rvert \approx 0.5$ of a developed cascade") consistently uses ≈−0.5, and the
  `skew_floor` default of `0.1` is explicitly glossed as "a fifth of" 0.5 (= 0.1), which only makes
  arithmetic sense against −0.5, not −0.05.
- **Description:** A numeric typo (an extra zero) inside the passage that explains *why* the
  `skew_floor` default is what it is. A reader trying to understand the physical target value the
  gate is calibrated against gets a self-contradicting number in the same breath.

## Finding 3 — `VarianceController` silently breaks the "every forcing has two constructor forms" rule the module states

- **Type:** contradiction
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: architecture, §4.4: "Each forcing has an operator-taking constructor and an
    operator-free keyword form (`NoForcing`, taking no operators, has the one form)"
  - PAGE: api / Forcing, `DeferredForcing`: "The operator-free keyword constructors `Linear(;
    rate, ...)`, `ConstantPower(; injection_rate, ...)`, `VarianceRescaling(; target, over, ...)`
    each return a `DeferredForcing` ... with the same defaults, as their `domain`-taking forms
    documented on each strategy" — `VarianceController` is not in this list.
  - PAGE: api / Forcing, `VarianceController` docstring: only signature shown is
    `VarianceController(; target, gain = 1, turnover_time = nothing, lowest_shell = 1,
    highest_shell = 2)` — no `domain`-taking form anywhere, and it is never called a
    `DeferredForcing`.
- **Contradicts:** the architecture's blanket claim names exactly one exception (`NoForcing`,
  because it "takes no operators"); `VarianceController` is a second, unnamed exception — it has
  neither a `domain`-taking constructor nor a `DeferredForcing` capture, unlike its three banded
  siblings (`Linear`, `ConstantPower`, `VarianceRescaling`), all of which do.
- **Description:** As a knock-on, the general Forcing-module claim "a band reaching above the
  dealias cutoff is inert there ... so construction warns about it" cannot literally hold for
  `VarianceController`, since its constructor never receives a `domain` to check the cutoff
  against — the warning must (if it exists at all for this strategy) happen somewhere else the
  docs never mention. Either the general rule needs a second stated exception, or
  `VarianceController` is missing documentation of when/how its band-vs-cutoff check happens.

## Finding 4 (nit) — The notation glossary omits the derivative-skewness symbol $S$

- **Type:** organization
- **Severity:** nit
- **Confidence:** low
- **Locations:** PAGE: notation, "## Diagnostics" table lists $k$, $\varepsilon$, $E_\varphi(\kappa)$,
  $E(\kappa)$, $E(\kappa_n)$, $\langle\varphi^2\rangle$, $\varepsilon_\varphi$ — no row for the
  velocity-derivative skewness $S$, despite $S$ being a first-class, heavily-referenced quantity
  (the warm-up gate, `derivative_skewness`, an entire architecture §2/§10 discussion, and a
  dedicated decision-log entry).
- **Description:** notation.md bills itself as "the single reference" for every symbol in the
  docstrings and design docs; every other diagnostic of comparable weight has a row, and $S$ does
  not. The doc's own rule ("a docstring introduces a symbol on first use and need not repeat the
  convention") technically excuses this since `derivative_skewness`'s own docstring defines $S$,
  but the omission still stands out by contrast with the rest of the table.

## Finding 5 (nit) — Kolmogorov (1941) page ranges in the References list read slightly off from the standard citation

- **Type:** citation
- **Severity:** nit
- **Confidence:** low
- **Locations:** PAGE: api / phenomenology / StructureFunctions, "## References": "Kolmogorov
  (1941), Dokl. Akad. Nauk SSSR 30, 301–305 (the 2/3 law) and 32, 16–18 (the exact 4/5 law)"
- **Description:** My own recollection of the standard citation for the "local structure" 1941
  paper is Dokl. Akad. Nauk SSSR 30, 299–303 (not 301–305); the "dissipation of energy" 4/5-law
  paper at 32, 16–18 matches what I recall. I flag this at low confidence since I cannot verify the
  page range independently from the manuscript alone, and reprints/translations do carry varying
  pagination — worth a second check against the original source rather than treating as settled.
