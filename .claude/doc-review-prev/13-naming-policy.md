# Naming-policy hat — findings

Reviewed against `CLAUDE.md`'s Naming rules: (a) name for what it means to the physicist-user, never
the backend mechanism; (b) unambiguous and precise; (c) field math variables are symbols, storage/
functions are descriptive; (d) one concept, one name, across the whole surface. Cross-checked the
rendered manuscript against `src/*.jl`.

---

## Finding 1 — `Linear.mask` and `ConstantPower.indicator` are the same concept under two names

**Type:** other (one-concept-two-names) · **Severity:** major · **Confidence:** high

**Locations:**
- PAGE: api / Forcing, `Linear` Fields: "`mask` — **the band indicator as a real array**."
- PAGE: api / Forcing, `ConstantPower` Fields: "`indicator` — **the band indicator as a real array**, the rate fill's factor."
- `src/Forcing.jl:352` (Linear docstring) vs `src/Forcing.jl:417` (ConstantPower docstring) — identical wording, different field name.
- `src/Forcing.jl:356` `mask::M  # real array: the band indicator (1 in band, 0 outside)` vs `src/Forcing.jl` `indicator::...` — same struct role.

**Contradicts:** the two docstrings use the *verbatim same description* — "the band indicator as a
real array" — for a field in `Linear` named `mask` and the structurally identical field in
`ConstantPower` named `indicator`. Both are the same object built the same way (materializing the
lazy shell kernel into a real array to fill a per-mode rate), in sibling types of the same
`AbstractForcing` family, documented on the same rendered page.

**Description:** Rule (d) — one concept, one name — is violated inside a single module's export
list: a reader who learns `ConstantPower.indicator` from one docstring has no reason to expect the
identical concept to reappear as `Linear.mask` three sections earlier on the same page. `mask` also
reads as a *different* kind of object to a numerics-literate reader (a boolean/multiplicative filter
applied broadly, cf. `dealias`/`squared_wavenumber_kernel` "mask" usage elsewhere in the corpus),
where `indicator` is the more precise term for a 0/1 membership array — so the mismatch is not just
cosmetic, it picks the *less* precise of the two available words for one of the two sites.
**Resolution hint:** rename `Linear.mask` → `Linear.indicator` (or vice versa, consistently), and
update the constructor comment at `Forcing.jl:363` ("the same stored mask this forcing always
carried") that itself asserts the old name across the rename boundary.

---

## Finding 2 — `deposit_sample!` is the one place "sample" survives; everywhere else it is "particle velocities"

**Type:** other (one-concept-two-names) · **Severity:** major · **Confidence:** high

**Locations:**
- PAGE: api / Cache: "`deposit_sample!` — records **the particle velocities** the tracer advance wrote."
- PAGE: api / Cache, `deposit_sample!` docstring: "Record **the particle velocities** already written into `cache`… so `particle_velocities` will serve them."
- PAGE: api / Particles, `record_particle_velocities!`, `particle_velocities` — the writer and reader both name the object "particle velocities".
- `src/Cache.jl:21,54,265-285` — the function is `deposit_sample!`; every field, accessor, and doc sentence around it says `particle_velocities` / "the particle velocities".

**Contradicts:** the full public index (PAGE: api / GBGIsotropicTurbulence) lists, for this one
observable, `deposit_sample!` (Cache), `record_particle_velocities!` (Particles), and
`particle_velocities` (Cache) — three verbs/accessors for one concept, and "sample" appears in
exactly one of the three names, nowhere else on the whole public surface (the notation glossary's
own Vocabulary section does not define "sample" as a term at all, only "particle velocities").

**Description:** The 2026-08 decision log entry "The trajectory sample is a cache slot…" explains
*why* the object was formerly called a "sample" internally, and the rename swept the reading/writing
accessors to `particle_velocities` — but left the marking-current verb as `deposit_sample!` rather
than something like `record_sample_current!`/`confirm_particle_velocities!`. The result is a name
that only makes sense to a reader who already knows the retired internal vocabulary — exactly the
"survives only because a reader already knows the code" pattern this hat is asked to hunt.
**Resolution hint:** rename `deposit_sample!` to use the `particle_velocities` root the rest of the
protocol uses (the internal `sample_fields_epoch`/`sample_particles_epoch` field names carry the same
residue and could be swept in the same pass).

---

## Finding 3 — `AbstractParticleIntegrator` (particle-rooted) vs `Simulation.trajectory_scheme` (trajectory-rooted) name the same object

**Type:** other (one-concept-two-names) · **Severity:** major · **Confidence:** medium-high

**Locations:**
- PAGE: api / Particles: `AbstractParticleIntegrator`, `ParticleIntegratorBuffers`, `allocate_buffers(scheme, tracers)`.
- PAGE: api / SimulationRun, `Simulation` Fields: "`tracers`, **`trajectory_scheme`**, `particle_buffers`… The two roots are not interchangeable: *trajectory* names the path through time the scheme integrates, *particle* the objects whose storage the buffers hold."
- `src/SimulationRun.jl:226-227`: `trajectory_scheme::PI  # AbstractParticleIntegrator, or nothing` / `particle_buffers::PB`.

**Contradicts:** the value stored in `Simulation.trajectory_scheme` is literally an instance of
`AbstractParticleIntegrator` — the type family, its buffer type (`ParticleIntegratorBuffers`), and
its allocator (`allocate_buffers(scheme, tracers)`) all use the root **particle**, while the field
that holds that same value and the front-door keyword that sets it (`trajectory_scheme = EndpointHeun()`)
use the root **trajectory**. The docstring's own defense — "trajectory names the path… particle the
objects whose storage" — explains why *buffers* differ from *scheme*, but does not explain why the
*scheme itself* is typed under one root and instanced under another.

**Description:** This is exactly the "two nouns for one concept in the same export list" pattern:
`AbstractParticleIntegrator`/`EndpointHeun` is a *particle* integrator by type, but is read and
written everywhere on the `Simulation`/front-door surface as a *trajectory* scheme. A user who greps
the API index for "particle" to find the scheme family, then reads `Simulation`'s field list, meets
an unexplained third root. The field-side parallel construction (`scheme` for the field integrator,
paired with `buffers`) would predict `particle_scheme` here, not `trajectory_scheme`.
**Resolution hint:** either rename the field/keyword to `particle_scheme` to match the type family,
or rename the type family to `AbstractTrajectoryIntegrator` to match the field — but not both roots
left standing.

---

## Finding 4 — `ω_consumed` / `u_consumed` mix a math symbol with a descriptive suffix, against the stated math-variable rule

**Type:** other (naming-rule tension) · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / Generator, `velocity_rhs!(N̂, generator, û, u, ω_consumed, domain)`.
- PAGE: api / Generator, `scalar_rhs!(N̂, generator, û, φ̂, u_consumed, φ, domain)`.
- CLAUDE.md, Naming: "A field **math variable** (a function parameter or a local) is named by its
  symbol… **Storage slots keep descriptive names**… The rule: symbols for math variables,
  descriptive names for storage."

**Contradicts:** the house rule draws a hard line — a field-valued function *argument* is a math
variable and takes a bare symbol (`u`, `ω`, `û`, `φ̂`), never a descriptive name; only *storage
slots* (struct fields) get descriptive names. `ω_consumed` and `u_consumed` are function arguments,
not storage slots, yet each appends a descriptive English suffix to the bare symbol — a hybrid the
written rule does not carve out.

**Description:** The choice is thoroughly motivated in the architecture decision log ("The consumed
operand is named for it") — Julia's `!` convention only flags the first argument as mutated, so the
suffix warns a caller that a second, physically-determined argument is destroyed in place. That is a
legitimate correctness concern, but the *fix chosen* (symbol + descriptive suffix) sits outside the
two categories the naming rule defines, and no exception is recorded in CLAUDE.md's Naming section
itself (only in the architecture decision log, which is not where a reader consulting the naming
rule would look). Flagging for awareness rather than as a clear-cut violation, since the underlying
motivation is sound; the written rule should either name this a third, sanctioned pattern or the
policy text should be tightened to exclude it.
**Resolution hint:** add a one-line carve-out to CLAUDE.md's Naming section for the "consumed operand"
pattern, so the rule and the practice agree without a reader needing the decision log.

---

## Finding 5 — `FlowConditions` and `FlowParameters` share two field names across "configured" vs "measured" objects

**Type:** other (ambiguity risk) · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / Generator, `FlowConditions`: "Not to be confused with `Phenomenology`'s `FlowParameters`, **which shares two field names**: this type holds what a run is configured with, that one holds what a run has been measured to have."
- PAGE: api / phenomenology / Phenomenology, `FlowParameters(; viscosity, dissipation, rms_velocity, integral_scale, schmidt, scalar_dissipation)` vs PAGE: api / Generator, `FlowConditions(; viscosity, schmidt, velocity_forcing, scalar_forcing)`.

**Contradicts:** rule (b) requires each name be unambiguous — "one reading." `viscosity` and
`schmidt` mean the same physical quantity in both types, but one bundle is a run's *input* and the
other its *measured state*, and nothing in either field name signals which regime a value read off
it belongs to; the docstring itself calls out the collision as a risk worth a standing warning
("Not to be confused with…").

**Description:** This is a self-acknowledged near-miss rather than an unnoticed defect — the
docstring already carries the disambiguating note — but per rule (b) a name that needs a permanent
"don't confuse this with…" footnote to stay unambiguous has not fully met the bar the rule sets. The
two objects are legitimately different (configured vs measured) and merging them would be wrong, but
the shared field names (`viscosity`, `schmidt`) could instead have been namespaced or worded to
carry the configured/measured distinction on their face (e.g. keeping `schmidt` only on
`FlowConditions` and using the already-distinct `scalar_diffusivity`/derived-scale vocabulary
consistently on the `FlowParameters` side, where the docstring says the small scales are "derived,
not stored").
**Resolution hint:** none proposed beyond the existing note; recorded for completeness since the
policy's own bar is "one reading," and this is admitted to need a second sentence to reach it.
