# Closure audit — Software Architect hat (02-software-architect.md)

## Finding 1 — `tracer_scheme` renames `interpolation_scheme` across a forwarding hop; collides with `particle_scheme`
**VERDICT: ABSENT**
Evidence: `src/SimulationRun.jl:162-166` — the front-door keyword is now literally `interpolation_scheme` (identical to `Tracers`'), and the neighbouring temporal keyword is now `trajectory_scheme` (`interpolation_scheme = CatmullRom`, `trajectory_scheme = EndpointHeun()`). Grepped `tracer_scheme|particle_scheme` across `src/`, `docs/src/`, `ARCHITECTURE.md` — no `tracer_scheme` remains; `Tracers.jl` uses `interpolation_scheme` throughout (`src/Particles.jl:48,74,121,130,137`). The "despite the neighbouring names" disclaimer is gone.

## Finding 2 — `advect!`'s argument order breaks the shared `state, domain, buffers` order
**VERDICT: ABSENT**
Evidence: `src/Particles.jl:248,282` — signature is now `advect!(scheme, tracers, velocity_end, domain, buffers, dt)`, `domain` before `buffers`, matching `step!`/`deposit!` (`src/Propagator.jl:169,465`: `step!(scheme, state, generator, domain, buffers, cache, dt)`, `deposit!(cache, state, domain, buffers)`). Order now consistent everywhere.

## Finding 3 — `Simulation`'s fields expose `buffers`/`generator` at the same level as sanctioned reads
**VERDICT: ABSENT**
Evidence: `src/SimulationRun.jl:186-199`, the `# Fields` section now opens: "Two of these are what a user reads — `state` and `cache`. The rest are the machinery the step runs on: they hold partial values while a step is in flight, so read them only between steps..." — directly states which fields are unsafe to read mid-run, addressing the resolution hint verbatim.

## Finding 4 — "One forcing instance per forced field" enforced only by prose, not code
**VERDICT: ABSENT**
Evidence: `src/Generator.jl:87-98` — `FlowConditions`'s constructor now checks `ismutable(velocity_forcing) && velocity_forcing === scalar_forcing` and throws `ArgumentError` naming the strategy. `src/Forcing.jl:80-86` — `AbstractForcing`'s docstring warning was updated to say `FlowConditions` "throws an `ArgumentError` rather than let that happen," matching the code.

## Finding 5 — `FlowParameters.scalar_dissipation` `NaN` sentinel vs `nothing` convention elsewhere
**VERDICT: ABSENT**
Evidence: `src/Phenomenology.jl:87-93` — the docstring now explicitly scopes the "does not propagate" guarantee: "That check is what makes the sentinel safe, so it covers the laws here and not arithmetic a caller does on the field itself, which propagates `NaN` as `NaN` always does." This is exactly the resolution hint's first option (scope the claim to the `Phenomenology` evaluators); the field itself is unchanged (still `NaN`, by design) but the misleading unscoped guarantee is fixed.

## Finding 6 — `Cache`'s epoch invariant is written by `deposit!`, homed in `Propagator`, with no stated reason
**VERDICT: ABSENT**
Evidence: `src/Cache.jl:30-33` — module docstring now reads: "It is homed in `Propagator` rather than here because it needs the scheme's own scratch to recover the fields, and that is the module owning the iteration it closes." This is the exact include-order/ownership rationale the resolution hint asked to be stated.

## Finding 7 — `ObservablesCache.particle_velocities` is aliased external storage, unlike other self-owned slots
**VERDICT: ABSENT**
Evidence: `src/Cache.jl:73-74` — the type's opening paragraph now states: "The cache allocates and owns every slot but one: the particle velocities are the tracer set's own storage, which the cache borrows and records epochs for rather than filling itself." Matches the resolution hint (name the asymmetry in the opening paragraph) verbatim.

## Finding 8 — `k_max_η` mixes ASCII-folded κ with literal Unicode η
**VERDICT: ABSENT**
Evidence: The keyword is now `κ_max_η` throughout `src/SimulationRun.jl` (lines 65, 101, 109, 111, 114, 132, 224, 240-245) — fully Unicode, no ASCII folding of κ at all. Grepped `ASCII` across `src/*.jl`, `docs/ARCHITECTURE.md`, `docs/src/*.md` — zero hits; the "spelled in ASCII" framing is gone entirely, resolving the half-transliteration.

## Finding 9 — Explicit mode silently ignores `k_max_η`/`κ_max_η` when `viscosity` is also given
**VERDICT: ABSENT**
Evidence: `src/SimulationRun.jl:239-243` — constructor now throws: `if !isnothing(viscosity) && !isnothing(κ_max_η); throw(ArgumentError("\`viscosity\` and \`κ_max_η\` are two ways to set ν ... Pass one, not both."))`. Docstring at line 116-117 states "passing both raises an `ArgumentError` rather than dropping one." Matches resolution hint.

## Finding 10 — The four `AbstractForcing` hooks reuse the parameter name `field` for physically distinct instants
**VERDICT: ABSENT**
Evidence: `src/Forcing.jl:165,175` — `apply_forcing!`'s documented signature and default method now use `advanced_field`, distinct from `prepare_forcing!`/`set_forcing_rate!`'s `field` (start-of-step). Docstring at lines 172-174 explicitly explains the distinction: "Unlike the two hooks that read the start-of-step field, this one is handed the field the step has already advanced — the argument is named for that instant..." Matches resolution hint exactly at the documented/rendered API surface (concrete strategy implementations like `BandRescaling`'s internal `field` parameter name are not part of the rendered public docstring, per house style of one docstring per operation on the bare/generic binding).
