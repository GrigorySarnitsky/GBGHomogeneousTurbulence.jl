# Closure audit — Style / Copy-Edit Panel (10-style-editor)

## Finding 1 — Hyphenated compound splits into two words ("deposit- completeness")
**VERDICT: ABSENT**
Evidence: `rg "deposit-" docs/src/observables_cache.md docs/src/architecture.md` shows
`deposit-completeness` joined on a single source line at observables_cache.md:419 and
architecture.md:458/1497/1675 (also 1486 heading, 72 deposit-driven — different compound, fine).
Built HTML confirms: `grep -o "deposit-[ ]*completeness" docs/build/{observables_cache,architecture}/index.html`
returns 4 hits, all `deposit-completeness` with no stray space. No split instance found anywhere.

## Finding 2 — Citation punctuation split: "Year, Title" vs "Year — Title"
**VERDICT: ABSENT**
Evidence: `rg "Betchov 1956|Lundgren 2003|Bussi.*2007" src/` shows all three now comma-joined:
`src/Observables.jl:246` "(Betchov 1956, *An inequality...*", `src/Forcing.jl:307` "(Bussi, Donadio &
Parrinello 2007, *Canonical sampling...*", `src/Forcing.jl:350` "Lundgren 2003, *CTR Annual Research
Briefs*". Swept `src/Observables.jl` and `src/Forcing.jl` for stray " — " near a year; only hit
(Forcing.jl:460, Eswaran & Pope) is a label dash before the author, not a year-title separator —
consistent with house form elsewhere.

## Finding 3 — Redundant, near-verbatim repeated sentence in the same admonition
**VERDICT: PRESENT**
Evidence: `src/Propagator.jl:556-557`, `recommended_cfl`'s "IFRK2 margin" admonition: "...the
practical course at high Reynolds number is to prefer `IFLowStorageRK3`, whose ceiling has no such
dependence, or to pass an explicit `cfl` and verify it against a run that holds its energy.
`IFLowStorageRK3`'s ceiling carries no such dependence." — the trailing sentence is still there,
verbatim as quoted in the finding.

## Finding 4 — Missing subsection heading breaks the page's one-heading-per-group pattern
**VERDICT: PRESENT**
Evidence: `docs/src/api/SimulationDomain.md:30-35` — the `max_wavenumber` blurb "The dealiasing
cutoff it sets — the dealiasing cutoff — the highest wavenumber the run treats as resolved signal,
and the resolution criterion κ_max η a run is built to meet." still has no `##` heading above it
(directly follows the "Dealiasing strategies" `@docs` block) and still doubles the phrase "the
dealiasing cutoff" back-to-back, exactly as quoted.

## Finding 5 — Two distinct citations merged into one bulleted reference line
**VERDICT: PRESENT**
Evidence: `src/phenomenology/Spectra.jl:407-408` — `_OBUKHOVCORRSIN` is still one `Reference` whose
`citation` string joins Obukhov (1949) and Corrsin (1951) with `" / "`. `docs/src/api/phenomenology/Spectra.md`'s
`## References` `@eval` block (lines 73-79) emits one bullet per unique citation string with no
splitting on `" / "`, so the generated bibliography still renders both papers on one bullet line.

## Finding 6 — Phenomenology References use labelled DOI-link form, not the bare-autolink form
**VERDICT: PRESENT**
Evidence: `docs/ARCHITECTURE.md:1834-1848` `## References` still uses bare autolinks
(`<https://doi.org/...>`, confirmed rendering as plain URL text, not a labelled anchor). The three
Phenomenology reference pages still render the labelled inline form: `grep -o '<a href="https://doi.org[^"]*">[^<]*</a>'`
on `docs/build/api/phenomenology/{Scalings,Spectra,StructureFunctions}/index.html` returns
`<a href="...">doi:10....</a>` anchors throughout — the two-form disagreement is unchanged.

## Finding 7 — Admonition title runs directly into its own body (extraction artifact, verified benign)
**VERDICT: NOT-A-DEFECT**
Evidence: Original finding already established this is not a rendering defect. Re-confirmed:
`docs/build/index.html` shows `admonition-header">Work in progress<a class="admonition-anchor"...`
— a proper `admonition-header` element distinct from the following `admonition-body`; the "header
runs into body" reading is an artifact of flat-text extraction only, not of the actual HTML/DOM
structure. No fix was ever needed.
