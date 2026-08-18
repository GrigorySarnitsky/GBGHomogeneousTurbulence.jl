# Closure audit — Hat 12: Plain-sense editor

One verdict per banked finding, adjudicated against the current corpus only.

---

## 1. `step!`'s argument-order paragraph states an order that is false on its natural reading

**VERDICT: ABSENT**

`src/Propagator.jl:194-196` now reads: "The argument order is shared with `deposit!`... This
signature interleaves two more: `generator` directly after `state`, and `cache` then `dt` at the
end." The two interleaved facts are stated as separate clauses (`generator` after `state`; `cache`
then `dt` at the end), matching the signature `step!(scheme, state, generator, domain, buffers,
cache, dt)` exactly. The false "generator after both state and cache" reading is gone. `deposit!`'s
mirror sentence (`Propagator.jl:492-494`) is now one short clause, not a restated paragraph.

## 2. `deposit!`'s second sentence: ~95 words, five clauses, cost accounting where the reader wants the arguments

**VERDICT: ABSENT**

`src/Propagator.jl:463-482`: the docstring is now split into short paragraphs — deposit list and
recoveries first, then a standalone two-sentence cost paragraph ("Caching therefore costs an
iteration no transforms. It costs one pass: the maximum-speed reduction runs every iteration,
including under a hand-fixed ``\Delta t`` that never reads it."). No single sentence bundles the
deposit list, the transform count, the pass-count exception, and the `domain`/`buffers` explanation
together.

## 3. `Simulation`'s `initial_spectrum` entry nests parentheses two deep and buries its subject

**VERDICT: ABSENT**

`src/SimulationRun.jl:155-158`: "`initial_spectrum = nothing` — draw the initial velocity from a
`Phenomenology` `EnergySpectrum`... instead of the default large-scale Gaussian. The model is
evaluated at the run's state, with its integral scale taken as `1/envelope_wavenumber`, and the
result normalized to `kinetic_energy`." No nested parentheses. `grep` for "Gaussian envelope's
characteristic" and `peak_wavenumber` across `src/` and `docs/src/` returns nothing — the keyword
was renamed to `envelope_wavenumber` and the duplicated peak caveat is gone from this entry.

## 4. "not a filtered subset of the scales" — a fossil that plants the reading it denies

**VERDICT: ABSENT**

`docs/src/observables_cache.md:392-393`: "`fields_modified!` announces a change made outside an
iteration — the *resolved fields* being the two integrated fields — after which reads throw..." The
denial clause "not a filtered subset of the scales" is gone. `grep -rn "filtered subset" src/
docs/` returns no hits anywhere in the corpus.

## 5. Architecture §4.1's `State` bullet is one ~600-word paragraph containing an 85-word sentence

**VERDICT: PARTIAL**

`docs/ARCHITECTURE.md:192-226`, the `State` bullet. The flagged sentence itself is now split: "An
accessor (`velocity_physical`, `vorticity_physical`, `scalar_physical`, the cached `max_speed`)
serves the deposited value or throws; no read ever causes a computation." (211-213) — short, and the
epoch-counter/`fields_modified!`/decision-cite material has moved to its own paragraph after one
blank line (215-226). But the bullet is still a single, un-subdivided `-` item running ~35 lines with
only one internal paragraph break (not the state/recoveries/cache-contract three-way split the fix
asked for), and other sentences in it are still long multi-clause runs, e.g. lines 197-206 ("The
values land in the **`ObservablesCache`**... under the no-recompute rule (`docs/src/
observables_cache.md` is the design page; §11 decision 40)") and 194-199 ("The **chart map**... at
the sites that consume them, and the derived vorticity by `Observables.vorticity_physical!`
(decision 47)"). The specific flagged sentence was fixed; the class (long unbroken multi-clause
sentences packed into this one bullet) survives at those two lines.

**surviving_class**: `docs/ARCHITECTURE.md:194-199` and `197-206` — both still single sentences
chaining multiple clauses and a parenthetical decision cite, the same shape flagged in the original
finding.

## 6. Grid mode: a dangling "which" leaves the reader guessing what credits what

**VERDICT: ABSENT**

`src/SimulationRun.jl:107-108`: "**That criterion** treats the whole retained band as clean signal —
exact for `TwoThirds` and [`PhaseShift`](@ref)..., approximate for [`HouLi`](@ref)..." The dangling
"which" is gone, replaced by an explicit subject ("That criterion") almost exactly matching the
finding's suggested rewrite.

## 7. `step!`: "the step allocates and resides nothing"

**VERDICT: ABSENT**

`src/Propagator.jl:189-191`: "...so the step allocates nothing and occupies no storage beyond its own
spectral stage registers." The ungrammatical intransitive "resides" is gone, replaced by "occupies
no storage." (The sentence is still long, but the finding's specific grammar defect is fixed.)

## 8. `AbstractForcing` states the return-value contract twice

**VERDICT: ABSENT**

`src/Forcing.jl:77-79` carries the sole statement of the return contract ("Each mutating hook returns
its mutated argument (`set_forcing_rate!` the rate, `add_forcing_source!` the right-hand side,
`apply_forcing!` the field); `prepare_forcing!` returns `nothing`."). `grep -n "mutate and return\|
Three of the four hooks"` on `src/Forcing.jl` returns nothing — the first, redundant copy is gone.

## 9. The Particles page says "changing the scheme changes nothing here" three times

**VERDICT: ABSENT**

Only two instances remain in `src/Particles.jl`: line 169 ("the supertype exists so that adding one
changes no other type", on `AbstractParticleIntegrator`) and line 196 ("This storage belongs to the
scheme, not to the trajectory...", on `ParticleIntegratorBuffers`). The "tracer set" blurb and the
`Tracers` Fields restatement ("changes no part of this type") are both gone — `grep -n "changes
nothing here\|changes no part of this type"` on `src/Particles.jl` returns nothing. The two survivors
carry distinct content (type-extensibility vs. storage ownership), not verbatim restatement.

## 10. `truncate_to_band!`'s admonition argues about its own name and repeats the blurb above it

**VERDICT: ABSENT**

The "argues about its own name" half is gone: `grep -n "deliberately does not claim\|The name says"`
across `src/` and `docs/src/` returns nothing. The admonition (`src/SimulationDomain.jl:363-367`,
"Truncating the band is not always the whole of dealiasing") now adds content the blurb
(`docs/src/api/SimulationDomain.md`, "Band truncation" section) does not: the `TwoThirds`/`HouLi`
behavior and the actionable consequence ("calling it on a product assembled without the
displaced-evaluation average leaves that product aliased"). It restates the `PhaseShift`-is-half fact
from the blurb, but no longer as pure repetition — it is now the operationally useful elaboration.

## 11. The `Cache` module map points at verbs a reader cannot look up

**VERDICT: ABSENT**

`src/Cache.jl:11-32`, the module docstring, no longer mentions internal "deposit"/"take" verbs or
"move the individual epochs." `grep -n "deposit and take verbs\|move the individual epochs"` on
`src/Cache.jl` returns nothing; the map now says only "Each slot carries the value **and** the epoch
that value belongs to... The solver's side of the contract is `deposit!`..."

## 12. Architecture §4.7 explains an API that no longer exists

**VERDICT: ABSENT**

`docs/ARCHITECTURE.md` §4.7 (lines 432-461) now states the current API only: "A `Simulation` is a
container, not a reading surface (decision 49). The state is read through `sim.state` and the
deposited observables through `sim.cache`..." The removed-forwarders explanation
("forwarders bought a shorter call...") lives exactly once, in the decision log at line 1669 (decision
49) — not in §4.7. `grep -n "run layer once carried\|hid this split"` returns nothing anywhere.

## 13. "A fifth name is not a hook" — a denial with nothing to deny

**VERDICT: ABSENT**

`src/Forcing.jl:31-33`: "[`DeferredForcing`](@ref) is the operator-free keyword form of a strategy,
materialized once the [`Simulation`](@ref)... has built the domain — a construction-time object, not
a lifecycle hook." Subject-first, matching the finding's suggested rewrite; `grep -n "fifth name"` on
`src/Forcing.jl` returns nothing.

## 14. `Simulation` glosses the docs' own house word inside its own docstring

**VERDICT: ABSENT**

`src/Cache.jl:78-79` now reads "The [`Simulation`](@ref)... front door builds, wires, and seeds one
for you; a hand-assembled run constructs it here" — the self-referential parenthetical ("the
convenience constructor that builds every component") is gone. `grep -rn "front door" src/*.jl` shows
plain uses at every other site (`Generator.jl:189`, `SimulationDomain.jl:49`) with no repeated gloss;
`docs/src/notation.md:123` carries the single legitimate glossary definition. One minor residual
appositive survives at `src/Particles.jl:62-64` ("the build-everything convenience constructor") but
it does not name or explain the term "front door" itself, unlike the flagged self-referential form.

## 15. `run!` leaks the audit ledger into the front-door loop verb

**VERDICT: ABSENT**

`src/SimulationRun.jl:405-423`, the `run!` docstring, no longer mentions the maximum-speed reduction
or host readback at all. `grep -n "host readback\|even under a fixed"` on `src/SimulationRun.jl`
returns nothing; the cost note survives only in `deposit!` (`src/Propagator.jl:481`).

## 16. "a solver with no cache serving only its own dynamics" — a dangling modifier

**VERDICT: ABSENT**

`docs/src/observables_cache.md:144`: "...so, relative to a **cacheless solver** serving only its own
dynamics, the run pays one extra closing deposit..." The compound adjective "cacheless" now modifies
"solver" directly, removing the two-parse ambiguity the finding flagged.

## 17. `SaffmanDissipation`: "about half the earlier Townsend 1951 spectrum"

**VERDICT: ABSENT**

`src/phenomenology/Spectra.jl:230-236`: "...roughly half the **cutoff coefficient** of the earlier
Townsend 1951 form... whose coefficient varies with **the derivative skewness `S`** — about `2.6` to
`3.3` across the range of `S` that paper considers — and is simplified downward to `2` here... which
retains more near-cutoff energy **than a measured spectrum shows**." All three ambiguities named in
the finding (half of what; which skewness; which physical range) are now explicit.

## 18. `PhaseShift`: a relative clause torn from its noun by a 14-word gloss

**VERDICT: ABSENT**

`src/SimulationDomain.jl:109-111`: "...cancels the aliasing images **that wrap in an odd number of
axes** — the aliasing images being the spurious spectral replicas... — while the spherical cutoff
removes the surviving two-axis images." The restrictive clause now sits directly against its noun,
with the gloss moved after it — matching the finding's suggested rewrite.

## 19. `particle_scheme` apologises for a name instead of stating what it does

**VERDICT: ABSENT**

The naming collision is resolved at the source: `src/SimulationRun.jl:162-166` now uses
`interpolation_scheme` (spatial) and `trajectory_scheme` (temporal) — clearly distinct names, not
`tracer_scheme`/`particle_scheme`. `grep -n "despite the neighbouring names"` on `src/SimulationRun.jl`
returns nothing; no apology text remains.

## 20. The epoch-vs-step worked example is printed four times, verbatim

**VERDICT: ABSENT**

The worked numeric example ("clock reads step 2 and the fields epoch reads 4") now appears at only
two sites: `src/SimulationRun.jl:347-348` (`current_step` docstring) and `docs/ARCHITECTURE.md:1734`
(decision log; `docs/src/architecture.md` is a byte-identical build copy of the same source, not an
independent third copy). `src/Cache.jl`'s module docstring and `docs/src/observables_cache.md` §1.3
no longer contain it (`grep` for "after two steps and one announced mutation" / "fields epoch reads
4" on both returns nothing). The `ObservablesCache` Fields entry keeps a short non-numeric paraphrase
("will run ahead of `current_step`", `src/Cache.jl:112`), not the verbatim example.

## 21. The notation page states the ϰ-distinctness convention twice

**VERDICT: ABSENT**

The "Conventions" table (`docs/src/notation.md:14-19`) no longer carries a ϰ row — only "Wavenumber
clash" (``\boldsymbol{\kappa}``/``\kappa``/``k``) remains there. Only one occurrence of the
distinctness statement survives, the free-floating parenthetical under "Parameters"
(`docs/src/notation.md:49-50`). The duplication is gone, even though the specific half cut (table vs.
parenthetical) is the opposite of the finding's suggested direction.

## 22. "That is bookkeeping, not a slogan"

**VERDICT: ABSENT**

`docs/src/observables_cache.md` §1.4 ("What caching costs", lines 188+) no longer contains this
clause; `grep -n "bookkeeping, not a slogan\|not a slogan"` on the file returns nothing. The
replacement text goes straight to the evidence: "Each clause of that is an accounting statement:
every slot is a register the iteration fills anyway (§1.2)..."
