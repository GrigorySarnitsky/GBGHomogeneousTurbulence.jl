# Closure — hat 01-consistency-matrix

## Finding 1 — Decision-log entries cited by number but log shows no visible numbering
**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md` §11 is a genuine markdown ordered list — 56 entries matching
`^[0-9]+\. \*\*(2026` (verified by grep count: 56). It renders in `docs/build/architecture/index.html`
as a real `<ol><li>…</li></ol>` (confirmed by reading the built HTML around
`id="11.-Decision-log"`), and no site CSS under `docs/build/assets/*.css` sets `list-style:none` on
it, so the browser's default decimal numbering (1., 2., …, 56.) is visible. Spot-checked that the
numeral lines up with citations: entry 20 in the source (`awk` count) is "Resolution-based
`viscosity`…", matching `docs/ARCHITECTURE.md:453`'s "(decision 20)" citation, which names exactly
that resolution-based viscosity criterion. The log is not bulleted; the finding's premise no longer
holds against the current source.

---

## Finding 2 — Home and api-overview order the same nine modules two different ways
**VERDICT: PRESENT**

Evidence: `docs/src/index.md` "## Components" (lines 90-119) still lists
`SimulationDomain, State, Observables, Cache, Forcing, Generator, Propagator, Particles,
SimulationRun, Phenomenology` — `SimulationRun` 9th of 10. `docs/src/api.md` (lines 7-21) still
states "The pages below are ordered for reading, not by that dependency: `SimulationRun` comes
first because a run is what a user builds first" and its bullet list opens
`GBGIsotropicTurbulence, SimulationRun, SimulationDomain, State, …`. Neither page cross-references
the other's ordering choice. Unchanged from the finding's description.

---

## Finding 3 — `FixedDomain(...)` examples inconsistently include the keyword-only `;`
**VERDICT: PRESENT**

Evidence: `docs/src/observables_cache.md:404` still reads
`domain = FixedDomain(grid_points_per_axis = 64, side_length = 2π, dealiasing = TwoThirds(), …)`
— no leading `;`. `src/SimulationDomain.jl:169,172` still use
`FixedDomain(; grid_points_per_axis = 128, …)` — with `;`, matching the declared signature
(`src/SimulationDomain.jl:218`, `function FixedDomain(; grid_points_per_axis::Integer, …)`).
`src/SimulationRun.jl:202` ("Domain-first" example) still has
`FixedDomain(grid_points_per_axis = 128, side_length = 2π, dealiasing = HouLi(), …)` — no `;`.
The inconsistency the finding flagged is unchanged; the class is additionally alive at
`src/Forcing.jl:122` (`domain = FixedDomain(grid_points_per_axis = 64)`, no `;`), not named in the
original finding.

**surviving_class:** `src/Forcing.jl:122` — another `FixedDomain(...)` construction example
omitting the leading `;`, not among the finding's originally cited locations.
