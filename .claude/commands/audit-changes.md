# /audit-changes — were these edits justified, and did they silently change behaviour?

The fourth instrument. `/check-docs` and `/check-consistency` audit **prose**; `/bug-hunt` audits
**code**. This one audits **changes to code** — a different object, with failure modes none of the
others can see.

Run it after any instrument's fix pass, or on request over any commit range.

## The question, and why it is not a defect hunt

> **Was each change proportionate to the defect it claims to fix, and did it silently alter behaviour
> for input that previously worked?**

An edit can be a *correct fix* and still be wrong to make: wider than the defect required, changing a
default, rejecting a workflow that used to be legitimate, breaking a contract the fix did not need to
touch. Neither the code nor the fix looks wrong in isolation, which is exactly why a hunt cannot find
it — a hunt reads code, and this reads the *diff*.

Measured over five rounds of automated defect fixing: it found a convenience method that threw on the
exact call its own docstring described; a forcing amplitude that lost its only bound when a numerical
floor was removed for a genuinely good reason; and a timestep ceiling that turned out to be a
statement about which **units** the caller had chosen. None of the three is a defect in code. All
three are defects in *edits*.

Its own measurement of the same change set, against the witness gate: the witnesses reported
`NEWLY BROKEN = 0` while two regressions were live and confirmed by hand. A witness exists only for a
defect the hunt *found*, so a regression introduced by a *fix* is invisible to it. That gap is this
tool.

## Running it

```bash
git diff <base>..HEAD -- src test docs > /tmp/changes.diff
git log --format="%h %s" <base>..HEAD          > /tmp/claims.txt     # optional
```
```
Workflow({ scriptPath: ".claude/commands/audit-changes/audit.js",
           args: { repo, diff: "/tmp/changes.diff", claims: "/tmp/claims.txt",
                   base: "<base>", head: "HEAD", kind: "both" } })
```
`kind` selects the lane set: `code`, `prose`, or `both`. A lane that cannot fire on the diff at hand
teaches the reader to discount `CLEAN` verdicts everywhere, so a prose-only sweep should not be run
through the numerics lens.

Then record the findings to `.claude/audit-changes/latest.json` and:

```bash
python3 .claude/commands/audit-changes/gate.py       # exit 0 = closed; non-zero says what is not
```

## Two structural rules, each from a demonstrated failure

**The norm is pinned at BASE, never at HEAD.** The docstrings and tests a lane would naturally treat
as the standard were themselves edited in the audited window — the audited party rewrote the
description of the thing being audited. A contract quietly amended to match changed behaviour *is*
the defect, not the baseline.

**`test/` is inside the audited material.** A fix that also edited the test that would have caught it,
or re-baselined a frozen ledger in the same commit, is the shape that certifies itself.

## The lens set, and why you should distrust yours

Ten code lanes and three prose lanes. The shape of that set was settled by **attacking it**, not by
taste: `attack-design.js` puts a logician, a philosopher, a red-teamer and a measurement specialist
against a lens list and demands *a concrete harmful edit that passes every lane*. Against an earlier
seven-lane version it produced **eleven fatal gaps**, and three of the four attackers converged
independently on the same one — **not a single lane ran anything**. An instrument founded on "the only
admissible evidence is a program that fails" had been given an audit made entirely of readers, so an
edit justified by a measurement written in a comment was certified by agents that read the comment.

The three lanes that closed fatal gaps:

| lane | the gap it closes |
|---|---|
| `executing` | **runs** every measurement claim the diff asserts, and calls every new entry point the way its own documentation says to |
| `under-rejection` | the strict dual of `over-rejection`: guards *removed* or weakened, which no lane owned — and which fail silently, where an over-strict guard fails loudly |
| `backend-portability` | bit-identical on `Array`, broken on a device — invisible here because every test runs on CPU |

`attack-design.js` is not specific to this tool. Any instrument's lane list should have to survive it.

## Why it has no adversarial verifier, unlike its siblings

The doc instruments carry `verify.js` because *"is this finding fixed?"* is a judgement and judgements
get quietly dropped. This tool already holds its mechanical anchor — the `executing` lane runs things
— and a second adversarial layer auditing the auditor is where the regress starts and the grounding
stops.

What replaces it is `gate.py`, which asks two questions a program can answer: has every **serious**
finding been *answered* (fixed, refused with a reason, or escalated — but not absent), and does the
audit still describe the **current** tree? It also reports any lane whose `candidates_found` exceeds
what it reported, because a reporting cap silently discarding half a lane's findings is otherwise
indistinguishable from a quiet lane.

## Discipline

- **Audit only.** No lane edits anything. It reports; the user disposes.
- **An unanswered serious finding is a dropped finding.** The gate refuses to close on one.
- **A `CLEAN` verdict must enumerate what was checked.** Clean with a vague `checked` list is
  indistinguishable from a lane that did nothing, and is read as such.
- **Never close a finding by declaring it "by design."** Answer it or escalate it.
