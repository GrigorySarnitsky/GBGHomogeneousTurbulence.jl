# Closure — Hat 11: Cold-reader (first-year grad student)

One verdict per banked finding, adjudicated against the current corpus only.

---

## Finding 1 — "front door" unglossed on first page, then re-glossed 3× before its canonical definition

**Verdict:** PARTIAL

**Evidence:** `docs/src/index.md:32` now glosses on first use: "Build a case at the **front door** —
the `Simulation` constructor that builds every component for you —". The zero-gloss defect at the
exact flagged location is fixed. But the surviving class persists: `src/Cache.jl:82-83` and
`src/Generator.jl:177-178` still each carry their own independent paraphrase ("the build-everything
convenience constructor"), unchanged, distinct in wording from Home's and from the canonical
definition in `src/SimulationRun.jl:77`.

**Surviving class:** independent re-glosses of "front door" remain at `src/Cache.jl:82`,
`src/Generator.jl:177` — same redundant-definition pattern the finding described, now with a 4th
gloss (Home) added rather than consolidated.

---

## Finding 2 — "iteration"/"deposit"/"stamp" used on Home before being defined

**Verdict:** ABSENT

**Evidence:** `docs/src/index.md:47-48` now glosses inline at first use: "One ITERATION is one
advance: a step, then the deposit that closes it" (code comment) and Components
(`docs/src/index.md:97-98`) repeats the same parenthetical. "Stamp"/"stamped" no longer appears
anywhere in `docs/src/` or `src/*.jl` (`grep -rn "stamp"` returns only `docs/src/architecture.md`
decision-log entry 47 explaining the term was retired in favor of "epoch").

---

## Finding 3 — "scratch arity" used twice, never defined

**Verdict:** ABSENT

**Evidence:** `grep -rn "scratch arity"` across `src/` and `docs/src/` returns zero hits. Both
flagged sites now explain the mechanism in place: `src/State.jl:21-23` — "the four-argument
`to_physical!`, whose extra argument is a scratch field the transform consumes in the state's
place"; `src/Generator.jl:30-32` — "the four-argument, source-preserving form (the extra argument is
a scratch field the transform consumes in the source's place)". `docs/src/api/State.md:10-11` matches.

---

## Finding 4 — "2N-storage" silently reuses N for a different quantity than notation's N

**Verdict:** ABSENT

**Evidence:** `src/Propagator.jl:240-241` now disambiguates explicitly: "in Williamson's 2N-storage
count, whose ``N`` counts evolved field registers, not the grid points ``N`` of the rest of the
documentation".

---

## Finding 5 — "instant between steps" (Home) vs. "instant between iterations" elsewhere

**Verdict:** ABSENT

**Evidence:** `docs/src/index.md:48` now reads "valid between iterations" (not "between steps"); the
phrase "instant between steps" no longer appears anywhere in `docs/src/` or `src/*.jl`
(`grep -rn "instant between steps"` empty). `docs/src/architecture.md:1636-1637` records decision 48,
which retired the ambiguous vocabulary and standardized on "between iterations" / "the instant"
throughout. The one remaining "between steps" phrase (`src/Propagator.jl:84`, about a scratch
register's read-validity) refers to a different object (`IntegratorBuffers`, not the cache/clock
instant) and is not a recurrence of the flagged inconsistency.

---

## Finding 6 — $y_{\mathrm s}$ missing from the notation page

**Verdict:** ABSENT

**Evidence:** `docs/src/notation.md:100` now lists it in the Numerics table: "``y_{\mathrm{s}}`` | a
scheme's imaginary-axis stability limit (``\sqrt{3}`` for `IFLowStorageRK3`; ``0`` for the
imaginary-axis-unstable `IFRK2`) | [`recommended_cfl`](@ref …)".

---

## Finding 7 — `StationarityCriterion`'s "Fields" list accounts for only 6 of 7 keywords

**Verdict:** ABSENT

**Evidence:** `src/SimulationRun.jl:568-571` now states explicitly: "Note the keyword arguments above
do **not** map one-to-one onto these fields: `gate_skewness`, `min_turnovers`, `window_turnovers`,
`tol` and `skew_floor` are all stored inside `monitor`, which holds the sampled series together with
the thresholds that judge them." All 7 keywords are now accounted for by name.

---

## Finding 8 — `PointSet`/`VectorPointValues`/`ScalarPointValues` used with no on-site definition

**Verdict:** ABSENT

**Evidence:** All three now carry `@extref` links to `GBGPeriodicFields.Points.*`
(`src/Particles.jl:107,119,194,295-296,327,336`). Confirmed live in the rendered build:
`docs/build/api/Particles/index.html` shows resolved hrefs to
`https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/dev/api/Points/#GBGPeriodicFields.Points.PointSet`
etc. — the finding's own low-confidence speculation ("likely a backend cross-link exists") is now true.

---

## Finding 9 — "observation" overloaded between "act of observing" and "the callback object"

**Verdict:** ABSENT

**Evidence:** `src/SimulationRun.jl:22-23` now glosses the noun sense explicitly on first use: "the
callback *is* the observation — the thing that reads the run each iteration — and its return decides
continuation". `StationarityCriterion` (`src/SimulationRun.jl:535`, "The packaged spin-up observation
… a callback that watches …") is consistent with that same object-sense.

---

## Finding 10 — "reified"/"reification" used repeatedly with no plain-language gloss

**Verdict:** PARTIAL

**Evidence:** Both flagged sites are fixed: Home (`docs/src/index.md:102-104`) now says "packaged
into one object", no "reified"; `ResolvedGenerator`'s docstring (`src/Generator.jl:149-150`) now
opens "The flow's generator as one value a scheme can hold" — no "reified" either. But the term
survives unglossed as a section heading, `docs/src/api/Generator.md:17`, "## The reified generator"
(immediately followed by a plain paraphrase in the next sentence, but the word itself is still never
explained), and remains pervasive and unglossed throughout `docs/src/architecture.md`.

**Surviving class:** `docs/src/api/Generator.md:17` heading; dozens of unglossed uses in
`docs/src/architecture.md` (e.g. lines 196, 289, 1023, 1085, 1100, 1138-1139, 1179).

---

## Finding 11 — "armed" (forcing rate) used metaphorically, mechanism never stated plainly

**Verdict:** ABSENT

**Evidence:** `src/Generator.jl:231-232` (`prepare!` docstring) now states the mechanism explicitly on
first use: "arm the per-mode linear forcing rates (fill them, so the factor verbs return them instead
of `nothing`)". Downstream uses (`velocity_integrating_factor`, `scalar_integrating_factor`,
`src/Generator.jl:381,397,400,414`) rely on that established gloss, standard for a per-module reading
order.

---

## Finding 12 — notation-page symbol $T$ never recurs in a formula elsewhere

**Verdict:** ABSENT

**Evidence:** `docs/src/architecture.md:585-586` and `:751` now use the glyph ``T`` in prose matching
the notation-page binding: "The element type ``T`` flows from the frame …" and "**No privileged
precision or backend.** ``T`` and the array type flow from the frame …". No longer dead weight.

---

## Finding 13 — "wavenumber-magnitude shell" never plainly defined

**Verdict:** ABSENT

**Evidence:** `docs/src/notation.md:73` now defines it explicitly: "the energy in wavenumber-magnitude
shell ``n`` — a set of Fourier modes one shell width ``\Delta\kappa = 2\pi/L`` thick". `src/Observables.jl:272-277`
matches ("resolved over wavenumber-magnitude shells … the shell width …").

---

## Finding 14 — "CFL" acronym never expanded on first use

**Verdict:** ABSENT

**Evidence:** `docs/src/notation.md:97` — "advective-CFL (Courant–Friedrichs–Lewy) ceiling"; matching
expansion at the docstring's first use, `src/Propagator.jl:511` — "A conservative advective-CFL
(Courant–Friedrichs–Lewy) ceiling".

---

## Finding 15 — "Dirichlet ($H^1$) energy" asserted with only the formula, no gloss of the term

**Verdict:** ABSENT

**Evidence:** Both flagged sites now gloss the term in plain language immediately alongside it:
`src/Observables.jl:101-102` — "its **Dirichlet energy** — the mean square of its gradient, ``H^1`` in
the Sobolev naming"; `src/Observables.jl:194-195` — "the mean square of the scalar's gradient, the
Dirichlet or ``H^{1}`` energy in the Sobolev naming".
