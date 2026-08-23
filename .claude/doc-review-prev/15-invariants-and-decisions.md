# Hat: invariants-and-decisions

Audits whether the rendered docs honour the package's own recorded invariants (CLAUDE.md "Core
invariants") and the ARCHITECTURE.md §11 decision log, in both directions — the current state
against a decision, and a current-state claim with no decision backing it.

Read in full: CLAUDE.md, ARCHITECTURE.md §1–§11 (all 56 decisions plus §References), the rendered
manuscript (all 20 pages, `manuscript-full.md`), and `src/*.jl` for cross-checks (include order,
`velocity_rhs!`/`scalar_rhs!` consumed-argument naming, Phenomenology's dependency list). The corpus
is unusually self-consistent — the numeric cross-checks I ran (transform counts per dealiasing
strategy, spectral/physical register counts per scheme, the `(k/G)^{3/2}/L` and
`κ_max·η = fπη/Δx` algebra, the two-`(M,3)`-arrays-per-side split of decision 50, the include order
in `GBGIsotropicTurbulence.jl` against CLAUDE.md and both rendered pages) all reconciled exactly.
The findings below are the residue: not value errors, but places the package's own recorded
*costs* and *decisions* stop short of the user-facing surface a reader actually consults.

---

## Finding 1 — The default warm-up path's largest memory cost is undisclosed where a user would read it

- **Type:** api-gap
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - ARCHITECTURE.md §11, decision 33 (episode ledger): "the velocity-derivative skewness
    ``\approx 19.6`` — the dominant episode, about half again the default resident set, and on by
    default in `warmup!`'s skewness gate: the binding device peak of a default warm-up at the
    largest fitting ``N``."
  - `api / SimulationRun` page, `StationarityCriterion`: `StationarityCriterion(; gate_scalar =
    true, gate_skewness = true, …)` — `gate_skewness` defaults `true` (confirmed in
    `src/SimulationRun.jl:565`).
  - `Home` page quick-start: `warmup!(sim)` — called with no keywords, i.e. with the default
    `gate_skewness = true`.
  - `api / Observables` page, `derivative_skewness`: documents only that the strain "allocates its
    per-call tensor scratch" — no size, no comparison to the resident working set.
- **Contradicts:** invariant 4 (CLAUDE.md / ARCHITECTURE §9): "minimal memory footprint trumps
  compute cost" and "prefer... per-call allocation of an occasional diagnostic over resident
  scratch" — a claim that only holds if the occasional allocation stays small relative to what it
  is traded against.
- **Description:** The package's own audit (decision 33) names the skewness diagnostic's per-call
  tensor scratch as the single largest peak-memory episode the suite has measured — roughly 1.5×
  the *entire resident working set* of a run — and flags that it fires by default because
  `gate_skewness = true` and `warmup!` is the documented, quick-start way to spin up a case. Neither
  `StationarityCriterion`'s docstring nor `derivative_skewness`'s own docstring (the two surfaces a
  user would actually read before calling `warmup!(sim)` at a memory-constrained grid size)
  mentions this cost or points to `gate_skewness = false` as the mitigation the decision log itself
  names. A user memory-budgeting a GPU run from the rendered docs alone has no way to learn that the
  default warm-up call can nearly double their peak memory footprint.

## Finding 2 — The default forcing's host-device sync cost is undisclosed in its own docstring

- **Type:** api-gap
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - ARCHITECTURE.md §11, decision 35: "the default configuration issues **three** blocking
    readbacks per step — the CFL speed bound, and `BandRescaling`'s band and whole-field
    observables — against a floor of **one**."
  - `api / Forcing` page, `BandRescaling`: the full docstring (arguments, `over`, the empty-band
    caveat, the Berendsen-thermostat caveat) never mentions a device-to-host transfer or
    synchronization cost.
  - `api / SimulationRun` page, `Simulation`: `velocity_forcing` "defaults to a `BandRescaling`
    holding the total (whole-field) energy... (`over = :total`)" — i.e. `BandRescaling` is the
    out-of-the-box forcing every `Simulation()` call gets.
- **Contradicts:** invariant 4's "GPU-first" framing and §6's "GPU-first, allocation-free discipline
  ... is load-bearing" — a hidden pipeline-draining synchronization on the *default* path cuts
  against the package's own stated GPU-primary posture.
- **Description:** Decision 35 names `BandRescaling`'s per-step energy measurement as two of the
  three blocking host readbacks a default run pays (against a floor of one, the CFL bound alone).
  `BandRescaling` is not an opt-in strategy the docs might reasonably leave uncaveated — it is the
  velocity-forcing default of the `Simulation` front door, the entry point the Home page's
  quick-start uses. Its rendered docstring documents the physical trade-off (which quantity is
  clamped, the Berendsen-limit caveat) at length but says nothing about the two extra
  pipeline-stalling scalar readbacks it costs every step, a cost the package's own optimality audit
  treats as significant enough to name and hold against a floor.

## Finding 3 — The audited-footprint claim in current-state prose is unexplained without the historical log

- **Type:** organization
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - `architecture` page §9 (Invariants): "Allocation-free stepping over a compile-time state — with
    an audited footprint."
  - `architecture` page §6 (Precision and footprint as studied axes): "the working point is chosen
    by direct fitness test, never decreed" — no mention of what performs the test.
  - CLAUDE.md, "Verification workflow": "the suite includes three audits over the shared op model in
    `test/audit_ops.jl`... `test/memory_audit.jl` and `test/compute_audit.jl` measure... while
    `test/optimality_audit.jl` bounds."
- **Description:** §9's "audited footprint" and §6's "fitness test" phrasing are the *only* places
  in the current-state sections (§1–§10, the part the doc policy holds to the "current & complete"
  and "self-contained... cold read" tests) that gesture at the three-instrument audit apparatus
  (memory / compute / optimality ledgers, the holder register, the five-axis combination sweep)
  that decisions 33–37, 40, 44–45 build up at length. A cold reader of §1–§10 alone — without
  descending into the append-only §11 log, which the doc policy explicitly does not hold to the
  same currency bar — cannot tell what "audited" means, how footprint is bounded rather than merely
  measured, or that a named-holder discipline exists. CLAUDE.md's own "Verification workflow"
  section names the three files by name; ARCHITECTURE's current-state prose does not, even in the
  section (§6) whose entire subject is exactly this footprint/fitness claim.

## Finding 4 — Two differently-membered register counts are both stated as "two" for `IFLowStorageRK3`

- **Type:** clarity
- **Severity:** nit
- **Confidence:** low
- **Locations:**
  - `api / Propagator` page, `IFLowStorageRK3`: "in Williamson's 2N-storage count... two field
    registers per field: the state's own array plus one accumulator (`stage1`)."
  - `architecture` page §4.5: "three spectral registers per field against the low-storage scheme's
    two, counting the same way on both sides: the scheme's own registers plus the dealiasing seam's
    assembly register."
- **Contradicts:** each other on what the "two" registers *are* — the first is {state, `stage1`}
  (excluding `nonlinear`, the assembly register, which the same docstring explicitly says is *not*
  in that count); the second is {`stage1`, `nonlinear`} (excluding the state array, since it
  compares "the scheme's own registers plus the assembly register" against `IFRK2`'s {`stage1`,
  `stage2`, `velocity_predictor_spectral`}, none of which is the state either).
- **Description:** Both counts are numerically 2 and, worked through against `IntegratorBuffers`'
  actual field list (`stage1`, `nonlinear` for RK3), are mutually consistent under careful reading —
  this is not a value error, and the RK3 docstring is explicit that its "2" is the classical
  Williamson count rather than what `IntegratorBuffers` allocates. But the corpus reuses the phrase
  "two registers per field" for two different set memberships without a shared disambiguating term
  (the `notation.md` glossary's "register" entry does not distinguish the two conventions), so a
  reader who takes either sentence alone at face value and tries to reconcile it with the six-vs-four
  spectral-field count in `observables_cache.md` §1.4 has to do the reconciliation I did above by
  hand.
