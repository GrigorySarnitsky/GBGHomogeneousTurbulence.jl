# Closure audit — 10-style-editor

One verdict per banked finding, established against the current corpus only.

---

## Finding 1 — Admonition titles do not render Markdown code spans

**VERDICT: ABSENT**

Evidence: `grep -rn '!!! ' src/*.jl docs/src/*.md` lists all 24 admonition titles in the
corpus; none contains a backtick (`grep -rn '!!! .*\`'` returns nothing). The three flagged
titles now read: `"Which one a run wants depends on what else reads the kinetic energy"`
(`src/Forcing.jl:250`), `"The default holds the kinetic energy fixed, so it is not a
measurable of the default run"` (`src/SimulationRun.jl:94`), `"The vorticity argument is
read and then overwritten"` (`src/Generator.jl:327`). Confirmed in the built HTML too:
`docs/build/api/Forcing/index.html` renders the title as plain text with no stray backticks.

---

## Finding 2 — Phenomenology References render DOIs as dead text

**VERDICT: ABSENT**

Evidence: `src/phenomenology/{Scalings,Spectra,StructureFunctions}.jl` — every `Reference(...)`
citation string now wraps its DOI in Markdown link syntax, e.g.
`Reference("Sreenivasan (1998)... [doi:10.1063/1.869575](https://doi.org/10.1063/1.869575)")`.
Checked the rebuilt HTML directly: `docs/build/api/phenomenology/{Scalings,Spectra,
StructureFunctions}/index.html` `## References` sections render all DOIs (Pope 2000, von
Kármán 1948, Pao 1965, Corrsin/Obukhov, Kolmogorov 1962, She & Lévêque, Lundgren, etc.) as
live `<a href="https://doi.org/...">` anchors, matching the in-body citation convention.

---

## Finding 3 — Stray space before closing punctuation after a linked/coded term

**VERDICT: ABSENT**

Evidence: `grep -rlo '</code></a> [,.);]' docs/build/` and the broader
`grep -rlo '</code> [,.);]' docs/build/` both return zero matches anywhere in the rebuilt
docs, not just on the five originally-flagged pages
(`Cache`, `Forcing`, `Generator`, `Propagator`, `phenomenology/Phenomenology`). Source check
of `src/Cache.jl:311` (`record_particle_velocities!`) shows the comma hugging the closing
`)` with no space.

---

## Finding 4 — Prose sentences open with a lowercase code identifier

**VERDICT: PARTIAL**

Evidence: both quoted instances are fixed — `docs/ARCHITECTURE.md:1793-1794` now reads "The
`velocity_rhs!` assembly reads the vorticity…"; `docs/src/observables_cache.md:386` now reads
"The `run!` driver is the observation-first loop…". But the class survives elsewhere in the
same `ARCHITECTURE.md` decision log, in plain prose (not bulleted `arg` entries or
signatures, so not exempt).

**surviving_class:**
- `docs/ARCHITECTURE.md:216` — "...fields, particles. `step!` advances the fields epoch as it
  completes." (new sentence after a period, starts with lowercase `step!`)
- `docs/ARCHITECTURE.md:1654` — "...where "boundary velocity/observables" stood.
  `check_boundary` is renamed **`check_deposits`**..."
- `docs/ARCHITECTURE.md:1673` — "...rather than forwarding to one. `validate_spectrum` leaves
  the package altogether..."
(`docs/src/architecture.md` is byte-identical to `docs/ARCHITECTURE.md`, so each instance
above appears twice in the rendered corpus.)

---

## Finding 5 — "No DOI" / "no DOI" capitalization inconsistency

**VERDICT: PRESENT**

Evidence: `docs/ARCHITECTURE.md:1826,1837,1855` still write "*(No DOI: ...)*" /
"*(No DOI; ...)*" (capitalized). `src/phenomenology/Spectra.jl:376` ("... (no DOI) / ...")
and `src/phenomenology/StructureFunctions.jl:38,137` ("... no DOI, the 1941 Doklady notes
..."; "... (no DOI: a 1949 Doklady note)") still use lowercase "no DOI". Confirmed identical
in the rebuilt `docs/build/api/phenomenology/{Spectra,StructureFunctions}/index.html`. The
inconsistency described by the finding is unchanged.

---

## Finding 6 — `@extref` exception followed in `notation.md` but not in `ARCHITECTURE.md`

**VERDICT: PARTIAL**

Evidence: the exact flagged sentence (`docs/ARCHITECTURE.md:188-190`) was edited: `Float32`,
`Float64`, and `Array` now carry `@extref Julia Core.*` links
(`[\`Float32\`](@extref Julia Core.Float32)`, etc.), matching `notation.md`'s convention. But
in the same sentence `CuArray` and `ROCArray` remain plain unlinked `` `code` `` spans, and
every other `Float32`/`Float64`/`to_physical!` mention elsewhere in `ARCHITECTURE.md` (e.g.
lines 586-593, 1026-1027, 1429, 1481, 1517, 1572, 200, 249, 279, 1015-1018, 1618-1627) is
still a plain unlinked code span — the class is alive on the large majority of surfaces the
finding names, only the one quoted sentence was partly patched.

**surviving_class:** `docs/ARCHITECTURE.md:190` (`CuArray`, `ROCArray` unlinked in the fixed
sentence itself) and every other `Float32`/`Float64`/`to_physical!` mention throughout the
file (lines listed above).
