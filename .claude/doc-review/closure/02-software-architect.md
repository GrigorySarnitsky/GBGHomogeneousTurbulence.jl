# Closure — Software-architect hat (02-software-architect.md)

## Finding 1 — Particle-velocities slot needs a hand-run two-call, cross-module protocol
**VERDICT: PRESENT**
Evidence: `src/Particles.jl` `record_particle_velocities!` (line ~236-243) still states "This call
is that slot's only producer of values, but it writes values only: the slot stays stale ... until
`deposit_sample!` records them as current." `src/Cache.jl` `particles_modified!` docstring
(line ~341-345) still instructs a hand-run loop to call `particles_modified!`, then
`record_particle_velocities!`, then `deposit_sample!`, "the write alone leaves the slot stale."
Contrast `deposit!` in `src/Propagator.jl` (line 508) still fills the other four slots atomically
in one call. Architecture unchanged; asymmetry intact.

## Finding 2 — Cache's checked-read guarantee is convention-only (struct fields share accessor names)
**VERDICT: PRESENT**
Evidence: `src/Cache.jl` `ObservablesCache` struct (line 124-138) still has public `const` fields
`velocity_physical`, `vorticity_physical`, `scalar_physical`, `particle_velocities` — identical
names to the checked accessor functions defined below them (lines 175, 191, 205, 234). No guard
against `cache.velocity_physical` bypassing `_checked`. `docs/src/observables_cache.md` §1.3
(line 117-118) still states "There is no path — internal or on request — by which reading causes a
computation," with no caveat about direct field access anywhere in `Cache.jl` or the design page
(grepped for "dot", "bypass", "field access", "private" — no hits on this topic).

## Finding 3 — FlowParameters.scalar_dissipation uses NaN sentinel, unlike every sibling "no scalar" case
**VERDICT: PRESENT**
Evidence: `src/Phenomenology.jl` line 117-124: `struct FlowParameters ... scalar_dissipation::Float64
end` — still concrete `Float64`, default `NaN` (line 127), with the same "keeps the bundle a plain,
type-stable set of `Float64`s" rationale (line 92) the finding disputes. Contrast confirmed still
true: `src/State.jl` line 53/58 (`scalar_spectral`, `nothing`), `src/Propagator.jl` (`nothing` for
absent buffers), `src/Cache.jl` line 109/111 (`scalar_physical`, `particle_velocities`, both
`nothing`-typed).

## Finding 4 — deposit! mutates ObservablesCache but is owned by Propagator, not Cache
**VERDICT: PRESENT**
Evidence: `src/Cache.jl` module docstring (line 29-30) still reads "The field slots are filled by
`deposit!`, which `Propagator` owns rather than this module because it needs the scheme's scratch
to recover the fields." `src/Propagator.jl` line 508 still defines
`function deposit!(cache::ObservablesCache, state::ResolvedFields, domain::FixedDomain,
buffers::IntegratorBuffers)` in `Propagator`, not `Cache`. Cross-module verb ownership unchanged.

## Finding 5 — AbstractForcing protocol states a return-value rule then documents an exception with no rationale
**VERDICT: PRESENT**
Evidence: `src/Forcing.jl` `AbstractForcing` docstring (lines 81-83) is byte-identical to the
quoted text: "Each mutating hook returns its mutated argument (`set_forcing_rate!` the rate,
`add_forcing_source!` the right-hand side, `apply_forcing!` the field); `prepare_forcing!` returns
`nothing`." No rationale sentence added anywhere in the surrounding docstring (lines 62-92) or in
`prepare_forcing!`'s own docstring (line 184-191) for why it alone returns `nothing` despite
mutating the forcing's own state.

## Finding 6 — FlowConditions/FlowParameters near-homonyms flagged in-doc rather than differentiated
**VERDICT: PRESENT**
Evidence: `src/Generator.jl` line 62-63 still reads "Not to be confused with `Phenomenology`'s
`FlowParameters`, which shares two field names: this type holds what a run is **configured with**,
that one holds what a run has been **measured to have**." Names unchanged (`FlowConditions`,
`FlowParameters`, both still carry `viscosity`/`schmidt` fields per `src/Generator.jl` line 84 and
`src/Phenomenology.jl` line 117-124). The disclaimer stands in place of differentiated names.

## Finding 7 — Glossary's one-sentence "deposit" definition doesn't cover deposit_sample!'s actual behavior
**VERDICT: PRESENT**
Evidence: `docs/src/notation.md` line 121 still defines "deposit | to write an observable into the
cache and mark the moment it belongs to" as one atomic act. `src/Cache.jl` `deposit_sample!`
docstring (line 264-282) still states it only marks: "Record the particle velocities already
written into `cache` ... as current" — the writing is a separate call,
`record_particle_velocities!` in `Particles.jl`. No exception noted in the glossary entry.

## Finding 8 — StationarityCriterion's keywords don't map onto its # Fields, unlike sibling types
**VERDICT: PRESENT**
Evidence: `src/SimulationRun.jl` line 614-617, `# Fields` section still reads "The fields are not
the keywords: `gate_skew`, `min_turnovers`, `window_turnovers`, `tol` and `skew_floor` all live
inside `monitor`" — same structural deviation, same explicit callout, no stated design rationale
beyond the description itself. `StationarityMonitor` struct (line 489-506) confirms the fields
genuinely live inside the sub-bundle.

## Finding 9 — step! and deposit!, always called back to back, lead with differently-typed first arguments
**VERDICT: PRESENT**
Evidence: `src/Propagator.jl` line 197-199, `step!`'s docstring, is essentially unchanged: "The
leading argument differs from `deposit!`'s in kind, and it is worth knowing which: `scheme` here is
a stateless dispatch tag, and what this call mutates is `state`, the second argument; `deposit!`
leads with `cache`, the object it mutates." The asymmetry and its self-acknowledgment both remain.
