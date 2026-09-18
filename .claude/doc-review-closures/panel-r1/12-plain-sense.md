# Closure — Hat 12: Plain-sense editor

21 findings enumerated from the banked hat file. One verdict each, from the current corpus only.

---

## 1. Front-page quick start dates a deposit by "the iteration"

**PARTIAL**

The specific contradiction is fixed: `docs/src/index.md:47-48` now reads "each stamped with the
epoch of the state they were computed from" (not "tagged with the iteration it belongs to"), and
"stamp" is the glossary's own sanctioned verb (`notation.md:122`: "the value of that counter
stamped on it when it was filled") — no longer a revived retired verb. But the anthropomorphism the
same finding flagged survives verbatim at the same location: `index.md:47-48` — "the write in which
the iteration hands the cache the observables it has just computed" — the iteration still "hands"
the cache something.

**Surviving class**: `docs/src/index.md` lines 47-48, "the iteration hands the cache the
observables" — no other instance found (`rg` for "hands the cache" is a single hit).

---

## 2. Glossary's "resolved" denies the sense its sibling names depend on

**PRESENT**

`docs/src/notation.md:126` — "in `ResolvedFields` and `ResolvedGenerator`, *made concrete as one
value*. The numerical sense — a scale the grid resolves … — is the other reading … " still denies
the grid/resolution sense for these two names. `docs/ARCHITECTURE.md:1180-1181` still names the
naming axis as "resolved against filtered" ("`ResolvedFields` ↔ `ResolvedGenerator`, resolved
against filtered, with `FilteredGenerator` … the eventual LES sibling") and `:1065-1066` calls
`ResolvedFields` the DNS-scale representation against `FilteredFields` (LES) as its sibling —
exactly the resolved-vs-filtered *scale* axis the glossary disclaims. The contradiction is unchanged
in substance; only minor rewording ("and the docs write it out in full wherever it is meant") was
added.

---

## 3. Two definitions of "iteration"

**ABSENT**

`docs/src/notation.md:119` now reads "one advance of the run: choose the timestep, `step!` the
fields, advance any tracers, then the `deposit!` that closes it" — includes the timestep choice and
the tracer push. `docs/src/observables_cache.md:29-30` — "the timestep choice, the step, the
particle push, and the deposits at its end" — the two definitions now match on content. Checked both
files directly; no other "iteration" definition found via `rg -n "^\*\*iteration\*\*|An
\*\*iteration\*\*"`.

---

## 4. "Write, then record" inverts the function's own name

**PRESENT**

`src/Particles.jl:225-244` (`record_particle_velocities!`): "This call is that slot's only producer of
values, but it writes values only: the slot becomes readable once `deposit_sample!` records them as
current. Write, then record — a run does both at the end of each iteration…" The function named
`record_particle_velocities!` is still cast in the "write" role while "record" is assigned to
`deposit_sample!`. The one part of the finding that is fixed: the second call is no longer
anonymous — it is now named and `@ref`-linked (`deposit_sample!`), and `deposit_sample!` itself
(`src/Cache.jl:262-278`) has a full docstring confirming the same "record"-labelled role. The name
inversion itself is unchanged.

---

## 5. A docstring instructs calling a verb documented nowhere

**ABSENT**

`deposit_sample!` now has a full docstring at `src/Cache.jl:262-278`, is exported
(`src/Cache.jl:57`), is listed on the Cache module map (`src/Cache.jl:28`), and appears in the
rendered `docs/build/api/GBGHomogeneousTurbulence/index.html` Index
(`../Cache/#GBGHomogeneousTurbulence.Cache.deposit_sample!`, confirmed by grep on the built HTML). The
instruction in `particles_modified!`'s docstring now points at a documented, indexed call.

---

## 6. "A `Simulation` is a container, not a reading surface" fossil

**PARTIAL**

The `SimulationRun` module docstring (`src/SimulationRun.jl:17-31`), one of the four locations named
in the finding, is rewritten to drop the denial and keep only the positive clause: "Read a run's
state through `sim.state` and its deposited observables through `sim.cache`, with the observables
and cache accessors that own them; the run layer adds no forwarding methods of its own." The other
three locations named in the same finding are untouched, verbatim:
- `docs/src/index.md:114-115` — "A `Simulation` is a container, not a reading surface: the state is
  read through `sim.state`…"
- `docs/src/api.md:20` — same sentence.
- `docs/src/architecture.md:465` — "**A `Simulation` is a container, not a reading surface**
  (decision 49)."

**Surviving class**: `docs/src/index.md:114`, `docs/src/api.md:20`, `docs/src/architecture.md:465`
(and decision-log entry 49 at `:1676`).

---

## 7. "Observation" names both the callback and the instant

**ABSENT**

The glossary entry was rewritten to state both senses explicitly in one home, resolving the
cross-page contradiction: `docs/src/notation.md:125` — "the callback a run is driven by … By
extension the *occasion* — 'computed at an observation' means computed in that callback, between
iterations, from what the run already holds." This now licenses the "at an observation" /
"observation builds it" usages on `observables_cache.md` (`:34, :86, :139-146`) and `run!`'s
"until the observation stops it" (`src/SimulationRun.jl:414`) as the documented extended sense, not
a contradiction of a callback-only definition.

---

## 8. `FlowConditions` "Consumed by the time step" vs. "a scheme holds no conditions"

**ABSENT**

`src/Generator.jl:64-65` now reads "Read through the [`ResolvedGenerator`](@ref) a scheme is handed
— [`step!`](@ref …) never holds conditions itself" — the false "consumed by the time step" claim is
gone and the docstring now agrees with `docs/ARCHITECTURE.md:310` ("A scheme consumes the physics
only through this protocol"). Searched `src/Generator.jl` for "Consumed by the time step" — no hits.

---

## 9. Module-placement rationale behind an ambiguous "It"

**ABSENT**

`src/Cache.jl:33-35` now reads "The solver's side of the contract is `deposit!` … A caller reads
through the accessors and never deposits. `deposit!` lives in `Propagator` rather than here because
it needs the scheme's own scratch to recover the fields, and that is the module owning the iteration
it closes." The subject is now the explicit name `deposit!`, not the pronoun "It"; the nearest
antecedent for the remaining "it"s in the sentence is unambiguously `deposit!`.

---

## 10. Argument-order paragraphs explain shape, not use

**ABSENT**

`step!`'s docstring (`src/Propagator.jl:196-198`) now reads "Call it with the same arguments in the
same order as `deposit!`, the call that closes the iteration: the dispatch object first, then
`state`, `domain`, `buffers`. Only the extras differ — `generator` sits directly after `state` here,
and `cache` and `dt` come last — so the two calls of a hand-run loop read as a pair." The
unparaphrasable "transposes nothing" / "interleaves two more" language is gone (`rg` for both
strings in `src/Propagator.jl` returns no hits); the replacement is concrete and actionable (helps a
hand-run loop match positional arguments across the two calls), with `deposit!`'s own paragraph
(`:497-499`) now cross-referencing it symmetrically rather than independently re-deriving the shape.

---

## 11. "carries `_consumed` … because it is" defers its own meaning

**ABSENT**

Both docstrings now state the fact plainly and immediately, not by forward reference:
`src/Generator.jl:303-304` — "The vorticity argument is named `ω_consumed` because the assembly
overwrites it: on return it no longer holds the vorticity." and `:452-454` (scalar) — "The velocity
argument is named `u_consumed` because the assembly overwrites it: on return it no longer holds the
velocity." The admonitions below (`:329-339`, `:474-482`) now add distinct content (the in-place
cross-product/footprint rationale, and the cross-reference between the two functions) rather than
repeating the same "because it is" fact a third and fourth time.

---

## 12. Sentences carrying five clauses

**PRESENT**

Both quoted sentences are structurally unchanged. `docs/ARCHITECTURE.md:70-73` — "The run layer
holds the pieces of §4 in one `Simulation` value, chooses a stable timestep each iteration …, serves
the deposited observables …, and runs the **observation-first loop**: after every iteration … (§11
decision 43)." — measured at 70 words, still four coordinate clauses plus a colon-introduced fifth
idea and three parenthetical section cites. `docs/src/observables_cache.md:145-148` — "Only the last
closing deposit has no following iteration to fold into — it serves the final observation instead —
so, relative to a cacheless solver …, the run pays **one** extra closing deposit — the state-only
share of one first-stage evaluation, one reduction, and one interpolation — once per run." —
measured at 55 words; the closing noun phrase is unchanged and still requires §1.4 to unpack.

---

## 13. Same parenthetical rebuttal in four places, unprovoked in the fourth

**ABSENT**

The `max_speed` docstring (`src/Observables.jl:128-152`) no longer contains any "constant-energy
forcing forms `k` mid-step" parenthetical — searched the full docstring text; the qualification is
absent. It survives only on its home page, `docs/src/observables_cache.md` (`:189`, `:347`), where
it belongs (two statements, not the finding's three, but confined to the design page rather than
recurring in the unrelated `max_speed` docstring).

---

## 14. `max_speed` re-argues `recommended_cfl`'s margin

**ABSENT**

`src/Observables.jl`'s `max_speed` docstring no longer contains "the two are independent, so the
second is not guaranteed to cover the first" — searched, no hits. `src/Propagator.jl:538-539`
(`recommended_cfl`) is now the sole home: "The conservative factor below exists because the second
is not guaranteed to cover the first."

---

## 15. "not the absence of one" defends against a reading nobody has

**ABSENT**

`src/Forcing.jl:243-248` (`BandRescaling`, `:total` bullet) now ends "…so `L_{11}`, `u'` and
`\mathrm{Re}_\lambda` are meaningless for turnovers afterwards — the most violent intervention the
rescale can make. Here `k` is the artifact and the band is free." The dangling "not the absence of
one" clause is gone; searched `src/Forcing.jl` for the phrase, no hits.

---

## 16. Cost-accounting vocabulary arrives without its argument

**PARTIAL**

`deposit!`'s docstring (`src/Propagator.jl:482-483`) is rewritten to carry its own premise inline:
"Every recovery here is work the next iteration's first stage would have done anyway, so closing the
iteration costs it no extra transforms. It costs one extra pass…" — no longer a bare "therefore"
pointing off-page. But `ObservablesCache`'s docstring (`src/Cache.jl:76-77`) still reads "the cache
holds exactly what the iteration computes, materializes, and leaves alive at the iteration's end,
and nothing may be added on any cost axis" with the three cost axes (compute, traffic, residency)
never named or linked in this docstring.

**Surviving class**: `src/Cache.jl:77`, "any cost axis" — undefined in this docstring's cold read.

---

## 17. "but it is no longer a sketch"

**ABSENT**

`docs/ARCHITECTURE.md:86-89` (§2 Status) now ends "The API may still evolve, since setup ergonomics
is the package's primary quality target." The denial clause is gone; searched the file for "no
longer a sketch", no hits.

---

## 18. "not an optimization"

**ABSENT**

`src/Forcing.jl:154-156` (`uses_linear_rate`) now ends "Declaring it is therefore part of
implementing `set_forcing_rate!`: a forcing that fills a rate without declaring one is never given an
array to fill, and the `ResolvedGenerator` constructor rejects it rather than let the forcing go
silently unapplied." The "not an optimization" trailer is gone; searched, no hits.

---

## 19. A glossary that documents its own link policy

**ABSENT**

`docs/src/notation.md:23-33` ("Physical variables" preamble) now reads only "The **Code** column
gives the name each symbol carries in the package." before the table. The two-sentence maintainer
rule ("Every Code entry naming a package object links…") is gone; searched the file for "stay bare",
no hits.

---

## 20. A deferred item that settles the name of an option nobody can pass

**ABSENT**

`docs/ARCHITECTURE.md:667-676` (§7, FFT-planner bullet) no longer contains "named for the
planning-effort choice a user makes, not the raw backend flag"; the bullet now ends on the
cost/benefit deferral itself ("It is wired when a long CPU campaign makes the search worth the added
front-door surface"). Searched the file for "planning-effort choice", no hits.

---

## 21. The paragraph's subject arrives last

**ABSENT**

`docs/src/observables_cache.md:55-58` is reordered: the convention-fixing sentence now leads —
"Where this page says *the state*, it means the fluid's — the resolved fields, the velocity and,
when the run carries one, the scalar." — followed by the architecture-positioning sentence ("Tracer
particles are instruments rather than a second physics…"). The paragraph's own job (fixing the word
"state" on this page) is now the opening clause, matching the finding's suggested fix.
