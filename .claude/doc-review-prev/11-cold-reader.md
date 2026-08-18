# Hat: First-year turbulence grad student (cold reader)

Read top-to-bottom in manuscript page order: Home → api → notation → phenomenology →
api/Cache → api/Forcing → api/GBGIsotropicTurbulence(index) → api/Generator →
api/Observables → api/Particles → api/Propagator → api/SimulationDomain →
api/SimulationRun → api/State → api/phenomenology/{Phenomenology,Scalings,Spectra,StructureFunctions}.
Findings are ordered most-severe first; each names the page where I *first* met the term.

---

## Finding 1 — "deposit" is jargon used inside its own would-be definition

**Type:** clarity **Severity:** major **Confidence:** high

**Locations:**
- Home, Quick start (code comment): *"One ITERATION is one advance: a step, then the deposit that closes it."*
- Home, Quick start (code comment): *"the cache holds what the last deposit left"*
- (True definition, four pages later) api/Cache, "The observables cache": *"`deposit!` — homed in `Propagator`... which fills every slot at the iteration's end and sets its epoch"*

**Description:** The very first thing the manuscript tells me about the run loop is what an "iteration" is — and it defines that word using another undefined word, "the deposit." I have no idea yet what gets deposited, where, or why the word "deposit" (with its financial connotation) was chosen over "write" or "record." I don't find out until page 5 (api/Cache). Sharpening 2 applies exactly here: the definition site (Cache) does not rescue the four pages of bare use that precede it.

---

## Finding 2 — No glossary exists for the package's own operational vocabulary

**Type:** organization **Severity:** major **Confidence:** high

**Locations:**
- notation page, entire "## Conventions" through "## Forcing" tables (math symbols only)
- Contrast: epoch, deposit, slot, iteration, register are each defined exactly once, in passing, wherever the relevant API page happens to introduce them (Cache, Propagator)

**Description:** The Notation page bills itself as *"the single reference — a docstring introduces a symbol on first use and need not repeat the convention."* It delivers on that promise for math symbols (i, κ, k, ε, …) but has zero entries for the package's operational nouns — epoch, deposit, slot, iteration, register, front door — even though these are used just as load-bearingly and just as repeatedly as the math symbols. A cold reader has no single page to consult for "what is a slot" the way they can consult Notation for "what is κ."

---

## Finding 3 — `FlowConditions` and `FlowParameters`: near-identical names, overlapping fields, different jobs

**Type:** clarity **Severity:** major **Confidence:** medium

**Locations:**
- api/Generator, "Flow conditions": `FlowConditions(; viscosity, schmidt, velocity_forcing, scalar_forcing)` — *"The physical conditions the generator is built from"*
- api/phenomenology/Phenomenology, "The flow-state bundle" (met many pages later): `FlowParameters(; viscosity, dissipation, rms_velocity, integral_scale, schmidt = 1.0, scalar_dissipation = NaN)` — *"the analogue of `FlowConditions` and `FixedDomain` on the phenomenology side"*

**Description:** By the time I meet `FlowConditions` (Generator page) I have no warning that a second, differently-scoped bundle called `FlowParameters` exists later, sharing two of its four-to-six field names (`viscosity`, `schmidt`) and an almost-identical descriptive phrase ("physical conditions" vs "flow-state bundle"). Only the later type's docstring acknowledges the relationship — the earlier one gives no forward pointer, so on first meeting `FlowConditions` I have every reason to assume it is the one and only "conditions" object in the package.

---

## Finding 4 — "register" is used in two unrelated senses before the package sense is ever defined

**Type:** clarity **Severity:** minor **Confidence:** medium

**Locations:**
- api/Observables, "Timestep control" (`max_speed`), first use: *"The magnitude is formed per grid point in registers and consumed by the maximum immediately"* (ordinary CPU/GPU hardware registers)
- api/Propagator, "Step scratch" (`IntegratorBuffers`), two pages later: *"Each such array is a register: storage a scheme computes one stage into and overwrites at the next"* (a specific package concept)

**Description:** "Registers" first appears as an offhand remark about how a reduction is computed on hardware. Two pages later the identical word is promoted to a formal package term — a named, reusable per-stage scratch slot, deliberately contrasted with the cache's slots. Nothing flags that the second use is a distinct, technical redefinition of a word I already filed away as "just CPU/GPU internals, not my concern."

---

## Finding 5 — "CFL" used unexpanded at its very first two appearances

**Type:** clarity **Severity:** minor **Confidence:** medium

**Locations:**
- Home, Components: *"the CFL-adaptive loop (`advance!` / `run!` / `warmup!`)"*
- api overview, Components (repeated verbatim)
- (expansion, three pages later) notation, Numerics table: *"$C_{\mathrm{CFL}}$ | advective-CFL (Courant–Friedrichs–Lewy) ceiling"*

**Description:** "CFL" is dropped bare on page 1 and again on page 2 before the Notation page spells out Courant–Friedrichs–Lewy on page 3. A minor point (the acronym is common in the field) but a genuine ordering gap by the doc's own stated self-containedness standard.

---

## Finding 6 — "the developed-turbulence markers" (plural) but only one marker is ever documented

**Type:** clarity **Severity:** minor **Confidence:** medium

**Locations:**
- Home, Components / api overview (identical wording both places): *"Observables: ... the developed-turbulence markers, the spectrum-derived scales, ..."*
- api/Observables module docstring and its own section: *"`derivative_skewness` — the velocity-derivative skewness, the **classical marker** of a developed cascade"* (singular; the only entry of this kind in the module's bullet list)

**Description:** The Components lists (met on page 1 and page 2) promise plural "markers," priming me to expect more than one diagnostic of this kind. When I reach the Observables page itself, exactly one such quantity exists, and its own section calls it "the marker" (singular). Either the plural is stale or a second marker is missing from the module's own summary.

---

## Finding 7 — "Berendsen-thermostat limit" borrowed from molecular dynamics, never explained mechanically

**Type:** clarity **Severity:** minor **Confidence:** medium

**Locations:**
- api/Forcing, `BandRescaling` note: *"Holding an amplitude fixed by deterministic rescaling is the Berendsen-thermostat limit of stochastic velocity rescaling"* (citing Bussi, Donadio & Parrinello 2007, *J. Chem. Phys.*)

**Description:** As a turbulence student I have no particular reason to already know what a Berendsen thermostat is (it's an MD concept for holding kinetic temperature fixed). The sentence explains the *consequence* (no conserved quantity, fluctuations suppressed) but never actually states what a Berendsen thermostat mechanically does, so the name itself functions as an unexplained label rather than an aid to understanding.

---

## Finding 8 — "EDQNM, DIA, LRA" acronyms never expanded anywhere on the site

**Type:** clarity **Severity:** minor **Confidence:** low-medium

**Locations:**
- api/phenomenology/Spectra, `ExponentialDissipation`: *"the form the triadic spectral closures (EDQNM, DIA, LRA) consistently predict (Kaneda 1993; Sagaut & Cambon 2018)"*

**Description:** Eddy-Damped Quasi-Normal Markovian, Direct-Interaction Approximation, and Lagrangian Renormalized Approximation are considerably less universally known than CFL or DNS to a first-year reader; they appear exactly once, unexpanded, with no gloss beyond a citation.

---

## Finding 9 — "arm"/"armed" used before its own gloss, on the same page

**Type:** clarity **Severity:** nit **Confidence:** low-medium

**Locations:**
- api/Generator module docstring (top of page): *"`prepare!` — open a step: advance the forcings' internal state and **arm the linear rates**."*
- api/Generator, `prepare!` docstring (further down the same page): *"arm the per-mode linear forcing rates **(fill them**, so the factor verbs return them instead of `nothing`)"*

**Description:** Reading top-to-bottom, I meet "arm the linear rates" in the module's summary bullet list first, with no gloss; only when I reach the `prepare!` docstring itself, further down the same page, does a parenthetical equate "arm" with "fill." A small in-page ordering gap, but the module summary is exactly the place a skimming reader stops.

---

## Finding 10 — `PointSet` / `VectorPointValues` / `ScalarPointValues` named but never characterized

**Type:** clarity **Severity:** nit **Confidence:** low

**Locations:**
- api/Particles, `Tracers` Fields: *"`position_points` — a `PointSet` wrapping `positions`: the form the interpolation reads them in."*
- api/Particles, `interpolate_at_particles!`: *"into the point-value buffer `out` (a `VectorPointValues` for the velocity, a `ScalarPointValues` for the scalar φ)"*

**Description:** These three types (presumably from the sibling `GBGPeriodicFields` package) are named several times but never described beyond their bare role as "the form the interpolation reads them in" — I cannot tell from the site alone what a `PointSet` actually contains or why it differs from the plain `(M, 3)` array `positions` it wraps.

---

## Finding 11 — "resolved" used for two different concepts

**Type:** clarity **Severity:** nit **Confidence:** low

**Locations:**
- api overview, SimulationDomain bullet: *"the **resolved-wavenumber ceiling** `max_wavenumber`"* (met first — "resolved" = the wavenumbers actually retained by dealiasing)
- api/Generator: *"`ResolvedGenerator` — the generator as one value"* (a type-name prefix meaning "gathered into one concrete value")

**Description:** The word "resolved" is introduced first (api overview) with a specific numerical-methods meaning tied to the dealiasing cutoff. It then reappears, unremarked, as a type-naming convention (`ResolvedFields`, `ResolvedGenerator`) with a different sense — "materialized as one object" rather than "kept below the dealiasing cutoff." The two uses are never distinguished or cross-referenced.
