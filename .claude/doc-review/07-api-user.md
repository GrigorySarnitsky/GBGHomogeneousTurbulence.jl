# Doc-review — Hat: physicist-programmer / API user

Scope: assembling a `Simulation`, warming it up, driving it with `run!`, reading the
`ObservablesCache`, and sampling along `Tracers` — using only the rendered docs.

Overall impression: the public surface is unusually complete for this pass — every constructor's
keywords are enumerated, every checked-read's throw condition is stated, and the exported Index
matches what each page documents. The findings below are the residue: two real ordering/attribution
contradictions in the tracer-cache handoff (the one area where the checked-read contract is genuinely
subtle), plus two low-stakes editorial nits.

---

## Finding 1 — `particles_epoch`'s producer is attributed two different ways, and `advect!`'s own signature rules out one of them

**Type:** contradiction
**Severity:** major
**Confidence:** medium-high

**Locations:**
- PAGE: api / Cache, `ObservablesCache` Fields: "`particles_epoch` — the tracer positions' counter, **advanced when `advect!` moves them**."
- PAGE: api / Cache, `particles_modified!`: "The sanctioned mutator calls it for you: **the run layer announces its own tracer advance** (`advect!` followed by `record_particle_velocities!`, both inside `advance!`), and the run layer then refills the slot for you."
- PAGE: api / Particles, `advect!` signature: `advect!(scheme, tracers, velocity_end, domain, buffers, dt) -> tracers` — no `cache` argument anywhere.

**Contradicts:** the `ObservablesCache` Fields entry names `advect!` as the direct actor that advances `particles_epoch`; the `particles_modified!` docstring instead names *the run layer* (`advance!`) as what announces the change, with `advect!` merely one of the two calls it wraps. The two cannot both be literally true: `advect!`'s documented signature carries no `cache` parameter, so `advect!` itself cannot touch `particles_epoch` — only code holding the cache (i.e. `advance!`, or a hand-written caller) can. Contrast the fields' side, which is unambiguous both places: `fields_epoch`'s Fields entry says "advanced by every completed step **and by `fields_modified!`**," and `fields_modified!`'s own docstring confirms "`step!` advances the epoch itself when it completes" — `step!` *does* receive `cache` as an argument, so that attribution is structurally consistent. The particles side has no such consistent story.

**Description:** A reader building a hand-run particle loop (which the Particles page explicitly invites, via its "Building a set directly" example) is left unable to determine from the docs alone whether calling the sanctioned `advect!` is itself sufficient to keep `particles_epoch` correct, or whether a `particles_modified!`-equivalent call is additionally required whenever a cache is in play — the two passages point in different directions on exactly this question.

---

## Finding 2 — `deposit!(sim)` is credited with filling the particle-velocities slot, which the documented iteration order and the Cache module's own verbs both rule out

**Type:** contradiction
**Severity:** major
**Confidence:** medium

**Locations:**
- PAGE: notation, Vocabulary: "iteration | one advance of the run, in this order: choose the timestep, **`step!` the fields, `deposit!` to close them, then advance any tracers** and record their sample."
- PAGE: api / Propagator, `deposit!`: "The particle-velocities slot is not among them: it depends on the tracer positions as well as the state, so it is filled by `record_particle_velocities!` wherever the positions move — **which `advance!` and the `deposit!(sim)` form above both do for you**."
- PAGE: api / Cache, `deposit_sample!`: "Record the particle velocities already written into `cache`... Use it after writing new values along the trajectories — `record_particle_velocities!` writes, **this call records**." (i.e. the slot is only made readable by `deposit_sample!`, a `Cache`-module verb `deposit!`'s own docstring never names.)

**Contradicts:** the canonical iteration order fixes `deposit!` (fields) strictly *before* the tracer advance — tracers "come last because their second velocity sample is interpolated from the field the deposit just made current" (same Vocabulary entry). If that order holds, `deposit!(sim)` runs *before* any tracer has moved, so it cannot itself be what "fills" `record_particle_velocities!`'s output "wherever the positions move," since the positions have not yet moved at that point in the sequence. The `deposit!` docstring's claim that `deposit!(sim)` does the particle-velocities work "for you" also never names `deposit_sample!`, the verb the Cache page identifies as the actual slot-finalizer.

**Description:** A user closing a hand-run iteration with `deposit!(sim)` cannot tell from this page alone: (a) whether that call also advances/records the tracers (contradicting the stated step!→deposit!→advect! order), or (b) if it doesn't, why its docstring says it does the particle-velocities filling "for you." Either the order or this claim is imprecise; the docs should say which, since this is exactly the checked-read boundary (`particle_velocities` throwing on a stale slot) a user is most likely to hit by copying the wrong closing call.

---

## Finding 3 — `step!` and `deposit!`'s argument order is claimed to "line up," but `step!` interposes `generator` between `state` and `domain`

**Type:** clarity
**Severity:** minor
**Confidence:** low-medium

**Locations:**
- PAGE: api / Propagator, `step!`: "After the leader both take `state`, `domain`, `buffers` in that order, so **a hand-run loop's two calls still line up**."
- Signatures on the same page: `step!(scheme, state, generator, domain, buffers, cache, dt)` vs. `deposit!(cache, state, domain, buffers)`.

**Description:** `deposit!`'s tail is exactly `state, domain, buffers` (positions 2–4), but `step!`'s tail is `state, generator, domain, buffers, cache, dt` (positions 2, 4, 5 for the same three names, with `generator` inserted between `state` and `domain`, and `cache`/`dt` following `buffers`). The relative order of the three shared names is indeed preserved, but "still line up" overstates it for a reader expecting the two calls to read positionally parallel when placed one above the other; the extra interposed arguments are the point most likely to trip a copy-paste hand-run loop.

---

## Finding 4 — Duplicated sentence in `recommended_cfl`'s IFRK2 caveat

**Type:** format
**Severity:** nit
**Confidence:** high

**Locations:**
- PAGE: api / Propagator, `recommended_cfl`: "...the practical course at high Reynolds number is to prefer `IFLowStorageRK3`, **whose ceiling has no such dependence**, or to pass an explicit `cfl` and verify it against a run that holds its energy. **`IFLowStorageRK3`'s ceiling carries no such dependence.**"

**Description:** The same claim — that `IFLowStorageRK3`'s CFL ceiling carries no dependence on viscosity — is stated twice back to back, the second time as a standalone trailing sentence that adds nothing beyond what the clause just before it already said. Reads as leftover text from an edit rather than a second, distinct point.

---

## Summary

Findings 1 and 2 are the substantive ones: they sit precisely at the checked-read contract's most
delicate seam (the two-epoch particle-velocities slot), which is the one place in an otherwise very
thorough API surface where the "who does this and when" story does not stay internally consistent
across the pages a user is directed to (`notation.md`'s Vocabulary, the `Cache` module page, and the
`Propagator` module page). Everything else audited — every public constructor's keyword completeness,
every checked accessor's throw condition, the exported Index against each page's own docstrings, and
the cross-page formula consistency (`Li2008`'s `G = (3/2)C_ε^{-2/3}` identity, the per-step transform
counts, the CFL constant derivation) — checked out clean.
