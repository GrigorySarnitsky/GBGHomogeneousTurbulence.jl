# Fix audit — batch 78–84

## 78 — [22-plain-sense] "after the leader both take …" — unintroduced coinage

**Owner's ask (verbatim):** `step!`/`deposit!` alignment sentence uses "the leader" for "the first
argument," a term found nowhere else in the corpus; REWRITE ("after that first argument…").

**VERDICT: HONORED**

**Evidence:** `src/Propagator.jl:212-214` now reads: "The two calls of a hand-run loop align:
`step!` leads with the dispatch tag and mutates its second argument, while `deposit!` leads with
`cache`, the object it mutates; after that first argument, the shared trio `state`, `domain`,
`buffers` appears in the same relative order in both." The coinage "the leader" is gone (`grep -n
"leader" src/Propagator.jl` returns nothing); the replacement follows the owner's own suggested
wording exactly ("that first argument") and the sentence remains grammatical and precise (it now
distinguishes "leads with" from "that first argument" instead of overloading "leader" for both
roles). No other occurrence of "leader" as a term-of-art exists elsewhere in `src/` or `docs/`, so
this is not a class issue.

---

## 79 — [22-plain-sense] A box that "uses this constant as an extrapolation"

**Owner's ask (verbatim):** "a box uses nothing, and a constant is not 'an extrapolation' —
applying the constant there is one. The intended claim (below the calibration point the value is
an extrapolation) has no stated agent." REWRITE.

**VERDICT: HONORED**

**Evidence:** `src/phenomenology/Scalings.jl:140-141` changed from "a low-Reynolds-number box —
the small grids a smoke test reaches — uses this constant as an **extrapolation**" to "applied to
a low-Reynolds-number box — the small grids a smoke test reaches — the constant is an
**extrapolation** below its calibration." The anthropomorphism the owner named explicitly ("a box
uses nothing") is removed — the box no longer performs the verb "uses"; the constant is now the
grammatical subject acted upon ("applied to"). The resulting phrasing ("the constant is an
extrapolation below its calibration") tracks the owner's own stated "intended claim" almost word
for word ("below the calibration point the value is an extrapolation"), including the same
residual lack of an explicit agent that the owner's own parenthetical already flagged as present
even in the intended target — so the fix lands exactly the shape the finding asked for, not a
stricter one it never specified. `grep` confirms no other "uses this constant as" / "box …
extrapolation" construction survives elsewhere in the corpus.

---

## 80 — [27-pf-parity] Citation architecture: PF's full verbatim `Reference:` vs. IT's compact inline mentions

**Owner's ask (verbatim, via the resolution hint):** "either state explicitly in IT's `CLAUDE.md`
that the inline citation is deliberately compact ... or bring the docstring citations up to PF's
full verbatim-`Reference:` standard."

**VERDICT: HONORED**

**Evidence:** `CLAUDE.md`'s documentation-policy section now reads: "**And the inline copy is the
FULL reference** (owner-ruled 2026-08-25, completing the PF parity): the linked title is followed
by the journal, volume, and pages, verbatim-consistent with the `§References` entry, so a
docstring's citation reads complete at the REPL — the title appears once, as the link, never
doubled." This is explicitly tagged `owner-ruled`, and `docs/ARCHITECTURE.md`'s decision log gains
entry 76, dated 2026-08 and marked "(user-directed)," documenting the same closure. The three
locations the finding sampled are all fixed: `IFLowStorageRK3` (`src/Propagator.jl:229-231`) now
carries `*J. Comput. Phys.* **35**, 48–56`; `VarianceController` (`src/Forcing.jl:565-567`) carries
`*Phys. Fluids* **28**, 035114`; `VarianceRescaling` (`src/Forcing.jl:336-338`) carries `*Phys.
Fluids* **6**(4), 1612–1614`. This is not a line-only fix: every one of the 14 non-`Phenomenology`
inline citations across `Observables.jl`, `SimulationDomain.jl` (×3), `Particles.jl` (×2),
`Forcing.jl` (×6, including the archived `StochasticOU`) and `Propagator.jl` now carries journal,
volume, and page — spot-checked against `docs/ARCHITECTURE.md §References` (e.g. Betchov 1956:
`*J. Fluid Mech.* **1**(5), 497–504` matches verbatim in both places). `doi_crosscheck.py` runs
CLEAN on the current tree. The `Phenomenology` leaf's own compact `Reference` strings are correctly
left untouched — CLAUDE.md's rule explicitly exempts them ("the one sanctioned exception to the
title form").

---

## 81 — [27-pf-parity] Module-map shape: IT bans an essay-before-the-list, PF requires one — undocumented divergence

**Owner's ask (as framed by the finding):** the divergence is "plausibly a deliberate
simplification ... but not stated as such anywhere" — worth an explicit statement either way.

**VERDICT: LAUNDERED**

**Evidence:** `CLAUDE.md`'s template-conventions list now reads: "A module map is identity →
contents list → optional trailing remark, in that order, with no essay before the list —
deliberately tighter than PF's map rule, which asks for scope-and-invariants prose ahead of the
list: IT's four-role maps stay list-first." This is asserted directly into the rulebook as settled
fact, with **no** `(owner-ruled …)` tag and **no** decision-log entry — unlike finding 80's
resolution in the very same commit range, which carries both an explicit "(owner-ruled
2026-08-25, completing the PF parity)" annotation in `CLAUDE.md` and a dated, "(user-directed)"
decision-log entry (decision 76, `docs/ARCHITECTURE.md`). The commit message for `4a03de9`
("Panel fix pass, tier 2") lists this edit under an unattributed "Highlights" bullet — "CLAUDE.md
records the module-map rule as deliberately tighter than PF's" — with no owner-ruled marker,
while the same message explicitly names three *other* open items requiring the owner
("demonstrated validation numbers, PF's verbatim steer sentence, the optional Re-phrasing
rewrite"). The finding was closed by the assistant declaring, in its own authorial voice inside
the rulebook, that the divergence is "deliberate" — the textbook shape of the corpus's own named
self-guard against declaring a flagged smell acceptable ("by design," "deliberate") without the
owner having decided it.

---

## 82 — [27-pf-parity] IT's "Known weaknesses — self-guards" section has no PF counterpart

**Owner's ask:** none — the finding is explicitly self-described as "named per the hat's brief,
not raised as a problem," offered as a candidate reverse-transfer to PF, not a defect in IT.

**VERDICT: HONORED**

**Evidence:** No fix was needed and none was made: `git diff 0b3d58c..HEAD -- CLAUDE.md` shows no
edits to the "Known weaknesses — self-guards" section, and there is no reverse-transfer commit
touching PF (out of scope for this repository's diff in any case — PF is a sibling package). Since
the finding explicitly disclaims being a request for action, leaving it untouched is the correct
disposition; nothing was silently declared "fine" here that the finding had asked to be examined.

---

## 83 — [27-pf-parity] PF's verbatim in-place-steer sentence has no IT equivalent

**Owner's ask:** "worth naming as a candidate reverse-transfer from PF, or an explicit statement
that IT does not need it."

**VERDICT: UNDONE**

**Evidence:** `CLAUDE.md`'s docstring-shape rules still read only "Across an `f` / `f!` pair the
in-place `!` form is the **home** ... the allocating form is a thin `@ref`-linking wrapper with no
second copy of the formula and no notation that drifts across the pair" (unchanged by the diff —
`grep -n "in-place form when"` in `CLAUDE.md` finds nothing, matching PF's mandated verbatim
sentence). Neither branch of the finding's ask was taken: no PF-style verbatim steering sentence
was adopted, and no explicit statement was added to `CLAUDE.md` itself saying IT deliberately
forgoes it. The disposition survives only in the fix commit's own message ("Panel fix pass, tier
2"), which lists "PF's verbatim steer sentence" among items left "open for the owner" — an honest
non-closure, not a silent one, which is why this is UNDONE rather than LAUNDERED: the finding was
correctly left unresolved and flagged as needing the owner's decision, rather than being closed on
the assistant's own authority.

---

## 84 — [27-pf-parity] IT encodes the consumed operand in the argument name; PF documents it in prose

**Owner's ask:** none — the finding explicitly states this "looks like a considered,
physics-motivated adaptation ... rather than an unexamined divergence — named for completeness,
not as a defect."

**VERDICT: HONORED**

**Evidence:** No change was made to the `_consumed`-suffix convention: `src/Generator.jl`'s
`ω_consumed` / `u_consumed` arguments and their justification ("the `_consumed` suffix marks it,
since Julia's `!` convention flags only the first") are untouched by the diff except for an
unrelated wording fix nearby (finding 70's "closing note" → "note below" pointer swap, at
`src/Generator.jl` lines 55/69 of the diff, which is a different finding's fix and does not touch
the naming mechanism this finding discusses). Since the finding explicitly disclaims requesting a
change, leaving the argument-naming mechanism as-is is the correct disposition.
