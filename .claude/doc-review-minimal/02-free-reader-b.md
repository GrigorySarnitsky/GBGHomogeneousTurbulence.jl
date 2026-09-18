# Free reader (hat B) — fresh-eyed review

No checklist; read the whole rendered manuscript (Home, api overview, ARCHITECTURE, decision log,
notation, observables_cache design page, Phenomenology overview, and every per-module API page
including the Phenomenology subpages) as a physicist-programmer deciding whether to trust and adopt
the package. Findings below are ranked most-severe first.

---

## Finding 1 — "Today the single EndpointHeun" is stale: a second trajectory scheme (`AdamsBashforth`) is fully built and exported

**Type:** contradiction
**Severity:** blocker
**Confidence:** high

**Locations:**
- PAGE: architecture, §4.6: "Two axes matter: the trajectory scheme — today the single second-order `EndpointHeun`, with higher-order schemes the studied future axis"
- PAGE: architecture, §4.6 (same section): "`AbstractParticleIntegrator` is the family, `allocate_buffers(scheme, tracers)` builds its registers" (only the one-scheme, two-argument form is described)
- PAGE: Home, Components: "`Particles`: Lagrangian tracer tracking — second-order advection and field sampling along trajectories"
- PAGE: api, module list: "Particles: Lagrangian tracer tracking — `Tracers`, second-order `advect!` (Heun-in-time), and `interpolate_at_particles!`"
- PAGE: api / Particles, `AbstractParticleIntegrator`: "Two members today: `EndpointHeun`, a one-step method … and `AdamsBashforth`, a multistep method …"
- PAGE: api / SimulationRun, `Simulation` Arguments: "`trajectory_scheme = EndpointHeun()` … Pass `AdamsBashforth``()` when trajectory accuracy in time limits a measurement"
- PAGE: api / GBGIsotropicTurbulence, Index: lists `GBGIsotropicTurbulence.Particles.AdamsBashforth` as an exported public name

**Contradicts:** Architecture §4.6 literally says "today the single second-order `EndpointHeun`… higher-order schemes the studied future axis" — using the same word "today" the Particles API page uses to say the opposite: "**Two** members today: `EndpointHeun` … and `AdamsBashforth`."

**Description:** The Architecture document is the package's authoritative current-state spec (CLAUDE.md: "read it before any structural change"), yet its §4.6 describes exactly one trajectory scheme as the present reality and a second as a *future* axis, while the actual API — a fully documented, exported, order-configurable (`order = 4`, capped at 8) `AdamsBashforth` scheme with its own `MultistepBuffers`, cache-backed sample history (`history_depth`, `particle_velocity_history`), and a `Simulation` front-door keyword — is already built and shipped. The Home page and API-overview page repeat the same "second-order" framing. A reader relying on the Architecture doc to scope the package's current capabilities is materially misled about what exists today.

---

## Finding 2 — `ObservablesCache`'s printed constructor signature omits `history_depth`, which its own Arguments list documents

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: api / Cache, `ObservablesCache` signature block: "`ObservablesCache(domain; scalar = false, particle_velocities = nothing)`"
- PAGE: api / Cache, immediately below, Arguments: "`history_depth = 1` — how many Lagrangian samples the run must be able to look back over, including the current one."

**Contradicts:** The signature block presents itself as the complete call form (no `kwargs...` ellipsis, unlike `Simulation`'s constructor elsewhere in the same manuscript, which explicitly uses `kwargs...` to signal an abbreviated list) — yet the very next section documents a third keyword, `history_depth`, that the signature does not show.

**Description:** This is a same-page, self-contained defect: either the printed signature is incomplete (should read `ObservablesCache(domain; scalar = false, history_depth = 1, particle_velocities = nothing)`) or the Arguments list is documenting a keyword that doesn't belong on this constructor. Given `history_depth` is clearly needed to size the multistep sample history for `AdamsBashforth` (see Finding 1), the signature is almost certainly the stale side — likely fixed everywhere else in the same commit that added multistep support except this one code-block.

---

## Finding 3 — `allocate_buffers`'s documented method set is missing the three-argument form `MultistepBuffers` requires

**Type:** api-gap
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: api / Propagator, `allocate_buffers` signature block: "`allocate_buffers(scheme, domain; scalar = false) -> IntegratorBuffers` / `allocate_buffers(scheme, tracers) -> ParticleIntegratorBuffers`" — and body text: "One generic covers both because it is one concept, and because both sides keep the same separation."
- PAGE: api / Particles, `MultistepBuffers`: "Build it with `allocate_buffers``(scheme, tracers, cache)`; a run builds it for you."

**Contradicts:** The home docstring for the generic `allocate_buffers` (in `Propagator`, where CLAUDE.md's "one concept, one home" rule says every method of a generic belongs) enumerates exactly two call forms and says "One generic covers both" — but a third call form, taking a `cache` argument as well, is used elsewhere in the same manuscript for `AdamsBashforth`'s `MultistepBuffers`.

**Description:** Given the corpus's own documentation rule ("a generic carries one docstring, never one per method"), the `allocate_buffers` docstring is the wrong-shaped home once a third dispatch exists: a reader consulting the Propagator page — the more central, more likely first stop for "how do I allocate scheme buffers" — would not learn that a scheme like `AdamsBashforth` needs the cache passed in too. This is the same root cause as Findings 1–2 (the multistep feature's documentation was not swept across every surface it touches).

---

## Finding 4 — No documented verb updates the multistep sample history (`particle_velocity_history`) each iteration

**Type:** api-gap
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: api / Cache, `ObservablesCache` Fields: "`particle_velocity_history` — the earlier Lagrangian samples, most recent first, and `sample_steps` the step sizes they were taken over; `history_filled` says how many are valid."
- PAGE: api / Cache, `deposit_sample!`: "Record the particle velocities already written into `cache` … as current" — describes only the current-sample slot, not the history array.
- PAGE: api / Particles, `record_particle_velocities!`, `advect!`, `restart!`: none mentions pushing a value onto, or shifting, `particle_velocity_history`.

**Description:** The cache clearly carries a rolling history for a multistep trajectory scheme (`AdamsBashforth`), and `fields_modified!` / `particles_modified!` are documented as *discarding* it, but no documented function is ever shown *populating* it iteration over iteration. A reader trying to understand how the history actually advances (shift-and-append? overwrite a ring buffer?) has to infer it; this is exactly the kind of "obvious to the author, invisible to the cold reader" gap the corpus's own self-contained-docs rule targets.

---

## Finding 5 — Home page / API-overview "second-order advection" summaries reinforce the stale scheme-count claim

**Type:** organization
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: Home, Components: "`Particles`: Lagrangian tracer tracking — second-order advection and field sampling along trajectories, with a selectable interpolation scheme."
- PAGE: api, module list: "Particles: Lagrangian tracer tracking — `Tracers`, second-order `advect!` (Heun-in-time), and `interpolate_at_particles!` for the Lagrangian statistics."

**Description:** Grouped separately from Finding 1 because these are map-level one-liners rather than the explicit "today the single …" claim, but they are still incomplete once a second, higher-order (up to 4th-order-converging) trajectory scheme is part of the public surface: neither summary hints that a `trajectory_scheme` choice exists at all. A first-time reader skimming only the Home page would not know `AdamsBashforth` exists.

---

## Finding 6 — `VarianceController`'s `gain` documented as a "method default" sits at the low end of its own cited literature range

**Type:** clarity
**Severity:** nit
**Confidence:** low

**Locations:**
- PAGE: api / Forcing, `VarianceController` Arguments: "`gain = 1` — the dimensionless gain $G$. Larger relaxes faster; Bassenne report $O(1-10)$."

**Description:** Not a contradiction — `gain = 1` is inside the cited $O(1\text{–}10)$ range — but the docstring gives no reason for landing at the low edge of that range specifically rather than, say, a mid-range value, when everywhere else in this corpus a default is justified ("what does your run hold fixed?" for `over`, the epsilon-machine derivation for `HouLi`'s `strength`). A one-clause justification ("gentlest default; raise for faster settling") would close a small gap between the corpus's own documentation standard and this one instance. Low confidence because it may simply be Bassenne's own paper default, which the text does not say either way.
