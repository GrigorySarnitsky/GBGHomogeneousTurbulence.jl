# Closure — 11-cold-reader

## Finding 1 — Page order contradicts the site's own stated "dependency order"
**VERDICT: REGRESSED**

`docs/src/api.md` (and the built `docs/build/api/index.html`) now carries a new sentence: "**The
pages below are ordered for reading, not by that dependency**: `SimulationRun` comes first because a
run is what a user builds first, and the pieces it composes follow." The actual site sidebar nav
(confirmed from `docs/build/api/index.html`'s `<nav class="docs-sidebar">`) does follow this:
`GBGHomogeneousTurbulence, SimulationRun, SimulationDomain, State, Observables, Cache, Forcing,
Generator, Propagator, Particles` — so the original "Concretely" example (Cache leaning on
`FixedDomain` before `FixedDomain`'s home page) is now fixed: `SimulationDomain` (banner 3) precedes
`Cache` (banner 6).

But the bulleted list immediately following that sentence — "the pages below" it explicitly refers
to — and the `@contents` block further down on the *same page*, both still list `SimulationRun`
**last**, after `Particles`: `GBGHomogeneousTurbulence, SimulationDomain, State, Observables, Cache,
Forcing, Generator, Propagator, Particles, SimulationRun`. This is a live, self-contained
contradiction introduced by the fix: the prose's claim ("`SimulationRun` comes first... pages below")
is false against the very list it points to, verified in both `docs/src/api.md` lines 4-19 and the
rendered `docs/build/api/index.html`.

---

## Finding 2 — "Resolved" used in the disclaimed numerical sense one page before its own gloss forbids it
**VERDICT: ABSENT**

Searched `docs/src/*.md`, `docs/ARCHITECTURE.md`, `src/*.jl`, and the rendered
`docs/build/api/index.html` for "resolved-wavenumber" / "resolved wavenumber" — zero hits. The api
overview page's `max_wavenumber` bullet now reads "`max_wavenumber`, the highest wavenumber magnitude
the run evolves" (`docs/src/api.md:12`) — the bare disclaimed word is gone. The Vocabulary entry
(`docs/src/notation.md:126`) still carries the house rule distinguishing the two senses.

---

## Finding 3 — `deposit_sample!` named as a callable the reader must invoke, with no docstring anywhere
**VERDICT: ABSENT**

`src/Cache.jl:262-281` now carries a full docstring for `deposit_sample!` ("`deposit_sample!(cache) ->
particle velocities`", with usage/rationale prose), it is exported (`src/Cache.jl:57`,
`src/GBGHomogeneousTurbulence.jl:99,178`), and it appears in the rendered `docs/build/api/Cache/index.html`
docstring block and is linked from `docs/build/api/GBGHomogeneousTurbulence/index.html`'s Index
(`href="../Cache/#GBGHomogeneousTurbulence.Cache.deposit_sample!"`).

---

## Finding 4 — "the developed-turbulence marker" used unglossed at first sight, resolved 8 pages later
**VERDICT: ABSENT**

Both first-sight locations now name the function inline: `docs/src/index.md:97` — "the
developed-turbulence marker (`derivative_skewness`)" — and `docs/src/api.md:14` — same parenthetical.
A cold reader no longer has to wait for the `Observables` page to bind the phrase.

---

## Finding 5 — "verbs" used as unglossed jargon for the protocol's functions, from page one
**VERDICT: ABSENT**

The Home page (`docs/src/index.md:106-108`), the exact page-one location the finding cited, now
reads: "a fixed set of **verbs** — the protocol's functions, `prepare!`, `velocity_rhs!` and the rest
— rather than assembling the physics itself." The gloss sits inline at first use. (`docs/src/api.md:17`
repeats the term without re-glossing, but by then the reader has already met the Home-page gloss, and
`src/Generator.jl`'s own docstring uses "protocol" — not "verb" — to introduce the concept before
"verb" recurs in later notes.)

---

## Finding 6 — "the tracer push": an ordinary word given a specific technical referent, never bound to a name
**VERDICT: PARTIAL**

Fixed at the exact flagged line: `src/Cache.jl:119-120`'s `particles_epoch` field entry now reads
"the tracer positions' counter, advanced when [`advect!`](@ref ...) moves them" — explicit, linked.

Class survives elsewhere:
- `docs/src/api/Particles.md:66` — "Wiring tracers into a run": "`advance!` **pushes** it every
  iteration and records the Lagrangian sample" — the verb form, still never bound to `advect!` (this
  is the finding's own second cited location, unchanged).
- The noun phrase "the tracer push" itself recurs unglossed in rendered docs at
  `docs/src/architecture.md:455,1172,1318` and `docs/src/observables_cache.md:339`, none binding it to
  `advect!` at first use (`advect!` itself first appears only at `docs/src/architecture.md:1550`).

**surviving_class:** `docs/src/api/Particles.md:66` ("pushes it every iteration"); "the tracer push" at
`docs/src/architecture.md:455,1172,1318` and `docs/src/observables_cache.md:339`.

---

## Finding 7 — "epoch" names both the running counter and the value stamped on a slot
**VERDICT: ABSENT**

`docs/src/notation.md:122`'s Vocabulary entry was reworded to state both senses explicitly: "a counter
of *changes to the state*... — **and, for a slot, the value of that counter stamped on it when it was
filled**." This directly names the double duty the finding flagged, rather than leaving it to be
inferred from context. `src/Cache.jl:18` similarly separates "the slots, their epochs, and the two
counters" in its module map.
