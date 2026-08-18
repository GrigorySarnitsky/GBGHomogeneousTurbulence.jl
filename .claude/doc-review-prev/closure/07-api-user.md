# Closure audit — hat 07-api-user

## Finding 1 — In-place protocol verbs never document their return value
**VERDICT: ABSENT**

Evidence: `src/Generator.jl:323` `velocity_rhs!` now ends "Returns `N̂`."; `:459` `scalar_rhs!` ends
"Returns `N̂`."; `src/Propagator.jl:204` `step!` ends "Returns `state`."; `src/Propagator.jl:486`
`deposit!` ends "Returns `cache` (or `sim`)."; `src/SimulationDomain.jl:341` `truncate_to_band!`
(the renamed `dealias!`) states "Returns `field`." Swept the class further — `advect!` (`Particles.jl:251`),
`record_trajectory_velocity!` (`:212`), `apply_forcing!`/`add_forcing_source!`/`set_forcing_rate!`/
`prepare_forcing!` (`Forcing.jl`, all carry `-> value` in the signature), `advance!`
(`SimulationRun.jl:349`, "return it") — every in-place verb checked documents its return.

## Finding 2 — `uses_linear_rate`'s rejecting constructor not documented at the constructor
**VERDICT: ABSENT**

Evidence: `src/Generator.jl:202-208`, `ResolvedGenerator`'s own docstring, now carries `!!! warning
"The constructor rejects a misdeclared forcing"` naming `ArgumentError` explicitly. `src/Forcing.jl`
`uses_linear_rate`'s docstring now says "...the [`ResolvedGenerator`](@ref
GBGIsotropicTurbulence.Generator.ResolvedGenerator) constructor rejects it..." — the ambiguous "the
constructor" is now an explicit named link.

## Finding 3 — Checked-read exception type stated once, not on the throwing accessors
**VERDICT: ABSENT**

Evidence: `src/Cache.jl:158` `velocity_physical` states "the throw is an `ErrorException` naming the
slot..." on its own docstring; `:215` `particle_velocities` states "throws an `ErrorException`, like
every cached read"; `vorticity_physical`/`scalar_physical` cross-reference "exactly
`velocity_physical`'s contract" by name rather than restate (consistent with the house
at-home-test policy). `src/SimulationRun.jl:392` `run!` now names "throws an `ArgumentError`"
explicitly, resolving the previously unnamed case on that page.

## Finding 4 — No worked example wiring `Simulation` tracers with `particle_velocities`/`sample!`
**VERDICT: ABSENT**

Evidence: `docs/src/api/Particles.md:8-23`, new "## Wiring tracers into a run" section with a
runnable snippet: `Simulation(...; number_of_particles = 4096)` → `warmup!` → `advance!` →
`particle_positions(sim.tracers)` / `particle_velocities(sim.cache)` /
`interpolate_at_particles!(out, velocity_physical(sim.cache), sim.tracers)`. (`sample!` itself was
renamed to `interpolate_at_particles!`, `number_of_tracers` to `number_of_particles` — followed the
concept, not the string.)

## Finding 5 — Grid-mode `Li2008` viscosity never cautioned against decaying (`NoForcing`) runs
**VERDICT: ABSENT**

Evidence: `src/SimulationRun.jl:116-120`, the "Setting the Reynolds number" section's Explicit-mode
bullet: "Grid mode is calibrated on a *stationary forced* balance (`Li2008`'s ``G`` is fitted to
forced-isotropic DNS), so a decaying run should set ``\nu`` explicitly: the resolution it buys is
only meaningful while the box sustains the energy the law assumes." Placed in the same section a
grid-mode reader would read.

## Finding 6 — `StructureFunctions` laws' "any other order throws" never names the exception type
**VERDICT: ABSENT**

Evidence: `src/phenomenology/StructureFunctions.jl:54` "any other `order` throws an `ArgumentError`";
`:156` "any other `order` throws an `ArgumentError`" (Yaglom1949); `:186-187` "any other `order`
throws an `ArgumentError`" (Lundgren2002). All three law docstrings now name the type explicitly,
matching the code (`throw(ArgumentError(...))` at `:72`, `:161`, `:192`).

## Finding 7 — `Simulation`'s "Keywords" section lists a positional argument under its own heading
**VERDICT: ABSENT**

Evidence: `src/SimulationRun.jl:122-124` — the section heading is now `# Arguments` (not `Keywords`),
prefaced "All keyword except `domain` (below)." The label/content mismatch the finding flagged no
longer exists; `domain`'s entry (`:128-130`) still explains it is positional, now under a heading
that doesn't contradict it.

## Finding 8 — `dissipation`'s two forms vs `scalar_dissipation`'s one form, no note on why
**VERDICT: ABSENT**

Evidence: `src/Observables.jl:201-204`, `scalar_dissipation`'s docstring now ends: "There is only
this one route: `dissipation`'s second form exists because the vorticity is a cached field a run
already holds, while ``\nabla\varphi`` is never recovered or cached, so a field-argument twin would
have nothing to consume." Directly supplies the missing rationale.
