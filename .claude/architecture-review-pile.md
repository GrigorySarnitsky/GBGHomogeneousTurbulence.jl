# ARCHITECTURE.md review pile — problems the user found reading the rewrite

> **Per-item status (done vs pending) and the post-refactor name map: see [`.claude/README.md`](./README.md).**
> #7, #8, #11, #12 are closed; #1–#6, #9, #10 are pending ARCHITECTURE.md prose edits. Names predate the
> `4e2c0bd` refactor.

**Collection only.** The user is reading `docs/ARCHITECTURE.md` (the holistic MZ-foundation rewrite)
and reporting problems. I **collect** them here and do **not** edit the doc — or the code — until the
user explicitly says to orchestrate the fixes. This mirrors the earlier docstring-pile discipline.

Each entry, in the order raised:
- **Report** — what the user said (verbatim where possible).
- **Where** — the section / passage it points to.
- **Defect** — the problem distilled to its class.
- **Verified** — any ground-truth I checked against `src/` or the doc (facts for the eventual fix).
- **Status** — `collected` (nothing acted on yet).

**Render caveat (context, not a defect):** the user reviews in **VSCode's markdown preview**, not the
Documenter build — so Documenter inline-math spans (`` ``…`` ``) and `\texttt{…}` show as literal source in
their screenshots. That rendering is *not itself* a defect; but where the underlying *source* is wrong
regardless of renderer (e.g. a standalone code identifier written as `\texttt{}`-in-a-math-span instead of
backticks — item 4), it IS a defect. Judge each on the source, not the preview.

---

### 1. §1 Identity — `GBGCloudPhysics` is not a link, unlike PF and SS

- **Report:** "Here you link to PF and SS, but the `GBGCloudPhysics` is not clickable." (with a render of §1)
- **Where:** §1, the inversion paragraph — "its sibling consumer `GBGCloudPhysics`" is bare code, while
  `GBGPeriodicFields` and `GBGStreamingStatistics` (both in the blockquote just above) are hyperlinked to
  their GitHub repos.
- **Defect:** link inconsistency across the three siblings. Either link `GBGCloudPhysics` too (consistency),
  or the asymmetry is deliberate and should have a reason.
- **Verified:** in §1, PF → `github.com/GrigorySarnitsky/GBGPeriodicFields.jl`, SS →
  `github.com/GrigorySarnitsky/GBGStreamingStatistics.jl`; `GBGCloudPhysics` has no URL anywhere in the doc.
  **Open question for the fix:** is there a public `GBGCloudPhysics` repo to link (presumably
  `github.com/GrigorySarnitsky/GBGCloudPhysics.jl`), or is it a private sibling (in which case the omission
  is intentional and PF/SS being linked-but-Cloud-not is the consistent choice)? — the user decides.
- **RESOLVED:** the repos are private but the **docs are public** — link to the docs sites, not the repos.
  Change PF `github.com/…` → `https://grigorysarnitsky.github.io/GBGPeriodicFields.jl`, SS →
  `https://grigorysarnitsky.github.io/GBGStreamingStatistics.jl`, and **add** CloudPhysics →
  `https://grigorysarnitsky.github.io/GBGCloudPhysics.jl`.
- **Status:** resolved; ready to apply.

### 2. CLASS — velocity named descriptively but the scalar by its symbol `\varphi` (recurring)

- **Report:** "one for the velocity, one for `\varphi` — you keep doing it!! Why call velocity 'velocity',
  but scalar '`\varphi`'?!" (frustrated; a *recurring* pattern, not a one-off).
- **Where:** §4.1 `SimulationDomain`, the transform-plans parenthetical: "one for the velocity, one for
  ``\varphi``, one for the rank-2 strain tensor …". But treat as a **class**, not this line.
- **Defect:** register mixing between the two fields. In a *descriptive/storage* context (naming plans,
  buffers, slots) both fields must be **descriptive** — "the velocity, the scalar"; in a *math-variable*
  context both must be **symbols** — `u`/`φ`, `û`/`φ̂`. The defect is asymmetry: one field by its word alone
  while the other by its symbol alone ("velocity … `\varphi`"). Here the context is descriptive → fix to
  "one for the velocity, one for the scalar, one for the rank-2 strain tensor". (The flow-field naming
  convention: symbols for math variables, descriptive names for storage.)
- **Cold-read probe (for the sweep):** scan every place the two fields are named *together* — is either
  named by its word alone while the other by its symbol alone? Both descriptive, or both symbolic, never
  one-of-each. (Note: "the spectral velocity `û` and scalar `φ̂`" — word+symbol for *both* — is consistent
  and fine; the defect is only the *asymmetric* form.)
- **Status:** collected. **Sweep the whole doc**, do not fix only the flagged line.

### 3. §4.1 dealiasing — drop the growing option list, name only the default

- **Report:** "'(the sharp 2/3 rule by default, or the smooth Hou–Li filter).' → just '(the sharp 2/3 rule
  by default)', because soon we will add phase shift, possibly 3/2 — we don't want to maintain the growing
  list."
- **Where:** §4.1 `SimulationDomain` dealias-kernel parenthetical. (Same instinct the user gave earlier for
  the de-aliasing overview: name the default, do not enumerate a family that will grow.)
- **Defect:** an enumerated option list ("… or the smooth Hou–Li filter") that will need maintenance as
  phase-shift / possibly 3/2 dealiasing arrive. Cut to just the default: "(the sharp ``2/3`` rule by
  default)". Check other spots that enumerate dealiasing variants (§7, §4.2 mention 2/3 only — likely fine).
- **Status:** collected.

### 4. CLASS — standalone `Float32`/`Float64` written as `\texttt{…}` in a math span, not backticks

- **Report:** "'(`\texttt{Float32}` or `\texttt{Float64}`) and' — are those LaTeX-rendered? Why?"
- **Where:** §4.1 `SimulationDomain` precision sentence; and wherever else `\texttt{Float32}`/`\texttt{Float64}`
  appear (§6 precision section at least).
- **Defect:** a *standalone* code identifier should be plain-backticked `` `Float32` `` / `` `Float64` ``.
  The `\texttt{}`-inside-a-``…``-math-span form is reserved by the house rule *only* for a code identifier
  that must sit **inside a larger formula**; here they are standalone, so the math-span wrapping is
  unnecessary and renders as LaTeX. Fix: `\texttt{Float32}` → `` `Float32` ``, `\texttt{Float64}` →
  `` `Float64` ``.
- **Cold-read probe (for the sweep):** every `\texttt{…}` — is it genuinely inside a formula? If it is
  standalone, it should be backticked code instead.
- **Reinforced (§6):** user re-flagged `\texttt{Float32}` / `\texttt{Float64}` in §6 — confirmed second
  instance, same class. **Sibling formatting defect in the same §6 paragraph:** the set notation
  `` ``\{`` model fidelity, integrator, precision, footprint, closure ``\}`` `` splits a formula across prose
  (math braces around English contents), rendering as literal `\{` `\}`. Fix by dropping the math braces —
  a plain prose list ("ranges over model fidelity, integrator, precision, footprint, and closure"). Fold
  into this notation/formatting sweep.
- **Status:** collected. **Sweep all `\texttt{}` uses and stray math-markup-around-prose.**

### 5. §4.1 `State` — FieldBuffers allocation must be run-specific; no overprovisioning (memory is tight)

- **Report:** "FieldBuffers allocation must be specific to the simulation. E.g. if we don't need scalar in
  the run, nothing is allocated for it. We must not overprovision, the memory is tight."
- **Where:** §4.1 `State`: "`FieldBuffers` preallocates *all* field-sized scratch a coupled velocity +
  scalar step writes into: …" — reads as if velocity *and* scalar buffers are always allocated.
- **Defect:** the description over-provisions in prose. The code allocates **only what the run needs** — no
  scalar buffers when `scalar = false`. The doc should say allocation is *specific to the configured run*
  (scalar scratch only when the scalar is carried), tying to the minimal-footprint / tight-memory invariant
  (GPU-primary, §6, invariant 4), not "all … velocity + scalar".
- **Verified:** recent commits confirm — `53f9c56` "Optional scalar: allocate and evolve it only when
  scalar = true"; `3aa3467` "FieldBuffers scalar default → false, matching Simulation". So the buffers are
  config-specific; the current prose is stale/overstated. (Re-check the exact `FieldBuffers` fields at fix
  time.)
- **Status:** collected.

### 6. ADD A POLICY — coordinate-free (rotation-invariant) expressions and computations

- **Report:** "we need an explicit policy of using coordinate-free expressions and computations, like we
  did for the `derivative_skewness`."
- **Where:** a *new* convention in §10 (physics-first sibling of "operator-first docstrings" and
  "physical-meaning-first"); the exemplar is §4.3 `derivative_skewness` and decision 17. May also warrant
  a new decision-log entry when acted on.
- **Gap (not a defect in existing text):** the codebase *practises* coordinate-free diagnostics but never
  states it as a **policy**. Make it explicit: homogeneous isotropic turbulence is statistically isotropic,
  so a diagnostic or computation that picks a coordinate axis imports a spurious direction-dependence; a
  **rotation-invariant (coordinate-free)** form is the honest, physically-faithful object. State invariants,
  not axis projections. Extends to computation, not just diagnostics (prefer tensor-invariant / basis-free
  operations).
- **Verified (the reference to cite):** decision 17 — `derivative_skewness` is the normalized third
  invariant of the strain rate ``\boldsymbol S``, ``3C\langle\det\boldsymbol S\rangle/\langle\boldsymbol S:\boldsymbol S\rangle^{3/2}``
  with ``C = \tfrac47\sqrt{15/2}``, chosen precisely because "the axis-picking longitudinal form was
  coordinate-dependent, the invariant is the honest object." That is the template the policy generalizes.
- **Status:** collected.

### 7. CODE NAMING — the `AbstractForcing` protocol methods are grammatically inconsistent

- **Report:** "What about the naming? `forcing_rate!` and `forcing_source!` — are those good? Expressive,
  understandable, consistent?"
- **Where:** the `AbstractForcing` protocol in `Forcing.jl` (described in §4.4). A **code** rename, to fold
  into the module refactor — not a doc-text fix.
- **Defect (consistency, primary):** two grammars in one four-method protocol —
  `forcing_rate!` / `forcing_source!` are **noun-first** (`forcing_<thing>`, naming what is contributed),
  while `prepare_forcing!` / `apply_forcing!` are **verb-first** (`<verb>_forcing`, naming the action). Word
  order and grammar both flip.
- **Assessment given:** `rate` vs `source` is *good physics* (linear/multiplicative contribution folded
  into ``\mathcal E`` vs an additive RHS source) — keep the distinction. The weakness is that the noun+`!`
  form hides the action (`forcing_rate!` *fills* a rate; `forcing_source!` *adds* a source), unlike the
  verb-named pair; and a newcomer won't grok rate-vs-source without the linear-vs-additive context.
- **Proposed direction (user decides):** unify to verb-first, verb carrying the action —
  `set_forcing_rate!` (fills the per-mode rate ``A(\boldsymbol{\kappa})``), `add_forcing_source!` (adds to
  the RHS), `prepare_forcing!`, `apply_forcing!`. One grammar; each verb states fill / add / prep /
  post-step. (Alternative reading: the split is *intentional* — two contribution hooks named by what they
  contribute, two lifecycle hooks named by the verb — but on the surface it still reads inconsistent.)
- **Verified:** the four names are the real code methods (used in `test/forcing.jl`: `forcing_rate!`,
  `prepare_forcing!`).
- **DECIDED (yes):** adopt `set_forcing_rate!` / `add_forcing_source!` / `prepare_forcing!` /
  `apply_forcing!`. Rename in `Forcing.jl` + all call sites and tests.
- **Status:** resolved; ready to apply.

### 8. CODE + ARCHITECTURE — `Physics` (the System spec) lives inside the `Propagator` module

- **Report:** "Why is `Physics` part of `Propagator`? It describes the system. We should either rename it to
  `PropagatorParameters` (better?), or move it."
- **Where:** `struct Physics{VF,SF}` is defined in `TimeIntegration.jl` (→ the `Propagator` module), holding
  `viscosity` (ν), `schmidt` (Sc), `velocity_forcing`, `scalar_forcing`. Described in §4.5.
- **Defect:** a **System specification** (Re via ν, Sc, the forcings — §3's System, minus IC) is defined in
  the **Method/Propagator** module. Placed there because `step!` consumes it (define-where-used /
  programmer-first), not because it belongs there. This is the sharpest physics-first-vs-programmer-first
  misfiling found so far.
- **Assessment given:** DON'T rename to `PropagatorParameters` — that mislabels System physics as numerics
  config and doubles down on the misplacement (and fights §4.4, which calls forcing "the source", a System
  concern). MOVE it. The move exposes that the §3 **System is named but has no module** — it is scattered
  (forcings in `Forcing`, ν/Sc/forcings in `Physics`-in-`Propagator`, IC in `State`).
- **Fix options (user decides):** (a) give the System a home; possibly rename `Physics → System` to match
  the frame (caveat: `System` slightly over-claims — it omits the IC, which the frame counts as System).
  (b) Fold `Physics` into `Generator`, which it parametrizes (ν→diffusion, Sc→scalar diffusion,
  forcings→source) — caveat: it carries the forcings, so this adds a `Generator → Forcing` dependency the
  current graph (and the `.als`) does not have.
- **Verified:** `TimeIntegration.jl:49-54` — `struct Physics{VF<:AbstractForcing, SF<:AbstractForcing}`
  with fields `viscosity::Float64`, `schmidt::Float64`, `velocity_forcing::VF`, `scalar_forcing::SF`.
  Consumed by `step!` and assembled in `SimulationRun.jl:150`.
- **DECIDED (option B):** fold `Physics` into `Generator`; add the honest `Generator → Forcing` edge (the
  RHS includes the source, per §4.2). Reconcile the `.als` dependency graph accordingly.
- **NAME — panel ran (wcd240lwk), user deciding:** `Physics` too abstract; `FlowParameters` taken
  (`Phenomenology`); `System` over-promises (subsumes the box). Six-perspective panel → **recommends
  `FlowConditions`** (3/6 generalist lenses + synthesis): intrinsic not relational, completes the triad
  `SimulationDomain`/`FlowConditions`/`State`, set-vs-measured foil to `FlowParameters` by a different
  head-noun, doesn't demote the stateful forcing strategies; sole debit (conditions≈IC/BC) is void in a
  periodic box with a separate `State`. **Runner-up `ControlParameters`** (the literal turbulence term; loses
  on shared "…Parameters" noun + demoting forcings). **`GeneratorParameters` REJECTED** — it *clears* the
  `PropagatorParameters` bar (Generator is physics, not numerics), but killed on forward precision: this
  struct is the **System**, held *invariant* down the Model ladder (§3, decision 7), while the **Generator
  varies per rung** (an LES generator gains closure coefficients) — so `GeneratorParameters` names only a
  subset, precise *only because DNS is the sole built rung*; also relational, and "Parameters" mis-describes
  the forcing strategy objects. Shortlist: FlowConditions › ControlParameters › Scenario › GoverningParameters
  › GeneratorParameters › Regime.
- **DECIDED — `FlowConditions`.** The open-systems panel (whz21kwlk) confirmed it and did NOT revive
  `System`: the bundle is a *proper subset* of the §3 System axis (lacks the IC and the domain), so a
  type named for the axis while holding less is ambiguous + imprecise; `{ν,Sc,forcing}` are the
  generator's coefficients that *tune* the flow, not the system. Fold into `Generator` as `FlowConditions`.

### 11. ARCHITECTURE — a stateful forcing's internal state belongs in `State`, not the spec bundle

- **Report:** "If flow conditions are stateful, why aren't they part of the state?"
- **Where:** the `State` role, the `Forcing` protocol (stateful forcings), and the `#8` `FlowConditions`
  carving.
- **Insight (verified reasoning):** a stochastic forcing's internal state IS state. An OU forcing obeys
  `df = −f/τ·dt + noise`; only the joint `(u, φ, f)` is autonomous/Markovian — `f` is the minimal Markovian
  embedding of a colored-noise drive. Currently that state lives *inside the forcing object* and
  `prepare_forcing!` advances it out-of-band, so the state is split across two homes (`State` + the forcing)
  and the generator is not a clean function of the declared `State` — a mild physics-first impurity.
- **Recommendation:** split the forcing into **specification** (which forcing + its config τ/variance/band —
  stateless → `FlowConditions`) and **evolving state** (the OU field, a controller's accumulator —
  auxiliary/driver state → `State`). The verified carving already supports this: the State role is
  **resolved + modeled + extra** (the `.als`), auxiliary/notional state rides in `modeled`/`extra` (the FDF
  Q-space is the model case). Bonus: this makes `FlowConditions` hold *only* stateless specification,
  dissolving the "stateful contents" objection and strengthening the name.
- **Scope:** `StochasticOU` (the only genuinely stateful forcing) is archived (§7); the live forcings are
  ~stateless — so this bites on re-add and when controllers arrive. A real refactor (config/state split),
  **not** a rename — does NOT block the `FlowConditions` name; but decide + document the principle now.
- **RESOLVED (panel whz21kwlk):** the diagnosis is confirmed (the OU state IS extended state; the
  generator is not a clean function of the declared `State` today — a real MZ defect), but the home is the
  **existing `modeled` slot on the ONE `State`** (the retained surrogate on the *system* side), NOT a new
  `EnvironmentState`. DEFERRED: `StochasticOU` is archived and every live forcing is stateless, so the
  defect is *inactive* at the built rung — record the `modeled` slot as the landing site and fold the
  state-homing into the work that de-archives `StochasticOU` (invariant 9: deferred ≠ missing). The
  config/state split still stands: `FlowConditions` holds the stateless forcing spec.
- **Status:** RESOLVED — home = `modeled` slot on `State`, deferred; no plumbing now.

### 12. FOUNDATIONAL — open-systems framing: System / SystemState / EnvironmentState (links #8 + #11)

- **Report:** "What about having System, SystemState, and some ExternalState/UniverseState? Something from
  open systems theory / statistical mechanics / thermodynamics."
- **Insight:** the open-systems system/environment split *is* the Mori-Zwanzig projection (system = resolved,
  environment = projected-out, its influence = memory + noise), which the verified `.als` already encodes as
  **resolved + modeled** State slots. Mapping: **SystemState** = resolved `(u,φ)` (today's `State` /
  `resolved`); **EnvironmentState** = modeled environment DOF (a stochastic forcing's OU internals, a
  closure's Q-space = `modeled`) — the principled home for #11; **System** = the open-system spec
  (ν, Sc, forcing-coupling) = the #8 bundle, paired with SystemState.
- **Precision flag:** *universe* = system + surroundings (the total); the external part is the
  **environment / reservoir / bath**. The driver's state is `EnvironmentState` / `ReservoirState`, NOT
  `UniverseState` (which would be the whole). Forcing models an energy *reservoir*; viscosity couples to an
  unmodeled heat *bath* (sink). Use the surroundings word.
- **Altitude / YAGNI:** at DNS with the live (stateless) forcings the EnvironmentState is EMPTY — so this is
  *abstraction-ready-not-populated* (invariant 9): adopt the vocabulary + reinterpret resolved/modeled, but
  don't build a separate concrete `EnvironmentState` type until a stateful forcing or a closure populates it.
- **Reopens #8:** open-systems draws System vs domain the other way (system = the fluid; `SimulationDomain` =
  the container it sits in) — so `System` for the #8 bundle becomes viable again, reversing the earlier
  domain-subsumption rejection. **Confirm with user.**
- **Next:** offered a panel (open-systems / non-eq stat-mech / thermodynamics / MZ) to settle vocabulary +
  altitude, or decide directly.
- **RESOLVED (panel whz21kwlk, unanimous 6/6 — adopt-as-lens-only):**
  - **Adopt as a LENS, mint NO type.** Record the open-systems / non-equilibrium reading as a **sub-lens
    under Mori-Zwanzig in §8** (prose), never a competing top-level frame (that would re-litigate decision
    22). Hard constraint: a `SystemState`/`EnvironmentState` type split would **break the checked
    `extendsNeverRecarves` invariant** (every slot on the ONE `State`) — so it isn't even a lens.
  - **The naming is inverted (the key correction):** in MZ the environment is *eliminated* (survives only
    as memory + noise); what the code ever retains (a forcing's OU state) is the finite **Markovian
    surrogate you KEEP**, on the *system* side — the dilation `(u,φ,f̂)` enlarges the system. So
    "Environment" names what you threw away. Honest word = **modeled / auxiliary** (already the `.als`
    word). If a stateful rung ever forces a concrete type, prefer `ModeledState`/`AuxiliaryState`.
  - **Vocabulary struck:** `UniverseState` categorically wrong (= system + surroundings = the whole);
    `Reservoir`/`Bath` import equilibrium baggage (infinite/memoryless/fixed-T) a finite-τ OU violates;
    `BathState` names the unmodeled sink that carries no state. Keep `State` (not `SystemState` — collides
    with the frame-axis word "System").
  - **DOC ACTION when executing:** add the open-systems sub-lens to §8 (under MZ) + name the `modeled`
    slot's meaning in prose. No code, no type.
- **Status:** RESOLVED — adopt-as-lens (§8 sub-lens); no types; confirms #8 `FlowConditions` and #11's
  home (the `modeled` slot on the one `State`, deferred to StochasticOU de-archiving).
- **Status:** collected; option B decided, name pending.

### 9. ADD — statistics is the sole *computational* precision exception: it aggregates in `Float64`

- **Report:** "Shall we note that statistics is the sole exception since it aggregates in `Float64`?"
- **Where:** §6 Precision, alongside "the element type ``T`` flows from the frame … no kernel silently
  fixes the arithmetic."
- **Gap (add a note):** §6 says precision flows from the frame (both `Float32`/`Float64` equal), but
  **statistics / reductions aggregate in `Float64` regardless of the field precision** — a deliberate
  exception for accumulation accuracy (summing many `Float32` values loses precision). Note statistics as
  the **sole** exception *among field computations*. This is distinct from — and stronger than — the
  `Physics`-scalar-params `Float64` already noted in §6 (that is scalar config cast to ``T`` at use, not a
  field computation; so "sole computational exception" is the honest phrasing).
- **Verify at fix time:** the user states statistics aggregates in `Float64`. Confirm the exact scope —
  `GBGStreamingStatistics` aggregation, and whether the `Observables` reductions (`inner`, radial spectrum)
  also accumulate in `Float64` (likely, and worth stating if so). This is the numerical-hygiene sibling of
  invariant 4 / §6.
- **Status:** collected.

### 10. §9 invariant 8 — "the scalar **is** `\varphi`" conflates the field with its symbol (root of #2)

- **Report:** "'The scalar is `\varphi`. Never `\theta` …' — could that be the source of you putting
  `\varphi` everywhere instead of the word 'scalar'? Rewrite it to '… the scalar is denoted with `\varphi`
  …' or something that works."
- **Where:** §9, invariant 8.
- **Defect:** "the scalar **is** `\varphi`" is an *identity* (scalar ≡ symbol), which licenses substituting
  the symbol for the word "scalar" in descriptive prose — plausibly the *priming source* of the recurring
  register-mixing defect [[#2]]. Change identity → denotation.
- **Proposed rewrite (user's, polished):** "8. **The scalar is denoted `\varphi`**, never `\theta` — in
  code, mathematics, and prose." Keep it terse; the register rule (symbol for the math variable, the word
  "scalar" in prose) is #2's job, not this invariant's.
- **Cross-link:** fix together with **#2** — this removes the priming, #2 sweeps the instances and states
  the rule. Root + surface.
- **Status:** collected. (User invited applying this one now; holding under collect-only unless told to.)
