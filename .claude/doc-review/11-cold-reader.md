# Cold-reader panel — first-year turbulence grad student, top-to-bottom pass

Hat: a first-year turbulence grad student, comfortable with Fourier methods and Julia, new to this
package. Findings below are ordered most-severe first. Each names the PAGE (banner) and, where useful,
the point in my top-to-bottom read where I first met the term.

---

## Finding 1 — `epoch` used with zero gloss on the very first page

**Type:** clarity · **Severity:** major · **Confidence:** high

**Locations:**
- PAGE: Home, Quick start comment (first page, first code block): "each stamped with the epoch of the
  state they were computed from"
- PAGE: notation, Vocabulary (where it is actually defined, many screens later): "epoch | a counter of
  changes to the state, one per dynamical factor"

**Description:** The very first code example on the Home page uses "epoch" as if the reader already
knows the term — no gloss, no apposition, nothing. The word is not defined anywhere until the
Vocabulary table on the `notation` page, several pages later. A first-time reader has no way to know
whether "epoch" means a wall-clock time, an iteration count, or (the actual meaning) a per-slot
freshness counter that is *not* the same as the step count. This is exactly the class the Vocabulary
page itself warns about ("Not an iteration number") — but the warning arrives too late for the reader
who met the word on page one.

---

## Finding 2 — the same cache-slot state is given three different names

**Type:** contradiction · **Severity:** major · **Confidence:** high

**Locations:**
- PAGE: api / Cache, `ObservablesCache`: "a read that finds a stale, taken, or never-deposited slot"
- PAGE: api / Cache, `velocity_physical`: "the slot is mid-iteration scratch, stale, or was never
  deposited"
- PAGE: api / Cache, `ObservablesCache` Fields list: "a sentinel (never deposited / in use as scratch)"

**Contradicts:** all three passages describe the identical three-way state a slot can be in (fresh /
being-used-as-scratch-mid-iteration / never-filled), on the same page, within ~50 rendered lines of
each other — but the middle state is named "taken" once, "mid-iteration scratch" once, and "in use as
scratch" once, with no sentence ever stating these are the same thing.

**Description:** This matters specifically because the doc says the thrown `ErrorException` "names...
which of the three states it is in" — i.e. this taxonomy is meant to be a fixed, learnable vocabulary a
reader will see in an actual error message. Three unlinked synonyms for one state undermines exactly
the "the message names the slot and which of the three states it is in" promise.

---

## Finding 3 — tracer / particle / trajectory: three overlapping words, never disambiguated

**Type:** clarity · **Severity:** major · **Confidence:** medium-high

**Locations:**
- PAGE: notation: "$\boldsymbol{X}(t)$ | the position of a tracer particle"
- PAGE: api / Particles, module doc: "`Tracers` — the tracer set", "`AbstractParticleIntegrator`,
  `EndpointHeun` — the trajectory time-integration schemes"
- PAGE: api / Particles, `AbstractParticleIntegrator`: "the Lagrangian counterpart of the field side's
  `AbstractIntegrator`"

**Description:** The module is `Particles`, its one concrete type is `Tracers`, the notation table
calls the same object a "tracer particle", the accessors are `particle_positions` /
`particle_velocities` / `number_of_particles`, the integrator family is `AbstractParticleIntegrator`
but is introduced in prose as "the trajectory time-integration schemes," and the buffer type is
`ParticleIntegratorBuffers` holding a "predictor" read via `particle_velocities`. A cold reader cannot
tell whether "tracer," "particle," and "trajectory" are three synonyms, or whether "particle" is meant
to be the forward-looking general term (for a not-yet-built inertial-particle family) and "tracer" the
concrete massless case — the site never states this distinction anywhere, so the naming just reads as
inconsistent.

---

## Finding 4 — "seam" is used as settled jargon but is never introduced anywhere

**Type:** clarity · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / Propagator, `IFLowStorageRK3`: "it adds `nonlinear`, the dealiasing seam's assembly
  register"
- PAGE: api / phenomenology / Phenomenology: "`fit` is the (future) seam for fitting a parametrization
  to measured data"
- PAGE: api / phenomenology / Scalings, `Li2008`: "the seam the run layer uses to set the viscosity
  from the grid and target energy"

**Description:** Unlike "deposit," "slot," "epoch," "register," and "observation" — each given a
Vocabulary entry — "seam" is never defined anywhere on the site, yet is reused across two unrelated
modules (Propagator, Phenomenology) as if it were an established term of art. "The dealiasing seam's
assembly register" is particularly opaque on first encounter: nothing on the Propagator page says what
a "seam" is or why dealiasing has one.

---

## Finding 5 — "the resolution criterion" is used, unglossed, in the very first Quick Start

**Type:** clarity · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: Home, Quick start comment: "a 64³ forced-stationary run; ν is chosen from the resolution
  criterion"
- PAGE: api / SimulationRun, `Simulation` (many pages later): the actual definition, $\kappa_{\max}\eta$
  set via `κ_max_η`

**Description:** The very first runnable example tells the reader that ν is "chosen from the resolution
criterion" with no forward pointer and no inline gloss — a reader has to already know DNS resolution
practice ($\kappa_{\max}\eta$) or keep reading for many more pages before the phrase cashes out into a
concrete quantity.

---

## Finding 6 — a circular definition: "a budget is a callback that accumulates what it budgets"

**Type:** clarity · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / SimulationRun, `run!`: "Stopping is the observation's decision on observables, never a
  run option: a budget is a callback that accumulates what it budgets."

**Description:** The noun "budget" is defined using its own verb form ("what it budgets"), which is not
actually informative on first read — the reader only understands the concept from the three examples
that follow (time span, step count, eddy-turnover count), not from the definition sentence itself.

---

## Finding 7 — "sugar" used as a bare technical noun at its first appearance

**Type:** clarity · **Severity:** nit · **Confidence:** low-medium

**Locations:**
- PAGE: api / SimulationRun, module doc: "`StationarityCriterion`, `warmup!` — the packaged
  spin-up-to-stationarity observation, and its one-line sugar."

**Description:** "Sugar" (syntactic sugar) is common programmer shorthand, but is never spelled out on
this user-facing site and is used here as a load-bearing noun ("its one-line sugar," later "its
sugar") before the reader has seen `warmup!`'s own docstring, which does explain the relationship. A
first-year physicist reader (not necessarily a seasoned Julia programmer) may stumble on the word.

---

## Finding 8 — `PointSet` / `VectorPointValues` / `ScalarPointValues` given no provenance note

**Type:** clarity · **Severity:** nit · **Confidence:** low

**Locations:**
- PAGE: api / Particles, `Tracers` Fields: "`position_points` — a `PointSet` wrapping `positions`"
- PAGE: api / Particles, `interpolate_at_particles!`: "a `VectorPointValues` for the velocity, a
  `ScalarPointValues` for the scalar"

**Description:** `FixedDomain`'s Fields section explicitly flags its `GBGPeriodicFields`-sourced types
("The machinery types below are `GBGPeriodicFields` objects, each linked to its own documentation") so
the reader knows not to expect a local definition. `PointSet`, `VectorPointValues`, and
`ScalarPointValues` on the Particles page get no equivalent flag (only an indirect mention that
`PointSet` is "the form `GBGPeriodicFields`' interpolation takes"), so a reader has to infer rather than
be told that these three types are external and out of scope for this site.

---

## Finding 9 — "artifact" used as the mirror-opposite of "measurable" without being anchored as a pair

**Type:** clarity · **Severity:** nit · **Confidence:** low

**Locations:**
- PAGE: api / Forcing, `BandRescaling`: "The band's energy is then an artifact of the forcing, while
  $k$ remains a measurable of the flow." … "Here $k$ is the artifact and the band is free."

**Description:** "Artifact" (a forcing-induced value, not a genuine physical quantity) versus
"measurable" (a legitimately physical quantity) is a real and useful distinction that recurs through
the whole `BandRescaling` docstring, but it is never named as a pair anywhere on the site — the reader
has to reconstruct the opposition purely from these two sentences, on first encounter, with no
signpost that this vocabulary will matter for the rest of the docstring (and again on the `Simulation`
default-forcing caveat).

---

## Summary

Strongest, most actionable items: **Finding 1** (`epoch` on the front page with no gloss) and
**Finding 2** (three names for one cache-slot state) — the latter is a genuine same-page internal
inconsistency, not just a pacing issue. **Finding 3** (tracer/particle/trajectory) is the broadest: it
touches an entire module's naming and is never resolved anywhere a user can read. The rest are smaller
clarity nits consistent with an otherwise unusually well cross-referenced and self-aware set of docs —
most other candidate terms I traced ("deposit," "slot," "register," "observation," "resolved," "front
door") *are* properly glossed in the `notation` page's Vocabulary before or reasonably close to their
first real use.
