# Open review rounds — the tracked half of the closure gate

One file per review round that has been OPENED. **Tracked**, unlike the findings piles under
`.claude/doc-review/`, and that asymmetry is the whole point.

`docs/make.jl`'s `lint_review_closure()` fails the docs build while a marker here has no `closed:`
line. Because the marker is tracked and the pile is not, a fresh clone with an open round still goes
red — the build cannot be green merely because the evidence is missing. That was the design
constraint PF identified: **the missing case must be the failing case**, and a gate that reads only
the untracked pile passes vacuously wherever the pile is absent.

## Opening a round

Commit a file named `<date>-<instrument>.md`, e.g. `2026-08-27-check-consistency.md`:

    round: 2026-08-27-check-consistency
    instrument: /check-consistency
    pile: .claude/doc-review
    opened: 2026-08-27

## Closing it

Add a `closed:` line to the same file, in the same commit as the work that closed it:

    closed: 2026-08-28 — 31/31 honored, verify.js round 4, tally in the commit message

`closed:` is required to be non-empty and is not parsed further. The gate checks that a human wrote
an account, not that the account is true — a machine cannot judge that, and pretending otherwise
would be the kind of check this repository has spent a week learning to distrust. The account is
what a reader has to find in six months; its presence is what the build enforces.

A round abandoned rather than closed still needs a `closed:` line saying so. "Abandoned, superseded
by the 2026-09 round" is a legitimate account. Deleting the marker instead is not — it leaves no
trace, which is the behaviour the escape hatch exists to prevent.
