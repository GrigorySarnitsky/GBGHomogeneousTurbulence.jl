# Free Reader A — fresh-eyed, no-checklist pass

Read front to back: Home, api overview, architecture, decisions, notation,
observables_cache, phenomenology (+ its four API pages), and every `api/*` module page.
Six findings survived; ranked most-severe first.

---

## Finding 1 — `ObservablesCache`'s own call signature omits a keyword its Arguments list documents

**Type:** contradiction
**Severity:** blocker
**Confidence:** high

**Locations:**
- PAGE: api / Cache, "The observables cache" — the docstring's call signature:
  > `ObservablesCache(domain; scalar = false, particle_velocities = nothing)`
- Same docstring, four lines later, in its own "Arguments" list:
  > `history_depth = 1` — how many Lagrangian samples the run must be able to look back
  > over, including the current one. A one-step scheme needs 1 and stores no history; an
  > `order`-step scheme needs `order`.

**Contradicts:** itself — the signature line at the top of the docstring and the
Arguments list six lines below it disagree about what keywords the constructor takes.

**Description:** This is a single docstring's signature line versus its own prose, not
two separate pages — about as internal as a contradiction can get. A reader who reads
only the code-block signature (the way anyone skimming for a call template does) will
not know `history_depth` exists at all, or that it needs to be `4` to back an
`AdamsBashforth(order = 4)` trajectory scheme. This is exactly the doc-policy's own
"every signature argument documented, enumerated from the signature" check, failing in
the least deniable way: the argument is documented, but not in the signature it is
supposedly documenting.

---

## Finding 2 — Architecture claims one trajectory scheme; a second is fully built, documented, and wired into the front door

**Type:** contradiction
**Severity:** blocker
**Confidence:** high

**Locations:**
- PAGE: architecture, §4.6: "Two axes matter: the trajectory scheme — **today the
  single second-order `EndpointHeun`**, with higher-order schemes the studied future
  axis — and the sampling-consistency axis…"
- PAGE: api / Particles, module docstring: lists only "`AbstractParticleIntegrator`,
  `EndpointHeun` — the trajectory time-integration schemes" (no mention of a second
  scheme).
- PAGE: api / Particles, "The trajectory scheme" section: `AdamsBashforth(; order = 4)`
  — "Variable-step Adams–Bashforth trajectory integration — the scheme TurTLE uses for
  its tracers, at its default order."
- PAGE: api / SimulationRun, `Simulation` Arguments: "`trajectory_scheme =
  EndpointHeun()`… Pass `AdamsBashforth()` when trajectory accuracy in time limits a
  measurement."
- PAGE: decisions: "(2026-08, user-requested) A second trajectory scheme: variable-step
  Adams–Bashforth." — a full paragraph describing it as already shipped and measured.

**Contradicts:** the architecture page's own current-state claim ("today the single…")
against the API pages' and decision log's own description of a second, fully shipped
scheme, front-door-selectable by name.

**Description:** §4.6 is prose describing the present state of the package (not a
historical decision-log entry, which the adjudication file exempts), so "today the
single second-order EndpointHeun" is a stale claim contradicted by the rest of the same
manuscript. The `Particles` module docstring — which is supposed to be the map, "a
linked one-liner per operation" — independently omits `AdamsBashforth`,
`MultistepBuffers`, `restart!`, and `history_depth` entirely, even though the umbrella's
auto-generated Index (PAGE: api / GBGIsotropicTurbulence) lists all four, proving they
are exported and current. The hand-written summaries were not swept when the scheme
landed; the auto-generated index was.

---

## Finding 3 — The module include order is stated two different ways

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: architecture, §4.9 "Layout summary": "`SimulationDomain → Observables → State →
  Cache → Forcing → Generator → Propagator → Particles → SimulationRun`."
- PAGE: Home, "Components" (explicitly "listed in build order — each module uses the
  ones above it"): `SimulationDomain`, then `State`, then `Observables`, then `Cache`…
- PAGE: api, overview: "Its re-exported submodules build on one another in the order
  `SimulationDomain` → `State` → `Observables` → `Cache` → …"
- PAGE: decisions: "(2026-08, user-directed) `Observables` precedes `Cache`… **The
  include order becomes `State → Observables → Cache`**."

**Contradicts:** §4.9 says Observables before State; the Home page, the API overview
page, and the decision log's own explicit sentence ("include order becomes `State →
Observables → Cache`") all say State before Observables.

**Description:** Three surfaces (Home, api overview, and the decision log's own prose)
agree on one order; the architecture's "current state" layout summary states the
opposite order for the same two modules. Since §4.9 is a current-state section (not a
historical log entry), this is not covered by the adjudicated "decision-log entries can
describe superseded APIs" exemption — it is a live disagreement about a basic structural
fact the document otherwise treats as settled.

---

## Finding 4 — `ConstantPower`'s band kernel: "lazy, nothing stored" contradicts the decision log's "materialized indicator"

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: decisions, "(2026-08) The frame compresses to zero field-scale arrays…":
  "`Linear` and `ConstantPower` **keep one materialized real indicator each** for the
  rate fill."
- PAGE: api / Forcing, `ConstantPower` "Fields": "`band` — the band-pass kernel,
  **lazy**: the per-stage source both weights the band observable with it and convolves
  against it, so **no indicator array is stored**."

**Contradicts:** the decision log's explicit claim that `ConstantPower` materializes one
real indicator array versus the API docstring's explicit claim that its band kernel is
lazy and stores nothing.

**Description:** These are opposite claims about the same object's residency. Notably,
`Linear`'s own Fields section ("`indicator` — the band indicator as a real array")
*does* match the decision log, so this isn't a house-wide naming quirk — it is
specifically `ConstantPower`'s docstring that disagrees with the record of what the code
does, either because the docstring was never updated after the lazy-kernel refactor, or
because the decision log entry is itself wrong about which forcings kept a materialized
indicator.

---

## Finding 5 — `allocate_buffers`'s documented signatures omit the 3-argument form `MultistepBuffers` says to call

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: api / Propagator, `allocate_buffers` — the full, dedicated signature list for
  this function:
  > `allocate_buffers(scheme, domain; scalar = false) -> IntegratorBuffers`
  > `allocate_buffers(scheme, tracers) -> ParticleIntegratorBuffers`
- PAGE: api / Particles, `MultistepBuffers`: "Build it with
  `allocate_buffers`**`(scheme, tracers, cache)`**; a run builds it for you."

**Contradicts:** the home docstring for `allocate_buffers` enumerates exactly two call
forms; a third form (three positional arguments) is invoked by name in a different
page's docstring and is never listed at its own home.

**Description:** `allocate_buffers` is the one function whose docstring is supposed to
be the single source of truth for every one of its methods (the corpus's own
"one docstring per generic, home documents every method" rule). A reader who looks up
`allocate_buffers` to see what it can be called with will not learn that a
three-argument, cache-taking overload exists — they would only discover it by first
reading `MultistepBuffers`'s docstring and noticing the call template embedded there.
This is the same AdamsBashforth-landing sweep gap as Finding 2, but a distinct failure
mode (a signature omission, not a stale prose claim).

---

## Finding 6 — "uniform-mean-gradient scalar mixing" named as a supported System, with no forcing or mechanism anywhere that implements it

**Type:** organization / clarity
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: architecture, §3: "The System: the flow scenario — forced homogeneous isotropic
  turbulence, freely decaying turbulence, **uniform-mean-gradient scalar mixing**, and
  (a deferred frame, §7) homogeneous shear."

**Description:** In the same sentence, "homogeneous shear" is explicitly flagged as a
deferred frame with a §7 pointer; "uniform-mean-gradient scalar mixing" carries no such
flag, reading as an already-available scenario alongside forced/decaying HIT. But no
mean-scalar-gradient production term appears anywhere else in the manuscript: the
scalar's right-hand side (`scalar_rhs!`) is only advection plus diffusion plus a forcing
source, `FlowConditions` carries no gradient parameter, and none of the five `Forcing`
strategies mentions a mean gradient. If this System is genuinely realizable today
(e.g., as some combination of existing pieces), the architecture should say how; if it
is aspirational like homogeneous shear, it should carry the same deferred marker rather
than sitting unmarked in a list of built scenarios.
