# Closure audit — Hat 15: invariants-and-decisions

## Finding 1 — `CLAUDE.md`'s `Cache` bullet used retired terms "stamped" / `resolved_fields_modified!`

**VERDICT: ABSENT**

Evidence: `CLAUDE.md` line 40–42 now reads "the storage the iteration deposits its observables into
at its end (… `fields_modified!` announces an out-of-band state mutation)" — no "stamped", no
`resolved_fields_modified!`. `grep -rn "\bstamped\b" src/ docs/src/ docs/ARCHITECTURE.md README.md`
finds it only inside the append-only decision-log entry (decision 53, lines 1717–1721 of
`ARCHITECTURE.md`/`docs/src/architecture.md`), which the hat brief itself exempts. Likewise
`grep -rn resolved_fields_modified` hits only decision-log lines 1115/1662. `src/Cache.jl:295` defines
`fields_modified!(cache::ObservablesCache) = (cache.fields_epoch += 1; cache)`, matching `CLAUDE.md`'s
current text exactly.

---

## Finding 2 — `CLAUDE.md`'s `Generator` bullet named nonexistent verbs `velocity_factor` / `scalar_factor`

**VERDICT: ABSENT**

Evidence: `CLAUDE.md` lines 44–47 now read "…behind the protocol `prepare!` / `velocity_rhs!` /
`scalar_rhs!` / `velocity_integrating_factor` / `scalar_integrating_factor` / `finalize!`." —
the full, correct names. `grep -rn "\bvelocity_factor\b|\bscalar_factor\b" src/ docs/src/
docs/ARCHITECTURE.md README.md` returns nothing anywhere in the corpus. `src/Generator.jl:423,436`
define exactly `velocity_integrating_factor` / `scalar_integrating_factor`, matching.

---

## Finding 3 — `CLAUDE.md`'s naming-convention example list gave two stale storage-field names: `cache.vorticity`, `state.velocity`

**VERDICT: ABSENT**

Evidence: `CLAUDE.md` lines 100–102 now read "Storage slots keep descriptive names — `cache.vorticity_physical`,
`generator.product_spectral`, `state.velocity_spectral`, `Tracers.particle_velocities` —" — all four
entries correct. `grep -rn "cache\.vorticity\b|state\.velocity\b|Tracers\.trajectory_velocity\b"
src/ docs/src/ docs/ARCHITECTURE.md README.md` returns nothing. Confirmed against source:
`src/Cache.jl:116` `const vorticity_physical::PV`; `src/State.jl:57` `velocity_spectral::UH`;
`src/Particles.jl:129` `particle_velocities::VV` (also matches the 2026-08 rename
`trajectory_sample → particle_velocities` noted in recent commit history) — no class survivors found.
