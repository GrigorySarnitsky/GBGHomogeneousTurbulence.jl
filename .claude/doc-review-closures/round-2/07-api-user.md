# Closure audit — hat 07: physicist-programmer API user

## Finding 1 — `advance!`'s own docstring never mentions the closing deposit it performs

**VERDICT: ABSENT**

`src/SimulationRun.jl:369-373` now reads: "Closes the iteration with
[`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!), so the cache is readable when it
returns." The docstring states the closing deposit and its consequence (cache readability)
directly, in `advance!`'s own home. Grepped `advance!` block in full; no other gap found.

---

## Finding 2 — `ObservablesCache`'s `particle_velocities` keyword: type and required wiring undocumented

**VERDICT: ABSENT**

`src/Cache.jl:84-86`: "`particle_velocities = nothing` — the tracer set's own point-value storage,
passed when the run advects tracers. Pass `tracers.particle_velocities`: the slot **is** that
array, so the tracer advance writes the values and the cache only records which epochs they belong
to." This states both the value to pass and why the aliasing holds. `docs/src/observables_cache.md`
build example (line 400) still omits tracers, but the finding's core gap — the constructor
docstring not saying what to pass — is closed.

---

## Finding 3 — `Tracers`'s two-line signature block visually implies dispatch the architecture says is impossible

**VERDICT: ABSENT**

`src/Particles.jl:47-51`: immediately under the two-line signature block, a parenthetical now
reads: "(One method, shown as the two ways it is called — keywords do not dispatch.)" This directly
disambiguates the visual convention at the one site the finding named. No other multi-signature
keyword-only block found lacking this note (`grep -n "keywords do not dispatch" src/*.jl` — only
this one site, which is the only offending one named).

---

## Finding 4 — "What does this return?" is documented three incompatible ways across modules

**VERDICT: PRESENT**

All four quoted instances are byte-for-byte unchanged: `src/Generator.jl:255` "Returns
`generator`." (no arrow in signature at line 246); `src/Propagator.jl:498` "Returns `cache` (or
`sim`)."; `src/Forcing.jl:131` `set_forcing_rate!(...) -> rate`; `src/Particles.jl:222`
`record_particle_velocity!(tracers, u) -> tracers`. CLAUDE.md now states a house rule ("a
`Returns x.` sentence is required... whose signature carries no `->` arrow") but this is
repo-internal, never surfaced on any rendered page (`grep -rn "arrow" docs/src/*.md` — no
explanation found); a reader of the manuscript still cannot tell the two styles apart from the page.

---

## Finding 5 — `Observables`' plain scalar reductions never show a return-type arrow, unlike `Phenomenology`'s equivalents

**VERDICT: PRESENT**

`src/Observables.jl:50-51,68`: `kinetic_energy(u)` / `kinetic_energy(û)`, still no `->` in either
signature line. `src/Phenomenology.jl:129`: `kolmogorov_length(fp) -> Float64` still carries the
arrow. Same asymmetry the finding named, both sites unchanged.

---

## Finding 6 — Bare, physical-convention symbol names (`u`, `ω`, `φ`) are documented to accept — and an example passes — spectral data

**VERDICT: ABSENT**

`src/Observables.jl:49-58`: `kinetic_energy` now shows **two** signature lines, `kinetic_energy(u)`
and `kinetic_energy(û)`, with prose "it accepts the velocity in either representation — the
physical field ``\boldsymbol{u}`` or its spectral coefficients ``\hat{\boldsymbol{u}}``."
`dissipation` (lines 72-73) and `scalar_variance` (lines 184-190, "it accepts `φ` in either
representation") carry the same explicit disambiguation. The correct hatted symbol is now used for
the spectral call form everywhere checked, so `docs/src/index.md:51`'s
`kinetic_energy(sim.state.velocity_spectral)` example is now consistent with a documented, properly
notated call form rather than an undocumented one.

---

## Finding 7 — `advect!`'s argument order diverges from `step!`'s despite the docs advertising a shared convention

**VERDICT: ABSENT**

`src/Particles.jl:248`: `advect!(scheme, tracers, velocity_end, domain, buffers, dt)` — `domain`
now precedes `buffers`, matching `src/Propagator.jl:169`'s `step!(scheme, state, generator, domain,
buffers, cache, dt)` order. Confirmed against the actual method definition at
`src/Particles.jl:282-283` (`domain::FixedDomain, buffers::ParticleIntegratorBuffers`). The
mismatch is gone.

---

## Finding 8 — `tracer_scheme` (front door) vs `interpolation_scheme` (`Tracers`) is a renamed forward with no stated reason

**VERDICT: ABSENT**

`src/SimulationRun.jl:162-167`: the front-door keyword is now `interpolation_scheme` itself (no
rename, matches `Tracers` exactly), and the former `particle_scheme` keyword is now
`trajectory_scheme` — no longer a one-letter-shuffle collision with the interpolation keyword.
`grep -n "tracer_scheme\b" src/*.jl` returns nothing; the old name is gone from the surface.
