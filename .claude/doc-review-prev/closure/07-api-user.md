# Closure — Hat 07: physicist-programmer / API user

## Finding 1 — `particles_epoch`'s producer attributed two different ways
**VERDICT: PRESENT**

Evidence: `src/Cache.jl:121-122` (`ObservablesCache` Fields) still reads "`particles_epoch` — the
tracer positions' counter, advanced when [`advect!`](@ref ...) moves them." `src/Cache.jl:337-340`
(`particles_modified!` docstring) still attributes the advance to "the run layer" — "`advect!`
followed by `record_particle_velocities!`, both inside `advance!`" — and `particles_modified!` itself
is the function that increments `cache.particles_epoch` (`src/Cache.jl:349`). `src/Particles.jl:292-293`
confirms `advect!`'s concrete method carries no `cache` argument
(`advect!(::EndpointHeun, tracers::Tracers, velocity_end, domain::FixedDomain, buffers::ParticleIntegratorBuffers, dt::Real)`).
Checked `docs/src/observables_cache.md`, `docs/src/api/*.md`, `docs/ARCHITECTURE.md` for
`particles_epoch` / "advect! moves" — no other mention; the two contradictory attributions stand
exactly where the finding located them, text unchanged.

---

## Finding 2 — `deposit!(sim)` credited with the particle-velocities slot
**VERDICT: PRESENT**

Evidence: `src/Propagator.jl:489-492`, the `deposit!` docstring, is unchanged: "The particle-velocities
slot is not among them... filled by `record_particle_velocities!` wherever the positions move — which
`advance!` and the `deposit!(sim)` form above both do for you" — still never names `deposit_sample!`.
`docs/src/notation.md:120` still fixes the order "`step!` the fields, `deposit!` to close them, then
advance any tracers and record their sample." `src/Cache.jl:266-276`, `deposit_sample!`'s docstring, is
unchanged: "`record_particle_velocities!` writes, this call records." Runtime confirms `deposit!(sim)`
(`src/SimulationRun.jl:321-329`) does not move tracer positions (comment: "the positions are unchanged")
while `advance!` (`src/SimulationRun.jl:415-421`) does — the docstring's "wherever the positions move"
clause still glosses over that the two callees it names are not both instances of positions moving.

---

## Finding 3 — `step!`/`deposit!` argument order "still line up"
**VERDICT: PRESENT**

Evidence: `src/Propagator.jl:199-200` unchanged: "After the leader both take `state`, `domain`,
`buffers` in that order, so a hand-run loop's two calls still line up." Signatures unchanged:
`step!(scheme, state, generator, domain, buffers, cache, dt)` (`src/Propagator.jl:172`) vs.
`deposit!(cache, state, domain, buffers)` (`src/Propagator.jl:470`) — `generator` still interposed
between `state` and `domain` in `step!`, so the claim still overstates positional alignment for a
reader lining the two calls up visually.

---

## Finding 4 — Duplicated sentence in `recommended_cfl`'s IFRK2 caveat
**VERDICT: PRESENT**

Evidence: `src/Propagator.jl:556-557`, the `!!! warning "The IFRK2 margin does not know the
viscosity"` block, still ends "...prefer `IFLowStorageRK3`, whose ceiling has no such dependence, or
to pass an explicit `cfl` and verify it against a run that holds its energy. `IFLowStorageRK3`'s
ceiling carries no such dependence." — the same claim stated twice back to back, verbatim as the
finding quoted it.

---

## Summary

All four findings from this hat are still present in the corpus, verbatim or effectively unchanged
from the quoted text. No evidence of any fix landing for this hat's findings; the particle-epoch /
deposit-sample attribution contradictions (Findings 1–2) and the two editorial nits (Findings 3–4)
all reproduce exactly at the cited locations.
