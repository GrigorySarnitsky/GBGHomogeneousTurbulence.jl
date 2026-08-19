# Plain-sense editor — findings

Hat: **plain-sense**. The question asked of every clause: *does this sentence mean anything, and
does it earn its place?* Tests applied in order — paraphrase, non-vacuity, unprovoked defence,
the delete test, load-bearing subject. Style, notation, formatting, terminology and factual
defects are other hats' business and are not reported here.

---

## 1. The quick-start gloss defines "deposit" as "the write in which the deposit writes"

- **type**: clarity
- **severity**: major
- **confidence**: high
- **locations**:
  - PAGE: Home, "Quick start" code block comment — "One ITERATION is one advance: a step, then the
    DEPOSIT that closes it — **the write in which the closing deposit writes the observables the
    iteration has just computed into the cache**, each stamped with the epoch of the state they were
    computed from."
- **test failed**: PARAPHRASE + NON-VACUITY (the appositive restates its own head noun)
- **description**: The em-dash appositive is supposed to explain "the DEPOSIT that closes it"; it
  explains it as "the write in which the closing deposit writes … into the cache", i.e. by using the
  word being defined. Strip the circular half and the sentence loses nothing: "a step, then the
  closing deposit, which writes the iteration's observables into the cache". The clause is also the
  reason this comment runs to 43 words across three clauses in a code block, where a reader is
  skimming.
- **fix**: REWRITE (drop the appositive; keep "each dated to the state's epoch").

---

## 2. "Two kinds of field share the word" — a sentence with no reconstructible subject

- **type**: clarity
- **severity**: major
- **confidence**: high
- **locations**:
  - PAGE: api / Cache, `ObservablesCache` → `# Fields` — "**Two kinds of field share the word**: the
    two counters below tick as the state changes, and each slot carries a stamp, the counter's value
    at the moment that slot was filled."
- **test failed**: PARAPHRASE (which word? which two kinds?)
- **description**: Nothing in the sentence names the shared word. If "field" is meant (struct field
  vs flow field), the colon-clause that follows does not discuss fields at all — it discusses
  counters and slot epochs. If "epoch" is meant, the sentence says "field". A reader cannot restate
  it. What the paragraph actually needs to say is that the entries below come in two kinds — the
  slots and their epoch counters — which the bullets then show.
- **fix**: REWRITE (state the two kinds outright), or CUT and let the bullets speak.

---

## 3. The max_speed admonition explains its rule three times inside one sentence

- **type**: clarity
- **severity**: major
- **confidence**: high
- **locations**:
  - PAGE: api / Observables, `max_speed`, admonition "Why this observable alone has a cached form" —
    "The cache holds exactly what the iteration already computes and leaves alive at its end — **its
    contents are derived from the run's fixed computation schedule — what each iteration computes,
    settled when the cache is built** — never declared."
- **test failed**: DELETE TEST (two nested appositives restate the main clause)
- **description**: The main clause already says the cache holds what the iteration computes and
  leaves alive. The first dash-clause restates it as "derived from the fixed computation schedule";
  the second restates *that* as "what each iteration computes"; a third fragment, "never declared",
  hangs 20 words from the noun it modifies. Two nested dashes inside one 39-word sentence make the
  reader hold three parses at once for one idea.
- **fix**: REWRITE to one clause.

---

## 4. Sentences past 40 words carrying four or more clauses, with the load-bearing verb buried

- **type**: clarity
- **severity**: major
- **confidence**: high
- **locations**:
  - PAGE: api / SimulationRun, `Simulation`, "Grid mode" bullet (~180 words, ~6 clauses) — the verb
    pair is "**It reads** the dissipation … **then sets** $\nu$", separated by roughly sixty words of
    nested parenthetical ("— a value that assumes forcing confined to the same low-wavenumber band
    as the calibrating runs, since $G$ is $C_\varepsilon$ rescaled by $L_{11}/L$ …").
  - PAGE: architecture, §4.1 (~100 words, 5 clauses, three nested parentheticals) — "Its concrete
    type is the `FixedDomain`, the fixed, unsheared cube, realized by the grid, the real–Fourier
    layout, the real-to-complex transform plans (one for the velocity, …)".
  - PAGE: api / Propagator, `step!` (~70 words) — "The first stage reads the deposited velocity,
    vorticity, and scalar in physical representation from `cache` — the values of the instant between
    iterations, … — and the later stages compute their recoveries into those same slots".
- **test failed**: LOAD-BEARING SUBJECT / clause count
- **description**: One class, three samples. In each, the sentence's actual claim is a two-verb
  spine, and everything between the verbs is qualification. The grid-mode bullet is the worst: a
  reader who wants to know *what grid mode does* has to carry a caveat about forcing bands and an
  identity between $G$ and $C_\varepsilon$ before reaching "then sets $\nu$". Splitting at the
  qualification costs nothing.
- **fix**: REWRITE (split the spine from the caveats; the caveat can be its own sentence).

---

## 5. A trailing sentence in `StationarityCriterion` that points at an argument the reader has not met

- **type**: clarity
- **severity**: minor
- **confidence**: high
- **locations**:
  - PAGE: api / SimulationRun, `StationarityCriterion`, identity paragraph — "**The same argument the
    scalar gate makes for an unforced scalar applies to the velocity.**"
- **test failed**: DELETE TEST + PARAPHRASE
- **description**: The paragraph has just said, in full, that a decaying run has no stationary state
  to detect and that its $\varepsilon$ never plateaus. This sentence then asks the reader to fetch
  an argument from `gate_scalar`, which appears further down the page, and to transpose it back onto
  the case already stated. It adds no fact, and its referent is below it.
- **fix**: CUT.

---

## 6. "The same arguments in the same order" — a promise the next clause withdraws

- **type**: clarity
- **severity**: minor
- **confidence**: medium
- **locations**:
  - PAGE: api / Propagator, `step!` — "**Call it with the same arguments in the same order as
    `deposit!`** … **Only the extras differ** — `generator` sits directly after `state` here, and
    `cache` and `dt` come last".
  - PAGE: api / Propagator, `deposit!` — "The argument order is shared with `step!` — the mutated
    dispatch object (here the cache) leads".
- **test failed**: PARAPHRASE (the claim is asserted and then qualified out of shape)
- **description**: The signatures are `step!(scheme, state, generator, domain, buffers, cache, dt)`
  and `deposit!(cache, state, domain, buffers)`: three arguments are common, one is interleaved, two
  are appended, and the leading argument is mutated in one and not in the other (`deposit!` says
  "the mutated dispatch object", `step!`'s `scheme` mutates nothing). The mnemonic makes the reader
  verify it against both signatures — which is more work than reading the signatures.
- **fix**: REWRITE to the checkable claim ("`state`, `domain`, `buffers` keep their order in both"),
  or CUT from one of the two.

---

## 7. "so the arrows stay primary" — unglossed jargon in a document that promises to gloss everything

- **type**: clarity
- **severity**: minor
- **confidence**: high
- **locations**:
  - PAGE: architecture, §4.1 — "the reification the Mori–Zwanzig lens demands, **kept a bare carrier
    so the arrows stay primary** (§11 decision 26)".
  - PAGE: architecture, preamble (the promise) — "The document is self-contained — every symbol,
    mathematical or `code`, is introduced in plain language at first use".
- **test failed**: PARAPHRASE
- **description**: "The arrows" is category-theory shorthand for morphisms/functions-over-objects. It
  appears once, undefined, and the decision-log entry it cites uses the same phrase without
  defining it either. The plain claim underneath is stated three words earlier ("every operation
  external"), so the clause is jargon on top of an already-made point.
- **fix**: CUT, or REWRITE as "so the operations stay external to the record".

---

## 8. "output cursors" names a component the documented package does not have

- **type**: clarity
- **severity**: minor
- **confidence**: medium
- **locations**:
  - PAGE: architecture, §8, the skew-product tower — "and **the clock and output cursors** are the
    experimenter's logbook".
- **test failed**: PARAPHRASE (no referent anywhere in the corpus)
- **description**: The package has a clock (`current_time` / `current_step`) and no output or I/O
  layer at all — writing is explicitly the caller's business in the observation-first design. "Output
  cursors" appears once, in a sentence that is otherwise a precise litmus for what belongs in a
  restart record, and a reader who takes the litmus seriously will hunt for the cursors.
- **fix**: CUT the two words (the clock alone carries the point).

---

## 9. §1.4 states its two costs, then states them again as though for the first time

- **type**: clarity
- **severity**: minor
- **confidence**: medium
- **locations**:
  - PAGE: observables_cache, §1.4 — "It costs nothing on the memory axis, nothing on the transform
    axis, and — with one exception — nothing on the traffic axis: the closing deposit's maximum-speed
    reduction is one physical-vector pass every iteration…"
  - same section, three sentences later — "**Those are two different costs and it is worth keeping
    them apart**: the maximum-speed reduction above recurs every iteration, while the only work the
    cache adds over a cacheless solver is §1.3's final closing deposit…"
- **test failed**: DELETE TEST
- **description**: The second sentence presents as a distinction the reader has yet to draw, but the
  per-iteration reduction was the opening sentence's "one exception" and the once-per-run deposit was
  fully derived in §1.3. "Those are two different costs" also has an antecedent problem: the nearest
  plural is the three axes, not the two costs.
- **fix**: REWRITE (name the two costs once, in one sentence).

---

## 10. Each `*_rhs!` docstring states the consumed-operand fact three times

- **type**: clarity
- **severity**: minor
- **confidence**: high
- **locations**:
  - PAGE: api / Generator, `velocity_rhs!` — body: "The vorticity argument is named `ω_consumed`
    because the assembly overwrites it: on return it no longer holds the vorticity."; admonition: "so
    `ω_consumed` must hold the vorticity on entry and no longer does on return"; then "**Which operand
    is consumed follows the physics, not the argument position**".
  - PAGE: api / Generator, `scalar_rhs!` — the same three, with `u_consumed`.
- **test failed**: DELETE TEST
- **description**: One fact — this argument is destroyed — carried by three separate sentences per
  docstring, and the third ("follows the physics, not the argument position") is itself repeated
  almost verbatim in the sibling docstring, where it defends a positional convention neither
  docstring proposes. The admonition is the right home; the body sentence and the position defence
  can go.
- **fix**: CUT the duplicate body sentence and the position defence; keep the warning admonition.

---

## 11. "deliberately deferred" three times in a four-sentence admonition

- **type**: clarity
- **severity**: nit
- **confidence**: high
- **locations**:
  - PAGE: api / phenomenology / Spectra, `DissipationFactor` — title: "Bottleneck models are
    **deliberately deferred**"; first sentence: "These factors are inertial-normalized cutoffs;
    bottleneck models are **deliberately deferred**."; last clause: "…need a richer spectrum
    structure; **they are deliberately deferred**."
- **test failed**: DELETE TEST
- **description**: The title makes the claim, the opening sentence repeats it verbatim, and the
  closing clause repeats it a third time after the reason has been given. Only the middle sentence
  (the models, their form, why $f_\eta \to 1$ fails) carries information.
- **fix**: CUT the first and third instances.

---

## 12. Argument entries that explain the implementation instead of the meaning

- **type**: clarity
- **severity**: minor
- **confidence**: medium
- **locations**:
  - PAGE: api / phenomenology / Phenomenology, `FlowParameters` → `scalar_dissipation` — "That check
    is what makes the sentinel safe, so it covers the laws here and not arithmetic a caller does on
    the field itself, **which propagates `NaN` as `NaN` always does**."
  - PAGE: api / SimulationRun, `Simulation` → `κ_max_η` — "**the sentinel is what lets the
    constructor tell an omitted keyword from an explicit one**, so that giving both it and
    `viscosity` is an error rather than a silent drop".
- **test failed**: NON-VACUITY (the first restates the language's default) + HOW-not-WHAT
- **description**: One class, two samples. "propagates `NaN` as `NaN` always does" tells a Julia user
  nothing they do not know and is the tail of an already 120-word argument entry. The `κ_max_η`
  clause explains the constructor's internal sentinel trick where the reader is asking what the
  keyword means; the user-facing fact — passing both `κ_max_η` and `viscosity` is an error — is the
  clause after it and stands alone.
- **fix**: CUT both clauses.

---

## 13. The observation is placed before the iteration in one document and after it in every other

- **type**: clarity
- **severity**: minor
- **confidence**: medium
- **locations**:
  - PAGE: observables_cache, §1.3 — "**The observation comes before the iteration.** Between
    iterations the callback reads what it wants…"
  - PAGE: api / SimulationRun, `run!` — "**After every iteration** — and once at the seeded initial
    state, before any advance — the `callback` observes the run".
- **contradicts**: same event, opposite framing (before-the-next vs after-the-last)
- **test failed**: PARAPHRASE (a reader building a mental loop order gets two answers)
- **description**: Both descriptions are of the same $n+1$ observations, but a reader meeting §1.3
  first will encode "observe, then iterate" and then read "after every iteration" as a different
  schedule. The design page's own §3.2 uses the other framing ("observes the run after every
  iteration and once before the first"), so the collision is inside one document as well.
- **fix**: REWRITE §1.3's topic sentence to the corpus framing.

---

## 14. "the thing that reads the run each iteration"

- **type**: clarity
- **severity**: nit
- **confidence**: high
- **locations**:
  - PAGE: api / SimulationRun, module map — "(the callback is the observation — **the thing that
    reads the run each iteration** — and its return decides continuation)".
- **test failed**: DELETE TEST
- **description**: The gloss defines "observation" as "the thing that reads the run", which is what
  the same sentence has already said by naming the callback. "The thing" is also the only such
  placeholder noun on the page; every other definition names its object.
- **fix**: CUT the dash-clause.

---

## 15. "It is never the cache" — a denial of a reading the text never invites

- **type**: clarity
- **severity**: nit
- **confidence**: medium
- **locations**:
  - PAGE: notation, "Vocabulary" table, entry *observation* — "By extension the occasion … from what
    the run already holds. **It is never the cache, which is the storage the callback reads.**"
- **test failed**: UNPROVOKED DEFENCE
- **description**: The entry has just defined the observation as the callback and as the occasion of
  calling it; no reader arrives thinking it might be a storage array. The denial introduces the
  confusion it forecloses — the classic fossil left by a rename — and the useful half of it (the
  cache is what the callback reads) is already the *cache* entry's job two rows up.
- **fix**: CUT.

---

## 16. "and that is the module owning the iteration it closes" — a reason that does not attach

- **type**: clarity
- **severity**: nit
- **confidence**: medium
- **locations**:
  - PAGE: api / Cache, module docstring — "That verb lives in `Propagator` rather than here because it
    needs the scheme's own scratch to recover the fields, **and that is the module owning the
    iteration it closes**."
- **test failed**: PARAPHRASE (the pronoun "that", and a second reason grafted onto the first)
- **description**: "That" has three candidate antecedents in the preceding clause (the verb, the
  scratch, `Propagator`), and the appended clause is a second, independent justification presented
  as a continuation of the first. Two reasons stated as one leave a reader unsure which is
  load-bearing.
- **fix**: REWRITE as two sentences, or keep the scratch reason alone.
