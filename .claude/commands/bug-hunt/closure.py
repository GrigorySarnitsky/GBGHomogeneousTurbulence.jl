#!/usr/bin/env python3
"""The /bug-hunt CLOSURE GATE — mechanical, mandatory, and it refuses to be optimistic.

`/check-docs` and `/check-consistency` both close a round with an audit that "is not optional" and a
loop that runs "until the numbers stop moving", on the stated ground that a fix pass introduces its
own defects. /bug-hunt shipped without either, and then MEASURED the exact failure that justifies
them: round 1's fixes introduced two regressions, and only the following run found them. A sequence
I follow by hand is not a gate; "I verified it" is the claim a gate exists to replace.

This script answers one question — MAY THIS ROUND BE CALLED CLOSED? — and answers it from the
filesystem and from programs that exit non-zero, never from a report.

  1. Every confirmed finding's witness PASSES.            (runs witnesses.jl)
  2. Every passing witness has been PROMOTED into test/regressions/.
     A fix whose witness never became a regression test protects nothing: the next refactor
     reintroduces the defect and the suite stays green.
  3. The full suite passes.                               (runs Pkg.test)
  4. A FOLLOW-UP HUNT has run since the last fix, and returned zero new confirmed findings.
     This is the loop, and it is the whole point. A round is not closed because its own findings
     are fixed; it is closed when hunting AGAIN, after those fixes, finds nothing new.

/bug-hunt gets a sharper convergence test than the doc instruments do. They stop when successive
rounds agree within noise, because a doc finding is a judgement and fifteen fresh readers always
produce some. Here a confirmed finding is a program that fails, so the honest terminator is EXACTLY
ZERO — and anything left over is either an open defect or a decision that belongs to the user.

  python3 .claude/commands/bug-hunt/closure.py            # audit the latest round
  python3 .claude/commands/bug-hunt/closure.py --record N confirmed=K escalated=M   # write a ledger entry
"""
import json, os, subprocess, sys, glob

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
WIT = os.path.join(ROOT, ".claude", "bug-hunt", "witnesses")
REG = os.path.join(ROOT, "test", "regressions")
LEDGER = os.path.join(ROOT, ".claude", "bug-hunt", "rounds.json")


def run(cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)


def record(argv):
    entry = {"round": int(argv[0])}
    for kv in argv[1:]:
        k, v = kv.split("=", 1)
        entry[k] = int(v) if v.isdigit() else v
    rounds = json.load(open(LEDGER)) if os.path.exists(LEDGER) else []
    rounds = [r for r in rounds if r["round"] != entry["round"]] + [entry]
    rounds.sort(key=lambda r: r["round"])
    json.dump(rounds, open(LEDGER, "w"), indent=1)
    print(f"recorded round {entry['round']}: {entry}")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--record":
        return record(sys.argv[2:])

    failures = []

    # ---- 1. witnesses pass ------------------------------------------------------------------
    names = sorted(f for f in os.listdir(WIT) if f.endswith(".jl")) if os.path.isdir(WIT) else []
    if not names:
        failures.append("no witnesses on disk — nothing was verified, and an empty audit is not a clean one")
    else:
        r = run(["julia", "--project", ".claude/commands/bug-hunt/witnesses.jl", "pass"])
        print(r.stdout[-1500:] if r.stdout else r.stderr[-800:])
        if r.returncode != 0:
            failures.append("witness gate FAILED — a confirmed defect is not fixed, or a witness is broken")

    # ---- 2. every witness promoted ----------------------------------------------------------
    promoted = set(os.listdir(REG)) if os.path.isdir(REG) else set()
    unpromoted = [n for n in names if n not in promoted]
    if unpromoted:
        failures.append("witnesses never promoted into test/regressions/ (the fix is unprotected): "
                        + ", ".join(unpromoted))

    # ---- 3. the suite ------------------------------------------------------------------------
    r = run(["julia", "--project", "-e", "using Pkg; Pkg.test()"])
    if r.returncode != 0:
        tail = (r.stdout or "")[-600:] + (r.stderr or "")[-600:]
        failures.append("the test suite FAILS:\n" + tail)

    # ---- 4. the loop -------------------------------------------------------------------------
    rounds = json.load(open(LEDGER)) if os.path.exists(LEDGER) else []
    if not rounds:
        failures.append("no round ledger — record each round with --record so the loop is auditable, "
                        "not remembered")
    else:
        last = rounds[-1]
        if "followup_confirmed" not in last:
            failures.append(
                f"round {last['round']} has NO FOLLOW-UP HUNT. This is the loop, and it is mandatory: "
                "a fix pass introduces its own defects — measured here, round 1's fixes introduced two "
                "regressions that only the next run found. Re-run the hunt, then "
                "--record {r} followup_confirmed=<n>.".format(r=last["round"]))
        elif last["followup_confirmed"] != 0:
            n = last["followup_confirmed"]
            failures.append(f"the follow-up hunt confirmed {n} new finding(s) — the round is NOT closed. "
                            "Fix them and hunt again; a confirmed finding here is a failing program, so "
                            "the terminator is exactly zero, not 'within noise'.")

    print("\n" + "=" * 72)
    if failures:
        print(f"ROUND NOT CLOSED — {len(failures)} blocker(s):\n")
        for f in failures:
            print("  !! " + f + "\n")
        print("Anything you cannot close is either an open defect or a DECISION FOR THE USER.")
        print("Escalate the latter by name; do not close a round by reclassifying a defect as a decision.")
        sys.exit(1)
    print("ROUND CLOSED. Every witness passes and is promoted, the suite is green, and a follow-up")
    print("hunt after the fixes confirmed nothing new.")
    sys.exit(0)


main()
