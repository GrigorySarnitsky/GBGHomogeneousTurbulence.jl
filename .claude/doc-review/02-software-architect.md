# Software-architect review — GBGIsotropicTurbulence rendered docs

Hat: senior Julia programmer / software architect, judging the documented API and module design as written (no source read).

---

## Finding 1 — `StationarityCriterion`'s documented positional constructor exposes an internal object and admits it

**Type:** contradiction · **Severity:** major · **Confidence:** high

**Locations:**
- PAGE: api / SimulationRun — "The plain constructor `StationarityCriterion(monitor, max_turnovers, gate_scalar, elapsed_turn, last_time, started)` is internal. Note the keyword arguments above do not map one-to-one onto these fields: `gate_skewness`, `min_turnovers`, `window_turnovers`, `tol` and `skew_floor` are all stored inside `monitor`, which holds the sampled series together with the thresholds that judge them."

**Description:** The rendered API page documents the type's plain positional constructor in full — a labelled, code-fenced signature, exactly like every other type's constructor on the site — and then immediately states that this same form "is internal" and that its parameters do not correspond one-to-one with the keyword constructor a caller actually wants. Publishing a constructor signature on the public docs page while telling the reader not to use it is self-contradictory documentation: a reader skimming the signature block (as the "Fields" convention used throughout the rest of the corpus trains them to do) has no cue, short of the trailing prose, that calling it would require hand-assembling an opaque `monitor` object. Every comparable "assembled-from-preallocated-internals" type elsewhere in the corpus (`Simulation`, `ObservablesCache`, `IntegratorBuffers`, `ResolvedGenerator`) instead omits the positional form entirely; `StationarityCriterion` is the one place the corpus's own pattern is broken.

**Resolution hint:** Either drop the positional-constructor line from the rendered page (matching `Simulation`/`ObservablesCache`/`IntegratorBuffers`/`ResolvedGenerator`) or replace it with a `# Fields` list that documents `monitor`'s role without presenting a callable signature.

---

## Finding 2 — The opportunistic `displaced_velocity_fresh` flag reopens the class of hazard the generator reification was built to close

**Type:** contradiction · **Severity:** major · **Confidence:** medium

**Locations:**
- PAGE: architecture, §4.2 / decision log — "A scheme consumes the physics only through this protocol, so it can never assemble the right-hand side from a mismatched intermediate — the class of the stage-ordering bug that motivated the reification (§11 decisions 29, 31)."
- PAGE: api / Generator, `ResolvedGenerator` — "One optimization crosses two verbs. Under `PhaseShift`, `velocity_rhs!` leaves the stage's displaced velocity fresh for the same stage's `scalar_rhs!` to reuse, through the `displaced_velocity_fresh` flag rather than through either signature."

**Description:** The generator's six-verb protocol was reified specifically so a scheme could never observe a stale or mismatched intermediate across two verb calls (the RK3 stage-ordering bug the decision log names as the motivating incident). The `displaced_velocity_fresh` flag reintroduces exactly this shape: `scalar_rhs!`'s cost and correctness path now depend on whether `velocity_rhs!` was called immediately before it in the same stage, tracked by mutable state hidden on the `ResolvedGenerator` rather than by either function's signature. The self-healing fallback ("a `scalar_rhs!` that finds the flag clear rebuilds the displaced velocity itself, value-identically") keeps it correctness-safe, but it is still an undocumented-in-the-signature, call-order-sensitive side channel between two protocol verbs — the very pattern the protocol's own charter says it makes "unrepresentable."

**Resolution hint:** Either surface the freshness dependency in `scalar_rhs!`'s signature (an optional argument or a documented calling contract), or note explicitly, next to decision 31's "never a mismatched intermediate" claim, that this one opportunistic exception exists.

---

## Finding 3 — `deposit!`, the cache's only writer, is undocumented in `Cache`'s own operation list and lives in a different module

**Type:** organization · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / Cache — "The cache's operations: `ObservablesCache` …; `fields_modified!`, `particles_modified!` …; `velocity_physical`, `vorticity_physical`, `scalar_physical` …; `max_speed` …" (four bullets, all reads or an announce-mutation pair — no `deposit!`).
- PAGE: api / Cache — "The solver's side of the contract is `deposit!`, which fills every slot at the iteration's end and sets its epoch. … It is homed in `Propagator` rather than here because it needs the scheme's own scratch to recover the fields, and that is the module owning the iteration it closes."

**Description:** `Cache`'s module docstring is a map ("the cache's operations") that lists every read accessor and both "announce a mutation" verbs, but omits the one function that actually fills the type it defines. A reader who wants to know "how does something get into this cache" is not served by `Cache`'s own bullet list at all — the answer surfaces only in prose several paragraphs later, pointing to a different module three steps downstream in the include order. The write half of `ObservablesCache`'s API is consequently split across two module pages with no forward pointer from `Cache`'s bullet list to `Propagator.deposit!`.

**Resolution hint:** Add `deposit!` (with an `@ref`-style pointer to its home) to `Cache`'s own bullet list, even though the implementation stays in `Propagator`.

---

## Finding 4 — `velocity_rhs!`/`scalar_rhs!`'s "consumed" arguments are, at real call sites, the cache's live deposited slots — protected only by a naming convention

**Type:** api-gap · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / Generator — "`velocity_rhs!(N̂, generator, û, u, ω_consumed, domain)` … The vorticity argument is read and then overwritten. The Lamb vector is formed in place over the vorticity's array — the backend's cross product may write into one of its operands — so `ω_consumed` must hold the vorticity on entry and no longer does on return."
- PAGE: api / Propagator, `step!` — "The first stage reads the deposited velocity, vorticity, and scalar in physical representation from `cache` … and the later stages compute their recoveries into those same slots."

**Description:** `velocity_rhs!` and `scalar_rhs!` are public, exported functions (`GBGIsotropicTurbulence.Generator.velocity_rhs!`/`scalar_rhs!` in the Index). Inside `step!` their `ω_consumed`/`u_consumed` arguments are literally `cache.vorticity_physical`/`cache.velocity_physical` — the same array a concurrent call to `vorticity_physical(cache)`/`velocity_physical(cache)` would otherwise serve as a checked, currently-valid deposited observable. A caller who invokes the generator protocol directly (the docs advertise "the composable pieces stay fully exposed" for exactly this kind of hand-rolled use) and passes the array returned by `vorticity_physical(cache)` — reasonably assuming a read-only "give me the vorticity" call — will silently destroy the cache's current deposit as a side effect. Nothing in the type system distinguishes a "safe to pass" array from a "will be destroyed" one; the `_consumed` suffix is the only guard, and it protects only a reader who already reads the docstring.

**Resolution hint:** Consider a distinguishing wrapper type (or at minimum a bold caveat on `vorticity_physical`/`velocity_physical` themselves cross-referencing the destructive consumers) so the hazard is visible at the read site, not only at the write site.

---

## Finding 5 — `max_speed(u)` / `max_speed(cache)`: one generic spans an O(N³) reduction and an O(1) cached read, and the pattern is declared the template for future observables

**Type:** design · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / Observables, `max_speed` — "`max_speed(u)` / `max_speed(cache)` … The second form reads the number back from an `ObservablesCache`, where the closing deposit left it — the same quantity, measured once per iteration and served without a reduction (or a device readback)."
- PAGE: architecture, decision log (2026-08, "`Observables` precedes `Cache`") — "an observable with both a measurement and a cached value is one generic with two method families … the pattern is the rule for any future cached observable."

**Description:** Calling `max_speed` on a field sweeps the whole grid (an O(N³) reduction); calling it on a cache performs an O(1) array lookup that can throw if the deposit is stale. Both share one name and are selected only by argument type, so a call site's cost class is invisible from the call itself — a reader must know which argument they hold. This is workable for one observable, but the decision log states this dispatch shape is now the house pattern for *every future* observable that gains a cached form, meaning the corpus is set to accumulate more same-name, differently-costed, differently-failure-mode method pairs over time rather than fewer.

**Resolution hint:** None required to fix `max_speed` itself (already shipped and reasoned about), but worth flagging before the pattern is applied a second and third time — a distinguishing verb (`max_speed!`/`cached_max_speed`) would make the cost class visible at the call site.

---

## Finding 6 — `Tracers`'s two constructor forms are merged into one method, disambiguated only by a runtime `ArgumentError`

**Type:** design · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / Particles, `Tracers` — "(One method, shown as the two ways it is called — keywords do not dispatch.) … Give exactly one of `number_of_particles` … or `positions` … Supplying both, or neither, is an `ArgumentError`."
- PAGE: architecture, decision log (2026-08-18, "Constructor arguments") — "keyword arguments do not participate in dispatch, so two all-keyword forms cannot be two methods. `Tracers` is therefore a single method requiring exactly one of `positions` or `number_of_particles`, with an `ArgumentError` naming the choice — a better error than a missing-keyword one, but a merge forced by the language rather than preferred."

**Description:** Two conceptually distinct construction paths — "seed `M` random tracers" versus "wrap these positions" — are collapsed into a single method whose branch is chosen by which keyword happens to be non-`nothing`, checked at run time. The docs candidly call this "a merge forced by the language rather than preferred," which is honest, but the result is still weaker than ordinary Julia dispatch: a caller who typos `position` instead of `positions` gets "neither supplied" rather than a `MethodError`/`UndefKeywordError` pointing at the typo, and there is no compile-time signal distinguishing the two call shapes. A small dispatchable seed-selector value (e.g. two argument types instead of two keywords) would restore ordinary multiple-dispatch behavior at the cost of one more exported name.

---

## Finding 7 — `FlowConditions` and `FlowParameters`: near-identical names sharing two field names, flagged as confusable in the docs and left as-is

**Type:** clarity · **Severity:** nit · **Confidence:** low

**Locations:**
- PAGE: api / Generator, `FlowConditions` — "Not to be confused with `Phenomenology`'s `FlowParameters`, which shares two field names: this type holds what a run is configured with, that one holds what a run has been measured to have."

**Description:** Two types eight letters apart in name (`FlowConditions` vs `FlowParameters`), living in different modules, sharing the field names `viscosity` and `schmidt`, are distinguished only by a parenthetical disclaimer inside one of the two docstrings — a reader who meets `FlowParameters` first has no matching cross-reference back. Given how much naming care the rest of the corpus invests in disambiguating near-neighbors (`particle` vs `tracer`, `epoch` vs `stamp`, `scheme` vs `integrator`), this pair reads as a residual case the same discipline has not yet reached.

---

## Finding 8 — The cached-vs-measured duality has two different, module-crossing resolutions depending on whether the observable is scalar- or field-valued

**Type:** design · **Severity:** nit · **Confidence:** low

**Locations:**
- PAGE: api / Observables — "`max_speed` — the fastest flow speed on the grid … (one generic shared with `Cache`, where the cached read lives …)" versus "`vorticity_physical!` — the vorticity recovered in physical representation … (its cached read, `vorticity_physical`, lives in `Cache`)."
- PAGE: architecture, decision log (2026-08, "The chart recoveries are not package verbs") — "an f/`f!` pair, not decision 46's single dispatched generic, and the difference is structural rather than a drift."

**Description:** A scalar observable with both a live and a cached form (`max_speed`) is one generic dispatching on argument type; a field-valued observable with both forms (`vorticity_physical!`/`vorticity_physical`) is instead an `f`/`f!` pair, with the two halves living in two different modules (`Observables` and `Cache`). The docs explicitly defend the split as principled rather than accidental, which the panel takes at face value — but the practical result is that a future contributor adding a new cached observable must first classify it as scalar or field-valued before knowing which of two unrelated naming/module patterns to follow, a piece of tacit knowledge not stated as a rule anywhere a newcomer would find it before hitting the two examples.
