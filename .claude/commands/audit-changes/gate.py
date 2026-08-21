#!/usr/bin/env python3
"""THE DISPOSITION GATE — has this audit been answered, and does it still describe the tree?

The audit's findings are judgements, and judgements get quietly dropped: that is the whole reason the
sibling instruments carry an adversarial verifier. This tool does NOT carry one, deliberately — it
already contains its mechanical anchor (the `executing` lane runs things), and a second adversarial
layer auditing the auditor is where the regress begins and the grounding ends.

What replaces it is this gate, which asks two questions a program can answer:

  1. Has every SERIOUS finding been answered? Not fixed — ANSWERED. A disposition may be "fixed",
     "refused, because ...", or "escalated to the user", but it may not be absent. An absent
     disposition is a dropped finding, and dropping findings is the failure mode the sibling
     verifiers were built to catch.

  2. Does the audit still describe the current tree? An audit that read an older commit certifies
     nothing about the code as it stands. This is the check that makes "we audited it" mean
     something a week later.

  python3 gate.py [path/to/audit.json]     default: .claude/audit-changes/latest.json
"""
import json, os, subprocess, sys

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                      capture_output=True, text=True).stdout.strip()
DEFAULT = os.path.join(ROOT, ".claude", "audit-changes", "latest.json")


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    if not os.path.exists(path):
        print(f"NO AUDIT ON RECORD at {path}.")
        print("An unaudited change set is not a clean one — run the audit before claiming it is.")
        sys.exit(2)

    audit = json.load(open(path))
    problems = []

    # ---- 1. staleness, against the paths the audit says it covered -------------------------------
    covered = audit.get("covered_paths") or ["src"]
    r = subprocess.run(["git", "log", "-1", "--format=%H", "--"] + covered,
                       cwd=ROOT, capture_output=True, text=True)
    current = r.stdout.strip()
    if not current:
        problems.append(f"could not determine the last commit touching {covered}")
    elif audit.get("head") != current:
        problems.append(
            f"STALE: the audit read {str(audit.get('head'))[:9]}, the tree is now at {current[:9]}. "
            f"Re-audit — an audit of an older tree certifies nothing about the code as it stands.")

    # ---- 2. dispositions ------------------------------------------------------------------------
    findings = audit.get("findings", [])
    if not findings and audit.get("verdict_all_clean") is not True:
        problems.append("the audit records no findings and does not assert it was clean — "
                        "an empty audit is not a clean one")
    serious = [f for f in findings if f.get("severity") == "serious"]
    undecided = [f for f in serious if not (f.get("disposition") or "").strip()]
    if undecided:
        problems.append(f"{len(undecided)} of {len(serious)} SERIOUS finding(s) unanswered:")
        for f in undecided[:8]:
            problems.append(f"      - {f.get('title', '?')[:88]}")

    # ---- 3. a capped lane is a lane hiding findings ----------------------------------------------
    capped = [l for l in audit.get("lanes", [])
              if l.get("candidates_found", 0) > len(l.get("findings", []))]
    if capped:
        detail = ", ".join(f"{l['lane']} ({l['candidates_found']}→{len(l.get('findings', []))})"
                           for l in capped)
        problems.append("NOT FATAL, BUT KNOW IT: lanes reported fewer findings than they found — "
                        + detail + ". The reporting cap is hiding the remainder; re-run those lanes "
                        "narrowed if the topic matters.")

    print()
    if problems:
        fatal = [p for p in problems if not p.startswith("NOT FATAL")]
        for p in problems:
            print(("  !! " if not p.startswith("      ") else "") + p)
        print()
        if fatal:
            print(f"AUDIT NOT CLOSED — {len(fatal)} blocker(s).")
            sys.exit(1)
    n = len(serious)
    print(f"AUDIT CLOSED — all {n} serious finding(s) answered, and it describes the current tree.")
    sys.exit(0)


main()
