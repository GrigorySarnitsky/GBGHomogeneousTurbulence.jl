# Closure audit — Hat 15: invariants-and-decisions

## Finding 1 — `CLAUDE.md`'s `Cache` bullet used retired terms "stamped" / `resolved_fields_modified!`

**VERDICT: ABSENT**

Evidence: `grep -n "stamp\|resolved_fields_modified" CLAUDE.md` → no hits. Current `Cache` bullet
(CLAUDE.md, "Modules and wiring") reads "the storage the iteration deposits its observables into at
its end (… `fields_modified!` announces an out-of-band state mutation)". `src/Cache.jl:298` defines
`fields_modified!(cache::ObservablesCache) = (cache.fields_epoch += 1; cache)`, matching. Swept the
live corpus (`src/`, `docs/src/`, `docs/ARCHITECTURE.md`, `README.md`) for both terms: the only
survivors are inside `docs/ARCHITECTURE.md` §11 decisions 30 and 53 (append-only historical record,
explicitly exempt per this hat's own scope note) — no live-surface instance of the class remains.

## Finding 2 — `CLAUDE.md`'s `Generator` bullet named nonexistent verbs `velocity_factor` / `scalar_factor`

**VERDICT: ABSENT**

Evidence: `grep -n "velocity_factor\|scalar_factor" CLAUDE.md` → only
`velocity_integrating_factor` / `scalar_integrating_factor` (lines 46–47), matching
`src/Generator.jl` (exports and defines exactly these two, e.g. lines 420, 433). Swept `src/`,
`docs/src/`, `docs/ARCHITECTURE.md` for a bare `velocity_factor`/`scalar_factor` (not part of the
longer `_integrating_factor` name): no hits anywhere in the live corpus.

## Finding 3 — `CLAUDE.md`'s naming-convention example list gave stale storage-field names `cache.vorticity`, `state.velocity`

**VERDICT: ABSENT**

Evidence: CLAUDE.md ("Style" → naming section) now reads `cache.vorticity_physical`,
`generator.product_spectral`, `state.velocity_spectral`, `Tracers.particle_velocities` — all four
verified against source: `src/Cache.jl:119` (`const vorticity_physical::PV`), `src/State.jl:57`
(`velocity_spectral::UH`), `src/Particles.jl:129` (`particle_velocities::VV`). Swept `src/`,
`docs/src/`, `docs/ARCHITECTURE.md`, `README.md` for bare `state.velocity`, `state.scalar`,
`cache.vorticity`, `cache.velocity`, `cache.scalar` (no suffix): zero hits in the live corpus — no
surviving instance of the class.
