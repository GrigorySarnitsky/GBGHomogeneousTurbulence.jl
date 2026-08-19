# Doc-reading pile — user read-through round 2, started 2026-08-15 (Enteropia)

The user is reading the rendered documentation and reporting problems. **Accumulate only — no fixes
until the read-through is done.** Each entry: the user's report (verbatim where short), the surface,
the verified spread, and the class it samples.

Context: this round follows the `/check-docs` battery (commit `ebfde77`) and the 11-hat
`/check-consistency` panel (85 findings, all dispositioned, commits `0baddf3` → `b16a7df`). Round 1 of
the user's own read-through is `.claude/doc-reading-pile-2026-08-11.md` (fully discharged).

---

## Findings

### 1. The CFL ceiling should not wear the bare glyph `C` (screenshot: `docs/src/notation.md:94`)

User: "change bare C to `C_\text{CFL}` or similar. And all other places we use it."

The notation row currently reads: `` ``C`` | advective-CFL ceiling, ``\Delta t = C \Delta x/\max_i\lvert
u_i\rvert`` (the derivative-skewness isotropy constant wears the subscripted ``C_S``) ``.

The parenthetical is the tell: the glossary has to spend half its row **defending** the bare glyph
against a neighbouring constant, which is the symptom of a symbol carrying too little information. Both
are dimensionless constants named `C`; the reader must remember which one is bare. Subscripting both —
``C_{\mathrm{CFL}}`` and ``C_S`` — makes each self-describing and lets the row lose its defence.

Note this is the *same glyph* the panel's most-corroborated finding was about (four hats flagged
`ARCHITECTURE`'s bare `C` in the skewness formula, fixed to `C_S` in `0baddf3`). That fix subscripted
the *skewness* side; the user is now closing the other side. The class is one symbol, one concept.

**Spread — every site where `C` denotes the CFL ceiling (verified by grep, 2026-08-15):**
- `docs/src/notation.md:94` — the glossary row (the screenshot). The parenthetical defence goes with
  the rename.
- `src/Propagator.jl:488` — `recommended_cfl`'s identity sentence, "a conservative advective-CFL
  (Courant–Friedrichs–Lewy) ceiling ``C``".
- `src/Propagator.jl:490` — the timestep formula ``\Delta t = C \Delta x / \max_i\lvert u_i\rvert``.
- `src/Propagator.jl:493` — "stability needs this times ``C`` to stay within…".
- `src/Propagator.jl:498` — ``C \lesssim 0.83``, and the `0.5` / `0.25` values that follow it.
- `docs/ARCHITECTURE.md:374` — §4.5, "its conservative advective-CFL ceiling ``C``".
- Also check at fix time (prose, no math span, so grep-invisible): `ARCHITECTURE.md:640` ("near the CFL
  ceiling"), the `Simulation` docstring's `cfl` keyword, and `advance!`'s `dt` discussion — those name
  the concept without the glyph and may not need changing, but should read consistently with it.

**Decision to settle at fix time:** the exact spelling. ``C_{\mathrm{CFL}}`` matches the house
multi-letter-subscript idiom (`\kappa_{\mathrm{Ny}}`, `y_{\mathrm{s}}`, `\mathrm{Re}_\lambda`), which
argues for it over `C_\text{CFL}`. The code identifier stays `recommended_cfl` / the `cfl` field either
way — this is the math glyph only.


### 2. "Stamped storage" — a house coinage, and it never says stamped *with what*
### (screenshot: `docs/src/api.md:13`; same formula on `index.md:94`)

User: "Is 'stamped storage' a clear and standard term? Not a jargon invented by you?"

**Verdict: it is ours.** The standard vocabulary for this exact mechanism is a **generation counter**
(or *epoch*, *version stamp*, *validity token*) compared against a global counter to decide whether a
cached entry is current. "Timestamp" is standard; "stamp" as a bare noun is borderline; **"stamped
storage" as a noun phrase is a coinage** with no external referent a reader can look up.

Two distinct problems, and the second is the load-bearing one:
- **(a) Not standard.** A reader cannot resolve it from prior knowledge, and nothing on the page it
  appears on defines it.
- **(b) It elides its own object.** *Stamped with what?* The answer — the epoch the value belongs to —
  is stated only in the `Cache` module docstring (`src/Cache.jl:17`: "a slot's **stamp** records which
  of these instants its value belongs to"). Every other use of the word is bare. This is the same
  cold-read class as the panel's finding 11#1–#4 (a term coined in one module used bare in another).

**Self-flag:** round 1's pile explicitly recorded this risk and I did not act on it — the note under
finding 1 read *"'stamped' itself was not flagged — but when rewording, verify it survives the cold
read too (stamped with what? the step's time/index)."* I dropped "boundary" and kept "stamped". The
user has now flagged precisely the term I predicted and left standing. **Do not carry a term through a
rewrite just because it was not the one being complained about.**

**Spread — every site (verified 2026-08-15):**
- `docs/src/api.md:13` (the screenshot) and `docs/src/index.md:94` — the two summary bullets.
- `src/Cache.jl:1` (module comment), `:5`, `:13` (module docstring), `:55` (`ObservablesCache`).
- `src/GBGIsotropicTurbulence.jl:18` — the umbrella comment map.
- `src/State.jl:44` — "the stamped slots of the `ObservablesCache`".
- `src/SimulationRun.jl:192` — the `Simulation` field comment, "the stamped observation cache".
- `docs/ARCHITECTURE.md:202`, `:1445`.
- `CLAUDE.md:40` — the module map (update in the same pass).

**Direction to settle at fix time** (do not decide unilaterally — it is a vocabulary decision like
decision 48's): either say what the stamp *is* on first use in each summary ("each value tagged with
the iteration it belongs to, so a stale read is refused"), or adopt the standard word outright
(*epoch-tagged* / *generation-stamped*). The `Cache` page's own definition survives either way; the
`stamp` field names in the struct are a separate, code-level question.


### 3. The overview bullets describe contents, not identity — and the Generator bullet explains a
### mechanism that has no business in an overview (`docs/src/api.md:15`, `index.md:101–103`)

User: "What the point of listing how it gets the physical fields? Is that what the module is? Also, is
the docstring justified in its length? It looks it just lists what it has… it should list classes with
examples, not provide an exhaustive export list."

Three separable complaints; the first is the sharpest.

**(a) The recovery clause should not exist.** The bullet closes with *"The physical fields its assembly
consumes … are recovered by the source-preserving `to_physical!` scratch arity of `GBGPeriodicFields`
and by `vorticity_physical!`."* That is a statement about **how the module obtains its inputs** —
plumbing, and moreover plumbing that lives in two *other* modules. An overview bullet answers *what is
this module*; the recovery route is neither its identity nor its interface. Delete, do not reword.

**SELF-FLAG — this is a regression I introduced.** Round 1's finding 3 flagged the *predecessor* of
this clause ("The physical-representation recoveries it consumes live with the State.") for unclear
referents. In `89a0d48` I replaced it with a **longer, more precise** sentence about the same
irrelevant subject. I fixed the defect that was named (ambiguous "it", colloquial "live with") without
asking the prior question — *should this sentence be here at all?* The clause went from 12 words to 37.
**Named failure mode: repairing the stated defect while preserving the wrong subject.** Round 2's
finding 2 is the same shape (carrying "stamped" through a rewrite); two instances in one round makes it
a class worth guarding, not a slip.

**(b) Length is not justified, and it is measurable.** Word counts of the `api.md` bullets, which all
do one job:

| bullet | words | | bullet | words |
|---|---|---|---|---|
| `Generator` | **78** | | `Cache` | 57 |
| `Observables` | 48 | | `Phenomenology` | 38 |
| `State` | 35 | | `SimulationRun` | 34 |
| `SimulationDomain` | 26 | | `Forcing` | 16 |
| `Particles` | 16 | | `Propagator` | 15 |

`Forcing`, `Propagator` and `Particles` show the target register in 15–16 words. `Generator` runs 5×
that, and `Cache`/`Observables` are also inflated — every one of the long ones is long because it
enumerates.

**(c) The class ruling from round 1 extends to every bullet.** Round-1 finding 2 established
"classes with examples, not an exhaustive export list" for the `Observables` bullet. The user is now
generalizing it: it governs the whole Components/overview list on **both** pages. `Generator` currently
enumerates rotational-form RHS + dealiased + Leray-projected + scalar advection + integrating factor +
`ResolvedGenerator` + `FlowConditions` + its three contents + assembly scratch + protocol — a contents
list where an identity belongs.

**Spread:** `docs/src/api.md:10–19` (all ten bullets, `Generator` worst) and `docs/src/index.md:86–110`
(the Components list, same bullets in the same register). The two lists must stay consistent with each
other, so treat them as one surface. The per-module docstrings and the API pages' `@docs` blocks remain
the exhaustive homes and are untouched by this.


### 4. "The forthcoming Eulerian + Lagrangian statistics" — wrong owner, on four surfaces
### (screenshot: `src/GBGIsotropicTurbulence.jl:35`, the umbrella module docstring)

User: "What do you mean forthcoming? User is responsible for calculating its statistics. Tools are
provided by GBGPeriodicFields and GBGStreamingStatistics."

**This is a category error about ownership, not a stale roadmap word.** "Forthcoming … statistics"
promises that *this package* will grow a statistics capability. It never will — and the package's own
charter says so: CLAUDE.md's division is "**PF is all field mathematics, no physics; SS is all
statistics, no physics; this package is the physics**", and ARCHITECTURE invariant 2 is "No field or
statistics machinery reimplemented." The claim contradicts the invariant two clicks away from it.

What is actually true, and what the wording should say: **IT produces the samples** — the observables
and the tracer sampling — and the **user** accumulates statistics from them with SS's estimators (and
PF's reductions). The only thing genuinely forthcoming on IT's side is the **statistics bridge**, the
sampling-to-`GBGStreamingStatistics` path, which ARCHITECTURE §7 already records correctly as a
deferred item ("the sampling-to-`GBGStreamingStatistics` path (Eulerian field samples and Lagrangian
trajectory samples in, streamed summaries out)"). So the design doc has it right and the user-facing
surfaces overstate it — the reverse of the usual staleness direction.

**Spread — the overclaim (fix these):**
- `src/GBGIsotropicTurbulence.jl:35` — the screenshot: "field sampling for the forthcoming Eulerian +
  Lagrangian statistics".
- `README.md:6` — **worst instance**: "…with Lagrangian particle tracking **and Eulerian + Lagrangian
  statistics**" states the capability as *present*, with no hedge at all. This is the repo's front page.
- `docs/src/index.md:82` — "the Eulerian and Lagrangian statistics **are being added**" (inside the
  work-in-progress admonition — the hedge is there, but the owner is still wrong).
- `src/Particles.jl:177` — `sample!`: "to gather a field along the trajectories for the forthcoming
  Lagrangian statistics".

**Adjacent, and correct — do NOT change (they name SS as the owner or name the samples, not the
statistics):** `src/Observables.jl:5` ("their statistics are to be tracked by GBGStreamingStatistics" —
a `#` comment, right owner), `src/Particles.jl:116`/`:162`, `src/Cache.jl:203`, `docs/src/api.md:17`
("`sample!` for the Lagrangian statistics" — the sample feeds them; borderline, re-read at fix time),
`ARCHITECTURE.md:625` (§7's statistics bridge, correct as deferred).

**Direction:** say what the package gives the user and who owns the rest — e.g. "…with Lagrangian
particle tracking and the field and trajectory **sampling** that feeds Eulerian and Lagrangian
statistics, which you accumulate with `GBGStreamingStatistics`." Removes the false promise, names the
real owner, and keeps §7's bridge as the one honest "forthcoming".


### 5. `recommended_cfl` is named six times in `SimulationDomain` and linked zero times
### (screenshot: `FixedDomain`'s `dealiasing` bullet, `src/SimulationDomain.jl:143`)

User: "What is that recommended_cfl? Why no link to it anywhere? User would want to know more about it
and read its docs."

Verified: **every** mention in `SimulationDomain.jl` is a bare backtick span, while `Observables.jl` and
`Propagator.jl` link the same name correctly. The asymmetry has a mechanical cause worth recording,
because it will recur for every backward cross-module reference:

> `recommended_cfl` is homed in `Propagator`, which is included **after** `SimulationDomain`. A bare
> `[`recommended_cfl`](@ref)` from `SimulationDomain` does not resolve — Documenter needs the
> fully-qualified target. `src/Observables.jl:125` already shows the working form:
> ``[`recommended_cfl`](@ref GBGIsotropicTurbulence.Propagator.recommended_cfl)``.

So the link was not *declined*; it was mechanically awkward and quietly skipped — in exactly the module
a user meets **first**, while choosing a dealiasing strategy, which is the moment the CFL consequence
matters most. (I hit this same resolution failure in the panel fix pass on `ConstantPower` and
qualified it; I did not then sweep for the class.)

**Spread — bare, all rendered, each in a different docstring (so each is a legitimate first mention
and gets its own link, per the once-per-docstring rule):**
- `src/SimulationDomain.jl:43` — `DealiasingStrategy`
- `src/SimulationDomain.jl:76` — `HouLi`
- `src/SimulationDomain.jl:110` — `PhaseShift`
- `src/SimulationDomain.jl:143` — `FixedDomain`'s `dealiasing` bullet (the screenshot)
- `src/SimulationDomain.jl:259` — `max_wavenumber`
- `src/SimulationDomain.jl:37` — a `#` comment (not rendered; align for consistency only)
- `docs/ARCHITECTURE.md:374` — §4.5 prose

**Second, wider defect this exposed — `notation.md`'s Code column is inconsistently linked.** Rows 33,
34, 35, 59, and the two RHS/factor rows link their code objects with `@ref`; the majority
(`kinetic_energy`, `dissipation`, `spectrum`, `scalar_variance`, `scalar_dissipation`,
`vorticity_physical!`, `taylor_reynolds`, `taylor_microscale`, `side_length`, `set_forcing_rate!`,
`recommended_cfl` ×2, …) are bare backticks. The glossary's whole job is to send a reader from a symbol
to the object that computes it, so the Code column is the one place where "a link earns its place" is
satisfied by *every* row. Pick one policy and apply it to the table — the sensible one is: link every
Code-column entry.

**Note the interaction with finding 1:** both `recommended_cfl` rows in that table are the CFL-ceiling
rows. Whatever `C` is renamed to, these two rows get touched anyway — do the link and the rename in one
pass.


### 6. Default-narration survives on the dealiasing surface — and it is half-applied, my error
### (screenshot: `docs/src/api/SimulationDomain.md:19` + `src/SimulationDomain.jl:44`)

User: "Shall we mention that 2/3 is the default? Or just recommended as default? Or just go with the
list, and discuss defaults at the simulation page."

**Recommendation: option (c) — no default talk on this surface at all.** Two reasons, the second
decisive:

1. **It is the round-1 ruling, and I applied it to only two of the three strategies.** Round 1 finding 6
   removed "hence an opt-in, not the default" from `HouLi`, and I extended the class ruling to
   `PhaseShift`'s "Opt-in, not the default." — both landed in `5fcb890`. But I left the *positive* form
   standing on `TwoThirds`. The corpus now says nothing about defaults for two strategies and "the
   default" for the third, which is worse than either consistent choice. **Named failure: applying a
   class ruling to the instances that matched the flagged wording (the negative form) instead of to the
   class (default-narration on a strategy type).**
2. **On this surface there is no default to speak of.** `FixedDomain`'s arguments are "All keyword, all
   required" — it demands `dealiasing` explicitly. `TwoThirds` is the default of the **`Simulation`
   front door** only (`SimulationRun.jl:69, :259`, documented at `:137`). So "the default" stated in
   `SimulationDomain` is not just narration, it is *about the wrong object* — a reader building a
   `FixedDomain` from these docs gets no default and must pass one.

Option (b) ("recommended as default") is the weakest of the three: it keeps the narration and adds a
recommendation the page cannot support, since which strategy is right is a run-level choice (band width
vs cost) that `Simulation` and `recommended_cfl` already frame.

**Spread — the default claims to remove from the dealiasing surface:**
- `src/SimulationDomain.jl:44` — `DealiasingStrategy`: "(the sharp ``2/3`` rule, **the default**)".
- `src/SimulationDomain.jl:57` — `TwoThirds`: "the lean, GPU-friendly **default**".
- `docs/src/api/SimulationDomain.md:19` — the section blurb: "the sharp ``2/3``**-rule default**".
- `docs/src/index.md:73` — "dealiased by the **default** ``2/3`` rule (other strategies are available)".
  *Judgment:* this one is on the Home page describing what a default run does, which is arguably the
  front-door context where a default IS the fact. Decide with the user; my read is it may stay.

**Keep (correct — this is where the default lives):** `SimulationRun.jl:69`, `:137` (`dealiasing =
TwoThirds()` in the keyword list), `:259`.

**Related instance of the same class, same page:** `docs/src/index.md:77` calls `IFLowStorageRK3` "the
default" in the same breath — same question, same answer, and it should be settled together so the
integrator and dealiasing surfaces do not diverge.

---

**USER CONFIRMED THE CLASS RULING (2026-08-15):** *"Same here. 'default'. Be sure to fix that as a
class."* — pointing at `TwoThirds`' own docstring (`src/SimulationDomain.jl:57`, "the lean,
GPU-friendly default"). Full class enumeration below, done now so the fix pass sweeps it rather than
chasing screenshots.

**The ruling is not a new preference — it is decision 28, which these docstrings contradict.**
`ARCHITECTURE.md:1055–1060`: *"**Defaults only in `SimulationRun`.** The low-level types carry no
convenience defaults — `FixedDomain`, `FlowConditions`, the initial-condition seeders, and `Tracers`
require their arguments; the `Simulation` front door supplies the run-layer values. Model/preset types
(`Pope2000`, `HouLi`, …) keep their canonical parameters."* A low-level type saying "the default" is
therefore stale against a recorded decision, not merely inelegant — which also settles that this is a
correctness sweep, not a taste call.

**IN SCOPE — default-narration on a low-level type or its section blurb (remove):**
| site | text |
|---|---|
| `src/SimulationDomain.jl:44` | `DealiasingStrategy` — "(the sharp ``2/3`` rule, **the default**)" |
| `src/SimulationDomain.jl:57` | `TwoThirds` — "the lean, GPU-friendly **default**" *(the screenshot)* |
| `docs/src/api/SimulationDomain.md:20` | blurb — "the sharp ``2/3``**-rule default**" |
| `src/Propagator.jl:28` | module map — "`IFLowStorageRK3` (**the default**)" |
| `src/Propagator.jl:225` | `IFLowStorageRK3` — "The **default** workhorse:" |
| `src/Propagator.jl:334` | `IFRK2` — "is **not** the default — prefer …" ← the **negative** form, the exact wording removed from `HouLi`/`PhaseShift` in `5fcb890`; the sweep missed this one too |
| `docs/src/api/Propagator.md:10` | blurb — "the **default** third-order low-storage RK3" |
| `docs/src/index.md:77` | Components — "`IFLowStorageRK3` — **the default** —" |

**JUDGMENT — front-door context, decide with the user (my read: may stay):**
`docs/src/index.md:73` ("dealiased by the default ``2/3`` rule"), `docs/src/notation.md:95` (κ_max "for
the default ``2/3`` rule"), `src/Generator.jl:399` ("the sharp ``2/3`` rule by default"),
`src/Particles.jl:46` (explicitly attributes: "the default `tracer_scheme` **of the `Simulation` front
door**" — correct as written).

**OUT OF SCOPE — genuine defaults of the documented object (do NOT touch):** every keyword default
(`strength = nothing`, `C₂ = 2.0`, `c_L`/`c_η`, `seed = 0`, `constant = 0.9`, `schmidt = 1.0`,
`scalar_dissipation = NaN`, `spectrum = nothing`, `rng`, `:band (default)`, `C_K = 1.5`, the
`correction`); the Forcing protocol's "the default does nothing" (a default *method*, a different sense
entirely); everything in `SimulationRun`/`Simulation` (the front door owns defaults); the ARCHITECTURE
decision-log entries (append-only history).

**Scope note:** the class spans **two** surfaces the earlier rounds treated separately — dealiasing
*and* integrators. Round 1 fixed only dealiasing, and only its negative form. Sweep both together.


### 7. No DOIs anywhere in IT — the stated policy is the inverse of PF's, and its stated reason is my
### limitation, not the reader's need (screenshot: `TwoThirds`, "The rule is due to Orszag (1971).")

User: "where is the DOI link? Don't we have a policy on that like in PF or SS?"

**We have a policy, and it is the opposite of PF's.** `docs/ARCHITECTURE.md:1633` (the §References
header): *"Cited author–year above; full entries here (**DOIs are omitted rather than filled from
memory, per the no-guessed-citation rule**)."* Verified: **zero** DOIs exist anywhere in IT — not in a
docstring, not in §References, not on a docs page.

**PF does the opposite, and it is the leading-edge sibling.** `GBGPeriodicFields` carries **14** DOIs in
its `ARCHITECTURE.md` and links them inline in docstrings as full markdown references, e.g.
`src/Interpolation.jl:61`:

> `C. C. Lalescu, B. Teaca, D. Carati, [*Implementation of high order spline interpolations for tracking
> test particles in discretized fields*](https://doi.org/10.1016/j.jcp.2009.10.046), J. Comput. Phys.
> **229**(17) (2010) 5862–5869.`

— author list, linked title, journal, volume, issue, year, pages. IT's richest citation by contrast is
`Kolmogorov, A. N. (1941). … *Dokl. Akad. Nauk SSSR* **30**, 301–305.` with no link.

**Why this matters beyond consistency.** The no-guessed-citation rule is sound and must stay — a
fabricated DOI is worse than none. But the *conclusion drawn from it* is wrong: "I cannot recall a DOI
reliably" argues for **looking it up or asking**, not for a package-wide omission. The rule was
converted into a permanent policy, which is my known failure mode of treating a limitation as a design
decision. PF proves the limitation is surmountable in this very codebase.

**A guard that passes vacuously.** `/check-docs` runs a DOI cross-check backstop ("every DOI cited in a
`src` docstring must appear verbatim in §References"), and both the battery and the panel's citations
hat reported it clean. It is clean **because there are no DOIs** — the guard cannot fail while the
policy holds. Worth recording as an instrument that certifies nothing today.

**Direction (a decision for the user, and it is a real one — ~28 references):** close the divergence
toward PF (parity is the standing rule for the sibling packages), with DOIs supplied by lookup rather
than recall — mine or the user's. Scope if adopted:
- `docs/ARCHITECTURE.md` §References, ~28 entries.
- The `Phenomenology` leaf's self-contained `Reference` values (~two dozen, e.g.
  `Reference("Kolmogorov (1941), *Dokl. Akad. Nauk SSSR* **30**, 301–305 …")`) — these are the
  user-facing citations a reader actually meets on the phenomenology pages.
- Inline docstring cites that name a paper (`TwoThirds` → Orszag 1971, `HouLi` → Hou & Li 2007,
  `PhaseShift` → Patterson & Orszag 1971 + Rogallo 1981, `derivative_skewness` → Betchov 1956,
  `IFLowStorageRK3` → Williamson 1980, the forcing cites, `Li2008`).
- Some are pre-DOI (Kolmogorov 1941 Dokl., Yaglom 1949, von Kármán 1948) — those legitimately have
  none, and that should be stated once rather than left to look like an omission.


### 8. IT's citation architecture cannot satisfy IT's own self-containedness rule — the structural
### cause behind finding 7 (screenshot: `HouLi`, "The smooth spectral filter of Hou & Li (2007)")

User: "How comes it lacks the source too? PF is quite good at catching and fixing things like this. I
don't remember how it does it, either with check-docs or hats."

**Answer to the mechanism question: `/check-docs`, not the hats — and the difference is structural, not
a matter of vigilance.** The two packages put the reference in different places:

| | PF | IT |
|---|---|---|
| where the full reference lives | **in the docstring**, inline | only in `ARCHITECTURE.md` §References |
| what the docstring shows | authors, linked title, journal, volume(issue), year, pages, DOI | `Author (Year)` |
| ARCHITECTURE structure | **per-section** reference blocks | one list at the end |
| DOI cross-check | docstring→ARCH **and vice-versa** | docstring→ARCH only |
| does the check bite? | yes (14 DOIs) | **no — vacuous, zero DOIs** |

PF's `src/Interpolation.jl:141` is the model: *"Reference: C. C. Lalescu, B. Teaca, D. Carati,
[*Implementation of high order spline interpolations…*](https://doi.org/10.1016/j.jcp.2009.10.046), J.
Comput. Phys. **229**(17) (2010) 5862–5869."* — complete where the reader stands.

**The sharp part: IT's two rules combine to strand the reader.** CLAUDE.md's *"No dead references on
the user-facing surface"* forbids a docstring from citing an `ARCHITECTURE.md` section — "a rendered
docstring must read **complete at the REPL**". But IT keeps every full reference *only* in
`ARCHITECTURE.md` §References. So `HouLi`'s reader gets "Hou & Li (2007)", is forbidden a pointer to
where the entry lives, and has no way to reach the paper. The docstring is **not** complete at the
REPL — the very property the rule exists to guarantee. IT's citation architecture is structurally
incapable of satisfying IT's own rule; PF's is built so that it does.

This is the cause of which finding 7 (no DOIs) is the symptom, so **fix them together**:
1. Move the full reference **into** the docstring that cites it, PF-style, with the DOI link.
   `ARCHITECTURE.md` §References keeps its list (it serves the design doc's own prose).
2. That makes each cite self-contained at the REPL and satisfies the existing rule.
3. It also makes IT's DOI cross-check **non-vacuous** for the first time, and the check should be made
   **bidirectional** like PF's ("and vice-versa") so an entry cannot rot on either side.

**Instrument note (the answer to "how does PF do it"):** IT already has PF's DOI script — it was ported
without the reverse direction, and it has been reporting "clean" ever since because the corpus it
guards is empty. Nothing in `/check-docs` or the 11 hats can flag a *missing* DOI; both check
consistency *between* citations, not their existence. If parity is adopted, add the existence check:
every inline `Author (Year)` naming a published method resolves to a full reference in the same
docstring.


### 9. `dealias!` names an outcome it cannot deliver alone — rename, don't just caveat
### (screenshot: the "Dealias filtering" section, `src/SimulationDomain.jl:325`)

User: "applying the filter may not be the whole dealiasing, e.g. for PhaseShift. User may think that
dealias! is the full de-aliasation. What do you think? Or shall we rename the operation? Or what?"

**The concern is correct, and it is worse than the `PhaseShift` case alone.** Verified:

- Under `PhaseShift`, `domain.dealias` is **only the spherical ``2\sqrt{2}/3\,\kappa_{\mathrm{Ny}}``
  truncation**. The part that actually cancels the aliases — averaging the primary evaluation with the
  half-cell-displaced one — lives in the generator's assembly (`src/Generator.jl:302`, `:320`). So
  `dealias!` applies *half* the strategy, and the half that does not dealias.
- Even under `TwoThirds`, dealiasing is a property of **how a quadratic product is formed and
  truncated**, not of a multiply on one field. Applying a ``2/3`` mask to an arbitrary field is a
  **band limit**; it earns the name "dealiasing" only in the context of the product it precedes.

So the name states a *policy outcome* while the operation is a *band-limiting multiply* — which is
exactly the "approximate cover word" the naming policy forbids ("unambiguous (one reading) and precise
(the exact thing, not an approximate cover word)"). `PhaseShift` merely made the gap visible.

**Recommendation: rename, and keep a one-clause note.** A caveat alone leaves a public verb whose name
contradicts its docstring's own caveat — the reader has to remember an exception to the name.

**Rename is cheap — verified:** `dealias!` has **zero callers in `src/`**. Its only uses are 8 test
lines (`test/integrators.jl:42`, `particles.jl:103`, `scalar.jl:65,83`, `simulation_run.jl:197`,
`velocity_slice.jl:27`, `forcing.jl:31,136`), the export lists, and the API page. Nothing in the hot
loop or the generator touches it — the assemblies compose `domain.dealias` into their own convolves.

**NAME SETTLED BY THE USER (2026-08-15): `truncate_to_band!`.** (Candidates weighed: `band_limit!` —
shorter, my suggestion; `apply_dealias_kernel!` — names the mechanism, which the naming policy
discourages.) `truncate_to_band!` is the more explicit of the two good options and says both halves of
what happens — a *truncation*, and *to the resolved band*. It also reads correctly under all three
strategies, and under `PhaseShift` it is exactly right: the spherical truncation is precisely what that
kernel is.

**The note to carry regardless**, on the renamed verb: applying the kernel is the whole dealiasing only
for the mask strategies; `PhaseShift` dealiases by averaging a half-cell-displaced evaluation inside the
right-hand-side assembly, and this kernel is only its spherical truncation. Point at
[`DealiasingStrategy`](@ref) for the full picture.

**Knock-on if renamed:** the `SimulationDomain` module map bullet, the umbrella export list, the API
page's "Dealias filtering" section heading (→ "Band limiting"), `ARCHITECTURE.md` §4.1's mention, and
`notation.md` if it names the verb. The `domain.dealias` **field** name and the `DealiasingStrategy`
type keep their names — the *strategy* genuinely is a dealiasing strategy; only the single-field verb
overclaims.


### 10. The `State` module docstring: an obvious clause, a parenthetical that should be a sentence,
### and a 71-word sentence (`src/State.jl:12–26`)

User: "'a passive record with every operation external' — just omit this. It is kind of standard and
obvious that you just list the data and imply there no functions in the struct. So you can make the note
in parenthesis just a regular sentence. The sentence 'The physical representations are recovered from
the state ...' is too long, break it."

**(a) Omit "a passive record with every operation external."** Correct — in Julia a struct that lists
fields *is* data with external operations; saying so is stating the language's default. Nothing is
gained by asserting it, and it costs the bullet's first clause.

**(b) Promote the parenthetical.** "(the single source of truth; the physical fields are recovered from
it, never held in the state)" is the actually-informative content; with (a) gone it should stand as a
plain sentence rather than an aside.

**(c) Break the 71-word sentence.** Measured: the second sentence of the closing paragraph is **71
words**, carrying two em-dash asides and two parentheticals — the four-argument form, the
scratch-argument gloss, the FFT-backend reason, the vorticity route, and the deposit destination, all
in one breath.

---

**META — this is the fourth instance this round of the same failure, plus a second pattern.**

*Pattern 1 — repairing the flagged wording while keeping (or expanding) a clause that should go.*
Round 1's finding 8 flagged "the **inert** record"; I replaced it with "a **passive record with every
operation external**" — longer, and now flagged as obvious. Same shape as: finding 2 (carried "stamped"
through a rewrite), finding 3 (made the Generator recovery clause more precise instead of deleting it),
finding 6 (removed the negative default-narration, left the positive). **The prior question is always
"should this clause exist?", asked before "is this clause correct?"**

*Pattern 2 — clause accretion.* This one sentence grew by successive fixes, each appending rather than
restructuring:
1. before R2: *"The boundary storage the recoveries fill is the `ObservablesCache`."* (~10 words)
2. `89a0d48` (decision 47): rewritten to name the PF arity and the preservation reason.
3. `0baddf3` (panel 11#3, "scratch arity" undefined): **appended** the parenthetical gloss "(the extra
   argument is a scratch field the transform consumes in the state's place)".

Each edit was locally justified and each made the sentence worse. **A fix that adds a clause to an
already-long sentence is a restructure disguised as an insertion** — when a repair lands in a sentence
past ~30 words, split first, then fix.

**Check the same two patterns at fix time on the sentences my other panel/round-1 fixes touched**, in
particular: `Simulation`'s grid-mode paragraph (gained the `Li2008`-calibration caveat), `deposit!`
(gained the epoch gloss), `dissipation` (gained the divergence-free condition), and `advance!` (gained
the max-speed-readback note).


### 11. `ResolvedFields` / the State page — four wording items and one naming decision
### (`docs/src/api/State.md:10–12`, `src/State.jl:41–47`)

**(a) "the source-preserving scratch arity of `to_physical!`" — "arity" is unfriendly.** User: "a bit
scary for the user, that 'arity thing'. Can you think of something more friendly?"

Agreed — "arity" is compiler vocabulary, and the naming policy's audience is a physicist, "not a
software engineer fluent in startup idiom". Suggested: **"the four-argument form of `to_physical!` that
leaves the state untouched (it transforms out of a scratch copy)"** — says the count, the guarantee, and
the mechanism, with no jargon. Settle the exact wording at fix time.

**SWEEP MISS — mine.** The panel's cold-reader finding 11#3 flagged "scratch arity" as undefined; in
`0baddf3` I replaced it in **two** docstrings (`State.jl`'s module docstring, `Generator.jl`) and left
**six** other occurrences standing: `src/State.jl:4` (comment), `docs/src/api/State.md:11` (the
screenshot), `docs/src/api.md:15`, and `docs/ARCHITECTURE.md:199, :246, :1592, :1605`. I fixed the
instances the hat quoted instead of grepping the phrase — against the panel's own rule, "a flagged
instance is a sample of a class". **At fix time: grep the phrase, not the citations.**

**(b) "a passive container with every operation external" — drop.** Same ruling as finding 10(a); this
is the `ResolvedFields` *type* docstring instance, the module-docstring one is finding 10. Both go.

**(c) "into the stamped slots of the `ObservablesCache` at its end" — two defects.** "Stamped" is
finding 2's class. **"its" is ambiguous**: the intended referent is *the iteration*, but the nearest
nouns are `ObservablesCache` and *slots* — "end of the stamped slot?" is a fair reading. Name the owner:
"…at the end of the iteration".

**(d) The parenthetical "(a slot's stamp records the instant its value belongs to; never on a read — a
cached read serves the deposited value or throws)" — cut.** User: "too vague, makes the sentence
unnecessary long." **And I added it**: the first half is the gloss I appended in `0baddf3` for the
panel's "stamped" cold-read finding. Third instance of the **clause-accretion** pattern (finding 10):
the gloss belonged in `Cache`'s own docstring, where the definition already lives, not appended here.
Cut it; the `ObservablesCache` link carries the reader to the definition.

**(e) NAMING DECISION — should the fields be `velocity_spectral` / `scalar_spectral`?**
**My recommendation: yes.** The decisive argument is a collision that exists today:

| reachable from `sim` | field | representation |
|---|---|---|
| `sim.state.velocity` | `src/State.jl:56` | **spectral** ``\hat{\boldsymbol{u}}`` |
| `sim.cache.velocity` | `src/Cache.jl:98` | **physical** ``\boldsymbol{u}`` |

Two fields, same name, opposite representations, both on the public object — the field-vs-representation
category error the doc policy polices, embedded in the API itself rather than in prose. Supporting
points: the public accessor is **already** `velocity_spectral(sim)` (`SimulationRun.jl:279`), so the
field name is the odd one out; and the suffix has precedent (`product_spectral`,
`velocity_star_spectral`, `star_spectral`, `scalar_spectral_storage`).

Counter-argument, for the record: within `ResolvedFields` *every* field is spectral, so the suffix is
locally redundant — and `CLAUDE.md:97` cites `state.velocity` as the **exemplar** of the
storage-naming rule. But redundancy inside the type is cheap, while the collision across `state`/`cache`
is a real hazard; and a policy example is not evidence the example is right (legacy is not correctness).

**DECIDED BY THE USER (2026-08-15): BOTH renames, landing together.**
- `ResolvedFields.velocity` → `velocity_spectral`, `.scalar` → `scalar_spectral`
- `ObservablesCache.velocity` → `velocity_physical` ("Yes, do cache.velocity → cache.velocity_physical")

Every storage slot then carries its representation, each field matches the accessor that reads it
(`velocity_spectral(sim)`, `velocity_physical(sim)`), and the collision closes from both sides. **They
must land in one commit** — renaming either alone just moves the asymmetry to the other struct.

**Scope (verify before starting; a field rename reaches further than the docs):**
- `src/State.jl` (struct + inner constructor), `src/Cache.jl` (struct, constructor, `_checked` reads,
  `take_`/`deposit_` verbs).
- Every `state.velocity` / `state.scalar` / `cache.velocity` use across `src/` — `Propagator.jl` (the
  step and the closing deposit), `SimulationRun.jl` (accessors, seeding, the tracer path),
  `Generator.jl`, `Observables.jl`.
- `test/` — including **the audits**: `memory_audit.jl`'s completeness walk enumerates field-scale
  arrays by name, and `audit_ops.jl`'s op model names registers; both must still see every array or the
  frozen ledgers break.
- Docs: `notation.md`'s Code column, the `# Fields` lists, `ARCHITECTURE.md` §4.1, and
  **`CLAUDE.md:97`**, which cites `state.velocity` as the storage-naming exemplar — the example itself
  changes.
- Sanity: `cache.vorticity` and `cache.scalar` are *also* physical; decide in the same pass whether they
  take the suffix too (consistency says yes: `vorticity_physical`, `scalar_physical` — which are exactly
  their accessor names) or whether only the colliding name moves. **Recommend: suffix all three**, so
  the rule is "a storage slot names its representation", not "the one that collided does".


### 12. Suffix the seeders too, and the seeding `!!! note` buries its own subject
### (`src/State.jl:63–94`, `:129–159`; API page "Random initial conditions")

**(a) DECIDED BY THE USER: `random_solenoidal_velocity!` → `random_solenoidal_velocity_spectral!`,
`random_scalar!` → `random_scalar_spectral!`.** ("Also suffix here … same with the scalar.")

This extends finding 11(e)'s rule from *storage slots* to *every name that touches a
representation-specific object*: both seeders fill a field in spectral representation (`û`, `φ̂`), and
their names did not say so. With the field renames it makes the rule uniform — a reader can tell the
representation from the name alone, whether it is a slot, an accessor, or a verb.

**Blast radius: 50 sites** (`random_solenoidal_velocity!` 29, `random_scalar!` 21) across `src/`,
`test/`, the docs pages, and `ARCHITECTURE.md`, plus the umbrella `using`/`export` lists and the API
page's `@docs` block. **Land with finding 11(e)'s field renames in the same commit** — they are one
naming decision, and a half-applied representation rule is worse than none.

*Open, decide at fix time:* whether the same suffix rule reaches other verbs whose argument's
representation is fixed but unstated — e.g. `truncate_to_band!` (finding 9's new name; it takes a
spectral field). My read: **no** — the rule earns its keep where a name would otherwise be ambiguous
across two live objects (the `velocity` collision) or where a physical twin exists; `truncate_to_band!`
has no physical counterpart to be confused with. State the boundary explicitly when recording the
decision so the next round does not re-litigate it.

**(b) The seeding `!!! note` never says what it is about until the closing parenthesis.**

User: "The 'Note' is about the cache behaviour? Then why doesn't it state from the beginning, that it is
about the cache, only in the end and in the parenthesis there is something about the cache."

Current text (identical in both seeders, `State.jl:89–93` and `:155–159`):

> Seeding into a running case mutates the resolved fields out of band — announce it with
> `resolved_fields_modified!`, and re-deposit with `deposit!` before advancing (cached reads throw in
> between; nothing is recomputed on a read).

The note's *subject* is the observables cache: seeding invalidates it, which is why the two calls are
needed. But "cache" appears only inside the trailing parenthesis. A reader meets two imperative calls
before learning what problem they solve — the reason is demoted to an aside while the remedy leads.
Same family as finding 3 (a bullet describing mechanism instead of identity), here inverted: **the
subject is present but demoted below the instructions**.

*Direction:* lead with the cache and the consequence, then the remedy — e.g. "The observables cache is
stamped against the state it was deposited from, so seeding into a running case makes every cached
value stale. Announce the change with …, then re-deposit with … before advancing; until you do, a
cached read throws." (Also fixes the trailing "nothing is recomputed on a read", which restates the
cache contract a third time.) Both copies change together; "stamped" here is finding 2's class.


### 13. "Their plateaus gate warm-up" — an unbound pronoun over a false quantifier
### (`src/Observables.jl:25`, the module docstring's closing paragraph)

User: "Their plateaus — who are they? The vorticity and max_speed?"

**The pronoun is unbound, and the sentence it opens is false.** "Their" can only mean the nine names in
the bullet list above it. Verified against `StationarityCriterion` (`src/SimulationRun.jl:561–564`),
exactly **three** observables can gate warm-up, two of them optionally:

| gate | observable | when |
|---|---|---|
| `flat_v` | `dissipation` ``\varepsilon`` | always |
| `flat_s` | `scalar_variance` ``\langle\varphi^2\rangle`` | only with `gate_scalar` |
| `flat_k` | `derivative_skewness` ``S`` (plateau **and** ``\lvert S\rvert \ge`` `skew_floor`) | only with `gate_skewness` |

So the claim is false for six of the nine: `max_speed` (sets the timestep, never gated),
`vorticity_physical!` (a field recovery — it has no plateau), `energy_spectrum`, `integral_scale`,
`scalar_dissipation`, and — the sharpest one — **`kinetic_energy`**.

**`kinetic_energy` is deliberately excluded from the gate, and the code says so.**
`src/SimulationRun.jl:495–496`: *"…rather than the kinetic energy ``k(t)``, which is clamped flat by
constant-energy forcing and rings under fixed-injection forcing; the small scales settle last, so a
flat ``\varepsilon`` is the strict indicator."* The module docstring's blanket "their plateaus gate
warm-up" therefore asserts the **opposite** of the design the criterion documents for its most obvious
candidate — and it is the same ``k``-is-clamped fact that finding round 2's `BandRescaling` caveat
turns on. `k` is measured, for the turnover clock, and deliberately not gated.

**Class:** false universal quantifier over a list — the same shape as the panel's "every diagnostic is
dimensionless" (03#5, fixed in `0baddf3`). That fix corrected the instance the hat found; this one
survived four surfaces away. **A quantifier over a bullet list should be checked against the list, item
by item** — it is exactly the "positive procedure" the doc checklist demands and that a read-through
does not perform.

*Direction:* name the three, drop the pronoun — e.g. "The dissipation ``\varepsilon``, and optionally
the scalar variance and the derivative skewness, gate warm-up through their plateaus (`warmup!`); the
kinetic energy is measured for the turnover clock but deliberately not gated, since a constant-energy
forcing clamps it flat." Also re-check the sibling claim in the same paragraph — "Each is a function of
the state" — against `vorticity_physical!`, which *writes* a field rather than returning a measurement.


### 14. The code-span-abutting-math-span pattern — a named house-rule violation, 16 sites; and the
### opposite failure (no binding at all) in `kinetic_energy` (`src/Observables.jl:84–85`, `:46–48`)

User: "look how awkwardly code û and latex are rendered together. Just use parenthesis perhaps around
one of them? And for the kinetic energy there is no stated link between code u and its latex form."

**Both are the same rule, broken in opposite directions — and the rule names this exact pattern.**
`CLAUDE.md:193–197`: *"**Bind each code object to its symbol on first mention** … In a rendered
docstring make the binding **one** LaTeX span — ``\texttt{dissipation} \equiv \varepsilon`` — **never a
`` `code` `` span abutting a math span** (silent-rendering rule (b))."*

- **`dissipation` over-binds** with the banned construction: `` `û` `` immediately followed by
  ``\hat{\boldsymbol{u}}`` renders as "û ��" — a code glyph and a math glyph side by side with nothing
  joining them, which reads as a typo or a duplication (exactly the user's reaction).
- **`kinetic_energy` under-binds**: the formula uses ``\boldsymbol{u}`` and the prose says "the velocity
  field `u`", but the correspondence is never written. The reader infers it. The rule's whole point is
  that it be explicit.

The prescribed form is one span: ``\texttt{û} \equiv \hat{\boldsymbol{u}}``. Parentheses would fix the
*visual* collision but keep two spans, so prefer the rule's own construction; if a sentence reads badly
with `\equiv`, write "the velocity in spectral representation, ``\hat{\boldsymbol{u}}`` (the argument
`û`)" — one math span, one code span, separated by words.

**User confirmed the class on a second instance (`scalar_dissipation`, `src/Observables.jl:176`):**
"Same here." — `` `φ̂` `` abutting ``\hat\varphi`` renders "φ̂ φ̂", and the rendered line even breaks
between the two spans so the following comma starts the next line. That docstring carries **two** of the
16 (`:176` for `φ̂`, `:177` for `diffusivity` ϰ), which is why the paragraph reads doubled twice over.

**Class sweep — 16 sites of the abutting pattern** (verified; none is caught by any build lint, so this
class has been invisible to `/check-docs` and to all 11 hats):
- `src/Observables.jl:66` (`viscosity` ν), `:80` (`ω`), `:84–85` (`û` — the screenshot), `:176` (`φ̂`),
  `:177` (`diffusivity` ϰ)
- `src/Forcing.jl:301` (`dissipation` ε)
- `src/Phenomenology.jl:201` (`order` p)
- `docs/ARCHITECTURE.md:307, 309, 313, 323, 1416` (the §4.3 observable list and the factor-parameter
  triple — five sites, and `:1416` chains three of them: `` `coefficient` ``` ``= -D\tau`` ``, …)

**Instrument gap worth recording.** `/check-docs`'s deterministic block has a *code-in-math* scan (a
bare identifier **inside** a math span) but **no scan for a code span abutting a math span** — the
converse, and the one CLAUDE.md explicitly names. A one-line grep catches it:
`grep -rnP '`[^`]+`\s+``' src/*.jl $DOCS_MD`. **Add it to the must-be-empty block** when fixing, or the
class regrows silently; and check `kinetic_energy`'s *absent* binding as its own positive procedure
(enumerate each docstring's math symbols, verify each is bound to its code object) — a grep cannot find
a missing binding.


---

**THIRD CONFIRMATION OF FINDINGS 7 + 8 (2026-08-15): `derivative_skewness`.** User: "Missing reference
again." — the docstring cites *(Betchov 1956)* twice and carries no resolvable reference.

This is the **strongest** case in the class, for a reason the others lack: the docstring does not merely
*mention* Betchov, it **derives its reported constant from him** —
``C_S = \tfrac{4}{7}\sqrt{15/2} \approx 1.5649`` follows from
``\langle\operatorname{tr}\boldsymbol{S}^3\rangle = \tfrac{105}{8}\langle(\partial_{x_1}u_1)^3\rangle``
and ``\langle\boldsymbol{S}:\boldsymbol{S}\rangle = \tfrac{15}{2}\langle(\partial_{x_1}u_1)^2\rangle``.
A reader who wants to check that derivation — and `CLAUDE.md` holds this very constant up as the
example of "correctness is verified, not asserted" — is given an author and a year and no way to reach
the paper. The citation is load-bearing for a numerical claim, which is exactly where a dead cite costs
most.

**Full class list for findings 7/8 (every inline author–year cite in a rendered docstring, none with a
resolvable reference):**
- `src/Observables.jl` — Betchov 1956 (×2)
- `src/Forcing.jl` — Lundgren 2003, Bussi/Donadio & Parrinello 2007, Eswaran & Pope 1988
- `src/SimulationDomain.jl` — Orszag 1971, Hou & Li 2007, Patterson & Orszag 1971, Rogallo 1981
- `src/Propagator.jl` — Williamson 1980
- `src/phenomenology/Scalings.jl` — Sreenivasan 1995/1998, Li et al. 2008, Taylor 1935,
  Kaneda et al. 2003, Sagaut & Cambon 2018
- `src/phenomenology/Spectra.jl` — Pope 2000, von Kármán 1948, Pao 1965, Obukhov 1949, Corrsin 1951,
  Sreenivasan 1996, Kaneda 1993, Qian 1984, Kraichnan 1959, Ishihara et al. 2005, Chen et al. 1993,
  Khurshid/Donzis & Sreenivasan 2018, Saffman 1963, Meneveau 2008, Sagaut & Cambon 2018
- `src/phenomenology/StructureFunctions.jl` — Kolmogorov 1941/1962, She & Lévêque 1994, Yaglom 1949,
  Lundgren 2002, Sagaut & Cambon 2018

~35 distinct works. The `Phenomenology` ones carry a `Reference` **value** (author, journal, volume,
page) but still no DOI; the DNS-side ones carry author–year only, with the full entry stranded in
`ARCHITECTURE.md` §References that a docstring is forbidden to point at (finding 8). Pre-DOI works
(Kolmogorov 1941, Yaglom 1949, von Kármán 1948, Taylor 1935, Betchov 1956 — *Phys. Fluids* **1**, 497,
which does have one) need the "no DOI exists" case stated once rather than left ambiguous.


### 15. `max_speed`'s three forms look arbitrary because the rule behind them is nowhere on the
### user-facing surface (`src/Observables.jl:117–131`)

User: "What did we decide on extending observables to cache and sim? Here we provide the signatures,
but not for other functions. What shall we do?"

**What we decided (decision 46, from round 1's R1):** *"an observable with **both a measurement and a
cached value** is one generic with two method families — the field-argument reduction computes, the
`ObservablesCache` method serves the deposited value or throws … (`max_speed` today; the pattern is the
rule for any future cached observable)."* Plus the standing guard, unchanged since decision 40:
``\varepsilon``, ``k``, ``E(\kappa)`` **never become resident slots**.

**So: nothing is missing, and no code should change.** The cache holds exactly five things
(`src/Cache.jl:98–105`): the physical velocity, vorticity and scalar, the particle velocities, and
`max_speed`. Of those, `max_speed` is the only **observable value**; the three fields are recoveries
read under their own names (`velocity_physical`, `vorticity_physical`, `scalar_physical`). So
`max_speed` is the only observable that *can* have a cache form — `dissipation(cache)` or
`kinetic_energy(cache)` cannot exist without either adding a resident slot (forbidden by the guard) or
recomputing on a read (forbidden by decision 40).

**The defect is documentary, not structural: the asymmetry is unexplained where a reader meets it.**
Nothing in `max_speed`'s docstring or the `Observables` module map says *why* this one has three forms
and its siblings one. A reader reasonably infers the pattern is under-applied — which is exactly the
inference the user drew, and the second time this round that a principled design read as an oversight
(cf. finding 15's sibling, `scalar_dissipation`'s single route, fixed in `0baddf3` by stating the
reason).

*Direction:* one sentence, in the module map beside `max_speed` and/or in its own docstring — e.g.
"`max_speed` is the only observable with a cached form, because it is the only observable **value** the
iteration deposits; the dissipation, energy and spectrum are measured on demand and deliberately never
cached (a cached read never computes, and they would each cost a resident slot)." **Fold into finding
13's rewrite of the same closing paragraph** — that paragraph is being rewritten anyway, and this rule
belongs in it.

*Also settle in the same pass:* the `(sim)` forms. `max_speed(sim)`, `velocity_physical(sim)`,
`vorticity_physical(sim)`, `scalar_physical(sim)`, `particle_velocities(sim)` and
`particle_positions(sim)` all exist as conveniences, while `kinetic_energy(sim)` etc. deliberately do
**not** (decision 28: "Observables are functions of the state, not the `Simulation`"). That is a second
principled asymmetry on the same surface, equally unstated — a reader who sees `max_speed(sim)` may
reasonably try `dissipation(sim)`. State both rules together or neither will read as intentional.


### 16. `energy_spectrum` "brought to the host" — TRUE, but the agent and the cost are unstated
### (`src/Observables.jl:236–239`)

User: "Are you sure they are moved to host? I thought PF gives them as the device arrays."

**Verified — the claim is correct, and the user's premise about PF is also correct.** Both hold:

```julia
function energy_spectrum(û, domain::FixedDomain)
  shells, spec = radial_spectrum(û, domain.multipliers)
  return (; wavenumbers = Array(shells), energy = Array(0.5 .* spec))
end
```

PF's `radial_spectrum` returns backend arrays — **device arrays on a GPU run**; **IT** converts them
with `Array(...)`. So this is not a correctness defect. **Not a finding against the claim; a finding
against its phrasing.**

**What is wrong: the sentence hides who acts and what it costs.** "brought to the host, an occasional
diagnostic" is passive, so a reader cannot tell whether PF hands back host arrays or IT copies them —
which is precisely the doubt it produced. And on the GPU path `Array(...)` is a **blocking
device-to-host readback**, a synchronization point the package tracks as a first-class cost: the
optimality audit's eighth axis counts readbacks per step, and `ARCHITECTURE`'s decision 35 records the
default configuration's three-per-step against a floor of one. A docstring that mentions the transfer
without naming it as a readback undersells the one thing a GPU-minded reader needs.

*Direction:* name the actor and the cost, and keep the existing "occasional diagnostic" justification —
e.g. "the two vectors are copied to the host here (`Array`), a blocking device-to-host readback on a GPU
run; `energy_spectrum` is an occasional diagnostic, not a hot-loop read, so the synchronization is
deliberate." Check `integral_scale` in the same pass — it consumes `energy_spectrum`, so it inherits
the readback and says nothing about it either.

**ADDENDUM — why the readback exists at all (user: "why does IT move the radial spectrum to host?
What's the point?"). Verified; the reason is threefold and the docstring gives none of it:**

1. **Both consumers are scalar host-side loops.** `integral_scale` (`src/Observables.jl:281–288`) runs
   `for i in eachindex(κ, E) … E[i] / κ[i]`, and `validate_spectrum` (`src/SimulationRun.jl:352–366`)
   the same with `predicted[i] = …`. Scalar indexing of a device array is forbidden outright by
   invariant 4 ("no scalar indexing of device arrays") and would be pathological if allowed.
2. **`Phenomenology` cannot run on the device, by charter.** `validate_spectrum` evaluates
   `spectrum(model, κ[i], fp)` per shell, and `Phenomenology` is the **extraction-bound leaf**: it takes
   no `GBGPeriodicFields`, no `KernelAbstractions`, no GPU dependency, so its laws are plain scalar
   Julia functions. Comparing measured against model *must* happen on the host — this is the leaf's
   design working as intended, not an oversight.
3. **The transfer is ``O(N)``, not ``O(N^3)``.** A shell vector is a few hundred floats — kilobytes —
   against the ``N^3`` field it summarizes. This is the one reduction whose result is small enough that
   a readback is the cheap option.

So the design is right and the sentence is thin: "brought to the host, an occasional diagnostic" states
the *what*, and the three reasons that make it obviously correct are absent. Fold into the fix above —
one clause naming the scalar-consumer constraint and the ``O(N)`` size turns a claim a reader must take
on trust into one they can check.

**Class note:** this is the second time this round that a *true* statement read as suspect because the
agent was elided (cf. finding 12(b), where the seeding note's subject — the cache — was demoted to a
parenthesis). Passive constructions in an API docstring hide exactly the thing a caller needs: who does
it, and what it costs them.


### 17. OPEN QUESTION FOR THE USER — should `kinetic_energy(sim)` / `(cache)` exist? The two halves
### have very different answers, and one of the bans may be obsolete

User: "why don't we have kinetic_energy(sim)? or kinetic_energy(cache)? I would think they all need to
be symmetric."

Answering honestly rather than defending the arrangement (this is the "a recorded cost is not a minimal
one" trap: the ban is *recorded*, which is not the same as *still right*).

**(1) `kinetic_energy(cache)` — genuinely blocked, and the reason is structural.** The cache's contract
is **automatic contents**: it holds "exactly what the iteration computes, materializes, and leaves alive
at the iteration's end, and nothing may be added on any cost axis" (`src/Cache.jl:60`). The iteration
never computes ``k`` — nothing in `step!` needs it. Caching it would mean adding an ``O(N^3)`` reduction
**and a blocking readback** to every iteration, for a number most runs read rarely; and a cached read
may never compute (decision 40). So this form cannot exist without changing what a run costs. **Not
symmetry-breaking — the asymmetry *is* the design**: `max_speed` is cached because the timestep needs it
every iteration anyway.

**(2) `kinetic_energy(sim)` — blocked only by policy, and the policy's motivation looks spent.**
Decision 28 (`ARCHITECTURE.md:1066`): *"No `f(sim)` form: an observable taking a `Simulation` reached
across `state` / `buffers` / `conditions`, **smearing the single source of truth** (decision 26)."* The
motivating bug was concrete — a diagnostic that read the physical **scratch** as if it were the state.
But that bug was possible because the state was *scattered across the `Simulation`*; decision 26 then
reified it as `ResolvedFields`, so `kinetic_energy(sim)` today would have exactly one unambiguous
meaning, `kinetic_energy(sim.state.velocity)`. **The hazard the ban was written against no longer
exists.**

Note the resulting rule is subtle and unstated: **the `(sim)` forms that exist are all *cache reads*
(`max_speed`, `velocity_physical`, `scalar_physical`, `particle_velocities`, `particle_positions`);
the ones that are banned are all *state measurements*.** A reader who meets `max_speed(sim)` has no way
to infer that.

**Three coherent options — the user's call:**
| option | what it means | cost |
|---|---|---|
| **A. Keep as is, state the rule** | `(sim)` is a cache-read convenience only; measurements take their field explicitly | zero code; one sentence (folds into finding 15) |
| **B. Add `(sim)` measurement forwards** | `kinetic_energy(sim)`, `dissipation(sim)`, `derivative_skewness(sim)`, … ≡ the same on `sim.state.velocity` | reverses decision 28's bullet, needs a new decision entry; makes the surface uniform, which is what the user's instinct expects |
| **C. Full symmetry incl. `(cache)`** | also cache ``k``, ``\varepsilon`` | **rejected** — breaks the automatic-contents contract and the no-recompute rule, and costs a pass + readback per iteration |

**My read: A or B, not C** — and B is defensible now in a way it was not in 2026-07, so if the user's
expectation is symmetry, B is the honest way to give it, *with* decision 28's bullet amended to record
why the original hazard is gone rather than silently contradicted.


### 17b. ANSWER — the `(sim)` forms are the **uniform read surface** for observation, and the current
### set contradicts that stated purpose

User: "Let us think if we actually need to call anything on sim. Why do we do that? As an API for the
loop? Or what?"

**Yes — and it is on record, in the design doc's own words.** `ARCHITECTURE.md:444–449`:

> `velocity_spectral(sim)`, `scalar_spectral(sim)`, the cache accessors … and `particle_positions` …
> **form the uniform read surface: a function names what the run holds, wherever it lives — reading
> needs no knowledge of the state/cache split**, while *writing* stays on the dot path (`sim.state`),
> where the danger demands the knowledge.

So the purpose is exactly what the user guessed: **an observation API for the loop.** `run!` hands the
callback a `Simulation`, and the reads are meant to work on it without the caller knowing which
component holds what.

**And by that criterion the current set is incomplete — it fails its own test for the most common
observation.** To read the kinetic energy inside a callback you must write
`kinetic_energy(s.state.velocity)`: you need to know that ``k`` is measured off the state, that the state
is `ResolvedFields`, and that its field is `velocity` — precisely the "knowledge of the state/cache
split" the principle says reading must not require. Meanwhile `max_speed(s)` beside it needs none.

**The docs' own example demonstrates the friction** (`src/SimulationRun.jl:468–473`, the `run!`
docstring):

```julia
run!(sim) do s
    current_time(s) < 5.0                        # uniform read surface ✓
    push!(history, kinetic_energy(s.state.velocity))   # dot-path reaching ✗
end
```

Two reads in one callback, two different idioms — and the second is the one a user writes most.

**This resolves finding 17 in favour of option B**, on stronger grounds than symmetry-for-its-own-sake:
adding `kinetic_energy(sim)`, `dissipation(sim)`, `derivative_skewness(sim)`, `scalar_variance(sim)`,
`scalar_dissipation(sim)`, `energy_spectrum(sim)`, `integral_scale(sim)` **completes a read surface the
design already declares**, rather than adding sugar. Decision 43's principle and decision 28's ban are
in direct tension; the ban's motivating hazard (a diagnostic reading scratch as state) died with
decision 26's reification of `ResolvedFields`.

**What still must not exist**, and should be said in the same entry: `f(cache)` for the uncached
observables (finding 17(1) — the automatic-contents contract), and any **write** through a function
(writing stays on the dot path, deliberately). The rule then reads cleanly in one line: *read through a
function, write through the dot path* — with no exceptions a user must memorize.

**If adopted:** amend decision 28's bullet (do not silently contradict it) noting the hazard is gone,
add the forwards next to the existing ones in `SimulationRun.jl:300–305`, update the `run!` example to
use `kinetic_energy(s)`, and state the one remaining asymmetry (`(cache)` forms exist only where the
iteration already deposits the value).


### 18. THREE DESIGN QUESTIONS FROM THE USER (2026-08-15) — the `(sim)` surface, cache-defined
### observables, and whether `validate_spectrum` belongs in the package at all

**(1) "Dropping readings on simulation completely, let the user learn what the state and cache holds."**

Coherent, and arguably better than 17b — **either extreme is uniform; the present middle is what is
incoherent.** The options are now three, not two:

| | surface | what a callback writes | cost |
|---|---|---|---|
| **B** (17b) | complete the read surface | `kinetic_energy(s)`, `velocity_physical(s)` | new forwards; amend decision 28 |
| **D** (this) | **drop every `(sim)` form** | `kinetic_energy(s.state.velocity_spectral)`, `velocity_physical(s.cache)` | delete ~7 forwards; **reverse decision 43's "uniform read surface"** |
| A | keep, document the rule | mixed idioms | one sentence, permanent asymmetry |

Arguments **for D**, which are strong in this package specifically: the state/cache split is *physics*,
not plumbing — a DNS user who does not know that ``\hat{\boldsymbol{u}}`` is the truth and the cache
holds the deposited ``t_n`` values does not understand the method, so hiding it teaches nothing; it
removes every asymmetry findings 15/17 exist to explain; and a thin surface is the house style
("deferred ≠ missing… a missing capability encodes a decision"). Against: it reverses decision 43's
stated principle (the user's to revise), and callbacks get more verbose.

**Consequence to accept explicitly if D is chosen:** the dot path becomes the read path, so
`sim.cache` must be a documented, *public* thing to reach into — today the cache accessors are
presented as the sanctioned way to read and the dot path as the writing danger. D inverts that, and the
`ObservablesCache` docstring's read-only warnings become more load-bearing, not less.

**(2) "Observables must be defined on cache, right? They just throw if it is not there." — needs a
correction.** For the **cached** quantities this already exists (`velocity_physical`,
`vorticity_physical`, `scalar_physical`, `max_speed`, `particle_velocities` all take a cache and throw
on a stale/absent deposit). For the **uncached** observables — ``k``, ``\varepsilon``, ``E(\kappa)``,
the skewness — a cache method would **not** "throw if it is not there"; it would throw **always, for
every run**, because the iteration never deposits them and (decision 40) a read may never compute. A
method that can only throw documents an absence in code rather than in prose. So: cache-argument reads
are already complete over the things the cache holds; extending them further requires either caching
more (a per-iteration pass + readback, finding 17(1)) or breaking no-recompute.

**(3) "Those comparisons with the predicted spectrum were your initiative, I never asked for them. Do
we really need them? Shall we just move them to testing?"**

**Accepted — `validate_spectrum` was mine, unasked.** Assessment, honestly:

*Against keeping it in the package:* it is a **goodness-of-fit metric, not physics**. The charter says
this package owns "the equations of motion, forcing, scalar transport, time integration, particle
tracking, and the run layer" — a relative-``L^2`` error between a measured and a model spectrum is none
of those. Its metric is also an opinionated research choice (which shells? weighted how? why
``\sqrt{\sum(m-p)^2/\sum m^2}``?) baked into the public surface. It is ~20 lines that a user can write
from `energy_spectrum` + `Phenomenology.spectrum`, and it is the only thing forcing a
measured-vs-model comparison into the run layer.

*For keeping:* it demonstrates the `Phenomenology` leaf's purpose, and the HIT-validation workflow is a
real user need.

**My read: the user is right — move it to `test/`.** It already lives there in substance
(`test/validation.jl:56`), so the move is mostly deletion from `src/` plus keeping the test. Consequences
to record: `Phenomenology`'s remaining in-package consumers are `flow_parameters` (the `FlowParameters`
bundle) and `Li2008` (grid-mode viscosity) — both legitimate and unaffected; the umbrella export list
and the `SimulationRun` module map lose one entry; and `docs/src/phenomenology.md` should then show the
comparison as a **user recipe** rather than pointing at a shipped function. That is arguably a better
demonstration of the leaf anyway: here is a law, here is your spectrum, compare them how your paper
compares them.


### 19. DECIDED — drop the 8 forwarding reads + the announcement; full `Simulation` inventory
### (user, 2026-08-15: "Yes, 'Drop (8 reads + 1 announcement)'")

**Removed (the `(sim)` method only; each keeps its `(cache)` / `(tracers)` / field form):**
`velocity_spectral`, `scalar_spectral`, `velocity_physical`, `vorticity_physical`, `scalar_physical`,
`max_speed`, `particle_velocities`, `particle_positions`, `resolved_fields_modified!`.
**Also removed:** `validate_spectrum` → `test/` (already covered, `test/validation.jl:56`).
**Kept:** `deposit!(sim)`, `flow_parameters(sim)`, `current_time(sim)`, `current_step(sim)`.

Accepted consequence: `scalar_spectral(sim)`'s `ArgumentError("this run carries no passive scalar")` and
`particle_positions(sim)`'s `ArgumentError("this run advects no tracers")` disappear; the user reads
`nothing` / gets a `MethodError`. `nothing` is a loud sentinel in Julia (unlike `NaN`), so what is lost
is message quality — move those texts into the `ResolvedFields` / `Simulation` docstrings as *shape*
documentation rather than guards.

**EXHAUSTIVE `::Simulation` INVENTORY** (`grep -rn "::Simulation" src/*.jl`, 20 methods — nothing
outside `SimulationRun.jl` takes a `Simulation`, which is itself the right layering):

| verdict | methods |
|---|---|
| **drop** (9) | the 8 reads + `resolved_fields_modified!` |
| **drop → test** (1) | `validate_spectrum` |
| **keep — needs the whole object** (4) | `deposit!`, `flow_parameters`, `current_time`, `current_step` |
| **keep — the run layer itself** (4) | `advance!`, `run!`, `warmup!`, `Simulation` (constructor) |
| **internal, unexported** (3) | `cfl_timestep`, `_scalar_forced`, `(criterion::StationarityCriterion)(sim)` |

Note `(criterion::StationarityCriterion)(sim)` — the packaged observation — reads through the *public*
surface today; after the drop it must read `sim.state.velocity_spectral` / `sim.cache` directly like any
other caller, and `_scalar_forced` already does (`sim.state.scalar !== nothing`).

**WHY THIS WAS NOT RAISED EARLIER — a process failure worth recording.** In finding 15 I examined this
exact surface, found the asymmetry the user later questioned, and concluded *"nothing is missing, and
no code should change… the defect is documentary, not structural."* I explained the arrangement instead
of asking whether the layer earns its place. The user's question — *"why do we do that? as an API for
the loop? or what?"* — took the step back I did not: from *is this consistent?* to *why does this exist
at all?*

This is the recorded known weakness firing precisely as described: **treating what is in place as
evidence that it should be** — closing a flagged smell by pointing at the existing arrangement and its
recorded rationale. The tell was present and I read past it: a surface that needs *two* unstated rules
to look intentional (finding 15's cache-form rule, finding 17's `(sim)`-form rule) is usually a surface
that should not exist. Also note the 11-hat panel did not raise it either — the `software-architect`
hat audited signatures, argument order, and coupling, but no hat asks *"should this API layer exist?"*.
**Candidate new hat / check-docs lane: an existence auditor** — for each public form, name its caller
and the alternative spelling; if the alternative is one dot longer and the form has no check, flag it.


### 20. DECIDED — `energy_spectrum` should stop forcing the host transfer; `adapt` is the user's verb
### (user: "Why can't a user just use adapt if he needs it there?")

**The user is right, and my earlier defence is partly void by our own decision.** In the addendum to
finding 16 I gave three reasons for the `Array(...)`: (1) scalar-indexing consumers, (2) `Phenomenology`
is host-only by charter, (3) the transfer is ``O(N)``. **Reasons (1) and (2) rested largely on
`validate_spectrum`**, which finding 18(3) removes to `test/`. What survives is:

- **`integral_scale` is the only remaining in-package consumer** — and it does not need host arrays
  either. Its body is two reductions over an ``O(N)`` vector (`total += E[i]`, `weighted += E[i]/κ[i]`),
  which is a broadcast-plus-`sum` on any backend: `sum(E)` and `sum(ifelse.(κ .> 0, E ./ κ, 0))`, both
  returning host scalars without a vector readback and without scalar indexing (which invariant 4
  forbids on device arrays anyway — the present loop is only legal *because* of the `Array` call).
- **Reason (3) is an argument that the transfer is cheap, not that it should be automatic.** Cheap is
  not the same as wanted.

**And the same principle we just applied to the `(sim)` reads applies here.** Forcing `Array(...)` is a
convenience that imposes a cost the caller did not ask for — a **blocking device-to-host readback** on
the GPU path, in a GPU-primary package. `GBGPeriodicFields` now re-exports `adapt` (PF decision 63), so
the user has a first-class, documented, one-line way to ask for the host copy when they want it:
`adapt(Array, spec.energy)`. Doing it for them is exactly the class of unrequested help we removed nine
instances of in finding 19.

**Decision to record:** `energy_spectrum` returns the shell vectors in the **backend's own storage** —
device arrays on a device run — and the docstring says so, pointing at `adapt` for the host copy.
`integral_scale` computes its two sums as backend reductions and returns a host scalar, like
`kinetic_energy` (`0.5 * inner(u, u)`) already does — so the *scalar* observables keep their
unavoidable one-number sync, and no observable performs a *vector* readback.

*Consequences to check at implementation:* the optimality audit's host-device sync axis (its 8th) counts
readbacks — removing a vector transfer from `energy_spectrum` and folding `integral_scale` into two
device reductions changes what an occasional-diagnostic call costs, so re-derive rather than assume;
`test/validation.jl`'s moved `validate_spectrum` becomes the place that calls `adapt` explicitly, which
also demonstrates the intended user pattern; and `notation.md`'s `E_n` row (finding 14's new row) should
not imply a host array.


### 21. The `Cache` module docstring's opening — rewrite completely (`src/Cache.jl:13–18`)

User: "That's a very bad writing, rewrite it completely. 'an instant of the run's clock, not a face of
the periodic box;' is just gibberish. Plus 'stamp notion'. Too long of a sentence. And people know what
iteration is. And what is 'run stands at t_n'???"

All four are right, and one is provable from git.

**(a) "an instant of the run's clock, not a face of the periodic box" is a FOSSIL of decision 48 — mine.**
Before the rename (`8bc7a5e~1`) the text read: *"a **boundary** is the instant between iterations — the
state at one ``t_n``, after one advance and before the next **(an instant of the run's clock, not a face
of the periodic box)**"*. The parenthetical existed to disambiguate the word **boundary**, which on a
triple-periodic box is genuinely ambiguous. Decision 48 deleted that word from the whole corpus — and I
**kept the disambiguation and promoted it from a parenthesis to a main clause**. It now defends against
a confusion no text creates, and by naming "a face of the periodic box" it *introduces* the reading it
denies. Not merely dead: harmful.

**This is the fifth instance this round of "repair the flagged wording, keep the surrounding clause"**
(findings 2, 3, 6, 10, 11) and the first that is *provable* rather than inferred. It sharpens the rule:
**when a term is retired, delete the scaffolding that existed to support it** — the disambiguations,
the contrasts, the "not to be confused with" asides. They are load-bearing only for the word they
defend.

**(b) "the run stands at one ``t_n``"** — anthropomorphic and meaningless; a run does not stand
anywhere. Fossil of the same edit (it replaced "the state at one ``t_n``", which at least had a
subject).

**(c) "iteration" does not need defining.** The word is ordinary. What is *not* ordinary is that here it
includes the closing deposit and the particle push — but that belongs where it bites (`step!`'s
docstring already says a bare `step!` leaves the cache mid-iteration), not as a definition opening the
module map.

**(d) "stamp"** — finding 2's open class, still unresolved.

**Sentence shape:** one sentence, four clauses, three separators (`—`, `;`, `—`), two bolded
definitions. The module-docstring contract is *a map*: what the module is, then a linked one-liner per
operation.

**Draft for the rewrite** (settle wording with the user; two sentences, no coinage, no fossil, no
definition of a common word):

> The observables cache: the storage each iteration fills at its end with the observables it produced,
> for the run's own components and any observation to read. Each value is tagged with the iteration it
> came from, so a read that would serve a stale value throws instead.

Then straight into the operations list. Everything cut is either ordinary English (`iteration`),
documented where it bites (step ⊂ iteration), or scaffolding for a retired word.


---

## END-OF-ROUND TASK (user, 2026-08-17): re-audit the panel against this round's findings

When the read-through closes, **review the new `plain-sense` hat and all eleven others, and fold in
what this round proved they miss.** The round's findings are evidence about the *instruments*, not only
about the docs — every finding the user produced that no hat produced is a rubric gap.

**Method:** for each finding in this pile, ask *which hat should have caught it, and why didn't it?*
Then either (a) sharpen that hat's persona, (b) note the class as genuinely out of panel scope (needs a
deterministic scan or history), or (c) add a lane. Candidates already banked:
- **`plain-sense`** (built, `3f6ea21`) — re-read its persona against findings 3, 10(a), 11(b), 12(b),
  21: does its rubric actually produce each of them? If any is missed, the persona is still too narrow.
- **Existence auditor** (finding 19) — no hat asks whether a *public form* should exist.
- **Diff-aware / fossil lane** (finding 21) — the panel is history-blind by design; scaffolding orphaned
  by a rename is invisible to fresh eyes. `plain-sense`'s "unprovoked defence" test covers part of it;
  a git-scoped sweep of the sentences a rename touched is the cheaper, sharper form.
- **`/check-docs` scans** — the abutting-span grep (finding 14) and the citation-existence check
  (findings 7/8).
- **False-quantifier check** (finding 13) — "their plateaus gate warm-up" was false for 6 of 9 listed
  items; no hat verifies a quantifier item-by-item against the list it quantifies over. Candidate for
  `consistency-matrix` (it already enumerates) or a deterministic lane.
- **Cross-package parity** — several findings (7, 8) are *divergences from PF*, which no hat can see:
  every hat reads only IT's rendered docs. A parity lane would need PF's corresponding surface as a
  second substrate.

Also re-check the **cost-mode** assignment after any persona change: a rubric whose false negatives
have no downstream verifier is an anchor (the criterion that promoted `plain-sense`).


### 22. `max_speed` is the only unlinked name in the `Cache` map — finding 5's class, second instance
### (`src/Cache.jl:25`, `:71`)

User: "Why is max_speed so lonely unreferenced?"

Same mechanical cause as finding 5 (`recommended_cfl` in `SimulationDomain`): **`max_speed`'s docstring
is homed in `Observables`, so a bare `` [`max_speed`](@ref) `` written from `Cache` does not resolve** —
Documenter refuses cross-module fallback except for fully-qualified targets (the failure I hit on
`ConstantPower` during the panel fix pass). The link was not declined; it was awkward and skipped, and
the result is the one bare name in a list of five linked ones. Fix:
`` [`max_speed`](@ref GBGIsotropicTurbulence.Observables.max_speed) ``. **Two sites**: `src/Cache.jl:25`
(the map bullet) and `:71` (the `ObservablesCache` accessor list).

**This makes it a class, not a coincidence** — every backward cross-module reference in the package is
at risk, and three instances are now known (`recommended_cfl` ×6, `max_speed` ×2, `ConstantPower` ×1,
the last already fixed). **Candidate deterministic scan for `/check-docs`:** for each backticked
identifier in a docstring, if the name is exported by a *different* module than the docstring's own and
is not `@ref`-qualified, flag it. Mechanically checkable, and it would catch the whole class.


### 23. "Stamp" vs "epoch" — two names for one integer, and the relation is stated only in a `#` comment
### (`src/Cache.jl`, the module docstring and `# Fields`)

User: "What's the difference between stamp (mind the term, I flagged it previously as problematic) and
epoch?"

**The relation, from the code:** an **epoch** is a counter on the cache (`fields_epoch`,
`particles_epoch`) advanced by every completed `step!` and by the announce verbs; a **stamp** is the
epoch value recorded on one slot when it was deposited (`velocity_stamp`, `vorticity_stamp`, …). A read
is served **iff** `slot_stamp == cache.fields_epoch` (`src/Cache.jl:124`). Stamps additionally carry two
sentinels epochs never hold — `NEVER_DEPOSITED = -2`, `SCRATCH = -1`. So: **the epoch is the clock; the
stamp is the reading of that clock stored with a value.**

**None of that relation appears on a user-facing surface.** The module docstring defines "stamp" alone
("records which of these instants its value belongs to"); the `# Fields` list defines the epochs
separately ("the state's epoch: advanced by every completed step"); the sentence that ties them — *serve
the slot only when its stamp names the current epoch* — is an internal `#` comment at `:121–122`,
invisible in the rendered docs. A reader meets two nouns for the same integer and no statement of how
they relate, which is exactly the question asked.

**This strengthens finding 2 rather than being separate from it.** The house coinage is carrying two
distinct roles — counter and tag — with no vocabulary to distinguish them, while the standard
generation-counter idiom names both and makes the invariant obvious (a value is current iff its
generation tag equals the current generation). Whatever wording finding 2 settles on **must state the
relation, not just gloss "stamped"**: one sentence of the form "each value is tagged with the iteration
it came from; a read is served only while that tag matches the run's current iteration."


### 24. DECIDED — `resolved_fields_modified!` → `fields_modified!` (user, 2026-08-17)

The verb is renamed to match the **epoch it advances**. The cache's two counters are `fields_epoch` and
`particles_epoch`; the announce verbs should carry the same two names, giving the symmetric pair
**`fields_modified!` / `particles_modified!`**. The old name was the odd one out — named after the
*type* (`ResolvedFields`) while advancing `fields_epoch`.

`state_modified!` was weighed and rejected: it blurs against `particles_modified!`, since the tracer
positions *are* part of the run's state physically, so "state vs particles" is not a real dichotomy
where "fields vs particles" (Eulerian fluid fields vs Lagrangian probes) is exact.

**On future states — no proliferation, and it is already settled.** Decision 30: *"Epoch granularity is
deliberately coarse: one counter per **dynamical factor of the tower** (fields, particles), no finer."*
So the verb count is bounded by dynamical factors, never by state variables; §7's deferred inertial
particles ``(\boldsymbol{x},\boldsymbol{v})`` and oriented probes
``(\boldsymbol{x},\boldsymbol{v},\boldsymbol{L})`` would either ride `particles_epoch` or add exactly
one more factor. Record this in the rename's decision entry so the question is answered where it will
next be asked.

**Blast radius (verified):** 25 sites — `src/Cache.jl` (docstring, export, definition), the umbrella
`using`/`export`, `src/SimulationRun.jl` (the import; the `(sim)` forward is being deleted anyway by
finding 19), `src/State.jl` ×2 (the seeders' notes), `src/Propagator.jl` (`deposit!`'s note),
`docs/src/api/Cache.md`, `docs/src/observables_cache.md`, `docs/ARCHITECTURE.md` (§4.1 and the
decision-log entries — the log is append-only history and keeps the old name where it *records* it),
and `test/`. Land with the other renames (findings 11(e), 12(a)) in one commit.

**Also correct decision 30's stated rationale in the same pass.** It cites SciML's `u_modified!` →
`derivative_discontinuity!` as the lesson "name the verb for the violated invariant, not the mutated
slot" — and then names the verb after the mutated slot, as does the new name. The *code* is right and
the *rationale* is wrong: the caller knows what they modified, not what it invalidates, so announcing
one's own action is the better contract (the package decides what goes stale). Say that, rather than
claiming a lesson the package declines to follow.


### 25. DECIDED — one noun for both roles: `epoch`; "stamp" retired; and the epoch ≠ iteration
### distinction must be documented (user, 2026-08-17)

**Decision.** The per-slot tags are renamed from `_stamp` to `_epoch`, so one noun carries both roles:

| | before | after |
|---|---|---|
| the cache's counters | `fields_epoch`, `particles_epoch` | unchanged |
| the per-slot recorded value | `velocity_stamp`, `vorticity_stamp`, `scalar_stamp`, `max_speed_stamp`, `sample_fields_stamp`, `sample_particles_stamp` | `velocity_epoch`, `vorticity_epoch`, `scalar_epoch`, `max_speed_epoch`, `sample_fields_epoch`, `sample_particles_epoch` |
| the invariant | stated only in a `#` comment | **self-evident from the names**: a slot's epoch must equal the cache's epoch |

The word **"stamp" is retired entirely** — the coinage the user flagged three times (findings 2, 21, 23),
including "stamped storage", "the stamped slots", "stamped boundary observables". This is not a
compromise but the standard idiom: **epoch-based reclamation** compares a global epoch counter against
per-entity recorded epochs, and Julia's own world-age counter works the same way. Sentinels stay, now
described as *two epoch values no deposit ever has* (`NEVER_DEPOSITED = -2`, `SCRATCH = -1`).

**MANDATORY, per the user: document that the epoch is NOT the iteration number.** `iteration_id` was
weighed and rejected as **factually false** — measured, not argued:

```
after construction : step=0   fields_epoch=1
after 2 advance!   : step=2   fields_epoch=3
after 1 out-of-band: step=2   fields_epoch=4   ← step frozen, epoch advanced
```

They are offset from construction and driven by different events: `clock.step` advances only in
`advance!`; the epoch advances on `step!` completion **and** on every out-of-band announcement
(`fields_modified!`, `particles_modified!`), so a hand-run `step!`/`deposit!` loop moves the epoch and
never touches the clock. The hazard is concrete: the package exports `current_step(sim)`, and a reader
meeting a slot's `epoch` will otherwise assume it equals that.

**Where the distinction must appear** (a reader can meet the epoch at any of these):
- the `ObservablesCache` `# Fields` entry for `fields_epoch` / `particles_epoch` — the primary home;
- the `Cache` module docstring, in the sentence that replaces the retired "stamp" definition;
- `docs/src/observables_cache.md`, where the freshness design is explained at length;
- `current_step`'s own docstring — the reverse direction, so a reader coming from the clock is told
  it is not the cache's epoch.

**Wording to carry** (settle exact phrasing at fix time): *"The epoch counts changes of state, not
iterations: it advances when a step completes **and** whenever a mutation is announced out of band, so
it is deliberately not `current_step`. A value is served only while the epoch it was deposited at is
still the cache's current epoch."*

**Blast radius:** 114 "stamp" mentions across `src/`, `test/`, both doc pages and `ARCHITECTURE.md`
(the decision log keeps the old word where it *records* history), plus the 6 struct fields and the
`_checked` helper's argument name. Land with the other renames (findings 11(e), 12(a), 24) in one
commit — they are one vocabulary decision.


### 26. "register" — a borrowed term of art, 80 rendered uses, defined nowhere; worst in `Cache`
### (screenshot: `ObservablesCache`'s `# Fields`, `src/Cache.jl:82–83`)

User: "it seems that 'register' is undefined. I don't know what is the recovery register."

**Verified: 80 uses across rendered docstrings and doc pages, and no definition on any user-facing
surface.** The nearest thing to one is inside a `§11` decision-log entry (`architecture.md:1493`), which
a docstring reader never sees.

**The word has a legitimate home and has been extended past it.** In the low-storage Runge–Kutta
literature a *register* is the standard unit of scheme storage — Williamson's "2N-storage" counts
registers, and `IntegratorBuffers` cites it, so inside `Propagator` the term is at home and its meaning
is supplied by the citation next to it. Everywhere else it has been generalized to "any preallocated
field-sized array a component computes in", which is a **broader** meaning the RK sense does not
license: a physical-representation recovery buffer is not an RK register.

**The screenshot is the worst instance**, and for a structural reason: it appears in `ObservablesCache`'s
`# Fields`, where the reader is thinking about caching and has no Runge–Kutta context whatever — and the
compound is doubly opaque ("stage" + "recovery" + "register"). It is also **load-bearing**: that clause
carries the slot=register merge, one of the cache's two central design facts (decision 40). A core
sentence resting on an undefined noun.

**Spread by context:**
- `src/Propagator.jl` — ~14 uses. **Keep**; this is the term's home and the Williamson citation is
  adjacent. Add the one-clause gloss here, at the coinage point.
- `src/Cache.jl` — the `# Fields` entry (screenshot) and the module docstring's "a slot IS its
  producer's register".
- `src/Particles.jl:68, 77, 160` — "a stage register of the push" for `predictor_velocity`, which is
  ``M\times3`` point values, not a field at all. The furthest stretch of the word.
- `docs/src/observables_cache.md` — ~10 uses; §1.2's whole "surviving" argument is phrased in registers.
- `docs/ARCHITECTURE.md` — design-doc uses, lower priority.

**Direction (two options, decide at fix time):**
1. **Define once at the home and gloss on first use elsewhere** — "a *register* is a preallocated
   field-sized array a component computes in and reuses each step" — keeping the word, which is genuine
   vocabulary in the numerics literature and earns its place in `Propagator`.
2. **Use plain words away from the RK context** — the package already says *scratch* everywhere else
   ("assembly scratch", "spectral scratch", "per-step scratch"), so `Cache`'s `# Fields` could read "the
   arrays double as the step's working space: the step recovers into them mid-iteration and the closing
   deposit refills them", with no new term at all.

**Recommendation: 2 for `Cache` and `Particles`, 1 for `Propagator`.** The word is right where the
literature supplies it and wrong where the reader has no such context; "scratch" is already the
package's own plain word for the same thing, which makes this a *removal* of vocabulary rather than an
addition. Note this also interacts with finding 21's rewrite (the same module docstring) and with the
`stamp`→`epoch` pass — the phrase "a slot IS its producer's register" appears in both.


### 27. `particle_velocities`' `# Fields` entry explains another function's mechanics — cut it
### (`src/Cache.jl:88–91`)

User: "'(the tracer set's own point-value storage, whose (M, 3) array the accessor extracts with
point_values),' — unclear what is meant and why it is needed."

**Not needed, and mine.** `git log -S` names `ebfde77` — the check-docs battery, where I closed the
panel's category-error finding (the entry conflated the storage *container* with the *array*). The
correct repair was to make the existing words name the container, which the first half already does
("the tracer set's own point-value storage"). Instead I **appended** a clause describing what a
*different function* does.

Three reasons it goes:
1. **Redundant** — the accessor's own docstring, a screen away, already says "the ``(M, 3)`` array of the
   flow velocity sampled at the position each tracer occupies at that instant".
2. **Wrong place** — a `# Fields` entry documents what the field *holds*, not how a reader gets at it.
3. **`point_values` is an unexported `GBGPeriodicFields` internal** — naming it tells a user about a
   function they have no reason to know and cannot usefully call.

**What is missing from the entry and should replace it:** the slot **aliases** the tracer set's storage
— the cache allocates nothing for it (decision 42). That is the memory-relevant fact a `# Fields` entry
exists to carry, and today it appears only in the constructor prose above.

*Direction:* "`particle_velocities` — the tracer set's own point-value storage, stamped here rather than
copied (the cache allocates nothing for it), or `nothing` for a tracer-free run; `sample_fields_epoch` /
`sample_particles_epoch` are its epochs against **both** counters, since the sample is a function of the
state and the positions together." (Wording folds in the finding-25 rename.)

**Third accretion instance with a git receipt** (after finding 21's fossil and finding 11(b)'s
parenthetical). The pattern is now well evidenced enough to state as a rule for the fix pass: **when a
review flags a clause as wrong, the default repair is to correct or delete the offending words — adding
a clarifying clause beside them is the exception, and needs a reason.**


### 28. `particle_velocities`' predictor Note — cut it (`src/Cache.jl:205–209`)

User: "I think this note is redundant. Who would think of reading the predictor step? Plus, that's
dependent on the particle integration scheme."

Three reasons, all confirmed:
1. **Unprovoked defence** — a reader reaching for the Lagrangian sample is not wondering about a
   predictor stage. **First finding this round that the new `plain-sense` hat's test 3 would have
   produced** — useful validation of `3f6ea21`.
2. **Scheme-dependent** — "the corrector stage of the predictor–corrector push" is *Heun*-specific
   (`Particles.jl:6` fixes Heun-in-time). §7's deferred inertial ``(\boldsymbol{x},\boldsymbol{v})`` and
   oriented probes use the exponential-drag integrator, which has no corrector stage; a cache
   accessor's docstring should not carry a fact owned by one tracer scheme.
3. **Duplicate of its home** — `Tracers`' field list already states it better and where it belongs
   (`Particles.jl:67–68`): *"`predictor_velocity` — the interpolated velocity at the Heun predictor
   positions, which no tracer ever occupies: a stage register of the push, never a sample of the flow,
   and never exposed."* One concept, one home; decision 42's forbidden ``v_2``-as-``v_1`` reuse is
   stated at the thing it constrains.

Cutting it also removes one use of "register" (finding 26) for free.


### 29. The `Forcing` map inserts a TYPE into the four-hook list, breaking its stated order
### (`src/Forcing.jl:26–27`)

User: "The order is illogical. I thought the four stages should be together, not interrupted by
DeferredForcing."

The list is introduced as *"up to four methods, each defaulting to doing nothing (listed in **the order
the step fires them**)"* — and `DeferredForcing`, a **type**, sits as bullet 2 of 5. It has no firing
position, so the stated ordering is false, and a type in a list of methods is a category slip.

**Mine, via git: `0baddf3`**, closing the panel's finding 05#4 ("`DeferredForcing` is absent from its
module's contents map"). It is also **redundant** — the closing paragraph already introduces it ("An
operator-free keyword constructor … returns a `DeferredForcing` that a `Simulation` materializes once
the domain exists"), which is precisely the trailing sentence the hat objected to; I added a bullet and
left the sentence, so it is now documented twice.

*Fix:* move the bullet to the **first** list, beside `AbstractForcing` — that list is the module's
types — leaving the hook list exactly four items in firing order. Then shorten or drop the trailing
duplicate.

**Fourth "fix by insertion" with a git receipt** (findings 21, 27, 11(b), this). The refined pattern:
*when a review says "X is missing from the map", I insert X into the nearest list rather than the
correct one.* Add to the fix-pass rule: **an insertion must satisfy the list's own stated contract** —
if the list says "four methods in firing order", only a method with a firing position may join it.


### 30. `AbstractForcing` says "a per-step state advance" — "state" is a term of art here
### (`src/Forcing.jl:57`, and `:69` in the same docstring)

User: "(a per-step state advance) — make it here more clear that's the forcing's state, not the
simulation state."

**The package's own surfaces already disagree, and the vague one is the most detailed:**

| surface | wording |
|---|---|
| `prepare_forcing!`'s docstring (`:159`) | "Update the strategy `forcing`'s **internal state**" ✓ |
| the `Forcing` module map (`:25`) | "a per-step **internal-state** advance" ✓ |
| **`AbstractForcing` (`:57`)** | "a per-step **state** advance" ✗ |

The correct reading does appear in the same docstring — but two paragraphs later ("what it advances is
the forcing's own internal state"), after the reader has already parsed the identity sentence.

**Why the bare word is wrong here specifically:** *state* is a **term of art** in this package — the
`State` module, `ResolvedFields`, `sim.state`. A hook described as performing "a per-step state advance"
reads as advancing *the run's* state, which would be alarming. Same collision class as finding 11(e)
(`state.velocity` spectral vs `cache.velocity` physical): a loaded noun reused for a different object
with no qualifier.

*Fix:* "(a per-step advance of the forcing's own internal state)", matching the two sibling surfaces.
**Also `:69` in the same docstring** — "the state a later hook consumes must be prepared here" — same
bare noun, one paragraph down; make it "the forcing state".

*Sweep at fix time:* every bare "state" in `src/Forcing.jl` that means the forcing's own (`:15`, `:355`,
`:368` are `#` comments/fields and lower priority, but `:216`'s "the closest reachable state" is prose
and should be checked).


### 31. "`target` is the observable the forcing holds" — it is the observable's VALUE, a number
### (`src/Forcing.jl:207`; comment at `:231`)

User: "it is the value of the observable, not the observable itself. Right?"

**Right — confirmed three ways in the code.** `target::Real` in both keyword constructors (`:235`,
`:312`), `target::T` in both structs, and it is used arithmetically:
`max(zero(band_value), forcing.target - total_value + band_value)` (`:250`),
`forcing.target / (2 * band_observable)` (`:325`). It is a number.

**Class: a diagnostic scalar conflated with the quantity it is a value of** — one of the category errors
the doc policy names by name ("a diagnostic scalar with the field it reduces"). The sentence slipped
because it carries two facts at once: (a) `target` is a number, and (b) *which* observable that number
is a value of depends on the field type — kinetic energy for a vector, scalar variance for a scalar.
Separate them and it is correct.

*Direction:* "The `target` is the **value** the forcing holds that field's ``L^2`` observable at — the
kinetic energy ``\tfrac{1}{2}\langle\lvert\boldsymbol{u}\rvert^{2}\rangle` (`kinetic_energy`) for the
velocity, the scalar variance ``\langle\varphi^{2}\rangle`` (`scalar_variance`) for the scalar, the
``\tfrac{1}{2}`` carried only for the vector."

**Spread — and the two structs contradict each other:**
- `src/Forcing.jl:231` — `BandRescaling`'s field comment: "the **observable** to hold: kinetic_energy
  (velocity) or scalar_variance (scalar)" — same slip, on the line that declares it `::T`.
- `src/Forcing.jl:309` — `ConstantPower`'s field comment: "the **dissipation rate** to hold", and its
  docstring (`:290–296`): "so `target` is the **dissipation rate**, chosen to agree with the diagnostics:
  `dissipation` ``\varepsilon`` …". **ADJUDICATION CORRECTED (user, same session):** I first called this
  one correct on the grounds that "a rate is a value". Wrong — the same class, milder. A *rate* names a
  quantity (``\varepsilon``, dimensions ``L^2T^{-3}``); the `target` is a **value** of it. The docstring
  then slides value → quantity → function in one sentence by listing the two observables as what
  `target` "is".
  *Direction:* "so `target` is the **value of the dissipation rate** the run settles at, matching the
  diagnostics that measure it — `dissipation` ``\varepsilon`` for the velocity, `scalar_dissipation`
  ``\varepsilon_\varphi`` for the scalar."
  **Preserve the dimensional contrast** in the following parenthetical ("A rate — note the contrast with
  `BandRescaling`, whose `target` is a held amplitude"): it is genuinely informative, since the two
  targets differ in dimension (``L^2T^{-2}`` vs ``L^2T^{-3}``). Reword, do not cut.
- `ConstantPower`'s docstring and `Simulation`'s "a `BandRescaling` holds the total (whole-field) energy
  at `kinetic_energy`" — the latter reads as holding a value *at a function*; check both in the pass.


### 32. The defaults rationale is coherent but stated nowhere a user can read it — and `over` is the
### one default UP FOR RECONSIDERATION (`src/Forcing.jl`, the three keyword constructors)

User: "I forgot what is the policy on the defaults? I like it here, on the other hand, not having them
prompts the user to understand the options…"

**The policy is decision 28, and it has two categories** (`ARCHITECTURE.md:1057–1060`): low-level
*assembly* types (`FixedDomain`, `FlowConditions`, the seeders, `Tracers`) carry **no** defaults, while
**model/preset types keep their canonical parameters** (`Pope2000`, `HouLi`, …).

**The test that separates them — write this down, it is the useful part:** *does the value come from the
**method**, or from **this run**?* Method-canonical → default; run-specific → required. The forcings
already obey it exactly:

| keyword | default | why |
|---|---|---|
| `target`, `rate` | **none, required** | no canonical energy or rate exists — a property of the run |
| `lowest_shell = 1`, `highest_shell = 2` | yes | the canonical large-scale forcing band in HIT |
| `over = :band` | yes | **see below** |

So the user's tension mostly dissolves: the defaults that exist do **not** hide a choice the user must
make, and the choice that does matter is required. Same shape as `HouLi(; order = 36)`.

**THE DOC DEFECT:** the test exists only in a §11 decision-log entry. From the docstrings alone a reader
cannot tell why `target` is required and `lowest_shell` is not — which is why the user has now asked
about defaults **twice** (finding 6 was the same policy from the other side). *Fix:* one sentence in the
`Forcing` module map — "A strategy's canonical band parameters default; what a run holds — `target`,
`rate` — never does." Consider the same sentence, adapted, wherever a preset type defaults
(`HouLi`, the `Phenomenology` laws).

**⚠ UP FOR RECONSIDERATION — `over = :band`.** This is the weakest default in the file by the package's
own reasoning. `ARCHITECTURE.md:872–876` calls it *"a modeling choice with two defensible answers, so it
is a selectable option rather than a fixed default"* — yet it **is** defaulted, and the two answers are
not equivalent physics: `:band` holds the forced band's energy and lets the whole-field value float,
while `:total` pins ``u'`` and hence the scale of ``\mathrm{Re}_\lambda``. By the method-vs-run test it
is a **run** decision (what does your run hold fixed?), which argues for requiring it. Against: it would
make every `BandRescaling` call longer, and the front door already overrides it to `:total` for the
default run — so the two surfaces disagree about which answer is the natural one, which is itself a
signal.

Not decided. Options at fix time: (a) leave defaulted, state the rationale; (b) require `over`
explicitly; (c) leave defaulted but align the front door so the two surfaces stop disagreeing.


### 33. `ResolvedGenerator`'s two sentences run 52 and 55 words; `Simulation` is never linked from any
### upstream module (17 sites); and the generator-vs-cache storage split is never stated

Three items from one screenshot (`src/Generator.jl:141–175`).

**(a) Sentence length.** Measured: the opening sentence is **52 words**, the next **55** — each carrying
three clauses plus a parenthetical (identity + contents list + protocol walk-through). Same shape as
finding 10's 71-word sentence; split them.

**(b) `Simulation` is unlinked everywhere upstream — 17 bare mentions**, `Cache.jl` 5, `Forcing.jl` 4,
`Propagator.jl` 4, `Particles.jl` 2, `Observables.jl` and `Generator.jl` 1 each. **Third and largest
instance of the cross-module `@ref` class** (findings 5, 22): `Simulation` is homed in `SimulationRun`,
included last, so a bare `@ref` cannot resolve and the link was skipped. It is the worst case of the
three — the package's front door, referenced from six modules and linked from none. **Class total now
25 missing links** (`recommended_cfl` 6, `max_speed` 2, `Simulation` 17), which settles that the
deterministic scan proposed in finding 22 is worth building.

**(c) The storage-ownership split is real and unstated** — user: "aren't those in the cache? Or are
those extra buffers? It should be stated clearly, that's not the same as in cache."

**They are extra buffers, owned by the generator, allocated in its own constructor**
(`src/Generator.jl:107`, `:198` — `new_vector_field_spectral(domain)`), and the memory audit ledgers
them apart from the cache (the retired `OWNERSHIP` holder existed precisely for the seam between "the
cache's recovery scratch" and "the generator's", `test/memory_audit.jl:190`).

**Why the confusion is the docstring's fault, not the reader's:** the same `# Fields` list mixes the two
kinds without marking the boundary. `product_spectral` is generator-owned — but its own entry then says
each physical product "is formed in place over an operand's own register — the Lamb vector over the
**vorticity's**, the flux over the **velocity's**", and those registers *are* the cache's slots
(decision 41). So one bullet references cache storage while describing a generator field, with nothing
saying which is which. The true picture, which no single surface states:

| storage | owner | note |
|---|---|---|
| physical ``\boldsymbol{u}``, ``\boldsymbol{\omega}``, ``\varphi`` | **cache** | the quadratic products are formed *in place over these* |
| `product_spectral` (the products' spectral image) | **generator** | extra buffer |
| `phase_shift` buffers + translation kernels | **generator** | extra, `PhaseShift` only |
| the scheme's spectral stage registers | **`IntegratorBuffers`** | per-scheme |

*Fix:* one clause in the `ResolvedGenerator` docstring stating that the assembly scratch is the
**generator's own** storage, distinct from the cache's slots — and that the physical products are
nonetheless formed over the cache's arrays rather than in generator storage. Both facts are load-bearing
for anyone reasoning about footprint, and today each is inferable only by cross-reading three docstrings
and a decision entry.


### 34. `max_speed`'s CFL gap; and whether CFL buys accuracy (`src/Observables.jl`, `Propagator.jl`)
*(answered in conversation; logged for the doc consequence)*

User: "Is that gap because between the nodes the velocity can be larger? … Just tell me." — Yes: the
reduction is over grid nodes, and the continuum supremum between them is larger; the ``\sqrt{3}``
factor is the *other* gap (a per-component bound versus the vector norm), and PF ships
`maximum(norm, u)` as a single-pass mapped reduction, so the ``\sqrt{3}`` slack is an unexamined cost,
not a necessary one. User: "Is CFL condition enough to ensure accuracy, not only stability?" — No; CFL
bounds the *stability* of the explicit advective term only. **Doc consequence:** `recommended_cfl`
and `max_speed` should say which of the two gaps each carries, and the CFL discussion should not
leave the reader with the impression that satisfying it certifies accuracy.


### 35. `record_particle_velocity!` — "put on record", "push" (`src/Particles.jl`)
User: "put on record, what is that record?! And what is that push? Completely unclear without broader
context. Some hat should have flagged both." — Two **ordinary words carrying package-specific
meanings**: the *record* is the `trajectory_velocity` slot (which is also the cache's
`particle_velocities` slot), and the *push* is the Heun advance of the tracer positions. Neither is
introduced. Same class as *deposit* / *stamp* / *register* / *chart*. **Instrument note:** the
`cold-reader` hat hunts undefined *technical* terms; it must also hunt **familiar English words used
as terms of art**, which read as prose and so never trip an "undefined symbol" check.


### 36. `velocity_buffer` allocates a *generic* vector buffer but is named for one use
(`src/Particles.jl:206`, `:214`)
User: "WTF, you allocate a vector buffer, but call it velocity. I could have sampling e.g. scalar
gradient." — Correct: the body is `VectorPointValues(similar(tracers.positions))`, which knows nothing
about velocity; the docstring even concedes it ("for use as the `out` of `sample!` **when sampling the
velocity**"). The name is the *first anticipated use*, not the object. *Fix:* the allocator naming
convention already settled for the cache — `new_<Type>` — gives `new_vector_point_values(tracers)` /
`new_scalar_point_values(tracers)`, and the docstrings then describe the shape, not one caller.


### 37. `sample!` — the verb collides with the noun *sample*, and says nothing about interpolation
(`src/Particles.jl:172`)
The recorded Lagrangian velocity is called "the genuine Lagrangian **sample**" (`:65`), the cache has
`deposit_sample!` (`src/Cache.jl:244`), and `sample!` is the *operation*. Three uses of one word for
two different things. The operation is: evaluate a Eulerian field at the particle positions by
interpolation. **Naming (settled in conversation): `interpolate_at_particles!`** — see 38 for the
noun.


### 38. *particle* vs *tracer* — three nouns for one concept, and no stated convention
(`src/Particles.jl:32`, `src/Cache.jl`)
User: "Tracer is just a specific type of particles, non-inertial, with no inner degrees of freedom.
Don't we have a convention on tracer vs particle distinction?" — **We do not**, and the export line
contradicts itself:

```julia
export Tracers, record_particle_velocity!, advect!, sample!,
       particle_positions, number_of_tracers, velocity_buffer, scalar_buffer
```

`particle_positions` and `number_of_tracers` sit adjacent, name the same set, and use different nouns;
add `particle_velocities` (Cache) and `trajectory_velocity` (the field) for a third. `CLAUDE.md` says
only "Lagrangian tracer tracking (`Tracers`)". ARCHITECTURE §7 already implies the right rule via the
deferred ladder ("today a tracer (position ``\boldsymbol{x}``); the deferred ladder is inertial and
oriented probes").

**Convention to record as a decision:** *name by what the operation is true of.* Anything true of the
whole ladder takes **particle** — positions, count, the cache slot, field interpolation at positions;
only what is specific to the massless, internal-degree-of-freedom-free kind takes **tracer** — the
`Tracers` type and its construction. Consequences: `interpolate_at_particles!` ✓ (an inertial particle
needs the same interpolation for its drag term, so the name survives the ladder unchanged);
`particle_positions` ✓ already right; **`number_of_tracers` → `number_of_particles`**; `advect!` keeps
its generic verb and dispatches per kind (its Heun push *is* tracer-specific physics — an inertial
particle integrates ``\mathrm{d}\boldsymbol{v}/\mathrm{d}t = (\boldsymbol{u} - \boldsymbol{v})/\tau_p``).


### 39. **Conventions hats** — the panel has no reader that checks our own rulebook
User: "probably we should have hats that check if our conventions are followed. … Not mechanical, just
readers." Eleven of the twelve hats are **forbidden `CLAUDE.md`**, and two (`style-editor`,
`structure-consistency`) are explicitly told to derive norms "from the corpus itself (majority style),
not an external guide" — so a convention violated *uniformly* is invisible to the whole panel, and the
rulebook never outranks observed practice. Findings 36, 37 and 38 are all of exactly that shape.
*Proposal:* three rulebook-holding hats — **naming-policy**, **doc-policy**, and
**invariants-and-decisions** — each given `CLAUDE.md` (and §11) as authoritative, with the standing
instruction that **the rulebook outranks the corpus**. Fold into the end-of-round panel review.


### 40. `Tracers`: which arguments are keyword is unprincipled — and this is round 1's finding 4a,
### fixed on one line instead of swept as a class (`src/Particles.jl:37`, `:82`, `:94`)

User: "Why are some arguments named, while others not? Did we note that problem before in that read?"

**Yes — verbatim.** Round-1 pile finding 4a: *"Why only the two of them are named? Make them all
named."* It was applied to `FixedDomain` alone (commit 3d6ff88, now `FixedDomain(; grid_points_per_axis,
side_length, …)`) and **never swept**. That is the "fix the line, not the class" failure the doc
discipline explicitly forbids, caught by the user two rounds running.

The class as it stands:

| constructor | shape |
|---|---|
| `FixedDomain`, `FlowConditions`, `FlowParameters`, `StationarityMonitor`, `HouLi`, `Linear` / `ConstantPower` / `BandRescaling`, `Simulation(; …)` | **all keyword** |
| `ResolvedFields(domain; scalar)`, `ObservablesCache(domain; scalar, particle_velocities)`, `Simulation(domain; …)` | positional `domain`, keyword tail |
| `ResolvedGenerator(domain, conditions; scalar)` | two positional |
| `Tracers(domain, number_of_tracers; scheme, rng)`, `Tracers(domain, positions; scheme)` | two positional |
| `Reference(citation; valid_Reλ)` (Phenomenology) | positional head |

There *is* an unwritten rule underneath — **the object a value is derived from is positional; its
settings are keyword** — which is the domain-derived-constructor convention the user endorsed earlier.
Under that rule `Tracers` is the genuine outlier: `number_of_tracers` and `positions` are *settings*,
not source objects, so they should be keyword; and `scheme` is a **required keyword** sitting beside a
required positional, so the split cannot even be read as "required positional / optional keyword".

Two defects, then: (a) `Tracers`'s second positional violates the rule; (b) **the rule is documented
nowhere**, which is precisely why the docstring cannot answer the reader's question. Fix (b) in
`ARCHITECTURE.md` (a decision entry) and fix (a) with the signature.


### 41. `particle_velocities` is the only unlinked name in its sentence — and the cross-module link
### class is **83 sites, not 25** (`src/Particles.jl:55`)

User: "particle_positions and number_of_tracers are linked, while particle_velocities are not."

Confirmed at the source — `particle_positions` and `number_of_tracers` are `@ref`-linked, and the third
is a bare backtick span:

```
Read the particle state with [`particle_positions`](@ref) and [`number_of_tracers`](@ref); the
trajectory velocities are read from the run's observables cache (`particle_velocities`), where the
```

The distinguishing fact is that `particle_velocities` lives in **`Cache`**, not `Particles` — the
cross-module `@ref` that fails to resolve unless fully qualified (the `ConstantPower` build failure of
this round). The failure mode is that the author silently *downgrades* the link rather than qualifying
it, so a broken link never reaches the build — it becomes a missing one. Three names in one sentence,
two linked, one not, reads to the user as a deliberate distinction.

**The class is far larger than reported.** My earlier count of "25 missing links" was a hand-picked
subset (`recommended_cfl`, `max_speed`, `Simulation`), not the class. Enumerating properly —
every umbrella export cited in docstring prose, first mention, never `@ref`-linked anywhere in that
docstring, excluding the docstring's own binding — gives **83 sites**, spread over every module
(`Propagator` 15, `Generator` 12, `Observables` 8, `SimulationDomain` 7, `Phenomenology` 5,
`Particles` 4). This settles finding 22: the deterministic scan is worth building, and it must
enumerate the **class** rather than a list of names I noticed.


### 42. `Tracers` mixes trajectory **state** with one integrator's **scratch** — CODE/ARCHITECTURE
### (`src/Particles.jl:71–80`, `advect!` at `:152`)

User: "Here we mix the state of the tracers with the integrator, no? What if we change the integrator?"

Three of the seven fields are Heun-specific, and the docstring says so itself — `predictor_velocity` is
"a **stage register of the push**, never a sample of the flow, and never exposed":

| field | kind |
|---|---|
| `positions`, `position_points` | state — the trajectory |
| `trajectory_velocity` | the recorded observable (the cache's particle-velocities slot) |
| `predictor`, `predictor_points`, `predictor_velocity` | **Heun stage scratch** |
| `scheme` | the interpolation method |

**The package already established the correct split and the Lagrangian side does not follow it:**
`ResolvedFields` is the state, `IntegratorBuffers` the per-scheme scratch, built by
`allocate_buffers(integrator, domain; scalar)` — which allocates *different* register sets for `IFRK2`
and `IFLowStorageRK3` (`src/Propagator.jl:418`, `:426`). The tracers hardwire one scheme's registers
into the state type instead, and `advect!(tracers, velocity_end, domain, dt)` takes no integrator
argument at all: the flow integrator is a dispatched object, the particle pusher a hardwired code path.

**The axis is recorded as planned, not hypothetical** — ARCHITECTURE §7: "the trajectory integrator —
today a single second-order Heun push, with **higher-order pushers the studied future axis**"; and the
memory audit already models "the particle-integrator axis" as an axis with one point (decision 34).
The scratch genuinely changes shape along it: RK4 wants several stage velocities and intermediate
position sets; AB4 (TurTLE's actual choice) wants **no predictor** but a 4-deep velocity history; an
inertial pusher adds ``\boldsymbol{v}`` as *state*, not scratch.

*Fix (code):* `Tracers` keeps positions, the point views, `trajectory_velocity`, and `scheme`; an
`AbstractParticleIntegrator` (Heun today) carries the push; `allocate_buffers(pusher, tracers)` builds
the predictor set — particle-named, per finding 38. A side benefit: it disentangles
`trajectory_velocity`'s two present roles (the measured observable, and "the first half of the next
Heun push"), so a history-based scheme would not disturb the observable.
