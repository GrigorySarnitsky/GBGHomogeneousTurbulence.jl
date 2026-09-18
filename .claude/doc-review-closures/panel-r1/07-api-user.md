# Closure — Hat 07: physicist-programmer / API user

## Finding 1 — `Simulation`'s own docstring contradicts the architecture doc on whether `sim.tracers` is a reading surface

**Verdict:** ABSENT

**Evidence:** `src/SimulationRun.jl:191` now reads "Three of these are what a user reads — `state`,
`cache`, and `tracers`." (was "Two of these … `state` and `cache`"), and `tracers` keeps its own
bullet describing the `Tracers`/`trajectory_scheme`/`particle_buffers` group as before. Confirmed
in the built page `docs/build/api/SimulationRun/index.html` ("Three of these are what a user
reads — `state`, `cache`, and `tracers`"). Matches architecture §4.7's `sim.tracers` framing; no
remaining "Two of these" text anywhere in `src/`, `docs/src/`, or `docs/build/`.

---

## Finding 2 — `deposit_sample!`, required by the documented hand-run particle-repositioning recipe, is never documented or indexed anywhere

**Verdict:** ABSENT

**Evidence:** `deposit_sample!` is now exported (`src/GBGHomogeneousTurbulence.jl:99,178`), has its
own docstring in `src/Cache.jl:262-278`, and is listed under `docs/src/api/Cache.md`'s `@docs`
block alongside `ObservablesCache`/`fields_modified!`/`particles_modified!`. `src/Particles.jl:234`
now names it explicitly with an `@ref`. Confirmed present in built
`docs/build/api/GBGHomogeneousTurbulence/index.html` and `docs/build/api/Cache/index.html`.

---

## Finding 3 — `BandRescaling` is the one forcing constructor missing a per-argument `Arguments` list

**Verdict:** ABSENT

**Evidence:** `src/Forcing.jl:261-266` now carries a bulleted `# Arguments` section for
`BandRescaling` enumerating `domain`, `target`, `over`, and `lowest_shell = 1, highest_shell = 2`
individually, matching `Linear` (line 326), `ConstantPower` (line 384), and `StochasticOU`
(line 447) — all four forcing constructors now have parallel `# Arguments` sections.

---

## Finding 4 — The `ArgumentError` a user hits inside `FlowConditions(...)` is documented only on a different page

**Verdict:** ABSENT

**Evidence:** `src/Generator.jl:69-73` (`# Arguments` section of `FlowConditions`'s own
docstring) now states: "A *stateful* strategy must not be the same instance for both fields …
and the constructor throws an `ArgumentError` naming the strategy if it is; build two." The
throw condition is documented on the type whose constructor raises it, not only on
`AbstractForcing`.

---

## Finding 5 — The stated `viscosity`/`κ_max_η` mutual-exclusivity contract is hard to reconcile with `κ_max_η`'s always-present default

**Verdict:** ABSENT

**Evidence:** `src/SimulationRun.jl:65,68` now show `κ_max_η = nothing` in the signature (a
sentinel, not the numeric default `2`), and the `# Arguments` entry (line 136-139) states: "It
defaults to `nothing` and grid mode then uses `2`; the sentinel is what lets the constructor tell
an omitted keyword from an explicit one, so that giving both it and `viscosity` is an error rather
than a silent drop." The ambiguity the finding raised (ordinary default vs. sentinel) no longer
exists; the code's own check at line 245 (`!isnothing(viscosity) && !isnothing(κ_max_η)`) matches
the documented contract exactly.
