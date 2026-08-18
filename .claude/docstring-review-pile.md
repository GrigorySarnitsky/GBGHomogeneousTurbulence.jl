# Docstring review pile

> **Status, done-items, and the post-refactor old→new name map: see [`.claude/README.md`](./README.md).**
> Names in this pile predate the `4e2c0bd` refactor (`SimulationState`, `Dynamics`, `TimeIntegration`,
> `Physics`, `forcing_rate!`, …) — translate via that map. Design items D4 and D9 are already done.

You steer development by **reading docstrings**; their clarity has no ground-truth test, so your eye
is the oracle. This file is where I **collect** what that eye catches — verbatim, then distilled to a
defect-class and a reusable cold-read probe. It holds **two kinds, kept separate**: **documentation**
problems (the numbered reports) and **design** problems (a distinct section at the end) — to be split
into their own tracks at the very end.

**The rule (learned the hard way, 2026-07-11).** I only **collect** here. I do **not** edit any
`src/` or `docs/` file, run any build, or commit — **until you explicitly say to fix** (e.g.
"orchestrate the reading" / "fix the pile"). A report is a pile entry, never a green light to touch
the code. Fixing happens later, in one pass, via the adversarial reading you orchestrate over the
whole pile — catching each instance *and its siblings*.

**Everything below is `collected` — nothing is fixed.** The package is unchanged
(`git diff HEAD` empty).

---

## Documentation problems — today's reports (2026-07-11), in the order you raised them

### 1 — De-aliasing overview names only the `2/3` rule
- **You said** (`index.md`, "What it solves"): *"you should add just single short mention, that we
  provide other de-aliasing, with no specifics."*
- **Class.** A map/overview names a *chosen* method as if it were the only one, hiding that a family
  exists. **Register-appropriate fix:** at the map a short mention, *no specifics*; the enumeration
  lives in the operation's home docstring.
- **Probe.** For each method named in an overview, does the code offer alternatives, and does the map
  signal "default, others available" without listing them?
- **Verified.** `DealiasingStrategy` has two concretes — `TwoThirds` (the `2/3` default) and `HouLi`
  (smooth) — both exported (`GBGIsotropicTurbulence.jl:68–69`). The overview mentions only `2/3`.

### 2 — "spectral machinery" gloss clashes with the `SimulationDomain` name
- **You said** (the `SimulationState` bullet on `index.md`, again on `api.md`, and again on the
  `SimulationDomain` **Type** docstring): *"'spectral machinery' doesn't go well with the name
  'simulation domain'."*; *"spectral machinery does not go well with 'simulation domain', too
  technical."*; *"'spectral machinery' — I think it['s] as descriptive as 'things'."*
- **Class.** After a user-facing name is fixed (`SpectralOperators → SimulationDomain`), the **prose
  gloss** still describes the object by its backend machinery — **too technical**, and worse **nearly
  content-free** ("as descriptive as 'things'"): it tells the user nothing about what the object *is*.
  A backend framing hides in the gloss even after the name is fixed.
- **Probe.** Does the gloss name what the object *is to the user* (the discretized box the run lives
  on) or how it's *built* ("spectral machinery")?
- **Verified.** "spectral machinery" glosses `SimulationDomain` in `index.md`, `api.md`,
  `SimulationState.jl` (module docstring + the `SimulationDomain` docstring), `api/SimulationState.md`.

### 3 — `SimulationState` "holds the random initial conditions" — state vs initialization
- **You said** (twice): *"does it hold the current state or the 'random initial conditions'?"* and,
  re-reading it on `api.md`, *"it tells about initial conditions, but nothing on the current state."*
- **Class.** A description says a module *holds* / *is* something it only *provides routines to set*,
  or conflates the current evolving state with its initialization — and here names the ICs while
  saying **nothing about the current state**. The fix must speak to the current state, not only reword
  the IC clause.
- **Probe.** For each "holds / is / contains", verify against the structs what is actually stored and
  *when* (current state vs scratch vs a routine that sets the initial state).
- **Verified.** `FieldBuffers` holds preallocated **scratch a step writes into**
  (`SimulationState.jl` module comment). The primary state `û`/`φ̂` is passed **into** `step!` from the
  run layer. `random_solenoidal_velocity!` / `random_scalar!` are **routines that fill a field**. So
  the module holds neither "the current state" nor "the ICs" as stored data.

### 4 — Map bullets exhaustively list a growing set (Observables, Forcing, TimeIntegration)
- **You said** (across several bullets): *"The list may grow, no need to list everything, just for
  people to understand."*; *"no need for exhaustive list, here you just tell the user the gist of the
  module."*; *"no need for exhaustive forcing list."*
- **Class.** A map bullet enumerates every member of an open/growing set; it goes stale and buries the
  gist. Characterize by kind + a few representative examples; the full list lives on the API page.
- **Probe.** Is this an exhaustive enumeration of a set the code will extend? Replace with the gist.
- **Verified.** `Observables` lists all eight (`kinetic_energy` … `integral_scale`); `Forcing` lists
  all five (`NoForcing`, `BandRescaling`, `Linear`, `ConstantPower`, `StochasticOU`); `TimeIntegration`
  lists both (`IFRK2`, `IFLowStorageRK3`). On `index.md` and/or `api.md`.

### 5 — Forcing default stated at the wrong layer
- **You said** (`Forcing` bullet): *"Is that our default? Both velocity and scalar unforced?"*
- **Class.** A doc states "the default" using a lower-layer constructor's default that the layer the
  user actually calls overrides.
- **Probe.** When a doc says "default", is it the default at the layer the user calls (the
  `Simulation`/run default), verified against that signature?
- **Verified.** **No — not both unforced.** The `Simulation` default is a *forced* velocity
  (`BandRescaling`, `target = :total`) + a freely-decaying scalar (`NoForcing`) —
  `SimulationRun.jl:129–130`, confirmed by its docstring `:90–92`. "each defaulting to `NoForcing()`"
  is `Physics`'s *own* constructor default (`Forcing.jl`), which the run overrides.

### 6 — SE jargon in user-facing prose: "pluggable" / "plug" / "hook"
- **You said** (`Forcing`, `Particles`, then again re-reading `api.md`): *"'pluggable'… it doesn't
  state where we 'plug' it. Also, a little be too [jargon]."*; *"You do like plugs, don't you?"*;
  *"Same as before, you 'plugs'."*
- **Class.** Startup/SE idiom (`pluggable`, `plug in`, `hook into`) a turbulence physicist wouldn't
  reach for — the naming policy applied to prose verbs/adjectives. And: where a thing is selectable,
  **say where it is chosen**, don't just call it "pluggable".
- **Probe.** Would a turbulence physicist write this word? Replace SE idiom with plain terms
  (selectable / chosen / enters / acts on); state the choice point.
- **Verified.** "pluggable" in `Forcing.jl:1,20`, `TimeIntegration.jl:1,19`, `Particles.jl:2,14`,
  `GBGIsotropicTurbulence.jl:17,18`, `index.md:72,75,78`, `api.md:9,12,13`, `api/Particles.md:10`,
  `architecture.md:143,243`; "hook(s) into" in `Forcing.jl`.

### 7 — `SimulationRun` "validates against the reference laws" — overclaim
- **You said** (`SimulationRun` bullet): *"Do we actually have or will have that validation
  functionality there?"*
- **Class.** A map claims a broader capability ("the reference laws", plural) than the code provides.
- **Probe.** Does every named capability exist and do what the phrase implies? Narrow the phrase to
  what's real.
- **Verified.** Both functions **exist and are exported**: `flow_parameters` (`SimulationRun.jl:208`)
  and `validate_spectrum` (`:230`). But `validate_spectrum` only compares the **energy spectrum** to a
  model — so "validates against the reference laws" over-reaches. The broader comparison machine is
  the pending **task #7**.

### 8 — "the conventions follow Pope" — false attribution
- **You said** (`notation.md`): *"I do not enforce any following to the book… it will be ultimately me
  who decides on the notation and I do not follow Pope, at least not consciously."*
- **Class.** Prose claiming the package *follows* an external authority for a choice you own. Sources
  are inspiration/references (cited), never authorities we follow.
- **Probe.** Does any "follows / per / adopts X's conventions" name a source as an authority?
  Downgrade to "see X" — unless the code literally inherits it (field/spectral conventions *do* follow
  `GBGPeriodicFields`, a real dependency).
- **Verified.** `notation.md:8` "physical conventions follow Pope"; `architecture.md:11` "Pope's
  turbulence conventions"; `architecture.md:646` §References "*(Notation; …)*". (Pope's *Turbulent
  Flows* is now in `inspiration/literature`.)

### 9 — "the symbol of −∇²" — not standard turbulence usage
- **You said**: *"is it the standard term? Commonly understandable in turbulence research?"*
- **Class.** Specialist math jargon (the operator/pseudodifferential *symbol*) where the turbulence
  audience reads it as ambiguous; state the physics plainly instead.
- **Probe.** Would a turbulence physicist parse this term? Replace with the physical statement:
  "−∇² acts in spectral space as multiplication by |κ|²".
- **Verified.** "symbol of −∇²" in `SimulationState.jl:92`, `Dynamics.jl:97`, `notation.md:50`,
  `architecture.md:142` — **and in `CLAUDE.md:128`** (the policy text itself uses it as an example;
  reconcile that with you, don't rewrite your governing doc unilaterally).

### 10 — `energy`/`kinetic_energy` and `variance`/`scalar_variance` — keyword vs observable register
- **You said** (Diagnostics table): *"In many parts we name the argument just energy, not
  kinetic_energy. The same for the scalar. Think about consistency carefully."*
- **Class (the principle).** Constructor **keywords** use the short generic word in a disambiguating
  context (`energy`, `variance`); the standalone measured **observables** use the fully-qualified name
  (`kinetic_energy`, `scalar_variance`). A keyword wearing an observable's long name breaks the
  register.
- **Probe.** For each setter keyword, is it the short word? For each observable, is it qualified?
  Flag a keyword using an observable's long name.
- **Verified.** Velocity is already consistent — `energy` everywhere (`Simulation`, `BandRescaling`,
  `random_solenoidal_velocity!`). The **lone outlier** is `Simulation(; scalar_variance = …)`
  (`SimulationRun.jl:133`), whose body forwards `variance = scalar_variance` to `random_scalar!` —
  while `random_scalar!` and `StochasticOU` already use the short `variance`. (Needs your decision on
  direction before any rename.)

### 11 — "scratch allocators" vs "buffers" — two names that both read as "buffers"
- **You said** (`SimulationState` bullet, `api.md`): *"are scratch allocators the same or not as
  buffers? For a user both sound as some sort of buffer."*
- **Class.** A map lists two adjacent items whose names don't distinguish them — the reader can't tell
  if they're the same or two different things.
- **Probe.** For adjacent list items, does each name make clear it's a *distinct* thing? If two names
  collapse to one mental category ("buffer"), distinguish them or drop one from the map.
- **Verified.** They ARE different: `FieldBuffers` is the **preallocated** bundle (one struct of many
  fields); the "scratch allocators" are the **functions** that allocate a fresh field on demand
  (`spectral_vector`, `physical_vector`, `scalar_spectral`, `scalar_physical`, `tensor_spectral`,
  `tensor_physical` — `SimulationState.jl` exports). The bullet names both without saying they differ.

### 12 — Symbols given inconsistently — and given where they aren't used
- **You said** (`SimulationState` bullet, then the "Random initial conditions" section): *"for some
  reason for the scalar you put its single-letter notation, but not for velocity."*; *"why does scalar
  earn mentioning its notation, but not velocity? There should be none here, you do not use it in the
  formula (though in docstrings below you do and you correctly name it)."*
- **Class.** Parallel items get notation inconsistently (scalar `φ`, velocity nothing) — **and** a
  symbol is introduced where it isn't used. A symbol earns its place only where a **formula** uses it;
  in a formula-free summary neither sibling should carry one.
- **Probe.** Does a symbol appear only where a formula uses it? In a formula-free summary, are **both**
  symbols absent? In an operation docstring whose formula uses them, are both named (correctly)?
- **Fix direction.** Here (a formula-free summary) **drop `φ`** — do *not* add `u`. In the operation
  docstrings below, the formulas do use them and name both correctly; leave those.
- **Verified.** The `SimulationState` bullet reads "…velocity and a mean-zero scalar ``\varphi``" (`φ`
  only, `index.md`/`api.md`); the "Random initial conditions" section reads "…random solenoidal
  velocity, or a mean-zero scalar φ" — `φ` with no formula present, while
  `random_solenoidal_velocity!` / `random_scalar!` below do use and correctly name both.

### 13 — `Observables` bullet singles out one function name (`max_speed`)
- **You said** (`Observables` bullet, `api.md`): *"Why would you single out max_speed to actually name
  its Julia function?"*
- **Class.** In a prose/map list, exactly one item is given its code identifier while its siblings are
  prose only — inconsistent code-name exposure (the code-name analog of #12).
- **Probe.** In a map list, is one (or a few) item given its code name while siblings aren't? Make it
  uniform — prose gist in the map, code names on the API page.
- **Verified.** `api.md:11` backticks only `max_speed` ("…the maximum velocity component that sets the
  CFL step (`max_speed`)…"); the other seven observables are prose.

### 14 — Integration method named "Heun" in one bullet, by code type in another
- **You said** (`Particles` / `TimeIntegration` bullets, `api.md`): *"here you name the integrator
  Heun, but not in the other place. Inconsistency."*
- **Class.** The same kind of thing (a time-integration method) is named by its **method** in one map
  bullet and by its **code type** in a sibling — inconsistent naming register across the map.
- **Probe.** Across sibling bullets, is a method named consistently — by method everywhere or by code
  type everywhere?
- **Verified.** The `Particles` bullet names the pusher "Heun-in-time" (`Particles.jl:15`); the
  `TimeIntegration` bullet names the velocity integrators `IFRK2`, `IFLowStorageRK3` — yet `IFRK2`
  **is** Heun (`TimeIntegration.jl:12,23,183`, "IFRK2 (Heun)"). Same method, named two ways.

### 15 — A struct docstring doesn't state what the struct holds (its fields) or how to access it
- **You said** (`Simulation`, then `Tracers`): *"Shall we explicitly state what is stored in the struct
  and how to access it?"*; *"I see the buffers below, you could have at least linked them. But better
  explain what the structure holds."*
- **Class.** A type's docstring describes what it *is* but not its **stored fields** (and, when it does
  mention them in passing, doesn't **link** them) — the reader can't tell what's inside or how to read
  it.
- **Probe.** For a user-facing struct, does the docstring name (and link) the fields it holds and how
  to read them?
- **Verified.** `Simulation` lists its *components* in prose but names no field/accessor (observables
  reach `sim.velocity`, `sim.scalar`, `sim.buffers.velocity` — `SimulationRun.jl:192–196`); `Tracers`
  mentions "the predictor positions and the point-value buffers" in passing, unlinked, and never states
  the struct's fields.

### 16 — Signature splits explicit keywords vs `kwargs…`, but the docstring calls them all "Keywords"
- **You said**: *"how do you decide what to put as explicit arguments, and what to call just 'kwargs'?
  Below you call them all 'keywords'."* (the design half — the *principle* — is **D3**.)
- **Class.** The signature distinguishes explicit keywords from a `kwargs…` splat, yet the "Keywords"
  section documents them all uniformly — the split is neither explained nor reflected, so the reader
  can't tell which are front-door-only vs forwarded.
- **Probe.** Where a signature has both explicit keywords and `kwargs…`, does the docstring mark which
  is which (or explain the split)?
- **Verified.** Front door `Simulation(; grid_points_per_axis, k_max_η, energy, side_length,
  scalar_type, array_type, dealiasing, kwargs…)` — explicit keywords + a splat; the "Keywords" list
  documents everything (including the `kwargs…`-forwarded `viscosity`, `schmidt`, forcings, `scalar`, …)
  as one flat "Keywords".

### 17 — Non-obvious usage without a concrete example (`run!` call form; `ForcingSpec` usage)
- **You said** (`run!`, then `ForcingSpec`): *"You need to add examples here how to specify the stopping
  condition. The user might miss that you use it as a named argument e.g. turnovers = 10 or whatever.
  Also we need an example of the do block/callback."*; *"And how to use it? I see, those constructors."*
- **Class.** A docstring whose usage is non-obvious — mutually-exclusive keywords shown as `A | B | C`,
  a do-block/callback, or a type built by operator-free constructors and passed elsewhere — with **no
  concrete example**.
- **Probe.** Does a non-obvious usage (keyword `A | B | C`; a do-block; a construct-then-pass type)
  carry a concrete example of the actual call?
- **Verified.** `run!(sim; turnovers | time | steps, every = nothing)` and `run!(sim; …) do sim … end`
  show no example; `ForcingSpec` explains the operator-free-constructor (`Linear(; rate)`, …) → pass-to
  -`Simulation` pattern but shows no example call.

### 18 — Module docstrings are unstructured technical inventories (no map, no per-group "why", no bullets)
- **You said** (`SimulationState`, then `Forcing`): *"That reads too technical. Either be less concrete,
  or give a short explanation for each group, why they are needed, etc."*; *"That's just unstructured
  single-paragraph mess."*
- **Class.** A **module** docstring densely enumerates its contents in one cramped paragraph — no
  structure (bullets), no per-group purpose, no map. (Policy: a module docstring is a *map* — what it
  is, a short *why* per group, a linked one-liner per operation.)
- **Probe.** Does a module docstring read as a structured map (bullets, a one-line purpose per group)
  or as a single dense inventory paragraph? If the latter: raise altitude, add structure, give a
  purpose per group.
- **Verified.** `SimulationState` is one run-on sentence (SimulationDomain internals, scratch
  allocators, FieldBuffers, IC routines — no per-group "why"; also #2, #3). `Forcing` is worse — a
  single paragraph cramming the four step methods, the `domain`/`buffers`/`scratch` conventions, the
  five forcings, the `Physics` velocity/scalar split, and `ForcingSpec` (also carries #6 jargon, #4
  exhaustive list, #21 args-by-contents, #10 the `NoForcing` default).

### 19 — `SimulationDomain` docstring: cramped prose should be bullet lists of fields and arguments, with clickable refs
- **You said**: *"If we list the ingredients, we should just list the struct fields with proper
  clickable references to PF. Also, it is hard to [read] a paragraph which is just a cramped list. A
  bullet list which describes the fields would be much, much better. Also, there are lots of arguments,
  once again a bullet list of arguments would be better. See SS, there is a package wide, consistent
  look of docstrings … Array/ROCArray/CuArray need to be clickable and lead to the appropriate Julia
  packages."*
- **Class.** A docstring lists contents (and arguments) as a **cramped prose list** rather than a
  **bullet list**, describes vague "ingredients" instead of the **actual struct fields**, and leaves
  types (PF types, external array types) **unlinked**.
- **Probe.** Where a docstring lists fields or arguments: is it a bullet list? Does it name the actual
  struct fields (not a vague gloss)? Is every type a clickable `@ref` (PF types → PF; external types →
  their package)?
- **Verified.** `SimulationDomain`'s fields are `grid`, `layout`, `velocity_plans`, `scalar_plans`,
  `tensor_plans`, `multipliers`, `squared_wavenumber`, `squared_wavenumber_kernel`, `dealias`,
  `dealiasing` (`SimulationState.jl:104–113`); the prose gloss lists a vague subset (drops `layout`,
  `squared_wavenumber_kernel`, `dealiasing`; merges the three plan types). Five constructor arguments
  in prose; `Array`/`ROCArray`/`CuArray` named unlinked. **Recurs on the `FieldBuffers` Type
  docstring**: no field list, first paragraph one super-long list-sentence ("unreadable") — same class
  as #15 (no fields) and #18 (cramped).

### 20 — A sentence gestures at a capability without a link or an example ("bridges a Phenomenology model spectrum")
- **You said**: *"'The run layer bridges a Phenomenology model spectrum into this function.' that
  sentence tells nothing for the user. Either remove it, or make a clickable link to the available
  spectrums. And add an example of using one from Phenomenology."*
- **Class.** A sentence references a capability without making it actionable — no clickable link to the
  concrete options, no example — so it tells the user nothing usable.
- **Probe.** Does a sentence that gestures at a capability ("the run layer bridges …", "you can use a
  model …") link to the concrete options and show an example? If not, remove it or make it actionable.
- **Verified.** `random_solenoidal_velocity!` ends "The run layer bridges a `Phenomenology` model
  spectrum into this function." — no link to the `EnergySpectrum` models, no example.

### 21 — A per-argument entry gives a type's contents, not the argument's role (and doesn't just link)
- **You said** (`random_solenoidal_velocity!`, then `Dynamics`): *"… is it important for the user here
  to know what does domain supply? Or shall he just click a link to it?"*; *"'… the operator bundle
  domain (a SimulationDomain: grid, transform plans, wavenumber multipliers, de-alias kernel) …' — that
  describes what they contain, not their role."*
- **Class.** An argument entry lists a linked type's **contents** (already documented on the type)
  instead of the argument's **role** here — why the method needs it. Link the type for its contents;
  state the role. (One concept, one home.)
- **Probe.** Does an argument entry state the argument's *role* and `@ref` the type — or re-enumerate
  the type's internals?
- **Verified.** `random_solenoidal_velocity!` re-lists what `SimulationDomain` supplies; `Dynamics`
  documents `domain`/`buffers` by contents ("a `SimulationDomain`: grid, transform plans, …", "a
  `FieldBuffers`") rather than why each method needs them.

### 22 — `Dynamics` module docstring: render the NS equation (as on the main page) and bullet the ops per term
- **You said**: *"You need to have the rendered NS equation in rotational form here, as on the main
  page. And a bullet list of functions, each referencing the rendered term of this NS equation. Observe
  again, some paragraphs are just single-sentence list."*
- **Class.** A module docstring for the operations that realize an equation should **render that
  equation** and present the operations as a **bullet list, each tied to the term it computes** — not a
  prose sentence-list with the equation only in words.
- **Probe.** Where a module realizes an equation, is the equation rendered, and is each operation a
  bullet referencing the term it computes (rather than a single-sentence list)?
- **Verified.** The `Dynamics` docstring gives the rotational-form NS RHS in prose only (the rendered
  form is on `index.md`) and lists its five operations (`velocity_vorticity!`, `scalar_to_physical!`,
  `velocity_nonlinear!`, `scalar_nonlinear!`, `integrating_factor!`) as a single-sentence list (also
  carries #18/#19).

### 23 — An implementation reason muddies the "preserved" guarantee (too technical, reads contradictory)
- **You said**: *"'then a copy of û is transformed — the in-place inverse transform consumes its
  spectral source.' that motivation just makes muddies it. Like [two] opposite sentences nearby. And
  isn't it too technical? The user must know that û is intact, that's all."*
- **Class.** A docstring gives an **implementation reason** (a copy is made because the in-place
  transform consumes its source) that is too technical and reads as **self-contradictory** beside the
  user-facing guarantee ("preserved" … "consumes its source"). State only the guarantee; the mechanism
  is a `#` comment.
- **Probe.** Does a docstring carry an implementation reason the user doesn't need — one that muddies
  the guarantee? Keep the guarantee ("`û` is preserved"); move the mechanism to a `#` comment.
- **Verified.** `velocity_vorticity!`: "`û` is preserved: … a copy of `û` is transformed — the in-place
  inverse transform consumes its spectral source." `scalar_to_physical!` repeats it ("preserving `φ̂` —
  a copy is transformed, since the in-place inverse transform consumes its source").

### 24 — A long formula is set inline instead of as a displayed block equation
- **You said** (`velocity_nonlinear!`): *"The formula is too long to have it inline."*
- **Class.** A long or standalone formula is set inline (a ``…`` span in running prose) rather than as
  a displayed block (a ```math``` block) — hard to read, and it risks horizontal scroll / the
  inline-math-on-one-line lint.
- **Probe.** Is any long or standalone formula inline rather than a display block? Promote long
  formulas to ```math``` blocks.
- **Verified.** `velocity_nonlinear!` sets the Lamb-vector identity and the momentum equation
  ``∂ₜu = ℙ(u×ω) + ν∇²u + f`` as inline spans in running prose (`Dynamics.jl:66–68`).

### 25 — Diagnostic docstrings don't say whether de-aliasing is involved
- **You asked** (twice — energy/variance, then dissipation): *"does it first dealiase and then compute?
  Is it important?"*; *"And here too. Do we do it after dealiasing?"*
- **Class.** A diagnostic docstring doesn't preempt a natural numerics question (is the field
  de-aliased before the reduction?), leaving the reader unsure. State the answer briefly.
- **The answer (verified).** None de-alias — they are direct inner-product **reductions**
  (`kinetic_energy = ½ inner(u,u)`, `scalar_variance = inner(φ,φ)`, `dissipation = ν inner(ω,ω)`,
  `scalar_dissipation = 2ϰ weighted_inner(φ, |κ|²)` — `Observables.jl:35,67,47,84`). A reduction to a
  scalar is Parseval-exact and needs no de-aliasing; aliasing afflicts pseudospectral *products* (the
  nonlinear term), not a reduction. The run already keeps the field de-aliased (2/3 zeroes the top
  modes; HouLi damps them to ~machine-ε), so a physical-space reduction is exact too.
- **Probe.** Does a diagnostic docstring preempt "is the field de-aliased first?" — stating it's an
  exact reduction that relies on the field's maintained de-aliasing?
- **Status.** collected — documentation.

### 26 — Inline citation is a bare surname, not author-year (and not linked)
- **You said** (`derivative_skewness`, then `IFLowStorageRK3`): *"No link to Betchov, citation?"*;
  *"No references?"*
- **Class.** An inline citation gives a bare surname ("(Betchov)") without the year — not the
  author-year the policy requires, and inconsistent with the `§References` entry.
- **Probe.** Does every inline citation give **author-year** consistent with `ARCHITECTURE.md`
  §References (not a bare surname)? Is the reference present there?
- **Verified.** `derivative_skewness` says "(Betchov)"; the reference **does exist** — "Betchov, R.
  (1956). An inequality concerning the production of vorticity…" (`architecture.md:633`) — so the fix
  is the inline form "(Betchov 1956)", not a new reference. (Documenter has no link target for a
  bibliography line, so author-year is the consistent form.) Same for `IFLowStorageRK3` — "Williamson
  2N" with no citation; the reference exists ("Williamson, J. H. (1980). Low-storage Runge–Kutta
  schemes.", `architecture.md:644`).
- **Status.** collected — documentation.

### 27 — `BandRescaling` `:total`: is "total energy" all modes or resolved modes?
- **You asked** (`BandRescaling`): *"And here, the total energy or energy of resolved modes?"*
- **The answer (verified).** The **total over all stored modes**: `:total` computes
  `total_energy = ½ inner(field, field)` — "½⟨|·|²⟩ over the whole field" (`Forcing.jl`, `:total`
  branch). For the sharp **2/3** rule (default) this equals the **resolved** energy (non-resolved modes
  are zero); for **HouLi** it also includes the damped high modes (≈ machine-ε at default strength), so
  it is strictly the total.
- **Class.** A quantity ("total"/"whole-field" energy) whose all-modes-vs-resolved reading a reader
  can't settle from the docstring — moot for 2/3, real for HouLi.
- **Probe.** Where a docstring says "total"/"whole-field", is it clear this is the Parseval sum over
  all stored modes (and equal to the resolved energy for a sharp cutoff)?
- **Status.** collected — documentation.

### 28 — Content that serves neither using nor understanding (a mathematical aside)
- **You said** (`IFLowStorageRK3`): *"'setting D=0 recovers the bare Williamson scheme, and dropping
  the nonlinearity recovers exact diffusion E_D(Δt).' — why is this information important? For
  understanding? Or using?"*
- **Class.** A docstring carries content whose purpose is unclear — it neither helps the user *use* the
  object nor is essential to *understand* it (a mathematical aside / limiting-case decomposition). Trim
  it, or tie it to a use or understanding it earns.
- **Probe.** Does each sentence serve using or understanding? Flag asides that serve neither (limiting
  cases, decompositions the user never invokes).
- **Verified.** `IFLowStorageRK3`: "setting `D = 0` recovers the bare Williamson scheme, and dropping
  the nonlinearity recovers exact diffusion `E_D(Δt)`" — two limiting cases the user neither sets nor
  invokes.
- **Status.** collected — documentation.

### 29 — A sentence starts with a code identifier or a latex span
- **You said** (`Tracers`): *"don't start a sentence with code or latex."*
- **Class.** A sentence begins with a `code` identifier or a math/latex span (e.g. "`scheme` is …") —
  reads awkwardly and (for math) risks the inline-math rendering rules. Start sentences with a word.
- **Probe.** Does any sentence begin with a backticked identifier or a ``…`` / ```math``` span? Reword
  to lead with a word (e.g. "The `scheme` argument is …").
- **Verified.** `Tracers` has "`scheme` is the GBGPeriodicFields interpolation scheme …" and "`rng`
  (first form only) is the random stream …" — sentences opening with code.
- **Status.** collected — documentation.

### 30 — API-page section groups by a bare conjunction, not expressed logic ("Advection and sampling")
- **You said** (Particles API page): *"Why do you lump advection and sampling? I hope not by
  implementation, they should be bundled by logic and I see very little [connection]."*
- **Class.** An API-page `##` section groups objects under a bare "A and B" conjunction without stating
  the **logical** basis — so it reads as grouped by implementation (same module), not by meaning.
- **Probe.** Does each API-page section title/intro express *why* its objects belong together (the
  shared logic), or is it a bare conjunction of verbs?
- **Verified.** "Advection and sampling" groups `advect!` + `sample!`; both are steps of the same
  **Lagrangian-tracking loop** (advance the tracers, then read fields along their trajectories — both
  docstrings say "for the Lagrangian statistics"), but the title/intro conjoins them without expressing
  that unifying logic.
- **Status.** collected — documentation.

### 31 — Accessors are in a separate API-page section from the type they access
- **You asked** (Particles API page, "Tracer accessors"): *"Is that to access tracers fields? They
  should be together with the type documentation, no?"*
- **Class.** An API-page splits a type from its accessors into different `##` sections, when the
  accessors are *how you read the type* — they belong with it. (Ties to #15: a type's section should
  show how to access it; #30: group by logic.)
- **Probe.** Are a type's accessors grouped **with** the type (the reader finds "how to read it" next
  to it), or stranded in a separate section?
- **Verified.** "Tracer accessors" (`tracer_positions`, `tracer_velocities`, `ntracers`) is a separate
  section from the `Tracers` **type** section, though all three read the `Tracers` fields (positions,
  trajectory velocities, count).
- **Status.** collected — documentation.

---

## Cross-cutting directives you gave today (for the fix pass to honor)
- **Map register** (from 1, 4): a map/overview *characterizes* — a short mention, no specifics, no
  exhaustive lists; specifics and full lists live in the operation's home docstring / API page.
- **Say where** (from 6): don't call a thing "selectable/pluggable" without naming the point at which
  it is chosen.
- **Physicist, not startup** (from 6, 9): plain physics/math words, no SE idiom, no specialist jargon
  the turbulence reader won't parse.
- **Consistency is deliberate** (from 10): "think about consistency carefully" — a naming change is a
  decision to bring to you, not to apply unilaterally.
- **I won't narrate per-problem** (you said you won't read individual-problem output): I collect
  quietly here; this pile is the audit surface.
- **Bullet lists, not cramped prose** (from #18, #19): a docstring's fields and arguments go in a
  bullet list, each described — never a cramped paragraph-list.
- **Consistent argument docs, modeled on SS** (from #19): adopt the package-wide, consistent
  argument-documentation look of `GBGStreamingStatistics` (SS). Study SS's docstrings in the fix pass
  (reference clone under `inspiration/`, or the published package) — do not invent a new format.
- **Clickable references** (from #19): name the actual struct fields; every type is a clickable
  `@ref` — PF types → `GBGPeriodicFields`; external types (`Array`, `ROCArray`, `CuArray`) → their
  Julia packages (Base / AMDGPU / CUDA).

**Completeness.** The thirty-one entries above are every *documentation* issue you raised today, in
order, from the de-aliasing mention onward — including your re-reads of the `SimulationState`,
`Observables`, `Forcing`, `TimeIntegration`, and `Particles` bullets on `api.md` (which sharpened #2,
#3, #4, #6 and added #11–#14), the `Simulation` Type page (#15–#16), the `run!` page (#17), the
`SimulationState` module docstring (#18), and the `SimulationDomain` Type docstring (#19, and
reinforcing #2), the `FieldBuffers` Type docstring (reinforcing #15/#18/#19), and the "Random initial
conditions" section (reinforcing #12), and the `random_solenoidal_velocity!` docstring (#20–#21), and the `Dynamics` module docstring
(#22, sharpening #21, reinforcing #18/#19), and the `velocity_vorticity!` / `scalar_to_physical!`
docstrings (#23), and the `velocity_nonlinear!` docstring (#24), and the diagnostic docstrings (#25), the `derivative_skewness` docstring (#26), and the `Forcing` module docstring (reinforcing
#18/#19, and #4/#6/#10/#21), and the `BandRescaling` docstring (#27), the `ForcingSpec` docstring (reinforcing #17), and the `IFLowStorageRK3` docstring (#28, reinforcing
#26), the `step!` docstring (reinforcing #21, and D2's FieldBuffers doc ask), and the `Tracers` docstring
(#29, reinforcing #19 and #15/#21), the Particles API page grouping (#30), and the "Tracer accessors" grouping (#31).
Design problems are tracked separately below. If I've missed or misread one, it's a defect in this file — tell me and I'll correct
the entry, not the code.

---

## Design problems (kept separate — to split into their own track at the end)

These are **not** documentation fixes — they question the architecture itself. Collected, **not to be
acted on** until we take up design (you said: at the very end).

### D1 — `Simulation` vs `SimulationState`: where does "the state" live, and why do observables take a whole `Simulation`?
- **You asked** ("The simulation" page): *"what's the point of calling `kinetic_energy` directly on
  `Simulation`, rather than `SimulationState`? What is the distinction between the two?"*
- **The tension (facts).**
  - `SimulationState` is a **module** (`SimulationState.jl:20`), not a value — it bundles
    `SimulationDomain` + `FieldBuffers` + the IC routines, and does **not** hold the evolving state, so
    its name over-promises (ties to doc-problem #3).
  - `Simulation` (a struct in `SimulationRun`) holds the evolving state — `sim.velocity` (`û`,
    spectral) and `sim.scalar` (`φ̂`) — plus `buffers`, `physics`, `domain`, `clock`.
  - The observables take a whole `Simulation` and reach inside it:
    `kinetic_energy(sim) = kinetic_energy(sim.buffers.velocity)` (the **physical-velocity scratch
    buffer**), `energy_spectrum(sim) = energy_spectrum(sim.velocity, sim.domain)`,
    `scalar_variance(sim) = scalar_variance(sim.scalar)` (`SimulationRun.jl:192–196`).
  - So "the state" is **fragmented** — `sim.velocity`/`sim.scalar` for the primary fields, plus
    `sim.buffers.velocity`/`vorticity_start` (scratch that also feeds the observables) — and the module
    named `SimulationState` is not where it lives.
- **You then worked it through** ("The simulation" page + the `Simulation` docstring): *"So simulation
  is the full case? So SimulationState is the mutable part of it? Oh, I see, we do not have a type
  SimulationState, that's a module."* — correct on all three: `Simulation` **is** the full case; there
  is **no** `SimulationState` type; the mutable/evolving state is embedded as fields *inside*
  `Simulation` (`sim.velocity`, `sim.scalar`, and the step scratch in `sim.buffers`).
- **The question to resolve (later).** A candidate direction you surfaced: make the **mutable part its
  own `SimulationState` type** — the evolving `û`, `φ̂`, and the step scratch — which `Simulation`
  composes (full case = domain + physics + integrator + a `SimulationState` + tracers + clock);
  observables would then read the state type, not the whole `Simulation`. Today no such type exists —
  `SimulationState` is a *module* of setup machinery, and the state is fragmented inside `Simulation`.
  (This would also settle doc-problem #3 and the module name.)
- **Sharpened at `FieldBuffers`** — you said: *"Aha! So it's a scratch, not the state! Does it mean,
  there is no concept of state in the package? I bet following MZ faithfully would have prevented that
  omission."* Confirmed: `FieldBuffers` **is** scratch ("Preallocated scratch for one integrating-factor
  step"), so the package has **no first-class `state` concept** — the state is scattered across
  `sim.velocity`/`sim.scalar` and scratch the diagnostics read. The **Mori–Zwanzig** reading the
  architecture already uses for naming (`Dynamics` = generator, `Observables` = observables) has the
  **state** at its centre — the phase point the generator evolves and the observables read — so a
  faithful MZ design makes `state` first-class, completing the triad. **This is the strongest argument
  for the `SimulationState`-as-a-type direction.**
- **Status.** collected — **design track, do not act on now.**

### D2 — `FieldBuffers`: scratch, or (part of) the state?
- **You said**: *"FieldBuffers sound as a scratch, but it may be the actual state of the simulation."*
- **The tension (facts).** The name says "buffers" (scratch), but `FieldBuffers` holds fields the
  observables read as **state**: `kinetic_energy(sim) = kinetic_energy(sim.buffers.velocity)`,
  `dissipation(sim) = dissipation(sim.buffers.vorticity_start, …)` (`SimulationRun.jl:192–193`). So it
  is *both* step scratch *and* a cache the diagnostics treat as state — the name hides that.
- **Now clarified** (you, reading its docstring: *"Aha! So it's a scratch, not the state!"*):
  `FieldBuffers` **is** scratch by design. The remaining tension is that the diagnostics read the
  *physical-velocity scratch* as the state — so the real issue is the **missing state concept** (→ D1),
  not `FieldBuffers`' identity.
- **Confirmed again + a doc ask** (you, reading `step!`): *"Ok, so buffers are not the state, they are
  scratch. Definitely we need a proper docstring for the buffers. Their role and what do they
  contain."* → **`FieldBuffers` needs a proper docstring**: its **role** (scratch a step writes into)
  and its **contents** (the fields) — the convergence of doc-problems #15 (fields), #21 (role), #19
  (bullets) on the `FieldBuffers` surface. (`step!` also under-documents its `buffers` arg as "the
  buffers `buffers`" and re-enumerates `Physics`'s contents inline — #21.)
- **The question (later).** If a `SimulationState` type carries the true state (D1), what stays in
  `FieldBuffers` — only genuine step scratch? Ties to D1, and to doc-problems #3 and #11.
- **Status.** collected — **design track, do not act on now.**

### D3 — What is the principle for explicit constructor arguments vs `kwargs…`?
- **You asked**: *"how do you decide what to put as explicit arguments, and what to call just
  'kwargs'?"*
- **The tension (facts).** The front door names some keywords explicitly (`grid_points_per_axis`,
  `k_max_η`, `energy`, `side_length`, `scalar_type`, `array_type`, `dealiasing`) and forwards the rest
  through `kwargs…` to `Simulation(domain; …)`, with no stated rule for the split. The documentation
  half — that the docstring then calls them all "keywords" — is doc-problem #16.
- **The question (later).** State, and make principled, which arguments are explicit and why.
- **Status.** collected — **design track, do not act on now.**

### D4 — `Physics` (the system/problem parameters) is defined in the `TimeIntegration` module
- **You said** (`TimeIntegration` bullet, then the `Physics` docstring): *"Why Physics live in
  TimeIntegrators… that does not make sense."*; *"That's the system description, should not be in the
  integrators."*
- **The tension (facts).** **Verified:** `struct Physics` — viscosity, Schmidt number, and the two
  forcings — is defined and exported by the **`TimeIntegration`** module (`TimeIntegration.jl:49`,
  export `:37`). Its own docstring calls it "the problem definition consumed by `step!`" — i.e. the
  **System** description (viscosity/`Re`, Schmidt, forcings) in the System×Model×Method framing. So the
  System's parameters live inside the *numerics* module, against concern-based module naming and the
  "thin physics / rich numerics" split (`CLAUDE.md` invariant 1).
- **The question (later).** Where should `Physics` live — its own concern (a System/problem module), or
  with `Dynamics` (the RHS/generator it parameterizes)? Not `TimeIntegration` (the propagator), which
  only *consumes* it.
- **Status.** collected — **design track, do not act on now.**

### D5 — `HouLi` `strength` default should be precision-dependent (auto for Float64 / Float32), with override
- **You said**: *"Probably we need to make it type-dependent, so it automatically chooses the right one
  for Float64 and Float32, as well as the manual override."*
- **The proposal (facts).** `HouLi`'s `strength = 36` default is tuned to **Float64** machine epsilon —
  the Nyquist mode damps to e^−36 ≈ 2.2e-16 ≈ eps(Float64). For **Float32**, eps(Float32) ≈ 1.2e-7, so
  the matching default is strength ≈ 16 (= −log eps(Float32) = 23·ln2 ≈ 15.9). The struct fixes
  `strength::Float64 = 36` at `HouLi()` construction (`SimulationState.jl:74,76`), before the element
  type is known.
- **The direction.** The kernel is built by `_build_dealias(dealiasing, …, T)`, which **already
  receives the element type `T`** (`SimulationState.jl:142`). So default `strength` to *auto* (a
  sentinel), resolved there to −log(eps(T)) (≈36 Float64, ≈16 Float32) so the Nyquist mode always damps
  to that precision's machine epsilon; keep an explicit `strength = …` as the manual override. Applies
  the precision-as-a-studied-axis principle (`CLAUDE.md` invariant 4).
- **Doc follow-on.** The `HouLi` docstring's "defaults 36, 36 … e^−36 ≈ machine epsilon" is
  Float64-specific and would need updating.
- **Status.** collected — **design track, do not act on now.**

### D6 — Does the `DealiasingStrategy` template fit 3/2 padding and phase-shifting?
- **You asked**: *"That's about the design, will 3/2 padding and phase-shifting still fit that
  template?"*
- **The tension (facts).** The current template is **build a kernel, apply as a coefficientwise
  multiply**: a `DealiasingStrategy` provides `_build_dealias(…) → domain.dealias` (a
  `ScalarFieldSpectral` low-pass), applied by `dealias!` / `convolve!(nonlinear, nonlinear,
  domain.dealias)` **after** the nonlinear term is assembled (`Dynamics.jl` `velocity_nonlinear!` /
  `scalar_nonlinear!`). Both concretes fit it — `TwoThirds` (sharp) and `HouLi` (smooth) are spectral
  truncations.
- **The answer: no, not as-is.** **3/2 padding** (zero-pad to 3N/2, transform, multiply, transform
  back, truncate) and **phase-shifting** (form the product on phase-shifted copies and average) don't
  produce a *kernel* — they **restructure the nonlinear-product computation itself** (larger or
  multiple shifted transforms). A post-multiply hook cannot express them.
- **The direction.** To fit them, the abstraction must be broader — a strategy that **owns the
  nonlinear-product assembly** (`û, φ̂` → the de-aliased product), with kernel-multiply as one
  implementation and padding / phase-shift as others. Ties to the 2/3-vs-3/2 dealiasing research
  (`inspiration/reports`).
- **Status.** collected — **design track, do not act on now.**

### D7 — `random_scalar!` has no `spectrum` argument (asymmetry with `random_solenoidal_velocity!`)
- **You said** (`random_scalar!` docstring): *"There is asymmetry with velocity, no spectrum
  argument."*
- **The tension (facts).** **Verified:** `random_solenoidal_velocity!(û, domain; energy,
  peak_wavenumber, spectrum = nothing, rng)` accepts a `spectrum` — a function `κ → E(κ)`, a target
  radial energy spectrum (`SimulationState.jl:333–347`). `random_scalar!(φ̂, domain; variance,
  peak_wavenumber, rng)` has **no** `spectrum` (`:382,393`) — only the large-scale Gaussian envelope.
- **The question (later).** Symmetry says add `spectrum` to `random_scalar!` (seed the scalar from a
  specified scalar spectrum — e.g. an Obukhov–Corrsin form the `Phenomenology` already models). Either
  add it, or record it as a **deliberate deferral** — a coverage gap is a decision (`CLAUDE.md`
  invariant 3, "deferred ≠ missing"), not a silent absence.
- **Status.** collected — **design track, do not act on now.**

### D8 — Naming inconsistency: `velocity_vorticity!` (named by outputs) vs `scalar_to_physical!` (named by direction)
- **You said**: *"Naming inconsistency — for scalar we explicitly say that it gives the physical
  representation, not so for velocity."*
- **The tension (facts).** `velocity_vorticity!(u, ω, û, …)` computes the physical velocity `u` and
  vorticity `ω` from `û`, named by its **outputs**; `scalar_to_physical!(φ, φ̂, …)` computes the physical
  scalar from `φ̂`, named by its **transformation direction** ("to physical"). Sibling spectral→physical
  recoveries, named two ways — one announces "physical", the other doesn't.
- **The question (later).** Pick one convention for the spectral→physical recoveries: name by outputs
  (then `scalar_to_physical!` loses its direction marker) or by direction (then `velocity_vorticity!`
  gains one). Ties to the user-facing naming policy.
- **Status.** collected — **design track, do not act on now.**

### D9 — Archive the OU (Eswaran–Pope `StochasticOU`) forcing; scrub public docs, keep only in the roadmap
- **You said**: *"Archive OU forcing for now, we will readd it later. Make sure not public docs mention
  it, only in the roadmap."*
- **The decision (a spec, not a question).** Remove `StochasticOU` from the public surface for now
  (re-add later): un-export it, remove every **public-doc** mention, and record it in the **roadmap**
  (`ARCHITECTURE.md`) as a deferred / to-re-add feature. Keep the implementation (archived) for the
  re-add.
- **Surfaces (from grep).** Un-export: `Forcing.jl` export line + `GBGIsotropicTurbulence.jl`
  re-exports. Scrub public docs: `notation.md` (2 OU rows), `index.md` (WIP note "Eswaran–Pope"),
  `api.md` (Forcing bullet), `api/Forcing.md` (`@docs` entry), the `Forcing` module docstring
  ("…`StochasticOU` are provided"), the `StochasticOU` type docstring, `architecture.md` public
  mentions. Keep-in-roadmap: an `ARCHITECTURE.md` roadmap/deferred entry (and decide whether the
  Eswaran–Pope 1988 §Reference moves there too, since no public doc would then cite it).
- **Status.** ✅ **DONE (executed 2026-07-11).** Un-exported `StochasticOU` (kept in `Forcing` —
  `isdefined(…Forcing, :StochasticOU)` true, `isdefined(GBGIsotropicTurbulence, :StochasticOU)` false);
  scrubbed public docs (Forcing module + `ForcingSpec` + `prepare_forcing!`/`forcing_source!`
  docstrings, `api.md`, `notation.md` 2 rows, `index.md` WIP note, `api/Forcing.md` prose + `@docs`
  block); moved to the `ARCHITECTURE.md` §7 roadmap and dropped the now-moot allocation-free exception.
  Verified green: load + **full test suite** (OU tests kept, `StochasticOU` imported into
  `test/forcing.jl` + `test/simulation_run.jl` from `…Forcing`) + docs build (checkdocs + both lints).
  **Lesson:** `docs/src/architecture.md` is a **gitignored copy** regenerated
  from **`docs/ARCHITECTURE.md`** (the canonical) by `copy_rationale_pages()` in `make.jl` — always
  edit `docs/ARCHITECTURE.md`; this is why earlier `architecture.md` edits appeared to "revert".

### D10 — `ForcingSpec` name: "why spec?" (SE abbreviation, not what it means)
- **You said** (`ForcingSpec`): *"Think about the name. Why spec?"*
- **The tension (facts).** `ForcingSpec` is a **deferred forcing** — the operator-free constructors
  (`Linear(; rate)`, `ConstantPower(; power)`, `BandRescaling(; energy)`) return one, materialised into
  a concrete `AbstractForcing` once the `SimulationDomain` exists. "Spec" is an SE abbreviation
  (specification), not what the object *means* to the user.
- **The question (later).** Rename for meaning — a forcing specified without a domain, built later:
  e.g. `DeferredForcing` / `ForcingRecipe` / `PendingForcing`. Ties to the user-facing naming policy
  (name by meaning; no SE-jargon or abbreviations).
- **Status.** collected — **design track, do not act on now.**

### D11 — `default_integrator()` exists, but no `default_forcing`/`default_dealiasing` (inline literals)
- **You asked** (`default_integrator`): *"Do we have default_something for other things? Like e.g.
  forcing/dealiasing?"*
- **The tension (facts).** **Verified:** only the integrator has a named default —
  `default_integrator() = IFLowStorageRK3()` (`TimeIntegration.jl:288`, exported). The **dealiasing**
  default is an inline literal `dealiasing = TwoThirds()` (`SimulationState.jl:84`,
  `SimulationRun.jl:51`); the **forcing** defaults are inline `velocity_forcing = BandRescaling(…)` /
  `scalar_forcing = NoForcing()` (`SimulationRun.jl:129–130`). No `default_dealiasing`/`default_forcing`.
- **The question (later).** Consistency: give every pluggable choice a discoverable `default_*`
  accessor, or none (inline for all). (Why the integrator has one: its default is reused by
  `recommended_cfl(integrator, domain)`; the others aren't.)
- **Status.** collected — **design track, do not act on now.**

### D12 — Discuss: is there (should there be) an accuracy control on the integration timestep?
- **You said** (`recommended_cfl`): *"Remind me to discuss if we have an accuracy knob on the
  integration timestep."*
- **Current state (verified).** The timestep is set by the **advective CFL** — a stability-calibrated,
  conservative coefficient (`recommended_cfl`; `IFLowStorageRK3` `C ≈ 0.5`), `Δt = C·Δx/max|u|`. A user
  can **override `cfl`** manually, but there is **no dedicated temporal-accuracy control** (no error
  tolerance, no setting that adapts the step for a target temporal error).
- **To discuss (later).** Whether to add a temporal-accuracy axis — an error-tolerance / order-based
  step control — distinct from the stability CFL ceiling. Precision and footprint are already studied
  fitness axes (`CLAUDE.md` invariant 4); temporal accuracy would be another.
- **Status.** collected — **design track / discussion item.**
