# Cold-reader hat — first-year turbulence grad student, new to the package

Findings from a top-to-bottom read of the rendered site, treating every term as unknown until the
document itself defines it. Ranked most-severe first.

---

## 1. "front door" used with zero gloss on the very first page it appears

**Type:** clarity **Severity:** major **Confidence:** high

**Locations:**
- PAGE: Home, Quick start: "Build a case at the front door, spin it up to statistical stationarity, and advance it:" — no explanation at all of what "front door" means.
- PAGE: api / Cache, `ObservablesCache`: "The `Simulation` front door — the build-everything convenience constructor — builds, wires, and seeds one for you." (first real gloss, many pages later)
- PAGE: api / Generator, `ResolvedGenerator`: "The `Simulation` front door — the build-everything convenience constructor — builds one for you." (a second, separate gloss)
- PAGE: api / SimulationRun, `Simulation`: "('front door' names exactly this convenience form throughout — the constructor that builds every component for you)" (the closest thing to a canonical definition)

**Description:** A first-time reader meets "front door" as an unglossed idiom in the first sentence of the Quick start, with no forward pointer. The term is then independently re-glossed three separate times on three different pages before the reader ever reaches the page that actually defines it canonically. A one-clause parenthetical on first use (Home) would fix this.

---

## 2. Core cache vocabulary ("iteration", "deposit", "stamp") used on the Home page before any of it is defined

**Type:** clarity **Severity:** major **Confidence:** high

**Locations:**
- PAGE: Home, Quick start: "`velocity_physical(sim)` # a cached observable at the iteration's end (the instant between steps)" — "iteration" used with no definition.
- PAGE: Home, Components: "`Cache`: the `ObservablesCache` — the stamped storage each iteration fills at its end with the observables of the state it just produced; the checked accessors ... serve the deposited value or throw" — "stamped", "iteration", "deposited" all used together, unglossed.
- PAGE: api / Cache, module docstring (first actual definition, many pages later): "An iteration is one advance of the run — one `step!` and the `deposit!` that closes it..."

**Description:** The Home page is the reader's very first exposure to the package, yet its Quick start and Components section lean on "iteration" / "deposit" / "stamp" as if already known. None of these is a common-English word doing double duty — each is later given a precise, load-bearing technical meaning (Cache page) that the reader cannot yet have. Cold-read fails here: parsing the Home page alone, a reader cannot tell an "iteration" apart from a "step" or know what "stamped" means.

---

## 3. "scratch arity" is used twice and never defined anywhere in the document

**Type:** clarity **Severity:** major **Confidence:** high

**Locations:**
- PAGE: api / Generator, module docstring: "recovered by the source-preserving `to_physical!` scratch arity of `GBGPeriodicFields`"
- PAGE: api / State, module docstring: "The physical representations are recovered from the state with the scratch (source-preserving) arity of `to_physical!`"

**Description:** "Scratch arity" is presented as a fixed term of art (used identically, verbatim, in two places) but is never explained anywhere on the site — not what "arity" refers to here (an overload with an extra output-buffer argument?), not why it matters beyond "source-preserving." A reader has to reverse-engineer the phrase from the surrounding sentence each time; it is never introduced with a plain-language gloss on first use.

---

## 4. "2N-storage" silently reuses the symbol N for a different quantity than the notation page's canonical N

**Type:** clarity **Severity:** major **Confidence:** medium

**Locations:**
- PAGE: notation, Numerics table: "$N$ | grid points per side | `grid_points_per_axis`"
- PAGE: api / Propagator, `IFLowStorageRK3`: "Three nonlinear evaluations per step, and — in Williamson's 2N-storage count — two field registers per field..."

**Description:** The notation page fixes $N$ as *grid points per axis* and calls the wavenumber/kinetic-energy clash ($\boldsymbol\kappa$/$\kappa$/$k$) out explicitly as a "kept distinct" set of glyphs — signaling the document cares about symbol collisions. But "2N-storage" (classical Williamson low-storage RK terminology, where N counts *evolved field registers*, not grid points) reuses the same letter for an unrelated quantity with no disambiguating note. A reader who just internalized $N$ = grid resolution from the notation page will misread "2N-storage" as "twice the grid points."

---

## 5. "instant between steps" (Home) vs. "instant between iterations" (elsewhere) — inconsistent phrasing for the same concept

**Type:** contradiction **Severity:** minor **Confidence:** medium

**Locations:**
- PAGE: Home, Quick start: "a cached observable at the iteration's end (**the instant between steps**)"
- PAGE: api / Cache, module docstring: "between iterations the run stands at one $t_n$ ... — **an instant of the run's clock**"
- PAGE: api / Propagator, `step!`: "the values of **the instant between iterations**, where the cache's deposits are current"

**Description:** Once "iteration" and "step" are established as distinct technical terms (an iteration = one `step!` + one `deposit!`), calling the cached instant "the instant between steps" on Home — while every later page consistently says "between iterations" — reads as a terminology slip on the axis of *step vs. iteration*, exactly the distinction the rest of the document is careful to preserve.

---

## 6. $y_{\mathrm s}$ (the imaginary-axis stability limit) is used and defined inline but missing from the "single reference" notation page

**Type:** organization **Severity:** minor **Confidence:** medium

**Locations:**
- PAGE: notation: "This page is the single reference — a docstring introduces a symbol on first use and need not repeat the convention." Numerics table lists $N, L, \Delta t, C, \kappa_{\max}, A_i/B_i/d_i, T$ — no $y_{\mathrm s}$.
- PAGE: api / Propagator, `recommended_cfl`: "stability needs this times $C$ to stay within the scheme's imaginary-axis stability limit $y_{\mathrm{s}}$ ... for `IFLowStorageRK3` $y_{\mathrm{s}} = \sqrt{3}$ ... `IFRK2` is imaginary-axis unstable ($y_{\mathrm{s}} = 0$...)"

**Description:** The notation page explicitly bills itself as the single reference for every symbol used throughout the docstrings, yet a load-bearing symbol used twice in one docstring ($y_{\mathrm s}$) never makes it into that glossary. Minor because it is re-explained locally, but it breaks the "single reference" promise.

---

## 7. `StationarityCriterion`'s documented "Fields" list accounts for only 6 of the 7 keyword-constructor parameters

**Type:** clarity **Severity:** minor **Confidence:** medium

**Locations:**
- PAGE: api / SimulationRun, `StationarityCriterion`: keyword constructor takes `gate_scalar, gate_skewness, min_turnovers, window_turnovers, tol, skew_floor, max_turnovers` (7 keywords).
- Same page, Fields: "The plain constructor `StationarityCriterion(monitor, max_turnovers, gate_scalar, elapsed_turn, last_time, started)` is internal" — lists only `monitor, max_turnovers, gate_scalar, elapsed_turn, last_time, started` (6 fields), with `gate_skewness, min_turnovers, window_turnovers, tol, skew_floor` unaccounted for except by the vague gloss "`monitor` — the sampled signals and gates."

**Description:** A cold reader trying to map the 7 documented keywords onto the type's actual storage cannot: 5 of them seemingly vanish into an opaque `monitor` field whose own structure is never described. Whether they are truly inside `monitor` or dropped is not stated.

---

## 8. `PointSet` / `VectorPointValues` / `ScalarPointValues` used with no on-site definition of their shape or purpose

**Type:** clarity **Severity:** minor **Confidence:** low

**Locations:**
- PAGE: api / Particles, `Tracers` Fields: "`position_points`, `predictor_points` — `PointSet`s wrapping `positions` / `predictor` for interpolation."
- PAGE: api / Particles, `sample!`: "into the point-value buffer `out` (a `VectorPointValues` for the velocity, a `ScalarPointValues` for the scalar $\varphi$)"

**Description:** These three type names are used as if already familiar; nothing on the site says what a `PointSet` or a `*PointValues` object actually is (an array wrapper? a struct with fields?) beyond "wraps positions" / "the point-value buffer." Likely a backend (`GBGPeriodicFields`) cross-link exists in the live HTML that this text extraction can't show — flagged at low confidence for that reason — but as written, a cold reader has no way to know these types' shape.

---

## 9. "observation" is overloaded between "the act of observing" and "the callback object itself"

**Type:** clarity **Severity:** minor **Confidence:** medium

**Locations:**
- PAGE: api / SimulationRun, module docstring: "advance one iteration; observe and advance until the callback stops the run (**the callback is the observation**, and its return decides continuation)"
- PAGE: api / SimulationRun, `StationarityCriterion`: "**The packaged spin-up observation** for `run!`: a callback that watches the run settle..."

**Description:** "Observation" first reads naturally as the *act* (observing the run each iteration), but is then used as a noun standing in for the callback *object* itself ("the callback is the observation," "the packaged ... observation"). A cold reader has to hold both readings simultaneously without either being flagged as the intended usage.

---

## 10. "reified" / "reification" used repeatedly with no plain-language gloss

**Type:** clarity **Severity:** nit **Confidence:** medium

**Locations:**
- PAGE: Home, Components: "reified as the `ResolvedGenerator` a scheme consumes through the generator protocol"
- PAGE: api / Generator, `ResolvedGenerator`: "The reified right-hand side of the resolved dynamics — the flow's generator as one object"

**Description:** "Reified" is a CS term of art (turning an abstract concept into a concrete object) that a physics-first audience (per the project's own stated documentation policy — "the user is a physicist... not a software engineer fluent in startup idiom") may not know. It is used several times with no gloss beyond the surrounding sentence's own paraphrase, which does help, but the word itself is never explained.

---

## 11. "armed" (forcing rate) used metaphorically with no explicit definition of the mechanism

**Type:** clarity **Severity:** nit **Confidence:** low

**Locations:**
- PAGE: api / Generator, `ResolvedGenerator` Fields: "a non-`nothing` rate is **the armed offset** the factor verbs return"
- PAGE: api / Generator, `prepare!`: "**arm** the per-mode linear forcing rates"

**Description:** "Arm"/"armed" is used as if self-explanatory; the reader can infer it means "populated by `set_forcing_rate!` and therefore non-`nothing`," but this is never stated plainly — only implied across two separate docstrings.

---

## 12. Notation-page symbol $T$ (element type) is never used in any formula elsewhere in the document

**Type:** organization **Severity:** nit **Confidence:** low

**Locations:**
- PAGE: notation, Numerics table: "$T$ | the real element type (Float32 / Float64) | `element_type`"

**Description:** Every other notation-table entry recurs in at least one formula or docstring elsewhere on the site; $T$ does not appear again anywhere (element type is always referred to in prose as "`Float32`/`Float64`" or "the real element type," never by the glyph $T$). A minor glossary/usage mismatch — not misleading, just dead weight for a reader cross-referencing the table against the docstrings.

---

## 13. "wavenumber-magnitude shell" used pervasively without ever plainly stating what a shell is

**Type:** clarity **Severity:** minor **Confidence:** low

**Locations:**
- PAGE: notation, Diagnostics: "$E(\kappa)$ | the energy spectrum, in two readings related by the shell width $\Delta\kappa = 2\pi/L$: as measured, **the energy in each wavenumber-magnitude shell**"
- PAGE: api / Observables, `energy_spectrum`: "the turbulent kinetic energy resolved over wavenumber-magnitude shells"

**Description:** The shell *width* is given ($\Delta\kappa = 2\pi/L$), but "shell" itself — the set of Fourier modes whose $|\boldsymbol\kappa|$ falls in one such width-$\Delta\kappa$ bin — is never spelled out plainly. A reader who does not already know pseudospectral radial-binning conventions has to infer the concept purely from the word "shell" plus the width formula.

---

## 14. "CFL" acronym never expanded on first use

**Type:** clarity **Severity:** nit **Confidence:** low

**Locations:**
- PAGE: Home, Components: "the advective-CFL `max_speed`"
- PAGE: api / Propagator, `recommended_cfl`: used throughout as "advective-CFL ceiling"

**Description:** "CFL" (Courant–Friedrichs–Lewy) is used dozens of times across the site as an established acronym but is never expanded or cited anywhere. Likely known to the target audience (a numerical-methods-literate turbulence physicist), hence nit-level, but strictly a term used before (in fact, without ever) being defined.

---

## 15. "Dirichlet ($H^1$) energy" used twice with only the formula, no gloss of the Sobolev-norm terminology

**Type:** clarity **Severity:** nit **Confidence:** low

**Locations:**
- PAGE: api / Observables, `dissipation`: "the enstrophy of a divergence-free velocity is its Dirichlet ($H^{1}$) energy, $\langle\lvert\boldsymbol{\omega}\rvert^{2}\rangle = \langle\hat{\boldsymbol{u}},\lvert\boldsymbol{\kappa}\rvert^{2}\hat{\boldsymbol{u}}\rangle$."
- PAGE: api / Observables, `scalar_dissipation`: "The gradient energy ... is the Dirichlet ($H^{1}$) energy $\langle\varphi,\lvert\boldsymbol{\kappa}\rvert^{2}\varphi\rangle$"

**Description:** "Dirichlet energy" / "$H^1$" is functional-analysis terminology that a first-year turbulence student may not have met; the formula that follows does make the *quantity* clear, but the name itself is asserted rather than glossed even briefly (e.g., "the mean-square-gradient norm").
