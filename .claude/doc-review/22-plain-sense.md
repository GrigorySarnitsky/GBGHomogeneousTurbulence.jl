# Plain-sense editor — findings (hat: plain-sense)

Read: the full rendered-site manuscript (`manuscript-full.md`), all 21 pages. Tests applied per
clause: paraphrase, non-vacuity, unprovoked defence, delete test, load-bearing subject, sentence
length/clause count, pronoun ambiguity, WHAT-vs-HOW. Extraction artifacts (merged admonition
titles, dropped italics, list merges) and decision-log history were not flagged per the
adjudication file. Candidates weighed before the cap: 44.

---

## 1. §1.3 calls the recurring max-speed reduction free; §1.4 calls it the one standing cost
- type: contradiction / severity: major / confidence: medium
- location A: PAGE observables_cache, §1.3 — "The reduction inside every other closing deposit
  recurs per iteration, and is work the following first stage would have done anyway (§1.4)."
- location B: PAGE observables_cache, §1.4 — "the closing deposit's maximum-speed reduction is
  one physical-vector pass every iteration, paid even by a hand-fixed-$\Delta t$ run"
- axis: whether the per-iteration maximum-speed reduction is work already owed or an added pass.
- description: §1.3 asserts the recurring reduction is work the next first stage would do anyway
  and cites §1.4 for it; §1.4 states the opposite — that this reduction is the one traffic-axis
  exception, paid even when nothing consumes it. Also, the first stage never reduces a maximum;
  the consumer is the timestep choice, and only on the adaptive path. REWRITE §1.3's sentence.

## 2. The PhaseShift reuse-contract prose cannot be paraphrased
- type: clarity / severity: minor / confidence: high
- location A: PAGE api / Generator, `ResolvedGenerator` admonition — "recorded as the identity of
  the `û` it was taken of rather than either signature"
- location B: same page, `displaced_velocity_source` field — "reuse needs this record to match
  and the caller's `displaced_velocity_current` promise"
- description: Both clauses fail the paraphrase test. "Rather than either signature" compresses
  "rather than being expressed in either verb's signature" past recovery; "needs this record to
  match and the caller's promise" is a broken coordination ("needs X to match and Y"). The
  contract itself is stated clearly in `scalar_rhs!`; these two compressions are the unreadable
  copies. REWRITE both.

## 3. "The `Simulation` `Simulation` must start somewhere" — a rename fossil garbles the sentence
- type: clarity / severity: minor / confidence: high
- location: PAGE architecture, §6, first bullet — "(The `Simulation` `Simulation` must start
  somewhere and starts at `Float64` / `Array`; …)"
- description: The doubled word leaves the sentence without a parseable subject — it reads as
  the type name twice. This is the shape of an alias-purge fossil (a deleted "front door" or
  "constructor" leaving its replacement duplicated). REWRITE: restore the missing noun
  ("the `Simulation` constructor must start somewhere").

## 4. "the form mirroring `particles_modified!`'s two" — an ellipsis the reader cannot fill
- type: clarity / severity: minor / confidence: high
- location: PAGE api / Cache, `fields_modified!` — "Given a `Simulation` it announces the change
  to that run's cache — the form mirroring `particles_modified!`'s two."
- description: "…'s two" omits its noun (forms), and one form cannot "mirror" two: the intended
  claim — this verb's two-form pattern matches its twin's — is a category mismatch as written.
  The twin's own sentence ("mirroring `deposit!`'s own `sim` form") shows the readable shape.
  REWRITE.

## 5. Over-long multi-clause sentences in ARCHITECTURE (counts reported)
- type: clarity / severity: minor / confidence: high
- location A: PAGE architecture, §8, skew-product bullet — "Triangularity is what licenses the
  composed propagator — … the experimenter's logbook rather than physics." (~85 words, 6+
  clauses, nested parentheses with internal semicolons)
- location B: PAGE architecture, §2 — "The run layer holds the pieces of §4 in one `Simulation`
  value, …" (~70 words, 5 clauses)
- location C: PAGE architecture, §4.1 — "The per-step scratch is not state: …" (~60 words, 4
  clauses)
- location D: PAGE architecture, §4.7, `StationarityCriterion` bullet — a parenthesis containing
  a full sentence boundary: "(a trailing-window flatness test … $\Delta t \varepsilon/k$. When
  the scalar is forced, $\langle\varphi^2\rangle$ must settle too)"
- description: Each exceeds the ~40-word / 3-clause bar; location D additionally closes one
  sentence and opens another inside a parenthesis, so the closing bracket lands two sentences
  after it opened. REWRITE: split each at its clause seams.

## 6. A defence against a confusion nobody has — repeated verbatim on three pages
- type: clarity / severity: minor / confidence: high
- locations: PAGE api / phenomenology / Scalings, Spectra, StructureFunctions — each `##
  References` preamble: "the leaf's independence means it does not rely on that list, not that
  the two never overlap"
- description: Unprovoked defence + delete test. An API-page reader has not been invited to
  think leaf independence forbids citation overlap with `ARCHITECTURE.md`; the sentence
  introduces the misreading it denies, and striking the whole "A few works are cited in
  `ARCHITECTURE.md` as well…" passage loses nothing the page's reader needs. CUT (on all three
  copies — it is one template).

## 7. "it is listed last here because a reader meets it last" — circular
- type: clarity / severity: minor / confidence: medium
- location: PAGE Home, Components, `Phenomenology` bullet — "it is listed last here because a
  reader meets it last."
- description: Fails non-vacuity: where does a reader "meet it last" if not in this very list?
  The intended reason — a user's workflow reaches validation-against-laws after running — is
  never stated, so the justification is the listing justifying itself. REWRITE to name the
  actual reason, or CUT the clause (the preceding include-order remark stands alone).

## 8. The glossary's τ row points "below" at a row that is above
- type: clarity / severity: minor / confidence: medium
- location: PAGE notation, Derived scales, $\tau$ row — "in the integrating factor's row below,
  $\tau$ is a Runge–Kutta stage substep"
- description: The integrating factor $\mathcal{E}$ row sits in "Spectral representation and
  operators", two sections earlier; there is no such row below. A reader following the
  instruction finds nothing. REWRITE ("above", or name the section).

## 9. "consumed (the closing note)" — a pointer that collides with the house sense of "closing"
- type: clarity / severity: minor / confidence: medium
- location A: PAGE api / Generator, `velocity_rhs!` — "`ω_consumed` — the stage vorticity in
  physical representation, consumed (the closing note)."
- location B: same page, `scalar_rhs!` — "`u_consumed` — the stage velocity in physical
  representation, consumed (the closing note)."
- description: The parenthesis means "see the admonition at the end of this docstring", but
  "closing" is a loaded word here — the closing deposit, the closing recovery — so the cold
  reader first tries those senses and fails. A pointer should name what it points at ("see the
  note below"). REWRITE.

## 10. `history_depth = 1` documented by itself, plus a dangling "which"
- type: clarity / severity: minor / confidence: medium
- location: PAGE api / Cache, `ObservablesCache` arguments — "the value of
  `history_depth``(particle_integration_scheme)` for the run's particle integration scheme,
  which is where a hand-assembled run gets the number"
- description: The keyword is defined as the value of a function of the same name, and the
  trailing "for the run's particle integration scheme" restates the argument already shown; the
  "which" then has no clear antecedent (the function? the value?). The entry's first clause
  already defines the quantity; the rest is a self-referring loop. REWRITE to one sentence:
  set it to `history_depth(scheme)`.

## 11. The `initial_spectrum` bullet buries its point in a nested-aside sentence
- type: clarity / severity: minor / confidence: medium
- location: PAGE api / SimulationRun, `Simulation` arguments, `initial_spectrum` — "Note the
  $\varepsilon$ half: it is the stationary forced estimate, so on a decaying run — where the
  explicit-$\nu$ advice above exists precisely because that balance does not hold — the model's
  dissipation-range placement inherits the same mismatch."
- description: A ~45-word sentence whose dash-aside itself contains a causal clause, inside a
  ~200-word bullet; the aside also leans on cross-bullet deixis ("the advice above"). The
  load-bearing subject (the model's dissipation-range placement) arrives last. REWRITE: state
  the caveat first, then the reason, in two sentences.

## 12. "Read the particle state off the fields directly" — "fields" means struct fields here
- type: clarity / severity: minor / confidence: medium
- location A: PAGE api / Particles, `Tracers` — "Read the particle state off the fields
  directly — the positions are `PointSet`s…"
- location B: same page, `unwrapped_positions` — "where the plain state is read off the fields
  directly"
- description: In this corpus "the fields" nearly always means the flow fields; here it means
  the struct's members, and the cold reader takes the wrong sense first ("read particle state
  off the velocity field?"). The corpus elsewhere polices exactly this kind of two-sense word
  (the glossary's "resolved" row). REWRITE: "off the struct's fields" or "through `tracers.positions`".

## 13. "The declaration is measured at construction, not trusted" — measured how?
- type: clarity / severity: minor / confidence: medium
- location: PAGE api / Forcing, `AbstractForcing` — "The declaration is measured at
  construction, not trusted."
- description: Fails paraphrase: what act does "measured" name? The reader cannot tell whether
  something numerically verifies steadiness or a constructor merely cross-checks the trait
  against the implemented hooks (the `ResolvedGenerator` admonition suggests the latter, and
  describes a different check — a missing declaration, not a false one). REWRITE to say what is
  checked, by whom, and what happens on failure — or CUT and rely on the `ResolvedGenerator`
  admonition.

## 14. The `DealiasingStrategy` docstring answers WHO chooses the default, not WHAT it is
- type: clarity / severity: minor / confidence: medium
- location: PAGE api / SimulationDomain, `DealiasingStrategy` — "The default is chosen by the
  `Simulation` constructor that builds a whole run from a few keywords."
- description: The reader at this sentence asks "which strategy is the default?" and is told
  only which component supplies it — the HOW/WHO where the WHAT was asked. Either name it
  (`TwoThirds`) or cut the sentence; `FixedDomain`'s own "Nothing here defaults" admonition
  already carries the delegation story. REWRITE or CUT.

## 15. The "register" definition ends on a noun-less "at the next"
- type: clarity / severity: minor / confidence: medium
- location A: PAGE notation, Vocabulary, register row — "storage a component computes one value
  into and overwrites at the next"
- location B: PAGE observables_cache, §1.2 — the same clause verbatim.
- description: "At the next" what — iteration, use, computation? A glossary definition is the
  one place an ellipsis may not lean on context, and this one is the term's single normative
  statement, copied verbatim into §1.2. REWRITE: "overwrites at the next use" (or whichever
  noun is meant).

## 16. "the length is 3.7 times smaller" — smaller than what?
- type: clarity / severity: nit / confidence: medium
- location: PAGE api / phenomenology / Spectra, `large_scale_length` — "at $C_\varepsilon = 0.5$
  the length is 3.7 times smaller and the spectrum integrates to $0.42k$"
- description: The comparative has no stated baseline in its own sentence; the reader must
  reconstruct that "the length" is $L_{11}$ fed in place of $\ell_0$ and the ratio is
  $\ell_0/L_{11}$. One prepositional phrase ("smaller than $\ell_0$") repairs it. REWRITE.

## 17. "after the leader both take …" — an unintroduced coinage for the first argument
- type: clarity / severity: nit / confidence: low
- location: PAGE api / Propagator, `step!` — "after the leader both take `state`, `domain`,
  `buffers` in the same order."
- description: "Leader" as "the leading argument" appears nowhere else in the corpus and is not
  in the vocabulary table; the sentence is decodable but stalls the reader on a one-off term.
  REWRITE ("after that first argument…").

## 18. A box that "uses this constant as an extrapolation"
- type: clarity / severity: nit / confidence: low
- location: PAGE api / phenomenology / Scalings, `Li2008` — "a low-Reynolds-number box — the
  small grids a smoke test reaches — uses this constant as an extrapolation."
- description: Anthropomorphism hiding the subject: a box uses nothing, and a constant is not
  "an extrapolation" — applying the constant there is one. The intended claim (below the
  calibration point the value is an extrapolation) has no stated agent. REWRITE.
