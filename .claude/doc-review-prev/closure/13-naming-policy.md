# Closure — 13-naming-policy

## Finding 1 — `Linear.mask` / `ConstantPower.indicator` two names, one concept
**Verdict: ABSENT**
Evidence: `src/Forcing.jl:363,367` (`Linear`) and `:428,433` (`ConstantPower`) both now name
the field `indicator`, with matching struct comments ("real array: the band indicator …" /
"the band indicator as a real array — the rate fill's factor"). No occurrence of a `mask` field
remains in either struct (`rg "\bmask\b" src/Forcing.jl` → only a prose comment at line 373,
"the same stored mask this forcing always carried", not a field/binding name). Rendered
`docs/src/api/Forcing.md` autodocs both, so the rendered page inherits the fix.

## Finding 2 — `deposit_sample!` vs `particle_velocities` root mismatch
**Verdict: PRESENT**
Evidence: `src/Cache.jl:21,54,266,284-286,345` still export/define `deposit_sample!` verbatim,
alongside `particle_velocities`/`record_particle_velocities!`. Internal fields
`sample_fields_epoch`, `sample_particles_epoch` (Cache.jl:114,135-136,238-239,285-286,303-304)
also retain the "sample" root the finding names as residue. No rename occurred anywhere in the
class (Cache.jl or Particles.jl).

## Finding 3 — `AbstractParticleIntegrator` vs `Simulation.trajectory_scheme` root mismatch
**Verdict: PRESENT**
Evidence: `src/SimulationRun.jl:187-188,219,234,258,297,305,419` all still read `trajectory_scheme`
as the field/keyword name holding an `AbstractParticleIntegrator` (`src/Particles.jl:175`, exported
`:42`). Both roots ("trajectory" on the field/keyword, "particle" on the type family/buffers)
stand unchanged; no rename to `particle_scheme` or `AbstractTrajectoryIntegrator` found.

## Finding 4 — `ω_consumed` / `u_consumed` hybrid naming, no CLAUDE.md carve-out
**Verdict: PRESENT**
Evidence: `src/Generator.jl:301-372` (`velocity_rhs!`, `ω_consumed`) and `:450-509`
(`scalar_rhs!`, `u_consumed`) unchanged — same symbol+suffix hybrid. `docs/ARCHITECTURE.md:1814`
still carries the decision-log-only rationale ("decision 56"). `rg "consumed" CLAUDE.md` returns
no hits — the Naming section still has no carve-out for this pattern, exactly the gap the finding
flagged.

## Finding 5 — `FlowConditions` / `FlowParameters` shared field names across configured/measured
**Verdict: PRESENT**
Evidence: `src/Generator.jl:62` still reads "Not to be confused with `Phenomenology`'s
`FlowParameters`, which shares two field names" verbatim; `FlowConditions(; viscosity, schmidt, …)`
(Generator.jl:91) and `FlowParameters(; viscosity, …, schmidt, …)` (Phenomenology.jl:117-128)
still share the bare `viscosity`/`schmidt` field names between the configured-input and
measured-state bundles, with the same standing disambiguating footnote as the finding quotes — no
namespacing or rewording applied.
