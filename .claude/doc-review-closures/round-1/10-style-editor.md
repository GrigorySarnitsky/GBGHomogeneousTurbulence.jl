# Closure audit — 10-style-editor

## 1. Admonition titles do not render Markdown code spans

**VERDICT: ABSENT**

Evidence: All three flagged titles rewritten to avoid inline code entirely. `src/Forcing.jl:235`
now reads `"Which one a run wants depends on what else reads the kinetic energy"`;
`src/SimulationRun.jl:94` reads `"The default holds the kinetic energy fixed, so it is not a
measurable of the default run"`; `src/Generator.jl:330` reads `"The vorticity argument is read
and then overwritten"`. Rendered `admonition-header` text in `docs/build/api/{Forcing,
SimulationRun,Generator}/index.html` confirmed backtick-free. Corpus-wide grep of all `!!! `
titles in `src/*.jl` shows none contain a backtick.

---

## 2. `Phenomenology` References render DOIs as dead plain text

**VERDICT: ABSENT**

Evidence: Every `Reference(...)` citation string in `src/phenomenology/{Spectra,Scalings,
StructureFunctions}.jl` now wraps its DOI in a Markdown link, e.g.
`[doi:10.1063/1.869575](https://doi.org/10.1063/1.869575)`. Rendered HTML confirmed: all 3 DOIs
in `docs/build/api/phenomenology/Scalings/index.html`'s `##References` render as
`<a href="https://doi.org/...">doi:...</a>`; all 11 in `Spectra/index.html` and all 3 in
`StructureFunctions/index.html` likewise render as live `<a>` tags (grep counts of
`doi.org/...` hrefs match grep counts of `>doi:10...<` text exactly on all three pages).

---

## 3. Stray space before closing punctuation after a linked/coded term

**VERDICT: ABSENT**

Evidence: Regex sweep `</code></a> [,.)]` and `</code> [,.)]` (space required before the
punctuation) returns zero matches on all five originally flagged pages
(`Cache`, `Forcing`, `Generator`, `Propagator`, `phenomenology/Phenomenology`), and zero matches
across all 20 rendered HTML pages under `docs/build` — corpus-wide, not just the flagged
locations.

---

## 4. Prose sentences open with a lowercase code identifier

**VERDICT: PRESENT**

Evidence: `docs/ARCHITECTURE.md:1789` — decision 56's body still opens a sentence with
"`velocity_rhs!` reads the vorticity and overwrites it; `scalar_rhs!` reads the velocity and
overwrites it." (the bold heading was reworded and shortened, but the flagged sentence itself
still leads with a lowercase code identifier, now on its own line). `docs/src/
observables_cache.md:381` is completely unchanged: "[`run!`](@ref) is the observation-first
loop: after every iteration…" — identical text to what the finding quoted. Neither is a bulleted
`arg` entry or a signature, so both still violate the house rule verbatim.

surviving_class: same two sites as originally flagged; no new instances searched beyond these
two (finding named only these two).

---

## 5. "No DOI" / "no DOI" capitalization inconsistency

**VERDICT: PRESENT**

Evidence: `docs/ARCHITECTURE.md:1821,1832,1850` still use capitalized `"(No DOI: …)"` /
`"(No DOI; …)"` in all three References entries (Kolmogorov 1941, Rogallo 1981, Lundgren 2003).
`src/phenomenology/StructureFunctions.jl:38,137` and `src/phenomenology/Spectra.jl:375` still use
lowercase `"no DOI"` in all three Phenomenology `Reference` citation strings. No harmonization
occurred; both spellings coexist unchanged.

---

## 6. `@extref` exception followed in `notation.md` but not in `ARCHITECTURE.md`

**VERDICT: PRESENT**

Evidence: `docs/src/notation.md:101` links `Float32`/`Float64` via `@extref Julia
:jl:type:Core.Float32/64`. `docs/ARCHITECTURE.md:188-189` — the near-identical sentence
"`element_type` fixes the real element type (`Float32` or `Float64`) and `array_type` the
storage (`Array`, `CuArray`, `ROCArray`)" — still leaves every one of those five type names as
plain unlinked `` `code` `` spans; `grep -n "extref" docs/ARCHITECTURE.md` returns zero matches
in the whole file. The finding itself flagged this at low confidence as possibly-deliberate; the
inconsistency is unchanged either way.
