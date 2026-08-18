# Closure audit — Hat 12: Plain-sense editor

## 1. `step!`'s argument-order paragraph states a false order
**VERDICT: ABSENT**
Rewritten at `src/Propagator.jl:195-197`: "generator directly after state, and cache then dt at the
end" — matches signature `step!(scheme, state, generator, domain, buffers, cache, dt)` exactly (generator
is 3rd, directly after state 2nd; cache 6th and dt 7th are the trailing pair). `deposit!`'s paragraph
(`src/Propagator.jl:491-492`) states the shared order consistently. No false claim remains; searched both
docstrings in full.

## 2. `deposit!`'s second sentence: cost accounting buries the arguments
**VERDICT: REGRESSED**
The complaint's substance is largely addressed — the arguments (`domain`, `buffers`) now get their own
sentence and the cost claim is split into two short closing sentences (`src/Propagator.jl:466-478`). But
the edit left a duplicated word: `src/Propagator.jl:470-471` reads "...(the cache's freshness counter).
The\nThe deposits are the next iteration's..." — renders in `docs/build/api/Propagator/index.html` as
"...freshness counter). The The deposits are...". New defect, same docstring.

## 3. `Simulation`'s `initial_spectrum` entry: nested parens, buried subject
**VERDICT: ABSENT**
Rewritten at `src/SimulationRun.jl:151-154`: one sentence for what the option does, no nested
parentheses, and the duplicated peak-location caveat is gone (left solely with `envelope_wavenumber`
above it, `src/SimulationRun.jl:149-151`). Matches the finding's suggested fix directly.

## 4. "not a filtered subset of the scales" — unprovoked defence
**VERDICT: ABSENT**
`grep -rn "filtered subset|scale-filtered|filtered scales"` across `docs/src`, `src/*.jl`, and
`docs/ARCHITECTURE.md` returns nothing. Current text at `docs/src/observables_cache.md:174-176`: "the
*resolved fields* being the two integrated fields — after which reads throw..." — the denial clause is
gone.

## 5. Architecture §4.1's `State` bullet: 600-word paragraph, 85-word sentence
**VERDICT: ABSENT**
`docs/ARCHITECTURE.md:191-214` (§4.1): the flagged sentence is now its own short sentence — "An accessor
(...) serves the deposited value or throws; no read ever causes a computation." — followed by a paragraph
break, then a new paragraph "Freshness is tracked by one epoch counter... `step!` advances the fields
epoch as it completes. An out-of-band mutation..." as three separate sentences instead of one chained
85-word sentence. The five-clause run-on quoted by the finding no longer exists.

## 6. Grid mode: dangling "which"
**VERDICT: ABSENT**
`src/SimulationRun.jl:108`: "That criterion treats the whole retained band as clean signal — exact for
`TwoThirds` and `PhaseShift`, approximate for `HouLi`..." — "which" replaced by "That criterion" as an
explicit subject, matching the finding's suggested rewrite almost verbatim.

## 7. `step!`: "the step allocates and resides nothing"
**VERDICT: ABSENT**
`src/Propagator.jl:188-189`: "...so the step allocates nothing and occupies no storage beyond its own
spectral stage registers." The intransitive misuse of "resides" is gone. (The sentence is not literally
split as the fix also suggested, but the grammatical defect quoted by the finding is fixed.)

## 8. `AbstractForcing` states the return-value contract twice
**VERDICT: ABSENT**
`grep -n "Three of the four hooks|read-only" src/Forcing.jl` returns nothing. Only one contract statement
remains, at `src/Forcing.jl:77-79`: "Each mutating hook returns its mutated argument (...); prepare_forcing!
returns nothing." The duplicate lead-in sentence is gone.

## 9. Particles page: "changing the scheme changes nothing" x3
**VERDICT: PARTIAL**
The exact quoted "tracer set" module-blurb instance is gone (module docstring at `src/Particles.jl:17-29`
now reads plainly, no "changes nothing" phrasing). But the class survives at two other sites: `Tracers`
Fields (`src/Particles.jl:124`, "...so changing the scheme changes no part of this type.") and
`AbstractParticleIntegrator` (`src/Particles.jl:169`, "...the supertype exists so that adding one changes
no other type."). `ParticleIntegratorBuffers` (`src/Particles.jl:196`, kept per the finding's own
recommendation) makes three total renderings of the same point still on the page.
**surviving_class:** `src/Particles.jl:124` (`Tracers` Fields), `src/Particles.jl:169`
(`AbstractParticleIntegrator`).

## 10. `truncate_to_band!`'s admonition argues about its name / repeats the blurb
**VERDICT: PRESENT**
The "argues about its own name" framing is fixed — the admonition title is now "Truncating the band is
not always the whole of dealiasing" (`src/SimulationDomain.jl:359-364`), no longer "the name says...". But
the redundancy complaint stands: the admonition still restates the same PhaseShift fact as the blurb
immediately above it in `docs/src/api/SimulationDomain.md:51-56` ("Under `PhaseShift` this is only part
of the dealiasing — the averaging of two displaced evaluations is the other half") almost verbatim
("`PhaseShift` is the case to watch: it cancels its aliases by *averaging two displaced evaluations*...
the truncation here is only the second half"). The admonition was not cut as the fix asked.

## 11. `Cache` module map points at unlookupable internal verbs
**VERDICT: ABSENT**
`grep -rn "move the individual epochs|take verbs|internal per-slot deposit"` across `src/` and `docs/src/`
returns nothing. Current module docstring (`src/Cache.jl:9-38`) lists only public, linkable operations.

## 12. Architecture §4.7 explains a removed API
**VERDICT: ABSENT**
§4.7 (`docs/ARCHITECTURE.md:430-460`) no longer carries the removal sentence. The near-identical sentence
("The forwarders bought a shorter call at the price of a second docstring per quantity...") now lives only
in the decision log, §11 decision 49 (`docs/ARCHITECTURE.md:1658-1665`) — exactly where the finding said
the record belongs.

## 13. "A fifth name is not a hook" — denial with nothing to deny
**VERDICT: ABSENT**
`src/Forcing.jl:31-33` now opens subject-first: "`DeferredForcing` is the operator-free keyword form of a
strategy, materialized once the `Simulation` has built the domain — a construction-time object, not a
lifecycle hook." No "fifth name" framing remains (`grep -n "fifth name" src/Forcing.jl` empty).

## 14. `Simulation` glosses "front door" inside its own docstring
**VERDICT: PARTIAL**
The self-referential parenthesis is cut from `Simulation`'s own docstring (`src/SimulationRun.jl:70-71`
now just uses **front door** in bold with no meta-gloss). But the class survives at every other mention
the finding named: `src/Cache.jl:82-84` ("The `Simulation` front door — the convenience constructor that
builds every component — builds, wires, and seeds one for you" — itself now redundant with the sentence
two lines above it at `Cache.jl:81-82`), `src/Generator.jl:220-221`, and
`src/SimulationDomain.jl:48-49`, all still carrying the "the convenience constructor that builds every
component" gloss verbatim.
**surviving_class:** `src/Cache.jl:82-84`, `src/Generator.jl:220-221`, `src/SimulationDomain.jl:48-49`.

## 15. `run!` leaks the audit ledger into the front-door loop verb
**VERDICT: ABSENT**
`src/SimulationRun.jl:409-421` (`run!`'s docstring): no mention of "host readback" or the maximum-speed
per-iteration cost claim. `grep -rn "host readback"` across `src/SimulationRun.jl`,
`docs/src/observables_cache.md` returns nothing; the phrase survives only in `docs/ARCHITECTURE.md`'s
decision-log / audit sections, not in `run!`.

## 16. "a solver with no cache serving only its own dynamics" — dangling modifier
**VERDICT: ABSENT**
`docs/src/observables_cache.md:143-144` now reads "...relative to a cacheless solver serving only its own
dynamics, the run pays one extra closing deposit..." — the compound adjective "cacheless" removes the
"cache"-as-noun ambiguity the finding flagged; the sentence has one grammatical parse.

## 17. `SaffmanDissipation`: "about half the earlier Townsend 1951 spectrum"
**VERDICT: PRESENT**
Partially addressed: `src/phenomenology/Spectra.jl:232-238` now says "roughly half the *cutoff
coefficient*" — the "half of what" ambiguity is resolved. But the other two complaints remain verbatim:
"whose coefficient is skewness-dependent (about 2.6 to 3.3)" still names no skewness quantity anywhere on
the page (`grep -n "skewness" src/phenomenology/Spectra.jl` finds only this one use), and "retaining a
little more near-cutoff energy than the physical range would" still leaves "the physical range"
unspecified.

## 18. `PhaseShift`: relative clause torn from its noun by a 14-word gloss
**VERDICT: PRESENT**
Unchanged at `src/SimulationDomain.jl:108-110`: "cancels the aliasing images — the spurious spectral
replicas that the under-resolved quadratic product folds back into the resolved band — that wrap in an
odd number of axes" — the restrictive clause is still separated from "aliasing images" by the em-dash
gloss, exactly as quoted.

## 19. `particle_scheme` apologises for a name instead of stating what it does
**VERDICT: ABSENT**
The naming collision is resolved at the source: the front-door keyword is now `interpolation_scheme`
(matching `Tracers`' own keyword, `src/SimulationRun.jl:157-159`) and the time-integration keyword is
`trajectory_scheme` (`src/SimulationRun.jl:165-167`) — no longer neighbouring, confusable names.
`grep -rn "despite the neighbouring|particle_scheme\b"` across `src/*.jl` and `docs/src/*.md` returns
nothing; the apology clause is gone because the keywords it excused no longer collide.

## 20. The epoch-vs-step worked example printed four times
**VERDICT: PARTIAL**
Reduced but not to the two docstring copies the fix asked for. Removed from `src/Cache.jl`'s module
docstring (now an abstract note with no "step 2 / epoch 4" numbers, `src/Cache.jl:34-38`) and from the
design page (`docs/src/observables_cache.md`, no hits on the literal numbers). Survives at
`src/SimulationRun.jl:346-348` (`current_step`, one docstring copy — fine) and, unchanged, in the decision
log at `docs/ARCHITECTURE.md:1727-1730` (§11) — which the finding also counted against the total, and
which now additionally *misdescribes* the corpus: it claims "the `Cache` docstring now states it outright"
with the numeric example, but that example is no longer in `src/Cache.jl`. The `ObservablesCache` Fields
entry still carries the prose fragment "will run ahead of `current_step`" (`src/Cache.jl:111-113`).
**surviving_class:** `docs/ARCHITECTURE.md:1727-1730` (decision log, and now stale relative to
`src/Cache.jl`), `src/Cache.jl:111-113` (Fields-list fragment).

## 21. The notation page states the ϰ-distinctness convention twice
**VERDICT: ABSENT**
The Conventions-table "Wavenumber clash" row (`docs/src/notation.md:19`) no longer mentions ``\varkappa``
at all — only ``\boldsymbol\kappa``/``\kappa``/``k``. The statement now appears exactly once, as the
free-floating parenthetical under Parameters (`docs/src/notation.md:49-50`). The duplication the finding
flagged is gone, though the surviving copy is the one the finding's fix said to cut rather than keep.

## 22. "That is bookkeeping, not a slogan"
**VERDICT: PRESENT**
Unchanged at `docs/src/observables_cache.md:190`: "...the price of a schedule that never varies with how
the run is driven. That is bookkeeping, not a slogan: every slot is a register the iteration fills
anyway..." — verbatim, still a denial with no accusation to answer.
