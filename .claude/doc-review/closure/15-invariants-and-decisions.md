# Closure: 15-invariants-and-decisions

## Finding 1 — `CLAUDE.md` Cache bullet: "stamped" / `resolved_fields_modified!`
**VERDICT: ABSENT**
Evidence: `CLAUDE.md` "Modules and wiring" now reads "…a slot doubles as its producer's stage
register; `fields_modified!` announces an out-of-band state mutation" (line 42) — no "stamped", no
`resolved_fields_modified!`. Corpus-wide `rg -n "resolved_fields_modified"` across `src/`,
`docs/src/`, `CLAUDE.md` returns empty; `rg -n "stamped" CLAUDE.md` returns empty. `src/Cache.jl:298`
defines `fields_modified!(cache::ObservablesCache) = (cache.fields_epoch += 1; cache)`, matching
`CLAUDE.md`'s claim.

## Finding 2 — `CLAUDE.md` Generator bullet: nonexistent `velocity_factor` / `scalar_factor`
**VERDICT: ABSENT**
Evidence: `CLAUDE.md` "Modules and wiring" now lists the protocol as `prepare!` / `velocity_rhs!` /
`scalar_rhs!` / `velocity_integrating_factor` / `scalar_integrating_factor` / `finalize!` (lines
46–47). `rg -n "\bvelocity_factor\b|\bscalar_factor\b"` over `src/`, `CLAUDE.md`, `docs/src/` returns
empty. `src/Generator.jl` exports and defines exactly `velocity_integrating_factor` /
`scalar_integrating_factor` (lines 28, 393, etc.), matching the corrected bullet.

## Finding 3 — `CLAUDE.md` naming example: stale `cache.vorticity`, `state.velocity`
**VERDICT: ABSENT**
Evidence: `CLAUDE.md` "Style" → naming section now reads "`cache.vorticity_physical`,
`generator.product_spectral`, `state.velocity_spectral`, `Tracers.particle_velocities`…" (lines
101–102) — all four entries match live field names. `rg -n "cache\.vorticity\b|state\.velocity\b"`
(bare, unsuffixed forms) over `src/`, `CLAUDE.md`, `docs/src/` returns empty. `src/Cache.jl:21`
documents `vorticity_physical`; `src/State.jl:52` documents `velocity_spectral`; no plain
`vorticity`/`velocity` field exists on either type.
