# Fix audit — batch 15–21

Source pile: `.claude/doc-reading-pile-2026-08-15.md`. Diff audited: `git diff 9b3ecdd..HEAD`
(commits `9b3ecdd..ee362b5`). Corpus checked against the current working tree of `src/`, `docs/`,
`CLAUDE.md`, and a locally-built `docs/build/` (timestamped 2026-08-17 22:03, so a real Documenter
build ran after the fixes).

---

## Finding 15 — `max_speed`'s three forms look arbitrary; the rule is nowhere on the surface

**Owner (verbatim):** "What did we decide on extending observables to cache and sim? Here we provide
the signatures, but not for other functions. What shall we do?"

**VERDICT: HONORED**

**Question:** none (fidelity satisfied).

**Evidence.** `src/Observables.jl` (the `max_speed` docstring) now carries a `!!! note "Why this
observable alone has a cached form"` block:

> "The cache holds exactly what the iteration already computes and leaves alive at its end … The
> maximum speed qualifies because the run itself needs it: the next timestep is chosen from it …
> `kinetic_energy` and `dissipation` have no cached form because no part of the iteration computes
> them; caching either would mean adding a reduction the run does not otherwise perform, which is the
> one thing the cache may not do."

This states the exact rule the finding asked for, in the module beside `max_speed` (the finding's own
"and/or its own docstring" alternative). Verified against the code: `kinetic_energy` is called only
from `flow_parameters`/`StationarityCriterion` (observation-time, on demand), never from `step!` or
`deposit!` (`grep kinetic_energy( src/Propagator.jl src/Generator.jl` returns nothing) — the claim is
literally true, not merely plausible.

The finding's second half — "also settle in the same pass: the `(sim)` forms" — is moot rather than
skipped: finding 19 (below) removes every `(sim)` forwarding read, including `max_speed(sim)`, so the
asymmetry the finding flagged no longer exists at all (the docstring's own signature block now reads
only `max_speed(u)` / `max_speed(cache)`, the `(sim)` line deleted).

---

## Finding 16 — `energy_spectrum` "brought to the host": true, but the actor and cost are unstated

**Owner (verbatim):** "Are you sure they are moved to host? I thought PF gives them as the device
arrays."

**VERDICT: HONORED**

**Question:** none.

**Evidence.** The finding's own direction ("name the actor and the cost, keep the 'occasional
diagnostic' justification") was explicitly superseded in-pile by finding 20's decision, which removes
the host transfer altogether rather than documenting it. The current code implements finding 20:
`src/Observables.jl`'s `energy_spectrum` no longer calls `Array(...)` at all —

```julia
function energy_spectrum(û, domain::FixedDomain)
  shells, spec = radial_spectrum(û, domain.multipliers)
  return (; wavenumbers = shells, energy = 0.5 .* spec)
end
```

and the docstring states: "Both arrays live on the backend `û` lives on — bring them to the host
yourself with [`adapt`](@extref …) when you want them there." `grep -n "Array(" src/Observables.jl
src/SimulationRun.jl` returns nothing — the transfer this finding questioned is gone, not merely
explained, which resolves the underlying doubt more completely than the finding's own direction asked
for. (Graded under finding 20 below for the mechanics of the removal; this entry is about whether
finding 16's question was answered — it was, by a stronger fix than requested.)

---

## Finding 17 — OPEN QUESTION: should `kinetic_energy(sim)` / `(cache)` exist?

**Owner (verbatim):** "why don't we have kinetic_energy(sim)? or kinetic_energy(cache)? I would think
they all need to be symmetric."

**VERDICT: HONORED**

**Question:** none.

**Evidence.** This entry is a question, not an instruction; the assistant's own pile entry frames three
options (A/B/C) and defers the choice to the user. The user's follow-up (17b) reopened the question
("why do we do that? as an API for the loop? or what?"), and the chain resolved through 18(1) to
option D (drop every `(sim)` form) — recorded as decision 49, verified under finding 19. `(cache)` for
the uncached observables was correctly assessed as structurally blocked (would violate the
automatic-contents/no-recompute contract) and never added — verified: `grep -n
"kinetic_energy(cache\|dissipation(cache" src/*.jl` returns nothing. The question was answered, acted
on, and the final state matches the decision actually reached (D, not the entry's own tentative B).

---

## Finding 17b — ANSWER: the `(sim)` forms are the uniform read surface, and the set is incomplete

**Owner (verbatim):** "Let us think if we actually need to call anything on sim. Why do we do that? As
an API for the loop? Or what?"

**VERDICT: HONORED**

**Question:** none.

**Evidence.** 17b's own diagnosis (the `run!` docstring example mixes `current_time(s)` with
`kinetic_energy(s.state.velocity)`, exposing the friction) is confirmed still present in the code, but
resolved in the opposite direction from 17b's tentative recommendation (option B — complete the
surface). The user's next message (finding 18(1)) revisited and chose option D (drop the surface
entirely) instead; the `run!` docstring's example was updated accordingly to
`kinetic_energy(s.state.velocity_spectral)` (`src/SimulationRun.jl:420`), not to `kinetic_energy(s)`.
17b's factual observations both survive verification and were acted on by the decision that actually
landed (19/49), not abandoned.

---

## Finding 18 — Three design questions: drop `(sim)`, cache-argument correction, `validate_spectrum`

**Owner (verbatim, three parts):**
1. "Dropping readings on simulation completely, let the user learn what the state and cache holds."
2. "Observables must be defined on cache, right? They just throw if it is not there." (needing
   correction)
3. "Those comparisons with the predicted spectrum were your initiative, I never asked for them. Do we
   really need them? Shall we just move them to testing?"

**VERDICT: HONORED**

**Question:** none.

**Evidence per part:**

- **(1)** Implemented exactly as decision 49 (see finding 19): all eight forwarding reads plus
  `resolved_fields_modified!` are gone from `src/SimulationRun.jl` (`grep -n "::Simulation"
  src/*.jl` lists only `deposit!`, `flow_parameters`, `current_time`, `current_step`, `cfl_timestep`,
  `advance!`, `run!`, `_scalar_forced`, `(criterion::StationarityCriterion)(sim)` — none of the nine
  dropped names remain bound to `Simulation`).
- **(2)** The correction (a hypothetical `f(cache)` for an uncached observable would always throw, not
  conditionally) is folded into `max_speed`'s new note (finding 15): "`kinetic_energy` and
  `dissipation` have no cached form because no part of the iteration computes them … which is the one
  thing the cache may not do." This states the "always, structurally, not conditionally" distinction
  the correction called for.
- **(3)** `validate_spectrum` is verified absent from `src/`: `grep -rn "validate_spectrum"
  src/*.jl` returns nothing. It now lives at `test/validation.jl:64` as `compare_to_model`, matching
  the pile's own accepted direction, and decision 49's log entry (`docs/ARCHITECTURE.md:1664`)
  records the move and its reasoning ("comparing a run against a model spectrum answers 'does this
  reproduce the literature', which is what a validation suite asks and a solver never does").

---

## Finding 19 — DECIDED: drop the 8 forwarding reads + the announcement

**Owner (verbatim):** "Yes, 'Drop (8 reads + 1 announcement)'"

**VERDICT: HONORED**

**Question:** none.

**Evidence.** Full `::Simulation` inventory reproduced from the current source
(`grep -n "::Simulation" src/*.jl`):

```
deposit!, flow_parameters, current_time, current_step, cfl_timestep,
advance!, run!, _scalar_forced, (criterion::StationarityCriterion)(sim)
```

This matches the pile's own post-fix inventory exactly: the 4 "keep — needs the whole object", the 4
"keep — the run layer itself" (`Simulation`'s constructor is present too, just not matched by the
`::Simulation` grep pattern), and the 3 "internal, unexported" — with all 9 "drop" methods and the 1
"drop → test" method (`validate_spectrum`) absent. `docs/ARCHITECTURE.md` decision 49
(`(2026-08, user-directed) A Simulation is a container, not a reading surface`) records the removed
list verbatim (all 8 reads + `resolved_fields_modified!`) and the rationale, matching the pile's
wording closely. `resolved_fields_modified!` itself: `grep -rn "resolved_fields_modified"
src/*.jl test/*.jl` returns nothing outside the decision-log's own historical citations of the old
name — the rename/removal reached every live site, not just the flagged one.

One secondary observation, not a defect against this finding's own ask: decision 43
(`docs/ARCHITECTURE.md:1539`, dated earlier in the same round) still describes "the uniform read
surface completes the redesign" as a standing feature (`velocity_spectral(sim)`,
`particle_positions(sim)`, …) with no cross-reference noting decision 49 retired it — unlike decision
47, which explicitly says "the supersession also retires decision 28's … convention" when it overrides
an earlier entry. The decision log is append-only history per house convention (and finding 6 lists it
as explicitly out of scope for the default-narration sweep), so leaving decision 43's text as written
at the time is defensible; but the *convention* of noting a supersession in the later entry, which the
corpus itself establishes at decision 47, was not followed at decision 49. This does not reach any of
the four audit questions for finding 19 itself (the ask was to drop the reads, which is done
completely and correctly) — noted as evidence, not scored against this finding.

---

## Finding 20 — DECIDED: `energy_spectrum` stops forcing the host transfer; `adapt` is the user's verb

**Owner (verbatim):** "Why can't a user just use adapt if he needs it there?"

**VERDICT: HONORED**

**Question:** none.

**Evidence.** `src/Observables.jl`'s `energy_spectrum` no longer transfers to host (quoted under
finding 16). `integral_scale` was rewritten from a scalar host-side `for` loop to backend reductions,
exactly as the decision specified ("like `kinetic_energy` … already does"):

```julia
total = sum(E)
weighted = sum(broadcast((k, e) -> k > 0 ? e / k : zero(e), κ, E))
```

with a `#` comment explaining why (no host transfer, no scalar indexing of a device array — invariant
4). The `[`adapt`](@extref GBGPeriodicFields Adapt.adapt)` link was checked against a real local
Documenter build (`docs/build/api/Observables/index.html`, built 2026-08-17 22:03): it resolves to
`https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/dev/api/Fields/#Adapt.adapt` — a working,
non-dangling cross-reference, confirmed against the actual `GBGPeriodicFields` clone at
`/home/grigory/Dropbox/Research and Teach/Isotropic Turbulence/GBGPeriodicFields`, where `adapt` is
imported from `Adapt` and documented under that name (`import Adapt: adapt, adapt_structure` in
`src/Fields.jl`), so the `Adapt.adapt` slug (rather than the `GBGPeriodicFields.Fields.foo` pattern
used for IT's own domain objects) is the correct one for this specific external-package re-export, not
a copy-paste error. `test/validation.jl`'s `compare_to_model` is the in-package call site now exercising
`adapt` explicitly, matching the decision's "demonstrates the intended user pattern" consequence.
The per-step synchronization ledger (`test/optimality_audit.jl`) was checked and does not count
`energy_spectrum` at all (it is an occasional, not per-step, call), so no re-derivation was owed there
— consistent with the decision's own scope.

---

## Finding 21 — The `Cache` module docstring's opening: rewrite completely

**Owner (verbatim):** "That's a very bad writing, rewrite it completely. 'an instant of the run's
clock, not a face of the periodic box;' is just gibberish. Plus 'stamp notion'. Too long of a
sentence. And people know what iteration is. And what is 'run stands at t_n'???"

**VERDICT: HONORED**

**Question:** none.

**Evidence.** `src/Cache.jl`'s module docstring is fully replaced. Each of the four complaints is
verifiably gone from the live surface (not merely reworded around):

- **"an instant of the run's clock, not a face of the periodic box"** — `grep -rn "face of the
  periodic box" src/*.jl docs/src/*.md` returns nothing outside `docs/src/architecture.md`'s
  decision-log record of the old text (historical, append-only, legitimate).
- **"the run stands at one t_n"** — `grep -rn "stands at\b" src/*.jl` returns nothing live.
- **"iteration" as a defined term** — the new docstring uses "iteration" as ordinary English
  throughout, with no opening definition of the word.
- **"stamp"** — retired package-wide per decision 25 (audited under a different batch, but confirmed
  here too): `grep -rn "stamp" src/*.jl docs/src/*.md CLAUDE.md` returns nothing live; only
  `docs/src/architecture.md`'s decision-log entries recording the historical rename.

The replacement text states the epoch/clock relation the finding's own draft called for, as a
`!!! note "An epoch is not an iteration number"` block with a worked numeric example (step 2, fields
epoch 4) — stronger than the two-sentence draft suggested in the pile, and it satisfies finding 23's
follow-on demand (documented in this same commit family) that the stamp/epoch relation not be left to
a `#` comment. The operations list beside it links every named verb (`fields_modified!`,
`particles_modified!`, the checked reads, `max_speed`, `deposit!`) rather than leaving them bare.
