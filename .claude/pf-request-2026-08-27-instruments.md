# Request from GBGIsotropicTurbulence (IT) — 2026-08-27: three instrument changes to port

Not an API request. Three changes to the *instruments* have landed in IT since the shared
`/check-consistency` was written, each driven by a measurement rather than by taste. IT and PF run
the same panel design, so the same failure modes apply. **What I am proposing is that PF adopt the
mechanisms; I am NOT proposing that PF adopt IT's numbers** — two of the three are calibrations that
each package must measure for itself, and copying IT's answer would reproduce the exact error the
first change exists to correct.

What PF has today, from the clone at `inspiration/GBGPeriodicFields` (HEAD 2026-08-24):
`.claude/commands/check-consistency/` holding `panel.js` and `consolidate.py`, **12 hats, all of
which always run** (no `core` key anywhere), and `check-consistency.md` whose discipline section asks
for closure to be reported "per hat and per finding number" — with nothing that checks it. No
`verify.js`, no `verify-fixes.js`, no code instrument, no `test/regressions/`.

---

## 1. A measured hat profile, so the panel is built upwards

**The problem.** A panel grows monotonically. Every hat looks reasonable in isolation, cutting one
means defending its removal, and so IT's reached 23. Nobody had measured what the marginal hats
were worth.

**The measurement** (2026-08-22, IT): the full panel and a six-hat subset ran on the **identical
manuscript**. Full panel **5.94 M tokens, 184 findings**; six-hat **1.64 M, 58**. The seventeen extra
hats bought **14 unique blocker-or-major findings** for their extra 4.3 M tokens — about **307 k
tokens per unique significant finding against the small panel's 57 k** — and **eight of the seventeen
produced no unique significant finding at all**.

**The change.** A `core` flag on each hat and a `PROFILE` selector, defaulting to `core`. The rule
that matters is not the list but its direction: **the profile is built UPWARDS from a small measured
set, never cut down from the large one.** Cutting means defending each incumbent, which is how it got
to 23. A hat enters `core` only by producing unique significant findings in a measured run.

**Admission needs more than one run.** The same six hats reproduced only **72%** of their own
findings across the two arms, so a single run's "uniqueness" sits inside the noise. Dormant hats stay
defined and runnable (`profile: "full"`, or named explicitly); they re-enter by repeating, not by
argument. Dormancy reads "insufficient evidence", never "condemned" — and a persistent zero across
runs becomes a deletion candidate on real evidence rather than on one sample.

**For PF: port the mechanism, then run your own paired arm.** IT's `core` membership is a fact about
IT's manuscript and IT's defect population. PF's hats differ, PF's prose differs, and PF's highest
yield may well sit in a hat IT retired. The honest port is `profile` plus the admission rule, with
PF's first `profile: "full"` round doubling as the measurement.

---

## 2. Fix verification, and why self-reported closure is not closure

**This is the one I would port first**, because PF's current discipline is exactly the configuration
the measurement condemns: the panel bans laundering, asks for per-finding closure, and then trusts
the fixer's own account of whether the class was swept.

**The measurement** (IT, 2026-08-17): in one round of `verify-fixes.js`, **eleven of thirteen
deficiencies were `LINE-ONLY`** — the flagged site fixed, the class still alive on surfaces the
finding's own text had already named. Not carelessness: the rule "a flagged instance is a sample of a
class" was written down, known, quoted, and broken anyway. The lesson is not a firmer statement of
the rule. It is that **stating it does not work and measuring it does.**

**The change: two verifiers with deliberately opposite information.**

- `verify.js` audits a **STATE** and is **blind to the diff**: it re-reads the current tree against
  the banked findings and asks whether each defect is present, with no knowledge of what was edited.
- `verify-fixes.js` audits an **ACT** and **sees the diff**: it judges the edits themselves, in
  categories `HONORED` / `LINE-ONLY` / `NEW-DEFECT` / `SCOPE-CREEP` / `UNDONE` / `LAUNDERED`, with
  `HONORED` the only passing verdict.

Two properties are load-bearing:

- **Both default to the unfavourable verdict**, so a lazy or truncated lane fails safe rather than
  certifying clean.
- **A zero count for a hat means a DEAD AGENT, not a clean hat** — normalize to percentages and check
  liveness, or a crashed lane reads as success.

**Loop to a plateau, and do not stop at the first good round.** IT's honored-rate across ten runs
went 43 → 69 → 76 → 95 → 93 → 90%. Round 2 looked like progress and concealed the eleven
`LINE-ONLY`s. The stopping rule is three rounds flat within noise.

**For PF:** the shape ports unchanged; only the finding schema is package-specific. PF has the
harder version of this problem, not the easier one — a field library's defects are more often
*classes* (a normalization convention, a docstring pattern repeated across an operator family) than
one-off sentences, and a class fix is precisely what self-report gets wrong.

---

## 3. `/bug-hunt` — a code instrument, new since the shared design

**The gap.** `/check-docs` and `/check-consistency` both audit **prose**. Neither asks whether the
code is *correct*. A docstring can be flawless about a function that returns the wrong number and
both instruments pass it.

**The one design rule:**

> A static claim about code is a hypothesis. The only admissible evidence is a program that FAILS.

This is a correction for a measured failure mode, not a preference. An agent reading code and
reporting what "looks wrong" produces fluent, confident, unfalsifiable prose. In a documentation
instrument that costs a wasted read; here it costs **a fix pass on working code**, which is strictly
worse than the imagined bug — the tree gets edited, the suite still passes, and afterwards nobody can
tell whether anything was ever wrong.

**So the hunt is static and the confirmation is dynamic.** Every candidate is reduced to a
**witness**: a self-contained `@testset` asserting the CORRECT behaviour, therefore observed to FAIL
on the current tree.

- Witness **passes** → not a bug. Discarded, however good the argument.
- **No witness can be written** → not actionable. Reported as a latent hazard, not fixed.
- Witness **fails** → that *is* the finding, and unchanged it is the regression test the fix must
  flip, promoted into `test/` when the fix lands.

**Free lanes beat class lanes.** IT's measurement: unconstrained readers outperformed eight
defect-class lanes at **a third of the cost**, and found four regressions IT had introduced itself. A
class list is a hypothesis the instrument then reports `complete` over — which is a false comfort.

**For PF this should work better than it does for IT, not worse.** PF's operations carry exact
mathematical contracts — adjointness, Parseval, normalization factors, kernel composition — so an
oracle is usually available and a witness is usually writable. PF already has `test/adjointness.jl`,
`test/contracts.jl` and `test/exhaustive/`; what is missing is `test/regressions/` and the discipline
that a defect claim is inadmissible without a failing witness.

---

## What I am not asking for

Not IT's `core` list, not IT's finding schema, and not the supporting scripts copied verbatim —
`hunt.js`, `witnesses.jl`, `dismissals.js`, `closure.py`, `finished.py` are shaped around IT's pile
layout and its Julia test conventions. Read them as a reference implementation if useful
(`.claude/commands/bug-hunt/` and `.claude/commands/check-consistency/` in the IT tree); the
mechanisms are the request, the code is not.

I am also not claiming IT's instruments are finished. `verify.js` had never been run at all until
recently, the dormant-hat question is settled only by passive accumulation, and the profile rule has
one paired measurement behind it, not several. If PF's own measurement disagrees with IT's, PF's
measurement wins for PF — that is the whole point of the first change.
