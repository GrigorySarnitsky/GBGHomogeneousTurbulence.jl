# Closure audit — Software Architect hat (02-software-architect.md)

## 1. `tracer_scheme` renames `interpolation_scheme` across a hop, clashes with `particle_scheme`

**VERDICT: ABSENT**

`src/SimulationRun.jl:162-167,232-233` — the front-door keyword is now `interpolation_scheme`
(identical to `Tracers`' own keyword, forwarded unchanged: `Tracers(domain; number_of_particles,
interpolation_scheme = interpolation_scheme, rng)`), and the temporal axis is now named
`trajectory_scheme` (not `particle_scheme`). `grep -rn "tracer_scheme\|particle_scheme"
src/ docs/src/` returns nothing. Three names collapsed to two, no clash, no disclaimer prose left.

---

## 2. `advect!`'s argument order breaks the shared `state, domain, buffers` order

**VERDICT: ABSENT**

`src/Particles.jl:249,283` — docstring and definition both now read `advect!(scheme, tracers,
velocity_end, domain, buffers, dt)`, `domain` before `buffers`, matching `step!`/`deposit!`
(`src/Propagator.jl:169,500`: `..., domain, buffers, ...`). Order is uniform across all three verbs.

---

## 3. `Simulation`'s fields expose scratch (`buffers`, `generator`) at the same level as reads

**VERDICT: ABSENT**

`src/SimulationRun.jl:186-189` — the `# Fields` section now opens: "Two of these are what a user
reads — `state` and `cache`. The rest are the machinery the step runs on: ... read them only
between steps, and treat their contents as the scheme's business rather than the run's state."
The fields are still listed together, but the docstring now states the safe/unsafe split directly,
per the resolution hint's first option.

---

## 4. "One forcing instance per forced field" enforced only by a warning, not code

**VERDICT: ABSENT**

`src/Generator.jl:95-98` — `FlowConditions` constructor: `ismutable(velocity_forcing) &&
velocity_forcing === scalar_forcing && throw(ArgumentError("the same $(nameof(typeof(
velocity_forcing))) instance was given as both \`velocity_forcing\` and \`scalar_forcing\`; ..."))`.
`src/Forcing.jl:81-86` docstring updated to describe the throw and scope it to stateful strategies.

---

## 5. `FlowParameters.scalar_dissipation` `NaN` sentinel vs the corpus-wide `nothing` convention

**VERDICT: ABSENT**

`src/Phenomenology.jl:87-91` — the docstring now reads: "It is a **sentinel, not a value that
propagates**: every law that reads the field checks it first ... That check is what makes the
sentinel safe, so it covers the laws here and **not arithmetic a caller does on the field itself,
which propagates `NaN` as `NaN` always does**." This is exactly resolution-hint option 1 (scope the
claim to the `Phenomenology` evaluators); the `NaN`/`nothing` divergence itself is a kept, now-honest
design choice, not the defect the finding turned on (the overclaim).

---

## 6. `Cache`'s epoch invariant is written by `deposit!`, homed in `Propagator` not `Cache`

**VERDICT: ABSENT**

`src/Cache.jl:29-31` — module docstring now states the reason: "It is homed in `Propagator` rather
than here because it needs the scheme's own scratch to recover the fields, and that is the module
owning the iteration it closes." Matches resolution-hint option 1 verbatim in spirit.

---

## 7. `ObservablesCache.particle_velocities` is externally-owned aliased storage, unlike other slots

**VERDICT: ABSENT**

`src/Cache.jl:73-75` — the type's opening paragraph (before `# Arguments`) now states: "The cache
allocates and owns every slot but one: the particle velocities are the tracer set's own storage,
which the cache borrows and records epochs for rather than filling itself." Previously this was
only in the constructor's keyword description; now stated up front, per the resolution hint.

---

## 8. `k_max_η` mixes ASCII-folded κ with literal Unicode η, contradicting its own "ASCII" claim

**VERDICT: ABSENT**

`src/SimulationRun.jl:65,101-132,224` — the keyword is now `κ_max_η` (full Unicode κ, not
ASCII-folded `k`). `grep -n "ASCII\|spells\|spelled" src/SimulationRun.jl docs/src/architecture.md`
returns nothing — the "spelled in ASCII" framing that created the contradiction is gone entirely.

---

## 9. Explicit mode silently ignores `k_max_η` when `viscosity` is also given

**VERDICT: ABSENT**

`src/SimulationRun.jl:240-243` — `Simulation` constructor: `if !isnothing(viscosity) &&
!isnothing(κ_max_η) throw(ArgumentError("\`viscosity\` and \`κ_max_η\` are two ways to set ν —
\`viscosity\` fixes it directly, \`κ_max_η\` derives it from the grid. Pass one, not both."))end`.
Passing both now throws instead of silently dropping the resolution criterion.

---

## 10. The four `AbstractForcing` hooks reuse `field` for three physically distinct instants

**VERDICT: ABSENT**

`src/Forcing.jl:165,175-177` — `apply_forcing!`'s generic signature and docstring now use
`advanced_field` distinctly from the `field` shared by `prepare_forcing!`/`set_forcing_rate!`, with
explicit prose: "Unlike the two hooks that read the start-of-step field, this one is handed the
field the step has already advanced — the argument is named for that instant..." This is the
rendered/documented surface the finding audited (only the generic binding carries a docstring per
house rule). Note: the concrete `apply_forcing!(forcing::BandRescaling, field, domain)` method
(`src/Forcing.jl:287`, undocumented, no separate docstring) still spells its local parameter
`field` — an internal-naming residue with no doc surface, not a rendered-docs defect.
