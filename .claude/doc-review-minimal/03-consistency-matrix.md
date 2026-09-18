# Consistency-matrix audit — hat: consistency-matrix

Systematic cross-page diff of recurring entities (symbols, formulas, constants, verb names,
module maps, include order) across the full rendered manuscript. Findings below are the
divergences that survived the sweep; a large majority of entities checked (kinetic energy,
dissipation, Yaglom's law, the PhaseShift cutoff fraction, the CFL calibration numbers, the
memory-ledger byte counts, the transform-count tables, the Li2008/Sreenivasan constant
cross-relation) were internally consistent across every page they appear on and are not
reported here.

---

## Finding 1 — Module include order stated three different ways

- **Type:** contradiction
- **Severity:** blocker
- **Confidence:** high

**Locations:**
- Architecture, §4.9 "Layout summary": *"`SimulationDomain → Observables → State → Cache → Forcing → Generator → Propagator → Particles → SimulationRun`."*
- `api` page, API overview: *"the order `SimulationDomain` → `State` → `Observables` → `Cache` → `Forcing` → `Generator` → `Propagator` → `Particles` → `SimulationRun`"*
- Home page, "Components" (same order as the API overview): `SimulationDomain`, `State`, `Observables`, `Cache`, …
- Architecture, decision log (2026-08, user-directed, "`Observables` precedes `Cache`"): *"The include order becomes `State → Observables → Cache`"*
- `GBGIsotropicTurbulence` API index: lists `State.*` entries before `Observables.*` entries.

**Contradicts:** whether `State` or `Observables` is included first. §4.9 of Architecture — the page's own designated "current, authoritative" layout statement — asserts `Observables` before `State`. Every other source in the manuscript (the API overview page, the Home page's component list, the package-wide API index ordering, and the decision log's own dated entry narrating this exact reordering) asserts the opposite, `State` before `Observables`.

**Description:** This is a basic architectural fact restated in five places with a 4-to-1 split against Architecture's own §4.9. The decision log entry is explicit that the order "becomes `State → Observables → Cache`" as of a 2026-08 change; §4.9 was evidently never updated to match. A reader relying on §4.9 (the section literally titled "Layout summary") gets the include order backwards relative to every other page.

---

## Finding 2 — Which call "completes" the particle-velocity deposit

- **Type:** contradiction
- **Severity:** major
- **Confidence:** high

**Locations:**
- Architecture, §4.6 (Particles): *"After the push, `record_particle_velocities!` records the new sample at the new positions from the same deposited field, **completing the iteration's deposits**"*
- `api/Cache`, `deposit_sample!`: *"Use it after writing new values along the trajectories — `record_particle_velocities!` writes, **this call records**. … A run does both for you at the end of each iteration … since **the write alone leaves the slot stale**"*
- `api/Particles`, `record_particle_velocities!`: *"This call is that slot's only producer of values, but **it writes values only**: the slot stays stale, and reads of it throw, **until `deposit_sample!` records them as current**."*

**Contradicts:** Architecture credits `record_particle_velocities!` alone with completing/closing the iteration's deposits. Both API pages that actually document the two verbs state the opposite division of labour: `record_particle_velocities!` only writes (and leaves the slot stale/throwing), while the separate `deposit_sample!` call is what marks the value current — i.e. is what actually completes the deposit.

**Description:** A reader who trusts Architecture's summary would conclude a hand-run loop needs only `record_particle_velocities!` after the push; the Cache and Particles API pages both say a second call, `deposit_sample!`, is required or the read throws.

---

## Finding 3 — The `Particles` module docstring is stale: it omits a whole scheme family and three of its own exported names

- **Type:** organization / format (module-map completeness)
- **Severity:** major
- **Confidence:** high

**Locations:**
- `api/Particles`, module docstring (the page's own "map"): lists only `Tracers`, `particle_positions`, `number_of_particles`, `AbstractParticleIntegrator`, `EndpointHeun`, `ParticleIntegratorBuffers`, `record_particle_velocities!`, `advect!`, `interpolate_at_particles!`, `new_vector_point_values`, `new_scalar_point_values`.
- Same page, later sections: fully documents `AdamsBashforth`, `MultistepBuffers`, `history_depth`, and `restart!` — none named in the map above.
- `GBGIsotropicTurbulence` API index: lists all fifteen `Particles.*` names, including the four missing from the module map.
- Architecture, §4.7: *"any `Tracers` with its own `AbstractParticleIntegrator` and `ParticleIntegratorBuffers`"* — also silent on `MultistepBuffers`, the buffer type an `AdamsBashforth`-driven run actually carries.

**Description:** CLAUDE.md's own documentation policy states a module docstring is a map with "a linked one-liner per operation" and that "a capability list missing a builder" is stale even if every individual sentence is true. Four of the fifteen names this module exports — including an entire second trajectory-integration scheme (`AdamsBashforth`) and its buffer type (`MultistepBuffers`), added per a later decision-log entry — are absent from the module's own map, and Architecture's run-layer field description repeats the same omission for `ParticleIntegratorBuffers` vs. `MultistepBuffers`. No other module docstring in the manuscript has this gap (all eight other module maps were checked and match their pages' content).

---

## Finding 4 — `allocate_buffers` is documented with two methods; a three-argument call is used elsewhere

- **Type:** contradiction
- **Severity:** major
- **Confidence:** high

**Locations:**
- `api/Propagator`, `allocate_buffers` (the generic's own docstring — the corpus's designated "home" for a function's signature): shows only
  `allocate_buffers(scheme, domain; scalar = false) -> IntegratorBuffers` and
  `allocate_buffers(scheme, tracers) -> ParticleIntegratorBuffers`.
- `api/Particles`, `MultistepBuffers`: *"Build it with `allocate_buffers``(scheme, tracers, cache)`; a run builds it for you."*

**Contradicts:** the generic's own docstring enumerates exactly two methods, neither of which takes a `cache` argument, while another page invokes a third, three-argument form that is nowhere listed as one of `allocate_buffers`'s methods.

**Description:** A cold reader who looks up `allocate_buffers` to learn how to build any of its return types will not learn that a three-argument overload exists for `MultistepBuffers`; the two method signatures shown do not cover it.

---

## Finding 5 — `ObservablesCache`'s printed constructor signature omits a keyword its own Arguments list documents

- **Type:** contradiction (within one docstring)
- **Severity:** major
- **Confidence:** high

**Locations:**
- `api/Cache`, `ObservablesCache` — printed signature: `ObservablesCache(domain; scalar = false, particle_velocities = nothing)`
- Same docstring, "Arguments": *"`history_depth = 1` — how many Lagrangian samples the run must be able to look back over, including the current one. A one-step scheme needs 1 and stores no history; an `order`-step scheme needs `order`."*

**Contradicts:** the code-block signature and the prose Arguments section of the very same docstring disagree about which keywords the constructor accepts — the signature shows two keywords, the prose documents three.

**Description:** A reader who copies the printed call signature (the form CLAUDE.md's own convention treats as authoritative and complete) would omit a real, separately-documented keyword that a multistep trajectory scheme needs the cache to be built with.

---

## Finding 6 — `fields_modified!` lacks the `Simulation`-argument form its declared "twin" `particles_modified!` has

- **Type:** contradiction
- **Severity:** minor
- **Confidence:** medium

**Locations:**
- Architecture, §4.1: *"declared through `fields_modified!` — or, for an out-of-band edit of the tracer positions, through the particle-side twin `particles_modified!`"*
- `api/Cache`, `fields_modified!`: single signature, `fields_modified!(cache)`.
- `api/Cache`, `particles_modified!`: two signatures, `particles_modified!(cache)` and `particles_modified!(sim)`, explicitly described as *"the form to reach for when a run is what you are holding, **mirroring `deposit!`'s two forms**."*

**Contradicts:** if the two announce-functions are "twins" (Architecture's own word) and `deposit!` — which both mirror — has both a `(cache)` and a `(sim)` form, one would expect `fields_modified!` to have the same `(sim)` convenience overload that `particles_modified!` was explicitly given "mirroring `deposit!`". It does not, and no page states a reason for the asymmetry.

**Description:** This may be a deliberate omission (perhaps because seeding routines only ever hold a bare `cache`), but nothing in the manuscript says so, and the explicit "twin" and "mirroring" language elsewhere invites the reader to expect symmetry that is not delivered.
