# Closure audit — Hat 11: First-year turbulence grad student (cold reader)

One verdict per banked finding, established from the current corpus alone (no diff/log/report reading).

---

## Finding 1 — "deposit" is jargon used inside its own would-be definition

**VERDICT: PRESENT**

Evidence: `docs/src/index.md:47-48` still reads verbatim "One ITERATION is one advance: a step, then
the deposit that closes it. The state is always current; the cache holds what the last deposit left,
so its reads are valid between iterations." — unchanged, still the first thing a reader meets, still
uses "deposit" undefined to define "iteration." The rigorous definition (`deposit!`, "fills every
slot at the iteration's end and sets its epoch") still lives only in `src/Cache.jl:30-32`
(`api/Cache.md`), which in the stated reading order (Home → api → notation → phenomenology →
api/Cache) is still four pages later. `docs/src/api.md:13,18` also uses "deposited"/"deposit" bare
before that page.

---

## Finding 2 — No glossary exists for the package's own operational vocabulary

**VERDICT: ABSENT**

Evidence: `docs/src/notation.md:110-126` now has a `## Vocabulary` section — "This section does the
same for the package's **operational** words" — with entries for `iteration`, `deposit`, `slot`,
`epoch`, `register`, `front door`, `observation`, and `resolved`, each one sentence, each linked to
its home type/function. Searched notation.md and found no other operational-vocabulary table; this is
now the single glossary the finding said was missing.

---

## Finding 3 — `FlowConditions` and `FlowParameters`: near-identical names, overlapping fields, different jobs

**VERDICT: ABSENT**

Evidence: `src/Generator.jl:62-63` (rendered on `api/Generator.md`, the earlier-met page) now reads:
"Not to be confused with `Phenomenology`'s `FlowParameters`, which shares two field names: this type
holds what a run is **configured with**, that one holds what a run has been **measured to have**." —
the forward pointer the finding said was missing, naming the shared fields and the semantic split,
placed at first meeting of `FlowConditions`.

---

## Finding 4 — "register" is used in two unrelated senses before the package sense is ever defined

**VERDICT: ABSENT**

Evidence: `docs/src/notation.md:122` Vocabulary entry — "**register** | storage a component computes
one value into and overwrites at the next, holding nothing a reader should trust in between." — is
met on page 3 of the reading order, before both `Observables.jl:127` ("formed per grid point in
registers") on page 9 and `Propagator.jl:84` on page 11. The generic definition covers both the
per-grid-point hardware sense and the named `IntegratorBuffers` sense consistently (both are "computed
into and overwritten"), so the reader now has one governing definition in place before meeting either
use, reversing and resolving the original unflagged-redefinition problem. Residual: the two use sites
themselves still carry no local cross-reference to each other, but the finding's specific complaint —
no definition exists ahead of use — no longer holds.

---

## Finding 5 — "CFL" used unexpanded at its very first two appearances

**VERDICT: PRESENT**

Evidence: `docs/src/index.md:111` and `docs/src/api.md:18` both still read "CFL-adaptive loop" bare,
unchanged. The expansion "advective-CFL (Courant–Friedrichs–Lewy) ceiling" still lives only at
`docs/src/notation.md:97`, page 3 of the reading order — still after both bare uses on pages 1 and 2.

---

## Finding 6 — "the developed-turbulence markers" (plural) but only one marker is ever documented

**VERDICT: ABSENT**

Evidence: `docs/src/index.md:95`, `docs/src/api.md:12`, and `docs/src/api/Observables.md:28` all now
read singular "the developed-turbulence marker" — grepped `developed-turbulence marker` across
`docs/src` and `src`; every hit is singular, none plural. `src/Observables.jl:15` likewise says "the
classical marker" (singular). The plural/singular mismatch is gone.

---

## Finding 7 — "Berendsen-thermostat limit" borrowed from molecular dynamics, never explained mechanically

**VERDICT: PRESENT**

Evidence: `src/Forcing.jl:247-255` still reads (essentially verbatim to the finding's quote) "Holding
an amplitude fixed by deterministic rescaling is the Berendsen-thermostat limit of stochastic velocity
rescaling — the molecular-dynamics thermostat whose deterministic limit this is: it has no conserved
quantity, is not associated with a well-defined ensemble except in limiting cases, and suppresses the
physical fluctuations..." — this still states only the *consequences*, never the *mechanism* (that a
Berendsen thermostat rescales velocities each step toward a target). The name still functions as an
unexplained label.

---

## Finding 8 — "EDQNM, DIA, LRA" acronyms never expanded anywhere on the site

**VERDICT: ABSENT**

Evidence: `src/phenomenology/Spectra.jl:207-209` now reads "the triadic spectral closures —
eddy-damped quasi-normal Markovian, direct-interaction approximation, Lagrangian renormalized
approximation — consistently predict (Kaneda 1993; Sagaut & Cambon 2018)." Grepped `EDQNM|DIA|LRA`
across `src/phenomenology` and `docs/src/api/phenomenology`: zero hits — the acronyms themselves are
gone, replaced by the spelled-out names.

---

## Finding 9 — "arm"/"armed" used before its own gloss, on the same page

**VERDICT: ABSENT**

Evidence: the `Generator` module docstring (`src/Generator.jl:23-24`, top of `api/Generator.md`) now
reads "`prepare!` — open a step: advance the forcings' internal state and fill the linear rate arrays
the integrating factor will consume" — no longer uses "arm" at all. The term "arm" is first introduced
further down the same page, inside `prepare!`'s own docstring (`src/Generator.jl:252-253`), with its
gloss immediately attached: "arm the per-mode linear forcing rates (fill them, so the factor verbs
return them instead of `nothing`)". The module-summary bare use the finding flagged is gone; the
surviving "armed" uses in `velocity_integrating_factor`/`scalar_integrating_factor` (lines 401, 411,
420, 434) all come after this gloss in reading order.

---

## Finding 10 — `PointSet` / `VectorPointValues` / `ScalarPointValues` named but never characterized

**VERDICT: ABSENT**

Evidence: `src/Particles.jl:116, 306-307, 338, 347` and `docs/src/api/Particles.md:57-58` now wrap
every mention in `@extref GBGPeriodicFields GBGPeriodicFields.Points.PointSet` /
`.VectorPointValues` / `.ScalarPointValues`. Checked `docs/build/api/Particles/index.html`: the links
render as live `https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/dev/api/Points/#...` anchors,
not dead text. This is the house-sanctioned exception (CLAUDE.md: "the `GBGPeriodicFields` types are
the deliberate `@extref` exception") — the reader now has an actual path to the types' characterization
rather than a bare, unlinked name.

---

## Finding 11 — "resolved" used for two different concepts

**VERDICT: ABSENT**

Evidence: `docs/src/notation.md:125` Vocabulary entry — "**resolved** | in `ResolvedFields` and
`ResolvedGenerator`, *made concrete as one value* — not the numerical sense of 'resolved by the grid',
which this package writes out in full wherever it is meant." — explicitly distinguishes the two senses
the finding flagged, by name, contrasting the type-naming use against the dealiasing-cutoff use. Both
uses (`docs/src/api.md:10-11,15`) still appear together, unremarked, at first meeting on page 2, but
the disambiguation the finding said "is never distinguished or cross-referenced" now exists on the very
next page.
