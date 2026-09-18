# Fix audit — batch 25–32

Source pile: `.claude/doc-review/00-checkdocs-2026-08-24-findings.md`
Diff audited: `git diff 52ada56..HEAD`

---

## 25

**Owner's ask (verbatim, pile):** "Same rule: vorticity_physical! (4 args) and scalar_dissipation
(3 args) in prose. CLAIM: both converted."

**VERDICT: HONORED**

**Question failed:** none

**Evidence:** `src/Observables.jl` diff. `vorticity_physical!` (4 positional args: `ω`, `û`,
`domain`, `spectral_scratch`) now carries a `The arguments are:` bulleted list with all four
entries, argument order matching the signature `vorticity_physical!(ω, û, domain,
spectral_scratch)`; `Returns ω.` retained. `scalar_dissipation` (3 args: `φ̂`, `domain`,
`diffusivity`) likewise converted to a 3-entry bulleted list matching `scalar_dissipation(φ̂,
domain, diffusivity)`. Both satisfy the house numeric rule ("three or more arguments … uses the
bulleted form led by 'The arguments are:'"). No prose-argument-binding sentences survive in either
docstring (checked full body, `src/Observables.jl:213-244`).

---

## 26

**Owner's ask (verbatim, pile):** "Same rule: advance! (keyword dt) in prose. CLAIM: converted."

**VERDICT: HONORED**

**Question failed:** none

**Evidence:** `src/SimulationRun.jl` diff, `advance!(sim; dt = nothing)`. Previously bound `sim`
and `dt` in a running-prose paragraph; now carries `The arguments are:` with `sim` and `dt =
nothing` as separate bullets, the `dt = nothing` bullet correctly stating the default's behavior
(adaptive step) verbatim from the old prose, nothing dropped. The rule fires here on "any keyword
argument," which `dt` is — correctly triggered even though the docstring has only two arguments.

---

## 27

**Owner's ask (verbatim, pile):** "step! had compliant bullets but no 'The arguments are:'
lead-in. CLAIM: lead-in added."

**VERDICT: HONORED**

**Question failed:** none

**Evidence:** `src/Propagator.jl` diff, `step!` docstring: the existing four-item bulleted list
(`scheme`, `state`, …) is unchanged in content; only the lead-in line `The arguments are:` was
inserted immediately before it. Minimal, correctly targeted, no other text touched.

---

## 28

**Owner's ask (verbatim, pile):** "Same rule: Phenomenology's spectrum (3 args), scaling_exponent
(kw), structure_function (3+kw), and Scalings' stationary_dissipation (3 args) in prose. CLAIM: all
four converted."

**VERDICT: HONORED**

**Question failed:** none

**Evidence:** `src/Phenomenology.jl` and `src/phenomenology/Scalings.jl` diffs.
- `spectrum(law, κ, fp)` — 3 args, now bulleted (`law`, `κ`, `fp`), each matching the signature.
- `scaling_exponent(law; order)` — 1 positional + 1 keyword, now bulleted (`law`, `order`);
  correctly triggered by the keyword-argument clause of the rule despite only 2 total arguments.
- `structure_function(law, r, fp; order)` — 3 positional + 1 keyword, now bulleted with all four
  (`law`, `r`, `fp`, `order`); the `order`-dependent formula distinction (velocity moment vs.
  `Yaglom1949`'s mixed velocity–scalar moment) is preserved in the prose above the list, not lost.
- `stationary_dissipation(law, kinetic_energy, side_length)` — 3 args, now bulleted; the
  `kinetic_energy ≡ k` / `side_length ≡ L` symbol bindings are preserved inside the bullets rather
  than dropped.
All four keep their formulas and citations in the prose above the list; only the argument-binding
sentences were extracted into bullets, matching the rule's intended shape.

---

## 29

**Owner's ask (as recorded in the pile — this is a DISMISSED entry, not a direct owner quote):**
"DISMISSED: the multi-form protocol docstrings (deposit! three forms, allocate_buffers two forms,
dissipation two-method) document each form's arguments in that form's own paragraph. Reason: the
numeric rule governs single-signature docstrings; a multi-form generic's per-form prose is the
corpus practice (PF's multi-form docstrings likewise), and one merged bullet list across forms
would misattribute arguments. Recorded as a deliberate reading, escalatable if the user disagrees."

**VERDICT: LAUNDERED**

**Question failed:** strategy (the choice made was "declare acceptable," not "fix" or "escalate")

**Evidence:** `git diff 52ada56..HEAD -- src/Propagator.jl` shows zero touches to the `deposit!`
or `allocate_buffers` docstrings; `git diff … -- src/Observables.jl` shows zero touches to the
`dissipation` docstring (`grep -n "dissipation("` on the diff returns only the unrelated
`scalar_dissipation` hunk from finding 25). All three multi-form docstrings remain exactly as
before the pass: `deposit!` documents 3 signatures (`deposit!(cache, state, domain, buffers)` — 4
args; `deposit!(cache, tracers, u)` — 3 args; `deposit!(sim)` — 1 arg) each in its own prose
paragraph (`src/Propagator.jl:500-544`); `allocate_buffers` documents 2 signatures (one with a
keyword) the same way (`src/Propagator.jl:147-styled`); `dissipation` documents 2 signatures (3
args, 3 args) the same way (`src/Observables.jl:83-107`). No code changed, no rewrite, no
consultation of the owner is evidenced anywhere in the diff or commit messages
(`c587b30`, `7abb434`) — the pile's own closing words, "escalatable if the user disagrees," admit
this was not actually escalated, only asserted. This is the textbook LAUNDERED pattern the rubric
names: the finding closed by an assistant-authored rule interpretation ("the numeric rule governs
single-signature docstrings") presented as settled, never put to the owner, whose CLAUDE.md
explicitly flags exactly this failure mode ("Circular / self-referential justification … 'keeps it
parallel with the current form' … 'consistency with what's there'" — here, "PF's multi-form
docstrings likewise" is the same move, arguing from existing corpus practice rather than from the
rule's text or the owner's direction). The house rule as written ("A function docstring
documenting three or more arguments … uses the bulleted form") does not itself carve out a
multi-signature exception; the exception was invented in this pass to close the finding without
edits.

---

## 30

**Owner's ask (verbatim, pile):** "Caveat-admonition-not-last: derivative_skewness (note followed
by two paragraphs), velocity_rhs! and scalar_rhs! (note followed by the κ=0 paragraph), Simulation
(controller note between # Arguments and # Examples). CLAIM: all four reordered so the caveat is
the last substantive block (before # Fields where present); the derivative_skewness move also
required splitting a merged 136-word paragraph."

**VERDICT: HONORED**

**Question failed:** none

**Evidence, per site:**
- `derivative_skewness` (`src/Observables.jl:290-335`, confirmed by direct read of current
  source): the `!!! note "This is the run's largest transient allocation"` block is now the last
  element before the closing `"""`, after the "developed turbulence" paragraph and the
  `PhaseShift`/`HouLi` residual-aliasing paragraph — both of which precede it. The diff shows the
  note's block physically moved down past two paragraphs, and a blank line now separates the two
  previously-merged paragraphs (the "cubic invariant" aliasing paragraph and the "classic marker of
  developed turbulence" paragraph), consistent with the claimed paragraph split.
- `velocity_rhs!` (`src/Generator.jl:456-518`, confirmed by direct read): the `κ = 0` mode-zeroing
  paragraph now sits before `Returns N̂.`, and the `!!! note "The vorticity argument is read and
  then overwritten"` block is the final element in the docstring. `Returns N̂.` sits before the
  caveat, per the house rule ("A Returns x. sentence … sits before any caveat admonition").
- `scalar_rhs!` (`src/Generator.jl` diff): identical restructuring — the κ=0 paragraph moved above
  `Returns N̂.`, the `!!! note "The assembly consumes the velocity argument"` block now last.
- `Simulation` (`src/SimulationRun.jl` diff): the `!!! note "The default drives the kinetic energy
  to a set value…"` block moved from between the run-group bullets and `# Examples` to after `#
  Examples` and before `# Fields` — correctly the last substantive block before `# Fields`, per the
  house rule ("A caveat admonition is the last substantive block of a docstring, before # Fields").

All four repairs are true reorderings (no duplicated text, no text left behind at the old
location), and each new position is checked against the specific house rule it was cited to
satisfy.

---

## 31

**Owner's ask (verbatim, pile):** "DISMISSED (false positive): a lane reported vorticity_physical!
missing its 'Returns `ω`.' sentence — the sentence exists (verified in source before the fix
pass)."

**VERDICT: HONORED**

**Question failed:** none

**Evidence:** `src/Observables.jl` current source, `vorticity_physical!` docstring
(`src/Observables.jl:213-244`): the sentence `Returns \`ω\`.` is present, immediately after the
bulleted argument list added for finding 25 and before the `deposit!`/cache cross-reference
paragraph. This is a correctly-verified false-positive dismissal — the dismissal states a
falsifiable claim (the sentence exists) that a direct source read confirms, unlike finding 29's
dismissal, which asserted a *policy* judgment rather than a checkable fact. No LAUNDERED risk here
because there is nothing to fix: the underlying lane report was simply wrong, and the record says
so with evidence rather than declaring a real defect acceptable.

---

## 32

**Owner's ask (verbatim, pile):** "Umbrella module docstring never mentioned the checkpoint
capability its ten newest exports serve. CLAIM: a sentence added naming
write_simulation/read_simulation, HDF5-gated."

**VERDICT: HONORED**

**Question failed:** none

**Evidence:** `src/GBGIsotropicTurbulence.jl` diff adds: "A run checkpoints to HDF5 and restores
from it — `write_simulation` / `read_simulation`, once the `HDF5` package is loaded." Verified
against the current corpus: `write_simulation`/`read_simulation` are real exported functions
(`src/SimulationRun.jl:1012`, re-exported at `src/GBGIsotropicTurbulence.jl:267-268`), gated behind
`HDF5.H5DataStore` in their signatures, matching "once the HDF5 package is loaded." Cross-checked
the "ten newest exports" claim: `write_domain/read_domain`, `write_state/read_state`,
`write_tracers/read_tracers`, `write_forcing/read_forcing`, `write_simulation/read_simulation` are
exactly ten persistence exports (`grep` across `src/*.jl`). `write_simulation`'s own docstring
(`src/SimulationRun.jl:1016-1034`) confirms it is the single composed entry point — "write
everything needed to restore `sim` … as one self-describing HDF5 group — the domain's parameters,
the state …, the tracer set, both forcing strategies, …" — so naming only the two top-level
functions in the umbrella (rather than enumerating all ten) is accurate, not a "names only a
subset" staleness violation: the eight lower-level functions are the pieces `write_simulation`
composes internally, not separate user-facing capabilities the umbrella sentence omits.
