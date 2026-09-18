# Hat 18 — PLAIN-SENSE EDITOR

Does the sentence mean anything, and does it earn its place? Tests applied in order:
PARAPHRASE / NON-VACUITY / UNPROVOKED DEFENCE / DELETE TEST / LOAD-BEARING SUBJECT.
Each finding names the failed test and whether the fix is CUT or REWRITE.

---

## 1. `particles_modified!` contradicts itself in adjacent sentences

- **type**: contradiction · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: api / Cache, `particles_modified!`: "The run's own tracer advance is not such a change and keeps its history."
  - PAGE: api / Cache, `particles_modified!` (next sentence): "the run layer announces its own tracer advance (`advect!` followed by `record_particle_velocities!`, both inside `advance!`)"
- **contradicts**: itself, one sentence later, on the axis *is the run's own tracer advance announced or not?*
- **description**: Sentence one tells the reader the run's own advance is **not** the kind of change this verb announces; sentence two says the run layer **does** announce its own advance. A hand-run-loop reader cannot decide from this text whether an in-loop push needs the call. The probable truth — the run layer bumps the particles epoch without discarding history — is exactly what the words deny. Failed PARAPHRASE (the two cannot both be restated as true).
- **fix**: REWRITE — separate "advances the epoch" from "announces an out-of-band change".

## 2. Garbled field description on `ResolvedGenerator`

- **type**: clarity · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: api / Generator, `ResolvedGenerator` → Fields: "`displaced_velocity_source` — the `û` whose displaced velocity `phase_shift.u_shifted` holds displaced velocity, left fresh by `velocity_rhs!`"
- **description**: The clause cannot be paraphrased: "the `û` whose displaced velocity … holds displaced velocity" says the same noun phrase twice and leaves the relative clause without a predicate. A reader cannot tell whether the field stores a `û`, a marker, or a buffer. Failed PARAPHRASE.
- **fix**: REWRITE — e.g. "the `û` the displaced velocity in `phase_shift.u_shifted` was recovered from".

## 3. Subjectless sentence in `max_wavenumber`

- **type**: language-tone · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: api / SimulationDomain, `max_wavenumber`: "For the two sharp strategies sits strictly below the grid Nyquist $\tfrac{N}{2}\tfrac{2\pi}{L}$ — they zero the modes above it each step."
- **description**: The sentence has no subject; the reader has to reconstruct "it" (the cutoff) from the previous sentence. It reads as a copy-edit casualty and stops a first-pass read cold. Failed LOAD-BEARING SUBJECT.
- **fix**: REWRITE — "For the two sharp strategies the cutoff sits strictly below …".

## 4. `prepare!` stacks two parentheticals back to back

- **type**: clarity · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: api / Generator, `prepare!`: "arm the per-mode linear forcing rates (fill them, so the factor verbs return them instead of `nothing`) (its `set_forcing_rate!` hook, written into the generator's rate arrays)"
- **description**: One 70-word sentence carrying four clauses and three parentheticals, two of them adjacent with no connective, both glossing the same verb. The reader must hold "advance … and arm …" open across 40 words before the arguments arrive. Failed DELETE TEST on the second parenthesis (the hook name belongs in the first) and LOAD-BEARING SUBJECT.
- **fix**: REWRITE — merge the two parentheses, or split into two sentences.

## 5. `StationarityCriterion`: a 90-word sentence with a 40-word aside inside it

- **type**: clarity · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: api / SimulationRun, `StationarityCriterion`: "At each iteration it measures the dissipation $\varepsilon$ — … — and the kinetic energy $k$, which normalizes the eddy-turnover clock … and tests flatness over a trailing window"
- **description**: Roughly 90 words and six clauses. The em-dash aside (why $k$ is not gated on) is inserted between the two objects of "measures", so "and the kinetic energy $k$" reads at first as a new subject; the third verb "tests" then has to be re-attached to "it" over 60 words of intervening text. Failed the ~40-word/3-clause limit.
- **fix**: REWRITE as three sentences: what it measures, what it tests, why $k$ is excluded.

## 6. Front-page quick start: "that value" has no antecedent

- **type**: clarity · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: Home, "Quick start": "warmup!(sim) # spin up to statistical stationarity / (the default forcing drives k to that value — / see VarianceController before measuring k itself)"
- **description**: No value has been named anywhere in the snippet — the only prior comments concern the grid and $\nu$. The reader meets a demonstrative pointing at nothing on the package's first code example. "see VarianceController before measuring k itself" then issues an instruction without saying what the reader would learn there. Failed PARAPHRASE (ambiguous pronoun).
- **fix**: REWRITE — name the value ("drives $k$ to the default `kinetic_energy = 1.5`").

## 7. `initial_spectrum` states the same fact twice inside one sentence

- **type**: clarity · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: api / SimulationRun, `Simulation` → Arguments, `initial_spectrum`: "so its integral scale is `1/envelope_wavenumber` rather than the $L_{11}$ the seeded field will have"
  - same sentence, ~40 words later: "and the integral scale as `1/envelope_wavenumber`"
- **description**: One sentence of ~85 words with five clauses says the assumed integral scale is `1/envelope_wavenumber`, then repeats it as the last item of a four-item list in the same sentence. The repetition makes the reader hunt for a distinction that is not there. Failed DELETE TEST on the second occurrence.
- **fix**: CUT the repeat and split the sentence at the colon.

## 8. `recommended_cfl` explains a scaling before stating it

- **type**: organization · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: api / Propagator, `recommended_cfl`: "The same $1/\kappa_{\max}$ scaling is applied to both schemes' bases, including `IFRK2`'s empirical one"
  - next paragraph: "It scales that base by the domain's dealiasing: a strategy that keeps modes to a higher $\kappa_{\max}$ … takes a proportionally smaller step, $C_{\mathrm{CFL}} \propto 1/\kappa_{\max}$."
- **description**: The caveat about the $1/\kappa_{\max}$ scaling is printed **before** the sentence that introduces the scaling. "The same … scaling" refers forward to text the reader has not met, and the opening "It" of the later paragraph has to reach back past the caveat for its antecedent. Failed LOAD-BEARING SUBJECT (mechanism before the thing).
- **fix**: REWRITE — swap the two paragraphs.

## 9. `deposit!`'s argument-order sentence denies its own first clause

- **type**: clarity · **severity**: major · **confidence**: medium
- **locations**:
  - PAGE: api / Propagator, `deposit!`: "The argument order is shared with `step!` — the cache leads because it is what this call mutates — unlike `step!`, whose leading `scheme` is a dispatch tag — and `state`, `domain`, `buffers` follow in the same order as there."
  - PAGE: api / Propagator, `step!`: "The leading argument differs from `deposit!`'s in kind, and it is worth knowing which"
- **contradicts**: within one sentence — "shared with `step!`" versus "unlike `step!`" — on the axis *is the order the same or not?*
- **description**: Three em-dash asides in one sentence, the second cancelling the first clause; the reader ends up unsure whether the orders agree. The same comparison is then made a second time from the other side in `step!`, where "it is worth knowing which" tells the reader that something matters without saying why it would ever change what they write.
- **fix**: REWRITE one of the two and CUT the other; the shared tail (`state, domain, buffers`) is the only load-bearing fact.

## 10. "One piece of prior art is excluded by name" — and no name follows

- **type**: clarity · **severity**: major · **confidence**: medium
- **locations**:
  - PAGE: architecture, §8 Lenses and prior art: "One piece of prior art is excluded by name."
  - same paragraph: "The direction of the GBG packages is to replace it entirely, because it was problematic"
- **description**: The sentence promises a name and the paragraph gives none — the object is identified only as "the previous generation of this work — kept privately, outside the package". A reader cannot check, look up, or reason about a thing that is never named, so the six-sentence paragraph arguing that nothing may be justified by continuity with it defends against a confusion this document cannot create. "because it was problematic" asserts nothing that could be false. Failed NON-VACUITY and UNPROVOKED DEFENCE.
- **fix**: CUT to one sentence, or name the artifact.

## 11. The glossary's "resolved" does not define "resolved"

- **type**: clarity · **severity**: major · **confidence**: medium
- **locations**:
  - PAGE: notation, "Vocabulary": "resolved | in ResolvedFields and ResolvedGenerator, made concrete as one value. The numerical sense — a scale the grid resolves … — is the other reading, and the docs write it out in full wherever it is meant."
- **description**: "Made concrete as one value" is the meaning of *reified*, not of *resolved*; no ordinary reading of the word yields it. The entry then disambiguates against grid resolution — a reading it has just made more likely, not less, by giving a definition that matches neither the numerical sense nor the resolved/filtered contrast the architecture page uses (`ResolvedGenerator` … `FilteredGenerator` "the eventual LES sibling"). Failed PARAPHRASE and UNPROVOKED DEFENCE.
- **fix**: REWRITE — define it as the resolved/filtered axis, which is what the type names encode.

## 12. `IFLowStorageRK3` denies two collisions it alone introduces

- **type**: clarity · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / Propagator, `IFLowStorageRK3`: "with the stage coefficients $A_i = (0, -5/9, -153/128)$ — unrelated to the forcing rate $A(\boldsymbol{\kappa})$ of the `Forcing` page —"
  - same docstring: "in Williamson's 2N-storage count, whose $N$ counts evolved field registers, not the grid points $N$ of the rest of the documentation"
- **description**: Two defensive asides in one docstring, each naming a symbol from another page purely to deny it. Neither confusion is created here — the forcing rate never appears in this docstring — so both first introduce the reading they refuse. Struck, nothing is lost. Failed UNPROVOKED DEFENCE and DELETE TEST.
- **fix**: CUT both (the notation page is where a symbol clash is settled).

## 13. `fit` says the same thing twice in two sentences

- **type**: clarity · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / phenomenology / Phenomenology, `fit`: "the seam by which a run's own measurements become a parametrization sitting beside the literature. No methods are defined yet; it is the recorded extension point for fitting a run's own measurements to a parametrization."
- **description**: The second half of the second sentence restates the first sentence with the words re-ordered. Only "No methods are defined yet" carries new information. Failed DELETE TEST.
- **fix**: CUT the trailing clause.

## 14. `DeferredForcing`'s example is introduced by editorial housekeeping

- **type**: clarity · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / Forcing, `DeferredForcing` → Examples: "The two-form construction is the non-obvious part of this module, so the example lives here; the strategies themselves are built by the forms shown below."
- **description**: The sentence explains why the documentation is laid out as it is — a fact about the docs, not about the code — and its second half points at "the forms shown below", where what follows is the example itself and then `# Fields`. The reader looks for a list that is not there. Failed NON-VACUITY (first clause) and PARAPHRASE (second).
- **fix**: CUT.

## 15. `max_dt`: a four-clause run-on ending in "stops that"

- **type**: clarity · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: api / SimulationRun, `Simulation` → Arguments, `max_dt`: "The advective rule alone diverges as a decaying flow approaches rest — … — and it is the resolution bound that stops that, needing no constant from the caller."
- **description**: About 55 words across four clauses, with a 20-word em-dash aside separating the subject from its verb, closing on "stops that", whose referent is the aside rather than the main clause. The paragraph is otherwise the clearest in the argument list, which makes this sentence the one place a reader stalls.
- **fix**: REWRITE as two sentences.

## 16. "An epoch is not an iteration number" is defended on four separate surfaces

- **type**: organization · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: api / Cache, module: "An epoch counts changes to the state, not advances of the run"
  - PAGE: notation, "Vocabulary": "Not an iteration number: an announced out-of-band mutation advances an epoch without advancing the clock."
  - PAGE: api / SimulationRun, `current_step`: "after two steps and one announced mutation the clock reads step 2 and the fields epoch reads 4"
  - PAGE: decisions: "after two steps and one announced mutation the clock reads step 2 and the fields epoch reads 4 — measured, not assumed"
- **description**: The same denial, twice with the identical worked example, on four surfaces plus the `ObservablesCache` field list. Repetition at this density stops reading as clarification and starts reading as anxiety about a rename; a reader who meets it the fourth time learns nothing and begins to suspect the two really are confusable in the code. Failed DELETE TEST at three of the four sites.
- **fix**: CUT to one home (the `Cache` module docstring) plus the glossary line.

## 17. `ScalingLaw`: a trailing modifier with nothing to modify

- **type**: clarity · **severity**: nit · **confidence**: medium
- **locations**:
  - PAGE: api / phenomenology / Scalings, `ScalingLaw`: "— here the normalized dissipation $C_\varepsilon$, the Kolmogorov constant $C_K$, and the box-normalized dissipation group $G$ — possibly Reynolds-number-dependent."
- **description**: Three em-dash asides in one sentence, the last a bare adjective phrase that could attach to the group $G$, to the list, or to "a pure number characterizing developed turbulence" 30 words earlier — and it contradicts "a pure number" if read as attaching to the nearest noun. Failed PARAPHRASE (dangling modifier).
- **fix**: REWRITE — "Each may carry a Reynolds-number trend." as its own sentence.

## 18. `restart!`'s closing clause is unparaphrasable

- **type**: clarity · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: api / Particles, `restart!`: "Its bare-cache form clears the sample history the cache itself holds, but cannot dispatch here — so a hand-run loop that announces to the cache alone must call this as well, and a scheme carrying registers beyond that history is reached only this way."
- **description**: 45 words, three clauses, opening on "Its" (antecedent `particles_modified!`, two sentences back) and closing on "a scheme carrying registers beyond that history is reached only this way" — a passive with no agent, where the reader cannot tell what is "reached", by whom, or what would go wrong otherwise. Failed PARAPHRASE on the final clause.
- **fix**: REWRITE the last clause: say which registers, and what happens if the call is skipped.
