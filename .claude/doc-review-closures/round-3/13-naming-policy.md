# Closure audit — 13-naming-policy

## Finding 1 — `tracer_scheme` / `particle_scheme` swap decision 51's axis
**VERDICT: ABSENT**
Evidence: `src/SimulationRun.jl:162,232` now uses `interpolation_scheme` (forwarded to `Tracers`, the ladder-general axis) and `:165,233` uses `trajectory_scheme = EndpointHeun()` (the tracer-specific temporal axis) — exactly the resolution hint's suggestion. `grep -rn "tracer_scheme\|particle_scheme"` returns nothing; no loaded-word collision remains.

## Finding 2 — `Linear` claims an identity `ConstantPower` shares
**VERDICT: PRESENT**
Evidence: `src/Forcing.jl:54` still bare-exports `Linear` alongside `NoForcing, BandRescaling, ConstantPower`; the type is still named `Linear` (`:319`). The docstring (`:304-306`) now explicitly says "the fixed-rate member of the two linear forcings, with `ConstantPower` the member whose rate is re-solved each step," which documents the family relation but the identifier itself was never renamed — no `FixedRate`/`LinearDamping` adopted.

## Finding 3 — `peak_wavenumber` promises an outcome the code does not deliver
**VERDICT: ABSENT**
Evidence: `grep -rn "peak_wavenumber"` returns nothing anywhere in `src/` or `docs/`. The keyword is now `envelope_wavenumber` throughout (`src/State.jl:66,77,102,114,137,151,175,188`; `src/SimulationRun.jl:152,158,231,262,267,268`) — precisely the resolution hint's suggested name, matching what the docs already called it in prose.

## Finding 4 — `k_max_η` reuses the kinetic-energy glyph for wavenumber
**VERDICT: ABSENT**
Evidence: `src/SimulationRun.jl:65,68,101,106,109,111,114,132,224,240-245` all spell the keyword `κ_max_η` (Unicode kappa), not ASCII `k`. `grep -rn "\bk_max"` across `src/` and `docs/src/` returns no hits — the collision with `k` ≡ kinetic energy no longer exists in the identifier.

## Finding 5 — `target` names two different physical kinds across sibling forcings
**VERDICT: ABSENT**
Evidence: `BandRescaling` still uses `target` (an amplitude, `src/Forcing.jl:98,220,227,275,279`), but `ConstantPower`'s keyword is now `injection_rate` (`src/Forcing.jl:97,344,357,370,373,484`) — a rate, distinctly named. The two sibling forcings no longer share one ambiguous keyword name for different physical kinds.

## Finding 6 — `Tracers.trajectory_velocity` (singular) vs `particle_velocities` (plural)
**VERDICT: ABSENT**
Evidence: `src/Particles.jl:118,129,228,233,290` — the `Tracers` struct field is now `particle_velocities` (plural), matching `Cache.jl`'s `particle_velocities` slot/accessor exactly (decision 42's slot-is-register wiring). `grep -n "trajectory_velocity" src/Particles.jl` only matches the verb `record_particle_velocities!`, not a stored field.

## Finding 7 — `Li2008(; constant = 0.9)` names its parameter imprecisely
**VERDICT: ABSENT**
Evidence: `src/phenomenology/Scalings.jl:122,152,155,159,161` — the field/keyword is now `dissipation_group`, not `constant`; matches the module map's own description "the box-normalized dissipation group `G`" (`:14`).

## Finding 8 — `stationary_dissipation`'s `energy` argument breaks the `kinetic_energy` convention
**VERDICT: ABSENT**
Evidence: `src/phenomenology/Scalings.jl:38,147,163` — the signature is now `stationary_dissipation(law, kinetic_energy, side_length)`, matching `Observables.kinetic_energy` and the `Simulation(; kinetic_energy = ...)` keyword package-wide.

## Finding 9 — `finalize!` borrows a software-engineering term
**VERDICT: PRESENT**
Evidence: `src/Generator.jl:30,48,184,274,284` still name the verb `finalize!`; `docs/ARCHITECTURE.md:1155-1156` still carries the same "recorded deviation from the solver-library precedent" caveat verbatim. No rename (e.g. `apply_forcing_projections!`) was adopted; the identifier and its documented tension are unchanged.
