# Closure audit — hat 07: physicist-programmer API user

## 1. `advance!`'s own docstring never mentions the closing deposit it performs
**VERDICT: ABSENT**

`src/SimulationRun.jl:370-371` — `advance!`'s docstring now reads: "Closes the iteration with
[`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!), so the cache is readable when it
returns." The exact fact the finding said was missing is now stated in `advance!`'s own home.

---

## 2. `ObservablesCache`'s `particle_velocities` keyword: type and required wiring undocumented
**VERDICT: PARTIAL**

`src/Cache.jl:84-86` now states exactly what to pass: "`particle_velocities = nothing` — the
tracer set's own point-value storage, passed when the run advects tracers. Pass
`tracers.particle_velocities`: the slot **is** that array…" — the core "what value do I pass" gap
is closed. Surviving class: no worked hand-assembly example wires the two together anywhere in the
corpus — `docs/src/observables_cache.md:400` still builds `ObservablesCache(domain; scalar = true)`
with tracers omitted, and `src/Particles.jl`'s hand-run-loop example (`record_particle_velocity!`
/ `advect!`) never constructs an `ObservablesCache` at all.

---

## 3. `Tracers`'s two-line signature block visually implies dispatch the architecture says is impossible
**VERDICT: ABSENT**

`src/Particles.jl:47-51` — directly under the two-signature block, the docstring now adds: "(One
method, shown as the two ways it is called — keywords do not dispatch.)" Confirmed in the rendered
build (`docs/build/api/Particles/index.html`). The visual-implication gap the finding flagged is
closed at the exact point a reader would be misled.

---

## 4. "What does this return?" is documented three incompatible ways across modules
**VERDICT: PRESENT**

Still split: `Generator.jl`/`Propagator.jl`/`Cache.jl` use a trailing "Returns `X`." sentence
(`Generator.jl:282,340,476`; `Propagator.jl:204,498`; `Cache.jl:290,307`) while `Forcing.jl`
(`:131,147,165,179,189`) and `Particles.jl`(`:222,249,304`) and `Phenomenology.jl` put `-> X` in the
signature block. Verified the two styles are now applied *consistently* per-function (no
docstring has both, and every checked `!`-mutator without an arrow does carry a "Returns" sentence)
— but no rendered page (architecture.md, notation.md, or any docstring) states this convention for
the reader, so a page-only reader still cannot tell the rule without cross-reading many modules.

---

## 5. `Observables`' plain scalar reductions never show a return-type arrow, unlike `Phenomenology`'s equivalents
**VERDICT: PRESENT**

`src/Observables.jl` — every reduction's signature block is still bare: `kinetic_energy(u)`
(`:51-52`), `dissipation(ω, viscosity)` (`:72-73`), `max_speed(u)` (`:125-126`),
`scalar_variance(φ)` (`:185`), `scalar_dissipation(φ̂, domain, diffusivity)` (`:195`) — none carry a
`-> Float64`/`-> T` arrow, while `Phenomenology.jl:129,138,147,158,169` (`kolmogorov_length`,
`kolmogorov_time`, `taylor_microscale`, `taylor_reynolds`, `scalar_diffusivity`) all do, for the
same "pure scalar query" shape.

---

## 6. Bare, physical-convention symbol names (`u`, `ω`, `φ`) are documented to accept — and an example passes — spectral data
**VERDICT: PRESENT**

`src/Observables.jl:51-52,56-58` — `kinetic_energy(u)` / `kinetic_energy(û)` documented as one
generic accepting either representation under the bare name `u` ("it accepts the velocity in either
representation — the physical field `u`… or its spectral coefficients `û`…"), still implemented as
the single method `kinetic_energy(u) = 0.5 * inner(u, u)` (`:68`). `docs/src/index.md:51` still
demonstrates `kinetic_energy(sim.state.velocity_spectral)` — spectral data through the physical-look
argument name — in the flagship quick-start.

---

## 7. `advect!`'s argument order diverges from `step!`'s despite the docs advertising a shared convention
**VERDICT: ABSENT**

`src/Particles.jl:249` — `advect!(scheme, tracers, velocity_end, domain, buffers, dt)` now places
`domain` before `buffers`, matching `step!`'s `(..., domain, buffers, cache, dt)`
(`src/Propagator.jl:169`). Verified against the actual method signature
(`src/Particles.jl:279-280`) and the call site in `advance!` (`src/SimulationRun.jl:391-392`) — both
consistent with the corrected order. Searched for any other producer/consumer pair with a
domain/buffers swap (`grep -n "domain.*buffers\|buffers.*domain" src/*.jl`); none found.

---

## 8. `tracer_scheme` (front door) vs `interpolation_scheme` (`Tracers`) is a renamed forward with no stated reason
**VERDICT: ABSENT**

`src/SimulationRun.jl:162-167` — the front-door keyword is no longer renamed: it is now
`interpolation_scheme = CatmullRom` itself, "forwarded to the `Tracers` constructor as its
`interpolation_scheme`" (identical name, no rename). The unrelated axis is `trajectory_scheme =
EndpointHeun()`, no longer named `particle_scheme` — the near-collision the original finding quoted
("despite the neighbouring names") is gone along with the self-acknowledging note itself.
