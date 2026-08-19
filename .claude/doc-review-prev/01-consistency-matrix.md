# Consistency-matrix audit — hat: consistency-matrix

Fresh-eyed cross-page consistency sweep over the full rendered manuscript (Home, api overview,
architecture, notation, observables_cache, phenomenology + its four sub-pages, and every `api/*`
module page). Method: built an entity matrix (every recurring formula, constant, naming
convention, decision citation, default value, and docstring cross-reference) and diffed each
entry's every appearance. The document turns out to be extremely well cross-verified already —
most formulas, transform counts, CFL constants, and terminology sweeps that I independently
recomputed checked out exactly. The findings below are the divergences that survived that
process.

---

## Finding 1 — Two decision-log entries disagree about what "decision 46's pattern" is

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: architecture, §11 decision log, the entry beginning "(2026-08, user-directed) `Observables`
  precedes `Cache`": *"an observable with both a measurement and a cached value is **one generic**
  with two method families — the field-argument reduction computes ('measure now'), the
  `ObservablesCache` method serves the deposited value or throws — with the bare binding and the
  docstring homed in `Observables` and `Cache` extending it (`max_speed` today; **the pattern is
  the rule for any future cached observable**)."*
- PAGE: architecture, §11 decision log, the very next entry ("The chart recoveries are not package
  verbs; the vorticity recovery is an observable"): *"homed in `Observables` as the field-valued
  observable whose cached read is `Cache.vorticity_physical` (**the f/f! pair decision 46's pattern
  implies**; the `!` form is the home)."*

**Contradicts:** PAGE: architecture §4.3 itself cites two *different* decisions for the two
patterns — `max_speed` "(one generic shared with `Cache`... decision 46)" versus
`vorticity_physical!`/`vorticity_physical` "(decision 47)" — confirming decision 46 is the
single-generic-name pattern and decision 47 is the separate bang/no-bang naming used for vorticity.

**Description:** Decision 46 (the "Observables precedes Cache" entry) explicitly defines its
pattern as *one generic function name*, dispatched by argument type (field vs. cache) — the shape
`max_speed(u)` / `max_speed(cache)` actually has. The very next entry (decision 47, on the
vorticity recovery) instead mints *two different names* differing only by a trailing `!`
(`vorticity_physical!` vs. `vorticity_physical`) and claims this two-name f/f! convention is what
"decision 46's pattern implies." That is not the pattern decision 46 describes, and it is not the
pattern §4.3 itself credits to decision 46 elsewhere on the same page. A reader following "the
pattern is the rule for any future cached observable" (decision 46) and then modeling a new cached
observable on `vorticity_physical!`/`vorticity_physical` would be modeling it on a naming
convention the docs themselves misattribute.

**Resolution hint:** Either correct decision 47's parenthetical to cite the f/f! convention on its
own terms (it does not need decision 46's authority — `vorticity_physical!` mutates and returns
nothing while `max_speed(u)`/`max_speed(cache)` both return a value, so the two truly are different
shapes for a structural reason: unifying a mutating recovery with a checked cache read under one
name isn't the same move as dispatching a pure reduction by argument type), or reconcile the two
patterns explicitly if one is meant to supersede the other.

---

## Finding 2 — `tracer_scheme`'s stated default drops the parens every sibling default keeps

**Type:** format
**Severity:** minor
**Confidence:** high

**Locations:**
- PAGE: api / SimulationRun, `Simulation` docstring, Arguments: *"`number_of_particles = 0`,
  `tracer_scheme = CatmullRom` — ... forwarded to the `Tracers` constructor as its
  `interpolation_scheme`."*
- PAGE: api / Particles, `Tracers` docstring: *"`CatmullRom` is the ``C^1`` choice (**the default
  `tracer_scheme`** of the `Simulation` front door...)"* — again bare, no parens.

**Contradicts:** Every other type-valued keyword default on the same `Simulation` signature is
shown instantiated: *"`dealiasing = TwoThirds()`"*, *"`scheme = IFLowStorageRK3()`"*, *"`particle_scheme
= EndpointHeun()`"* — and the one place `CatmullRom` is actually *used* as a value in a code
example, it is instantiated too: *"`interpolation_scheme = CatmullRom()`"* (PAGE: api / Particles,
`Tracers` example).

**Description:** `interpolation_scheme` (and its `Simulation`-level alias `tracer_scheme`) needs an
instance of a `GBGPeriodicFields` interpolation scheme, not the bare type — exactly as every other
strategy-valued keyword on the same constructor does. The two places that state `tracer_scheme`'s
default write it as the bare type name `CatmullRom` rather than `CatmullRom()`, inconsistent with
the parenthesized form used for `dealiasing`, `scheme`, and `particle_scheme` right next to it, and
with the one working code example that actually constructs the value.

---

## Finding 3 — Three descriptions of what makes `particle_velocities` readable name three different actors

**Type:** clarity
**Severity:** minor
**Confidence:** low

**Locations:**
- PAGE: api / Particles, `record_particle_velocity!`: *"storing them here is therefore what makes
  `particle_velocities` readable."*
- PAGE: api / Cache, `particles_modified!`: *"the run layer announces its own tracer advance
  (`advect!` followed by `record_particle_velocity!`, both inside `advance!`), and **the closing
  deposit then re-records the sample at the new epoch**."*
- PAGE: api / Propagator, `deposit!`: *"it is re-recorded where the positions move — **by
  `advance!` after the tracer advance, and by the `deposit!(sim)` form**... which does it for you
  when the run carries tracers."*

**Contradicts:** Each passage credits a different call with making the particle-velocities slot
current — `record_particle_velocity!` itself, "the closing deposit," and `advance!`/`deposit!(sim)`
— without stating whether these are three names for the same event or three distinct writes to the
same epoch pair.

**Description:** Given the slot's epoch is checked against *two* counters
(`sample_fields_epoch`/`sample_particles_epoch`, per the `ObservablesCache` field list), a reader
piecing together the exact call sequence that makes `particle_velocities` current from these three
docstrings alone cannot tell whether `record_particle_velocity!` sets both epoch fields itself, or
whether a separate "closing deposit" step is required afterward as `particles_modified!`'s text
implies ("then re-records"). This is a plausible design-consistency gap rather than a demonstrated
bug — flagged at low confidence because the docs may simply be using "re-record"/"the closing
deposit" loosely to mean the same call already described.

**Resolution hint:** State once, in one home docstring, the exact call that sets both epoch fields,
and have the other two mentions `@ref`/point there instead of re-describing the mechanism from a
different angle each time.

---

## Finding 4 — "the developed-turbulence markers" (plural) names only one built marker

**Type:** clarity
**Severity:** nit
**Confidence:** low

**Locations:**
- PAGE: Home, Components: *"`Observables`: ... the energy and dissipation diagnostics of the flow
  and the scalar, **the developed-turbulence markers**, the spectrum-derived scales..."*
- PAGE: api (overview), the identical sentence repeated verbatim.

**Contradicts:** The `Observables` module's own docstring and API page enumerate exactly one
observable under this description — `derivative_skewness`, "the classical marker of a developed
cascade" (singular) — with no second built marker named anywhere in `Observables`.

**Description:** The plural "markers" in the two summary pages reads as naming a category with more
than one member, but only `derivative_skewness` currently fills it. Low severity/confidence because
this may just be loose collective-noun phrasing (or intentionally future-facing toward the
recorded-but-unbuilt `Scalings`-side markers), not a factual overstatement of the current API
surface — but it is the kind of phrasing the doc policy's "current & complete" check flags when a
summary names a class that resolves to a single instance.

---

## Notes on what checked out clean

For the record (so a future pass doesn't re-spend effort here): the momentum/scalar/tracer system
of equations is reproduced identically, symbol-for-symbol, on Home, `architecture` §4.2, and
`observables_cache.md` §2.1. The transform-count table in `observables_cache.md` §2.3 (18/9,
21/18, 36/18, 42/36 inverse/forward) is internally self-consistent with the per-evaluation
breakdown given in prose above it, and the PhaseShift "RK3 51→42, RK2 34→28" figures in the
decision log reduce to exactly the same table. The CFL constants (2π/3 ≈ 2.09, C_CFL ≲ 0.83 → 0.5)
recompute exactly from the stated formulas. The `Li2008`/`Sreenivasan1998` cross-check (G ≈ 0.81 vs.
quoted 0.9) recomputes exactly as stated, including the stated length-ratio caveat. The
`ω_consumed`/`u_consumed` "both sit fifth" argument-position claim is exactly true of both
signatures. The house-terminology sweeps ("tail"/"boundary" → "closing deposit"/instant naming;
"stamp" → "epoch"; `ForcingSpec` → `DeferredForcing`; `tracer_positions` → `particle_positions`;
`number_of_tracers` → `number_of_particles`) show no surviving live occurrence of the retired terms
outside the decision log's own historical record (which is expected to retain them per the
adjudication file). The include-order string is identical on Home, api overview, and architecture
§4.9. Every `api` page's declared section outline matches its actual `##` headings one-for-one.
