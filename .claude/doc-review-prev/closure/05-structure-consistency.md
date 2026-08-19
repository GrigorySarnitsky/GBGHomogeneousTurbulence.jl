# Closure audit — hat: structure-consistency

Adjudicated against the current corpus only (`src/*.jl`, `docs/src/`, `docs/ARCHITECTURE.md`); no
prior-round verdicts consulted.

---

## Finding 1 — `ObservablesCache` Fields split by narrative paragraph

**VERDICT: PRESENT**

`src/Cache.jl:101-123`. The demoted `# Fields` section still opens with
`velocity_physical`/`vorticity_physical`/`scalar_physical`/`max_speed`/`particle_velocities`
(lines 102-107), is then interrupted by the paragraph "The word *epoch* names two things here, and
the fields below are of both kinds. The two **counters** tick as the state changes; every other
`*_epoch` field records the counter's value..." (lines 108-111), and only then resumes with
`velocity_epoch`, `vorticity_epoch`, ... (lines 113-123). Same structural defect as banked, reworded
prose. No other type's `# Fields` in the corpus (checked `ResolvedFields`, `IntegratorBuffers`,
`ResolvedGenerator`, `StationarityCriterion`, `Simulation`) is split by intervening prose.

---

## Finding 2 — `BandRescaling`/`Linear`/`ConstantPower` lack `# Fields`

**VERDICT: PRESENT**

`src/Forcing.jl`: `BandRescaling` (struct at line 297) ends its docstring at the second `!!! note`
(line 295) then goes straight to `source`, no `# Fields`. `Linear` (line 346) ends `# Arguments`
(line 344) with no `# Fields`. `ConstantPower` (line 405) ends its `# Arguments` (line 403) with no
`# Fields`. All three still carry genuine multi-field struct state (`band`/`target`/`over`,
`mask`/`rate`, `band`/`indicator`/`injection_rate`) with no demoted Fields section documenting it.

---

## Finding 3 — `deposit_sample!` combines arrow and terminal "Returns"

**VERDICT: ABSENT**

`src/Cache.jl:265-286`. The signature is now `deposit_sample!(cache)` — no `-> particle velocities`
arrow — with the terminal sentence "Returns the particle-velocities slot." (line 282): the
arrow-less/terminal-sentence shape, one of the two sanctioned mutually-exclusive forms, not both. A
corpus-wide scan (every docstring in every `src/*.jl` and `src/phenomenology/*.jl`, checking for a
signature line containing `-> ` together with a later `Returns ` line inside the same docstring)
found zero matches anywhere — the class is swept, not just the flagged instance.

---

## Finding 4 — `stationary_dissipation` has no return-type arrow

**VERDICT: ABSENT**

`src/phenomenology/Scalings.jl:38`: `stationary_dissipation(law, kinetic_energy, side_length) ->
Float64` — the arrow is present, matching every sibling pure evaluator
(`kolmogorov_length`/`taylor_reynolds`/`scaling`/`provenance`/etc., `src/Phenomenology.jl:133-262`).

---

## Finding 5 — `Simulation`'s "Setting the Reynolds number" internal subsection

**VERDICT: PRESENT**

`src/SimulationRun.jl:86-127`. The hand-titled `# Setting the Reynolds number` subsection —
multi-paragraph discussion, a nested `!!! note`, and a bulleted Grid-mode/Explicit-mode
breakdown — still sits between the identity paragraph and `# Arguments` (line 128). No other type
docstring in the corpus (`StationarityCriterion`, `FixedDomain`, `Tracers`, `ObservablesCache`, …)
uses a named internal subsection outside Arguments/Examples/Fields/admonition.

---

## Finding 6 — `FlowConditions` embeds its constructor-validation caveat inline, unlike its peers

**VERDICT: ABSENT**

`src/Generator.jl:75-77`: the caveat is now a titled `!!! warning "A stateful forcing cannot drive
both fields"`, sitting between `# Arguments` and `# Fields` — no longer inline in an `Arguments`
bullet. It now matches its two structural siblings: `AbstractForcing`'s `!!! warning "One instance
per forced field, for a strategy that carries state"` (`src/Forcing.jl:81`) and
`ResolvedGenerator`'s `!!! warning "The constructor rejects a misdeclared forcing"`
(`src/Generator.jl:201`). All three now share the titled-admonition shape.

---

## Finding 7 — `StationarityCriterion` uniquely explains why its positional form is unadvertised

**VERDICT: ABSENT**

`src/SimulationRun.jl:605-608`: the `# Fields` section now reads "The fields are not the keywords:
`gate_skewness`, `min_turnovers`, ... Build one through the keyword constructor above." — the
explanatory clause quoted in the finding ("the positional form takes assembled internals and is not
part of the interface") is gone; what remains is a necessary note that the keywords don't map
1:1 to fields (needed since `monitor` nests several of them), not a rationale for withholding the
positional form. Checked the other "internals" types (`Simulation` Fields at line 199-214,
`ObservablesCache` at `src/Cache.jl:101-123`, `IntegratorBuffers` at `src/Propagator.jl:105-116`,
`ResolvedGenerator` at `src/Generator.jl:215-234`, `ParticleIntegratorBuffers` at
`src/Particles.jl:204-`) — none mentions the positional constructor in Fields either, so the group is
now uniform.

---

## Finding 8 — Module-docstring trailing remark length varies (none / one sentence / paragraphs)

**VERDICT: PRESENT**

Confirmed all three bands still exist: `Propagator` (`src/Propagator.jl:21-38`) and `Particles`
(`src/Particles.jl:16-33`) end their bullet list with nothing after; `SimulationDomain`
(`src/SimulationDomain.jl:8-24`, "Precision and backend enter here and flow everywhere from here.")
and `SimulationRun` (`src/SimulationRun.jl:19-32`, one closing sentence) each carry exactly one
short remark; `Cache` (`src/Cache.jl:10-47`, four trailing paragraphs), `Observables`
(`src/Observables.jl:7-38`, a multi-sentence closing paragraph), and `State`
(`src/State.jl:9-27`, a short sentence *plus* a further substantive paragraph on the recovery
mechanism) still carry multiple/substantive paragraphs. The three-way spread is unchanged.

---

## Finding 9 — "in this order" qualifier applied inconsistently across equal-field-count constructors

**VERDICT: ABSENT**

`ResolvedFields` (`src/State.jl:39-55`) no longer carries any "plain constructor ... takes the
fields" sentence at all — the whole disclosure was dropped, not just the qualifier. Surveying every
remaining "takes the N field(s) directly" sentence in the corpus: all six-and-four-field cases now
carry the order qualifier — `FlowConditions` ("four fields directly, in the order shown",
`src/Generator.jl:80-81`), `ModelSpectrum` ("four fields directly, in the order shown:",
`src/phenomenology/Spectra.jl:301-302`), `FlowParameters` ("six fields directly, in the order
shown", `src/Phenomenology.jl:115`) — while every two-field case omits it (`Reference`, `HouLi`,
`PopeLargeScale`, `PopeDissipation`, `Sreenivasan1998`, all confirmed by grep with no "in this
order"/"in the order shown" nearby). The split now correlates cleanly with field count (order
stated once there are 3+ fields, omitted at 2) rather than being arbitrary; the specific
same-field-count contradiction the finding pointed at no longer exists.

---

## Finding 10 — Only `DeferredForcing` gets an `# Examples` block within `Forcing`

**VERDICT: PRESENT**

`src/Forcing.jl`: `DeferredForcing` still carries `# Examples` (line 108, two code snippets).
`BandRescaling` (223-296), `Linear` (328-345), `ConstantPower` (367-404) still carry none, despite
`BandRescaling`'s `over` keyword prose still calling itself the choice that "decides which quantity
your run may no longer measure" (line 240-241).

---

## Finding 11 — `Cache` module-docstring bullet order doesn't track its two page sections

**VERDICT: ABSENT**

`src/Cache.jl:17-30` bullet order is now: `ObservablesCache` → `fields_modified!`/
`particles_modified!` → `deposit_sample!` → `velocity_physical`/`vorticity_physical`/
`scalar_physical` → `max_speed` → `particle_velocities`. `docs/src/api/Cache.md`'s two `@docs`
blocks are `## The observables cache` = `ObservablesCache`, `fields_modified!`,
`particles_modified!`, `deposit_sample!` (lines 13-18) and `## The checked reads` =
`velocity_physical`, `vorticity_physical`, `scalar_physical`, `particle_velocities` (lines 25-30).
`deposit_sample!` now sits inside the first four bullets, matching the first section exactly, and
the reads group immediately follows, matching the second section (only `max_speed`, which the page
does not `@docs`-block under Cache at all, sits between the two read groups in the bullet prose).
The interleaving the finding described is gone.
