# Closure audit — hat: 01-consistency-matrix

One verdict per banked finding, established from the current corpus alone.

---

## Finding 1 — Two decision-log entries disagree about what "decision 46's pattern" is

**VERDICT: ABSENT**

**Evidence:** `docs/ARCHITECTURE.md`/`docs/src/architecture.md` decision 47 (line 1632) now reads:
"is `Cache.vorticity_physical` — an f/`f!` **pair**, not decision 46's single dispatched generic,
and the difference is structural rather than a drift: `max_speed` is a pure reduction... while a
recovery *writes a field* and a checked read *returns one*, which no single name can carry.
Decision 46's one-generic rule therefore governs reductions; a field-valued observable takes the
pair." Decision 47 no longer claims its f/f! naming *derives from* decision 46 — it explicitly
disclaims that and gives its own structural rationale, exactly the resolution hint's first option.
§4.3 (lines 314-319) still cites decision 46 for `max_speed` and decision 47 for
`vorticity_physical!`/`vorticity_physical`, consistently. Searched all of `docs/ARCHITECTURE.md`
and `docs/src/*.md` for "decision 46" / "decision 47" / "pattern implies" — only the one
self-consistent story remains.

---

## Finding 2 — `tracer_scheme`'s stated default drops the parens every sibling default keeps

**VERDICT: NOT-A-DEFECT**

**Evidence:** `tracer_scheme` no longer exists (renamed to `interpolation_scheme` directly,
`src/SimulationRun.jl:162`). `src/Particles.jl:58-60` now states explicitly: "`CatmullRom`... — a
ready-made **value rather than a type**, so it is passed bare —" and in
`inspiration`-independent ground truth, `GBGPeriodicFields`'s `Interpolation.jl:314` confirms
`const CatmullRom = LalescuSpline(1, 1)`, i.e. `CatmullRom` is a singleton instance, not a type.
Every default site (`src/SimulationRun.jl:162`, `src/Particles.jl:100`) now consistently writes it
bare, while genuine type-valued defaults (`dealiasing = TwoThirds()`, `scheme = IFLowStorageRK3()`,
`trajectory_scheme = EndpointHeun()`) keep the parens. The original finding's premise — that
`CatmullRom` needed instantiation like its siblings — was factually wrong; the corpus now states
why and is internally consistent.

---

## Finding 3 — Three descriptions of what makes `particle_velocities` readable name three different actors

**VERDICT: REGRESSED**

**Evidence:** The three docstrings were rewritten to give one definitive story, but that story is
now factually **false** against the code. `src/Particles.jl:227-229` claims of
`record_trajectory_velocity!`: "**This call is that slot's only producer**: it sets both of the
epochs the slot is checked against — the fields epoch and the particles epoch." But
`record_trajectory_velocity!(tracers::Tracers, u)` (`src/Particles.jl:241-244`) takes no `cache`
argument and only calls `interpolate!`; it cannot touch `cache.sample_fields_epoch` /
`cache.sample_particles_epoch`. Those are set exclusively by `deposit_sample!` (`src/Cache.jl:257-259`),
called as a **separate** statement immediately after `record_trajectory_velocity!` at every one of
its three call sites (`src/SimulationRun.jl:277-278`, `303-304`, `394-395`). `src/Cache.jl:314-317`
(`particles_modified!`) compounds this: it instructs a hand-run loop to call `particles_modified!`
then `record_trajectory_velocity!` "before advancing" — omitting `deposit_sample!` entirely — a
recipe that, followed literally, leaves `sample_fields_epoch`/`sample_particles_epoch` stale and
`particle_velocities(cache)` throwing (`src/Cache.jl:229-234`).

**Surviving class:** the conflation of "writes the array" with "advances the epoch" recurs at two
sites: `src/Particles.jl:227-229` (`record_trajectory_velocity!`'s own docstring) and
`src/Cache.jl:314-317` (`particles_modified!`'s docstring, whose stated hand-run recipe is
incomplete/broken without `deposit_sample!`). `src/Propagator.jl:479-482` (`deposit!`) is the one
passage that stays accurate — it says the slot "is filled by `record_trajectory_velocity!`" without
claiming it sets epochs.

---

## Finding 4 — "the developed-turbulence markers" (plural) names only one built marker

**VERDICT: ABSENT**

**Evidence:** `docs/src/index.md:97` and `docs/src/api.md:12` both now read "the
developed-turbulence marker" (singular), matching `src/Observables.jl:15`'s single built
observable, `derivative_skewness` ("the classical marker of a developed..."). Grepped
`docs/src/*.md`, `docs/ARCHITECTURE.md`, and `src/*.jl` for "developed-turbulence marker(s)" and
"marker" near `Observables` — no remaining plural instance and no second built marker in
`Observables.jl`'s export list (`kinetic_energy, dissipation, scalar_variance,
scalar_dissipation, derivative_skewness, max_speed, vorticity_physical`).

