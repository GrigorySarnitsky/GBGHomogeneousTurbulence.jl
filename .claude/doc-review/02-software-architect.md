# Software Architect review — GBGIsotropicTurbulence rendered docs

Hat: senior Julia programmer / software architect, judging the documented API and design as written.

---

## 1. `tracer_scheme` (Simulation front door) renames `interpolation_scheme` (Tracers) across one forwarding hop, and sits beside a same-shaped sibling keyword for an unrelated axis

**Type:** design | **Severity:** major | **Confidence:** high

**Locations:**
- PAGE: api / SimulationRun — `Simulation`: "`number_of_particles = 0`, `tracer_scheme = CatmullRom` — the number of Lagrangian `Tracers` and the spatial scheme that evaluates a field at their positions, forwarded to the `Tracers` constructor as its `interpolation_scheme`."
- PAGE: api / SimulationRun — `Simulation`: "`particle_scheme = EndpointHeun()` — the temporal scheme that advances the trajectories, a different axis from `tracer_scheme` despite the neighbouring names."
- PAGE: architecture — decision log, "`integrator` → `scheme` on the binding": "`Tracers` used `scheme` for its interpolation scheme, so two constructors would have taken one keyword for two concepts; it is now `interpolation_scheme`, which is the more precise name regardless."

**Description:** The decision log records a deliberate rename of `Tracers`' own keyword to `interpolation_scheme` specifically for precision. Yet the `Simulation` front door does not reuse that name for the pass-through — it introduces a third name, `tracer_scheme`, for the identical concept, then places `particle_scheme` (a wholly different, temporal-integration axis) one keyword away, defended only by a docstring caveat ("despite the neighbouring names"). A user now must hold three names for two concepts (`interpolation_scheme` / `tracer_scheme` for one; `particle_scheme` for the other) where the project's own naming discipline (six-lens panels, `ω_consumed`/`u_consumed`, `*_epoch`) argues for reusing the precise name at every hop.

**Resolution hint:** Rename the front-door keyword to `interpolation_scheme` (matching `Tracers`), removing the need for the disclaimer prose.

---

## 2. `advect!`'s argument order breaks the shared `state, domain, buffers` order that `step!`/`deposit!` are explicitly designed to share

**Type:** design | **Severity:** major | **Confidence:** high

**Locations:**
- PAGE: api / Propagator — `step!`: "The argument order is shared with `deposit!` ... the common arguments follow in the fixed order `state`, `domain`, `buffers` ... so the chained pair transposes nothing."
- PAGE: api / Propagator — `step!(scheme, state, generator, domain, buffers, cache, dt)`; `deposit!(cache, state, domain, buffers)`.
- PAGE: api / Particles — `advect!(scheme, tracers, buffers, velocity_end, domain, dt)`.

**Description:** `step!`/`deposit!` place `domain` before `buffers`, a design choice the docs call out by name as intentional ("transposes nothing"). `advect!` — introduced as "the Lagrangian counterpart of the field schemes," built on the identically-named `allocate_buffers` and an explicitly parallel `AbstractParticleIntegrator`/`ParticleIntegratorBuffers` pair — places `buffers` before `domain`, the opposite order. The one place the docs advertise cross-signature order discipline is exactly the place a parallel signature violates it.

**Resolution hint:** Reorder `advect!` to `(scheme, tracers, velocity_end, domain, buffers, dt)` or state why the particle side is exempt from the shared-order rule.

---

## 3. `Simulation`'s fields expose internal per-step scratch (`buffers`, `generator`) at the same access level as the sanctioned reading surfaces

**Type:** design | **Severity:** major | **Confidence:** medium

**Locations:**
- PAGE: architecture — decision log: "A `Simulation` is a container, not a reading surface... The state is read through `sim.state` and the deposited observables through `sim.cache`... each read by the accessor that owns it."
- PAGE: api / SimulationRun — `Simulation` Fields: "`domain`, `buffers`, `generator`, `scheme`... `state`... `cache`... `tracers`, `particle_scheme`, `particle_buffers`..."
- PAGE: api / Propagator — `IntegratorBuffers`: "Each such array is a register: storage a scheme computes one stage into and overwrites at the next, holding nothing a caller should read between steps."

**Description:** The "container, not a reading surface" decision deliberately rejects forwarding accessors in favor of direct field access as the package's whole read API. But `sim.buffers` and `sim.generator` are listed as ordinary fields alongside `sim.state`/`sim.cache`/`sim.tracers`, with no distinction in the type itself between a safe read (`state`, `cache`, `tracers`) and a stage register explicitly documented elsewhere as unsafe to read between steps. Julia field access carries no visibility distinction, so a user tab-completing `sim.` meets `buffers` and `generator` on equal footing with the reads the design intends to sanction.

**Resolution hint:** Either note directly on `Simulation`'s docstring which fields are unsafe to read mid-run, or keep them out of the field list a user is pointed at.

---

## 4. "One forcing instance per forced field" is enforced only by a documentation warning, unlike the package's demonstrated throw-on-misuse pattern

**Type:** design | **Severity:** major | **Confidence:** medium

**Locations:**
- PAGE: api / Forcing — `AbstractForcing`: "WarningConstruct one strategy instance per forced field. An instance owns per-field scratch and internal state, so passing the same instance as both `velocity_forcing` and `scalar_forcing` would silently conflate the two fields' bookkeeping."
- PAGE: api / Generator — `ResolvedGenerator`: "The constructor rejects a misdeclared forcing... Building a `ResolvedGenerator` around one throws an `ArgumentError` naming the strategy, rather than let the run proceed quietly wrong."

**Description:** The package elsewhere validates forcing configuration aggressively at construction (a forcing declaring `set_forcing_rate!` without `uses_linear_rate` throws, "rather than let the run proceed quietly wrong"). The reused-instance hazard is at least as easy to trigger by accident (`Simulation(...; velocity_forcing = f, scalar_forcing = f)`) and is documented as producing silent, wrong bookkeeping — yet nothing in the constructors checks for it. The one invariant most likely to be violated by a naive call site is the one left to prose.

**Resolution hint:** Have `ResolvedGenerator`'s constructor (or `FlowConditions`) reject `velocity_forcing === scalar_forcing` (identity check) with the same `ArgumentError` discipline used for the rate-declaration mismatch.

---

## 5. `FlowParameters.scalar_dissipation` uses a `NaN` sentinel, diverging from the `nothing`-sentinel convention used everywhere else for "this run lacks X"

**Type:** design | **Severity:** minor | **Confidence:** medium

**Locations:**
- PAGE: api / phenomenology / Phenomenology — `FlowParameters`: "`scalar_dissipation`... default `NaN` for a run that carries no scalar. `NaN` rather than `nothing` keeps the bundle a plain, type-stable set of `Float64`s. It is a sentinel, not a value that propagates: every law that reads the field checks it first and throws an `ArgumentError`..."
- PAGE: api / Cache — `ObservablesCache` Fields: "`scalar_physical` — the cached scalar in physical representation, or `nothing` for a scalar-free run."
- PAGE: api / Propagator — `IntegratorBuffers` Fields: registers left `nothing` when a scheme or config doesn't use them.

**Description:** Every other "absent because this run/config doesn't carry the capability" slot in the documented API — cache slots, integrator/particle buffers, `Tracers`/`particle_scheme` on a tracer-free `Simulation` — uses `nothing`. `FlowParameters` alone substitutes `NaN`, and its own docstring's guarantee ("not a value that propagates") holds only for the bundled `Phenomenology` law implementations, which check first; it does not hold for a caller doing ordinary arithmetic on `fp.scalar_dissipation` directly, where a `NaN` propagates silently exactly as the docstring says it does not. The type-stability argument is real, but it is applied at the one site with the least performance pressure (a per-run diagnostic bundle) while the actual hot-loop structs (`IntegratorBuffers`, `ResolvedGenerator`) use `Union{Nothing,T}` freely.

**Resolution hint:** Either scope the "does not propagate" claim explicitly to the `Phenomenology` evaluators, or use a small dedicated sentinel/`missing` with the same check-first contract stated package-wide.

---

## 6. The `Cache` module's central epoch invariant is written exclusively by `deposit!`, which is homed in `Propagator`, not `Cache`

**Type:** design | **Severity:** minor | **Confidence:** medium

**Locations:**
- PAGE: api / Cache — module docstring: "The solver's side of the contract is `deposit!` — homed in `Propagator`, with the iteration it closes — which fills every slot at the iteration's end and sets its epoch; internal per-slot deposit and take verbs move the individual epochs."

**Description:** `Cache` is presented as the module owning the deposit-driven design (three-valued epochs, slot=register merge, throw-on-stale). But the one function that actually advances a slot's epoch to "deposited" — the write side of the whole invariant — lives in a different module. The type that owns the storage and its read contract does not own its writer; a reader auditing `Cache` alone cannot see what makes a read valid. This is presumably forced by the include order (`Cache` precedes `Propagator`, and `deposit!` needs a scheme-agnostic notion of "the state the step just produced"), but the docs do not say so — they simply note the split.

**Resolution hint:** State the include-order reason for the split on `Cache`'s module docstring, or move the completeness/epoch-advance logic into a `Cache`-owned verb that `Propagator.deposit!` calls.

---

## 7. `ObservablesCache.particle_velocities` is externally-owned aliased storage, unlike every other slot the type allocates itself

**Type:** design | **Severity:** minor | **Confidence:** medium

**Locations:**
- PAGE: api / Cache — `ObservablesCache`: "pass ... `particle_velocities` — the tracer set's own point-value storage — when the run advects tracers: the slot IS that storage, so the tracers' push writes the values and the cache only records which epochs they belong to."

**Description:** `velocity_physical`, `vorticity_physical`, and `scalar_physical` are arrays the `ObservablesCache` constructor allocates and owns outright. The `particle_velocities` slot is instead a handed-in reference into `Tracers.trajectory_velocity` — the cache never allocates it and cannot itself guarantee it stays valid; correctness depends on `Particles`' own mutator (`record_trajectory_velocity!`) writing through the same array a well-behaved caller passed in. Within one type, most slots are self-contained value storage and one is a live alias into another module's object — an ownership split that is real (and reused deliberately for the "slot IS the register" design elsewhere) but is easy to miss when reasoning about what "the cache" actually holds.

**Resolution hint:** No code change implied; consider naming the asymmetry explicitly in the type's opening paragraph rather than only in the constructor's keyword description.

---

## 8. `k_max_η` mixes an ASCII-folded κ with a literal Unicode η, contradicting its own "spelled in ASCII" claim

**Type:** clarity | **Severity:** nit | **Confidence:** medium

**Locations:**
- PAGE: api / SimulationRun — `Simulation`: "`k_max_η = 2` — the resolution criterion $\kappa_{\max}\eta$ used to set $\nu$ in grid mode (the keyword spells $\kappa_{\max}$ in ASCII)".

**Description:** The parenthetical explains why κ became `k` (ASCII-friendliness for a REPL keyword), but the same keyword keeps `η` as a literal Unicode codepoint, requiring the same `\eta<tab>` REPL input the ASCII substitution was presumably meant to avoid. The identifier is neither fully ASCII nor fully symbolic — a half-transliteration the docstring's own justification doesn't quite cover.

**Resolution hint:** Either fold η too (`k_max_eta`) or drop the "spelled in ASCII" framing in favor of "κ is spelled `k`; η is kept as-is."

---

## 9. `Simulation`'s explicit mode silently ignores `k_max_η` when `viscosity` is also given

**Type:** design | **Severity:** minor | **Confidence:** medium

**Locations:**
- PAGE: architecture — decision log, "Resolution-based `viscosity`": grid mode vs explicit mode described, with `viscosity` opting "back into direct control."
- PAGE: api / SimulationRun — `Simulation`: "Explicit mode: pass `viscosity` and it is used directly (`k_max_η` is ignored)".

**Description:** Passing both `viscosity` and a non-default `k_max_η` produces no error and no effect on the ignored keyword — it is simply dropped. This is the opposite of the package's demonstrated stance elsewhere (a misdeclared forcing rate throws `ArgumentError` "rather than let the run proceed quietly wrong"; `BandRescaling`'s `over` was made required specifically because a silent default "made that choice for a user who might be measuring exactly the clamped quantity"). A user who sweeps `k_max_η` in an experiment while also fixing `viscosity` for reproducibility gets silently ignored input.

**Resolution hint:** Warn (or throw) when both `viscosity` and a non-default `k_max_η` are supplied together.

---

## 10. The four `AbstractForcing` hooks reuse the parameter name `field` for three physically distinct instants

**Type:** clarity | **Severity:** minor | **Confidence:** medium

**Locations:**
- PAGE: api / Forcing — `prepare_forcing!(forcing, field, domain, dt)`: "from the start-of-step `field` (in spectral representation)".
- PAGE: api / Forcing — `set_forcing_rate!(forcing, rate, field, domain)`: "The `field` is the start-of-step field in spectral representation".
- PAGE: api / Forcing — `apply_forcing!(forcing, field, domain)`: "Apply the strategy `forcing`'s post-step projection to `field`... in place".

**Description:** `prepare_forcing!` and `set_forcing_rate!` both name their argument `field` and mean the start-of-step value; `apply_forcing!` names its argument `field` too but means the just-advanced, post-step value — a different array at a different point in the lifecycle. The four-hook interface is pitched as one uniform per-step lifecycle ("the four hooks form one per-step lifecycle with a fixed order"), and the reused name invites a reader implementing a new strategy to assume all `field` arguments are interchangeable in timing, when only two of three actually are.

**Resolution hint:** Distinguish the post-step argument, e.g. `apply_forcing!(forcing, advanced_field, domain)`.
