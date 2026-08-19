# Closure — Hat 01: consistency-matrix

## Finding 1 — "stamp" retired term still used in notation.md / api-Cache
**VERDICT: ABSENT**

Evidence: `rg -i 'stamp' src/ docs/src/ docs/ARCHITECTURE.md` (scoped away from `.claude/`) returns
exactly one hit, in `docs/ARCHITECTURE.md:1738-1754`, the §11 decision-log entry itself narrating the
historical rename ("Stamp is retired... `*_stamp` fields become `*_epoch`") — a quoted-for-context
mention of the old term, not a live use. `docs/src/notation.md`'s Vocabulary table (lines 121-123) now
reads "epoch" throughout ("A slot is readable exactly while the epoch it records still equals the
counter it depends on"), with no "stamp." `src/Cache.jl`'s `ObservablesCache` docstring and every
accessor/deposit comment use "epoch" exclusively (`velocity_epoch`, `sample_fields_epoch`, etc.).
Rendered build confirms: `grep -ic stamp` on `docs/build/notation/index.html`,
`docs/build/api/Cache/index.html`, `docs/build/api/Particles/index.html`,
`docs/build/observables_cache/index.html` all return 0.

## Finding 2 — `particle_velocities` read-only/staleness caveat missing on the Particles page
**VERDICT: ABSENT**

Evidence: `src/Particles.jl`, `Tracers` `# Fields` section (lines 123-127): "`particle_velocities` —
... This array **is** the observables cache's particle-velocities slot, the same storage under two
names, so it carries that slot's rules — read it through `particle_velocities`, which serves it only
when current, and treat it as read-only, since the tracer advance writes here mid-iteration." This is
the exact caveat the finding says was missing. Confirmed present verbatim in
`docs/build/api/Particles/index.html` (grep match on "This array <strong>is</strong> the observables
cache's particle-velocities slot...treat it as read-only").

## Finding 3 — `kinetic_energy` shows dual-form signature block, `scalar_variance` shows only one
**VERDICT: ABSENT**

Evidence: `src/Observables.jl` lines 187-189 now show the two-line signature block
`scalar_variance(φ)` / `scalar_variance(φ̂)`, matching `kinetic_energy`'s dual-form block (lines 51-52).
Both docstrings pair the signature block with the identical Parseval-representation-agnostic prose.
Rendered `docs/build/api/Observables/index.html` contains `scalar_variance(φ̂)` in its signature block,
confirming the second form now renders. The style asymmetry the finding flagged no longer exists.
