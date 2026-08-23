# Plain-sense editor — findings

Hat: **plain-sense**. The question asked of every clause: *does it mean anything, and does it earn
its place?* Tests applied in order — paraphrase, non-vacuity, unprovoked defence, the delete test,
load-bearing subject — plus over-long multi-clause sentences, ambiguous pronouns, anthropomorphism,
and how-instead-of-what.

---

## 1. `max_wavenumber`: "the dealiasing cutoff" said four times in two sentences

- **type**: clarity · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: api / SimulationDomain, section header above `max_wavenumber`: "The dealiasing cutoff it
    sets — the dealiasing cutoff — the highest wavenumber the run treats as resolved signal"
  - same page, `max_wavenumber` docstring: "The dealiasing cutoff of `domain` … — the dealiasing
    cutoff" (then "It is the cutoff the dealiasing sets")
- **description**: The section header contains a self-apposition — the phrase interrupts itself with
  a verbatim copy of itself — and the docstring's opening sentence repeats the same phrase across a
  parenthetical before restating it a third time. Fails the paraphrase test: a reader cannot tell
  whether the second "the dealiasing cutoff" was meant to introduce something new. Reads as a
  merge artifact left in a rendered heading.
- **fix**: CUT the interrupting apposition in the header and the trailing repetition in the
  docstring; one naming is enough.

## 2. `Simulation` grid mode: one ~120-word sentence whose main verb is lost, with a garbled coordination

- **type**: clarity · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: api / SimulationRun, `Simulation` → "Setting the Reynolds number", Grid-mode bullet: "since
    $G$ carries $C_\varepsilon^{-2/3}$ and the ratio $L_{11}/L$ and that ratio is fixed by where the
    run is driven"
  - same bullet, the resumption: "invalidates the estimate and with it the $\nu$ grid mode chooses —
    then sets $\nu$ so that $\kappa_{\max}\eta$ equals `κ_max_η`"
- **description**: One sentence carries five clauses: it reads the law, states $G$'s value, defends
  the value's band assumption, warns about moved forcing, and only then resumes "then sets $\nu$" —
  whose subject ("It reads") is ~70 words upstream. The inner "and … and that ratio" coordination has
  no readable grammar (two `and`s, one referent). This is the constructor's decisive paragraph;
  a reader cannot extract the two-step recipe from it.
- **fix**: REWRITE as three sentences: read $\varepsilon$ from the law; set $\nu$ from
  $\kappa_{\max}\eta$; then the band caveat as its own sentence or `!!! note`.

## 3. `FlowParameters.scalar_dissipation`: the bullet denies, three clauses later, what it asserts

- **type**: contradiction · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: api / phenomenology / Phenomenology, `FlowParameters` Arguments: "It is a sentinel, not a
    value that propagates"
  - same bullet, closing clause: "there `NaN` propagates as it always does"
- **contradicts**: itself — the axis is whether the stored `NaN` propagates.
- **description**: The bullet runs ~120 words and turns on itself: the categorical claim ("not a
  value that propagates") is retracted by the final clause, which says it propagates whenever a
  caller touches it. The true content is narrower — *laws check it and throw* — so the categorical
  form is unearned and the retraction exists only to repair it. Also the longest entry in an
  argument list otherwise averaging one line.
- **fix**: REWRITE to the checked claim ("every law that reads it throws when it is `NaN`") and cut
  the sentinel/propagation pair.

## 4. `step!` and `deposit!` state opposite rules for the same argument order

- **type**: contradiction · **severity**: major · **confidence**: medium
- **locations**:
  - PAGE: api / Propagator, `deposit!`: "The argument order is shared with `step!` — the mutated
    dispatch object (here the cache) leads"
  - same page, `step!`: "The leading argument differs from `deposit!`'s in kind … `scheme` here is a
    stateless dispatch tag, and what this call mutates is `state`"
- **contradicts**: the two docstrings — axis: whether the leading argument is the mutated object.
- **description**: `deposit!` generalizes a rule ("the mutated dispatch object leads") that `step!`
  explicitly does not follow and says so. Beyond the clash, both paragraphs are unprovoked defence:
  they answer a question about calling convention that neither signature raises, and each teaches the
  other's signature rather than its own. The `step!` opener ("it is worth knowing which") announces
  importance instead of stating content.
- **fix**: CUT both meta-paragraphs; if a shared shape is worth stating, state it once, accurately
  ("both take `state`, `domain`, `buffers` after the first argument").

## 5. `recommended_cfl` admonition ends by repeating its own sentence

- **type**: clarity · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / Propagator, `recommended_cfl`, admonition: "prefer `IFLowStorageRK3`, whose ceiling
    has no such dependence"
  - same admonition, final sentence: "`IFLowStorageRK3`'s ceiling carries no such dependence."
- **description**: The closing sentence is the same claim as a clause fourteen words earlier, in the
  same admonition, with only the wording changed. Delete test: nothing is lost.
- **fix**: CUT the final sentence.

## 6. `Simulation` fields: a naming defence against a confusion the list never creates

- **type**: language-tone · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / SimulationRun, `Simulation` → Fields, `tracers, trajectory_scheme, particle_buffers`
    entry: "The two roots are not interchangeable: trajectory names the path through time the scheme
    integrates, particle the objects whose storage the buffers hold."
- **description**: A field list says what each field holds; this sentence instead defends a
  vocabulary choice against a reader who has not yet been given the chance to conflate the two roots
  — and by denying it, introduces the reading. It is design rationale, and the decision log already
  carries it. Delete test: the entry still names all three fields and their contents.
- **fix**: CUT (the rationale belongs in `ARCHITECTURE.md`).

## 7. `DealiasingStrategy`: two clauses about the documentation rather than the object

- **type**: clarity · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / SimulationDomain, `DealiasingStrategy`: "They come in two families, and the rest of
    the corpus uses these names"
  - same docstring: "is decided by the `Simulation` constructor … — the front door — and not by this
    catalogue"
- **description**: Neither clause tells a user anything about dealiasing. The first is a claim about
  vocabulary used elsewhere in the docs; the second denies that a type docstring sets a default —
  a confusion nothing here invites, and one the denial itself plants. Both survive the delete test
  with no loss.
- **fix**: CUT both; keep "a mask strategy acts on the assembled product, a shift strategy also
  changes how it is evaluated."

## 8. `truncate_to_band!`: the PhaseShift half-dealiasing fact stated three times in ten lines

- **type**: organization · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / SimulationDomain, section header: "Under `PhaseShift` this is only part of the
    dealiasing — the averaging of two displaced evaluations is the other half"
  - admonition title: "This verb truncates; under PhaseShift that is half the dealiasing"
  - admonition body: "Under `PhaseShift` it is only the second half"
- **description**: One fact, three consecutive statements, each in a different register (section
  prose, admonition title, admonition body). By the third the reader has stopped reading. The
  admonition body earns its place only for the consequence it adds ("a hand-built assembly must do
  the same"); the header and title are pure restatement.
- **fix**: CUT the section-header clause and compress the title to the consequence.

## 9. `envelope_wavenumber`: "forms its own" has no object

- **type**: clarity · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / SimulationRun, `Simulation` Arguments: "though a roll-off whose coefficient belongs to
    a different length forms its own (see `large_scale_length`)"
- **description**: Its own *what*? The nearest candidate noun is "the integral scale", but "forms its
  own integral scale" is not what `large_scale_length` describes (it *reads* a different length).
  The clause cannot be paraphrased without opening the linked docstring, which is the definition of a
  clause that has not been written.
- **fix**: REWRITE: "a roll-off fitted against a different length uses that length instead."

## 10. `ExponentialDissipation`: the closing sentence restates the one before it

- **type**: clarity · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / phenomenology / Spectra, `ExponentialDissipation`: "because Pope fits his $\beta$
    across the whole dissipation range … while the values here are fitted to the far range alone"
  - next sentence: "The two are the same symbol for the same decay, calibrated on different
    intervals."
- **description**: The second sentence is the first with the explanation removed. Delete test:
  nothing is lost — the preceding clause already says both the shared symbol and the differing
  calibration intervals.
- **fix**: CUT the closing sentence.

## 11. `max_speed`: a cache-policy essay lodged in a reduction's docstring

- **type**: organization · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: api / Observables, `max_speed`, admonition "Why this observable alone has a cached form":
    "The cache holds exactly what the iteration already computes and leaves alive at its end"
  - PAGE: observables_cache §1.4: "every slot is a register the iteration fills anyway"
- **description**: Five sentences of cache-contents policy — why $k$ and $\varepsilon$ are not
  cached, what happens under a fixed $\Delta t$ — sit inside the docstring of a reduction. At-home
  test: every sentence would sit equally well in `ObservablesCache`'s docstring, where the design
  page already says it. What the reader of `max_speed` needs is one clause: the run computes this
  every iteration, so the cached form costs nothing.
- **fix**: CUT to one sentence and link.

## 12. `velocity_rhs!` / `scalar_rhs!`: the caveat closes with a non-sequitur, duplicated across the pair

- **type**: clarity · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: api / Generator, `velocity_rhs!` admonition: "Only the spectral product scratch remains on
    the generator, and the operation allocates nothing."
  - `scalar_rhs!` admonition: the identical sentence, verbatim.
- **description**: The admonition's subject is *which argument is destroyed*; residency of the
  generator's scratch is a different subject, and "allocates nothing" is a third. Neither follows
  from the consumed-operand warning, and both are already stated in `ResolvedGenerator`. The
  duplication across the `f`/`f!`-style pair means the same non-sequitur is read twice.
- **fix**: CUT from both; keep the consumption warning alone.

## 13. `current_step`: the same distinction, three times, in four sentences

- **type**: clarity · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / SimulationRun, `current_step`: "The number of steps `sim` has taken — how far the run
    has gone."
  - same docstring, last sentence: "Use this to ask how far the run has gone, and the epoch to ask
    whether a cached value is still the right one."
  - PAGE: api / Cache, module docstring: "The epoch answers 'is this value still the right one?'; the
    clock's `current_step` answers 'how far has the run gone?'."
- **description**: A four-sentence docstring opens and closes with the same gloss ("how far the run
  has gone"), and the whole epoch-versus-step contrast is already delivered verbatim on the `Cache`
  page and again in `ObservablesCache`'s `fields_epoch` field. The middle of the docstring — the
  worked "step 2, fields epoch 4" example — is the only sentence that earns its place.
- **fix**: CUT the closing sentence; keep the example.

## 14. Architecture §4.5: a 55-word IFRK2 sentence with a defensive parenthetical

- **type**: clarity · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: architecture, §4.5: "cheaper in transforms (two nonlinear evaluations against three) but
    dearer in memory — three spectral registers per field against the low-storage scheme's two,
    counting the same way on both sides: the scheme's own registers plus the dealiasing seam's
    assembly register — and imaginary-axis unstable"
- **description**: Four coordinated predicates split by a 25-word dash aside, inside which
  "counting the same way on both sides" pre-emptively defends the comparison against a challenge no
  reader has made. The final predicate ("and imaginary-axis unstable") is stranded so far from its
  subject that it reads as a new sentence fragment.
- **fix**: REWRITE as two sentences; cut the counting defence or demote it to a footnote clause.

## 15. Architecture §4.7: a verb elided across a long parenthesis

- **type**: clarity · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: architecture, §4.7: "`current_time(sim)` and `current_step(sim)` report the clock, and the
    observables applied to `sim.state` (e.g. …) the current-state diagnostics, for a callback to
    read."
- **description**: The second half gaps its verb ("[report] the current-state diagnostics") across a
  parenthetical of two examples, so the sentence has no readable predicate at the point the reader
  needs one. The trailing "for a callback to read" then attaches to nothing definite.
- **fix**: REWRITE with the verb restored: "…and the observables, applied to `sim.state`, report the
  current-state diagnostics."

## 16. Decision-log entry 30: a sentence resumes in lower case after a closing parenthesis

- **type**: format · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: architecture, §11 (the `ObservablesCache` entry): "…a downstream consequence the caller
    would have to reason about.) the sanctioned mutators call it themselves, and the seeders'
    docstrings direct hand-run loops to it."
- **description**: The text after the parenthetical begins mid-sentence with a lower-case "the" and
  no grammatical connection to what precedes it — a fragment left where an earlier clause was cut.
  The log is append-only history, but this is a broken sentence in rendered prose, not a superseded
  claim.
- **fix**: REWRITE the resumption as its own sentence.

## 17. observables_cache §1.2: the `max_speed` boundary case buried under four dashes

- **type**: clarity · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: observables_cache, §1.2: "so the maximum is materialized — one number — while no per-point
    field is ever whole anywhere and none can be cached"
- **description**: Four dash-delimited asides in one sentence, and the final "none can be cached"
  has an ambiguous subject — no per-point field? no speed field? the maximum? The paragraph is
  making the design's sharpest distinction (a number is materialized, a field is not), and the
  punctuation hides it.
- **fix**: REWRITE as two sentences, one per side of the distinction.

## 18. `Li2008`: the author-year name asserts a provenance the docstring withdraws

- **type**: clarity · **severity**: minor · **confidence**: low
- **locations**:
  - PAGE: api / phenomenology / Scalings, `Li2008`: "The value is this package's own reduction of the
    Johns Hopkins Turbulence Database (JHTDB) forced-isotropic dataset"
  - PAGE: architecture, §4.8: "the paper is the author-year handle (`Pope2000`, first author's
    surname …)"
- **description**: The naming convention states that an author-year handle names *the paper the
  parametrization comes from*. Here the number is the package's own reduction of a dataset the paper
  describes, so the handle names a data source rather than a published fit. A reader who trusts the
  stated convention will cite Li et al. for a value they did not publish.
- **fix**: advisory — either name the law for what it is or state in one clause that the handle names
  the dataset, not a published fit.

## 19. Home page: "the protocol's functions, `prepare!`, `velocity_rhs!` and the rest"

- **type**: clarity · **severity**: nit · **confidence**: medium
- **locations**:
  - PAGE: Home, Components → `Generator`: "through a fixed set of verbs — the protocol's functions,
    `prepare!`, `velocity_rhs!` and the rest — rather than assembling the physics itself"
  - PAGE: api, overview: "which a scheme consumes through a fixed set of verbs." (same sentence, aside
    removed)
- **description**: "and the rest" names nothing; a partial enumeration on a landing page buys neither
  completeness nor precision, and the API overview shows the sentence reads better without it. The
  aside also pushes the bullet past 50 words.
- **fix**: CUT the aside on the Home page.
