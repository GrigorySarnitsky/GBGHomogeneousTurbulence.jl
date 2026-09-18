# Cold-reader hat — first-year turbulence grad student, first pass top-to-bottom

Substrate: rendered-docs-only manuscript (`manuscript-siteonly.md`). Reading order followed for
"first encountered" judgments is the site's own stated reading order (Home → Notation →
API overview → Decision log → Phenomenology → API Reference in the order the API overview page
gives: SimulationRun, SimulationDomain, State, Observables, Cache, Forcing, Generator, Propagator,
Particles, Phenomenology sub-pages) — not the manuscript's alphabetical `api/*` ordering, which the
adjudication file records as an extraction artifact. Findings that depend only on that manuscript
artifact are not raised here (per the adjudicated list).

Candidates considered before the cap: ~26. Findings kept: 10.

---

## Finding 1 — `StochasticOU` is discussed as a live, working forcing but is absent from every
current-state list

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: Home, "What it solves" (work-in-progress note): "the forcing menu `NoForcing`, `Linear`,
  `ConstantPower`, `VarianceController` (the default), and `VarianceRescaling`" — no `StochasticOU`.
- PAGE: api / GBGIsotropicTurbulence, `## Index` — the `Forcing.*` entries list `AbstractForcing`,
  `ConstantPower`, `DeferredForcing`, `Linear`, `NoForcing`, `VarianceController`,
  `VarianceRescaling`, the four hooks, and the persistence pair — no `StochasticOU`.
- PAGE: api / Forcing, `write_forcing`: "`StochasticOU` stores its parameters and not its evolving
  force or random stream: a reloaded stochastic forcing resumes on a fresh stream."
- PAGE: api / SimulationRun, `write_simulation` / `read_simulation`: "A stochastic forcing's
  evolving state is deliberately not stored" / "The one deliberate divergence is a stochastic
  forcing, which resumes on a fresh stream."

**Contradicts:** the Home page's explicit current forcing menu and the module index both omit
`StochasticOU` entirely (and the decision log elsewhere calls it "archived," e.g. "the archived
`StochasticOU`'s prepare phase"), while the `write_forcing` / persistence docstrings talk about it
in the present tense as an ordinary, usable strategy with its own checkpoint behaviour.

**Description:** A cold reader hits the name `StochasticOU` with no home page, no entry in the
Forcing module's own contents list, and no listing in the package index, yet two docstrings
describe its runtime and persistence behaviour as if it ships today. There is no way from the
rendered site alone to learn what `StochasticOU` is, how to construct it, or that it is currently
unavailable.

---

## Finding 2 — the Berendsen citation the References page says `VarianceRescaling` carries is not
in `VarianceRescaling`'s own docstring

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: decisions, `## References`: "Berendsen … (1984). … (The thermostat whose
  deterministic-rescaling limit `VarianceRescaling` is; **named there and now cited**.)" and
  "Bussi, Donadio & Parrinello (2007). … the caveat `VarianceRescaling` carries."
- PAGE: api / Forcing, `VarianceRescaling` type docstring (full text): cites only "Sullivan,
  Mahalingam & Kerr (1994, …)"; the caveat prose reads "Molecular dynamics reached the same
  conclusion about the same manoeuvre — rescaling to fix a quantity each step is the naive
  thermostat" with **no mention of Berendsen, no "no conserved quantity" language**.

**Contradicts:** the References entry's parenthetical claims that Berendsen is "named there" (in
`VarianceRescaling`) and that `VarianceRescaling` "carries" the Bussi-stated caveat, against the
actual rendered `VarianceRescaling` docstring, which names neither.

**Description:** A reader who follows the References page's promise to `VarianceRescaling`
expecting to find the Berendsen thermostat named and its ensemble caveat spelled out finds neither —
only the Sullivan/Mahalingam/Kerr citation and an unattributed "molecular dynamics reached the same
conclusion" sentence. The decision log (§2026-07, forcing hooks entry) shows the caveat text was
once drafted for this docstring; it appears not to have landed in the shipped copy.

---

## Finding 3 — `FlowConditions` used in `Forcing` before it is ever defined

**Type:** clarity
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: api / Forcing, module intro (first encounter, reading order position 6 of 9): "The two
  fields are forced independently: `FlowConditions` takes a separate `velocity_forcing` and
  `scalar_forcing`, so a run can force one, both, or neither."
- Also: `AbstractForcing`, "One instance per forced field": "`FlowConditions` throws an
  `ArgumentError` rather than let that happen."
- PAGE: api / Generator (reading order position 7, the definition site): "`FlowConditions` — the
  physical conditions the right-hand side is built from (the viscosity, the Schmidt number, the
  forcings)."

**Description:** `FlowConditions` is a named package type, not a generic English phrase, and it is
used twice in the `Forcing` module page — including in a sentence explaining *why* an
`ArgumentError` is thrown — a full module before its own docstring exists. A reader following the
API overview's stated reading order (SimulationRun → … → Forcing → Generator → …) meets the name
with no way yet to know it is a struct bundling `viscosity`, `schmidt`, and the two forcings.

---

## Finding 4 — `finalize!` collides with Julia's own `finalize`/`finalizer` vocabulary, with no
acknowledgment

**Type:** clarity
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: api / Generator, module contents: "`finalize!` — apply the post-step forcing projections;
  the iteration closes later, at the deposit."
- PAGE: api / Generator, `finalize!` docstring: "Close a step of the generator: apply each of its
  forcings' post-step projections … to the advanced state."

**Description:** For a Julia-fluent reader (this hat's stated persona), `finalize`/`finalizer` are
Base vocabulary for GC-triggered cleanup of an object's external resources — a very different idea
from "apply the post-step forcing projection." The decision log explicitly worked through and
documented an analogous false-cognate risk for `integrator` (the adjudicated finding notes it was
kept deliberately, with the collision named in the log). `finalize!` gets no equivalent
acknowledgment anywhere on the rendered site, so the same class of first-encounter misreading is
left unflagged for this name.

---

## Finding 5 — `ScalarBuffers` is described but never given its own definition site

**Type:** clarity
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: api / Propagator, `IntegratorBuffers` Fields: "`scalar` — a `ScalarBuffers` for the passive
  scalar $\varphi$ when `scalar = true`, else `nothing` … Its fields mirror the per-scheme
  breakdown above, sized to the scalar: `stage1` (every scheme), `stage2` and `predictor_spectral`
  …, and `nonlinear` (`IFLowStorageRK3` only)."
- PAGE: api / GBGIsotropicTurbulence, `## Index` — no `ScalarBuffers` entry among the
  `Propagator.*` names (only `AbstractIntegrator`, `IFHeun`, `IFLowStorageRK3`, `IntegratorBuffers`,
  `allocate_buffers`, `deposit!`, `recommended_cfl`, `step!`).

**Description:** `ScalarBuffers` is named and its field layout described in prose, but it has no
`## ScalarBuffers` heading, no own docstring block, and is absent from the package index — so a
reader cannot look it up the way every other named type on the site can be looked up; its shape
must be reconstructed from one paragraph inside a different type's Fields section.

---

## Finding 6 — "scratch" and "register" are used as if interchangeable, with no stated relationship

**Type:** clarity
**Severity:** minor
**Confidence:** low

**Locations:**
- PAGE: api / Generator, `ResolvedGenerator`: "the conditions bundled with the assembly **scratch**
  its evaluations write through."
- PAGE: api / Propagator, `IntegratorBuffers`: "Each such array is a **register**: storage a scheme
  computes one stage into and overwrites at the next, holding nothing a caller should read between
  steps."

**Description:** "Register" gets a precise definition (Notation Vocabulary: "storage a component
computes one value into and overwrites at the next"). "Scratch" never gets an equivalent entry, yet
is used constantly for the same kind of object (`ResolvedGenerator`'s "assembly scratch," the
"displaced-evaluation scratch," `IntegratorBuffers`'s docstring calling itself "the … scratch the
scheme writes into" one paragraph before defining "register"). A reader is left to infer whether
"scratch" names a collection of registers, a synonym for register, or something broader.

---

## Finding 7 — `restart!` (particle-history reset) reads as a checkpoint verb next to `read_simulation`'s "restore"

**Type:** clarity
**Severity:** minor
**Confidence:** low

**Locations:**
- PAGE: api / Particles, `restart!`: "Discard whatever history `buffers` holds for the particle
  integration scheme `scheme`, so the next `advect!` starts that scheme from scratch."
- PAGE: api / SimulationRun, `read_simulation`: "**Restore** a run from the group `write_simulation`
  wrote … the next `advance!` continues the checkpointed run."

**Description:** The package's checkpoint family is consistently named `write_*` / `read_*`
("restore," in prose), so `restart!` — an unrelated, purely in-memory reset of one particle
scheme's history buffers — is the one verb on the site that sounds like it belongs to that family.
A reader skimming the index for "how do I resume a run" could plausibly reach for `restart!` first.

---

## Finding 8 — `PointSet` / `VectorPointValues` / `ScalarPointValues` are used throughout Particles
with no on-site structural description

**Type:** clarity
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: api / Particles, `Tracers`: "the tracer positions, as the `PointSet` every operation
  takes."
- PAGE: api / Particles, `interpolate_at_particles!`: "into the point-value buffer `out` (a
  `VectorPointValues` for the velocity, a `ScalarPointValues` for the scalar $\varphi$)."

**Description:** These three types gate every particle-facing call on the page (`Tracers`'
`positions` keyword, `interpolate_at_particles!`'s `out`, the two point-value allocators) but are
never shown with a field list, a shape, or a constructor on this site — only inferable from one
worked example (`PointSet([0.1 0.2 0.3; 1.0 1.0 1.0])`). This is the documented `@extref`
exception for `GBGPeriodicFields` types, but for a reader who does not already know that sibling
package, the objects driving the whole Particles page remain structurally opaque.

---

## Finding 9 — "the default" forcing (Home page) is only the velocity's default; the scalar
defaults differently

**Type:** clarity
**Severity:** nit
**Confidence:** low

**Locations:**
- PAGE: Home, "What it solves": "the forcing menu `NoForcing`, `Linear`, `ConstantPower`,
  `VarianceController` **(the default)**, and `VarianceRescaling`."
- PAGE: api / SimulationRun, `Simulation` Arguments: "`velocity_forcing` … left at `nothing` means
  the default — a `VarianceController` … and `scalar_forcing` defaults to `NoForcing()`."

**Description:** Read on its own, the Home page's "(the default)" tag on `VarianceController` reads
as *the* package default, not *the velocity's* default; a reader only learns the scalar defaults to
`NoForcing()` two pages later. Low-stakes, but it is the kind of unqualified claim a newcomer copies
forward.

---

## Finding 10 — `$G$` names two unrelated constants, disclosed but still a live collision risk in
formulas that don't repeat the disclosure

**Type:** clarity
**Severity:** nit
**Confidence:** low

**Locations:**
- PAGE: notation, "Derived scales": "$G$ | two unrelated constants wear this glyph, each bound at
  its site: the box-normalized dissipation group of Li2008 ($\approx 0.9$), and
  VarianceController's dimensionless gain."
- PAGE: api / Forcing, `VarianceController` formula: "$A(\boldsymbol\kappa,t) = \dfrac{\varepsilon(t)
  - G[k(t)-k_\infty]/t_\ell}{2k_f(t)}$" — `G` used bare, relying on the reader recalling the earlier
  disclosure or the nearby Arguments entry.
- PAGE: decisions, viscosity-derivation entry: "$\varepsilon = (k/G)^{3/2}/L$ … $G \approx 0.9$ a
  dimensionless constant" — the *other* `G`, in the same document.

**Description:** The overload is self-aware (Notation states it plainly), which is good practice,
but nothing in either formula's own docstring reminds the reader which `G` is meant at the point of
use — a reader who lands on `VarianceController`'s formula without having read Notation first (a
plausible path if they came in from a search engine or a direct link) has no local signal that this
`G` is not the grid's `Li2008` constant a few pages away.
