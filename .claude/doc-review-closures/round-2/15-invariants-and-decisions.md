# Closure — Hat 15: invariants-and-decisions

## Finding 1 — `CLAUDE.md`'s `Cache` bullet used retired terms "stamped" / `resolved_fields_modified!`

**VERDICT: ABSENT**

Evidence: `grep -n "stamp\|resolved_fields_modified" CLAUDE.md` → no hits. Current `Cache` bullet reads
"the storage the iteration deposits its observables into at its end (… `fields_modified!` announces an
out-of-band state mutation)". `src/Cache.jl:298` defines `fields_modified!(cache::ObservablesCache) =
(cache.fields_epoch += 1; cache)`; no `resolved_fields_modified!` exists in `src/`, `docs/src/`, or
`CLAUDE.md`. The only remaining occurrences of `resolved_fields_modified!` are inside
`docs/ARCHITECTURE.md` §11's decision-log history (exempt, correctly framed as "was named … when the
decision was taken") and in `.claude/` working-note piles, which are not part of the audited doc
surface.

---

## Finding 2 — `CLAUDE.md`'s `Generator` bullet named nonexistent verbs `velocity_factor` / `scalar_factor`

**VERDICT: ABSENT**

Evidence: `grep -n "velocity_factor\|scalar_factor" CLAUDE.md` → no hits. Current `Generator` bullet
lists the protocol as "`prepare!` / `velocity_rhs!` / `scalar_rhs!` / `velocity_integrating_factor` /
`scalar_integrating_factor` / `finalize!`", matching `src/Generator.jl` (exports and defines
`velocity_integrating_factor` line 420, `scalar_integrating_factor` line 433) and the rendered
`api/Generator` page. Bare `velocity_factor`/`scalar_factor` (not part of the longer
`_integrating_factor` name) appear nowhere in `src/`, `docs/src/`, `docs/ARCHITECTURE.md`, or
`CLAUDE.md` — only in unrelated `.claude/` working notes.

---

## Finding 3 — `CLAUDE.md`'s naming-convention example list gave stale storage-field names `cache.vorticity`, `state.velocity`

**VERDICT: ABSENT**

Evidence: `CLAUDE.md` "Style" → naming section now reads "Storage slots keep descriptive names —
`cache.vorticity_physical`, `generator.product_spectral`, `state.velocity_spectral`,
`Tracers.particle_velocities`". Confirmed against source: `src/Cache.jl` exports/defines
`vorticity_physical` (no bare `vorticity` field); `src/State.jl:57` defines
`velocity_spectral::UH` (no bare `velocity` field); `src/Particles.jl:129` defines
`particle_velocities::VV` matching the renamed slot (post trajectory_sample → particle_velocities,
per the most recent commit). `grep -n "cache\.vorticity\b\|state\.velocity\b"` across `CLAUDE.md`,
`docs/src/`, `docs/ARCHITECTURE.md`, `src/` returns nothing.

---

## Scope note (from the banked hat)

Not independently re-audited beyond the three findings above; the hat's own scope note claims the
rest of the rendered site was already clean at banking time and is out of scope for this closure pass,
which targets only the three numbered findings.
