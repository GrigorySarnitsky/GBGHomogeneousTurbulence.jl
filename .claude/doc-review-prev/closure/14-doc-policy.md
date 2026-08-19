# Closure — 14-doc-policy

## Finding 1 — Repeated `@ref` to the same target within one docstring (11 instances, 4 files)

**VERDICT: PARTIAL**

Evidence: Fixed at every location the finding named in `src/Forcing.jl` (`BandRescaling`, `Linear`,
`ConstantPower`, `StochasticOU` — `# Arguments` bullet now bare `` `FixedDomain` ``, no second
`@ref`), `src/Cache.jl` (`ObservablesCache` `# Arguments` bullet bare; module docstring's second
`deposit!` mention now bare backtick at line 35; `particles_modified!`'s second
`record_particle_velocities!` mention bare at line 344), `src/Propagator.jl` (`recommended_cfl`'s
`!!! warning` re-mentions of `IFLowStorageRK3`/`IFRK2` now bare), and `src/Generator.jl`
(`ResolvedGenerator`'s `# Arguments`/`# Fields` `conditions` bullets bare).

Surviving class: `src/phenomenology/Spectra.jl` still double-links `` [`ModelSpectrum`](@ref) ``
within one docstring, in both `VonKarman1948` (lines 351 and 354) and `Pao1965` (lines 376 and
379) — the exact pattern the finding flagged and contrasted against the compliant `Pope2000`
(line 328, single link folded into a parenthetical). `Pope2000` itself remains correctly
single-linked.

---

## Finding 2 — `advance!`, `run!`, `warmup!` omit the required `Returns` sentence

**VERDICT: ABSENT**

Evidence: `src/SimulationRun.jl` — `advance!` docstring now closes "Returns `sim`." (line 392);
`run!` closes "Returns `sim`." (line 459); `warmup!` closes "Returns `sim`." (line 680, just before
the binding). All three in-place mutators with no `->` arrow now carry the mandated closing
sentence, matching the rest of the corpus (`prepare!`, `finalize!`, `deposit!`, etc.).

---

## Finding 3 — `ResolvedFields` names its plain positional constructor despite taking preallocated state internals

**VERDICT: ABSENT**

Evidence: `src/State.jl`, `ResolvedFields` docstring (lines 39–59) no longer contains the sentence
naming the plain positional constructor; the `# Fields` section (lines 51–54) states only the field
meanings, and the identity paragraph says "Build it on a `FixedDomain`" instead. A repo-wide grep
(`rg "plain constructor" src/*.jl src/phenomenology/*.jl`) confirms `ResolvedFields` is absent from
the list of types that name their positional form — only small parameter records remain
(`FlowConditions`, `HouLi`, `Reference`, `Phenomenology` laws, etc.), consistent with the rule.

---

## Finding 4 — `Cache` module docstring's operations list includes a function it does not own

**VERDICT: PRESENT**

Evidence: `src/Cache.jl` module docstring (lines 17–24), under "The cache's operations:", still
lists `` [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!) `` as a bullet, immediately
followed by "which `Propagator` owns because it needs the scheme's scratch to recover the fields."
The double-link into this same passage was fixed (Finding 1), but the underlying scope defect —
a module-docstring "operations" list including a function this module does not itself define —
is unchanged; `deposit!` remains listed as one of "the cache's operations" while the text itself
attributes it to `Propagator`.
