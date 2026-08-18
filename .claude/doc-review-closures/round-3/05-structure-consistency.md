# Closure audit — hat: structure-consistency

## Finding 1 — Admonition titling not uniform (bare Note/Warning vs custom titles)

**Verdict: ABSENT**

Every `!!!` admonition in `src/` now carries a custom descriptive title; a corpus-wide grep (`grep -rn
'!!! ' src/`) finds zero bare `note "Note"` / `warning "Warning"` occurrences. All four cited pairs are
now custom-titled: `BandRescaling`'s clamp caveat is `!!! note "A deterministic clamp, not a stationary
sampler"` (Forcing.jl:260); `ObservablesCache`'s slot note is `"A cached array is the next iteration's
scratch"` (Cache.jl:94); `velocity_rhs!`/`scalar_rhs!` are both custom-titled (Generator.jl:327,467).

---

## Finding 2 — Formula placement: inline vs. offset block, inconsistent within one module

**Verdict: PARTIAL**

The specific `Scalings` instance is fixed: `Sreenivasan1995`'s ``E(\kappa)`` formula is now its own
```math``` block (Scalings.jl:94-96), matching `Sreenivasan1998`/`Li2008` — the three siblings on that
page are now uniform. But the class survives on `Spectra.jl`: all six roll-off factors
(`PopeLargeScale` L103, `PopeDissipation` L124-125, `VonKarmanLarge` L146-147, `PaoDissipation`
L187-188, `ExponentialDissipation` L206, `SaffmanDissipation` L232) still fuse their formula into the
identity sentence, while the three composed presets (`ModelSpectrum` L251, `VonKarman1948` L322,
`Pao1965` L348) still use a separate display block, with no stated rule for the split.

**Surviving class**: `src/phenomenology/Spectra.jl` — roll-off-factor vs. composed-preset formula
placement split, unchanged from the original finding.

---

## Finding 3 — Dedicated "Arguments" header for some multi-keyword types, folded prose for siblings

**Verdict: PRESENT**

The class is unchanged, though two of the finding's cited examples flipped sides: `ObservablesCache`
(Cache.jl:81) and `Tracers` (Particles.jl:69) now *do* carry an explicit `# Arguments` header — they
moved into the header group alongside `FlowConditions`/`FixedDomain`/`Simulation`/
`StationarityCriterion`/`FlowParameters`. But `BandRescaling` (Forcing.jl, 4 keywords), `Linear`,
`ConstantPower` (Forcing.jl), and `ResolvedGenerator` (Generator.jl:168-226, no header before its
`# Fields`) still fold comparable keyword sets into running prose. No axis (keyword count, front-door
status) cleanly separates the two groups today, same as originally flagged.

---

## Finding 4 — Cache module docstring interposes a conceptual aside before its contents list

**Verdict: ABSENT**

Cache.jl:9-33 now reads identity sentence → `"The cache's operations:"` bulleted list (immediately
following) → then the epoch-mechanism discursive aside ("Each slot carries the value **and** the
epoch...", "The cache keeps one epoch counter...") → the `!!! note` admonition. The list now comes
directly after the identity sentence, matching the identity→list→trailing-remark shape every sibling
module docstring (Forcing, Observables, Particles) already follows.

---

## Finding 5 — Two random-seeding functions never state a "Returns" sentence

**Verdict: ABSENT**

Both now end their prose (before the caveat admonition) with an explicit `Returns` sentence:
`random_solenoidal_velocity_spectral!` — "Returns `û`." (State.jl:90); `random_scalar_spectral!` —
"Returns `φ̂`." (State.jl:163). Both sit in the same position as the sibling class (before the
"Seeding a running case invalidates..." note), matching `vorticity_physical!`/`fields_modified!`/etc.

---

## Finding 6 — `FlowConditions`'s Fields section duplicates full prose+types; `FlowParameters`'s is a one-liner

**Verdict: ABSENT**

`FlowConditions`'s `# Fields` (Generator.jl:74-77) is now a single compressed sentence — "The plain
constructor `FlowConditions(viscosity, schmidt, velocity_forcing, scalar_forcing)` takes the four
fields directly, in this order; each holds the value documented for the keyword of the same name
above, with the two numbers stored as `Float64`." — matching `FlowParameters`'s equivalent
back-reference sentence (Phenomenology.jl:108-110) almost verbatim. The full bulleted per-field
restatement-plus-types the finding quoted no longer exists.

---

## Finding 7 — `ResolvedGenerator`'s admonition sits mid-docstring, not near the end

**Verdict: ABSENT**

Both admonitions in `ResolvedGenerator` (Generator.jl:192 "The constructor rejects a misdeclared
forcing", Generator.jl:200 "One optimization crosses two verbs") now sit consecutively *after* the
"Build it on the `FixedDomain` `domain`..." construction paragraph and immediately before `# Fields` —
the same "last substantive block before the end" placement as `IFRK2`'s and `PhaseShift`'s notes. No
admonition precedes the construction paragraph any more.

---

## Finding 8 — `Phenomenology` module docstring has two separate contents lists

**Verdict: ABSENT**

Phenomenology.jl:24-36 now carries exactly one bulleted list under `"The module's contents:"`,
merging the flow-state-bundle items (`FlowParameters`, `provenance`) and the law-family submodules
(`Spectra`, `StructureFunctions`, `Scalings`) into a single flat list — matching the one-list shape of
every DNS-side module docstring.

---

## Finding 9 — Particles is the only API page opening with a usage example before reference material

**Verdict: ABSENT**

`docs/src/api/Particles.md` now opens directly with `## The tracer set` (line 9), the first reference
section, exactly like every sibling page. The "Wiring tracers into a run" usage vignette still exists
but has moved to the very end of the page (line 66, after "Point-value buffers"), following all
reference material rather than preceding it.

---

## Finding 10 — "Examples" sections appear on a minority of types with no stated selection rule

**Verdict: PRESENT**

The set of typed with Examples grew (a new type, `DeferredForcing`, gained one at Forcing.jl:108), but
the finding's specifically named comparison still holds unresolved: `ObservablesCache` (Cache.jl,
non-trivial keyword constructor) and `ResolvedGenerator` (Generator.jl, likewise) still carry no
`# Examples` section, and `BandRescaling` (Forcing.jl) still has none either — while `Tracers`,
`FixedDomain`, `Simulation`, `FlowParameters`, and now `DeferredForcing` do. No stated rule
distinguishes the two groups.
