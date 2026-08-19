# Consistency-matrix hat — findings

Fresh-eyed cross-page consistency audit of the rendered `GBGIsotropicTurbulence` documentation
(Home, api overview, `architecture`, `notation`, `observables_cache`, every `api/*` module page,
every `api/phenomenology/*` page). Method: built a matrix of recurring entities (physical
quantities and their formulas/normalizations, numerical constants, module/API cross-references,
docstring structure) and diffed each entity's every occurrence. The corpus is unusually
well-scrubbed — dozens of formulas, memory/transform-count tables, and cross-page numeric claims
were independently re-derived by hand during this pass and found to check out exactly (Parseval
factors, the `322.5 MiB` / `384 MiB` / `768 MiB` frame and register sizes, the `TwoThirds` /
`PhaseShift` transform-count table, the `κ_max·η = fπη/Δx` identity, the `ε = ν⟨|ω|²⟩ =
2ν⟨S_ijS_ij⟩` periodic/solenoidal identity, the IFLowStorageRK3 stage coefficients, the register
counts behind "IFRK2 is dearer by one register"). Those are not reported below since they
survived verification; only the residual, genuine divergences are.

---

## Finding 1 — Decision-log entries are cited by number ~50+ times, but no entry in the rendered log carries a visible number

**Type:** clarity
**Severity:** major
**Confidence:** medium (flagged explicitly as possibly a manuscript-extraction artifact — see below)

**Locations:**
- PAGE: api — "`Simulation(...)` — ... the highest Reynolds number consistent with the chosen resolution criterion `κ_max_η` (**decision 20**)"
- PAGE: architecture, §4.2 — "the class of the stage-ordering bug that motivated the reification (§11 **decisions 29, 31**)"
- PAGE: architecture, §11 (the decision log itself) — every one of the **56** bulleted entries opens with only `- (2026-06) …` / `- (2026-07) …` / `- (2026-08) …`; none is prefixed with a locatable number, yet later entries refer back to `decision 8`, `decision 12`, `decision 14`, `decision 16`, `decision 17`, `decision 21`, `decision 24`, `decisions 25`, `decision 26`, `decision 27`, `decision 28`, `decisions 30–31`, `decision 33`, `decision 34`, `decision 35`, `decision 36`, `decision 37`, `decision 40`, `decision 41`, `decision 46`, `decision 48`, `decision 52`, `decision 55`, etc.

**Description:** The prose (both in `ARCHITECTURE.md`'s own body and on the `api` page) treats "decision *N*" as a stable, locatable anchor — the corpus's primary internal cross-reference mechanism for design rationale — and cites it upward of fifty times. But the rendered decision log that is supposed to hold entry *N* shows no numbering at all: a reader trying to find "decision 20" or "decision 46" has no way to count to it reliably (the log is append-only prose, not a numbered list in the text given here). This is either a broken cross-reference on the built page, or — plausibly — an ordered-list (`<ol>`) that Documenter numbers visually but that the manuscript-extraction step flattened to bullets, stripping the numerals. Given the extraction-artifact caveat this panel operates under, this is reported at medium rather than high confidence, but it is worth a build-side check either way: does the actually-rendered HTML page show "1.", "2.", … beside each entry?

**Resolution hint:** Check the built `docs/` HTML for this page; if the numbers are genuinely absent, add them (or a manual `id`/anchor with the number in the bullet text) so "decision 26"-style citations resolve to something a reader can locate.

---

## Finding 2 — Home page and the api-overview page order the same nine modules two different ways, one of which contradicts the reading habit the other page sets up

**Type:** organization
**Severity:** minor
**Confidence:** low-medium

**Locations:**
- PAGE: Home, "## Components" — bullets in the order `SimulationDomain`, `State`, `Observables`, `Cache`, `Forcing`, `Generator`, `Propagator`, `Particles`, `SimulationRun`, `Phenomenology` (SimulationRun **second-to-last**).
- PAGE: api — "The pages below are ordered for reading, not by that dependency: **`SimulationRun` comes first** because a run is what a user builds first" — and its own bullet list opens `GBGIsotropicTurbulence`, **`SimulationRun`**, `SimulationDomain`, `State`, …

**Description:** Both pages describe the identical nine-module surface, but Home presents it in strict dependency-include order (matching §4.9's chain verbatim) while the api page explicitly promotes `SimulationRun` to the front "because a run is what a user builds first" — the exact same rationale that motivates Home's own Quick Start, which opens with `sim = Simulation(...)` as its very first line of code. Home's Components section then buries the thing its Quick Start used first at position 9 of 10. Neither page cross-references the other's ordering choice, so a reader moving from Home to the api index meets the same catalogue reshuffled with no stated reason tied back to Home.

**Contradicts:** Home's Components-section ordering (dependency order, `SimulationRun` 9th of 10) vs. api overview's explicit statement that reading order puts `SimulationRun` 1st, on grounds that apply equally to Home's own Quick Start.

---

## Finding 3 — `FixedDomain(...)` construction examples inconsistently include the keyword-only `;`

**Type:** format
**Severity:** nit
**Confidence:** low

**Locations:**
- PAGE: observables_cache, §3.1 — `domain = FixedDomain(grid_points_per_axis = 64, side_length = 2π, dealiasing = TwoThirds(), element_type = Float64, array_type = Array)` (no leading `;`).
- PAGE: api / SimulationDomain — `domain = FixedDomain(; grid_points_per_axis = 128, side_length = 2π, dealiasing = TwoThirds(), element_type = Float64, array_type = Array)` (leading `;`), and again in the "wide" example.
- PAGE: api / SimulationRun — `sim = Simulation(domain; viscosity = 1e-2)` and the `FixedDomain(grid_points_per_axis = 128, ...)` domain-first example (no leading `;` on the `FixedDomain` call itself).

**Description:** Functionally identical in Julia (a keyword-only constructor accepts keywords with or without the leading `;` at the call site), so this is not a code defect — but the corpus is otherwise extremely disciplined about matching the constructor's declared signature verbatim in every example (the signature itself is always written `FixedDomain(; grid_points_per_axis, …)` with the `;`). The observables_cache page is the one place that drops it, which is a small, easily-fixed drift given how carefully every other example mirrors the signature.

---

## Notes on what was checked and found consistent (no findings filed)

For the record, since this hat's job is exhaustive cross-referencing: the following recurring
entities were independently checked across every page they appear on and found in agreement —
`kinetic_energy` ($k=\tfrac12\langle|u|^2\rangle$, default `1.5`⇒`u'=1`), `dissipation`
($\varepsilon=\nu\langle|\omega|^2\rangle=2\nu\langle S_{ij}S_{ij}\rangle$), `scalar_dissipation`
(full-variance $2\varkappa\langle|\nabla\varphi|^2\rangle$ convention, consistent through the
Yaglom 4/3→2/3 conversion and Obukhov–Corrsin's $C_{OC}$), `derivative_skewness`'s
$C_S=\tfrac47\sqrt{15/2}$, the `TwoThirds`/`HouLi`/`PhaseShift` cutoff fractions and the
$\sqrt2/3\,N\cdot2\pi/L$ / $2\sqrt2/3\,\kappa_{Ny}$ equivalence, the memory-footprint numbers
(`384`/`768`/`322.5` MiB at $256^3$/`Float64`), the transform-count table in
`observables_cache` §2.3 against the compute-audit decision-log's post-fix numbers (`51→42`
c2r), the `G`↔$C_\varepsilon$ cross-check example, the epoch-vs-step-count worked example
(step 2 / epoch 4) repeated verbatim in two places, the `Li2008`/`stationary_dissipation`
formula $\varepsilon=(k/G)^{3/2}/L$, the `BandRescaling` `over` keyword's required-not-defaulted
status (matches its own decision-log correction), and the eight removed `Simulation`-forwarder
count. No drift found in any of these.
