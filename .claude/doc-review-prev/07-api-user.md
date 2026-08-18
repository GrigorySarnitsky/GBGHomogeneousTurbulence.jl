# Doc-review panel — hat: physicist-programmer / API user

Reviewed the full rendered manuscript (Home, architecture, notation, observables_cache, phenomenology
index, and every `api/*` page) as a user who wants to assemble a `Simulation`, warm it up, observe it
with `run!`, read the cache, and sample tracers — from the docs alone. Overall the surface is unusually
consistent (constructor/keyword coverage, representation labeling, and cross-page formula agreement all
checked out almost everywhere); the findings below are the genuine gaps and drift that survived that
sweep.

---

## Finding 1 — Several in-place protocol verbs never document their return value, while their siblings do

**Type:** api-gap
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE `api / Generator`, `velocity_rhs!(N̂, generator, û, u, ω, domain)` — full docstring body never
  states what is returned (no `-> …` in the signature, no "Returns …" sentence).
- PAGE `api / Generator`, `scalar_rhs!(N̂, generator, û, φ̂, u, φ, domain)` — same omission.
- PAGE `api / Propagator`, `step!(integrator, state, generator, domain, buffers, cache, dt)` — same
  omission.
- PAGE `api / Propagator`, `deposit!(cache, state, domain, buffers)` — same omission.
- PAGE `api / SimulationDomain`, `dealias!(field, domain)` — same omission.

**Contradicts:** the sibling verbs in the very same protocols document their return explicitly — PAGE
`api / Generator`: "`prepare!` … Returns `generator`." and "`finalize!` … Returns `state`."; PAGE
`api / Observables`: "`vorticity_physical!` … Returns `ω`."; PAGE `api / Cache`:
"`resolved_fields_modified!` … Returns `cache` (or `sim`)."; PAGE `api / Forcing`: `set_forcing_rate!(...)
-> rate`, `add_forcing_source!(...) -> nonlinear`, `apply_forcing!(...) -> field` all carry an explicit
arrow.

**Description:** A user hand-assembling a step (the docs explicitly invite this — "a hand-run loop is
`step!` then `deposit!`") cannot tell from `velocity_rhs!`/`scalar_rhs!`/`step!`/`deposit!`/`dealias!`'s
own docstrings whether the mutated argument is returned for chaining or `nothing` is returned. Every
comparable in-place verb elsewhere in the package states this explicitly, so the omission reads as
missed rather than deliberate.

---

## Finding 2 — `uses_linear_rate`'s validation contract ("the constructor rejects it") is not documented where the rejecting constructor lives

**Type:** api-gap
**Severity:** major
**Confidence:** medium-high

**Locations:**
- PAGE `api / Forcing`, `uses_linear_rate`: "a forcing that fills a rate without declaring one is never
  given an array to fill, and **the constructor rejects it** rather than let the forcing go silently
  unapplied."
- PAGE `api / Generator`, `ResolvedGenerator(domain, conditions; scalar = false)` — the only plausible
  "constructor" the previous sentence can mean — documents `product_spectral`, `phase_shift`,
  `velocity_rate`/`scalar_rate`, and `displaced_velocity_fresh`, but says nothing about validating or
  rejecting a misdeclared forcing.

**Description:** `AbstractForcing` is called out as "the one deliberately designed-in extension point"
(architecture §4.4), so a user is expected to write a custom forcing. If they implement
`set_forcing_rate!` but forget `uses_linear_rate`, the failure surfaces at whatever *actually* rejects
it — but that rejection is described only from the Forcing side, never from the constructor's own
docstring, and it isn't even named unambiguously ("the constructor" — of `ResolvedGenerator`? of
`Simulation`? of `FlowConditions`?). A user debugging the rejection has nowhere on the Generator page to
look it up.

---

## Finding 3 — The checked-read exception type is stated once, off to the side, not on the accessors or callback contract that actually throw it

**Type:** api-gap
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE `api / Cache`, `ObservablesCache` (type docstring): "it throws an `ErrorException` whose message
  names the slot and which of the three states it is in."
- PAGE `api / Cache`, `velocity_physical(cache)`: "Returns the deposited field … and throws otherwise …"
  — no exception type named.
- PAGE `api / Cache`, `vorticity_physical`, `scalar_physical`, `particle_velocities`: same pattern —
  each documents an `ArgumentError` for a *missing* scalar/tracers, but none names the exception for the
  stale/scratch/never-deposited case.
- PAGE `api / SimulationRun`, `run!`: "any other return throws (the decision may not be left implicit)"
  — exception type never named anywhere on the page.

**Description:** The "home" docstring for each checked read (the one a user actually calls and would
`catch` around) documents *that* it throws but not *what* it throws; the type is stated only once, on a
different page section (`ObservablesCache`'s own type docstring), which a user calling `velocity_physical`
directly has no particular reason to have read. A `try`/`catch ErrorException` written from
`velocity_physical`'s own docstring alone is a guess, not a documented contract.

---

## Finding 4 — No worked example wires `Simulation` tracers together with `particle_velocities` / `sample!`

**Type:** api-gap
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE `api / SimulationRun`, `Simulation`: three examples (grid mode, explicit mode, domain-first), none
  passing `number_of_tracers`.
- PAGE Home, PAGE `architecture` §2: both quick-start examples omit tracers entirely.
- PAGE `api / Particles`: every entry is a bare signature block with prose, no runnable snippet showing
  `Tracers` built through a `Simulation`, then read via `particle_positions` / `particle_velocities` /
  `sample!`.

**Description:** Every individual piece (the `number_of_tracers` keyword, `particle_positions`,
`particle_velocities`, `sample!`, `velocity_buffer`) is documented on its own, but nothing in the
manuscript shows them wired together end to end — the exact "sample along tracers" workflow this hat was
asked to assemble purely from the docs. A first-time user has to infer the wiring (does `sim.tracers`
exist automatically once `number_of_tracers > 0`? is `particle_velocities(sim)` populated from the first
observation, i.e. at $t_0$, or only after the first `advance!`?) rather than read it off an example.

---

## Finding 5 — Grid-mode viscosity selection (`Li2008`, calibrated for a forced-stationary run) is never cautioned against for a decaying (`NoForcing`) case

**Type:** api-gap
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE `api / SimulationRun`, `Simulation`, "Setting the Reynolds number": grid mode "reads the
  dissipation the box sustains from the box-normalized dissipation law `Li2008`" — a law explicitly
  calibrated on *stationary* forced DNS (per PAGE `api / phenomenology / Scalings`, `Li2008`:
  "$G = k/(L\varepsilon)^{2/3}$ … nearly Reynolds-number-independent" for the JHTDB *forced-isotropic*
  dataset).
- Same docstring, Keywords: "`viscosity` — … omit for grid mode." and separately "Explicit mode: pass
  `viscosity` … for a decaying run (`velocity_forcing = NoForcing()`) or manual control" — phrased as an
  example of when to use explicit mode, not as a restriction on grid mode.

**Description:** Nothing states that combining the default grid-mode $\nu$ selection with
`velocity_forcing = NoForcing()` is inapplicable or produces a viscosity calibrated for an energy balance
the run will never sustain (since `Li2008` presumes the box holds `kinetic_energy` in stationary forced
balance). A user reading only the `Simulation` docstring could plausibly build
`Simulation(grid_points_per_axis = 64, velocity_forcing = NoForcing())`, expecting the automatic
resolution-criterion viscosity to remain meaningful through decay, with no warning that it will not.

---

## Finding 6 — `StructureFunctions` laws' "any other order throws" never names the exception type

**Type:** api-gap
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE `api / phenomenology / StructureFunctions`, `Kolmogorov1941`: "any other `order` throws (K41
  fixes only these two longitudinal moments universally)."
- Same page, `Yaglom1949`: "any other `order` throws."
- Same page, `Lundgren2002`: "any other `order` throws."

**Description:** Same pattern as Finding 3 in a different module: three separate law docstrings promise a
throw on an invalid `order` keyword but never state whether it is an `ArgumentError`, a `MethodError`, or
something else, so a caller cannot write a targeted catch from the documented contract alone.

---

## Finding 7 — `Simulation`'s "Keywords" section lists a positional argument under its own heading

**Type:** format
**Severity:** nit
**Confidence:** medium

**Locations:**
- PAGE `api / SimulationRun`, `Simulation`, under the heading "Keywords": "`domain` — a pre-built
  `FixedDomain`, **the positional argument of the second form** (the front door builds one from
  `grid_points_per_axis`, `side_length`, `dealiasing`, `element_type`, `array_type`)."

**Description:** The bullet is self-explanatory once read, so no reader is actually misled, but a section
titled "Keywords" containing an entry that its own text calls "the positional argument" is an internal
label/content mismatch — a skimming reader scanning bullet names for a keyword called `domain` would be
surprised that passing it as `Simulation(; domain = …)` does not work (it must be positional:
`Simulation(domain; …)`).

---

## Finding 8 — `dissipation`'s two call forms and `scalar_dissipation`'s single form are asymmetric with no note on why

**Type:** clarity
**Severity:** nit
**Confidence:** low

**Locations:**
- PAGE `api / Observables`, `dissipation`: two forms, `dissipation(ω, viscosity)` and
  `dissipation(û, domain, viscosity)`.
- Same page, `scalar_dissipation(φ̂, domain, diffusivity)`: one form only.

**Description:** The velocity route gets a field-argument overload (from an already-recovered `ω`) and a
state-argument overload (straight from `û`); the scalar analogue only gets the state-argument form. This
is defensible (there is no cached, first-class $\nabla\varphi$ recovery the way there is a cached
`vorticity_physical`), but the docstring never says so, so a reader who has just read the velocity route's
two-form pattern may look for (and fail to find any explanation of the absence of) a
`scalar_dissipation(∇φ, diffusivity)` twin.

---

## Summary

The public surface is tightly disciplined overall: every exported name in the umbrella's Index is
documented, every documented type's own constructor and keywords are enumerated, physical-vs-spectral
representation is stated on essentially every field-taking function, and the formula cross-checks
(`Li2008` ↔ `stationary_dissipation` ↔ `Simulation`'s Reynolds-number section; `scalar_dissipation` ↔
`Yaglom1949` ↔ `ObukhovCorrsin1949`; the module dependency order across Home / api / architecture) all
agree exactly. The residual gaps are concentrated in two places a physicist-programmer would actually
hit: **return-value documentation on in-place protocol verbs** (Finding 1) and **exception-type
documentation on checked reads and validation contracts** (Findings 2, 3, 6) — plus one missing
end-to-end tracer example (Finding 4).
