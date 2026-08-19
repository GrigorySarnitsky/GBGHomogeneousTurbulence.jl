# Hat 12 — Plain-sense editor

Does the sentence mean anything, and does it earn its place? Tests applied per clause: paraphrase,
non-vacuity, unprovoked defence (fossil), the delete test, load-bearing subject. Plus: over-long
multi-clause sentences, ambiguous pronouns, anthropomorphism hiding a missing subject, and HOW where
the reader asked WHAT.

Fix column: **CUT** (nothing is lost by striking) or **REWRITE**.

---

## 1. The front-page quick start dates a deposit by "the iteration", which the vocabulary page forbids

- **type**: contradiction · **severity**: major · **confidence**: high · **fix**: REWRITE

**Locations**
- PAGE: Home, "Quick start" (code comment): "each tagged with the iteration it belongs to"
- PAGE: notation, "Vocabulary": "Not an iteration number: an announced out-of-band mutation advances an epoch without advancing the clock."
- PAGE: api / Cache, module admonition: "An epoch is not an iteration number"

**Contradicts**: notation → Vocabulary → `epoch`, on the axis *what a deposited value is dated with*.
The first thing a new reader is told is exactly the reading three later surfaces spend a paragraph
each denying. "Tagged" also revives the retired *stamp* verb. The sentence additionally hides its
agent behind anthropomorphism ("the write in which the iteration hands the cache the observables") —
the iteration hands nothing; `deposit!` writes.

---

## 2. The glossary's "resolved" denies the very sense its sibling names depend on

- **type**: contradiction · **severity**: major · **confidence**: medium · **fix**: REWRITE

**Locations**
- PAGE: notation, "Vocabulary": "resolved | … made concrete as one value — not the numerical sense of \"resolved by the grid\""
- PAGE: architecture, §11 (decision on `ResolvedGenerator`): "resolved against filtered, with `FilteredGenerator` … the eventual LES sibling"
- PAGE: architecture, §11 (decision on `ResolvedFields`): "with `FilteredFields` (LES/FDF) … its eventual siblings"

**Contradicts**: the resolved↔filtered naming axis, on the axis *what "Resolved" names*. Resolved
against filtered **is** the grid sense (resolved scales versus filtered ones). The gloss's positive
half, "made concrete as one value", also fails the paraphrase test on its own: it describes
reification, which is a different claim from the axis the type names sit on.

---

## 3. Two different definitions of "iteration", one of them on the page that claims exactness

- **type**: contradiction · **severity**: major · **confidence**: high · **fix**: REWRITE

**Locations**
- PAGE: notation, "Vocabulary": "iteration | one advance of the run: a step! followed by the deposit! that closes it."
- PAGE: observables_cache, §1.1: "the timestep choice, the step, the particle push, and the deposits at its end"

**Contradicts**: on the axis *what an iteration contains*. The Vocabulary section opens "each means
exactly this and nothing looser", then gives a definition that omits the timestep choice and the
particle push — both of which `advance!` documents as part of the same advance. A reader who takes
the glossary literally will conclude the tracer push sits outside the iteration.

---

## 4. "Write, then record" inverts the name of the function it is written on

- **type**: clarity · **severity**: major · **confidence**: high · **fix**: REWRITE

**Locations**
- PAGE: api / Particles, `record_particle_velocity!`: "Write, then record — a run does both at the end of each iteration"
- same docstring: "which is a second call the cache owns"

The verb is *record*, and this paragraph assigns "record" to the **other**, unnamed call, making the
function's own name the "write" half. A reader cannot hold both. The second call is also left
anonymous here while `particles_modified!` names it (`deposit_sample!`), so the docstring withholds
the one fact that would let a hand-run loop act.

---

## 5. A docstring instructs the caller to call a verb documented nowhere

- **type**: api-gap · **severity**: major · **confidence**: medium · **fix**: REWRITE

**Locations**
- PAGE: api / Cache, `particles_modified!`: "finally `deposit_sample!` to record them at the current epochs"
- PAGE: api / GBGIsotropicTurbulence, "Index": no `deposit_sample!` entry

An instruction the reader cannot follow: the named call has no docstring, no index entry, and no
mention on the Cache module map. (This is distinct from the adjudicated point that internal cache
verbs may stay undocumented — here a public docstring makes calling one a required step.)

---

## 6. "A `Simulation` is a container, not a reading surface" — a fossil that teaches the reading it denies

- **type**: design · **severity**: major · **confidence**: medium · **fix**: REWRITE (keep the positive half)

**Locations**
- PAGE: Home, "Components" → `SimulationRun`: "A `Simulation` is a container, not a reading surface"
- PAGE: api, overview list → SimulationRun: same sentence
- PAGE: architecture, §4.7: "A `Simulation` is a container, not a reading surface (decision 49)."
- PAGE: api / SimulationRun, module docstring: same sentence

Four surfaces deny a capability no current page offers. A reader meeting `sim` for the first time
learns from the denial that `velocity_physical(sim)` was once plausible. The load-bearing content is
the *positive* clause that follows ("read the state through `sim.state` …"); the negation is
removed-forwarder residue.

---

## 7. "Observation" names both the callback and the instant it happens

- **type**: contradiction · **severity**: major · **confidence**: medium · **fix**: REWRITE

**Locations**
- PAGE: notation, "Vocabulary": "observation | the callback a run is driven by"
- PAGE: observables_cache, §1.1: "sits the observation: the caller's callback reads the state and the cache"
- PAGE: observables_cache, §2.4: "an observation builds it itself in one act"
- PAGE: api / SimulationRun, `run!`: "Observe and advance `sim` until the observation stops it"

**Contradicts**: the Vocabulary entry, on the axis *is an observation a function or an event*. The
glossary fixes it as the callback; the cache page uses it as the instant between iterations and as
the act performed there ("at an observation"). "Until the observation stops it" then reads as an
event stopping a run.

---

## 8. `FlowConditions` says it is consumed by the time step; the architecture says a scheme holds no conditions

- **type**: contradiction · **severity**: minor · **confidence**: medium · **fix**: REWRITE or CUT

**Locations**
- PAGE: api / Generator, `FlowConditions`: "Consumed by the time step (`step!`)."
- PAGE: architecture, §4.2: "A scheme consumes the physics only through this protocol"

**Contradicts**: §4.2 and the `ResolvedGenerator` docstring, on the axis *who reads the conditions*.
`step!`'s own signature takes a generator, not conditions. As a three-word sentence it also tells a
user nothing they can act on — it fails the delete test even where it is not misleading.

---

## 9. Module-placement rationale, on a user page, behind an ambiguous "It"

- **type**: clarity · **severity**: minor · **confidence**: high · **fix**: CUT

**Locations**
- PAGE: api / Cache, module docstring: "It is homed in `Propagator` rather than here because it needs the scheme's own scratch to recover the fields, and that is the module owning the iteration it closes."

The nearest preceding subject is "A caller", not `deposit!`, so the pronoun genuinely misreads. Three
"it"s in one sentence carry two different referents. The content is architecture rationale (why a
verb lives in one module) that no caller acts on.

---

## 10. The argument-order paragraphs explain a signature's shape rather than its use

- **type**: clarity · **severity**: minor · **confidence**: high · **fix**: CUT

**Locations**
- PAGE: api / Propagator, `step!`: "so the chained pair transposes nothing. This signature interleaves two more"
- PAGE: api / Propagator, `deposit!`: "the mutated dispatch object (here the cache) leads, and `state`, `domain`, `buffers` follow in the same fixed order as there"

"Transposes nothing" and "interleaves two more" resist paraphrase — interleaves what into what? Both
paragraphs justify a design choice already visible in the two signatures printed above them; struck,
nothing operational is lost, and the pair stops carrying two copies of one argument.

---

## 11. "carries `_consumed` in its name because it is" — a sentence that defers its own meaning

- **type**: clarity · **severity**: minor · **confidence**: high · **fix**: CUT

**Locations**
- PAGE: api / Generator, `velocity_rhs!`: "The vorticity argument carries `_consumed` in its name because it is: see the note below."
- PAGE: api / Generator, `scalar_rhs!`: "The velocity argument carries `_consumed` in its name because it is: see the note below."

Because it *is* what? The clause is complete only after the reader has read the admonition it points
at — which then states the fact in full, twice more ("Which operand is consumed follows the physics,
not the argument position…" recurs near-verbatim in both docstrings). Four statements of one fact
across an `f`/`f` pair.

---

## 12. Sentences carrying five clauses

- **type**: clarity · **severity**: minor · **confidence**: high · **fix**: REWRITE

**Locations**
- PAGE: architecture, §2: "The run layer holds the pieces of §4 in one `Simulation` value, chooses a stable timestep…" — ~75 words, 5 coordinate clauses, 4 parenthetical cross-references, then a colon introducing a sixth idea.
- PAGE: observables_cache, §1.3: "Only the last closing deposit has no following iteration to fold into…" — ~55 words, 4 clauses, ending in the unparaphrasable "the state-only share of one first-stage evaluation".

Each packs an enumeration, a rationale, and an accounting result into one breath. The second's final
noun phrase cannot be restated without re-deriving §1.4.

---

## 13. The same parenthetical rebuttal in four places, unprovoked in the fourth

- **type**: clarity · **severity**: minor · **confidence**: medium · **fix**: CUT (keep the cache-page home)

**Locations**
- PAGE: api / Observables, `max_speed` admonition: "(A constant-energy forcing does form $k$ mid-step to size its rescale, but that is the pre-rescale value, discarded before the deposit.)"
- PAGE: observables_cache, §1.2, §1.3, and the §2.4 table row: three further statements of the same qualification

In a docstring about the fastest flow speed, the reader has raised no objection about `k`. The
clause answers a challenge that only the cache design page creates.

---

## 14. `max_speed` re-argues `recommended_cfl`'s margin

- **type**: clarity · **severity**: minor · **confidence**: medium · **fix**: CUT and link

**Locations**
- PAGE: api / Observables, `max_speed`: "the two are independent, so the second is not guaranteed to cover the first, which is why that ceiling carries a margin of its own"
- PAGE: api / Propagator, `recommended_cfl`: "The conservative factor below exists because the second is not guaranteed to cover the first."

The at-home test: the sentence explains why *another* function's constant is what it is, and sits
equally well (and does sit) in that function's docstring.

---

## 15. "not the absence of one" defends against a reading nobody has

- **type**: clarity · **severity**: minor · **confidence**: medium · **fix**: CUT

**Locations**
- PAGE: api / Forcing, `BandRescaling`, the `:total` bullet: "the most violent intervention the rescale can make, not the absence of one"

Nobody reads "the band is zeroed" as the forcing doing nothing. The trailing clause also dangles —
the absence of an *intervention*, a noun three phrases back. The rest of the bullet (it empties the
energy-containing range; $L_{11}$, $u'$, $\mathrm{Re}_\lambda$ are meaningless afterwards) carries
the whole warning.

---

## 16. Cost-accounting vocabulary arrives in the docstrings without its argument

- **type**: clarity · **severity**: minor · **confidence**: medium · **fix**: REWRITE

**Locations**
- PAGE: api / Propagator, `deposit!`: "Caching therefore costs an iteration no transforms. It costs one pass"
- PAGE: api / Cache, `ObservablesCache`: "nothing may be added on any cost axis"

"Therefore" points at an argument that is not on the page, and "any cost axis" presumes the design
page's three axes (compute, traffic, residency), never named here. Cold-read: a user learns a
conclusion whose premises are elsewhere and whose units they cannot check.

---

## 17. "but it is no longer a sketch"

- **type**: clarity · **severity**: nit · **confidence**: medium · **fix**: CUT

**Locations**
- PAGE: architecture, §2, "Status.": "The API may still evolve … but it is no longer a sketch."

The paragraph has just said the layer is implemented, tested, and that the example runs as written.
The closing clause denies a past state the reader never knew, and can only plant doubt about a
present one.

---

## 18. "not an optimization"

- **type**: clarity · **severity**: nit · **confidence**: medium · **fix**: CUT

**Locations**
- PAGE: api / Forcing, `uses_linear_rate`: "Declaring it is therefore part of implementing `set_forcing_rate!`, not an optimization"

The preceding sentence already states the consequence of not declaring it (no array, forcing never
applied), which settles the point. The denial invites the reading that a declaration might be
performance tuning.

---

## 19. A glossary that documents its own link policy

- **type**: organization · **severity**: nit · **confidence**: medium · **fix**: CUT

**Locations**
- PAGE: notation, "Physical variables": "Every Code entry naming a package object links to its documentation. The few that stay bare name no single object to link to: a constructor keyword, or a quantity carried as a field of the state rather than by a function of its own."

Addressed to a maintainer, printed for a reader looking up a symbol. Whether a cell is a link is
visible; why it is not needs no two-sentence rule in the table's own preamble.

---

## 20. A deferred item that settles the name of an option nobody can pass

- **type**: clarity · **severity**: nit · **confidence**: low · **fix**: CUT

**Locations**
- PAGE: architecture, §7, FFT-planner bullet: "named for the planning-effort choice a user makes, not the raw backend flag"

The bullet's job is to record that the passthrough is deferred and why. The closing clause pre-decides
the naming of a keyword that does not exist, and is the sort of clause a later implementation
silently contradicts.

---

## 21. The paragraph's subject arrives last

- **type**: organization · **severity**: nit · **confidence**: medium · **fix**: REWRITE

**Locations**
- PAGE: observables_cache, §1.1: "Tracer particles are instruments rather than a second physics: probes of the flow, each carrying a state of its own — its position — which its own equation advances. Where this page says the state, it means the fluid's."

The paragraph exists to fix a word on this page; that is its final sentence. The opening clause is
architecture positioning ("instruments rather than a second physics"), contrasting against a
second-physics reading this page never offers. Lead with the convention.
