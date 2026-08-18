# Closure audit — Hat 11: First-year turbulence grad student (cold reader)

## Finding 1 — "deposit" is jargon used inside its own would-be definition
**Verdict:** ABSENT
**Evidence:** `docs/src/index.md:47-49` now reads "the DEPOSIT that closes it — the write in which the iteration hands the cache the observables it has just computed, each tagged with the iteration it belongs to," defining "deposit" inline at its own first use rather than deferring to `api/Cache.md`. Checked `docs/src/index.md` in full; no remaining bare use before definition.

---

## Finding 2 — No glossary exists for the package's own operational vocabulary
**Verdict:** ABSENT
**Evidence:** `docs/src/notation.md:110-123` now carries a `## Vocabulary` section, explicitly introduced ("This section does the same for the package's **operational** words") with a table defining iteration, deposit, slot, epoch, register, front door, observation, and resolved. Grepped `notation.md` for each term; all present with one entry each.

---

## Finding 3 — `FlowConditions` / `FlowParameters` near-identical names, no cross-reference
**Verdict:** ABSENT
**Evidence:** `src/Generator.jl:62-63`, `FlowConditions` docstring: "Not to be confused with `Phenomenology`'s `FlowParameters`, which shares two field names: this type holds what a run is **configured with**, that one holds what a run has been **measured to have**." Confirmed rendered in `docs/build/api/Generator/index.html`.

---

## Finding 4 — "register" used in two unrelated senses before the package sense is ever defined
**Verdict:** PARTIAL
**Evidence:** `notation.md:122` now defines "register" formally and precedes `api/Observables.md` in the stated reading order, so the literal ordering complaint (informal use before formal definition) no longer holds. But `src/Observables.jl:130` (`max_speed` docstring) is textually unchanged: "formed per grid point in registers and consumed by the maximum immediately" — still the unrelated hardware sense, still unflagged against the now-earlier formal package sense.
**Surviving class:** `src/Observables.jl:130` (rendered `api/Observables.md`, `max_speed`) uses "registers" in the informal hardware sense with no note distinguishing it from the package's formal `register` glossary term; same word, two senses, no disambiguation at the site itself.

---

## Finding 5 — "CFL" used unexpanded at its very first two appearances
**Verdict:** ABSENT
**Evidence:** `docs/src/index.md:113` and `docs/src/api.md:18` both now read "Courant–Friedrichs–Lewy (CFL)" at first mention. Grepped both files plus `notation.md` for `CFL`; no remaining bare acronym before expansion.

---

## Finding 6 — "the developed-turbulence markers" (plural) but only one marker documented
**Verdict:** ABSENT
**Evidence:** `docs/src/index.md:97` and `docs/src/api.md:12` both now read singular "the developed-turbulence marker," matching the singular usage in `docs/src/api/Observables.md:28` and `src/Observables.jl:15,257`. Grepped `docs/src` and `src/*.jl` for "markers" (plural); zero hits.

---

## Finding 7 — "Berendsen-thermostat limit" never explained mechanically
**Verdict:** ABSENT
**Evidence:** `src/Forcing.jl:262-265` now reads "...the Berendsen-thermostat limit of stochastic velocity rescaling: the molecular-dynamics thermostat that multiplies every velocity by one factor each step, chosen to drag the instantaneous temperature toward its target, which is what this forcing does to the band's amplitude." The mechanism is now stated, not just the consequence.

---

## Finding 8 — "EDQNM, DIA, LRA" acronyms never expanded
**Verdict:** ABSENT
**Evidence:** `src/phenomenology/Spectra.jl:208-210` (`ExponentialDissipation` docstring) now reads "the triadic spectral closures — eddy-damped quasi-normal Markovian, direct-interaction approximation, Lagrangian renormalized approximation — consistently predict." Grepped `src/` and `docs/src` for bare `EDQNM`/`DIA`/`LRA`; only remaining hits are in `ARCHITECTURE.md`/`architecture.md` (not a Phenomenology API page, out of this finding's cited scope).

---

## Finding 9 — "arm"/"armed" used before its own gloss, on the same page
**Verdict:** ABSENT
**Evidence:** `src/Generator.jl:22` (module docstring) now describes `prepare!` as "advance the forcings' internal state and fill the linear rate arrays the integrating factor will consume" — no "arm" jargon at all in the module summary. `prepare!`'s own docstring at line 249-250 still uses "arm... (fill them, so the factor verbs return them instead of `nothing`)" with the gloss in the same sentence, not deferred.

---

## Finding 10 — `PointSet` / `VectorPointValues` / `ScalarPointValues` named but never characterized
**Verdict:** ABSENT
**Evidence:** `src/Particles.jl:116,203,307-308,339,348` now cross-link each type via `@extref GBGPeriodicFields GBGPeriodicFields.Points.*`, confirmed resolving to working external links in `docs/build/api/Particles/index.html` (e.g. `https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/dev/api/Points/#GBGPeriodicFields.Points.PointSet`). `position_points`'s bullet now also explains *why* it exists alongside `positions`: "the same coordinates in the form `GBGPeriodicFields`' interpolation takes, which is why both exist." Consistent with the house `@extref` exception for `GBGPeriodicFields` types.

---

## Finding 11 — "resolved" used for two different concepts, never distinguished
**Verdict:** ABSENT
**Evidence:** `docs/src/notation.md:123` (Vocabulary table): "**resolved** | in `ResolvedFields` and `ResolvedGenerator`, *made concrete as one value* — not the numerical sense of 'resolved by the grid', which this package writes out in full wherever it is meant." This entry precedes both usages in the stated cold-read order (notation is page 3; `api.md`'s "resolved-wavenumber ceiling" and `Generator.md`'s `ResolvedGenerator` come later), giving the reader a single reference that explicitly distinguishes the two senses.
