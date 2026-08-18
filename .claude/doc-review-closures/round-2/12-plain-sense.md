# Closure — Hat 12: Plain-sense editor

## 1. `step!`'s argument-order paragraph — false-on-natural-reading order
**ABSENT** — `src/Propagator.jl:194-197` now reads "This signature interleaves two more: `generator`
directly after `state`, and `cache` then `dt` at the end" — matches the actual signature
`step!(scheme, state, generator, domain, buffers, cache, dt)` unambiguously; `deposit!` (line 493-494)
mirrors it correctly too. No "generator after state and cache" phrasing remains anywhere in the file.

## 2. `deposit!`'s ~95-word second sentence
**ABSENT** — `src/Propagator.jl:464-498` is now four short paragraphs: deposit list, what the
recoveries use `domain`/`buffers` for (stated plainly, not buried), a standalone pass-count-exception
sentence, and the particle-velocities carve-out. No single sentence carries more than one claim.

## 3. `Simulation`'s `initial_spectrum` — nested parens, buried subject
**ABSENT** — `src/SimulationRun.jl:155-159`: one clean sentence for the option; the shell-spectrum-peak
caveat lives only at `envelope_wavenumber` (line 152-154), not duplicated here. No nested parentheses.

## 4. "not a filtered subset of the scales" — unprovoked defence
**ABSENT** — `docs/src/observables_cache.md:392-394`: "the *resolved fields* being the two integrated
fields — after which reads throw…" — the denial clause is gone. Grepped `filtered subset` repo-wide: no hits.

## 5. Architecture §4.1 `State` bullet — 600-word paragraph, 85-word sentence
**ABSENT** — `docs/src/architecture.md:174-226`: now two paragraphs (chart map / cache contract, then
freshness / epochs / initial conditions / scratch). The flagged accessor sentence (line 211-213) is now
short and standalone; the chained no-recompute/epoch/step!/decision-cite content moved to its own
paragraph starting "Freshness is tracked…" (line 215).

## 6. Grid mode — dangling "which"
**ABSENT** — `src/SimulationRun.jl:111-112`: "**That** criterion treats the whole retained band as
clean signal — exact for `TwoThirds` and `PhaseShift`, approximate for `HouLi`…" — explicit subject
("That criterion"), no dangling pronoun.

## 7. `step!`: "the step allocates and resides nothing"
**ABSENT** — `src/Propagator.jl:190`: "so the step allocates nothing and occupies no storage beyond
its own spectral stage registers" — grammatical, matches the suggested rewrite's meaning.

## 8. `AbstractForcing` states the return-value contract twice
**ABSENT** — `src/Forcing.jl:70-79`: only one statement of the contract now ("Each mutating hook
returns its mutated argument…; `prepare_forcing!` returns `nothing`"). Grepped for "Three of the four"
and "second argument": no hits.

## 9. Particles page: "changing the scheme changes nothing here" ×3
**ABSENT** — repo-wide grep for "changes nothing"/"changes no part"/"changes no other" finds exactly
one instance (`src/Particles.jl:169`, on `AbstractParticleIntegrator`) plus one non-verbatim paraphrase
on `ParticleIntegratorBuffers` (line 196: "belongs to the scheme, not to the trajectory"). No triple
repetition survives; the `Tracers` Fields entry no longer states it at all.

## 10. `truncate_to_band!` admonition — argues about its own name
**ABSENT** — `src/SimulationDomain.jl:364-368`: admonition retitled "Truncating the band is not always
the whole of dealiasing", now adds per-strategy facts (`TwoThirds`/`HouLi`/`PhaseShift`) beyond the
blurb above it, with no self-referential "the name says" language. Grepped for "The name says" and
"deliberately does not claim": no hits.

## 11. `Cache` module map — unlookupable internal verbs
**ABSENT** — `src/Cache.jl:10-27` (module map) no longer mentions internal "deposit and take" verbs or
"move the individual epochs"; grep for both phrases across `src/Cache.jl` returns nothing.

## 12. Architecture §4.7 explains a removed API
**ABSENT** — `docs/src/architecture.md:431-464` (§4.7, current state) no longer mentions the retired
forwarding methods; that history now lives solely in §11 decision 49 (line 1662-1675), the correct
historical home. §4.7 states only "A `Simulation` is a container… (decision 49)" with an @ref-style
pointer, no removal narrative.

## 13. "A fifth name is not a hook" — denial with nothing to deny
**ABSENT** — `src/Forcing.jl:31-33`: "`DeferredForcing` is the operator-free keyword form of a
strategy, materialized once the `Simulation` has built the domain — a construction-time object, not a
lifecycle hook." Subject-first, no "fifth name" framing. Grepped "fifth name": no hits.

## 14. `Simulation` glosses "front door" inside its own docstring
**ABSENT** — `src/SimulationRun.jl:74-75`, `src/Cache.jl:78`, `src/Generator.jl:189`,
`src/SimulationDomain.jl:49` all use "front door" bare, with no self-referential parenthetical
defining the term. Grepped "names exactly this convenience"/"convenience form throughout": no hits.

## 15. `run!` leaks the audit ledger into the front-door loop verb
**ABSENT** — `src/SimulationRun.jl:405-439`: the per-iteration host-readback cost sentence is gone;
the docstring now states what the callback receives and how continuation is decided, with the cost
note left to live in `deposit!`/the design page as recommended.

## 16. "a solver with no cache serving only its own dynamics" — dangling modifier
**ABSENT** — `docs/src/observables_cache.md:144`: "relative to a **cacheless solver** serving only its
own dynamics" — "cacheless" is now a single adjective directly on "solver", removing the two-parse
ambiguity of "with no cache".

## 17. `SaffmanDissipation`: "about half the earlier Townsend 1951 spectrum"
**ABSENT** — `src/phenomenology/Spectra.jl:232-239`: "roughly half **the cutoff coefficient** of the
earlier Townsend 1951 form… whose coefficient varies with **the derivative skewness S**" — both the
halved quantity and the named skewness are now explicit in the same sentence.

## 18. `PhaseShift`: relative clause torn from its noun
**ABSENT** — `src/SimulationDomain.jl:109-111`: "cancels the aliasing images **that wrap in an odd
number of axes** — the aliasing images being the spurious spectral replicas…" — the restrictive clause
now sits immediately after its noun; the gloss follows as a trailing appositive, exactly the suggested
restructuring.

## 19. `particle_scheme` apologises for a name
**ABSENT** — `src/SimulationRun.jl:162-164,232`: the keyword is now `interpolation_scheme` throughout
(matching `Tracers`' own keyword name); no `tracer_scheme`/`particle_scheme` collision or apology
remains. Grepped both spellings and "despite the neighbouring names" repo-wide: no hits.

## 20. Epoch-vs-step worked example printed four/five times
**ABSENT** — the verbatim "step 2 / fields epoch reads 4" example now appears exactly twice
(`src/SimulationRun.jl:347-348`, the `current_step` docstring, and `docs/src/architecture.md:1733`, the
decision-log historical record). `docs/src/observables_cache.md` and the `Cache.jl` module docstring no
longer state it; the `ObservablesCache` Fields entry (`src/Cache.jl:110-113`) uses distinct, non-numeric
prose ("will run ahead of `current_step`") that carries information proper to that field entry rather
than repeating the worked example.

## 21. Notation page states the ϰ-distinctness convention twice
**ABSENT** — `docs/src/notation.md`: the Conventions table's "Wavenumber clash" row (line 20) no longer
mentions ``\varkappa`` at all; only the Parameters section's parenthetical (line 49-50) states the
distinctness now. One instance, not two.

## 22. "That is bookkeeping, not a slogan"
**ABSENT** — `docs/src/observables_cache.md:190-193`: the clause is gone; the paragraph now opens
directly with "Each clause of that is an accounting statement: every slot is a register the iteration
fills anyway…". (A different "not a promise" at line 107 was checked and found substantive — it
contrasts fixed contents against contents that change with future storage decisions — not a defensive
denial of an unstated accusation, so it is not an instance of this finding's class.)
