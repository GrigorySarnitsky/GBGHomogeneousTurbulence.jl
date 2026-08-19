# Closure audit — hat: consistency-matrix

## Finding 1 — Two decision-log entries disagree about what "decision 46's pattern" is
**VERDICT: ABSENT**

**Evidence:** `docs/ARCHITECTURE.md:1637` (decision 47) now reads: "homed in `Observables` as the
field-valued observable whose cached read is `Cache.vorticity_physical` — an f/`f!` **pair**, not
decision 46's single dispatched generic, and the difference is structural rather than a drift:
`max_speed` is a pure reduction, so one name can dispatch on whether it is handed a field or the
cache, while a recovery *writes a field* and a checked read *returns one*, which no single name can
carry. Decision 46's one-generic rule therefore governs reductions; a field-valued observable takes
the pair, with the `!` form the home." This is exactly the resolution the finding proposed
(distinguish the f/f! shape from decision 46 on its own structural terms). `rg "decision 46's
pattern"` returns no hits anywhere in the corpus — the misattribution is gone. §4.3 still correctly
attributes `max_speed` to decision 46 and `vorticity_physical!` to decision 47, and the two are no
longer in tension.

---

## Finding 2 — `tracer_scheme`'s stated default drops the parens every sibling default keeps
**VERDICT: ABSENT**

**Evidence:** `tracer_scheme` no longer exists anywhere (`rg "tracer_scheme"` — zero hits); the
`Simulation` keyword is now uniformly `interpolation_scheme = CatmullRom` (`src/SimulationRun.jl:162`).
`src/Particles.jl:59-60` now explains *why* it is bare: "[`CatmullRom`]... — a ready-made value
rather than a type, so it is passed bare — is the ``C^1`` choice". Verified against
`GBGPeriodicFields`: `~/.julia/packages/GBGPeriodicFields/Y1yag/src/Interpolation.jl:314`: `const
CatmullRom = LalescuSpline(1, 1)` — CatmullRom genuinely is a value, not a type, so the bare form is
factually correct and now explicitly justified, unlike `TwoThirds()`/`IFLowStorageRK3()`/
`EndpointHeun()`, which are types. The one code example that constructs a `Tracers` directly
(`src/Particles.jl:100`) also now writes `interpolation_scheme = CatmullRom` bare, consistent with
the default. No remaining site pairs the bare default with a parenthesized worked example.

---

## Finding 3 — Three descriptions of what makes `particle_velocities` readable name three different actors
**VERDICT: ABSENT**

**Evidence:** The mechanism is now named consistently across all three docstrings via a single
extra verb, `deposit_sample!` (`src/Cache.jl:257-259`), which sets both
`sample_fields_epoch`/`sample_particles_epoch`. `src/Cache.jl:301-317` (`particles_modified!`)
spells the full sequence: `advect!` → `particles_modified!` → `record_particle_velocity!` (write)
→ `deposit_sample!` (mark current) — "the write alone leaves the slot stale, and a read of it
throws." `src/Particles.jl:221-234` (`record_particle_velocity!`) now states explicitly: "This
call is that slot's only producer of values, but it writes values only: the slot becomes readable
when the cache is then told the values are current, which is a second call the cache owns."
`src/Propagator.jl:483-486` (`deposit!`) says the slot "is filled by `record_particle_velocity!`
... which `advance!` and the `deposit!(sim)` form ... both do," consistent with (not contradicting)
the other two, since it doesn't claim `record_particle_velocity!` alone makes it readable. The
actual call sites (`src/SimulationRun.jl:277-278`, `:302-304`, `:393-395`) confirm the same
write-then-mark pair everywhere. No site claims a different call sequence.

---

## Finding 4 — "the developed-turbulence markers" (plural) names only one built marker
**VERDICT: ABSENT**

**Evidence:** All three prior occurrences now read singular: `docs/src/index.md:97` "the
developed-turbulence marker", `docs/src/api.md:12` "the developed-turbulence marker",
`docs/src/api/Observables.md:28` "The velocity-derivative skewness — the developed-turbulence
marker that gates warm-up." `rg "developed-turbulence"` across `docs/` and `src/` returns only these
three, all singular, matching the single `derivative_skewness` observable enumerated in
`src/Observables.jl`'s module docstring. No plural form remains.
