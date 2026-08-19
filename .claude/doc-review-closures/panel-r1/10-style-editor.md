# Closure audit — hat: 10-style-editor

## Finding 1 — "observation" is used for three different objects
**VERDICT: PARTIAL**

`docs/src/notation.md:125` now disambiguates the glossary entry: "the callback... By extension the
*occasion*... It is never the cache, which is the storage the callback reads." The
callback/event senses (object primary, event "by extension") are now reconciled with each other and
with `run!`'s "n iterations, n+1 observations" language (`docs/ARCHITECTURE.md:1561`,
`docs/src/observables_cache.md:145`).

However the third referent the finding named — "observation cache" used as an alias for the
`ObservablesCache` itself — is still live and now directly contradicts the newly-added glossary
sentence ("It is never the cache"). Confirmed via `rg 'observation cache' docs/ARCHITECTURE.md
docs/src/architecture.md`: 6 hits, e.g. `docs/ARCHITECTURE.md:397` "the observation cache's charts
(§4.1)", `:444` "the `ObservablesCache` observation cache", `:749` "the observation cache holds spent
compute", `:1207`, `:1214`, `:1358`.

**surviving_class:** the literal phrase "observation cache" as an alias for `ObservablesCache`,
6 occurrences in `docs/ARCHITECTURE.md` (mirrored verbatim in `docs/src/architecture.md`), none
retired in favor of "the cache" / `ObservablesCache` as the finding's resolution hint asked.

---

## Finding 2 — `deposit_sample!` is prescribed to the reader but never documented
**VERDICT: ABSENT**

`deposit_sample!` now has its own docstring at `src/Cache.jl:262-278` ("Record the particle
velocities already written into `cache`..."), is exported (`src/Cache.jl:57`,
`src/GBGIsotropicTurbulence.jl:178`), listed in the module docstring
(`src/GBGIsotropicTurbulence.jl:99`), and appears in the `@docs` block of
`docs/src/api/Cache.md:17` (under "## The observables cache"). Confirmed present in the built HTML
at `docs/build/api/Cache/index.html`.

---

## Finding 3 — Two citation/DOI formats coexist across the corpus
**VERDICT: PRESENT**

The exact split described (URL-percent-encoded vs bare `doi:`) has changed shape but the underlying
defect — the identical Orszag (1971) citation rendered two different ways depending on which page
cites it — persists. `docs/ARCHITECTURE.md:1845-1846` uses a bare angle-bracket autolink,
`<https://doi.org/10.1175/1520-0469(1971)028%3C1074:OTEOAI%3E2.0.CO;2>`, rendering with the raw URL
as link text (confirmed in `docs/build/architecture/index.html`: anchor text
`https://doi.org/10.1175/...`). `src/SimulationDomain.jl:59` (the `TwoThirds` docstring, same
Orszag 1971 paper) uses a markdown link with a `doi:`-prefixed label,
`[doi:10.1175/1520-0469(1971)028<1074:OTEOAI>2.0.CO;2](https://doi.org/...)`, rendering with anchor
text `doi:10.1175/1520-0469(1971)028&lt;1074:OTEOAI&gt;2.0.CO;2` (confirmed in
`docs/build/api/SimulationDomain/index.html`). The `Phenomenology` references
(`src/phenomenology/Scalings.jl:49` etc.) use the same `[doi:XXXX](https://doi.org/XXXX)` form as
`SimulationDomain.jl`, so the corpus is now split two ways rather than three, but `ARCHITECTURE.md`
still diverges from every docstring citation, most visibly on the shared Orszag (1971) reference.

---

## Finding 4 — `to_spectral` is `@extref`-linked on its second mention but bare on its first, same page
**VERDICT: ABSENT**

`docs/src/notation.md:20` (the Conventions table, ``\hat f`` row — the first genuine mention) now
carries the link: `` [`to_spectral`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.to_spectral) ``.
`docs/src/notation.md:60` (the later "Spectral representation and operators" table, second mention)
is now the bare `` `to_spectral` ``. Confirmed in built HTML
(`docs/build/notation/index.html`): first occurrence is `<a href="...#GBGPeriodicFields.Fields.to_spectral"><code>to_spectral</code></a>`,
second is plain `<code>to_spectral</code>` — the link now sits on the first mention only, matching
`CLAUDE.md`'s "link at most once... its first genuine mention" rule.

---

## Finding 5 — No single convention for where a trailing caveat admonition sits relative to the closing "Returns" sentence
**VERDICT: ABSENT**

All originally-cited instances now share one order (`Returns` sentence, then the admonition):
`src/Generator.jl:330-332` (`velocity_rhs!`, "Returns `N̂`." then `!!! note "The vorticity argument
is read and then overwritten"`), `src/Generator.jl:471-473` (`scalar_rhs!`, same pattern),
`src/Propagator.jl:202-204` (`step!`, "Returns `state`." then `!!! note "A step alone leaves the
cache mid-iteration"`), `src/State.jl:93-95` / `:172-174`
(`random_solenoidal_velocity_spectral!` / `random_scalar_spectral!`, unchanged), and
`src/SimulationDomain.jl:366-368` (`truncate_to_band!`, unchanged). A corpus-wide scripted scan of
every docstring containing both `Returns \`` and `!!! note`/`!!! warning` (`src/*.jl` and
`src/**/*.jl`) found zero admonition-before-`Returns` instances remaining — uniformly
`RETURNS-FIRST` across `SimulationDomain.jl`, `State.jl`, `Propagator.jl`, `Generator.jl`.

---

## Finding 6 — Conventions table's lack of a `Code` column vs. the corpus's Code-linking rule (design ambiguity, not a defect)
**VERDICT: NOT-A-DEFECT**

The finding explicitly disclaimed itself as a separate defect ("Flagging for completeness only...
not a separate defect from Finding 4"; "Resolution hint: none needed beyond Finding 4's fix").
Finding 4 is now ABSENT (verdict above). Independently, the specific sentence the finding quoted —
"Every Code entry naming a package object links to its documentation" — no longer appears anywhere
in `docs/src/notation.md` (`rg -i 'every.*code.*link|code entry' docs/src/notation.md` returns
nothing), so the literal-scope tension the finding described no longer has a textual anchor. The
"Conventions" table (`docs/src/notation.md:14`, `Concept | Symbol | Convention`) still structurally
lacks a `Code` column versus the later `Symbol | Meaning | Code` tables, but the finding never
claimed that structural fact alone was the defect.
