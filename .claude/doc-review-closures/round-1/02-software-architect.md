# Closure audit — 02-software-architect

## 1. `tracer_scheme` renaming collision with `particle_scheme`
**VERDICT: ABSENT**
`src/SimulationRun.jl`: the front-door keyword is now `interpolation_scheme` (matches `Tracers`'
own keyword exactly, line 226), and the temporal axis is now named `trajectory_scheme` (not
`particle_scheme`), clearly distinct from `interpolation_scheme`. No "despite the neighbouring
names" disclaimer remains (`grep` for it returns nothing). Three names collapsed to two, each
distinct.

## 2. `advect!`'s argument order breaks `state, domain, buffers`
**VERDICT: ABSENT**
`src/Particles.jl:248,282`: `advect!(scheme, tracers, velocity_end, domain, buffers, dt)` — `domain`
now precedes `buffers`, matching `step!`/`deposit!`'s order exactly, as the resolution hint asked.

## 3. `Simulation` exposes `buffers`/`generator` at the same level as `state`/`cache`
**VERDICT: PRESENT**
`src/SimulationRun.jl` `# Fields` (lines ~178–190) still lists `domain, buffers, generator, scheme`
before `state`/`cache` with no safety distinction; no "unsafe to read mid-run" language anywhere in
the file (`grep -n "unsafe\|between steps\|register\b" src/SimulationRun.jl` → empty). The
"container, not a reading surface" module docstring (line 30) and `ARCHITECTURE.md` decision 49
still only name `sim.state`/`sim.cache` as the sanctioned reads; `buffers`/`generator` remain
ordinary struct fields with no flag.

## 4. Reused forcing instance across `velocity_forcing`/`scalar_forcing` unguarded
**VERDICT: ABSENT**
`src/Generator.jl:96-100`: `FlowConditions` constructor now checks
`ismutable(velocity_forcing) && velocity_forcing === scalar_forcing` and throws an `ArgumentError`
naming the strategy, matching the rate-declaration-mismatch discipline exactly as the resolution
hint requested. A `#` comment explains why the check is `ismutable`-gated (immutable strategies
compare by value, so aliasing is harmless for them).

## 5. `FlowParameters.scalar_dissipation` `NaN` sentinel vs `nothing` convention
**VERDICT: PRESENT**
`src/Phenomenology.jl:69-93`: default is still `scalar_dissipation = NaN`; the docstring still
states "It is a **sentinel, not a value that propagates**" and now adds "A caller needs no guard of
its own" (line 93) — an even more general, still-unscoped claim. The "does not propagate" guarantee
remains true only for the bundled `Phenomenology` law evaluators (which check first, line 91-92),
not for direct arithmetic on `fp.scalar_dissipation`; the class-wide `nothing` convention used by
`Cache`/`IntegratorBuffers` is not adopted here.

## 6. Cache's epoch invariant is written by `deposit!`, homed in `Propagator`
**VERDICT: PRESENT**
`src/Cache.jl:29-31`: "The solver's side of the contract is `deposit!` ... — homed in `Propagator`
... which fills every slot at the iteration's end and sets its epoch. A caller reads through the
accessors and never deposits." The write side of the epoch invariant still lives outside `Cache`,
and no include-order (or any other) reason is given anywhere in the module for the split.

## 7. `particle_velocities` is externally-owned aliased storage, asymmetric with other slots
**VERDICT: PRESENT**
`src/Cache.jl`: the opening paragraph of `ObservablesCache`'s docstring (lines 63-79, "The
observables cache of a run — the storage where each iteration deposits...") still does not mention
the ownership asymmetry; the aliasing note ("the slot **is** that array...") is still confined to
the constructor's keyword description (line 76-78), exactly the placement the resolution hint asked
to change ("in the type's opening paragraph rather than only in the constructor's keyword
description").

## 8. `k_max_η` mixes ASCII-folded κ with literal Unicode η
**VERDICT: REGRESSED**
`src/SimulationRun.jl:131-132`: the keyword itself is now fully Unicode `κ_max_η` (confirmed by
hex-dump: `ce ba` = κ, `ce b7` = η) — the ASCII fold was *reverted*, not completed. But the
docstring prose at line 131-132 still reads "the keyword spells ``\kappa_{\max}`` in ASCII", which
is now flatly false: the keyword does not spell κ in ASCII at all, it uses literal Unicode κ. The
original half-transliteration defect became an outright false claim.

## 9. Explicit mode silently ignores `k_max_η` (now `κ_max_η`) when `viscosity` is also given
**VERDICT: PRESENT**
`src/SimulationRun.jl:229-238`: `if isnothing(viscosity) ... else ν = Float64(viscosity) end` — no
warning or error when both `viscosity` and a non-default `κ_max_η` are supplied; the docstring
(line 116) still states plainly "`κ_max_η` is ignored" with no caveat about a combined-argument
warning. No code path checks for this combination anywhere in the constructor.

## 10. The four `AbstractForcing` hooks reuse `field` for three distinct instants
**VERDICT: PRESENT**
`src/Forcing.jl`: `set_forcing_rate!(::AbstractForcing, rate, field, domain)` (line 132),
`apply_forcing!(::AbstractForcing, field, domain)` (line 160), and
`prepare_forcing!(::AbstractForcing, field, domain, dt)` (line 170) all still name their field
argument `field`; `apply_forcing!`'s docstring (line 154-159) still describes it generically as "a
velocity or scalar field" with no distinction from the start-of-step `field` in the other two hooks.
No renaming (e.g. `advanced_field`) was applied.
