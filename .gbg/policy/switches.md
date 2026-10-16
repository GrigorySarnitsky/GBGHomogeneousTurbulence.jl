<!-- gbg:managed begin v2.0.0-rc.76 — rewritten by `gbg sync`; do not edit -->
# What GBGHomogeneousTurbulence has switched off

Each entry names a rule this package does not hold itself to, and why. A rule listed
here is read as the entry states it.

- `RULE.GIT.TRACKED` — the TurTLE reproduction scripts the Validation page points at, so a reader of the published comparison can rerun it from the repository (the owner, 2026-10-05 and 2026-10-08) (`validation/**`)
- `RULE.GIT.TRACKED` — the parked reference-law module Phenomenology — its source, tests and pages kept whole, loaded and built by nothing, in the layout of the standalone package it becomes when extracted (the owner, 2026-10-16, decision 113) (`parked/**`)

Rules this package adds for itself, which are nobody else's:

- `lamb_sign` — The Lamb vector is ω × u; u × ω is its negation.

<!-- gbg:managed end -->
