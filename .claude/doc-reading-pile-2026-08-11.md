# Doc-reading pile — user read-through, started 2026-08-11 (Enteropia)

## STATUS 2026-08-14: IMPLEMENTED (user: "fix/refactor/implement what we have so far")

All findings and both refactors landed, commits a44b60c → (this pass):
- a44b60c — PF pin bump (the decision-64 preserving arity arrives).
- 66748ff — R1 = decision 46 (include order State → Observables → Cache; max_speed generic home flip).
- 89a0d48 — R2 = decision 47 (chart recoveries → PF's scratch arity; vorticity_physical! in
  Observables; State keeps state + seeders). Findings 3, 7, 8 (module surfaces), 9 folded in.
- 3d6ff88 — finding 4a (FixedDomain all-keyword) + 4b (no-defaults narration deleted, FlowConditions
  twin included).
- (wording commit) — findings 1 (cache one-liner formula: "stamped storage … fills at its end …
  checked accessors serve or throw" across index/api/api-Cache/ARCH §4/module comments), 2
  (observables enumerations → classes+examples on index/api.md; CLAUDE.md done in R1/R2 pass;
  ARCH §4.3 gains the vorticity bullet), 5 ("never materialized" ×3), 6 (opt-in clause dropped
  from HouLi AND PhaseShift — class ruling applied to both; flag to user), 8 (ARCH §4.2 "inert"
  dropped; decision-log §11 instances left as historical record).

BOTH OPEN ITEMS RULED AND CLOSED (user, 2026-08-14: "1 yes, drop everywhere. 2. Do the global
rename."):
- The opt-in clause is dropped everywhere (confirmed: zero instances remain).
- The global rename LANDED as decision 48 (commit 8bc7a5e + polish c036d94, ~200 sites): "closing
  deposit" for the deposit! that ends an iteration; "between iterations" / "the iteration's end" /
  "the instant t_n" for the instant; "deposited X" for the cache values; check_boundary →
  check_deposits; _tail_deposit/tail → _closing_deposit/closing. Different senses kept: spatial box
  boundary, ownership/kernel-granularity boundaries, the spectrum's κ² tail, the phase-shift
  chain's final convolve. The decision log swept to the current vocabulary; decision 48 records the
  history.

THE PILE IS FULLY DISCHARGED.

---

Original pile below, kept for the record.

The user is reading the rendered documentation and reporting problems. **Accumulate only — no
fixes until the read-through is done.** Each entry: the user's report (verbatim where short), the
surface it lives on, and — once triaged — the class it samples.

Already fixed before the pile opened (same session, commit 01fdeb4): "spectral differential
operators" → the operators are ordinary; spectral is the field's representation. Class: the
representation attached to the wrong noun (sibling of the banned "spectral field").

---

## Findings

### 1. The Cache one-liner (screenshot: `docs/src/index.md:90–91`) — three terms unclear

The rendered sentence: "`Cache`: the `ObservablesCache` — the stamped boundary storage each
iteration deposits its observables into at its tail; a read serves the deposited value or throws,
and nothing is recomputed on a read."

- **(a) "boundary storage"** — user: "we need to think about that term, not very clear." Not a
  standard term; a cold reader cannot tell what boundary is meant (it is the *step boundary* — the
  instant between iterations — not a spatial/domain boundary, which is the natural physics reading
  on a periodic box, where "boundary" is doubly confusing). Candidate direction (to discuss, not
  decided): name the *instant* the values belong to rather than a "boundary" — e.g. storage for the
  observables *of the completed step*, stamped with its time.
- **(b) "at its tail"** — user: "probably iteration end is more clear, unless this is a standard CS
  term." "Tail" is informal here (tail of a loop body is jargon-adjacent, not standard enough to
  lean on); "at the end of the iteration / of each step" reads plainly.
- **(c) "a read serves"** — user: "you need to be more explicit on what is read." The subject is
  elided; say *what* performs the read (the checked accessor functions, e.g. `vorticity(cache)`)
  and *what* is served (the value deposited by the last completed step).

**Class + spread** (the phrase is a house formula repeated near-verbatim; fixing it means fixing
the formula everywhere, and the three sub-terms travel together):
- `docs/src/index.md:90–91` (the screenshot)
- `docs/src/api.md:12`
- `docs/src/api/Cache.md:10`
- `docs/ARCHITECTURE.md:200`
- `src/GBGIsotropicTurbulence.jl:17` (umbrella comment)
- `src/Cache.jl:1` (module comment), `src/Cache.jl:53` (module docstring: "stamped storage …
  deposits, at its tail")
- `src/State.jl:4, :20` ("the boundary storage the recoveries fill"), `src/State.jl:40` ("at its
  tail")
- `src/SimulationRun.jl:166` ("the stamped boundary observables the iteration deposits at its
  tail" — here "boundary" modifies *observables*, a further drift of the same term)
- `CLAUDE.md:35–36` (the module map — update in the same pass)
- Also check `docs/src/observables_cache.md` (the design page) for the same vocabulary.

Note: "stamped" itself was not flagged — but when rewording, verify it survives the cold read too
(stamped *with what*? the step's time/index).


### 2. The Observables one-liner enumerates the full export set (screenshot: `docs/src/index.md:98–100`)

User: "That entry should not be read as list of functions exported, maintaining it in full is
prone to errors. List classes/examples."

The index Components bullet reproduces the *complete* `Observables` export list (all 8 names) in
prose. That duplicates `src/Observables.jl:34–36` with no guard — exactly the staleness class the
doc checklist item 5 names ("a summary that names only a subset of what the code now provides is
stale even if literally true"): the next added observable makes this bullet silently wrong.
Direction per the user: summarize by *classes with examples*, not exhaustively — e.g. the
energy/dissipation-scale diagnostics of flow and scalar, the spectrum-derived quantities, the CFL
`max_speed` — with a couple of representative names, and let the module's own docstring (the map,
which *is* the enumeration's home and is `checkdocs`-adjacent) plus the API page carry the full
set.

**Spread — surfaces that enumerate the full observable set outside its home:**
- `docs/src/index.md:98–100` (the screenshot) — full 8-name backticked list.
- `docs/src/api.md:15` — same 8, spelled in prose ("kinetic energy, dissipation, the
  velocity-derivative skewness, … energy spectrum and integral scale"). **Flagged separately by
  the user** ("Once again, the list is too large to maintain") — the ruling covers the
  prose-spelled variant too, not only backticked name lists.
- `CLAUDE.md:43–44` — the module map, same 8 in prose.
- `docs/ARCHITECTURE.md` §4 module list — check its Observables bullet for the same enumeration.
- **Exempt (enumeration is their job):** the `Observables` module docstring (`src/Observables.jl`,
  the map with a linked one-liner per operation — required by the doc policy), the API page's
  `@docs` blocks, the umbrella's `export` list. The umbrella *comment* map
  (`src/GBGIsotropicTurbulence.jl:22`) already does it right: "(energy, dissipation, skewness, …)"
  — classes/examples with an ellipsis; a model for the fix.
- **Same class, other bullets** (to decide with the user whether the rule extends): the index
  `SimulationRun` bullet enumerates `advance!`/`run!`/`warmup!`/`flow_parameters`/
  `validate_spectrum`; the Cache api.md:12 bullet enumerates the full slot list ("the physical
  velocity, vorticity, and scalar, the maximum velocity component, and, with tracers, the particle
  velocities"). Smaller, stabler sets — but the same unguarded-duplication mechanism.


### 3. "The physical-representation recoveries it consumes live with the State." (`docs/src/api.md:14`)

User: "the sentence is not clear. What are the recoveries? who is 'it'? and what lives with the
State? What does 'live with' mean?"

Four defects in one closing sentence of the Generator bullet:
- **"the recoveries"** — a term of art used with zero binding on this page's Generator bullet. What
  is meant: the operations `velocity_to_physical!` / `vorticity_to_physical!` /
  `scalar_to_physical!` (`src/State.jl:15–16`) that recover the physical-representation fields from
  the spectral state. The cold reader gets a plural noun with no referent — the checklist's
  term-of-art rule ("explained or @ref-linked, not left correct only to a reader who already knows
  the code").
- **"it"** — ambiguous antecedent. The sentence's preceding subject chain is "Generator … the
  `ResolvedGenerator` … the protocol a scheme consumes"; "it" must reach back over all of that to
  the *module/assembly*. Grammatically it can attach to "the protocol" or even "a scheme".
- **"live with"** — colloquial for "are homed in / are defined in (the `State` module)". A
  module-organization fact dressed as prose; say plainly that the functions belong to `State`
  (and are only *used* by the Generator's assembly).
- The whole sentence is an **architecture-rationale leak**: why the recoveries are homed in State
  is ARCHITECTURE §11 decision territory (`architecture.md:1078`: "the recoveries move to State —
  the chart map of the state"). An API overview needs at most a pointer ("the recovery operations
  are documented under State"), not the homing rationale in compressed jargon.

**Spread — the same compressed idiom elsewhere:**
- `src/Generator.jl:31` — "The physical-representation recoveries the assemblies consume …" (check
  the continuation; same vocabulary, presumably with its own binding).
- "recoveries" as unbound plural also opens the State bullets: `docs/src/api.md:11` and
  `docs/src/index.md:88` ("its physical recoveries") — same cold-read question, though there the
  `State` link is adjacent. Decide one binding formula ("the recoveries — the operations that
  recover the physical velocity/vorticity/scalar from the spectral state") and use it at first
  mention per page.
- Related, already piled: `State.jl:4/:20` "the boundary storage the recoveries fill" (finding 1's
  vocabulary intersects this sentence class).
- **Follow-up evidence (2026-08-12):** reading the State module page, the user asked "Why did you
  put Physical-field recovery into the state module? Why aren't those part of Observables?" — the
  homing is asserted on the user-facing surfaces but the reason is nowhere a reader passes. When
  fixing, carry the one-clause reason, *stated by the correct criterion* (below), not just the fact.
- **Refinement (user: "But vorticity_to_physical seems to be an observable"):** the chart-map
  rationale (decision 30's wording) covers `velocity_to_physical!` / `scalar_to_physical!` exactly
  but `vorticity_to_physical!` only loosely — ω is chart∘curl, a *derived* field, and its value IS
  an observable in the cache's own vocabulary (a stamped slot; decision 30's "a derived field's
  values" license). The uniform homing criterion is **what they feed and where**: all three
  physical fields are per-stage inputs of the generator's assembly *inside `step!`* (u×ω, ∇·(uφ)).
  **Corrected under the user's Hamiltonian challenge (2026-08-12):** "measurement reads the
  dynamics, never feeds it" is FALSE as a principle (Koopman/MZ: the generator acts on the
  observable algebra; H generates the flow) and false in-package (`max_speed` sets the adaptive
  Δt; `BandRescaling` holds a measured band energy) — do not use it in any fix. The true line:
  Observables functions are never called inside `step!`; their values steer the loop only
  *between* steps. Nothing hard forbids including Observables before Generator — the recorded
  arrangement rests on design reasons (diagnostics module stays opt-in/non-load-bearing for the
  hot loop, decision 30; buffer-writing plumbing vs stateless reductions), and doc fixes should
  claim no more than that. Two doc consequences at
  fix time: (a) where the homing is asserted, state the inside-the-step input criterion, not the
  chart map alone and not a false no-feedback principle; (b) the **terminological seam** —
  "observables" as ObservablesCache slot vocabulary
  (includes derived *fields*) vs `Observables` the module (reductions only) — is real and should
  be addressed by whatever wording finding 1 settles on ("deposits its observables into" invites
  reading the cache slots as the Observables module's outputs). Consider whether decision 30's
  chart-map sentence itself deserves a précis correction in the log (append-style, not rewrite).


### R1. DECIDED REFACTOR (user, 2026-08-13): Observables move to State → Observables → Cache;
### observables stay simple functions and gain cache methods

Grew out of the finding-3 thread (recoveries homing → "vorticity seems an observable" → the
Hamiltonian challenge → a design discussion). The user first sketched a
`observable(state, cache, compute::Bool)` form; rejected in discussion (flag argument conflating
an O(1) read with an O(N³) measurement; "stored in state" is empty so the nothing-cache semantics
were inconsistent; compute-from-what-is-available reopens the staleness class decision 40 closed).
**The settled design, per the user:**

1. **Include order becomes `… → State → Observables → Cache → Forcing → Generator → …`**
   (today: State → Cache → Forcing → Generator → Observables; `src/GBGIsotropicTurbulence.jl:53–57`).
2. **Observables stay simple functions** computing from field arguments (pure, testable,
   run-independent) — the `(state, cache, Bool)` form is NOT built.
3. **Each observable is one generic with a cache method**: `f(u)` measures now; `f(cache)` serves
   the deposited value or throws (the checked read). Dispatch by argument type is the mode
   selector — no flag, no silent recompute. This generalizes the existing `max_speed` pattern
   and REVERSES its generic's home: today the bare binding `function max_speed end` lives in
   `Cache` (`Cache.jl:184`) because Cache is included first, and Observables does
   `import ..Cache: max_speed` (`Observables.jl:32`); after the move the binding homes in
   `Observables` (the natural home) and `Cache` extends it.

**Implementation notes gathered now:**
- `Cache`'s current accessors: `velocity_physical`, `vorticity_physical`, `scalar_physical`,
  `max_speed`, `particle_velocities` (+ `check_boundary`, `resolved_fields_modified!`,
  `deposit!`…). Which of these become methods of Observables generics is a naming question at
  implementation time — the three physical-field reads correspond to *recoveries* (State), not
  Observables reductions; `particle_velocities` is particle-sourced. The clean immediate
  unification is `max_speed`; the design leaves room for any future cached reduction.
- The recorded guard stands: ``\varepsilon``, ``k``, ``E(\kappa)`` never become resident slots
  (no new cache slots implied by this refactor).
- Consumers to rewire: `Propagator.jl:49` (`using ..Observables: max_speed`), `Cache`'s
  import direction, `Observables.jl:31–32`.
- Doc/record consequences: new ARCHITECTURE §11 decision entry (explicitly supersedes the
  include-order sentence of the umbrella comment, CLAUDE.md's Modules section, ARCHITECTURE §4's
  order statement); the `max_speed(u)/(cache)/(sim)` signature block at `Observables.jl:111–113`
  (NB: a `(sim)` method is listed there — check against the recorded f(sim) drop);
  the "one generic shared with Cache" clauses in both module docstrings.
- Two decisions this touches but does not reverse: no-recompute-on-read (kept — cache methods
  still throw), f(sim) methods (not reintroduced… but see the existing `max_speed(sim)` line).

**Status: decided, NOT implemented — queued behind the read-through like the doc findings.**


### R2. DECIDED REFACTOR (user, 2026-08-13): field-agnostic preserving recovery; vorticity_physical!

Grew out of finding 9's thread (the PF non-destructive-transform request, declined). Per the user:

1. **Replace `velocity_to_physical!` / `scalar_to_physical!` with a field-agnostic preserving
   recovery.** ~~Name open — an IT verb like `recover_physical!`~~ **SUPERSEDED same day (user:
   "if it is field-generic, why isn't it part of PF?"): the general core goes to PF as a
   request** — see the amendment below. IT keeps no chart-recovery verb at all.
2. **`vorticity_to_physical!` → `vorticity_physical!`** — a separate operation (curl∘transform, a
   derived field, needs no preservation copy). Pairs with the existing cache read
   `vorticity_physical(cache)` as a proper f/f! pair under R1's one-generic design (home on `!`).

Verified facts for implementation:
- Two recovery regimes now explicit: consumable source → PF's `to_physical!` bare (strain);
  must-preserve source → the sugar (state, and the Generator's phase-shift chains, where
  `velocity_shifted` is read twice — u then ω — so the copy is load-bearing correctness).
- Call sites to rewire: `Generator.jl:40` (imports), `:297–298`, `:428`, `:432` (phase-shift
  displaced evaluations); umbrella exports (`GBGIsotropicTurbulence.jl:80–82`, `:183–185`);
  `test/dealiasing.jl:91–92`; `test/audit_ops.jl:211` (op-model comment; check the audit op lists
  if names appear in them); find who fills the cache slots at the tail (deposit path) and rewire.
- Doc ripple: decision 30's wording, State/Generator module docstrings, api/State page, notation
  if it names the recoveries; new §11 entry (can share R1's).
- Optional, decide at implementation: `FixedDomain.velocity_plans`/`scalar_plans`/`tensor_plans`
  are physics-named but rank-keyed — under a rank-dispatched recovery the honest storage names
  would be rank names (vector/scalar/tensor plans). Storage rename, low priority.
- Whether a preserving to_spectral twin is needed: NO today (r2c preserves input; no IT call site
  needs it) — do not add for symmetry (invariant 3).

**AMENDMENT (2026-08-13, user-directed): the field-generic core is a PF REQUEST, not an IT verb.**
Expand-check against PF's current exports (verified in the real checkout, `src/Fields.jl`):
- PF already has the **destructive** `to_physical!(physical, spectral, plans)` (invariant-11
  warning: source used as scratch) AND the **preserving-but-allocating** `to_physical(spectral,
  plans)` (copies coefficients + allocates result; docstring names preservation as its reason).
- The missing family member is exactly the **allocation-free preserving arity**:
  `to_physical!(physical, spectral, plans, spectral_scratch)` — copy into caller-supplied
  scratch, transform from scratch. Justification for PF triage: completes an existing family
  (like convolve!'s α/β arities, one docstring), encodes invariant 11's warning as API, explicit
  scratch keeps the copy pass visible; needed by any consumer whose spectral field is a source of
  truth in an allocation-free loop — not IT-specific. No to_spectral twin (r2c preserves).
- Request queue: round-3 candidate alongside the two-output IF stage kernel (per the standing
  PF-request protocol memory). Raise from a PF session. **Request handed to the user 2026-08-13**,
  with one correction after PF pushed back: the no-to_spectral-twin reason is NOT "r2c preserves
  input" (false in general — PF's to_spectral! docstring: rocFFT reserves the right to use r2c
  inputs as scratch; only FFTW guarantees preservation) but the consumer audit: all five IT
  forward-transform call sites (State.jl:139/:205 noise, Forcing.jl:388 noise, Generator.jl:318/
  :458 in-place products over tail-refreshed registers) have consumable sources by design —
  destruction is harmless on every backend.
- **IT endpoint (cleaner than the original R2):** delete `velocity_to_physical!` and
  `scalar_to_physical!` outright; call sites use the PF arity directly with the domain's plans
  (`to_physical!(u, û, domain.velocity_plans, scratch)`). The only surviving IT recovery verb is
  `vorticity_physical!` (physics-named derived-field composition: curl into scratch, transform —
  no copy, no fusion win to raise). Earlier my "PF request DECLINED" note under finding 9 stands
  only for its pre-R2 framing (no named general op wanted); R2 flipped the calculus — invariant 2
  sends a named field-generic operation to PF.
- Until the PF arity ships, the implementation can land with a two-line local composition at the
  call sites (copyto! + to_physical!) or hold the refactor's recovery leg behind the PF round —
  sequencing to decide when the read-through ends.


### 4. `FixedDomain` docstring (`src/SimulationDomain.jl:126–138`) — two findings, one an API change

**(a) Make all arguments named (keyword).** User: "Why only the two of them are named? Make them
all named." Current signature: `FixedDomain(grid_points_per_axis::Integer, side_length::Real;
dealiasing, element_type, array_type)` (`SimulationDomain.jl:186`) — two positional, three
keyword. The user wants the full all-keyword form, matching the `Simulation` front door (which is
already all-keyword: `Simulation(; grid_points_per_axis, side_length = 2π, …)`). **This is a code
change, not a doc edit**: the constructor signature at `SimulationDomain.jl:186`, its docstring
signature at `:127–128`, every call site (test/dealiasing.jl passes `FixedDomain(N, L; …)` many
times; sweep all of test/ and src/SimulationRun.jl's forwarding), and the inner positional
constructor at `:211` (the raw field-order form — presumably stays, it is the `# Fields` plain
constructor). No compatibility shim (API not frozen).

**(b) The "carries no defaults" paragraph narrates a design decision.** User: "reads as
documenting a historic decision, that's very dumb." The paragraph (`SimulationDomain.jl:136–138`)
leads the # Arguments section with where defaults live and what the *other* type's defaults are
(`side_length = 2π`, `TwoThirds()`, `Float64`, `Array`) — architecture rationale (the
defaults-live-only-at-the-front-door decision, commit a3a523c) leaked into a docstring, plus an
unguarded duplicate of `Simulation`'s default values that goes stale if the front door changes
(finding 2's mechanism). The docstring should document the constructor as it is (arguments
required, no defaults — each bullet already reads fine); pointing at `Simulation` as the
convenience form is at most one neutral clause, with the default *values* stated only at their
home (`Simulation`'s docstring).

**Spread of (b) — the same narration formula:**
- `src/Generator.jl:57–59` — "Every argument is explicit — `FlowConditions` carries no defaults;
  the `Simulation` front door supplies the run-layer values (`schmidt = 1.0`, a stationary
  `BandRescaling` velocity forcing, and `NoForcing()` for the scalar)." Same formula, same
  duplicated-defaults staleness risk.
- Sweep for softer variants of decision-narration in docstrings while fixing ("the front door
  builds one for you" at `Cache.jl:65` / `Generator.jl:154` is *usage* guidance, probably fine;
  the class to kill is narrating the *decision* and duplicating another surface's values).

User register note: "I hope I will not encounter such blunders again" — treat decision-narration
in docstrings as a named blunder class going forward; check candidate docstrings against it
before shipping.


### 5. "resident in no array" (`src/SimulationDomain.jl:165`, the `squared_wavenumber_kernel` field bullet)

User: "is it jargon or term?" Verdict: "resident" alone is a real systems term and the package's
own audit vocabulary; **"resident in no array" is a house coinage** — a negated inversion that is
not standard anywhere. Replace with the standard statement: *never materialized* — no array is
allocated, each value computed per mode on demand (from the axis multipliers).

**Spread (the exact phrase):**
- `src/SimulationDomain.jl:165` — the flagged docstring bullet.
- `src/SimulationDomain.jl:3` — the module `#` comment ("compressed symbols, resident in no
  array; decision 38"). A comment, not rendered — fix for consistency while at it.
- `docs/ARCHITECTURE.md:183` (→ architecture.md) — the same formula in the §2/§4 map.

Plain "resident"/"residency" elsewhere (Forcing.jl:349, observables_cache.md, ARCHITECTURE's
audit sections) is the audit term used normally — keep.


### 6. HouLi docstring: drop "hence an opt-in, not the default" (`src/SimulationDomain.jl:74`)

User: "For HouLi drop 'hence an opt-in, not the default'". The clause sits after "…only *damps*
aliasing rather than removing it exactly — a stabilization"; the deletion leaves "— a
stabilization." and the sentence stands. Same decision-narration family as finding 4(b): which
strategy is the default is the front door's fact, not this type's.

**Same clause, parallel instance (to decide at fix time whether the ruling extends):**
`src/SimulationDomain.jl:108` — the PhaseShift docstring's standalone sentence "Opt-in, not the
default." The user flagged only HouLi; PhaseShift's version follows a *cost* statement ("worth
the price: a second transform per stage…"), where the clause arguably carries when-to-use weight
rather than default-narration. Ask or judge in context at fix time.


### 7. State module docstring: "never held here" → "never held in the state" (`src/State.jl:13–14`)

User-supplied exact replacement. The defect class is **deixis**: "here" points at the docstring's
own module, which a reader inside the rendered bullet cannot resolve without stepping back out —
the ResolvedFields bullet is about the *state*, so name it.

**Class probe — other deictic "here/there" in rendered docstrings** (screen at fix time; not all
are defects — some have a clear in-sentence antecedent):
- `src/State.jl:3` — the module comment repeats the same "never held here" (non-rendered; align).
- `src/Observables.jl:17` — "the field reduction is homed here, the cached read there"
  (here=Observables, there=Cache — the pairing gives antecedents, but same cold-read strain).
- `src/Propagator.jl:175` — "the scheme here, the cache there" (parallel construction, likely OK).
- `src/Forcing.jl:64` — "prepared here" (check context).
- `src/Phenomenology.jl:19` — "here)" (check context).


### 8. "inert record" (`src/State.jl:37`, the `ResolvedFields` docstring opening; also `:12`)

User: "is that standard CS terminology?" Verdict: **no** — "record" is standard, "inert" is a
house metaphor that leaked from an ARCHITECTURE panel ruling (`ARCHITECTURE.md:1004`: "a bare,
inert record with every operation external") into the user-facing docstrings. The standard term
for the concept is **passive data structure** — data, no behavior, every operation external; or
say it plainly ("holds the fields and does nothing else; every operation is an external
function"). Package-specific hazard: "inert" collides visually with the ubiquitous "inertial"
(range, particles) in surrounding turbulence prose.

**Spread ("inert record" / "inert"):**
- `src/State.jl:37` — the `ResolvedFields` type docstring opening (the flagged sentence).
- `src/State.jl:12` — the State module docstring bullet ("the inert record of the evolving
  velocity and scalar…", the same bullet as finding 7).
- `docs/ARCHITECTURE.md:191` — "`ResolvedFields` is the inert…" (§4 map).
- `docs/ARCHITECTURE.md:1004` — the origin (decision-log prose; internal, may keep its own voice —
  decide at fix time whether the ruling reaches the decision log).
- Same coinage class as finding 5 ("resident in no array").


### 9. The recovery docstrings never state their reason to exist vs PF's `to_physical!`
### (`src/State.jl:58–100`)

User asked: "Why do we need velocity_to_physical! and scalar_to_physical!? Why can't we use PF
generics to_physical?" — answered in session (the wrappers are thin over PF's `to_physical!`; they
exist to (1) centralize the preservation copy — the c2r transform consumes its spectral source,
and û/φ̂ are the single source of truth, so the copy-first discipline must not be distributed over
call sites; (2) fold curl∘transform into one named operation for the vorticity, keeping the
three-recovery family uniform; (3) bind the domain's right plan set and name the physics). The
question is evidence of the gap: each recovery docstring's "when to use vs alternatives" slot
(policy element 2) is silent on the raw PF alternative — "(left unchanged)" hints at the contract
without stating why the wrapper exists. At fix time add one clause per docstring (or one shared
sentence in the State module docstring) naming `to_physical!` and the preservation reason.

**Follow-up (2026-08-13): a PF request for non-destructive to_physical!/to_spectral! was
considered and DECLINED.** to_spectral! is already non-destructive (r2c preserves input by
default on FFTW and cuFFT); a preserving c2r is impossible at the library level (FFTW:
PRESERVE_INPUT unsupported for multi-dim c2r; cuFFT: out-of-place C2R always overwrites input),
so a PF variant could only be copy+transform sugar with the same explicit-scratch signature IT's
wrappers already have — "convenient" is not a valid raise. Consequence for the fix: state the
destructive-source contract as a *backend-library fact*, not a package choice — it answers both
"why the wrapper" and "why not ask PF" in one clause.
