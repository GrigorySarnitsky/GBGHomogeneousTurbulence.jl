# Closure audit — Hat 11: First-year turbulence grad student (cold reader)

## Finding 1 — "deposit" is jargon used inside its own would-be definition

**Verdict: ABSENT**

`docs/src/index.md:47-50` now defines the term inline at first use: "a step, then the DEPOSIT that
closes it — the write in which the iteration hands the cache the observables it has just computed,
each tagged with the iteration it belongs to." The reader no longer waits four pages for a definition.

---

## Finding 2 — No glossary exists for the package's own operational vocabulary

**Verdict: ABSENT**

`docs/src/notation.md:110-125` now carries a `## Vocabulary` section, a table defining exactly the
flagged terms — iteration, deposit, slot, epoch, register, front door, observation, plus resolved —
each with a one-sentence definition and cross-links. Sits on the Notation page, second in the nav
after Home, before every API page.

---

## Finding 3 — `FlowConditions` and `FlowParameters`: near-identical names, overlapping fields

**Verdict: ABSENT**

`src/Generator.jl:62-63` (`FlowConditions` docstring) now reads: "Not to be confused with
`Phenomenology`'s `FlowParameters`, which shares two field names: this type holds what a run is
**configured with**, that one holds what a run has been **measured to have**." The forward pointer
the finding said was missing is now present at the earlier-met type.

---

## Finding 4 — "register" used in two unrelated senses before the package sense is defined

**Verdict: ABSENT**

The flagged `max_speed` docstring (`src/Observables.jl:128-131`) no longer uses the word "register" at
all ("The magnitude is formed one grid point at a time and consumed by the maximum immediately");
`docs/src/api/Observables.md` has zero occurrences of "register". Independently, `notation.md`'s new
Vocabulary section defines the package sense of "register" on page 2 of the nav, before any API page.
The only surviving hardware-sense "registers" is a plain `#` comment in `src/Observables.jl:268`
(`derivative_skewness`), which per house rule is not rendered into docs.

---

## Finding 5 — "CFL" used unexpanded at its very first two appearances

**Verdict: ABSENT**

`docs/src/index.md:113` and `docs/src/api.md:18` (both flagged first-appearance sites) now read
"the Courant–Friedrichs–Lewy (CFL) adaptive loop" — the acronym is spelled out at both points of first
use rather than deferred to the Notation page.

---

## Finding 6 — "the developed-turbulence markers" (plural) but only one marker is documented

**Verdict: ABSENT**

Both flagged sites now say singular "marker": `docs/src/index.md:97` and `docs/src/api.md:12` read
"the developed-turbulence marker" (was "markers"), matching the singular already used in
`docs/src/api/Observables.md:28` and `src/Observables.jl:15`. Consistent across all three surfaces now.

---

## Finding 7 — "Berendsen-thermostat limit" never explained mechanically

**Verdict: ABSENT**

`src/Forcing.jl:262-265` now states the mechanism, not just the consequence: "...is the
Berendsen-thermostat limit of stochastic velocity rescaling: the molecular-dynamics thermostat that
multiplies every velocity by one factor each step, chosen to drag the instantaneous temperature toward
its target, which is what this forcing does to the band's amplitude." The name is no longer a bare
label.

---

## Finding 8 — "EDQNM, DIA, LRA" acronyms never expanded anywhere on the site

**Verdict: ABSENT**

`src/phenomenology/Spectra.jl:208-209` (`ExponentialDissipation`) now spells the closures out in prose:
"the triadic spectral closures — eddy-damped quasi-normal Markovian, direct-interaction approximation,
Lagrangian renormalized approximation — consistently predict (Kaneda 1993; Sagaut & Cambon 2018)." No
bare acronyms remain at this site.

---

## Finding 9 — "arm"/"armed" used before its own gloss, on the same page

**Verdict: ABSENT**

The `Generator` module docstring's `prepare!` bullet (`src/Generator.jl:23-24`) no longer uses "arm" at
all — it now reads "advance the forcings' internal state and fill the linear rate arrays the
integrating factor will consume." The word "arm" first appears at line 249, inside `prepare!`'s own
docstring, immediately self-glossed: "arm the per-mode linear forcing rates (fill them, so the factor
verbs return them instead of `nothing`)." The flagged ordering gap (module summary before gloss) is
gone; the word now appears once, glossed at its own first use.

---

## Finding 10 — `PointSet` / `VectorPointValues` / `ScalarPointValues` named but never characterized

**Verdict: ABSENT**

`src/Particles.jl:116, 203, 307-308` now `@extref`-link all three types to their home docstrings in
`GBGPeriodicFields`'s own published docs (e.g.
`https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/dev/api/Points/#GBGPeriodicFields.Points.PointSet`,
confirmed resolving in `docs/build/api/Particles/index.html`). Per house policy this is the sanctioned
fix (`@extref` is the documented exception for exactly these sibling-package types) rather than
duplicating a second description on this site.

---

## Finding 11 — "resolved" used for two different concepts

**Verdict: ABSENT**

`docs/src/notation.md:125` (new Vocabulary section) now disambiguates explicitly: "**resolved** | in
`ResolvedFields` and `ResolvedGenerator`, *made concrete as one value* — not the numerical sense of
'resolved by the grid', which this package writes out in full wherever it is meant." This sits on the
Notation page, met before every API page that uses either sense.
