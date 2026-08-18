# Closure audit — hat: structure-consistency

## Finding 1 — Admonition titling is not uniform: bare `Note`/`Warning` vs. custom titles
**VERDICT: PRESENT**

Evidence: `src/Forcing.jl:235` custom-titled `!!! note "Which one a run wants depends on what else reads
the kinetic energy"` sits in the same `BandRescaling` docstring as the bare `!!! note` at line 245
("This is a deterministic clamp..."). `src/Cache.jl:37` custom `"An epoch is not an iteration number"`
(module docstring) vs. bare `!!! note` at `src/Cache.jl:91` (`ObservablesCache`). `src/Observables.jl:130`
custom `"A grid maximum, not a continuum supremum"` (`max_speed`). `src/Generator.jl:218` custom
`"One optimization crosses two verbs"` (`velocity_rhs!`'s docstring) vs. the paired `scalar_rhs!`'s bare
`!!! note` at `src/Generator.jl:470`. All four quoted locations unchanged.

---

## Finding 2 — Formula placement: offset display block vs. inline-fused, inconsistent within one module
**VERDICT: PRESENT**

Evidence: `src/phenomenology/Scalings.jl` — `Sreenivasan1995` (line ~90) still fuses
`E(\kappa) = C_K\varepsilon^{2/3}\kappa^{-5/3}` into its identity sentence, while `Sreenivasan1998`
(line ~58) and `Li2008` (line ~117) still use separate `math` display blocks — unchanged. In
`src/phenomenology/Spectra.jl` the six roll-off factors (`PopeLargeScale` etc., e.g. line 103) still fuse
their formula inline; `VonKarman1948` (line 321) and `Pao1965` (line 347) still show a separate display
block. One instance shifted: `Pope2000` (line 293) no longer restates a formula at all, deferring to
`ModelSpectrum`'s docstring — so the "all six roll-off inline / all three presets in a block" split is
now 2-of-3 for the preset side, but the underlying inconsistency (inline vs. block, no stated rule)
is intact.

---

## Finding 3 — Dedicated "Arguments" header for some multi-keyword types, prose for siblings
**VERDICT: PARTIAL**

Evidence: `src/Particles.jl:69` — `Tracers` now carries an explicit `# Arguments` bulleted section
(gained since the finding). `FlowParameters` (`src/Phenomenology.jl:77`) also carries one. But
`ResolvedGenerator` (`src/Generator.jl:169-224`, prose only, no header), `ObservablesCache`
(`src/Cache.jl:65-97`, prose only), `BandRescaling` (`src/Forcing.jl:203-249`, prose only), `Linear`
(`src/Forcing.jl:288-300`, prose only), and `ConstantPower` (`src/Forcing.jl:325+`, prose only) all still
document a comparable keyword set purely in running prose with no header.

surviving_class: `ResolvedGenerator`, `ObservablesCache`, `BandRescaling`, `Linear`, `ConstantPower` —
five multi-keyword types still lack the header that `FlowConditions`/`FixedDomain`/`Simulation`/
`StationarityCriterion`/`FlowParameters`/`Tracers` now carry.

---

## Finding 4 — Cache's module docstring interposes a conceptual aside before its contents list
**VERDICT: ABSENT**

Evidence: `src/Cache.jl:15-27` now reads identity sentence → one short lead-in clause ("Each slot
carries the value and the epoch that value belongs to, so a read can be refused rather than served
stale. The cache's operations:") → the bulleted list immediately. The substantial epoch-mechanism
discussion (the `deposit!` paragraph, the epoch-counter paragraph, and the `"An epoch is not an
iteration number"` admonition) now sits entirely *after* the list (`src/Cache.jl:29-41`), matching the
identity→list→trailing-remark shape. A comparably short pre-list lead-in clause exists in
`src/Forcing.jl` before its second list ("A strategy acts on the step through up to four methods...
listed in the order the step calls them:"), so this is within corpus variance, not the flagged
"substantial standalone explanation before the list."

---

## Finding 5 — The two random-seeding functions never state a "Returns" sentence
**VERDICT: REGRESSED**

Evidence: both `src/State.jl:90` (`random_solenoidal_velocity_spectral!`) and `src/State.jl:163`
(`random_scalar_spectral!`) now end with `Returns the filled field.` — the missing-sentence defect
itself is fixed. But every other instance of this sentence in the corpus follows a strict
`` Returns `x`. `` pattern naming the backticked argument (`` Returns `cache`. `` — Cache.jl:287,304;
`` Returns `ω`. `` — Observables.jl:164; `` Returns `field`. `` — SimulationDomain.jl:362;
`` Returns `state`. `` — Propagator.jl:204, Generator.jl:285; `` Returns `N̂`. `` — Generator.jl:343,479).
"Returns the filled field." breaks that established backtick-argument-name convention — a new
structural inconsistency introduced by the fix.

---

## Finding 6 — `FlowConditions`'s "Fields" duplicates full prose; `FlowParameters`'s is a back-reference
**VERDICT: PRESENT**

Evidence: `src/Generator.jl:75-79` — `FlowConditions`'s `# Fields` still fully restates each field
with element-type annotations ("(both `Float64`)"), unchanged. `src/Phenomenology.jl:108-112` —
`FlowParameters`'s `# Fields` is still the single sentence "each holds the value documented for the
keyword of the same name above." The verbosity gap is unchanged.

---

## Finding 7 — `ResolvedGenerator`'s admonition sits mid-docstring, not near the end
**VERDICT: PRESENT**

Evidence: `src/Generator.jl` current order is `# Fields` (line 189) → `!!! warning "The constructor
rejects a misdeclared forcing"` (line 210) → `!!! note "One optimization crosses two verbs"` (line 218)
→ plain construction prose ("Build it on the `FixedDomain` domain...", line 223) → end of docstring.
This still violates the corpus/house convention (CLAUDE.md: "A caveat admonition is the last
substantive block of a docstring, before `# Fields`") in a new arrangement: `# Fields` now precedes
both admonitions instead of following them, and prose follows the admonitions rather than the
docstring closing on one, unlike `IFRK2`/`PhaseShift` whose caveat is the true last block.

---

## Finding 8 — The `Phenomenology` module docstring carries two separate "contents" lists
**VERDICT: PRESENT**

Evidence: `src/Phenomenology.jl:24-38` still has `"**The flow state a law reads:**"` (a list) followed
by `"**The law families, one submodule per representation:**"` (a second list), unchanged. Every
DNS-side module docstring checked (Cache, Forcing, Observables, Particles, Generator) still has exactly
one flat contents list.

---

## Finding 9 — Particles is the only API page opening with a usage-example section first
**VERDICT: ABSENT**

Evidence: `docs/src/api/Particles.md` now opens with `## The tracer set` (reference material), and the
worked example `## Wiring tracers into a run` is the *last* `##` section in the file. Grepping every
`## ` heading across all nine `docs/src/api/*.md` pages shows Particles' first heading is reference
material like every sibling (Cache, Forcing, Generator, Observables, Propagator, SimulationDomain,
SimulationRun, State) — no page opens on a usage vignette.

---

## Finding 10 — "Examples" sections appear on a minority of types with no stated selection rule
**VERDICT: PRESENT**

Evidence: `grep -rn "^# Examples" src/*.jl src/phenomenology/*.jl` still returns exactly the same four
types as before — `FlowParameters` (Phenomenology.jl:95), `Tracers` (Particles.jl:78), `FixedDomain`
(SimulationDomain.jl:159), `Simulation` (SimulationRun.jl:169) — plus two function-level Examples
(`run!`, `warmup!`) that are not types. `ObservablesCache`, `ResolvedGenerator`, `FlowConditions`, and
`BandRescaling` still carry none (`grep -n "# Examples" src/Cache.jl src/Generator.jl src/Forcing.jl`
returns nothing). Unchanged.
