# Doc-policy hat — findings

Scope: does each docstring obey the package's own written documentation policy (`CLAUDE.md`
"Documentation policy" + "Doc-edit checklist")? Verified against the rendered manuscript and,
where the policy is a structural/markup claim invisible in rendered text (cross-reference
discipline, `Returns` sentences, constructor-first ordering), against `src/*.jl` directly.

---

## Finding 1 — Repeated `@ref` to the same target within one docstring (11 instances, 4 files)

- **Type:** other (cross-reference discipline)
- **Severity:** major
- **Confidence:** high

**Locations (source, not rendered — the rule is invisible in reader-text but verified against the
markup):**

- `src/Forcing.jl`, `BandRescaling` docstring: `` built on the [`FixedDomain`](@ref) `domain`. `` …
  then again in `# Arguments`: `` `domain` — the [`FixedDomain`](@ref) the band is built on. ``
- `src/Forcing.jl`: the identical double-link pattern recurs verbatim in `Linear`,
  `ConstantPower`, and `StochasticOU` — every `domain`-taking forcing constructor links
  `FixedDomain` once in the identity sentence and again in the `domain` bullet.
- `src/Cache.jl`, `ObservablesCache` docstring: `` Build it on a [`FixedDomain`](@ref) `domain`. ``
  … then `` `domain` — the [`FixedDomain`](@ref) the run lives on ``.
- `src/Cache.jl`, the `Cache` **module** docstring: `` [`deposit!`](@ref …Propagator.deposit!) ``
  in the operations bullet list, then again in the next paragraph: "The solver's side of the
  contract is `[`deposit!`](@ref …Propagator.deposit!)`."
- `src/Cache.jl`, `particles_modified!`: `` [`record_particle_velocity!`](@ref …) `` linked once
  describing the run-layer path, then again describing the hand-run-loop path.
- `src/Propagator.jl`, `recommended_cfl`: `` [`IFLowStorageRK3`](@ref) `` linked in the base-ceiling
  paragraph and again in the trailing `!!! warning`; `` [`IFRK2`](@ref) `` likewise linked twice.
- `src/Generator.jl`, `ResolvedGenerator`: `` the [`FlowConditions`](@ref) parameter record `` in
  the identity sentence, then again in `# Arguments`: `` `conditions` — the [`FlowConditions`](@ref)
  the generator resolves ``.
- `src/phenomenology/Spectra.jl`, `VonKarman1948`: `` a preset [`ModelSpectrum`](@ref) with the
  [`VonKarmanLarge`](@ref) roll-off `` then, two lines later, `` [`ModelSpectrum`](@ref)'s docstring
  carries the composed formula ``. `Pao1965` repeats the identical pattern.

**Rule violated (`CLAUDE.md`):** "Link a target **at most once per docstring** — its first genuine
mention."

**Why it's real, not noise:** the sibling preset `Pope2000` states the exact same fact ("whose
docstring carries the formula") **without** a second link, by folding it into a parenthetical of
the first sentence instead of a second sentence — proving the double-link in `VonKarman1948` /
`Pao1965` is an easy, avoidable slip rather than a necessary repetition. The pattern is consistent
enough (11 docstrings, the identity-sentence-then-`# Arguments`-bullet shape recurring on every
`domain`-taking forcing constructor) that it reads as a missed sub-rule of the review rather than
scattered one-offs.

---

## Finding 2 — `advance!`, `run!`, `warmup!` omit the required `Returns` sentence

- **Type:** other (missing mandated element)
- **Severity:** major
- **Confidence:** high

**Locations:**
- `src/SimulationRun.jl`, `advance!(sim; dt = nothing)`: "Advance `sim` by one timestep in place
  and return it." — no `->` in the signature, no closing "Returns `sim`." sentence.
- `src/SimulationRun.jl`, `run!(callback, sim)`: "Observe and advance `sim` until the observation
  stops it, and return it." — same gap.
- `src/SimulationRun.jl`, `warmup!(sim; kwargs...)`: "…it spins `sim` up … and returns it…" — same
  gap.

**Rule violated (`CLAUDE.md`):** "A **`Returns x.` sentence** is required of any in-place mutator
whose signature carries no `->` arrow."

**Contrast with the rest of the corpus:** every sibling in-place mutator with no arrow closes with
the literal sentence — `prepare!` → "Returns `generator`.", `finalize!` → "Returns `state`.",
`deposit!` → "Returns `cache` (or `sim`).", `fields_modified!` / `particles_modified!` → "Returns
`cache`.", `vorticity_physical!` → "Returns `ω`.", `step!` → "Returns `state`." The three run-layer
entry points are the only in-place mutators in the package that fold the return value into
narrative prose instead of the mandated closing sentence — an inconsistency inside the run layer
itself, the module a new reader meets first.

---

## Finding 3 — `ResolvedFields` names its plain positional constructor despite taking preallocated state internals

- **Type:** other (constructor-naming rule)
- **Severity:** minor
- **Confidence:** medium

**Location:** `src/State.jl`, `ResolvedFields` docstring, `# Fields`: "The plain constructor
`ResolvedFields(velocity_spectral, scalar_spectral)` takes the two fields directly, in this
order."

**Rule violated (`CLAUDE.md`):** "**Name the plain positional constructor only where a reader might
reasonably call it**... **Omit** it for a type whose positional form takes preallocated internals
(`Simulation`, `ObservablesCache`, `IntegratorBuffers`, `ResolvedGenerator`): advertising that form
invites a caller to assemble machinery by hand, which the derived constructor exists to prevent."

**Why this looks miscategorized:** `ResolvedFields`'s two positional fields are exactly the run's
own resolved spectral-state arrays (`û`, `φ̂`) — not a small independent parameter record like
`FlowConditions` or `Reference`, but the same kind of "preallocated internals" the rule's own
named examples exclude. `ObservablesCache`, `IntegratorBuffers`, `ResolvedGenerator`, and
`Simulation` — the four types CLAUDE.md names as the excluded category — all correctly omit
naming their positional form; `ResolvedFields` is the one state/machinery type that names it
anyway, which reads as the inconsistent outlier rather than a considered exception (there is no
restart-from-raw-arrays caveat or example accompanying it that would justify the exception, the
way `Tracers`'s `positions=` keyword path is explained).

---

## Finding 4 — `Cache` module docstring's operations list includes a function it does not own

- **Type:** other (module-docstring scope)
- **Severity:** nit
- **Confidence:** medium

**Location:** `src/Cache.jl`, `Cache` module docstring: "The cache's operations: … `deposit!`,
`deposit_sample!` — the writers…" — immediately followed a paragraph later by "That verb
[`deposit!`] lives in `Propagator` rather than here because it needs the scheme's own scratch to
recover the fields."

**Description:** the module docstring is a *map* whose job is "a linked one-liner per operation" —
i.e., per operation this module contains. `deposit!` is `GBGIsotropicTurbulence.Propagator.deposit!`,
not a `Cache`-owned binding; the docstring immediately admits this in the next sentence, so the
reader is not misled, but the "operations" bullet list is not, strictly, the module's own contents
list the map format calls for. Low severity since the text self-corrects one sentence later, but
worth folding into the same pass that fixes Finding 1's double-link on this exact same passage.

---

## Not flagged (checked and found compliant)

For the record, since this hat did a full source-level sweep: no docstring links its own binding
(zero self-references found across all 139 docstrings); no docstring in `src/` cites a decision-log
entry, an `ARCHITECTURE.md` section number, or a repo path (clean on "no dead references on the
user-facing surface"); no module docstring contains an actual formula (several bind a bare symbol,
e.g. `` ``C_K`` ``, which is not a formula); no type docstring places `# Fields` before `# Arguments`
or `# Examples`; the `f`/`f!` and thin-wrapper pairs checked (`velocity_integrating_factor` /
`scalar_integrating_factor`, `dissipation`'s two routes, `vorticity_physical!` /
`Cache.vorticity_physical`) each keep exactly one formula home with no notation drift.
