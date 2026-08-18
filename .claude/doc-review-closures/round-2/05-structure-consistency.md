# Closure audit — hat: structure-consistency

Ground truth checked against current `src/*.jl` and `docs/src/api/*.md`. Ten banked findings, ten verdicts below.

---

## Finding 1 — Admonition titling not uniform (bare `Note`/`Warning` vs. custom titles)

**Verdict: ABSENT**

`grep -rn '!!! ' src/` shows every admonition across the corpus (Forcing.jl:81,250,260,420; Cache.jl:38,94;
Observables.jl:109,133,147; Generator.jl:192,200,327,467) now carries a custom quoted title
(`!!! note "A deterministic clamp, not a stationary sampler"`, `!!! note "The assembly consumes the velocity
argument"`, etc.). A follow-up `grep -rn '!!! note$\|!!! warning$' src/ docs/src/` (bare, title-less form)
returns nothing. The specific `BandRescaling` pair and the `velocity_rhs!`/`scalar_rhs!` pair the finding
quoted both now use matched custom-title styles.

---

## Finding 2 — Formula placement: offset block vs. inline-fused, inconsistent within a module

**Verdict: PRESENT**

`src/phenomenology/Scalings.jl`: `Sreenivasan1995` (line ~92) still fuses ``E(\kappa) = C_K
\varepsilon^{2/3}\kappa^{-5/3}`` into its identity sentence; `Sreenivasan1998` (line ~58) and `Li2008`
(line ~119) still use a separate ` ```math ``` ` display block, on the same page. `src/phenomenology/Spectra.jl`:
all six roll-off factors (`PopeLargeScale` 103, `PopeDissipation` 122, `VonKarmanLarge` 143,
`PaoDissipation` 184, `ExponentialDissipation` 208, `SaffmanDissipation` 229) still fuse their formula
inline; the three composed presets (`ModelSpectrum` 251, `VonKarman1948` 322, `Pao1965` 348) still use a
separate block (or, for `Pope2000`, a link-back instead of repeating it). No rule distinguishes the split.

---

## Finding 3 — "Arguments" header used for some multi-keyword types, folded into prose for siblings

**Verdict: PARTIAL**

`ObservablesCache` (`src/Cache.jl:81`) and `Tracers` (`src/Particles.jl:69`) now both carry an explicit
`# Arguments` header — the finding's two headline counterexamples are fixed. But the class survives on
other siblings the finding named: `BandRescaling` (`src/Forcing.jl:219`, 4 keywords), `Linear`
(`src/Forcing.jl:304`, 3 keywords), `ConstantPower` (`src/Forcing.jl:340`, 3 keywords), and
`ResolvedGenerator` (`src/Generator.jl:167`, keyword `scalar`) still document their keywords purely in
running prose, no header, while `FlowConditions`/`FixedDomain`/`Simulation`/`StationarityCriterion`/
`FlowParameters`/`ObservablesCache`/`Tracers` now do. No axis separates the two groups.

**Surviving class**: `src/Forcing.jl` (`BandRescaling`, `Linear`, `ConstantPower`), `src/Generator.jl`
(`ResolvedGenerator`), `src/Propagator.jl` (`IntegratorBuffers`) — all still prose-only.

---

## Finding 4 — Cache's module docstring interposes a conceptual aside before its contents list

**Verdict: PRESENT**

`src/Cache.jl` lines ~19–20: the identity sentence is now followed by one additional sentence ("Each slot
carries the value **and** the epoch that value belongs to, so a read can be refused rather than served
stale.") before "The cache's operations:" introduces the list — the list is not *immediately* after the
identity sentence, unlike every sibling module docstring (`Forcing.jl:19`, `Observables.jl:11`,
`Particles.jl:18`, `Generator.jl` "Its contents (...):", `Propagator.jl`, `SimulationDomain.jl`,
`State.jl`, `SimulationRun.jl` — all checked, all list-immediately-after-identity). The finding's
original severity ("a substantial standalone explanation of the epoch mechanism" before the list,
including a `!!!` admonition) is much reduced: that discursive content and the admonition have moved to
*after* the list, leaving only the one-sentence residual. The letter of the rule ("identity sentence,
immediately followed by the list") is still broken only by Cache.

---

## Finding 5 — Two random-seeding functions never state a "Returns" sentence

**Verdict: ABSENT**

`src/State.jl:90` — `random_solenoidal_velocity_spectral!` now ends its prose with "Returns `û`." right
before the "Seeding a running case invalidates the observables cache" admonition. `src/State.jl:163` —
`random_scalar_spectral!` likewise now has "Returns `φ̂`." in the same position. Both match the sibling
pattern (`vorticity_physical!`, `fields_modified!`, `prepare!`/`velocity_rhs!`/etc.) of stating an
explicit Returns sentence before the closing admonition.

---

## Finding 6 — `FlowConditions`'s "Fields" duplicates full prose; `FlowParameters`'s is a one-liner

**Verdict: ABSENT**

`src/Generator.jl:74–76`: `FlowConditions`'s `# Fields` section is now "The plain constructor
`FlowConditions(viscosity, schmidt, velocity_forcing, scalar_forcing)` takes the four fields directly, in
this order; each holds the value documented for the keyword of the same name above, with the two numbers
stored as `Float64`." — a compressed back-reference, matching `FlowParameters`'s
(`src/Phenomenology.jl:108–110`) "...each holds the value documented for the keyword of the same name
above." Searched other multi-field types with bulleted `# Fields` (`HouLi` SimulationDomain.jl:86,
`Li2008`/`Sreenivasan1995`/`Sreenivasan1998` Scalings.jl, `Reference` Phenomenology.jl:184) — all use a
consistent "bulleted, one line per field" style, but none of them has a separate `# Arguments` section
duplicating the same content the way `FlowConditions`/`FlowParameters` do, so the back-reference style is
reserved for exactly the types that have a fuller `# Arguments` section elsewhere in the docstring — a
defensible, now-consistent split, not the three-level spread originally flagged.

---

## Finding 7 — `ResolvedGenerator`'s admonition sits mid-docstring, not near the end

**Verdict: ABSENT**

`src/Generator.jl:192` and `:200`: both admonitions (`"The constructor rejects a misdeclared forcing"`
and `"One optimization crosses two verbs"`) now sit together, immediately after the "Build it on the
`FixedDomain`..." construction paragraph and immediately before `# Fields` — i.e., both are now the last
substantive block before the Fields section, matching the dominant "caveat last" convention (`IFRK2`,
`PhaseShift`). Neither admonition precedes the construction paragraph any longer.

---

## Finding 8 — `Phenomenology` module docstring carries two separate "contents" lists

**Verdict: ABSENT**

`src/Phenomenology.jl:25–39`: the module docstring now has exactly one bulleted list under "The module's
contents:", containing `FlowParameters`, `provenance`/`fit`, `Spectra`, `StructureFunctions`, and
`Scalings` together — the previously separate "flow state" list and "law families" list are merged into
one, matching every DNS-side module docstring's single-list shape.

---

## Finding 9 — Particles is the only API page opening with a usage-example before reference material

**Verdict: ABSENT**

`docs/src/api/Particles.md`: the page now opens at line 9 with `## The tracer set` (reference material),
followed by `## The trajectory scheme`, `## The tracking loop`, `## Point-value buffers`; the "Wiring
tracers into a run" usage example is now the *last* `##` section (line 66), after all reference
sections — matching every sibling page's shape (Cache.md, Forcing.md, Generator.md, Observables.md,
Propagator.md, SimulationDomain.md, SimulationRun.md, State.md all open directly with reference `##`
sections, checked).

---

## Finding 10 — "Examples" sections appear on a minority of types with no stated selection rule

**Verdict: PRESENT**

`grep -rln '^# Examples' src/*.jl src/phenomenology/*.jl` → Forcing.jl, Phenomenology.jl, Particles.jl,
SimulationDomain.jl, SimulationRun.jl. Still absent: `ObservablesCache` (`src/Cache.jl:117`),
`ResolvedGenerator` (`src/Generator.jl:227`), `BandRescaling` (`src/Forcing.jl:273`) — the three types the
finding named as lacking Examples despite comparable or greater constructor complexity — while `Tracers`,
`FixedDomain`, `Simulation`, `FlowParameters` still carry one (and `DeferredForcing` in Forcing.jl newly
gained one, `src/Forcing.jl:108`, without closing the gap for its siblings). The described asymmetry is
unchanged.
