# Software-architect hat — findings

Reviewing the documented API/design surface of `GBGIsotropicTurbulence` as a Julia expert: signatures,
argument order, the f/f! convention, type/module decomposition, coupling, and decision-log consistency.
Findings are ranked most-severe first.

---

## 1. `velocity_rhs!` and `scalar_rhs!` silently destroy different, non-predictable argument positions

**Type:** api-gap · **Severity:** major · **Confidence:** high

**Locations:**
- PAGE `api / Generator`, `velocity_rhs!(N̂, generator, û, u, ω, domain)`: "The assembly consumes `ω` as its own register … on return `ω` no longer holds the vorticity."
- PAGE `api / Generator`, `scalar_rhs!(N̂, generator, û, φ̂, u, φ, domain)`: "The assembly consumes `u` as its own register … on return `u` no longer holds the velocity; `φ` is only read."

**Description:** Both functions have exactly one non-`N̂` argument silently clobbered into scratch, each
documented only in a `Note`. But the *position* of the destroyed argument is not systematic: in
`velocity_rhs!` it is the **last** physical-space argument (`ω`, position 5 of 6), while the earlier one
(`u`) survives; in `scalar_rhs!` it is **not** the last physical-space argument — `u` (position 5 of 7)
is destroyed while the later `φ` (position 6) survives. A caller cannot infer from argument order (or
from the `!` convention, which normally flags only the leading argument) which of several apparently
read-only inputs will come back garbage; they must re-read each docstring's `Note` every call site. This
is exactly the "spooky action on a non-leading argument" class of Julia API smell, made worse by the two
sibling functions of the same protocol disagreeing on where the trap sits.

**Contradicts:** (n/a — internal API inconsistency between the two halves of one documented protocol)

---

## 2. No `particles_modified!` counterpart to `resolved_fields_modified!`, despite a documented two-epoch design and a general "write via the dot path" convention

**Type:** api-gap · **Severity:** major · **Confidence:** medium

**Locations:**
- PAGE `api / Cache`: `fields_epoch` and `particles_epoch` are both first-class freshness axes ("the
  second freshness axis of the trajectory-bound slots"), and `resolved_fields_modified!` exists only for
  the former: "Announce that the resolved fields … were changed outside the iteration … Advances the
  fields epoch."
- PAGE `architecture`, decision (2026-08) "The loop is observation-first": "a function names what the run
  holds, wherever it lives … while writing stays on the dot path, where the danger demands the knowledge."

**Description:** The cache's staleness model is explicitly two-axis (`fields_epoch`, `particles_epoch`),
and the architecture generalizes "writing stays on the dot path" as the rule for any out-of-band
mutation, not one scoped to `sim.state` alone. Yet only the fields side has a documented announce-verb;
a caller who repositions tracers directly (e.g. a reseed or a periodic-wrap correction written through
`sim.tracers`, exactly the pattern `random_solenoidal_velocity!` sanctions for `sim.state`) has no
documented way to invalidate the `particle_velocities` slot's `particles_epoch` stamp. Either the gap is
real (an announce verb is missing) or the "dot path" generalization is narrower than stated and should
say so explicitly — as written the two read inconsistently.

**Contradicts:** the general "writing stays on the dot path" rule (decision log, 2026-08) vs. the
one-sided invalidation surface (`Cache` page)

---

## 3. `FlowParameters.scalar_dissipation` uses `NaN` as an "unset" sentinel rather than `nothing`/`missing`

**Type:** api-gap · **Severity:** major · **Confidence:** medium

**Locations:**
- PAGE `api / phenomenology / Phenomenology`, `FlowParameters`: "`scalar_dissipation` — the scalar
  dissipation rate $\varepsilon_\varphi$ (only scalar laws read it); default `NaN` (unset)."
- PAGE `api / SimulationRun`, `flow_parameters`: "the scalar dissipation $\varepsilon_\varphi$ … is left
  `NaN` only for a scalar-free run."

**Description:** Julia's idiomatic way to say "this dimension has no value yet" is `nothing` or
`missing`, precisely because both propagate as loud, immediate `MethodError`s the moment arithmetic is
attempted on them. `NaN` is the opposite: it propagates silently through every downstream floating-point
operation, so a scalar law mistakenly evaluated on an unscalared run (or a user bug that forgets to set
`scalar = true`) produces a quietly wrong `NaN` result rather than an informative failure at the point of
misuse. Given the codebase's own stated discipline against silent failure modes (the cache's
throw-on-stale design is the same instinct applied elsewhere), a `Union{Float64,Nothing}` here would be
more consistent with the package's own house style.

**Contradicts:** the throw-on-invalid-read philosophy elsewhere in the package (e.g. `Cache`'s
"nothing is ever recomputed on a read … it throws") vs. this one silently-propagating sentinel

---

## 4. The forcing four-hook protocol's second positional argument means "the thing about to be mutated" in three hooks but "read-only context" in the fourth

**Type:** api-gap · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE `api / Forcing`: `set_forcing_rate!(forcing, rate, field, domain) -> rate` — position 2 (`rate`) is
  the mutated/returned argument.
- Same page: `add_forcing_source!(forcing, nonlinear, domain) -> nonlinear` — position 2 (`nonlinear`) is
  again the mutated/returned argument.
- Same page: `apply_forcing!(forcing, field, domain) -> field` — position 2 (`field`) is again
  mutated-in-place and returned.
- Same page: `prepare_forcing!(forcing, field, domain, dt) -> nothing` — position 2 (`field`) is
  **read-only** here; the actual mutation target is the opaque internal state of `forcing` itself.

**Description:** Three of the four protocol hooks put "the argument this call mutates and returns" in
position 2; the fourth uses the same slot for a read-only input while mutating something the signature
never names. A third-party forcing author skimming the protocol by position (a reasonable habit once a
pattern holds three-for-three) will misread `prepare_forcing!`'s contract.

---

## 5. `displaced_velocity_fresh` couples `velocity_rhs!` and `scalar_rhs!` through a hidden boolean side-channel, invisible in either signature

**Type:** api-gap · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE `api / Generator`, `ResolvedGenerator` fields: "`displaced_velocity_fresh` — whether
  `phase_shift.u_shifted` still holds the current stage's displaced velocity, left fresh by
  `velocity_rhs!` for the same stage's `scalar_rhs!` to consume."
- PAGE `architecture`, decision (2026-08) "The displaced velocity is reused within the stage": "the
  contract is opportunistic, not load-bearing for correctness."

**Description:** The six-verb generator protocol is presented as stage-order-safe by construction
("a scheme can never assemble the right-hand side from a mismatched intermediate state") — precisely
the property that motivated the reification in the first place (the RK3 stage-ordering bug, decision
31/32). `displaced_velocity_fresh` reintroduces a smaller version of the same hazard one level down: two
of the six verbs now communicate through a mutable flag on the shared object rather than through their
signatures, so their correctness (as an optimization, not as a correctness matter — the doc is explicit
the fallback is safe) depends on call adjacency that no type signature encodes. Worth a documented
callout at the protocol level (not just in the field list), since it is exactly the pattern the protocol
was built to rule out for the coarser stage-ordering case.

---

## 6. `step!`'s `integrator` argument is a stateless dispatch tag, naming-colliding with the wider Julia/SciML convention where "integrator" denotes the full stateful object

**Type:** other · **Severity:** minor · **Confidence:** low

**Locations:**
- PAGE `api / Propagator`, `AbstractIntegrator`: "A scheme implements `step!(integrator, state,
  generator, domain, buffers, cache, dt)`."
- PAGE `api / Propagator`, `IFLowStorageRK3()` / `IFRK2()`: both are zero-field, argument-free
  constructors — pure dispatch tags with no internal state.

**Description:** In the wider Julia numerical-ODE ecosystem (`OrdinaryDiffEq.jl` / SciML), `step!` takes
a single `integrator` object that *bundles* the state, caches, and solver internals — `step!(integrator)`
needs nothing else. Here `integrator` names only the scheme choice (`IFLowStorageRK3()`), a stateless
value type, while the actual state, cache, generator, and buffers are threaded as five separate sibling
arguments. This is a defensible design (matches the package's stated no-god-object, arrows-external
style) but the identifier `integrator` for a bare dispatch tag will read as a false cognate to anyone
coming from the SciML idiom, where the same name means something categorically richer. A more specific
name (`scheme`) would avoid importing that reader's prior expectation.

---

## 7. `Pope2000` / `VonKarman1948` / `Pao1965` are `Function`s with Type-shaped (PascalCase, constructor-call) names

**Type:** other · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE `api / phenomenology / Spectra`: "`Pope2000` / `VonKarman1948` / `Pao1965` are factory functions
  that assemble and return a composed `ModelSpectrum`."
- Same page, index entries: `GBGIsotropicTurbulence.Phenomenology.Spectra.Pope2000` — Function (yet
  called exactly as `Pope2000(; C_K = 1.5, …)`, indistinguishable at the call site from a type
  constructor).
- PAGE `phenomenology`: "test `spec isa EnergySpectrum` on the value they return, not on the preset
  name" — the docs themselves flag the resulting trap.

**Description:** This is self-aware and explained (composed presets vs. concrete-subtype presets like
`ObukhovCorrsin1949`), but it is still a real Julia-idiom violation: PascalCase is conventionally reserved
for types, and a capitalized callable that returns a *different* concrete type than its own name breaks
`methods(Pope2000)` / `Pope2000 <: EnergySpectrum` reasoning a reader will reasonably attempt. The
package's own remedy ("test `isa`, not the preset name") is a workaround for the naming choice, not a
resolution of it — a lowerCase factory name (`pope2000`) would have sidestepped the ambiguity entirely
without losing the "author-year handle" naming scheme (`Spectra.pope2000` reads just as citation-like).

---
