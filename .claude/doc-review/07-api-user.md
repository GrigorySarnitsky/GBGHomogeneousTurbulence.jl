# Panel review — hat: physicist-programmer / API user

Scope: assemble a `Simulation`, spin it up, observe with `run!`, read cached observables, sample
tracers — from the rendered docs alone. Checked: constructor arguments and defaults, argument
documentation completeness, return-shape clarity, the checked-read (throw) contract, example
correctness, and exported-vs-documented parity.

Overall: the exported-surface-vs-documented-surface check came back **clean** — every name in the
`GBGIsotropicTurbulence` API index has a matching docstring, and every constructor follows one
stated positional/keyword convention (source object positional, settings keyword) without
exception across all ~20 constructors inspected. The findings below are the residue: one
corpus-wide terminology leftover, and several smaller signature/contract asymmetries.

---

## Finding 1 — "Stamp" vocabulary survives in live prose after its own retirement

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: Home, Quick start comment: "each stamped with the epoch of the state they were computed from"
- PAGE: notation, Vocabulary/`epoch` entry: "the stamp it carries still equals the counter it depends on"
- PAGE: api / Cache, `ObservablesCache` Fields: "each slot carries a stamp, the counter's value at the moment that slot was filled... its stamp still equals the counter"; "each slot's stamp"; "the particle velocities' two stamps"
- PAGE: api / Cache, `deposit_sample!`: "this call stamps both from the cache's current counters"

**Contradicts:** PAGE: architecture, decision log (2026-08, "'Stamp' is retired"): "The `*_stamp` fields become `*_epoch`, and the verb goes with the noun — a deposit fills a slot and sets its epoch rather than 'stamping' it" — axis: the very vocabulary the decision retired.

**Description:** The decision log records that "stamp" was swept everywhere in favor of "epoch" (the field names are indeed `velocity_epoch`, `fields_epoch`, etc. throughout). Yet the word survives as live, current-state prose on four separate user-facing surfaces, including the very first page a new user reads (Home's quick-start walkthrough) and the glossary entry that is supposed to be the single canonical definition of "epoch." A reader is left holding two words for one concept exactly where the decision log says that confusion was fixed.

---

## Finding 2 — `deposit_sample!`'s return-type arrow names neither a type nor an argument

**Type:** format
**Severity:** minor
**Confidence:** high

**Locations:**
- PAGE: api / Cache: `deposit_sample!(cache) -> particle velocities`
- Contrast, same page/corpus: `advect!(...) -> tracers`, `interpolate_at_particles!(...) -> out`, `allocate_buffers(...) -> IntegratorBuffers`, `kolmogorov_length(fp) -> Float64`

**Description:** Every other `-> X` signature in the corpus names either a concrete Julia type (`Float64`, `Bool`, `IntegratorBuffers`) or the literal identifier of the returned/mutated argument (`-> rate`, `-> tracers`, `-> out`). `deposit_sample!(cache) -> particle velocities` does neither: the sole argument is `cache`, and "particle velocities" is a two-word English phrase, not backticked, not a type, not an identifier in scope. The body separately says "Returns the slot's array," so the arrow is redundant as well as off-convention — the one signature line in the corpus that breaks the pattern.

---

## Finding 3 — `velocity_rhs!` / `scalar_rhs!` order the consumed operand inconsistently

**Type:** clarity
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: api / Generator: `velocity_rhs!(N̂, generator, û, u, ω_consumed, domain)` — consumed arg (`ω_consumed`) last before `domain`
- PAGE: api / Generator: `scalar_rhs!(N̂, generator, û, φ̂, u_consumed, φ, domain)` — consumed arg (`u_consumed`) comes *before* the non-consumed physical field (`φ`)

**Description:** The two sibling right-hand-side assemblers place the destructively-consumed physical argument in opposite relative positions with respect to the read-only physical argument: `velocity_rhs!` reads non-consumed-then-consumed, `scalar_rhs!` reads consumed-then-non-consumed. Both docstrings note "the consumed argument is fixed by the physics, not by its position," which explains *which* argument is consumed but not why the pair does not share one positional convention the way `step!`/`deposit!` are explicitly documented to ("Call it with the same arguments in the same order as `deposit!`"). A caller who has memorized one signature has no positional cue for the other.

---

## Finding 4 — `stationary_dissipation` is the one `Scalings` evaluator without a return-type arrow

**Type:** format
**Severity:** nit
**Confidence:** medium

**Locations:**
- PAGE: api / phenomenology / Scalings: `stationary_dissipation(law, kinetic_energy, side_length)` — no `-> Type`
- Contrast, same page/module family: `scaling(law, fp) -> Float64`, and elsewhere `spectrum(...) -> Float64`, `structure_function(...) -> Float64`, `scaling_exponent(...) -> Float64`, `kolmogorov_length(fp) -> Float64`

**Description:** Every other pure evaluator in the `Phenomenology` submodules — including `Li2008`'s own `scaling` sibling on the very same page — carries a `-> Float64` signature annotation. `stationary_dissipation`, the seam the run layer actually calls to set viscosity, is the lone silent one, with no prose "Returns …" sentence to compensate.

---

## Finding 5 — `particle_velocities` breaks the tracer-accessor naming pattern it sits beside

**Type:** clarity
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: api / Particles: "Read the particle state with `particle_positions` and `number_of_particles`; the trajectory velocities are read from the run's observables cache, through `particle_velocities`"
- PAGE: api / Particles, `Tracers` Fields: "`particle_velocities` — the interpolated velocity at the positions the tracers occupy... the observables cache's particle-velocities slot"

**Description:** `particle_positions(tracers)` and `number_of_particles(tracers)` both take the tracer set, establishing a "call the accessor on `tracers`" pattern for particle state. `particle_velocities`, despite naming the same conceptual quantity and existing as `tracers.particle_velocities` (a genuine field on the same struct), is exposed as a function only over `particle_velocities(cache)` — the cache, not the tracer set. The docs do call this out in prose, so it is not silently wrong, but the surface itself is the odd one out among three sibling "read the particle state" accessors, and a reader pattern-matching from the first two will reach for `particle_velocities(tracers)`, which does not exist.

---

## Finding 6 — the front door's spectrum-matched IC option covers velocity only, with no documented scalar path or explanation

**Type:** api-gap
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: api / SimulationRun, `Simulation` Arguments: "`initial_spectrum = nothing` — draw the initial velocity from a `Phenomenology` `EnergySpectrum`..."; the scalar-related keywords are only "`scalar = false`, `scalar_variance = 1.0`"
- PAGE: api / State, `random_scalar_spectral!`: "Pass `spectrum`, a function κ ↦ E_φ(κ)... e.g. an Obukhov–Corrsin form from `Phenomenology`"

**Description:** The underlying primitive `random_scalar_spectral!` already supports spectrum-matched scalar initial conditions (mirroring the velocity seeder, per the docs' own cross-reference). The `Simulation` front door exposes this for the velocity (`initial_spectrum`) but has no equivalent keyword for the scalar, and nothing in the `Simulation` docstring says why, or shows the workaround (build via `Simulation(domain; ...)`, then call `random_scalar_spectral!` plus `fields_modified!`/`deposit!` by hand). This is not one of the recorded §7 deferrals, so a user wanting faster scalar warm-up via an Obukhov–Corrsin IC has no documented route from the front door.

---

## Finding 7 — `scalar_physical`'s "exactly `velocity_physical`'s contract" is immediately contradicted by an extra throw case

**Type:** clarity
**Severity:** nit
**Confidence:** low

**Locations:**
- PAGE: api / Cache: `scalar_physical` — "with exactly `velocity_physical`'s contract (the deposited field or a throw; never a recomputation; read-only). Throws an `ArgumentError` when the run carries no scalar."
- Same pattern: `particle_velocities` — "it serves the deposited values or throws an `ErrorException`, like every cached read... Throws an `ArgumentError` when the run advects no tracers."

**Description:** "Exactly" oversells the parity: `velocity_physical` has one failure mode (stale/scratch/never-deposited → `ErrorException`), while `scalar_physical` has that mode *plus* a second, structurally different one (no scalar in the run → `ArgumentError`) that `velocity_physical` cannot hit (a velocity slot always exists). The information given is correct and complete: the word "exactly" is simply stronger than the two sentences that follow it support.
