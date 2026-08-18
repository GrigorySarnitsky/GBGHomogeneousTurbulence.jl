# Closure audit — 10-style-editor

## 1. Admonition titles do not render Markdown code spans
**VERDICT: ABSENT**
Evidence: `src/Forcing.jl:250` now `!!! note "Which one a run wants depends on what else reads the kinetic energy"`; `src/SimulationRun.jl:94` now `"The default holds the kinetic energy fixed, so it is not a measurable of the default run"`; `src/Generator.jl:327` now `"The vorticity argument is read and then overwritten"` — all three titles reworded to avoid backticks. `grep -rEn '!!! (note|warning) "[^"]*`' src/ docs/src/ docs/ARCHITECTURE.md` returns nothing corpus-wide. Rendered `docs/build/api/{Forcing,SimulationRun,Generator}/index.html` confirmed to show the plain-text titles with no stray backticks.

## 2. `Phenomenology` References render DOIs as dead plain text
**VERDICT: ABSENT**
Evidence: `src/phenomenology/Scalings.jl:49,87,118` and `src/phenomenology/Spectra.jl` / `StructureFunctions.jl` citation strings now wrap each DOI as `[doi:10.xxxx](https://doi.org/10.xxxx)`. Programmatic scan of `docs/build/api/phenomenology/{Scalings,Spectra,StructureFunctions}/index.html` found all 20 `doi:` occurrences (including the `## References` lists) sit inside `<a href="https://doi.org/...">` tags — zero unlinked.

## 3. Stray space before closing punctuation after a linked/coded term
**VERDICT: ABSENT**
Evidence: checked all four cited locations directly in rendered HTML — `record_trajectory_velocity!</code></a>, both inside` (Cache), `scalar_dissipation</code></a>). The keyword` (Forcing), `ResolvedFields</code></a>) the step has just` (Propagator), `StructureFunction</code></a>) at separation` (Phenomenology) — punctuation now hugs the code span with no gap. Corpus-wide regex `find docs/build -name "*.html" | xargs grep -oE '</code></a>[[:space:]]+[,.);:]'` and the plain `</code>` variant both return zero matches across all built pages.

## 4. Prose sentences open with a lowercase code identifier
**VERDICT: ABSENT**
Evidence: `docs/ARCHITECTURE.md:1795` now reads "**The** `velocity_rhs!` assembly reads the vorticity…" (capitalized lead); `docs/src/observables_cache.md:386` now reads "**The** [`run!`](@ref) driver is the observation-first loop…". Corpus-wide sentence-boundary scan (Python regex over `docs/src/*.md`, `docs/ARCHITECTURE.md`, all `src/**/*.jl`, matching a lowercase backtick term immediately after `. `/paragraph break) found one candidate, `src/Generator.jl:215`, but it sits inside a bulleted `# Fields` entry ("- `velocity_rate`, `scalar_rate` — … `A(\kappa)`. `prepare!` fills them…"), which the house rule's own exemption for bulleted `arg` entries covers. No non-exempt instance found.

## 5. "No DOI" / "no DOI" capitalization inconsistency
**VERDICT: PRESENT**
Evidence: `docs/ARCHITECTURE.md:1827,1838,1856` still use capitalized "*(No DOI…)*"; `src/phenomenology/Spectra.jl:376` ("(no DOI)"), `src/phenomenology/StructureFunctions.jl:38,137` ("no DOI, …" / "no DOI: …") still lowercase. Confirmed identically in rendered `docs/build/api/phenomenology/{Spectra,StructureFunctions}/index.html`. The two bibliographies still disagree.

## 6. `@extref` exception followed in `notation.md` but not `ARCHITECTURE.md`
**VERDICT: ABSENT**
Evidence: `docs/ARCHITECTURE.md:188-190` now links first mentions via `@extref`: `` [`Float32`](@extref Julia Core.Float32) `` and `` [`Array`](@extref Julia Core.Array) ``, with `Float64`/`CuArray`/`ROCArray` left as plain code — consistent with the corpus's own "link at most once per docstring, first genuine mention" rule (same family, already linked once). Rendered `docs/build/architecture/index.html` confirms `Float32` and `Array` render as `<a href="https://docs.julialang.org/...">` links.
