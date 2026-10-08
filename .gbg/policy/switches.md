<!-- gbg:managed begin v2.0.0-rc.66 — rewritten by `gbg sync`; do not edit -->
# What GBGHomogeneousTurbulence has switched off

Each entry names a rule this package does not hold itself to, and why. A rule listed
here is read as the entry states it.

- `RULE.GIT.TRACKED` — the TurTLE reproduction scripts the Validation page points at, so a reader of the published comparison can rerun it from the repository (the owner, 2026-10-05 and 2026-10-08) (`validation/**`)

Excluded from every rule: no rule reads these files, and no reader is given them.

- `src/Phenomenology.jl`, `src/phenomenology/**`, `docs/src/phenomenology.md`, `docs/src/api/phenomenology/**`, `test/phenomenology.jl` — the Phenomenology module is not held to the rulebook until it is extracted into its own package (the owner, 2026-09-29)

Rules this package adds for itself, which are nobody else's:

- `lamb_sign` — The Lamb vector is ω × u; u × ω is its negation.

<!-- gbg:managed end -->
