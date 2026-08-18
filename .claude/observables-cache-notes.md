# `docs/src/observables_cache.md` — user notes

Accumulating; do not act until told.

## Round 2 (reading the rewritten page)

R2-1. §"What it is for", line 11 — *"Some are fields in either representation, some are values at
   particle positions, and some are single numbers."* The bare "Some" reaches back past the previous
   clause for its antecedent. Write **"Some observables are fields in either …"**.

R2-2. §"What it is for", lines 29–30 — *"It strictly contains the **step**, which advances
   ``(\hat{\boldsymbol{u}}, \hat\varphi)`` and is itself divided into the **stages** …"* The second
   relative clause needs its own relative pronoun: **"which advances … and which is itself divided
   into the stages of the time scheme"** — otherwise "and is itself divided" reads as coordinated with
   "contains", attaching to the iteration rather than the step.

R2-3. §"What it is for", line 31 — *"Every rule below follows from one design choice"*: "rule" appears
   here for the first time with no referent — say what body of rules is meant, e.g. **"Every rule of
   the cache architecture below follows from one design choice"**.

R2-4. Throughout — **"raises" is Python idiom; Julia *throws*** (`throw`, `rethrow`; the manual's word
   is "thrown"). Sweep every "raise"/"raises" to "throw"/"throws" — including "otherwise it raises",
   "a stale or unstamped read raises", "makes that read raise", and any others. Also sweep the memory
   file and the eventual ARCHITECTURE entry when written.

R2-5. **DESIGN CHANGE (user-driven): the numbers move to the tail — one deposit point for
   everything.** The §2 "Numbers follow the same rule on a different schedule" paragraph documented
   the current `_run_loop!` head measurement (`SimulationRun.jl:383-387`: ε → stop → `cfl_timestep` →
   `advance!`) as if it were the design; the user asked why the numbers can't be computed at the end
   of the iteration like the fields — and nothing blocks it:
   - Tail of iteration ``n`` and head of iteration ``n+1`` see the identical state, so the max speed /
     ``\varepsilon`` / ``k`` deposited at the tail are exactly what the next iteration's CFL control,
     turnover clock, and stopping test need — the control *reads* instead of measuring.
   - The first head reads the mandatory ``t_0`` seed deposit (same seed as the fields').
   - The tail max-speed reduction reads the just-deposited physical ``\boldsymbol u`` chart — same one
     pass as today.
   - Price: one unconsumed measurement at the final tail — the same n+1-deposits-for-n-uses
     arithmetic as the fields, one reduction per run.
   Result: the asymmetry disappears — **one rule: everything declared deposits at the tail, from the
   new state, stamped ``t_{n+1}``** — and the numbers are current at every callback instead of
   throwing there. The paragraph reduces to "numbers follow the same rule", full stop.
   **Wrinkle first settled as option (i) (numbers join the construction-time declaration; `run!`
   validates at entry), then SUPERSEDED by R2-6 — under which it dissolves entirely.**

R2-6. **DESIGN CHANGE (user's, bigger): the stopping condition moves out of `run!` into the
   callback — the user stops the iteration.** `SimulationRun` will be redesigned accordingly; the
   cache design must reflect it now. Consequences (confirmed with user):
   - **The iteration is closed**: everything it computes is a function of configuration + state at
     ``t_n`` — no run-global knowledge (when to stop, budget denomination) enters it. The schedule is
     literally a constant of construction.
   - **`run!` loses its stopping vocabulary** (`turnovers | time | steps | stop` as loop-internal
     consumers). The loop is measure → step → deposit → callback; the callback's return decides
     whether to continue.
   - **Solver-internal numbers shrink to one**: only the CFL's max speed remains a component need
     (known at construction). ``\varepsilon`` / ``k`` become ordinary declared observables; the
     turnover clock (accumulating ``\Delta t/\tau``) moves into the user's callback, reading cached
     ``\varepsilon`` at each boundary.
   - **Validation collapses to one moment — construction only** (producers vs declaration + the
     CFL's `:max_speed`). No second moment at which a consumer appears; a callback reading an
     undeclared observable hits the standard undeclared-read throw. R2-5's run!-entry validation is
     gone because the thing it validated is gone.
   - **The callback fires at every boundary** (required for stopping; converges with the adopted
     ``n+1``-boundaries contract). A coarser output cadence is the callback's own business or a
     convenience layer — to be decided in the SimulationRun redesign.
   - ~~Named cost: a turnover-budgeted study must declare `:dissipation` at construction~~ —
     **WRONG, user-corrected (R2-8): ε/k leave the declarable vocabulary entirely.** With stopping
     and the turnover clock in the callback, no component of the iteration computes them (CFL needs
     only the max speed; forcing's band-energy reductions are stage-internal and consumed inside the
     step; tracers need the interpolated velocity) — so criterion (b) excludes them. Declaring
     `:dissipation` is a constructor error ("nothing produces it"), never a way to order a
     computation. The user computes ε/k in their own callback — one reduction, from the cached
     `:vorticity` chart or the state via the exported reductions.
   - Combined with R2-5's tail move: **one deposit point (the tail, from the new state, stamped
     ``t_{n+1}``), one validation moment (construction), one consumer discipline (declared reads at
     boundaries)** — the "Numbers follow the same rule on a different schedule" paragraph and its
     head/tail asymmetry disappear from the page.

R2-7. **DESIGN CHANGE (user's): callback-first loop ordering.** The loop body is
   `callback (observe t_n: record statistics, evaluate stop) → break? → Δt from cached max speed →
   advance! (step + tail deposits, stamp t_{n+1})`. NOTE: there is no "measure" phase at the head —
   under R2-5 the max speed at ``t_n`` was deposited at the previous tail, so choosing ``\Delta t``
   is scalar arithmetic on a cached number, not a grid pass (my earlier "measure → step → deposit →
   callback" sketch was stale head-schedule residue). Why callback-first wins:
   - ``t_0`` observed for free — the first pass reads the seed deposit; no special pre-loop callback.
   - Every reached boundary observed exactly once, INCLUDING the last (statistics recorded before the
     break). The ``n+1``-boundaries contract becomes structural, not contractual.
   - Body reads observation → decision → advance (the MZ framing: callback = observation of the
     state at ``t_n``, stop = decision on observables, step = dynamics).
   The callback both records and decides: it writes down the statistics of the state first, then
   evaluates the break condition, and its return controls continuation.

R2-8. **THE PRINCIPLE, user's words (sharpens R2-5/R2-6): "if the iteration does not compute/store
   something, one cannot ask it to cache this."** The declaration *selects among* what the iteration
   already computes; it can never *extend* it. The cache is a window onto the iteration's own
   products — never an order form for new computation. Numbers in the declarable vocabulary are
   therefore exactly the numbers the iteration computes: `:max_speed` (the CFL's need) and nothing
   else today. The future extended access stays consistent: unfusing materializes a value the
   iteration computes but fuses away — it changes what is *stored*, never what is *computed*.

R2-16. **Cache residence (2026-08-05, SETTLED — user adopted the recommendation): own module
   **`Cache`**, included between `State` and `Forcing`.** Today the type lives in `State` (recorded module map). Under the new
   design the cache spans every producer (state recoveries, generator displaced registers, particle
   sample, run-layer max speed) — no longer state-derived-only — and its machinery shrank to stamps
   + deposit/completeness bookkeeping + accessors + `resolved_fields_modified!` + seed (no-recompute
   ⇒ it never calls a recovery; deps = PF field types only). Module name by the established
   pattern (module = concern, type = reification; SimulationDomain/FixedDomain, Generator/
   ResolvedGenerator): module **`Cache`**, type `ObservablesCache` (settled name). Slots hold
   arrays, not owner types — wiring at Simulation assembly. If adopted: update CLAUDE.md +
   ARCHITECTURE §4 module maps, include order, and record residence in the §11 storage-decision
   entry (unwritten).

R2-15. **UNIFORM READ SURFACE (user, 2026-08-05; my concurrence): one family of functions on `sim`
   covering everything the run HOLDS, state/cache split invisible.** `velocity_spectral(sim)`,
   `velocity_physical(sim)`, `scalar_spectral(sim)`, `scalar_physical(sim)`,
   `particle_positions(sim)`, `particle_velocities(sim)` (the trajectory sample),
   `vorticity_physical(sim)`, `max_speed(sim)`. Rationale: which fields are "the state" (spectral,
   velocity-not-vorticity) is a Method decision, not physics — reads must not leak it; reading needs
   no architecture, WRITING does (mutation via dot + `resolved_fields_modified!` — the dangerous act
   demands the knowledge); the line generalizes to *functions = public read surface, dot =
   internals*. EDGE that keeps no-recompute honest: an accessor exists exactly for what the run
   holds (state ∪ cache) — `vorticity_spectral(sim)` does NOT exist (ω̂ materialized nowhere;
   MethodError = "build it yourself"). **SETTLED (user): the accessor prefix is `particle_`** —
   `particle_positions(sim)`, `particle_velocities(sim)`; `tracer_velocities` is renamed at the
   refactor (the `Tracers` type name is a separate question, untouched by this decision).

R2-14. **Sim-level accessors (2026-08-05): yes, as thin forwarders.** `velocity_physical(sim)`
   forwards to `velocity_physical(cache)` — the cache method is the home (docstring, stamp contract,
   throws; components are handed the cache, not sim — include-order layering). Roles of the sim
   method: the user's ontology (callbacks receive sim; automatic contents mean the user never holds
   a bare cache; name the run, not the machinery path) + insulation across refactors. One generic,
   one docstring home, forwarder @ref-links it. Boundaries: forwarders ONLY for cached observables
   (`dissipation(sim)` must NOT exist — MethodError is the right message, distinct from stale-stamp
   throw); dot path stays raw storage (`sim.state.velocity` = û unchecked). OPEN (I lean yes): the
   cached number under the same generic as the Observables reduction — `max_speed(u)` computes,
   `max_speed(sim)` reads the stamped value; uniform "apply the name to what holds it", docstring
   carries the compute-vs-read split.

R2-13. **API DECISIONS (user, 2026-08-05) for the cache accessors at the refactor:**
   - **Function form, not property access**: `velocity_physical(cache)` — the syntax carries the
     semantics (a checked read that can throw is a function; dot-access stays raw storage), one
     idiom with the package's observable verbs, docstring/@ref homes per accessor, type-stable
     without constant propagation, first-class. No `getproperty` overload, no symbol indexing.
     Signature collapses to the cache alone (no-recompute ⇒ no state/domain args).
   - **Noun first, representation qualifier trailing**: `velocity_physical`, `vorticity_physical`,
     (`scalar_physical`) — NOT `physical_velocity`. PF's `VectorFieldPhysical` order; IT's own
     storage slots (`buffers.vorticity_physical`, `product_spectral`, `velocity_shifted`) and verbs
     (`velocity_to_physical!`) already follow it; the current exported accessors are the package's
     only adjective-first names. First principles: the object is primary, the representation is how
     it is held — the naming mirror of physical-meaning-first. Rename at the refactor (exports,
     docstrings, error messages, the page's §3.1 call list).

R2-12. **USER IDEA (2026-08-05, future — downstream of the cache + Particles strands): BCC tracer
   interpolation from the cached displaced fields.** Under PhaseShift the displaced recoveries exist
   for ALL fields (φ̂ and ω̂ are shifted too — `scalar_shifted`/`phi_shifted`,
   `omega_shifted`), so the boundary cache holds u, ω, φ on BOTH grids. The union
   primary ∪ cell-center = a **BCC lattice** — the optimal sampling lattice for isotropically
   band-limited 3-D fields (ours are, spherically truncated at √2N/3) — so a two-grid tracer
   interpolant (box-spline family on BCC) is the right stencil, not just double data; both Heun
   samples sit at boundary states, when both charts are stamped. Caveats recorded: the interpolant
   is new machinery (data free, stencil not); accuracy becomes configuration-dependent (trajectories
   would differ between dealiasing configs through the stencil — must be documented loudly);
   PhaseShift-only by construction. **User: this is PF's — interpolation is field mathematics.
   Raise it there (task #45), after expanding against PF's current sampling exports.**

R2-11. **USER INSIGHT (2026-08-05): `u_shifted` at a boundary is a genuine observable — and the
   automatic contents cache it with no decision.** ``u_{\text{shifted}}(x) = u(x+\delta)``: the same
   physical field, spectrally exactly resampled on the half-cell-displaced grid; the translation
   kernel is a frame constant ⇒ passes the kind test. The stage-1 build is at a true boundary state;
   stage-2/3 builds are displaced STAGE VALUES (not observables, correctly uncacheable). Under the
   tail relocation + automatic contents, boundary `u_shifted` (and displaced φ, ω) are cached under
   the PhaseShift configuration — table rows absent from the page only because §2.4 is scoped to the
   mask configuration ("contents are a property of the configuration", another instance).
   **Decomposes #44's 9 c2r:** 3 (stage 1) dissolve into the cache strand for free — at the tail the
   two displaced evaluations sit adjacent in one relocated boundary assembly, no verb boundary
   between them; 6 (stages 2,3) remain the real protocol problem (one displaced recovery per stage
   passed by argument, or a stage-granular stamp on the scratch).

R2-10. **DESIGN DECISION (user's, 2026-08-05): `warmup!` loses its separate infrastructure.** With
   stopping on the user, warm-up is a run whose callback detects stationarity and says stop.
   VERIFIED against src: `warmup!` is literally `_run_loop!` + a `stop` closure over
   `StationarityMonitor` (`SimulationRun.jl:548-563`); it touches no state/forcing/IC. The
   observables stay in `Observables` unchanged (`derivative_skewness` — the gradient stopping
   criterion — `scalar_variance`, `dissipation`); the callback calls them, paying the skewness's
   three inverse transforms at its own cadence. OPEN (my recommendation: ship): whether the
   stationarity criterion (window + plateau + skew floor + turnover guards) survives as a packaged
   callback handed to `run!` (packaged researched judgment: ε not k, cadence, floor) or becomes a
   docs example; `warmup!` itself stays as one-line sugar or dies. Feeds task #42.

R2-9. **DESIGN DECISION (user's, supersedes the declaration entirely — the starting design): FULLY
   AUTOMATIC CONTENTS.** The cache holds exactly what survives the minimal-memory schedule; zero
   user acts; contents shift with solver versions. Other options (a survival declaration pinning
   contents) may follow, but much later. Consequences:
   - **No `observables =` keyword, no declaration, no construction-time validation** — there is
     nothing to validate; the constructor *derives* the cached set from the configuration. The
     round-1 "validate the declared vocabulary at construction" item is superseded.
   - **The cache adds zero memory by construction.** Every slot IS a register the iteration needs
     anyway, stamped. The design choice strengthens: caching adds nothing to what an iteration
     computes, moves, *or stores*. §3's three-level cost table collapses — there is no cost, ever;
     the round-1 "report the added residency" item is superseded (what remains worth reporting at
     construction is the *contents* — which observables this configuration caches).
   - **The undeclared-read throw becomes a not-in-this-configuration's-cache throw** (same mechanism,
     different message). A callback wanting anything else computes it themselves with the exported
     recoveries/reductions.
   - **Solver memory optimizations win by default**: landing Lamb-into-vorticity removes
     `:vorticity` from the cache — correct under this rule, documented as version-dependent contents.
   - **Deposit-completeness stays**, now as an internal invariant (every slot in the surviving set is
     stamped at every boundary — a solver-bug check, not a user error).

---

## Round 1

1. §"What it is for", line 6 — *"The two of them at one instant make up the **state**"*: say **instant
   of time** here, on first use, so the bare "instant" later in the document reads unambiguously.

2. §"What it is for", lines 7–8 — *"A run has the state at ``t_0``, then at ``t_1``, and so on through
   the discrete times where its steps begin and end; between those times it has no state."* Replace
   with the enumerated form, e.g. *"A run has the state at discrete times ``t_0, t_1, t_2, \ldots,
   t_n, \ldots``, and between those times the run has no state."*

3. §"What it is for", line 10 — *"a function of the state at one ``t_n``, and therefore rebuildable
   from it exactly"*: name the antecedent — **rebuildable from the state exactly** — rather than the
   pronoun.

4. §"What it is for", line 21 — *"where a component puts a value another will read"*: spell out the
   noun — **a value another component will read**.

5. §"What it is for", line 28 — **"moves" is never bound.** Define it at first use: *moves* = memory
   traffic, the bytes read and written; *computes* = the arithmetic on them. Say why that pair is the
   right one (bandwidth-bound on GPU: a pointwise multiply is ~10 flops per point against 24 bytes).
   A **pass over the grid** is one traversal touching every grid point once.

6. Same paragraph — say explicitly that the design choice bounds **time only** (arithmetic + traffic),
   and that **footprint is the axis it deliberately does not bound**, forwarding to §3. Right now §3
   asserts "a memory decision and never a time decision" without the design choice having said which
   axis it governs.

7. §1 — **"fixed" is used in two senses**, three lines apart: *determined by* (the question, "fixed by
   the state at a single ``t_n``") and *belongs to a time* (the bullet header, "fixed at another
   instant"). Use **determined by** for the first.

8. §1 — **LOGICAL ERROR, the user's: the two bullets are not two ways.** The second is a special case
   of the first (an RK stage value carries ``\Delta t``, so it fails the first test), and the sentence
   after them — *"A quantity failing the second test fails the first as well … where both apply, this
   page names the second"* — is me noticing the overlap and papering over it instead of deleting it.
   Collapse to **one test**: is the quantity determined by the state at a single ``t_n``? Then mention
   the discretization artifacts **in passing** (an RK stage value is the flow at no time; the velocity
   at a predicted tracer position is the probe's observable at no instant) as the obvious near-miss a
   reader will ask about — not as a second criterion. User: *"It is quite obvious that RK stages are
   not physical, you can note that in the passing, but it is not an excuse to make logical errors."*

9. §1, line 61 — *"**May the cache hold it?** Two tests apply the design choice above."* **Restate the
   design choice here rather than pointing back at it** — as written, "the design choice above" is
   read as the material just discussed (the observable test and its bullets), so the reader tries to
   see how *those* are a design choice. Name it: the two tests are what *caching adds nothing to what
   a cycle computes or moves* means, one test per half of that pair (arithmetic / traffic — see 5).

10. **Throughout — replace the coined *cycle* with *iteration*.** The distinction it draws is real:
    the loop body (choose ``\Delta t`` from the max speed → `advance!` → stopping-test reductions →
    callback) strictly contains `step!`, and two of the velocity's three readers (the CFL, the
    tracers) sit outside `step!`, so the accounting cannot be stated in terms of "step". But
    *iteration* is the standard name for a time-marching loop body (Fluidsim's `it_computed`,
    Dedalus's iteration counter, cost-per-iteration in the DNS literature), and no iterative solver
    exists here to make it ambiguous. Result: **stage** ⊂ **step** (`step!`) ⊂ **iteration**, three
    standard words, no coinage. Sweep every occurrence of "cycle" (including "end-of-cycle",
    "mid-cycle", "a cycle's cost", "the cycle writes").
    **User confirmed: "Yes, definitely use iteration."**

11. §1, line 63 — *"The cache is written from the cycle, not from a read"*: **"a read" is bare jargon
    used as a noun and never introduced**, and the sentence names neither party in the contrast it
    draws. Say it in full: the iteration fills the cache as it produces the values, rather than the
    cache being built on demand the first time a consumer asks for one. Sweep the same noun elsewhere
    ("a read repairs a stale value", "a mid-cycle read is refused", "what a read builds", "buys a read
    at ``t_n``") — each needs the actor named.

12. §2 heading — **"The currency contract" misleads.** It reads first as a price unit; the intended
    pun on *current* never lands because neither "current" nor "currency" appears anywhere in the
    section. Rename to something plain — **"When a cached value is valid"** (or "Validity"). Drop
    "contract" as well: software-engineering register, not physics. Also check §6's "outside the
    contract of §2" and any other back-reference to the old name.

---

## Design change (NOT a wording note) — user, round 1

**Throw on stamp mismatch; do not repair.** Repair-on-read makes the cache an instrument that cannot
fail: a mis-scheduled consumer silently doubles a recovery while the frozen compute ledger, which
freezes the *intended* schedule, still reads clean. Same shape as decision 37. Throwing makes the
transform ledger enforceable at runtime, and matches the discipline one level up (an undeclared
observable already errors rather than silently allocating).

**Writer owns the slot — ownership = responsibility for the stamp, not exclusive access.**

- One owner per slot: the component that produces the observable; it must leave a correct value and
  stamp at the boundary.
- Any component may take the array as scratch mid-iteration, but **taking it clears the stamp**. This
  is what makes the user's Lamb-vector-into-the-vorticity-slot legal: while the slot holds the Lamb
  vector it is stamped as holding nothing, so a read throws instead of returning a mislabelled field.
- Borrowing a foreign slot is allowed and correctly priced — the owner must recover again to deposit,
  and that inverse transform lands in the ledger.

**The stamp becomes three-valued:** holds the observable at ``t_n`` / in use as scratch / never
deposited. The mid-iteration refusal stops being a nicety and becomes the only thing between a reader
and a scratch array.

**Consequences to take on deliberately:**

- **Validate the declared vocabulary at construction.** Declaring `:scalar` in a velocity-only run
  means nothing ever deposits and every read throws — must be a constructor error, checked against
  what the configured components actually produce. (Was merely wasteful under repair; fatal under
  throw.)
- ~~**Separate door for the convenience path.**~~ **RETRACTED — user, round 1.** There is **no
  recompute path anywhere**, not even a user-requested one. The cache's schedule is fixed at
  construction and **identical on every iteration**; the user's one act of control is declaring once
  what the schedule stores. The later extended access (unfuse-on-demand) also has no recomputes — it
  changes the schedule once, at declaration. Anything outside the state and the cache, the user builds
  in their own callback with the exported recovery verbs. *This is what makes throwing coherent rather
  than harsh: with no fallback anywhere, a stamp mismatch is simply a report that the schedule is
  wrong.*
  - **Property bought:** per-iteration transform and traffic counts are exact constants of the
    configuration, not run averages — which is what makes the frozen ledgers mean anything.
  - **Consequence:** the ``t_0`` deposit is mandatory (constructor or warm-up), else the first
    callback has nothing to read. Same requirement as firing callbacks at ``n+1`` boundaries.
  - **Consequence:** after a reseed the cache is stale and reads throw until the next deposit. Correct
    under this rule, not a gap — the user mutated the state, the interval is theirs.
- **CHECK FIRST:** whether `warmup!`'s skewness gate or any off-cadence diagnostic reads through the
  cache at a non-boundary moment. If so, throwing breaks a working path and those call sites move to
  the boundary first.

This supersedes §2's "A read repairs a stale value" rule and rewrites §6's first two gap bullets.
Relates to the boundary-refresh design that retires the `CHART_CONTRACT` holder.

### Unused-storage detection — user's idea, split

**REJECTED: "error if a declared slot was not *read* during an iteration."** Reads happen at a
cadence (a callback every 100th iteration ⇒ 99 false errors); relaxing it to whole-run turns it into a
complaint at the end of a 12-hour job. And it is blind where useful — the solver-internal observables
are read by stage 1 every iteration by construction, so it can only fire on user-declared extras,
exactly the population whose irregular reads are legitimate.

**ADOPTED — user agreed, round 1: "error if a declared slot was not *deposited* during an
iteration."** Depositing is a
solver act on a fixed schedule — no cadence, no user involvement. A slot whose owner never deposits
holds scratch for the rest of the run and every later read throws anyway; catching it at the boundary
names the bug at its source. One flag per slot per iteration, cleared on deposit, checked at the
boundary. Composes with the three-valued stamp: it is a refusal to leave the *never deposited* state
at a boundary.

**The allocation worry needs a different instrument — REPORT, don't error.** The CI audits bound the
working set only for configurations the *test* constructs, so a user over-declaring in their own
script gets no signal at all; the real gap is that a declaration's price is invisible when the user
makes it. The constructor knows which declarations are free (slot merges with a producer's scratch
register) and which cost a fresh array — that is exactly §3's three-level table, determined by the
configuration — so it should **report** the added residency (n vector fields, m MiB at this size and
precision) at construction. Information at the decision point. An error would be wrong: over-declaring
is a legitimate choice, paid knowingly.
