# Closure — hat 07: physicist-programmer / API user

## Finding 1 — "Stamp" vocabulary survives in live prose after its own retirement
**VERDICT: ABSENT**
Evidence: `rg -i 'stamp' src/ docs/src/ CLAUDE.md` returns zero hits. Rendered pages checked directly
(`docs/build/index.html`, `docs/build/notation/index.html`, `docs/build/api/Cache/index.html`,
`docs/build/observables_cache/index.html`) — no "stamp" occurrences. The only surviving mentions are
in `docs/ARCHITECTURE.md`'s decision log (§53, "'Stamp' is retired…"), which is historical record of
the retirement itself, not live prose using the retired word.

## Finding 2 — `deposit_sample!`'s return-type arrow names neither a type nor an argument
**VERDICT: ABSENT**
Evidence: current docstring/signature at `src/Cache.jl:266` is `deposit_sample!(cache)` — no `->`
arrow at all. Rendered at `docs/build/api/Cache/index.html`: `deposit_sample!(cache)` confirmed. The
malformed `-> particle velocities` arrow the finding quoted is gone; body still says "Returns the
particle-velocities slot" in prose.

## Finding 3 — `velocity_rhs!` / `scalar_rhs!` order the consumed operand inconsistently
**VERDICT: PRESENT**
Evidence: `src/Generator.jl:301` `velocity_rhs!(N̂, generator, û, u, ω_consumed, domain)` (consumed
last); `src/Generator.jl:450` `scalar_rhs!(N̂, generator, û, φ̂, u_consumed, φ, domain)` (consumed
before non-consumed `φ`). The note "Which operand is consumed follows the physics, not the argument
position" (Generator.jl:346-350) still explains but does not resolve the asymmetry. Unchanged from
the finding.

## Finding 4 — `stationary_dissipation` is the one `Scalings` evaluator without a return-type arrow
**VERDICT: ABSENT**
Evidence: `src/phenomenology/Scalings.jl:38` now reads
`stationary_dissipation(law, kinetic_energy, side_length) -> Float64` — the arrow is present,
matching the sibling evaluators (`scaling(law, fp) -> Float64`, etc.).

## Finding 5 — `particle_velocities` breaks the tracer-accessor naming pattern it sits beside
**VERDICT: PRESENT**
Evidence: `src/Particles.jl:334` `particle_positions(tracers::Tracers) = tracers.positions`;
`src/Particles.jl:342` `number_of_particles(tracers::Tracers) = ...`; but
`src/Cache.jl:235` `particle_velocities(cache::ObservablesCache)` — still keyed on `cache`, not
`tracers`, despite `tracers.particle_velocities` existing as a genuine field
(`src/Particles.jl:133`). `docs/src/api/Particles.md:77-78` shows the same asymmetric pair
(`particle_positions(sim.tracers)` vs `particle_velocities(sim.cache)`). Unchanged from the finding.

## Finding 6 — the front door's spectrum-matched IC option covers velocity only, with no documented scalar path or explanation
**VERDICT: ABSENT**
Evidence: `src/SimulationRun.jl:168-171` now states explicitly: "This shapes the **velocity** only; a
scalar is always seeded from the default Gaussian envelope, and a scalar-spectrum initial condition
is reached by calling [`random_scalar_spectral!`](@ref ...) on the built run and announcing the
change." Both the "why" (mirrors the velocity limitation) and the workaround route the finding said
were missing are now present in the `Simulation` docstring itself.

## Finding 7 — `scalar_physical`'s "exactly `velocity_physical`'s contract" is immediately contradicted by an extra throw case
**VERDICT: ABSENT**
Evidence: `src/Cache.jl:202-204`, `scalar_physical`'s docstring now reads "on
[`velocity_physical`](@ref)'s terms (the deposited field or a throw; never a recomputation;
read-only) **plus one of its own**: it throws an `ArgumentError`..." — the overclaiming word "exactly"
no longer appears on `scalar_physical`; it now only appears on `vorticity_physical` (Cache.jl:187),
which genuinely has no extra throw case, so the claim there is accurate.
