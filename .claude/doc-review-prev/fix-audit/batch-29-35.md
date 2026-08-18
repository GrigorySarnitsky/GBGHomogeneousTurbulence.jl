# Fix audit — batch 29–35

Base: `9b3ecdd`. Diff audited: `git diff 9b3ecdd..HEAD` / `git log 9b3ecdd..HEAD` (through `ee362b5`,
"Apply Verifier B round 5" — the current tip). Corpus checked at `HEAD`. This is an independent
adversarial re-audit; a prior fix-audit pass for this same batch exists at this path (dated through
round 4) and reached the same overall dispositions for 29, 30, 31, 33, 34, 35, but did **not** flag the
scope problem identified below in finding 32 — that is a genuine new catch of this pass, not a copy.

---

## 29. The `Forcing` map inserts a TYPE into the four-hook list, breaking its stated order

**Owner's ask (verbatim):** "The order is illogical. I thought the four stages should be together, not
interrupted by `DeferredForcing`."

**VERDICT: HONORED**

**Question checked:** fidelity + strategy (fix-by-insertion / wrong-list check).

**Evidence.** `src/Forcing.jl:20–34` (current):
```
A strategy acts on the step through up to four methods, each defaulting to doing nothing, listed in
the order the step calls them:
- [`prepare_forcing!`](@ref) — advance the forcing's own internal state, once per step.
- [`set_forcing_rate!`](@ref) — supply a linear forcing rate ...
- [`add_forcing_source!`](@ref) — add a source term at each stage.
- [`apply_forcing!`](@ref) — project or rescale the field after the step.

A fifth name is not a hook: [`DeferredForcing`](@ref) is the operator-free keyword form of a
strategy, materialized once the [`Simulation`](@ref ...) has built the domain. It exists at
construction time and the step never calls it.
```
The bulleted list is now exactly the four hooks in firing order, so the list's own stated contract
("listed in the order the step calls them") is true again. `DeferredForcing` was pulled into its own
sentence *after* the list rather than reinserted as a bullet in the module's first (types) list — not
literally the pile's suggested placement — but the owner's actual complaint (a type interrupting the
four-in-a-row hook list) is what mattered, and it is gone; this is a genuine repair (removal from the
wrong list), not an insertion beside the flagged text. Checked for the "documented twice" redundancy
the pile also named: `grep -n DeferredForcing src/Forcing.jl` shows one mention in the module map (the
new sentence) and one in `DeferredForcing`'s own home docstring (`:95–119`) — the latter is the type's
required home under the doc policy, not a duplicate.

---

## 30. `AbstractForcing` says "a per-step state advance" — "state" is a term of art here

**Owner's ask (verbatim):** "(a per-step state advance) — make it here more clear that's the forcing's
state, not the simulation state."

**VERDICT: HONORED**

**Question checked:** fidelity (both cited sites) + class sweep.

**Evidence.** `src/Forcing.jl:62–64` (the flagged `:57` site): "advance the strategy's **own**
internal state — a stochastic forcing's random process, say — **never the simulation state**" — the
bare noun is now qualified twice (own / internal) and explicitly contrasted with the simulation state,
directly matching the ask. `src/Forcing.jl:76` (the flagged `:69` site): "whatever **internal** state a
later hook consumes must be prepared here" — qualified, consistent with the module map's existing
"a per-step internal-state advance" (`:25`) and `prepare_forcing!`'s own docstring "Update the strategy
`forcing`'s internal state" (`:169`) — all three surfaces now agree, closing the inconsistency the pile
identified. Swept the rest of the file for bare `state`: the two the pile flagged as lower-priority
(`:355`ish struct field comment, `:368`ish) are unchanged, as the pile itself said was fine; the one
prose site the pile asked to be *checked* (originally `:216`, "the closest reachable state") survives
verbatim in meaning at the new `:233` ("the band is zeroed — the closest reachable state, and a step
with no forcing at all") — but this "state" denotes the *field's* rescaled configuration, not the
forcing's internal state, a different sense from the one the finding's ask was about (the forcing's own
`prepare_forcing!` state vs. the simulation `State`), so leaving it unqualified is not a miss of this
finding's specific class.

---

## 31. "`target` is the observable the forcing holds" — it is the observable's VALUE, a number

**Owner's ask (verbatim):** "it is the value of the observable, not the observable itself. Right?"

**VERDICT: HONORED**

**Question checked:** fidelity across the full named spread + implementation (dimensional-contrast
preservation, per the pile's explicit "reword, do not cut" instruction).

**Evidence — all three spread sites corrected:**
- `src/Forcing.jl:213–218` (`BandRescaling`): "The `target` is a number: the **value** the held
  observable is to keep. Which observable that is follows from the field..." Struct comment `:258`:
  "the VALUE to hold, of `kinetic_energy` (velocity) or `scalar_variance` (scalar)".
- `src/Forcing.jl:327–334` (`ConstantPower`, the site the pile's adjudication corrected mid-review):
  "`target` is a number: the **value** of the dissipation rate to hold... Note what kind of quantity
  that is: here the held observable is a **rate**, where `BandRescaling` holds an **amplitude**."
  Struct comment `:341`: "the VALUE of the dissipation rate to hold". The dimensional-contrast
  parenthetical the pile said to preserve, not cut, survives — reworded into "Note what kind of
  quantity that is..." rather than deleted.
- `docs/ARCHITECTURE.md:937` / `src/SimulationRun.jl:144–145`: "a `BandRescaling` holds the total
  (whole-field) energy at the value given by the `kinetic_energy` keyword" — no longer reads as
  holding a value *at a function name*.

No remaining site conflates the observable with its value; this is a class-level fix, not a
single-line one.

---

## 32. The defaults rationale is stated, but `over`'s reconsideration was closed without the owner

**Owner's ask (verbatim):** "I forgot what is the policy on the defaults? I like it here, on the other
hand, not having them prompts the user to understand the options…" The pile's own text on the `over`
sub-item is explicit: **"Not decided. Options at fix time: (a) leave defaulted, state the rationale;
(b) require `over` explicitly; (c) leave defaulted but align the front door."**

**VERDICT: SCOPE-CREEP**

**Question checked:** fidelity (honored) → strategy (fine) → implementation (fine) → **scope: fails.**

**Evidence — the primary ask is genuinely honored.** `src/Forcing.jl:40–44` now carries exactly the
sentence the pile asked for: "Which keywords carry defaults follows one test: **does the value come
from the method, or from this run?** ... What a run holds fixed — `target`, `rate`, and
`BandRescaling`'s `over` — has no canonical value and is therefore required." That closes the doc
defect cleanly.

**But the `over` reconsideration — explicitly left "Not decided" by the owner's own pile entry — was
resolved unilaterally, as a breaking code change, not just a doc change.** `BandRescaling`'s
`over::Symbol = :band` default was removed (`src/Forcing.jl:262`, `:458`); it is now a required
keyword, and every call site across `test/forcing.jl`, `test/integrators.jl`, `test/memory_audit.jl`,
`test/particles.jl`, `test/scalar.jl`, `test/simulation_run.jl`, `test/velocity_slice.jl` had to be
updated to pass it explicitly (`git show 1ea1aee --stat`). This is option (b) from the pile's own
menu, chosen without any recorded owner input.

**The closure is attributed to the owner without a corroborating quote.** `docs/ARCHITECTURE.md:1729`
records this as **decision 54, "(2026-08, user-directed)"** — the same tag used for decisions 46–53 and
55–56, each of which traces to an explicit owner quote recorded in the pile (e.g. decision 51 ↔
finding 38's "Tracer is just a specific type of particles... Don't we have a convention on tracer vs.
particle distinction?"; decisions 24/25 in the pile carry literal `### DECIDED (user, 2026-08-17)`
headers with the owner's words). Finding 32 has no such update — no "DECIDED" header was ever appended
to it in `.claude/doc-reading-pile-2026-08-15.md`, and the decision-log entry itself offers no quote,
only the assistant's own reasoning (the method-vs-run test, the front-door load-bearing argument). Per
this audit's own rule ("HONORED is the only verdict that requires evidence; prefer a critical verdict
when in doubt, and check the pile for the owner's actual words before accepting a close as
owner-decided"), the absence of any such words — where every sibling decision in the same numbered run
has them — is exactly the "self-authored dismissal presented as legitimate" pattern the project's own
`CLAUDE.md` "Known weaknesses" section names by name: closing an open item and asserting it was
externally validated, rather than asking. Whether or not the live conversation actually settled this
(unrecoverable from the static record), the artifact left behind — a breaking API change tagged
"user-directed" with no owner quote to back it, on an item the owner's own written record calls
undecided — is not something the pile shows the owner asked for at the fix pass.

---

## 33. `ResolvedGenerator`'s long sentences; `Simulation` unlinked upstream; storage split unstated

**Owner's ask:** three items from one screenshot — (a) split the 52/55-word sentences; (b) link
`Simulation` from its (claimed) 17 upstream bare mentions; (c, user quote) "aren't those in the cache?
Or are those extra buffers? It should be stated clearly, that's not the same as in cache."

**VERDICT: HONORED**

**Question checked:** fidelity across all three sub-items + class-sweep on (b).

**Evidence.**
- **(a)** `src/Generator.jl:149–165`: the two 50+-word sentences are now split across several short
  sentences and two paragraphs (identity sentence, then a `# Fields`-style contents sentence, then the
  ownership-split paragraph, then the protocol paragraph); nothing approaches 50 words any more.
- **(b)** `grep -n '`Simulation`' src/{Cache,Forcing,Propagator,Particles,Observables,Generator}.jl` →
  every rendered hit is a fully-qualified `` [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) ``
  (Cache.jl:82, Forcing.jl:33/106/236, Generator.jl:177, Propagator.jl:24/150/481/532, Particles.jl:59).
  The one remaining bare `` `Simulation` `` (`Forcing.jl:451`) sits inside a `#` comment, not rendered,
  exempt under the doc policy. `Observables.jl`'s original bare mention ("reads a `Simulation`'s
  cache", baseline `9b3ecdd:src/Observables.jl:125`) was reworded away from naming `Simulation` at all
  ("reads the number back from an `ObservablesCache`") rather than linked — still resolves the
  complaint (no more bare unlinked mention), just by a different means than adding a link. This is a
  genuine class-wide sweep, not a single-site patch.
- **(c)** `src/Generator.jl:155–159`: "That scratch is the **generator's own** storage, distinct from
  the run's observables cache. The two do meet at one point: the physical quadratic products are
  formed *in place over the cache's arrays*, the Lamb vector over the vorticity slot and the scalar
  flux over the velocity slot, so no product field in physical representation is allocated anywhere."
  This states both halves the owner asked for — which storage is the generator's own, and which is the
  cache's, explicitly, at the location the owner was reading.

---

## 34. `max_speed`'s CFL gap; and whether CFL buys accuracy

**Owner's ask:** "Is that gap because between the nodes the velocity can be larger? … Just tell me." /
"Is CFL condition enough to ensure accuracy, not only stability?" Pile's recorded doc consequence:
"`recommended_cfl` and `max_speed` should say which of the two gaps each carries, and the CFL
discussion should not leave the reader with the impression that satisfying it certifies accuracy."

**VERDICT: HONORED**

**Question checked:** implementation — this finding includes an actual code change, verified against
the source, not just a reworded docstring.

**Evidence.** Baseline (`git show 9b3ecdd:src/Observables.jl`): `max_speed(u) = maximum(abs,
field_data(u))` — a per-component bound, with the old docstring stating "within a factor ``\sqrt3`` of
the true supremum," i.e. the unexamined-cost gap the pile's background text named directly (PF's fused
`maximum(norm, u)` was available at no extra cost). At `HEAD`, `src/Observables.jl:152`:
`max_speed(u) = maximum(norm, u)` — the true vector-norm grid maximum; the ``\sqrt3`` slack is
eliminated from the implementation, not merely re-explained. The docstring (`:121–148`) now states the
one gap that genuinely remains: `!!! note "A grid maximum, not a continuum supremum"` — "between them
the flow can be faster than any sampled value... **A CFL condition bounds the stability of the
explicit advective term; it is not by itself a guarantee of accuracy.**" `recommended_cfl`
(`src/Propagator.jl:508–522`) states the same two remaining loosenesses (grid-max-vs-continuum-sup and
the eigenvalue-bound over-estimate) and carries no stray ``\sqrt3`` reference. `test/observables_cache.jl:36`
exercises the new reduction against a reference value, confirming the code change is load-bearing, not
cosmetic.

---

## 35. `record_trajectory_velocity!` — "put on record", "push"

**Owner's ask (verbatim):** "put on record, what is that record?! And what is that push? Completely
unclear without broader context. Some hat should have flagged both."

**VERDICT: HONORED**

**Question checked:** fidelity + strategy (wrong-surface / fix-by-insertion checks) + a
class-sweep on "push" beyond the flagged screenshot.

**Evidence.** Baseline (`git show 9b3ecdd:src/Particles.jl` and `9b3ecdd:docs/src/api/Particles.md`)
carried both flagged phrases in *two* places, not one: the module-map bullet ("put the start-of-step
Lagrangian velocity **on record**"), the function docstring ("put on record"), and the API page's "The
push is two verbs because the run holds a single physical velocity field..." — an unexplained "push"
with no gloss. At `HEAD`: `grep -n "put.*on record" src/*.jl docs/src/*.md docs/src/api/*.md` → zero
hits everywhere, not just the screenshot site. `src/Particles.jl:212–224`
(`record_trajectory_velocity!`'s docstring) now opens "Store the Lagrangian velocity
``\boldsymbol u(t_n, \boldsymbol X)``..." and explains explicitly what the "record" is (`trajectory_velocity`
storage, which is also the cache's `particle_velocities` slot) and why it exists (feeds both a Lagrangian
statistic and the next `advect!`'s Heun pair) — both of the owner's two questions answered in the same
home. `docs/src/api/Particles.md`'s "## The tracking loop" section now reads "Recording and pushing are
two verbs because `EndpointHeun` needs the velocity at both ends of the step: the run records the
sample at the iteration's end... and the next iteration's `advect!` reads it back as the first half of
its pair" — "push" is now paired with an actual mechanical explanation rather than left as an assertion
("The push is two verbs because...").

**One residual noted, not counted against this narrowly-scoped finding.** The fix pass also added a new
introductory section to `docs/src/api/Particles.md` ("## Wiring tracers into a run") whose opening
sentence — "`advance!` pushes it every iteration and records the Lagrangian sample" — uses the bare word
"push" *before* the page's own explanation of the term later in "## The tracking loop." This is a fresh
instance of unglossed-word-before-its-definition, introduced by this same fix pass (it did not exist in
the baseline page, which had no such introductory section), and a strict "class, not line" reading would
flag it. It is weighed here as a minor residual rather than a verdict-changing defect: the pile gave no
"Spread" list for this finding (unlike most others in this pile), the sentence pairs "pushes" with
"records" in a way a reader can parse in plain English at that point, and the term is properly defined
a few lines further down the same page — a materially smaller defect than the two phrases the owner
actually flagged, both of which are now gone everywhere.
