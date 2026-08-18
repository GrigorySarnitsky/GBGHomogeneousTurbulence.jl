# Fix audit — findings 36–42 (independent re-audit)

Diff audited: `9b3ecdd..HEAD` (`git log --stat`, `git diff`), which includes the original phase-A/B fix
passes plus five "Verifier B" self-correction rounds already applied on top. Corpus checked against
current `src/*.jl`, `docs/`, `test/`, `CLAUDE.md`, `docs/ARCHITECTURE.md` §11 decisions 49–56,
`.claude/commands/check-consistency/panel.js`, and `.claude/commands/check-docs/xlink.jl` (run live).

A prior file already existed at this path, all seven verdicts HONORED. I re-derived every verdict from
the current corpus and the diff rather than trusting it; my conclusions below happen to agree with it
on all seven, but each is independently evidenced.

---

## Finding 36 — `velocity_buffer` allocates a generic buffer but is named for one use

**Owner's ask (verbatim):** "WTF, you allocate a vector buffer, but call it velocity. I could have
sampling e.g. scalar gradient." Direction: rename via the `new_<Type>` allocator convention already
settled for the cache — `new_vector_point_values(tracers)` / `new_scalar_point_values(tracers)` — with
docstrings that describe the shape, not one caller.

**VERDICT: HONORED**

**Evidence.** `src/Particles.jl:331,340`:
```julia
new_vector_point_values(tracers::Tracers) = VectorPointValues(similar(tracers.positions))
new_scalar_point_values(tracers::Tracers) =
  ScalarPointValues(similar(tracers.positions, eltype(tracers.positions), number_of_particles(tracers)))
```
exported at `:44`. `grep -rn "velocity_buffer\|scalar_buffer" src/ test/ docs/ README.md CLAUDE.md`
returns zero hits outside the pile document itself and stale `.claude/doc-review*` snapshots (which
predate the fix and are explicitly out of scope). Each docstring leads with the shape ("Allocate a
`VectorPointValues` … of shape `(M, 3)` matching the tracer set `tracers`") and only then names a use
as an example ("for use as the `out` of `interpolate_at_particles!` … when sampling the velocity"),
which is illustrative rather than definitional — the object is no longer identified with one caller,
which was the defect. The name pattern matches the pre-existing `new_vector_field_spectral` /
`new_scalar_field_spectral` family in `SimulationDomain.jl`, so it is not a fresh coinage.

---

## Finding 37 — `sample!` collides with the noun *sample*; says nothing about interpolation

**Owner's context:** `sample!` collided with "the genuine Lagrangian sample" (the recorded
`trajectory_velocity`) and the cache's `deposit_sample!`. Naming settled in conversation:
`interpolate_at_particles!`.

**VERDICT: HONORED**

**Evidence.** `src/Particles.jl:290–298` defines `interpolate_at_particles!(out, field, tracers) ->
out`, exported at `:44`. `grep -rn '\bsample!\b' src/ test/ docs/ README.md CLAUDE.md` returns nothing —
no residual caller, export, or doc mention of the old verb; `test/particles.jl` and
`docs/src/api/Particles.md` both call the new name. The identifier-level collision (`sample!` vs "the
Lagrangian sample" vs `deposit_sample!`) is gone. `deposit_sample!` (unflagged) and "the genuine
Lagrangian sample" (the noun, `:110`) both survive untouched, correctly — only the verb the owner named
was in scope.

One residue worth naming even though it does not change the verdict: the new function's own docstring
still opens "Sample the physical `field` at the current tracer positions…" and the module comment still
says "any physical field can be sampled along the trajectories" (`:3`, `:56`). This is ordinary-English
use of "sample" as a verb, not a re-introduction of the flagged identifier collision, and the owner's
decided fix was specifically the function name — so it does not move the verdict off HONORED, but a
stricter read of the finding's own "three uses of one word" framing would flag it as a class remnant.

---

## Finding 38 — *particle* vs *tracer*: three nouns, no stated convention

**Owner's ask:** "Tracer is just a specific type of particles, non-inertial, with no inner degrees of
freedom. Don't we have a convention on tracer vs particle distinction?"

**VERDICT: HONORED**

**Evidence.** `docs/ARCHITECTURE.md:1685–1692` (decision 51, user-directed) states the rule — "name by
what the operation is true of," particle for anything true of the whole deferred ladder, tracer only for
the massless kind — and its two concrete consequences: `number_of_tracers` → `number_of_particles`,
`sample!` → `interpolate_at_particles!`. `grep -rln "number_of_tracers" src/ test/ docs/src README.md
CLAUDE.md` returns nothing; `grep -n "number_of_tracers" docs/ARCHITECTURE.md` shows only the two
mentions inside decision 51's own prose (append-only history, the sanctioned exception), mirrored
verbatim in `docs/src/architecture.md`. The export line at `src/Particles.jl:44` reads
`particle_positions, number_of_particles, new_vector_point_values, new_scalar_point_values` — the
adjacent-nouns collision the owner quoted (`particle_positions` beside `number_of_tracers`) no longer
exists. `Tracers` and `interpolation_scheme` keep tracer-specific names (construction only), matching
the stated rule.

---

## Finding 39 — Conventions hats: no reader checks the rulebook itself

**Owner's ask (verbatim):** "probably we should have hats that check if our conventions are followed. …
Not mechanical, just readers."

**VERDICT: HONORED**

**Evidence.** `.claude/commands/check-consistency/panel.js:139–160` adds three hats — `naming-policy`,
`doc-policy`, `invariants-and-decisions` — each with a `substrate` explicitly granting `CLAUDE.md` (and,
for the third, `ARCHITECTURE.md` §11) as authoritative, and persona text stating "treat them as law,
above whatever the corpus happens to do" / "above the corpus's habits" / "they are law." The comment
block at `:134–138` records the rationale nearly verbatim to the pile's own framing ("Eleven of the
twelve hats above are deliberately BLIND to CLAUDE.md… a convention violated UNIFORMLY [is]
invisible… THE RULEBOOK OUTRANKS THE CORPUS"). Each hat's persona is a natural-language judgment prompt
for an LLM reader, not a script — matching "Not mechanical, just readers" (the mechanical instruments
the owner asked for elsewhere, e.g. the DOI cross-check and the abutting-span scan, are separate
`check-docs` Python scripts, correctly not folded into these three).

---

## Finding 40 — `Tracers`' keyword/positional split is unprincipled; round-1's finding fixed on one
## line instead of swept as a class

**Owner's ask:** "Why are some arguments named, while others not? Did we note that problem before in
that read?" — round-1 finding 4a ("make them all named") was applied to `FixedDomain` alone and never
swept; the class needed the rule stated and `Tracers` fixed.

**VERDICT: HONORED**

**Evidence.** `docs/ARCHITECTURE.md:1697–1710` (decision 52, user-directed) states the rule explicitly —
"the object a value is derived from is positional, its settings are keyword" — and names `Tracers` as
"its one remaining violator," recording the language-forced consequence (keyword args don't dispatch,
so the two constructor forms merge into one method with an `ArgumentError`). Current code,
`src/Particles.jl:124–142`:
```julia
function Tracers(domain::FixedDomain; interpolation_scheme, positions = nothing,
                 number_of_particles = nothing, rng = Random.default_rng())
  count(!isnothing, (positions, number_of_particles)) == 1 ||
    throw(ArgumentError("give exactly one of `positions` … or `number_of_particles` …"))
  ...
```
— `domain` stays positional (the source object), `positions`/`number_of_particles` are now keyword
(settings), matching the rule verbatim. I independently checked every other constructor the pile's table
named (`ResolvedFields`, `ObservablesCache`, `ResolvedGenerator`, `Reference`) against the stated rule
and each already satisfies it — a genuine source object stays positional, settings are keyword — so no
further code change was owed and the finding never asked for one. `grep -rn "Tracers(" src/ test/
docs/src` shows every call site (`test/particles.jl`, `test/memory_audit.jl`,
`src/SimulationRun.jl:260`) already using the merged keyword form; no stray two-positional caller
survives.

---

## Finding 41 — `particle_velocities` is the only unlinked name in its sentence; the cross-module
## link class is 83 sites, not 25

**Owner's ask:** "particle_positions and number_of_tracers are linked, while particle_velocities are
not." Plus the pile's own correction that the true class (every umbrella export cited by prose, first
mention, never `@ref`-linked) is 83 sites, of which 56 are cross-module.

**VERDICT: HONORED**

**Evidence.** `src/Particles.jl:98–101`, the exact flagged sentence:
```
Read the particle state with [`particle_positions`](@ref) and [`number_of_particles`](@ref); the
trajectory velocities are read from the run's observables cache, through
[`particle_velocities`](@ref GBGIsotropicTurbulence.Cache.particle_velocities), where the
iteration's closing deposit leaves them.
```
All three names are now linked, `particle_velocities` fully qualified across the module boundary
(also fixed identically at `:23` and `:221`). For the class-wide claim I ran the deterministic scan the
pile calls for directly rather than trusting the report: `julia --project --startup-file=no
.claude/commands/check-docs/xlink.jl` on the current tree prints `FOUND 0 cross-module first mentions`.
The scan file exists (`.claude/commands/check-docs/xlink.jl`) and executes cleanly against the live
corpus, not just against a cached report — the class this finding widened from 25 to 83 sites is fully
swept, not only the one screenshot sentence.

---

## Finding 42 — `Tracers` mixes trajectory state with one integrator's scratch

**Owner's ask:** "Here we mix the state of the tracers with the integrator, no? What if we change the
integrator?" Direction: split `Tracers` (state) from an `AbstractParticleIntegrator` /
`allocate_buffers`-built scratch type, mirroring the field side's `ResolvedFields` /
`IntegratorBuffers` split.

**VERDICT: HONORED**

**Evidence.** `src/Particles.jl` now defines `AbstractParticleIntegrator` (`:150–161`), `EndpointHeun <:
AbstractParticleIntegrator` (`:178`), and `ParticleIntegratorBuffers` (`:184–203`) holding exactly the
three fields the finding named as Heun-specific scratch (`predictor`, `predictor_points`,
`predictor_velocity`). `Tracers` is reduced to `positions`, `position_points`, `trajectory_velocity`,
`interpolation_scheme` (`:117–121`) — state only, with the docstring stating outright: "The trajectory
scheme's own working storage is **not** here: it is allocated per scheme into a
`ParticleIntegratorBuffers`, so changing the scheme changes no part of this type." The allocator is the
*same generic* used on the field side (`import ..Propagator: allocate_buffers` at `:40`, plus a new
method `allocate_buffers(::EndpointHeun, tracers::Tracers)` at `:205–208`). `advect!` now dispatches on
`scheme` (`advect!(::EndpointHeun, tracers::Tracers, buffers::ParticleIntegratorBuffers, …)`, `:271`)
instead of being a hardwired code path, directly closing "advect! … takes no integrator argument at
all."

Wiring is threaded end to end, not left as a library-only capability: `src/SimulationRun.jl:204–205`
stores `particle_scheme`/`particle_buffers` on `Simulation`, `:228` exposes `particle_scheme =
EndpointHeun()` as a front-door keyword, `:261` builds the buffers via the shared `allocate_buffers`,
`:377` calls `advect!(sim.particle_scheme, sim.tracers, sim.particle_buffers, …)`. Decision 50
(`docs/ARCHITECTURE.md:1668–1683`) records the change and its memory-ledger consequence, and
`test/memory_audit.jl:315–330` verifies the split directly: `length(_m_arrays(tracers)) == 2`,
`length(_m_arrays(buffers)) == 2`, total unchanged at 4, plus an explicit negative check
(`isempty(intersect((:predictor, :predictor_points, :predictor_velocity), fieldnames(Tracers)))`) that
no scheme register survives on the state type. `docs/src/api/Particles.md` documents the new split with
matching rationale. No stray reference to the old monolithic seven-field `Tracers` remains in `src/`,
`test/`, or the docs pages.

---

## Summary

All seven findings in this batch (36–42) verify as **HONORED** on independent re-derivation. The
renames and the state/scratch split land at every call site checked — source, tests, docs pages, and
the decision log — and the two class-wide claims (the `new_<Type>` sweep for finding 36, the
cross-module `@ref` sweep for finding 41) were confirmed by *running* the deterministic checks against
the live tree rather than trusting a prior report. Finding 42's restructuring is wired through the run
layer end to end and pinned by a memory-audit test, not left as a docstring-only claim. The one nuance
worth flagging without changing a verdict: finding 37's fix removed the `sample!` identifier collision
completely, but the renamed function's own docstring still uses "sample" as an ordinary-English verb —
a defensible reading under the owner's actual (narrower) decided fix, but a residue under the finding's
own broader "three uses of one word" framing.
