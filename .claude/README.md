# `.claude/` — local working artifacts (GBGIsotropicTurbulence)

Untracked working notes (**never committed** — only the instrument files under `.claude/commands/`
are tracked). This index says what is **live** versus **settled**, so a future session does not act
on a discharged pile. **Re-verified against the tree on 2026-08-20**; the previous version of this
file described the July rounds as live and was wrong on nearly every line.

## Settled — do NOT act on these

| Pile | Verdict |
|---|---|
| `architecture-review-pile.md` | **CLOSED 2026-08-20.** All 12 items re-verified against the current tree, individually, with evidence recorded in the file's own header table. #11 is deferred *correctly* (it bites only when `StochasticOU` is de-archived). #9's premise was **false** and is recorded as refuted. |
| `docstring-review-pile.md` | Worked off (round 1, commits `e56583a`, `2e12afc`). |
| `docstring-review-round2.md` | Worked off (`fd93722`, `1039f3b`, + the InterLinks commit). |
| `docstring-review-round3.md` | Worked off (`a3a523c`…`08c2c4d`). Its own header still says LIVE — that header is stale; sampled items (the InterLinks references page) are landed. |
| `doc-reading-pile-2026-08-11.md` | Implemented 2026-08-14. |
| `doc-reading-pile-2026-08-15.md` | **Findings** worked off (sampled: #5 `recommended_cfl`, #22 `max_speed` — both fixed; the `plain-sense` hat exists). **But see the live task below.** |
| `panel-reaudit.md` | Historical record of the round-1 fix-pass audit. |
| `doc-review/`, `doc-review-prev/`, `doc-review-round1/` | Regenerated every `/check-consistency` run. |
| `pf-api-survey-2026-08-05.md`, `observables-cache-notes.md` | Reference notes, not task lists. |
| `doc-review-adjudicated.md` | **Tracked and live** — the do-not-re-flag list injected into every hat. |

## DISCHARGED 2026-08-22 — the panel rubric-gap re-audit

Record: `panel-rubric-reaudit-2026-08-22.md` (untracked). **The panel went 15 hats → 21.** Four lanes
came from the banked candidates (`existence-auditor`, `quantifier-auditor`, `fossil-and-drift`,
`pf-parity`); two were NOT on the list — `free-reader-a` / `free-reader-b`, which run **first**,
because the measurement below says the fix is not only sharper lenses but readers carrying no rubric
at all. `plain-sense` was re-read against its five findings and needed no change. The banked
`/check-docs` scans were already built (`abutting_spans.py`, `doi_crosscheck.py`, `xlink.jl`). All six
additions run on the economy model — the anchor criterion is about a *rubric* whose false negatives
have no downstream verifier, and a free reader has no rubric to fail.

**Not yet validated:** the panel has not been RUN since the change. The next `/check-consistency` is
the real test of whether the six lanes produce the findings they were built for.

## Superseded — the task as originally written

**The panel rubric-gap re-audit** (`doc-reading-pile-2026-08-15.md`, § END-OF-ROUND TASK, user
2026-08-17). Every finding the user's own read-through produced that **no hat produced** is a rubric
gap; for each, either sharpen a persona, declare the class out of panel scope, or add a lane. Banked
candidates: an **existence auditor** (no hat asks whether a public form *should exist*), a
**diff-aware / fossil lane** (the panel is history-blind, so scaffolding orphaned by a rename is
invisible), a **false-quantifier check**, **cross-package parity with PF**, and two `/check-docs`
scans. Also re-check cost-mode assignment after any persona change.

> **2026-08-20 note.** `/bug-hunt` hit exactly this class from the other direction and it is now
> measured: eight class lanes reported `complete: true` over their own blind spot, and two
> *unconstrained* lanes then found nine defects at a third the cost — four of them regressions from
> the preceding 48 hours. The doc panel still has no such lane. That is the strongest argument for
> doing this task, and it suggests the answer is not only "sharpen the personas" but "add free
> readers", since the measured failure was the rubric itself, not the reading.
