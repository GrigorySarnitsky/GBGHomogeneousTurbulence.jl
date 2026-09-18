# Fix audit — batch 64–70

## 64 — "The `Simulation` `Simulation` must start somewhere" — rename fossil

**Owner's ask (verbatim):** "REWRITE: restore the missing noun (\"the `Simulation` constructor must
start somewhere\")."

**VERDICT: HONORED**

**Which question:** none (passed all four).

**Evidence:** `docs/ARCHITECTURE.md:640` now reads "(The `Simulation` constructor must start
somewhere and starts at `Float64` / `Array`; …)" — the exact restoration the owner specified,
word for word. `git diff 0b3d58c..HEAD -- docs/ARCHITECTURE.md` shows the change is a targeted
substitution (`` `Simulation` `Simulation` `` → `` `Simulation` constructor``), not an insertion
beside the fossil. A corpus grep for `` `Simulation` `Simulation` `` / `"Simulation Simulation"`
across `src/` and `docs/` returns nothing, so no sibling fossil survives elsewhere.

---

## 65 — "the form mirroring `particles_modified!`'s two" — ellipsis the reader cannot fill

**Owner's ask (verbatim):** "REWRITE" — citing the twin's own sentence ("mirroring `deposit!`'s
own `sim` form") as the readable shape to match, and noting the defect is a category mismatch
(one form cannot "mirror" two).

**VERDICT: HONORED**

**Which question:** none.

**Evidence:** The flagged sentence lived in `fields_modified!`'s docstring
(`src/Cache.jl:360-362`), not `particles_modified!`'s (the pile's location line names
`fields_modified!`). It now reads: "Given a `Simulation` it announces the change to that run's
cache — the form to reach for when a run is what you are holding (`particles_modified!` offers
the same pair of forms)." This replaces the broken "mirroring X's two" construction with a
grammatical claim about the *pair* of forms, matching the model shape the owner pointed to. The
twin sentence in `particles_modified!` (`src/Cache.jl:411-413`, "mirroring `deposit!`'s own `sim`
form") is untouched, as it was already the readable exemplar, not itself flagged.

---

## 66 — Over-long multi-clause sentences in ARCHITECTURE (4 locations, counts reported)

**Owner's ask (verbatim):** "REWRITE: split each at its clause seams" for locations A
(Triangularity bullet, ~85 words / 6+ clauses), B (run-layer §2 sentence, ~70 words / 5 clauses),
C (§4.1 "per-step scratch is not state", ~60 words / 4 clauses), D (§4.7 `StationarityCriterion`
bullet, a parenthesis spanning a sentence boundary).

**VERDICT: ADJACENT**

**Which question:** FIDELITY (landed at B, C, D; only partially at A).

**Evidence:**
- **B** (`docs/ARCHITECTURE.md:72-77`): cleanly split into three short sentences ("The run layer
  holds the pieces of §4 in one `Simulation` value." / "Each iteration it chooses a stable
  timestep … (§4.1)." / "It runs the **observation-first loop**: …"). Fully resolved.
- **C** (`docs/ARCHITECTURE.md:237-238`): split into two sentences at "The per-step scratch is
  not state: …" / "Each is preallocated, so a step allocates no field-sized memory (§9,
  invariant 4), and sized to the run — …". Fully resolved.
- **D** (`docs/ARCHITECTURE.md:494-499`): the parenthesis is removed outright — "a
  trailing-window flatness test …" is now an em-dash appositive, not a paren, and "When the
  scalar is forced, ⟨φ²⟩ must settle too." is its own sentence with a period. The specific defect
  (closing bracket landing two sentences after it opened) is gone. Resolved.
- **A** (`docs/ARCHITECTURE.md:815-823`, the Triangularity bullet): only partially split. The
  diff (`git diff 0b3d58c..HEAD -- docs/ARCHITECTURE.md`) shows "Triangularity is what licenses
  the composed propagator — splitting error … *up* the triangle — and it gives every state slot a
  litmus: **the restart record holds …**" was broken into three sentences ("Triangularity is what
  licenses the composed propagator: splitting error cannot propagate *up* the triangle." / "It
  also gives every state slot a litmus." / "**The restart record holds exactly what the flow map
  needs** — û, φ̂, the tracer positions, and a stochastic forcing's internal state (the
  extended-phase-space discipline of molecular dynamics' thermostats); the observables cache
  holds spent compute, reconstructable from the record (delete it and the trajectory is
  unchanged); and the clock and what a run records are the experimenter's logbook rather than
  physics."). The third sentence is essentially the *same* semicolon-chained, doubly-parenthesized
  content as before (only reformatted — parens → em-dash for the initial list), still ~60 words
  across three semicolon-joined clauses with two nested parentheticals. It was not itself split at
  its own clause seams (the semicolons), so this specific flagged instance still exceeds the
  ~40-word bar the finding measured the original against, even though the sentence it was
  fused to was successfully detached.

Three of the four counted locations are fully resolved; the location with the worst measured
count (85 words / 6+ clauses) was only partly de-fused, leaving a residual run-on that the "split
at its clause seams" instruction did not fully reach.

---

## 67 — "A defence against a confusion nobody has" — repeated verbatim on three pages

**Owner's ask (verbatim):** "CUT (on all three copies — it is one template)" — striking the whole
"A few works are cited in `ARCHITECTURE.md` as well…" passage.

**VERDICT: HONORED**

**Which question:** none.

**Evidence:** `git diff 0b3d58c..HEAD -- docs/src/api/phenomenology/{Scalings,Spectra,
StructureFunctions}.md` shows the identical removal in all three files: "A few works are cited in
`ARCHITECTURE.md` as well, where the DNS side needs them — the leaf's independence means it does
not *rely* on that list, not that the two never overlap." is deleted outright, leaving "… so a
reader never has to leave the page for them. This list is scoped to the laws' own provenance;
…". A corpus grep for "leaf's independence" / "never overlap" / "A few works are cited" over
`docs/src/api/phenomenology/*.md` returns nothing — the CUT, not a reword, was applied identically
to all three template copies as instructed.

---

## 68 — "it is listed last here because a reader meets it last" — circular

**Owner's ask (verbatim):** "REWRITE to name the actual reason, or CUT the clause."

**VERDICT: HONORED**

**Which question:** none.

**Evidence:** `docs/src/index.md:132` now reads: "this dependency-light leaf comes *first*; it is
listed last here because a user's workflow reaches it last — validating against the laws comes
after running." The diff (`git diff 0b3d58c..HEAD -- docs/src/index.md`) shows the added clause
"— validating against the laws comes after running" replacing the bare, self-referential "a
reader meets it last." The new clause names an external reason (workflow order: validation
follows a run) rather than restating the listing's own position, so the circularity — the claim
justifying itself by pointing at the very list it sits in — is resolved.

---

## 69 — The glossary's τ row points "below" at a row that is above

**Owner's ask (verbatim):** "REWRITE (\"above\", or name the section)."

**VERDICT: HONORED**

**Which question:** none.

**Evidence:** `docs/src/notation.md:93` now reads "in the integrating-factor row of *Spectral
representation and operators* above, ``\tau`` is a Runge–Kutta stage substep …". Both suggested
repairs were applied together — "above" replaces "below", and the section is named ("*Spectral
representation and operators*"). Checked against the actual document order: the ``\mathcal{E}``
integrating-factor row is at `docs/src/notation.md:64`, the τ glossary row at line 93 — 64 < 93,
so "above" is now geometrically correct and the pointer resolves.

---

## 70 — "consumed (the closing note)" — collides with the house sense of "closing"

**Owner's ask (verbatim):** "REWRITE" — "A pointer should name what it points at (\"see the note
below\")." — at both `velocity_rhs!`'s `ω_consumed` and `scalar_rhs!`'s `u_consumed`.

**VERDICT: HONORED**

**Which question:** none.

**Evidence:** `src/Generator.jl:473` ("`ω_consumed` — the stage vorticity in physical
representation, consumed (see the note below).") and `src/Generator.jl:637` ("`u_consumed` — the
stage velocity in physical representation, consumed (see the note below).") both now use the
owner's own suggested phrasing verbatim. Verified the pointer is not merely reworded but correct:
line 473 points to the `!!! note "The vorticity argument is read and then overwritten"` admonition
at `src/Generator.jl:509` (below, same docstring); line 637 points to the `!!! note "The assembly
consumes the velocity argument"` admonition at `src/Generator.jl:718` (below, same docstring). A
corpus grep for "the closing note" over `src/` and `docs/` returns no remaining hits — the class
is fully swept, both flagged sites and no others.
