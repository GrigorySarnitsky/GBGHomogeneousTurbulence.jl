# Closure audit — Hat 21: cold-reader

## 1. Epoch counter: "staleness counter" vs "freshness counter"
**VERDICT: ABSENT**
Evidence: `rg "staleness counter"` across `src/`, `docs/src/`, `docs/build/`, `CLAUDE.md` returns zero
hits. `docs/src/index.md:51` (Home) now reads "the epoch — the cache's freshness counter — is what a
read is checked against", matching `src/Propagator.jl:203,509` and `src/State.jl:103,194`, all
"freshness counter". The two-name contradiction is gone; one vocabulary word wins everywhere.

## 2. Cache page's hand-run recipe calls two undefined verbs
**VERDICT: ABSENT**
Evidence: `src/Cache.jl:410-415` (`particles_modified!` docstring) now names
`record_particle_velocities!` and `restart!` as `@ref GBGIsotropicTurbulence.Particles.…` links; the
built page `docs/build/api/Cache/index.html` renders `record_particle_velocities!` as
`<a href="../Particles/#GBGIsotropicTurbulence.Particles.record_particle_velocities!">`. `deposit_sample!`
(`src/Cache.jl:21-22`) is likewise cross-linked. A reader on the Cache page can now click straight to
the definition instead of guessing from the bare name.

## 3. `history_depth`'s source not stated where needed
**VERDICT: ABSENT**
Evidence: `src/Cache.jl:88-91`, the `ObservablesCache` constructor's `# Arguments` entry for
`history_depth`, now reads "the value of `[history_depth](@ref …Particles.history_depth)(trajectory_scheme)`
for the run's trajectory scheme, which is where a hand-assembled run gets the number." The exact gap
the finding flagged — the connection stated only in reverse, only on the Particles page — is closed at
the site the finding quoted.

## 4. `VarianceController` breaks the forcing family's constructor pattern, unexplained
**VERDICT: ABSENT**
Evidence: `src/Forcing.jl:602` now defines `VarianceController(domain::FixedDomain; target, gain=1,
turnover_time=nothing, lowest_shell=1, highest_shell=2)`, the same `Strategy(domain; …)` shape as its
siblings. `DeferredForcing`'s enumeration (`src/Forcing.jl:143`) now lists `VarianceController(; target,
gain=1, turnover_time=nothing, lowest_shell=1, highest_shell=2)` alongside `Linear`/`ConstantPower`/
`VarianceRescaling`. The asymmetry the finding flagged no longer exists.

## 5. "Lie–Trotter operator splitting" backs a claim with no gloss anywhere
**VERDICT: ABSENT**
Evidence: `src/Forcing.jl:371-372` (`VarianceRescaling` docstring, rendered on `docs/src/api/Forcing.md`
via its `@docs` block) now reads "…which is Lie–Trotter operator splitting — the step's map and the
rescale's map composed one after the other, a composition whose error is `O(Δt)` regardless of how
accurate either map is alone." The term is now defined inline, in plain terms, at its own point of use.

## 6. `flow_parameters` points at an undocumented-so-far module on the first API page
**VERDICT: PRESENT**
Evidence: `src/SimulationRun.jl:28` (module docstring one-liner) is unchanged, verbatim: "`flow_parameters`
— the run's measured flow state as a `Phenomenology` `FlowParameters`." — plain-text mentions, no `@ref`
on either noun, on the page the api.md reading order still puts first. `Phenomenology`/`FlowParameters`
are still not documented until the last page group. (The function's own docstring, `SimulationRun.jl:449`,
does link both — but the module-map one-liner the finding quoted is untouched.)

## 7. "checked reads" vs "checked accessors" vocabulary drift
**VERDICT: PRESENT**
Evidence: `docs/src/index.md:104-106` (Home) still reads "…leaves the observables it produced, read
through checked accessors that serve the deposited value or throw." `docs/src/api/Cache.md:20` still
reads "## The checked reads", and `docs/src/api.md:16` independently says "checked reads". Confirmed
live in the rendered build (`docs/build/index.html` vs `docs/build/api/Cache/index.html`, section anchor
`#The-checked-reads`). The two labels for the identical concept still disagree between the two pages a
reader is likeliest to compare.

## 8. `particle_velocities` names both a checked accessor and a bare struct field
**VERDICT: ABSENT**
Evidence: `src/Cache.jl:258-262` (`particle_velocities(cache)` docstring, the reader's *first* meeting
of the name) now states directly: "Treat the returned array as read-only — it is the tracer set's own
storage, and the tracer advance writes into it mid-iteration." This flags the shared-storage relationship
with `tracers.particle_velocities` at first meeting rather than only later on the Particles page, closing
the forward-reference gap the finding logged (itself already low-severity/low-confidence).

---

### Summary
- ABSENT: 1, 2, 3, 4, 5, 8 (6 of 8)
- PRESENT: 6, 7 (2 of 8)
- PARTIAL / REGRESSED / NOT-A-DEFECT: none
