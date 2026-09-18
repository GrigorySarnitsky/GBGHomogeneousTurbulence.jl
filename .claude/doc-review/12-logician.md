# Hat: LOGICIAN — definitions and arguments as formal objects

Substrate: `manuscript-full.md` (the rendered site) only. Candidates weighed before the cap: 46.
Defect names per the hat brief: CIRCULARITY / EQUIVOCATION / NON SEQUITUR / UNFALSIFIABILITY /
INCONSISTENT RULE PAIR / VACUOUS DISCRIMINATION.

---

## 1. Scalar mean conservation asserted exact and only-to-roundoff in one docstring
- **type**: contradiction · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: api / Generator, `scalar_rhs!`: "The conservative form conserves the scalar mean exactly: the divergence has no $\kappa=0$ component"
  - PAGE: api / Generator, `scalar_rhs!` (same docstring, three paragraphs later): "$\langle\nabla\cdot(\boldsymbol{u}\varphi)\rangle = 0$ holds discretely only to roundoff"
  - PAGE: observables_cache §2.1: "The conservative scalar form holds the $\kappa=0$ tendency at zero"
- **axis**: is the discrete scalar-mean conservation exact or roundoff-only?
- One paragraph claims exact conservation because the divergence has no zero mode; a later
  paragraph in the same docstring justifies the $\kappa=0$ pin by saying the identity holds
  "only to roundoff". Both cannot be true. (The velocity twin's pin is coherently motivated —
  $\langle\boldsymbol{u}\times\boldsymbol{\omega}\rangle$ is a genuine product mean; the scalar text
  appears to have inherited that justification while also keeping the older exactness claim.)
  Which sentence is right is the physics hat's question; that the docstring asserts both is mine.

## 2. "Holds the present instant only" contradicted by the Lagrangian sample history
- **type**: contradiction · **severity**: major · **confidence**: high
- **locations**:
  - PAGE: api / SimulationRun, module map: "It holds the present instant only; past instants exist only in what an observation recorded"
  - PAGE: architecture §4.7: "bundles what one iteration advances and reads — the present instant, no history"
  - PAGE: api / Cache, `ObservablesCache` fields: "`velocity_at_particles_history` — the earlier Lagrangian samples"
  - PAGE: observables_cache §2.3: "it is the one place the cache holds more than the latest deposit"
- **axis**: does a `Simulation` hold past-instant data?
- The multistep sample history is $\boldsymbol{u}(t_{n-j})$ at earlier instants, held in the cache
  the `Simulation` owns and persisted by `write_simulation` ("the Lagrangian sample history…"). It is
  neither the present instant nor something "an observation recorded" — the run itself deposits it.
  The blanket no-history identity claim is falsified by the corpus's own documented mechanism.

## 3. "The declaration is measured at construction, not trusted" — a check the described mechanism cannot perform
- **type**: contradiction (unfalsifiability at the claimed check point) · **severity**: major · **confidence**: medium
- **locations**:
  - PAGE: api / Forcing, `AbstractForcing`: "The declaration is measured at construction, not trusted."
  - PAGE: api / Generator, `ResolvedGenerator` caveat: "implements `set_forcing_rate!` without also declaring `uses_steady_linear_rate` … throws an `ArgumentError`"
- **axis**: what the construction-time guard can verify.
- Steadiness of a rate is a temporal property; no construction-time inspection can measure it. The
  only guard the docs describe catches the *reverse* misdeclaration (hook implemented, trait
  undeclared). A strategy that declares `true` while publishing a state-dependent rate passes
  construction and silently drops the scheme to first order — exactly the `ConstantPower` defect the
  decision log records. Ask what observation at construction would refute a false declaration: none
  the docs name. The sentence promises a verification the surface does not deliver.

## 4. The hand-run loop has no documented way to advance the particles epoch without destroying the history
- **type**: contradiction (plus vacuous discrimination) · **severity**: major · **confidence**: medium
- **locations**:
  - PAGE: api / Cache, `ObservablesCache` fields: "a hand-run loop that moves tracers itself announces the change with `particles_modified!`, which is what advances it"
  - PAGE: api / Cache, `particles_modified!`: "The run layer never calls this verb: its own tracer advance … moves the particles epoch through a separate, history-keeping announcement"; "It also discards the Lagrangian sample history"
  - PAGE: api / Particles, `Tracers` example: "`deposit!(cache, tracers, u)` … do this first / `advect!(Heun(), …)`" (no epoch verb appears)
- **axis**: how a legitimate hand-driven `advect!` advances the particles counter.
- The history-keeping announcement exists but is internal and unnamed on the public surface; the one
  public verb discards the history. Consequences as documented: (a) a hand loop running
  `AdamsBashforth` cannot both advance the epoch and keep the history its scheme needs; (b) a hand
  loop that calls neither leaves the counter frozen, so the two-epoch staleness guard on
  `velocity_at_particles` ("current only when both counters match") can never fire across a push —
  the guard discriminates nothing on the documented hand path.

## 5. Who makes the seeding deposit — "when the cache is built" vs the `Simulation` constructor
- **type**: contradiction · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: observables_cache §1.3: "a deposit seeding the initial state is made when the cache is built"
  - PAGE: api / Propagator, `deposit!`: "the `Simulation` constructor makes the seeding deposits"
  - PAGE: api / Cache, `ObservablesCache` signature: "`ObservablesCache(domain; scalar = false, …)`"
- **axis**: which construction performs the seeding deposit.
- The cache constructor takes no state, so it *cannot* deposit the initial state's observables; the
  API surface correctly assigns the seed to `Simulation`. The design page's "when the cache is
  built" is impossible as written and misleads a hand-assembling reader (whose §3.1 example indeed
  builds a cache that seeds nothing).

## 6. "A caller reads through the accessors and never deposits" vs the mandated caller re-deposit
- **type**: contradiction (inconsistent rule pair) · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / Cache, module: "A caller reads through the accessors and never deposits."
  - PAGE: api / Cache, `fields_modified!`: "After a hand-made mutation, re-deposit with the run layer's `deposit!` before advancing again"
  - PAGE: api / State, both seeders: "then restore the cache with `deposit!` before advancing again"
- **axis**: whether a caller may (must) call `deposit!`.
- Both rules are stated as binding, and the documented reseed workflow violates the first: the caller
  who mutates out-of-band is required to deposit. The intended split (reader vs solver role) is never
  stated, so the pair cannot both be obeyed as written.

## 7. `deposit!` ownership named two different ways
- **type**: contradiction · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: api / Cache, module: "`deposit!`, which `Propagator` owns rather than this module"
  - PAGE: api / Cache, `fields_modified!`: "re-deposit with the run layer's `deposit!`"
- **axis**: which module owns the verb.
- One surface argues explicitly that `Propagator` owns the verb (and the API index homes it there);
  a neighbouring docstring attributes it to "the run layer" (`SimulationRun`), which exports no such
  verb. A reader following the second attribution looks in the wrong module.

## 8. "The recoveries are exported" vs the no-re-export ruling
- **type**: contradiction · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: observables_cache §1.3: "the recoveries are exported, so a caller who mutates the state mid-run computes what they need themselves"
  - PAGE: decisions (2026-08, chart recoveries): "The umbrella re-exports no `GBGPeriodicFields` name, this operation included"
  - PAGE: api / State, module: "Recovery therefore goes through the four-argument `to_physical!`" (a backend function)
- **axis**: are the field recoveries exports of this package?
- The velocity/scalar recovery is a `GBGPeriodicFields` operation reached through the backend; only
  `vorticity_physical!` is an IT export. The design page's premise ("the recoveries are exported")
  is false on the current surface, so its conclusion — the mutating caller can self-serve with
  package exports — does not follow as stated.

## 9. The §2.4 table's Built column discriminates nothing by its own legend
- **type**: vacuous discrimination · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE: observables_cache §2.4: "Its Built column … reads `—` wherever Cached is no or never (a depends row is built whenever its configuration asks for it)"
- The legend makes Built a function of Cached (yes→yes, depends→per-configuration, no/never→"—"), so
  the column can never convey information the Cached column does not already carry. It also equivocates
  on "holds the observable": `dissipation` and `derivative_skewness` are built functions of the
  package today, yet their rows read "—".

## 10. §2's configuration enumeration excludes what the section then covers
- **type**: contradiction · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: observables_cache §2: "One configuration fixes the system: a mask dealiasing rule (`TwoThirds` or `HouLi` …), a three-stage scheme, … an adaptive timestep."
  - PAGE: observables_cache §2.3: table rows for `PhaseShift`; "a scheme with a different stage count scales them by its own"
  - PAGE: observables_cache §1.4: pricing "under a hand-fixed $\Delta t$"
- **axis**: the configuration space the section claims vs the one it analyzes.
- The stated configuration names two mask rules, three stages, adaptive stepping; the same section
  then prices `PhaseShift`, other stage counts, and fixed-Δt driving. Either the enumeration is a
  default-instance description mislabelled as the configuration, or the extra rows are out of scope —
  as written the two halves disagree.

## 11. The absolute design choice and its standing exception form a soft inconsistent pair
- **type**: inconsistent-rule-pair · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: observables_cache §1.1: "Caching an observable adds nothing to what an iteration computes, moves, or stores."
  - PAGE: observables_cache §1.4: "the closing deposit's maximum-speed reduction is one physical-vector pass every iteration, paid even by a hand-fixed-$\Delta t$ run that never reads the number"
- **axis**: whether the choice admits exceptions.
- The choice is stated as absolute ("stated here rather than derived") and then §1.4 documents a
  standing violation of it (a pass, and its reduction arithmetic, performed only so the deposit
  schedule stays uniform). §1.2's biconditional "cached exactly when it passes four tests" leans on
  the same "some component must produce it anyway" clause that the fixed-Δt mode breaks. The
  exception is honestly priced, but the rule is never weakened to accommodate it — a reader holding
  both sentences holds a contradiction.

## 12. "Front door" — the glossary resolves only one of the term's two live senses
- **type**: equivocation · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: notation, Vocabulary: "front door | the historical name … for what current docs call the domain-building `Simulation` constructor"
  - PAGE: architecture §4.7 heading: "SimulationRun — the front door" (the run layer, not a constructor form)
- **axis**: the term's referent.
- The glossary row — declared "where a reader resolves it" — defines the term as the domain-building
  constructor form; the architecture heading uses it for the whole run layer. A reader resolving the
  §4.7 title via the glossary lands on the wrong object. Two senses, one resolver, half a mapping.

## 13. `max_wavenumber`'s defining predicate excludes nothing under `HouLi`
- **type**: vacuous discrimination · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: api / SimulationDomain, `max_wavenumber`: "The highest wavenumber magnitude `domain` … treats as resolved signal"; "$f = 1$ for `HouLi`"
  - PAGE: api / SimulationRun, `Simulation`: "hands `HouLi` a $\mathrm{Re}_\lambda$ about 31% higher on the same grid"
- With $f = 1$ every representable mode counts as "resolved signal", including the modes the taper
  damps to machine epsilon — the predicate discriminates resolved from damped content for two of the
  three strategies and nothing for the third. The downstream $\kappa_{\max}\eta$ criterion inherits
  the vacuity, which the `Simulation` docstring quantifies but the definition itself never concedes.

## 14. "The state" is declared fluid-only, then the kind test needs positions to be state
- **type**: equivocation · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: observables_cache §1.1: "Where this page says the state, it means the fluid's"
  - PAGE: observables_cache §1.2: "determined by the state at a single $t_n$ — by the state alone, in every argument … the probe's position counts as an argument and is bound by the same rule"
- **axis**: what "the state" quantifies over in the kind test.
- Under the page's declared usage, the cached `velocity_at_particles` is *not* determined by the
  state alone (it needs $\boldsymbol{X}(t_n)$), yet the table marks it cached. The patch clause
  ("counts as an argument… same rule") silently widens "state" to the tower's fields-plus-positions
  sense without saying which rule now binds a position — a position is not a function of the fluid
  state. The test trades on both senses.

## 15. Skewness aliasing: the module's priced/unpriced split vs the docstring's "on either"
- **type**: contradiction · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: api / Observables, module: "priced for the sharp truncations, unpriced for `HouLi`'s taper"
  - PAGE: api / Observables, `derivative_skewness`: "on either, treat the skewness as an indicator, not an alias-controlled measurement"
- **axis**: where the indicator-only caution applies.
- The module draws the line at sharp-vs-taper (both `TwoThirds` and `PhaseShift` priced); the
  docstring groups `PhaseShift` with `HouLi` under "on either … an indicator", implying its residual
  is *not* controlled, while `TwoThirds` alone escapes with "negligible". The two surfaces partition
  the three strategies differently, and the referent of "either" is left for the reader to guess.

## 16. The CFL band-scaling is asserted, not derived, for the base it admits is degenerate
- **type**: non-sequitur · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE: api / Propagator, `recommended_cfl`: "which makes the formula degenerate: its $0.25$ is an empirical margin rather than a computed limit"
  - PAGE: api / Propagator, `recommended_cfl`: "the dependence on how much of the band is kept is geometric, holding whether the base was computed or measured"
- The $1/\kappa_{\max}$ scaling is derived from the imaginary-axis eigenvalue argument, which the
  docstring itself says does not apply to `IFHeun` (stability rests on viscous damping, a mechanism
  with its own $\nu\kappa^2\Delta t$ scale). "Is geometric" restates the conclusion for the empirical
  base without an argument that survives losing the premise. The honest hedge arrives one clause
  later ("only as trustworthy as its base"), half-retracting the claim just made.

## 17. Handles that "read like a citation" naming values the cited paper does not contain
- **type**: citation (equivocation on the handle's semantics) · **severity**: minor · **confidence**: low
- **locations**:
  - PAGE: architecture §4.8: "The full handle `Phenomenology.Spectra.Pope2000` reads like a citation"
  - PAGE: api / phenomenology / Scalings, `Li2008`: "the value is this package's own reduction of that database's forced-isotropic dataset"
  - PAGE: api / phenomenology / Scalings, `Sreenivasan1995`: "as quoted by Sagaut & Cambon (2018), not a figure read off the 1995 paper"
- The naming rule makes the author-year the paper the parametrization comes from; two presets carry
  values that do not come from their name's paper (each honestly disclosed in place). The handle
  semantics and the disclosed practice pull apart — a reader trusting "reads like a citation" is
  citing the wrong source for the number. Disclosed, hence low-severity; but the rule and the
  practice are not the same rule.

## 18. "A default never hides a choice you needed to make" vs the front door's forcing default
- **type**: inconsistent-rule-pair · **severity**: minor · **confidence**: low
- **locations**:
  - PAGE: api / Forcing, module: "what a run holds fixed — `target`, `rate`, `over` — … is required. A default never hides a choice you needed to make."
  - PAGE: api / SimulationRun, `Simulation`: "`velocity_forcing` left at `nothing` means the default — a `VarianceController` driving the whole-field kinetic energy to the `kinetic_energy` value" (itself defaulted to `1.5`)
- The principle is stated without scope; the front door defaults exactly the run-held choices
  (forcing kind and target) the principle says are never defaulted. The intended scoping (strategy
  constructors strict, run layer convenient — decision 28) exists in the log but not in the stated
  rule, so the two surfaces read as conflicting norms.

## 19. Glossary τ row points "below" at a row that is above
- **type**: other (false locator inside a definition) · **severity**: nit · **confidence**: medium
- **locations**:
  - PAGE: notation, Derived scales, τ row: "in the integrating factor's row below, $\tau$ is a Runge–Kutta stage substep"
  - PAGE: notation, Spectral representation and operators: the $\mathcal{E}(\boldsymbol{\kappa})$ row (which precedes Derived scales)
- The disambiguation clause — load-bearing for a glyph the page admits is overloaded — directs the
  reader downward to a row that sits in an earlier table. (If `consolidate.py` preserves page order,
  this is the site's own error, not an extraction artifact.)

## 20. Vocabulary defines the observation as "once per iteration"; the loop observes n+1 times
- **type**: contradiction · **severity**: nit · **confidence**: high
- **locations**:
  - PAGE: notation, Vocabulary: "observation | the callback a run is driven by: it reads the run once per iteration"
  - PAGE: api / SimulationRun, `run!`: "A run of $n$ iterations therefore observes $n + 1$ instants"
- The glossary definition excludes the initial observation at the seeded $t_0$ that every other
  surface insists on ("the instant a validation run most wants"). One reads once-per-iteration, the
  other once-per-instant-including-$t_0$; the definition undercounts by exactly the observation the
  design is proudest of.

## 21. The step!/deposit! "alignment" claim holds only as a subsequence
- **type**: non-sequitur · **severity**: nit · **confidence**: medium
- **locations**:
  - PAGE: api / Propagator, `step!`: "after the leader both take `state`, `domain`, `buffers` in the same order"
  - PAGE: api / Propagator, `step!` signature: "`step!(scheme, state, generator, domain, buffers, cache, dt)`"
- After `step!`'s leader the arguments are state, *generator*, domain, buffers, *cache*, dt — the
  claimed triple appears only as a subsequence with two interposed arguments. As a memorability
  argument ("the two calls … align") the premise is weaker than the conclusion suggests.

## 22. The turnover clock is homed in two fields of one struct
- **type**: contradiction · **severity**: nit · **confidence**: low
- **locations**:
  - PAGE: api / SimulationRun, `StationarityCriterion` fields: "`monitor` — the sampled signals (the turnover clock, $\varepsilon$, …)"
  - PAGE: api / SimulationRun, `StationarityCriterion` fields: "`elapsed_turn`, `last_time`, `started` — the turnover clock's state"
- Two field entries each claim the turnover clock. If `monitor` holds the clock's *series* and the
  trio its accumulator, neither entry says so; as written the same object is assigned to two homes.
