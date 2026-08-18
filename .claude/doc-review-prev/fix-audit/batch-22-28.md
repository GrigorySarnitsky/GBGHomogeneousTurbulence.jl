# Fix audit — batch 22–28

Audited against `git diff 9b3ecdd..HEAD` (five "Verifier B" rounds, `53f13d5`…`ee362b5`, plus the
earlier round-2 read commits) and the current corpus at `HEAD`.

---

## 22. `max_speed` is the only unlinked name in the `Cache` map

**Owner's ask:** "Why is max_speed so lonely unreferenced?" — link `max_speed` in `Cache.jl` at its
two bare sites (the module-map bullet, and the `ObservablesCache` accessor list), the same
fully-qualified `@ref` form `Observables.jl` already uses.

**VERDICT: HONORED**

**Question:** none (fidelity + implementation both check out).

**Evidence:** `src/Cache.jl:37` — module docstring bullet: `` [`max_speed`](@ref
GBGIsotropicTurbulence.Observables.max_speed) `` (was a bare `` `max_speed` `` at baseline,
`9b3ecdd:src/Cache.jl:20`). `src/Cache.jl:72` — the `ObservablesCache` constructor docstring's first
mention of `max_speed` is now the same fully-qualified link (was bare at baseline,
`9b3ecdd:src/Cache.jl:57`). The later bare mentions in the same docstring — `:87` ("Read through the
accessors — …, and `max_speed`") and `:102` (the `# Fields` entry) — are correctly left bare: they
are second/third mentions **within the same docstring** as the `:72` link, so leaving them bare
follows CLAUDE.md's "a link earns its place… at most once per docstring — its first genuine
mention," not a miss. Confirmed the module docstring and the constructor docstring are two distinct
docstrings (each closed by its own `"""`), so each legitimately got its own first-mention link,
matching the finding's own framing ("each in a different docstring… gets its own link").

---

## 23. "Stamp" vs "epoch" — the relation was stated only in a `#` comment

**Owner's ask:** "What's the difference between stamp (mind the term, I flagged it previously as
problematic) and epoch?" — the relation between the two nouns must be stated on a user-facing
surface, not just inferred from a `#` comment.

**VERDICT: HONORED**

**Question:** none.

**Evidence:** The finding's own text treats this as strengthening finding 2's open class rather than
demanding independent wording, and directs "whatever wording finding 2 settles on must state the
relation, not just gloss 'stamped'." Finding 25 (below) settled it by **retiring "stamp" outright**
and merging both roles onto one noun, `epoch`. The live module docstring now states the relation
directly: `src/Cache.jl:15–17`, "Each slot carries the value **and** the moment that value belongs
to… That moment is the slot's **epoch**, and the cache keeps two epoch counters saying what the
current moment is… A slot is readable exactly when its own epoch equals the counter it depends on."
That is the "counter is the clock; the per-slot value is the reading of that clock" relation the
finding asked to have stated, delivered by elimination of the second noun rather than by defining
two nouns — a legitimate resolution the finding itself anticipated ("Direction to settle at fix
time… adopt the standard word outright"). Verified zero remaining "stamp" occurrences in any `src/`,
`test/`, or `docs/src/*.md` file, and in `ARCHITECTURE.md` only inside decision-log entry 53's
historical record (append-only, permitted).

---

## 24. `resolved_fields_modified!` → `fields_modified!`

**Owner's ask (decided 2026-08-17):** rename the verb to match the epoch it advances, giving the
symmetric pair `fields_modified!` / `particles_modified!`; land with the other renames in one
commit; record the "no proliferation" rule (decision 30) and correct decision 30's stated SciML
rationale in the same pass.

**VERDICT: HONORED**

**Question:** none.

**Evidence:** `grep -rn "resolved_fields_modified\!"` across `src/`, `test/`, and rendered
`docs/src/*.md` returns **zero** hits outside `ARCHITECTURE.md`'s decision-log entries (append-only
history, explicitly out of scope for the rename per the finding's own spread note). The symmetric
pair is live: `src/Cache.jl:55` exports `fields_modified!, particles_modified!`; both are called
from `src/Propagator.jl:319,420`, `src/SimulationRun.jl:379`, and referenced from `src/State.jl:92,
161` and `src/Propagator.jl:486`. Decision 30 (`docs/ARCHITECTURE.md:1102–1119`) is corrected in
place: it now names `fields_modified!`, discloses the original name was
`resolved_fields_modified!`, and reverses the SciML-lesson rationale exactly as directed ("a
rationale that is backwards for this verb: `fields_modified!` names the mutated slot, and it earns
its place by saying plainly what a caller did"). The disclosure gap the finding did not itself
raise (round 5's commit found and fixed an earlier under-disclosure of the rename inside decision
30's own parenthetical) is a bonus, not a deficiency, and does not change the verdict.

---

## 25. One noun for both roles (`epoch`); "stamp" retired; epoch ≠ iteration must be documented

**Owner's ask (decided 2026-08-17):** rename every `_stamp` field to `_epoch`; retire "stamp"
entirely; and **mandatorily** document, at four named sites (the `ObservablesCache` `# Fields`
entry for the counters, the `Cache` module docstring, `docs/src/observables_cache.md`, and
`current_step`'s own docstring), that the epoch is **not** the iteration number — with the carried
wording explicitly avoiding the "run stands at" construction the owner had separately called
"gibberish" (finding 21).

**VERDICT: LINE-ONLY**

**Question:** implementation.

**Evidence:** The rename landed cleanly — `velocity_stamp` → `velocity_epoch` etc. confirmed at
`src/Cache.jl:119–129` and threaded through `_checked`, `deposit_*!`, `take_*!`; zero `_stamp`
identifiers remain anywhere in `src/` or `test/`. All four mandated sites carry *some* form of the
epoch-≠-iteration distinction: `src/Cache.jl:104–110` (`# Fields`, `fields_epoch`), `src/Cache.jl:21`
(the `!!! note "An epoch is not an iteration number"`), `docs/src/observables_cache.md:146–148`, and
`src/SimulationRun.jl:334–337` (`current_step`). But the round-3 fix-audit itself (`471dd4a`)
diagnosed, and removed from `src/Cache.jl` only, the exact anthropomorphic phrase the owner had
banned in finding 21 — *"the run stands at one `t_n`"* — after it had been reintroduced in fresh
words to satisfy finding 25: *"a run at step 2 may stand at fields epoch 4."* That construction
survives verbatim, unfixed by any of rounds 3–5, at two of finding 25's own four mandated sites:
`src/SimulationRun.jl:336` — "so a run at step 2 may stand at fields epoch 4" — and
`docs/ARCHITECTURE.md:1723` (decision 53, freshly authored prose describing *this* pass's change,
not a preserved historical quote) — "so a run at step 2 may stand at epoch 4 — measured, not
assumed." The class (banned anthropomorphic "run … stand[s] at") was fixed at its one instance in
`Cache.jl` and left standing at two of the four sites finding 25 itself named as mandatory — a
textbook LINE-ONLY: the flagged instance corrected, the class alive at named sibling surfaces.

---

## 26. "Register" — undefined term of art, worst in `Cache`

**Owner's ask:** "it seems that 'register' is undefined. I don't know what is the recovery
register." Direction (assistant's own recommendation, not decided by the owner, but internally
consistent): keep and gloss "register" in `Propagator` (its literature home), replace it with plain
words ("scratch") in `Cache` and `Particles`, away from the RK context.

**VERDICT: HONORED**

**Question:** none.

**Evidence:** The screenshot clause — `Cache.jl`'s `# Fields` entry describing `velocity`/`vorticity`
as doubling as "the step's stage recovery registers" — is gone; the current `# Fields` entry
(`src/Cache.jl:97–99`) reads "Mid-iteration the step also computes its stage recoveries *into these
same arrays*, which is why they are not readable then," with no jargon. `grep -n -i register
src/Cache.jl src/Particles.jl` returns hits only inside `#` comments (non-rendered): `Cache.jl:6`,
`Particles.jl:7,13,38,280` — none in a rendered triple-quoted docstring. `docs/src/api/Particles.md`
carries zero "register" mentions (the finding's flagged "no-RK-context surface"). `Propagator.jl`
keeps the word and glosses it at first use (`src/Propagator.jl:83`, "Each such array is a
**register**: storage a scheme computes one stage into and overwrites at the next…"), and the round-5
self-audit caught and fixed a false corpus-wide-usage claim in that same gloss (it had claimed the
cache's slots "double as the step's registers," directly contradicting the just-landed `Cache.jl`
fix); the current text correctly describes what the cache slots *do* without calling them
registers. `docs/src/observables_cache.md` also defines "register" at its own first use
(`docs/src/observables_cache.md:96`), satisfying the finding's option-1 path for that surface. No
scope creep: the module docstring's own residual "A slot IS the register its producer computes in"
(`Cache.jl:6`) is a `#` comment, invisible at the REPL, and CLAUDE.md's convention deliberately
exempts `#` comments from the rendered-docs discipline.

---

## 27. `particle_velocities`' `# Fields` entry explains another function's mechanics

**Owner's ask:** "'(the tracer set's own point-value storage, whose `(M, 3)` array the accessor
extracts with `point_values`),' — unclear what is meant and why it is needed." The finding's own
direction: delete the mechanics clause; what should replace it is the aliasing/no-allocation fact
(the cache allocates nothing for this slot).

**VERDICT: HONORED**

**Question:** none.

**Evidence:** `src/Cache.jl:103` now reads "`particle_velocities` — the particle-velocities slot, or
`nothing` for a tracer-free run" — the `point_values`-naming clause is gone, not merely reworded
beside itself (confirmed via `git log -p` on `src/Cache.jl`: the hunk is a straight deletion, `-
whose (M, 3) array the accessor extracts with point_values), or` → nothing, no replacement clause
appended in its place). The informational content the finding said was missing — that the slot
*aliases* the tracer set's own storage rather than being cache-allocated — is present earlier **in
the same docstring** (the `ObservablesCache` constructor doc, `src/Cache.jl:78–80`: "`particle_velocities`
— the tracer set's own point-value storage — when the run advects tracers: the slot IS that storage,
so the tracers' push writes the values and the cache only records which epochs they belong to"),
satisfying the finding's actual concern without repeating it a second time in the same docstring —
and without citing "(decision 42)" verbatim in a docstring, which the finding's own suggested
wording would have done and which CLAUDE.md's "no dead references on the user-facing surface" rule
forbids. Not a case of fix-by-insertion: the flagged clause is gone, not padded.

---

## 28. `particle_velocities`' predictor Note — cut it

**Owner's ask:** "I think this note is redundant. Who would think of reading the predictor step?
Plus, that's dependent on the particle integration scheme." — cut the `!!! note` explaining that
`particle_velocities` is never the corrector-stage velocity.

**VERDICT: HONORED**

**Question:** none.

**Evidence:** `grep -n -i "predictor\|corrector" src/Cache.jl` returns zero hits — the note is fully
gone, not reworded or relocated with a residual defect. `git log -p` confirms a straight deletion (a
`-!!! note` / `-    This is never the second velocity…` hunk with no corresponding addition in
`Cache.jl`). The equivalent, scheme-specific fact the finding said already lives at its correct home
survives there unchanged: `src/Particles.jl:195`, `Tracers`' own `# Fields` entry for
`predictor_velocity` — "the interpolated velocity at the Heun predictor positions… a stage
register of the push, never a sample of the flow, and never exposed" — so no information was lost,
only the duplicate removed from the surface where a reader reaching for the Lagrangian sample has no
reason to meet it.
