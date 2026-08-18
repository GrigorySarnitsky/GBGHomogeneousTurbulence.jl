# Cold-reader hat — first-year turbulence grad student, new to the package

Reading the rendered site top-to-bottom in banner order, flagging every term, symbol, or ordinary
English word given a package-specific meaning before (or without) a definition reachable at the point
of first use.

---

## Finding 1 — The page order contradicts the site's own stated "dependency order"

- **Type:** organization
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: api — "Its re-exported submodules, in dependency order, are `SimulationDomain` → `State` →
    `Observables` → `Cache` → `Forcing` → `Generator` → `Propagator` → `Particles` → `SimulationRun`"
  - The actual banner sequence encountered reading forward is: `api / Cache`, `api / Forcing`,
    `api / GBGIsotropicTurbulence`, `api / Generator`, `api / Observables`, `api / Particles`,
    `api / Propagator`, `api / SimulationDomain`, `api / SimulationRun`, `api / State` — strict
    alphabetical order, the reverse of the claimed dependency order in every load-bearing case
    (`Cache` first instead of fourth; `State`, "the single source of truth", dead last).
  - Concretely: PAGE `api / Cache`'s `ObservablesCache` docstring says "Build it on a `FixedDomain`
    `domain`," but `FixedDomain`'s home page (`SimulationDomain`) is seven banners later.
- **Contradicts:** the api page's own claim, quoted above, about the order the reader will meet things in.
- **Description:** A cold reader who trusts the stated dependency order and reads pages in the order
  they appear meets `Cache` — which leans on `FixedDomain`, `ResolvedGenerator`/`Propagator` scratch,
  and the deposit/epoch machinery — before any of the pages that establish those objects. `State`,
  named as the one holding "the single source of truth," is the very last per-module page. The
  Notation page's Vocabulary section (page 3) pre-glosses the operational words, which softens but
  does not remove the effect: types (`FixedDomain`, `ResolvedFields`, `ResolvedGenerator`) are still
  used well ahead of their homes.

---

## Finding 2 — "Resolved" is used in the disclaimed numerical sense one page before its own gloss forbids it

- **Type:** contradiction
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: api — "the resolved-wavenumber ceiling `max_wavenumber`"
  - PAGE: notation, Vocabulary — "resolved | in `ResolvedFields` and `ResolvedGenerator`, made concrete
    as one value — **not** the numerical sense of 'resolved by the grid', which this package writes
    out in full wherever it is meant."
- **Contradicts:** the notation page's explicit house rule (quoted above) that the bare word "resolved"
  is reserved for the `ResolvedFields`/`ResolvedGenerator` sense, and that the numerical sense is always
  spelled out rather than carried by the bare word.
- **Description:** `max_wavenumber` is exactly the numerical "resolved by the grid" sense the Vocabulary
  entry says the package always writes out in full — yet the api overview page (one page earlier in
  reading order) calls it "the resolved-wavenumber ceiling," using the bare disclaimed word. A cold
  reader hits the violation before ever seeing the rule that forbids it.

---

## Finding 3 — `deposit_sample!` is named as a callable the reader must invoke, with no docstring anywhere

- **Type:** api-gap
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: api / Cache, `particles_modified!` — "A hand-run loop that repositions tracers itself must
    call this, then `record_trajectory_velocity!` to write the new values, and finally
    `deposit_sample!` to record them at the current epochs — the write alone leaves the slot stale, and
    a read of it throws."
  - Absent from the `GBGIsotropicTurbulence` Index (PAGE: api / GBGIsotropicTurbulence) — neither
    `Cache.deposit_sample!` nor any `deposit_sample!` appears among the listed exports.
- **Description:** The text tells a reader building a hand-run loop that they must call
  `deposit_sample!` as the third step after `particles_modified!` and `record_trajectory_velocity!` — a
  step the docs say is necessary or "a read of it throws." But `deposit_sample!` has no docstring, no
  signature, and no Index entry anywhere on the site. A reader following the documented recipe hits a
  dead end: the one function the recipe depends on is undocumented and unlisted. (Distinct from the
  already-adjudicated `deposit_velocity!`/`take_velocity!` finding — a different name, never
  adjudicated.)

---

## Finding 4 — "the developed-turbulence marker" used unglossed at first sight, resolved 8 pages later

- **Type:** clarity
- **Severity:** minor
- **Confidence:** high
- **Locations:**
  - PAGE: Home, Components — "the energy and dissipation diagnostics of the flow and the scalar, **the
    developed-turbulence marker**, the spectrum-derived scales"
  - PAGE: api (identical repeat) — same phrase, same lack of gloss
  - Resolved only at PAGE: api / Observables — "`derivative_skewness` — the velocity-derivative
    skewness, the classical marker of a developed cascade."
- **Description:** On the very first page, and again on the second, the reader is told `Observables`
  contains "the developed-turbulence marker" with no indication of which function this is or what it
  measures. Only on reaching the `Observables` page (the 9th banner) does the phrase resolve to
  `derivative_skewness`. A first-time reader has no way to connect the two for many pages.

---

## Finding 5 — "verbs" used as unglossed jargon for the protocol's functions, from page one

- **Type:** clarity
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: Home, Components (`Generator` bullet) — "gathered into one object, the `ResolvedGenerator`,
    which a scheme consumes through **a fixed set of verbs** rather than assembling the physics itself."
  - Recurs unglossed later, e.g. PAGE: api / Generator — "a rate that has been filled is one **the
    integrating-factor verbs** then return", "**One optimization crosses two verbs**."
- **Description:** "Verb" is used throughout as a synonym for "one of the protocol's functions"
  (`prepare!`, `velocity_rhs!`, …) but this equivalence is never stated anywhere on the site — a reader
  must infer it from context on first sight, on the home page, before any protocol has been shown.

---

## Finding 6 — "the tracer push": an ordinary word given a specific technical referent, never bound to a name

- **Type:** clarity
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: api / Cache, `ObservablesCache` Fields — "`particles_epoch` — the tracer positions' counter,
    advanced by **the tracer push**."
  - Later, PAGE: api / Particles, "Wiring tracers into a run" — "`advance!` **pushes** it every
    iteration and records the Lagrangian sample" — the verb form recurs but is still never explicitly
    equated with `advect!`.
- **Description:** "Push" reads as ordinary English ("the tracer push" = "advancing the tracers"), but
  it is never explicitly bound to the documented verb that does it (`advect!`). A cold reader meeting
  "the tracer push" on the Cache page (well before the `Particles` page that explains `advect!`) has no
  way to confirm this is the same operation, only a plausible guess.

---

## Finding 7 — "epoch" names both the running counter and the value stamped on a slot

- **Type:** clarity
- **Severity:** nit
- **Confidence:** medium
- **Locations:**
  - PAGE: notation, Vocabulary — "epoch | a counter of changes to the state... A slot is readable
    exactly when its own epoch equals the counter it depends on."
  - PAGE: api / Cache, `ObservablesCache` Fields — "`fields_epoch` — the resolved fields' **counter**:
    advanced by every completed step..." vs. "`velocity_epoch` — **the epoch each slot's value belongs
    to**, or a sentinel..."
- **Description:** The Vocabulary entry's own wording ("its own epoch equals the counter") already
  shows the word doing double duty: the ticking counter (`fields_epoch`) and the frozen value a slot
  was stamped with (`velocity_epoch`) are both called "epoch," disambiguated only by which identifier
  prefix a reader happens to be looking at. The definition is careful enough to survive a close read,
  but a skimming reader can easily conflate "the epoch" (a slot's stamp) with "the epoch counter."
