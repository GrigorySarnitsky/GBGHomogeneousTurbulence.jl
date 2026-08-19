# Doc-review panel — Hat: physicist-programmer / API user

Reviewing the rendered manuscript as a user who would assemble a `Simulation`, warm it up,
observe it with `run!`, read the cache, and sample along tracers — from the docs alone.

---

## Finding 1 — `Simulation`'s own docstring contradicts the architecture doc on whether `sim.tracers` is a reading surface

- **Type:** contradiction
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - `PAGE: api / SimulationRun`, `Simulation` Fields: *"Two of these are what a user reads — `state` and `cache`. The rest are the machinery the step runs on: … treat their contents as the scheme's business rather than the run's state."* — `tracers` is listed among "the rest."
  - `PAGE: architecture`, §4.7: *"The state is read through `sim.state` and the deposited observables through `sim.cache`, each by the accessor that owns it — `kinetic_energy(sim.state.velocity_spectral)`, `velocity_physical(sim.cache)`, `particle_positions(sim.tracers)`."*
  - `PAGE: api / Particles`, "Wiring tracers into a run" and the `Tracers` example both show `particle_positions(sim.tracers)` as the ordinary way to read tracer state.
- **Contradicts:** the SimulationRun API page says exactly two fields (`state`, `cache`) are user-facing and `tracers` is scheme-internal machinery "read only between steps"; the architecture doc and the Particles page treat `sim.tracers` as a third, parallel, first-class accessor-owned reading route exactly like `sim.state`/`sim.cache`.
- **Description:** A user reading only the `Simulation` API page would conclude that reaching into `sim.tracers` is unsupported/internal, then find every worked example in the corpus doing exactly that. One of the two claims needs to be reconciled — either `Simulation`'s Fields section should list `state`, `cache`, *and* `tracers` (with `trajectory_scheme`/`particle_buffers`/`buffers`/`generator`/`scheme` as the true "read only between steps" machinery), or the examples are wrong.
- **Resolution hint:** Fold `tracers` into the "what a user reads" sentence; keep `domain`, `buffers`, `generator`, `scheme`, `trajectory_scheme`, `particle_buffers` as the internal-machinery group.

---

## Finding 2 — `deposit_sample!`, required by the documented hand-run particle-repositioning recipe, is never documented or indexed anywhere

- **Type:** api-gap
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - `PAGE: api / Cache`, `particles_modified!`: *"A hand-run loop that repositions tracers itself must call this, then `record_particle_velocity!` to write the new values, and finally `deposit_sample!` to record them at the current epochs."*
  - `PAGE: api / Particles`, `record_particle_velocity!`: *"the slot becomes readable when the cache is then told the values are current, which is a second call the cache owns"* — the "second call" is never named here either.
  - `PAGE: api / GBGIsotropicTurbulence` Index (the complete export list, lines ~1045–1125): no `deposit_sample!` anywhere.
- **Description:** The Cache page's own checked-read contract tells a user following the documented out-of-band tracer-repositioning recipe to call `deposit_sample!` as the final, required step. That name occurs exactly once in the whole corpus and is absent from the package's complete public index, from the Particles page's own function list, and from the Propagator page's `deposit!` docstring (which explicitly says the particle-velocities slot is *not* among what `deposit!` fills). A user cannot find this function's signature, confirm it is public, or complete the documented procedure.
- **Resolution hint:** Either export and document `deposit_sample!` where the other Particles/Cache verbs live, or replace the two vague references with the actual call a user should make.

---

## Finding 3 — `BandRescaling` is the one forcing constructor missing a per-argument `Arguments` list

- **Type:** format
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - `PAGE: api / Forcing`, `Linear` and `ConstantPower` each carry an explicit bulleted `Arguments` section naming `domain`, the rate/target keyword, and `lowest_shell`/`highest_shell` individually.
  - `PAGE: api / Forcing`, `BandRescaling(domain; target, over, lowest_shell = 1, highest_shell = 2)` has no such section — `domain`, `lowest_shell`, and `highest_shell` are only mentioned in running prose ("the integer shells `lowest_shell` to `highest_shell`… built on the `FixedDomain` `domain`").
- **Description:** All three constructors take the same shape of arguments (`domain`, a required target/rate keyword, a shell band), and two of the three enumerate every argument in a dedicated list per the corpus's own self-containedness rule ("every signature argument documented — enumerated from the signature, each its own entry"). `BandRescaling`'s prose covers `target` and `over` at length but leaves `domain`/`lowest_shell`/`highest_shell` unenumerated, breaking the sibling family's formatting parity.
- **Resolution hint:** Add the same `Arguments` bullet block `BandRescaling` is missing, reusing `Linear`'s wording for `domain`/`lowest_shell`/`highest_shell`.

---

## Finding 4 — The `ArgumentError` a user hits inside `FlowConditions(...)` is documented only on a different page

- **Type:** api-gap
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - `PAGE: api / Forcing`, `AbstractForcing`: *"A strategy holding per-field scratch or a random stream must not drive both fields from one instance… `FlowConditions` throws an `ArgumentError` rather than let that happen."*
  - `PAGE: api / Generator`, `FlowConditions(; viscosity, schmidt, velocity_forcing, scalar_forcing)`: no mention of this throw condition anywhere in its own docstring.
- **Description:** The error actually fires inside `FlowConditions`'s constructor, which is where a user would hit it (passing the same stateful forcing instance for both `velocity_forcing` and `scalar_forcing`), but the explanation of *why* and *when* lives only in `AbstractForcing`'s docstring on a different page. Per the corpus's own rule ("the checked-read contract documented where a user will hit it"), this belongs on (or is at least cross-referenced from) `FlowConditions`.
- **Resolution hint:** Add a one-line note to `FlowConditions` pointing at the shared-instance restriction, or `@ref` it from there.

---

## Finding 5 — The stated `viscosity`/`κ_max_η` mutual-exclusivity contract is hard to reconcile with `κ_max_η`'s always-present default

- **Type:** clarity
- **Severity:** minor
- **Confidence:** low
- **Locations:**
  - `PAGE: api / SimulationRun`, `Simulation`: signature shows `κ_max_η = 2` as an ordinary default (always present), while the prose says *"Explicit mode: pass `viscosity` and it is used directly; the two are alternatives, and passing both raises an `ArgumentError` rather than dropping one."*
- **Description:** Since `κ_max_η` is shown with an ordinary Julia default of `2` (not a `nothing` sentinel), nothing in the documented signature lets a reader tell "the user explicitly wrote `κ_max_η = 2`" apart from "the user omitted it and the default applied" — yet the docs describe an error path that depends on exactly that distinction ("passing both"). As written, a reader cannot tell whether providing `viscosity` alone is safe (most likely, and probably what happens) or whether it is expected to collide with the ever-present default. This is a documentation clarity gap rather than a demonstrated code bug.
- **Resolution hint:** State explicitly that the check is really "is `viscosity` given," with `κ_max_η` simply unused/ignored in that case, if that is the real behavior — rather than describing it as a symmetric "passing both" case.

---

*Not flagged (already adjudicated as non-defects): `kinetic_energy` default of 1.5, Saffman attribution, decision-log entries naming superseded APIs, absence of the deferred capabilities, `vorticity_spectral(sim)` non-existence, `Lundgren2002` citation, `deposit_velocity!`/`take_velocity!` existing as undocumented internals, the host-device-sync floor-vs-achieved pair, `integrator`→`scheme`, PascalCase composed presets, `No DOI`/`no DOI` capitalization, bare `CatmullRom`, the arrow-vs-`Returns` dual convention, and a citation opening a docstring ahead of its formula.*
