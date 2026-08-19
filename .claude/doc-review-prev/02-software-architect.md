# Software-architect review — GBGIsotropicTurbulence rendered docs

Hat: software architect / senior Julia programmer, judging the *documented* API and design.

---

## 1. The `Cache` module page misattributes `deposit!` to its own module, then contradicts itself

**Type:** contradiction · **Severity:** major · **Confidence:** high

**Locations:**
- PAGE: api / Cache, "The cache's operations" bullet list: `` `deposit!`, `deposit_sample!` — the writers: the first fills every field slot at the iteration's end, the second records the particle velocities the tracer advance wrote. ``
- Same page, a few paragraphs later: "That verb lives in `Propagator` rather than here because it needs the scheme's own scratch to recover the fields."

**Contradicts:** the module's own operations list presents `deposit!` as a `Cache` operation; the prose on the same page (and the API index, which lists `deposit!` only under `Propagator`) says it is not.

**Description:** A module docstring is supposed to be a map of what that module contains. Here the map lists `deposit!` as one of "the cache's operations" alongside `deposit_sample!` (which genuinely is a `Cache` function), then the page's own later prose says the opposite — the verb "lives in `Propagator`". A reader skimming the bullet list (the intended fast path) comes away believing `Cache.deposit!` exists; it does not.

---

## 2. `displaced_velocity_fresh` reintroduces the exact cross-verb ordering coupling the generator reification was built to eliminate

**Type:** api-gap · **Severity:** major · **Confidence:** medium

**Locations:**
- PAGE: api / Generator, `ResolvedGenerator`: "Under `PhaseShift`, `velocity_rhs!` leaves the stage's displaced velocity fresh for the same stage's `scalar_rhs!` to reuse, through the `displaced_velocity_fresh` flag."
- PAGE: architecture, decision "The generator reified": "the scheme does only stage arithmetic, so it can never assemble the right-hand side from a mismatched intermediate."

**Contradicts:** the stated architectural guarantee that a reified generator makes a "stage that reads a mid-update intermediate" — "a malformed factorization" — unrepresentable.

**Description:** The flag makes `scalar_rhs!`'s behavior depend on whether `velocity_rhs!` ran first in the same stage — an implicit ordering precondition encoded in neither signature, mediated by a hidden boolean on shared mutable state. The docs call it "opportunistic, never load-bearing" (a stale flag rebuilds correctly), which prevents wrongness but not the coupling itself: this is the same class of bug (decision "the RK3 stage ordering") the reification claims to have made structurally impossible.

---

## 3. `step!` and `deposit!`'s "same argument order" claim conflates a dispatch tag with a mutated object

**Type:** api-gap · **Severity:** major · **Confidence:** medium

**Locations:**
- PAGE: api / Propagator, `step!`: "the dispatch object first, then `state`, `domain`, `buffers` ... so the two calls of a hand-run loop read as a pair."
- PAGE: api / Propagator, `deposit!`: "the mutated dispatch object leads, and `state`, `domain`, `buffers` follow."

**Contradicts:** `step!(scheme, state, ...)`'s leading argument (`scheme`) is a stateless dispatch tag — `state` (second) is what is mutated and returned. `deposit!(cache, state, ...)`'s leading argument (`cache`) genuinely is the mutated, returned object. The phrase "mutated dispatch object" describes both as one role when they are two different roles.

**Description:** Julia's `!`-convention is "the mutated argument leads." `step!` breaks it (mutated `state` is second) for a defensible reason (dispatch needs `scheme` first); `deposit!` follows it. Presenting the two signatures as "the same order" for a "read as a pair" hand-run loop papers over that a reader relying on the stated parallel would misidentify which argument `step!` actually mutates.

---

## 4. Grid-mode viscosity selection silently assumes the default forcing pins `k`; nothing in `Simulation`'s own docstring states the cross-argument precondition

**Type:** api-gap · **Severity:** major · **Confidence:** medium

**Locations:**
- PAGE: architecture, decision "`BandRescaling`'s `over` is required": "in grid mode the front door chooses $\nu$ from the assumed kinetic energy ... self-consistent only if the run really holds $k$ at that value, which is precisely what `:total` guarantees and `:band` does not."
- PAGE: api / SimulationRun, `Simulation`, "Grid mode" paragraph and Arguments list for `velocity_forcing`: no statement that grid mode is unsound if `velocity_forcing` is changed away from a `:total`-holding strategy.

**Description:** The decision log names a load-bearing precondition — grid mode's $\nu$ choice is only physically consistent when the run's stationary $k$ equals `kinetic_energy`, guaranteed by the default `BandRescaling(:total)` and not by `ConstantPower` or a hand-built forcing. Nothing on the `Simulation` API page (Arguments, or the "Grid mode" prose) surfaces this: a caller reading only the constructor's own docstring can pair grid mode (omit `viscosity`) with `velocity_forcing = ConstantPower(...)` and get a silently miscalibrated $\nu$.

---

## 5. `recommended_cfl(scheme, domain)` admits it can be unsound for `IFRK2`, but the signature has no way to detect the condition that makes it so

**Type:** api-gap · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / Propagator, `recommended_cfl`: "This function takes no $\nu$, by design ... but `IFRK2`'s margin is the one value that depends on a quantity it cannot see ... at high Reynolds number verify the step against a run that holds its energy, or set `cfl` yourself."

**Description:** An abstraction whose whole job is "the stable step size for this scheme" ships a documented failure mode (instability at low $\nu$ with `IFRK2`) that its own inputs cannot detect, and offloads the mitigation entirely to user vigilance in prose rather than to any code-level guard (e.g., an optional viscosity-aware check, a runtime warning at `Simulation` construction time when `IFRK2` is paired with a small `viscosity`). The `Simulation` front door defaults `cfl = recommended_cfl(scheme, domain)`, so the unsound default is one keyword swap away with no signal.

---

## 6. `deposit_sample!` documents its return value twice, in two different words

**Type:** format · **Severity:** minor · **Confidence:** high

**Locations:**
- PAGE: api / Cache, `deposit_sample!` synopsis: `` deposit_sample!(cache) -> particle velocities ``
- Same docstring, final sentence: "Returns the slot's array."

**Contradicts:** every other arrow-bearing verb in the corpus (`advect!`, `record_particle_velocities!`, `allocate_buffers`, `interpolate_at_particles!`) states its return only once, via the arrow, with no trailing "Returns ..." sentence — the shape the panel's own prior round confirmed is the corpus convention (arrow *or* sentence, chosen by whether the signature carries one).

**Description:** `deposit_sample!` carries both, and the two descriptions use different vocabulary for the same value ("particle velocities" vs. "the slot's array") — a small but genuine notation drift on a single function's own return contract.

---

## 7. `velocity_rhs!` / `scalar_rhs!` mutate a second, non-leading argument that the `!` convention does not flag

**Type:** api-gap · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / Generator, `velocity_rhs!(N̂, generator, û, u, ω_consumed, domain)`: "The vorticity argument is named `ω_consumed` because the assembly overwrites it: on return it no longer holds the vorticity."
- Same page, `scalar_rhs!`: "The velocity argument is named `u_consumed` because the assembly overwrites it."

**Description:** Julia's `!`-suffix idiom signals "the leading argument is mutated"; here the leading argument `N̂` genuinely is, but a second, fifth-positional argument is also destructively consumed. The chosen mitigation — naming the argument `ω_consumed` / `u_consumed` — is a real improvement over silent prose but is still a documentation-level fix to a signature-level surprise: nothing in the call shape (only in each argument's name, which a caller must read individually) distinguishes this from an ordinary read-only argument.

---

## 8. `particle_velocities` is shared by array identity between `Tracers` and `ObservablesCache`, with no enforced check that the two match

**Type:** api-gap · **Severity:** minor · **Confidence:** low

**Locations:**
- PAGE: api / Cache, `ObservablesCache`: "the particle velocities are the tracer set's own storage, which the cache borrows and records epochs for rather than filling itself."
- PAGE: observables_cache, §3.1: "the particle-velocities slot is the tracer set's own storage, passed in ... `ObservablesCache(domain; scalar = true, particle_velocities = tracers.particle_velocities)`."

**Description:** The design depends on `cache.particle_velocities` and `tracers.particle_velocities` being the identical array object (so a write through one is visible through the other) — an aliasing contract Julia's type system cannot express. The `ObservablesCache` constructor's documented signature accepts any array under that keyword; nothing on the page states what happens if a caller passes a copy rather than `tracers.particle_velocities` itself (the two slots would then silently diverge).

---

## 9. "Chart" is a load-bearing term of art absent from the `notation.md` Vocabulary glossary that defines its siblings

**Type:** clarity · **Severity:** nit · **Confidence:** medium

**Locations:**
- PAGE: architecture, §4.1: "The chart map — the recovery of the physical representations — is not a package verb."; §8: "The `ObservablesCache` charts are the tower's algebraic variables."
- PAGE: notation, §Vocabulary: defines `iteration`, `deposit`, `slot`, `epoch`, `register`, `front door`, `observation`, `resolved` — no `chart` entry.

**Description:** "Chart" (borrowed from the differential-geometry sense of a coordinate map) recurs dozens of times across `ARCHITECTURE.md` and `observables_cache.md` as a structural term for the physical-representation recoveries, on equal footing with `slot`/`epoch`/`register`, all of which *are* glossed. A cold reader meeting "the chart contract" or "the tower's algebraic variables" has no page that defines the term.
