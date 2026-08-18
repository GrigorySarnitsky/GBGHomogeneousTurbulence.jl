# Closure audit — hat 07-api-user (physicist-programmer API user)

## Finding 1 — `advance!`'s own docstring never mentions the closing deposit it performs

**VERDICT: ABSENT**

Evidence: `src/SimulationRun.jl:353-361` — `advance!`'s docstring now reads "Closes the iteration
with [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!), so the cache is readable when it
returns." Searched `src/SimulationRun.jl` for `advance!`'s docstring block directly; the deposit fact
is now stated inline, not left to be pieced together from `step!`/`deposit!`'s pages.

---

## Finding 2 — `ObservablesCache`'s `particle_velocities` keyword: type and required wiring undocumented

**VERDICT: ABSENT**

Evidence: `src/Cache.jl:75-79` — `ObservablesCache`'s docstring now says "Pass
`tracers.particle_velocities`: the slot **is** that array, so the tracer advance writes the values
and the cache only records which epochs they belong to." Cross-checked against the actual wiring in
`src/SimulationRun.jl:262-263` (`particle_velocities = tracers.particle_velocities`) — the docstring
and the code agree on the exact value to pass and why.

---

## Finding 3 — `Tracers`'s two-line signature block visually implies dispatch the architecture says is impossible

**VERDICT: ABSENT**

Evidence: `src/Particles.jl:44-46` — directly under the two-line signature block, the docstring now
adds "(One method, shown as the two ways it is called — keywords do not dispatch.)", explicitly
disambiguating the convention at the one place it was flagged as visually misleading.

---

## Finding 4 — "What does this return?" is documented three incompatible ways across modules

**VERDICT: PRESENT**

Evidence: `src/Generator.jl` (`prepare!`, "Returns `generator`.") and `src/Propagator.jl:495`
("Returns `cache` (or `sim`).") still use a trailing sentence; `src/Forcing.jl:120`
(`set_forcing_rate!(...) -> rate`), `src/Particles.jl:222,248` (`-> tracers`), and
`src/Phenomenology.jl` (ten `-> Float64`/`-> Bool`/etc. signatures) still use signature-block arrows.
No page states which style applies where; the module-by-module split the finding describes is
unchanged.

---

## Finding 5 — `Observables`' plain scalar reductions never show a return-type arrow, unlike `Phenomenology`'s equivalents

**VERDICT: PRESENT**

Evidence: `src/Observables.jl:49-50` (`kinetic_energy(u)`), and the same pattern for `dissipation`,
`scalar_variance`, `derivative_skewness`, `max_speed` — none carry a `-> Float64` arrow.
`src/Phenomenology.jl:129,138,147,158,169` (`kolmogorov_length(fp) -> Float64` etc.) still do, for
structurally identical pure scalar queries.

---

## Finding 6 — Bare, physical-convention symbol names (`u`, `ω`, `φ`) are documented to accept — and an example passes — spectral data

**VERDICT: PRESENT**

Evidence: `src/Observables.jl:49-58` — `kinetic_energy(u)` docstring still reads "it accepts `u` in
either representation." The flagship quick-start still demonstrates the spectral call:
`docs/src/index.md:49` and `src/SimulationRun.jl:80,310,612` all read
`kinetic_energy(sim.state.velocity_spectral)`. The bare-symbol/spectral-argument category mismatch
the finding describes is unchanged.

---

## Finding 7 — `advect!`'s argument order diverges from `step!`'s despite the docs advertising a shared convention

**VERDICT: ABSENT**

Evidence: `src/Particles.jl:246,277` — `advect!`'s signature is now
`advect!(scheme, tracers, velocity_end, domain, buffers, dt)`, with `domain` preceding `buffers`,
matching `step!(scheme, state, generator, domain, buffers, cache, dt)` (`src/Propagator.jl:169`).
The previously mismatched `buffers`-before-`domain` order is gone.

---

## Finding 8 — `tracer_scheme` (front door) vs `interpolation_scheme` (`Tracers`) is a renamed forward with no stated reason

**VERDICT: ABSENT**

Evidence: `src/SimulationRun.jl:160-164` — the front-door keyword is now `interpolation_scheme`
(unrenamed, forwarded verbatim to `Tracers`'s own `interpolation_scheme`), and the trajectory-time
keyword is `trajectory_scheme` (renamed from `particle_scheme`), clearly distinct in name. No
"despite the neighbouring names" caveat remains (searched `src/SimulationRun.jl` for
`neighbouring`/`despite the` — no hits); the naming collision the finding flagged is gone.
