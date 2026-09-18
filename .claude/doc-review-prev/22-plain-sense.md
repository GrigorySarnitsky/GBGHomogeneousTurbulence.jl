# Plain-sense editor — hat 22

Reviewer question: does each sentence mean anything, and does it earn its place? Tests applied in
order: paraphrase, non-vacuity, unprovoked defence, the delete test, load-bearing subject; plus
overlong sentences (>40 words, ≥3 clauses), ambiguous pronouns, anthropomorphism hiding a subject,
and HOW-where-the-reader-asked-WHAT. Candidates weighed before the cap: **38**. Findings: 24.

---

## 1. The Built-column rule contradicts its own table two rows later
- **type**: contradiction / **severity**: major / **confidence**: high
- **locations**: PAGE observables_cache §2.4 — "reads `—` wherever Cached is not yes"; same table,
  sample-history row — "depends | yes"
- **contradicts**: the table's own history row: Cached = "depends", Built = "yes" — the axis is the
  stated Built-column rule vs. the table it introduces.
- The intro sentence states a rule ("Built … reads `—` wherever Cached is not yes") that the very
  next screen of the same table violates: the sample-history row has Cached = depends and
  Built = yes. A reader trying to use the rule to parse the table is immediately contradicted.
  Fix: REWRITE the rule (e.g. "wherever Cached is no or never") or the row.

## 2. "An additive source is what a state-dependent rate takes" — garbled routing sentence
- **type**: clarity / **severity**: minor / **confidence**: high
- **locations**: PAGE observables_cache §2.2 — "An additive source is what a state-dependent rate
  takes, the default velocity forcing among them"
- Paraphrase fails on first read: a *source* is not something a *rate* "takes" — the intended
  meaning is "a state-dependent rate must take the additive-source route". The appositive "the
  default velocity forcing among them" dangles with no clear head ("them" = state-dependent
  rates? sources?). Load-bearing routing content in a broken frame. Fix: REWRITE.

## 3. Double-parenthetical sentence in §4.4 collapses grammatically
- **type**: clarity / **severity**: minor / **confidence**: high
- **locations**: PAGE architecture §4.4 — "keyword form (`NoForcing`, taking no operators, has the
  one form) (`ConstantPower(injection_rate = 0.1)`, a `DeferredForcing`) materialized when"
- Two parentheticals sit back-to-back with no connective, and the participle "materialized" then
  attaches to nothing readable — "form (…) (…) materialized when `Simulation` builds the frame"
  has no parsable spine. The reader must reverse-engineer that the *keyword form returns* a
  `DeferredForcing` which is later materialized. Fix: REWRITE as two sentences.

## 4. "so `spec isa Pope2000` holds" — a language triviality asserted five times
- **type**: clarity / **severity**: minor / **confidence**: high
- **locations**: PAGE api/phenomenology/Spectra, `Pope2000` — "so `spec isa Pope2000` holds for a
  value this constructor returns, exactly as for the presets that are plain structs"; same page,
  `VonKarman1948` and `Pao1965` (near-identical closing sentences); Spectra module docstring —
  "so `spec isa Pope2000` holds either way"; PAGE phenomenology — "so `spec isa Pope2000` and
  `spec isa EnergySpectrum` both hold"
- Unprovoked defence (test 3) and vacuity (test 2): to a fresh reader, a constructor named
  `Pope2000` returning a value for which `isa Pope2000` holds is Julia's default behaviour — the
  sentence defends against the retired factory-function era the current text never mentions. One
  statement (the module's "either way", which does carry alias-vs-struct content) earns its place;
  the three per-preset repetitions are fossils. Fix: CUT the per-preset closings. (The alias design
  itself is adjudicated and not flagged.)

## 5. "if a slot is still with its epoch cleared" — broken English
- **type**: clarity / **severity**: minor / **confidence**: high
- **locations**: PAGE observables_cache §1.3 — "the completeness check throws if a slot is still
  with its epoch cleared"
- "is still with its epoch cleared" is not a grammatical predicate; the reader must guess at
  "still has its epoch at the cleared sentinel". Fix: REWRITE ("if any slot's epoch is still
  cleared" / "still un-deposited").

## 6. "Announcing to a bare cache … also takes `restart!`" — verb carries no actor
- **type**: clarity / **severity**: minor / **confidence**: high
- **locations**: PAGE api/Cache, `particles_modified!` — "Announcing to a bare cache rather than a
  `Simulation` also takes `restart!` for a scheme carrying its own registers"
- Paraphrase fails: "announcing … takes `restart!`" — who calls what? The intended instruction
  (a hand-run loop announcing to a bare cache must ALSO call `restart!` itself) is buried under a
  gerund subject and the vague verb "takes". The next sentence repeats the content more clearly,
  so the delete test nearly passes. Fix: REWRITE or CUT in favour of the following sentence.

## 7. `initial_spectrum` entry: one ~120-word sentence states the integral scale twice
- **type**: clarity / **severity**: minor / **confidence**: high
- **locations**: PAGE api/SimulationRun, `Simulation` Arguments — "its integral scale is
  `1/envelope_wavenumber` rather than the $L_{11}$ the seeded field will have"; same entry, same
  sentence — "and the integral scale as `1/envelope_wavenumber`"
- The single sentence enumerating the assumed state asserts its integral-scale value twice — once
  before the colon and again inside the four-item list — inside a ~120-word run-on with three
  levels of qualification. The duplicate clause fails the delete test verbatim. Fix: REWRITE the
  entry as two or three sentences, one statement of the integral scale.

## 8. `gate_skewness` entry: ellipsis "when the run must be", plus duplicated advice
- **type**: clarity / **severity**: minor / **confidence**: high
- **locations**: PAGE api/SimulationRun, `StationarityCriterion` Arguments — "the default is
  permissive; raise `skew_floor` toward $0.4$ when the run must be"; same docstring, `skew_floor`
  entry — "Raise it toward `0.4` when the run's statistics depend on the cascade being mature"
- "when the run must be" is elliptical to breaking — must be *what*? (strict, two clauses back).
  And the same raise-toward-0.4 advice appears twice in one Arguments list, in different words.
  Fix: REWRITE the ellipsis; keep the advice in the `skew_floor` entry only.

## 9. `turnover_time = nothing` — the default's behaviour is never stated
- **type**: clarity / **severity**: minor / **confidence**: medium
- **locations**: PAGE api/Forcing, `VarianceController` Arguments — "`turnover_time = nothing` —
  the large-eddy turnover time $t_\ell = 2k_\infty/3\varepsilon_\infty$ (Bassenne's convention…)"
- The entry defines what the quantity *is* but never says what passing `nothing` *does* — the
  reader must infer that `nothing` means "computed for you from that formula and the stationary
  estimate". Every other sentinel default on these pages states its resolution (`HouLi`'s
  `strength = nothing`, `Simulation`'s `κ_max_η`). The reader asked WHAT the default does and got
  a definition. Fix: REWRITE — one clause stating the auto behaviour.

## 10. §4.5 IFRK2 sentence: predicate resumes after two nested em-dash lists
- **type**: clarity / **severity**: minor / **confidence**: high
- **locations**: PAGE architecture §4.5 — "dearer in memory — three spectral registers per field
  against the low-storage scheme's two — `IFLowStorageRK3` an accumulator plus the assembly
  register; …— and imaginary-axis unstable"
- One ~60-word sentence, five clauses, with the main predicate ("is … and imaginary-axis
  unstable") resuming after a two-level nested apposition containing its own semicolon list. The
  reader loses the subject `IFRK2` twice. Fix: REWRITE as two sentences (the register breakdown
  its own sentence).

## 11. §4.6 `EndpointHeun` sentence: ~95 words, six-plus clauses
- **type**: clarity / **severity**: minor / **confidence**: medium
- **locations**: PAGE architecture §4.6 — "The default scheme, `EndpointHeun`, is Heun-in-time on
  the velocity at the iteration's two endpoints: $\boldsymbol{v}_1$ is the trajectory sample …"
- One sentence runs from the scheme's identity through the sample's storage, its double-epoch
  dating, a parenthetical decision citation, the predictor's definition, and a closing
  cross-reference — ~95 words, at least six clauses, with the cacophonous "the previous closing
  deposit deposited" en route. Fix: REWRITE — split at the $\boldsymbol{v}_2$ clause.

## 12. "before any iteration runs" says the wrong thing at every $t_n$
- **type**: clarity / **severity**: minor / **confidence**: medium
- **locations**: PAGE observables_cache §1.1 — "At each instant $t_n$ between iterations, before
  any iteration runs, sits the observation"
- "before any iteration runs" reads as "before the first iteration", yet the sentence quantifies
  over *each* $t_n$ — the intended meaning is "before the *next* iteration runs". The
  mis-scoped "any" makes the sentence self-contradictory on first parse. Fix: REWRITE ("before
  the next iteration begins").

## 13. "there is nothing to cache" — about a quantity the cache does cache
- **type**: clarity / **severity**: minor / **confidence**: medium
- **locations**: PAGE observables_cache §1.2 — "the per-point speed field is never whole anywhere;
  there is nothing to cache"; §2.4 table — "the maximum speed … | yes"
- The closing clause's antecedent is the speed *field*, but sitting at the end of the `max_speed`
  paragraph it reads as "nothing about `max_speed` is cached" — which §2.4 (and §1.3, "it is the
  only number the cache holds") then contradicts. The pronoun-free "nothing" needs its noun.
  Fix: REWRITE ("no field to cache — the number itself is").

## 14. "A slot's epoch … takes three values: the observable …" — a counter cannot hold a field
- **type**: clarity / **severity**: minor / **confidence**: medium
- **locations**: PAGE observables_cache §1.3 — "A slot's epoch says what it holds, and takes three
  values: the observable at a named $t_n$, or the producer's scratch"
- The sentence makes the epoch (a counter) "take" the observable and the scratch as its values —
  conflating the slot's *contents* with the epoch's *state*. The parenthetical after it then
  quietly gives the true mechanism, admitting the lead sentence didn't. Paraphrase requires
  reading past the sentence being paraphrased. Fix: REWRITE ("says which of three states the slot
  is in").

## 15. "so the state itself cannot go stale" — the "so" claims a causation that isn't there
- **type**: clarity / **severity**: minor / **confidence**: medium
- **locations**: PAGE api/State, `ResolvedFields` — "each iteration … recovers them at its end
  into the `ObservablesCache`, so the state itself cannot go stale"
- Non-sequitur connective: depositing recoveries into the cache does not make the state unable to
  go stale — the true reason is that the physical fields are *not part of the state*, so there is
  nothing in it to fall out of date. As written, the reader is invited to derive the conclusion
  from the wrong premise. Fix: REWRITE the causal link.

## 16. `recommended_cfl`: a double-"and" run-on, and "a run that holds its energy" is ambiguous
- **type**: clarity / **severity**: minor / **confidence**: medium
- **locations**: PAGE api/Propagator, `recommended_cfl` admonition — "and there is no code-level
  guard for this, and adding one would mean giving a grid-and-scheme property a physics argument";
  same admonition — "verify it against a run that holds its energy"
- The sentence chains three independent clauses with bare "and"s (~55 words). And "a run that
  holds its energy" is genuinely two readings: a run under an energy-holding forcing, or a run
  whose energy stays bounded (the stability check presumably meant). Fix: REWRITE; disambiguate
  the verification clause.

## 17. `max_dt`: the diffusive cap acquires a third, unbound name mid-entry
- **type**: clarity / **severity**: minor / **confidence**: medium
- **locations**: PAGE api/SimulationRun, `Simulation` Arguments — "and it is the resolution bound
  that stops that"; same entry, one sentence earlier — "the longest mode's diffusive-decay time
  $1/(D\kappa_{\min}^{2})$"
- Within one entry the same bound is "the longest mode's diffusive-decay time", then "the
  resolution bound"; `advance!`'s docstring calls it "the box-and-diffusivity cap". "Resolution
  bound" also collides with the resolution criterion $\kappa_{\max}\eta$ two entries up — a
  reader will reach for the wrong referent. Fix: REWRITE to reuse one name.

## 18. "per the constructor-first convention for small records" — a house term on a user surface
- **type**: clarity / **severity**: minor / **confidence**: medium
- **locations**: PAGE api/phenomenology/Spectra module docstring — "plain positional parameter
  records, per the constructor-first convention for small records"
- The clause cites an internal documentation convention (CLAUDE.md's type-docstring template) as
  if the reader knew it; on a cold read "the constructor-first convention for small records" is
  an unbound term that explains nothing about the API. Delete test: strike the clause and the
  sentence loses nothing a user needs. Fix: CUT.

## 19. Architecture §2: the run-layer paragraph is two ~70-word sentences
- **type**: clarity / **severity**: minor / **confidence**: medium
- **locations**: PAGE architecture §2 — "The run layer holds the pieces of §4 in one `Simulation`
  value, chooses a stable timestep …" (and the `warmup!` sentence that follows)
- Each of the paragraph's first two sentences runs ~70 words across five-plus clauses, with a
  parenthetical aside ("$n$ iterations, $n+1$ observations") interrupting the callback clause and
  a second em-dash aside inside the `warmup!` sentence. Both paraphrase, but only on a second
  pass. Fix: REWRITE — one clause per capability.

## 20. Decision-log epoch example: the arithmetic is underivable as stated
- **type**: clarity / **severity**: minor / **confidence**: medium
- **locations**: PAGE decisions, "Stamp is retired" entry — "after two steps and one announced
  mutation the clock reads step 2 and the fields epoch reads 4 — measured, not assumed"
- Two steps plus one mutation is three advances; the entry gives the reader no way to reach 4.
  The `current_step` docstring supplies the missing premise ("The constructor's seeding deposit
  already leaves the fields epoch at 1") — the log entry omits it and papers over the gap with
  "measured, not assumed", which concedes the number cannot be derived from the sentence.
  Fix: REWRITE — add the seeding-deposit clause (the entry is recent, not superseded history).

## 21. Quick-start comment block is a five-line conceptual lecture
- **type**: clarity / **severity**: nit / **confidence**: medium
- **locations**: PAGE Home, Quick start — "One ITERATION is one advance: a step, then the DEPOSIT
  that closes it. A deposit writes …"
- A ~65-word, three-term definitional essay (ITERATION / DEPOSIT / EPOCH, in caps) sits as a code
  comment between two example lines. The quick-start reader asked what the three calls below
  return; the HOW/vocabulary belongs to the cache page, which owns it. Fix: CUT to one line
  ("the cache serves what the last iteration deposited") and link.

## 22. "and the integral-scale one smaller again" — ellipsis below the parse threshold
- **type**: clarity / **severity**: nit / **confidence**: medium
- **locations**: PAGE api/Generator, `FlowConditions` — "the box-scale value is $2\pi/\nu$, and
  the integral-scale one smaller again"
- "the integral-scale one smaller again" compresses "the integral-scale Reynolds number is
  smaller still" past the point of first-pass parsing — "one" must be recovered as a pro-form for
  "value" while "again" means "further". Fix: REWRITE the clause.

## 23. "though it inherits the base's standing" — "standing" is a guess
- **type**: clarity / **severity**: nit / **confidence**: medium
- **locations**: PAGE api/Propagator, `recommended_cfl` — "holding whether the base was computed
  or measured, though it inherits the base's standing"
- "Standing" (the epistemic status computed-vs-empirical, presumably) is not a term the page has
  established; the reader must invent its meaning. The preceding clause already says the scaling
  holds either way, so the delete test nearly passes. Fix: CUT, or REWRITE as "the scaled value
  is only as trustworthy as its base".

## 24. "and not by this catalogue" fails the delete test
- **type**: clarity / **severity**: nit / **confidence**: medium
- **locations**: PAGE api/SimulationDomain, `DealiasingStrategy` — "is decided by the `Simulation`
  constructor that builds a whole run from a few keywords — the front door — and not by this
  catalogue"
- Unprovoked defence: no reader expects a supertype docstring ("this catalogue" — an odd
  self-reference) to decide runtime defaults. Strike the final clause and nothing is lost.
  Fix: CUT.
