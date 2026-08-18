# Hat 12 — Plain-sense editor

Does each sentence MEAN something, and does it EARN its place? Tests applied per clause:
paraphrase / non-vacuity / unprovoked defence / delete test / load-bearing subject.
Fix verdicts are CUT or REWRITE. Style, notation, formatting and factual defects are other hats'.

---

## 1. `step!`'s argument-order paragraph states an order that is false on its natural reading

- **type**: clarity — **severity**: major — **confidence**: high
- **locations**:
  - PAGE: api / Propagator, "Time stepping" (`step!`): signature `step!(scheme, state, generator, domain, buffers, cache, dt)`, then
    "with `generator` after `state` and `cache`, `dt` closing this signature"
  - PAGE: api / Propagator, "Time stepping" (`deposit!`): "The argument order is shared with `step!` — the mutated dispatch object (here the cache) leads"
- **description**: The clause reads most naturally as "generator after *both* state and cache", which the signature above
  contradicts — `generator` is third, `cache` sixth. The whole paragraph justifies a *convention* the printed signature
  already shows, and is then restated in `deposit!`; "so the chained pair transposes nothing" is unparaphrasable as user
  guidance. Fails the delete test twice over.
- **fix**: CUT both convention paragraphs (or, if kept, REWRITE as "`generator` follows `state`; `cache` follows `buffers`").

## 2. `deposit!`'s second sentence: ~95 words, five clauses, and cost accounting where the reader wants the arguments

- **type**: clarity — **severity**: major — **confidence**: high
- **locations**:
  - PAGE: api / Propagator, `deposit!`: "its pass counts are unchanged but for one: the maximum-speed reduction runs every iteration"
- **description**: One sentence carries the deposit list, the transform-count claim, the pass-count exception, the fixed-`dt`
  caveat, and — smuggled in at the tail — the only statement of what `domain` and `buffers` are for. A reader asking "what
  do I pass?" must parse a ledger argument to find out. The audit claim belongs in the design page, which already makes it.
- **fix**: REWRITE — arguments first as their own entries; move the pass-count exception to a short closing note.

## 3. `Simulation`'s `initial_spectrum` entry nests parentheses two deep and buries its subject

- **type**: clarity — **severity**: major — **confidence**: high
- **locations**:
  - PAGE: api / SimulationRun, `Simulation` Arguments: "its integral scale set to `1/peak_wavenumber` (which is the Gaussian
    envelope's characteristic wavenumber $\kappa_p$, not the shell-spectrum peak"
- **description**: A parenthesis inside a parenthesis inside the entry, closing with three `)` in a row. What the option *does*
  (draw the initial velocity from a model spectrum) is stated first, then dissolved into a caveat about a *different*
  keyword — one the `peak_wavenumber` entry two lines above already states ("each shell-summed spectrum peaks at
  $\kappa_p/\sqrt{2}$"). The reader cannot hold the sentence.
- **fix**: REWRITE — one sentence for the option, drop the duplicated peak caveat (leave it with `peak_wavenumber`).

## 4. "not a filtered subset of the scales" — a fossil that plants the reading it denies

- **type**: clarity — **severity**: major — **confidence**: high
- **locations**:
  - PAGE: observables_cache, §3.1 The calls: "the resolved fields being the two integrated fields, not a filtered subset of the scales"
- **description**: Nothing on this page — or in a DNS package with no LES rung built — suggests "resolved fields" means a
  scale-filtered subset. The denial is the first place a reader meets that idea, and it arrives mid-sentence inside the
  description of `fields_modified!`, whose subject is announcing an out-of-band mutation. Classic unprovoked defence, most
  likely left by the `ResolvedFields`/`FilteredFields` naming discussion.
- **fix**: CUT the clause.

## 5. Architecture §4.1's `State` bullet is one ~600-word paragraph containing an 85-word sentence

- **type**: organization — **severity**: major — **confidence**: medium
- **locations**:
  - PAGE: architecture, §4.1: "An accessor (`velocity_physical`, `vorticity_physical`, `scalar_physical`, the cached `max_speed`) serves the deposited value or throws"
- **description**: That sentence then chains: the no-recompute rule, the per-factor epoch counters, `step!` advancing the fields
  epoch, the out-of-band-mutation verb, a parenthetical decision cite, and the required follow-up `deposit!` — five clauses,
  85 words. The surrounding bullet runs six such sentences without a break, so the section's load-bearing claim (the state is
  the single source of truth) is indistinguishable from its footnotes.
- **fix**: REWRITE — split the bullet into state / recoveries / cache-contract paragraphs; one claim per sentence.

## 6. Grid mode: a dangling "which" leaves the reader guessing what credits what

- **type**: clarity — **severity**: major — **confidence**: medium
- **locations**:
  - PAGE: api / SimulationRun, `Simulation` "Setting the Reynolds number", grid mode: "which credits the whole retained band as clean signal, exact for `TwoThirds` and `PhaseShift`"
- **description**: The 80-word sentence before it has three candidate antecedents — the identity $\kappa_{\max}\eta = f\pi\eta/\Delta x$,
  the `k_max_η = 2` reading, and the wider-band claim. "Credits" has no stated agent (the criterion? the user? the
  constructor?), so the caveat that follows — the one thing a `HouLi` user must act on — hangs off an unresolved pronoun.
- **fix**: REWRITE — "The criterion treats the whole retained band as clean signal, which is exact for … and approximate for `HouLi`."

## 7. `step!`: "the step allocates and resides nothing"

- **type**: clarity — **severity**: minor — **confidence**: high
- **locations**:
  - PAGE: api / Propagator, `step!`: "so the step allocates and resides nothing beyond its own spectral stage registers"
- **description**: "Resides" is intransitive; a step cannot "reside" a register. The reader must guess "occupies no residency
  beyond". It closes a ~70-word sentence whose middle already carries a three-appositive aside ("the values of the instant
  between iterations, where the cache's deposits are current, deposited there by the previous iteration's `deposit!`;
  nothing is recomputed on a read").
- **fix**: REWRITE — "allocates nothing and holds nothing resident beyond its own spectral stage registers"; split the sentence.

## 8. `AbstractForcing` states the return-value contract twice

- **type**: organization — **severity**: minor — **confidence**: high
- **locations**:
  - PAGE: api / Forcing, `AbstractForcing`: "Three of the four hooks mutate and return their second argument; `prepare_forcing!` is the exception"
  - PAGE: api / Forcing, `AbstractForcing`: "Each mutating hook returns its mutated argument (`set_forcing_rate!` the rate, …); `prepare_forcing!` returns `nothing`."
- **description**: Same fact, same docstring, separated only by the lifecycle paragraph. The second copy adds the per-hook
  breakdown, so the first is pure restatement — and the first is the one carrying the reason ("its `field` is read-only").
  A reader who reads both wonders whether two different contracts are being described.
- **fix**: CUT the first; fold its "`field` is read-only" clause into the second.

## 9. The Particles page says "changing the scheme changes nothing here" three times

- **type**: organization — **severity**: minor — **confidence**: high
- **locations**:
  - PAGE: api / Particles, "The tracer set" blurb: "so changing the scheme changes nothing here"
  - PAGE: api / Particles, `Tracers` Fields: "so changing the scheme changes no part of this type"
  - PAGE: api / Particles, `AbstractParticleIntegrator`: "the supertype exists so that adding one changes no other type"
- **description**: One design point, three renderings within a single page, none adding information to the previous. The
  `ParticleIntegratorBuffers` docstring then makes it a fourth time ("This storage belongs to the scheme, not to the
  trajectory"). Each instance passes the delete test individually; collectively they read as anxiety about the split rather
  than documentation of it.
- **fix**: CUT two of the three; keep the one on `ParticleIntegratorBuffers`, which owns the storage.

## 10. `truncate_to_band!`'s admonition argues about its own name and repeats the blurb above it

- **type**: organization — **severity**: minor — **confidence**: high
- **locations**:
  - PAGE: api / SimulationDomain, "Band truncation" blurb: "Under `PhaseShift` this is only part of the dealiasing — the averaging of two displaced evaluations is the other half"
  - PAGE: api / SimulationDomain, `truncate_to_band!` admonition: "and deliberately does not claim to complete the dealiasing, because for one strategy it does not"
- **description**: The admonition restates the blurb printed immediately above it, and its subject is the *name* rather than the
  operation ("The name says what this call does … and deliberately does not claim"). A reader learns nothing from the second
  telling; the defence of a naming choice belongs to the design record.
- **fix**: CUT the admonition (the blurb and the docstring body already carry the per-strategy facts).

## 11. The `Cache` module map points at verbs a reader cannot look up

- **type**: clarity — **severity**: minor — **confidence**: high
- **locations**:
  - PAGE: api / Cache, module docstring: "internal per-slot deposit and take verbs move the individual epochs"
- **description**: Unparaphrasable from the page: which verbs, what "take" means, and what "move the individual epochs" does
  for the reader. They are undocumented internals, so the sentence names something the reader can neither call nor read
  about, in the one place that is supposed to be a map of the public surface.
- **fix**: CUT (or REWRITE to "each slot's epoch is set as it is deposited", with no verb names).

## 12. Architecture §4.7 explains an API that no longer exists

- **type**: organization — **severity**: minor — **confidence**: high
- **locations**:
  - PAGE: architecture, §4.7: "The run layer once carried forwarding methods that hid this split; they bought a shorter call at the price of a second docstring per quantity"
- **description**: §4.7 is a current-state section. The sentence documents a removal and its rationale — history, already recorded
  in the decision log, and repeated there almost verbatim. Delete it and the reader loses nothing about how the package works
  today; keep it and a reader new to the package learns of a surface they cannot use.
- **fix**: CUT (the decision-log entry keeps the record).

## 13. "A fifth name is not a hook" — a denial with nothing to deny

- **type**: language-tone — **severity**: minor — **confidence**: medium
- **locations**:
  - PAGE: api / Forcing, module docstring: "A fifth name is not a hook: `DeferredForcing` is the operator-free keyword form of a strategy"
- **description**: The list above it is explicitly "up to four methods… listed in the order the step calls them"; nothing invites
  the reading that `DeferredForcing` is a fifth hook. The sentence opens by correcting a mistake the reader has not made, and
  the useful content ("the operator-free keyword form, materialized once the domain exists") is demoted behind the correction.
- **fix**: REWRITE, subject first: "`DeferredForcing` is the operator-free keyword form … built before the domain exists."

## 14. `Simulation` glosses the docs' own house word inside its own docstring

- **type**: language-tone — **severity**: minor — **confidence**: high
- **locations**:
  - PAGE: api / SimulationRun, `Simulation`: "(\"front door\" names exactly this convenience form throughout — the constructor that builds every component for you)"
  - PAGE: api / Cache, `ObservablesCache`: "The `Simulation` front door — the convenience constructor that builds every component — builds, wires, and seeds one for you."
- **description**: A parenthesis that documents the manuscript's vocabulary rather than the object. The same gloss is then
  re-attached at every other mention (`ObservablesCache`, `ResolvedGenerator`, `DealiasingStrategy`), so the definition is
  paid for four times and never lands anywhere. Either the term is self-evident, or it should be used without apology.
- **fix**: CUT the self-referential parenthesis; keep one plain description at the constructor.

## 15. `run!` leaks the audit ledger into the front-door loop verb

- **type**: clarity — **severity**: minor — **confidence**: medium
- **locations**:
  - PAGE: api / SimulationRun, `run!`: "so the closing deposit's maximum-speed reduction and its host readback happen every iteration even under a fixed `dt`"
- **description**: `run!` is the first verb most users call. Its third sentence is a per-iteration cost note about a device
  readback — a fact about the schedule's uniformity, not about how to drive a run, and one already stated in `deposit!`, in
  the design page §1.4, and in the decision log. It displaces the thing a reader needs there: what the callback receives.
- **fix**: CUT here; the cost claim keeps its home in `deposit!` and on the design page.

## 16. "a solver with no cache serving only its own dynamics" — a dangling modifier

- **type**: clarity — **severity**: minor — **confidence**: medium
- **locations**:
  - PAGE: observables_cache, §1.3: "relative to a solver with no cache serving only its own dynamics, the run pays one extra closing deposit"
- **description**: Is it the solver or the cache that "serves only its own dynamics"? Both parses are grammatical and they
  describe different comparisons, so the baseline of the whole cost claim is undetermined — in the sentence that quantifies
  what caching costs. The reader cannot check the accounting without first guessing the reference solver.
- **fix**: REWRITE — "relative to a solver that keeps no cache and serves only its own dynamics".

## 17. `SaffmanDissipation`: "about half the earlier Townsend 1951 spectrum"

- **type**: clarity — **severity**: minor — **confidence**: medium
- **locations**:
  - PAGE: api / phenomenology / Spectra, `SaffmanDissipation`: "about half the earlier Townsend 1951 spectrum"
  - PAGE: api / phenomenology / Spectra, `SaffmanDissipation`: "whose coefficient is skewness-dependent (about 2.6 to 3.3)"
- **description**: Half of *what* — the coefficient, the spectrum's amplitude, its exponent? A spectrum cannot be halved
  meaningfully without saying in which quantity. And "skewness-dependent" names no skewness (the page never introduces one),
  so a cold reader cannot tell which parameter would move the 2.6–3.3 range. The closing "than the physical range would" has
  the same problem: which physical range?
- **fix**: REWRITE — name the quantity being halved and the skewness meant, or CUT the comparison.

## 18. `PhaseShift`: a relative clause torn from its noun by a 14-word gloss

- **type**: clarity — **severity**: minor — **confidence**: high
- **locations**:
  - PAGE: api / SimulationDomain, `PhaseShift`: "cancels the aliasing images — the spurious spectral replicas … folds back into the resolved band — that wrap in an odd number of axes"
- **description**: The restrictive "that wrap in an odd number of axes" is the load-bearing qualifier — it is *why* the spherical
  cutoff is still needed — but by the time it arrives the nearest noun is "the resolved band", and the sentence reads as if
  bands wrap in axes. The definition inserted between noun and qualifier should follow the sentence, not split it.
- **fix**: REWRITE — "cancels the aliasing images that wrap in an odd number of axes (the spurious spectral replicas …)".

## 19. `particle_scheme` apologises for a name instead of stating what it does

- **type**: language-tone — **severity**: minor — **confidence**: medium
- **locations**:
  - PAGE: api / SimulationRun, `Simulation` Arguments: "a different axis from `tracer_scheme` despite the neighbouring names"
- **description**: The entry's job is to say what the option sets; half of it concedes that the two keyword names mislead. Once
  written down, the concession makes the collision *more* visible without removing it — and the page elsewhere renames for
  exactly this reason (`Tracers`' keyword is `interpolation_scheme`). Documentation is being used to patch a name.
- **fix**: CUT the concession; rename `tracer_scheme` → `interpolation_scheme` at the front door to match `Tracers` (owner's call).

## 20. The epoch-vs-step worked example is printed four times, verbatim

- **type**: organization — **severity**: minor — **confidence**: medium
- **locations**:
  - PAGE: api / Cache, module docstring: "after two steps and one announced mutation the clock reads step 2 and the fields epoch reads 4"
  - PAGE: api / SimulationRun, `current_step`: same sentence
  - PAGE: observables_cache, §1.3: same sentence in parentheses
  - PAGE: architecture, §11 (2026-08 "Stamp is retired"): same sentence
- **description**: Two docstring copies are defensible under the read-complete-at-the-REPL rule; the design page and the decision
  log make four. By the fourth the example reads as a tic rather than an aid, and the `ObservablesCache` Fields list restates
  it a fifth time in prose ("will run ahead of `current_step`").
- **fix**: CUT from the design page and from the `ObservablesCache` Fields entry; keep the two docstring copies.

## 21. The notation page states the ϰ-distinctness convention twice

- **type**: organization — **severity**: nit — **confidence**: high
- **locations**:
  - PAGE: notation, "Conventions" table: "The scalar diffusivity $\varkappa$ (Parameters) is a fourth, deliberately distinct glyph."
  - PAGE: notation, "Parameters": "(The scalar diffusivity $\varkappa$ is a deliberately distinct glyph from the wavenumber magnitude $\kappa$ and the turbulent kinetic energy $k$.)"
- **description**: The same convention, on one short page, in two places roughly 25 lines apart — the second adding nothing the
  first did not say, and pointing back at the table it repeats. The parenthetical also floats free of any table row, so it
  reads as an editorial aside rather than part of the glossary.
- **fix**: CUT the free-floating parenthetical under Parameters.

## 22. "That is bookkeeping, not a slogan"

- **type**: language-tone — **severity**: nit — **confidence**: medium
- **locations**:
  - PAGE: observables_cache, §1.4: "That is bookkeeping, not a slogan: every slot is a register the iteration fills anyway"
- **description**: The text has not been accused of sloganeering; the clause defends the author rather than informing the reader,
  and the colon would introduce the evidence just as well without it. Same shape as the other pre-emptive denials on this
  page ("refusals rather than inconveniences", "not a promise").
- **fix**: CUT the clause, keep the evidence after the colon.
