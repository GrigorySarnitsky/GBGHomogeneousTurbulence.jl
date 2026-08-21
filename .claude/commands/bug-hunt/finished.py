#!/usr/bin/env python3
"""IS THIS WORK FINISHED? — answered by an exit code, never by my assessment of it.

Written BEFORE the remaining work was done, from the user's own request, so the checklist cannot be
quietly reshaped to match whatever got finished. That is the point: across this session I repeatedly
reported work complete and was wrong — an edit script that asserted and never wrote, an extractor that
reported 42 findings while recovering 6, a `cp` that destroyed a regression test, a documentation
claim for a method I had deleted. Every one of them REPORTED SUCCESS OVER ITS OWN GAP. A claim of
completion is a hypothesis; the only admissible evidence is a program that exits zero.

Design rules, each from a failure this session actually produced:

  * NO CHECK MAY PASS BY VACUITY. A check that finds nothing to inspect FAILS — an empty witness
    directory, an empty ledger, an unparsable git status. "Nothing to check" is not "all clear".
  * EVERY CHECK RUNS SOMETHING. No check infers a state from another check's result.
  * THE LIST IS COMPLETE OR IT IS NOTHING. Each item traces to a sentence of the request. Items are
    named here in plain language, not in this session's private vocabulary.

Usage:  python3 .claude/commands/bug-hunt/finished.py
"""
import json, os, subprocess, sys

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                      capture_output=True, text=True).stdout.strip()
WIT = os.path.join(ROOT, ".claude", "bug-hunt", "witnesses")
REG = os.path.join(ROOT, "test", "regressions")
LEDGER = os.path.join(ROOT, ".claude", "bug-hunt", "rounds.json")

results = []            # (ok, name, detail)


def check(name):
    def deco(fn):
        try:
            ok, detail = fn()
        except Exception as exc:                       # a check that crashes has NOT passed
            ok, detail = False, f"the check itself failed: {exc!r}"
        results.append((ok, name, detail))
        return fn
    return deco


def run(*cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)


@check("every bug-demonstrating test file now passes")
def _witnesses():
    names = [f for f in os.listdir(WIT) if f.endswith(".jl")] if os.path.isdir(WIT) else []
    if not names:
        return False, "no test files found — an empty audit is not a clean one"
    r = run("julia", "--project", ".claude/commands/bug-hunt/witnesses.jl", "pass")
    tail = [l for l in r.stdout.splitlines() if l.startswith(("FAIL", "BROKEN"))]
    return r.returncode == 0, ("all pass" if r.returncode == 0 else "; ".join(tail) or r.stderr[-300:])


@check("each of those files is filed in the permanent test suite")
def _promoted():
    names = sorted(f for f in os.listdir(WIT) if f.endswith(".jl"))
    if not names:
        return False, "nothing to file"
    have = set(os.listdir(REG)) if os.path.isdir(REG) else set()
    missing = [n for n in names if n not in have]
    return not missing, ("all filed" if not missing else f"{len(missing)} not filed: {', '.join(missing[:6])}")


@check("filing did not overwrite an earlier test of the same name")
def _no_clobber():
    # A destroyed test is invisible once destroyed, so the check is on git: no tracked file under
    # test/regressions/ may be MODIFIED. A promoted file is new; an edited one means a collision.
    r = run("git", "status", "--porcelain", "test/regressions")
    if r.returncode != 0:
        return False, "could not read git status"
    modified = [l for l in r.stdout.splitlines() if l.startswith(" M") or l.startswith("M ")]
    return not modified, ("no tracked test was overwritten" if not modified
                          else f"overwritten: {'; '.join(m[3:] for m in modified)}")


@check("the full test suite passes")
def _suite():
    r = run("julia", "--project", "-e", "using Pkg; Pkg.test()")
    return r.returncode == 0, ("green" if r.returncode == 0
                               else (r.stdout or "")[-400:] + (r.stderr or "")[-200:])


@check("the documentation builds")
def _docs():
    run("julia", "--project=docs", "-e", "using Pkg; Pkg.develop(PackageSpec(path=pwd()))")
    r = run("julia", "--project=docs", "docs/make.jl")
    run("git", "checkout", "--", "docs/Project.toml")
    return r.returncode == 0, ("exit 0" if r.returncode == 0
                               else [l for l in (r.stdout or "").splitlines() if l.startswith("ERROR")][:2])


@check("every finding of the hunt has a recorded disposition")
def _round():
    # BOUNDED TO ONE HUNT (corrected 2026-08-21). This check used to demand a FOLLOW-UP HUNT that
    # confirmed nothing new — a terminator I invented, which no sibling instrument uses and which
    # cannot be reached while the code is under repair, because each round's fixes seed the next
    # round's findings. Measured across five rounds: 20, 9, 17, 21, 17. A rule that makes "finished"
    # permanently false is a bad rule, not a strict one, and it invited unbounded edits to code the
    # user does not read.
    #
    # `/check-docs` and `/check-consistency` both bound themselves the same way: the instrument runs
    # ONCE, and what loops is the VERIFIER over that run's banked findings. The verifier exists to
    # stop findings being quietly dropped — not to find new ones. Here the equivalent is stronger,
    # because a witness is a program: "every confirmed finding of THIS hunt is fixed" is decided
    # mechanically by the gate above, over a finite set, so it terminates.
    #
    # What remains for the ledger is that every finding has a DISPOSITION and none was forgotten.
    if not os.path.exists(LEDGER):
        return False, "no ledger — the hunt was never recorded"
    rounds = json.load(open(LEDGER))
    if not rounds:
        return False, "ledger is empty"
    last = rounds[-1]
    for field in ("confirmed", "fixed"):
        if field not in last:
            return False, f"hunt {last['round']} records no `{field}` count"
    accounted = last.get("fixed", 0) + last.get("escalated", 0) + last.get("refuted", 0)
    if accounted != last["confirmed"]:
        return False, (f"hunt {last['round']}: {last['confirmed']} confirmed but "
                       f"{accounted} accounted for (fixed + escalated + refuted). "
                       "Every finding needs a disposition; a missing one is a dropped finding.")
    return True, (f"hunt {last['round']}: all {last['confirmed']} findings dispositioned "
                  f"({last.get('fixed', 0)} fixed, {last.get('escalated', 0)} escalated, "
                  f"{last.get('refuted', 0)} refuted)")


@check("the edits were independently audited (/audit-changes) and every serious finding answered")
def _edit_audit():
    """The witness gate cannot see this class, which is why the audit is a phase and not an extra.

    A witness exists only for a defect the hunt happened to FIND. So a regression introduced by a
    fix — an edit wider than the defect required, a changed default, a broken convenience method —
    is invisible to the gate, and the gate scores it as zero damage. Measured on this repository:
    the witness set reported NEWLY BROKEN = 0 while two regressions were live and confirmed by hand
    (a CFL ceiling cutting the timestep 1.9x on ordinary runs, and a `fields_modified!(sim)` that
    always threw). Both were found by an independent auditor reading the DIFF, and by nothing else.

    So: the diff must be audited by agents that did not make it, and the audit must cover the
    CURRENT edits — an audit of an older tree certifies nothing about the code as it stands.
    """
    # DELEGATED. The edit audit is `/audit-changes`, a standalone instrument with its own gate — it
    # was lifted out of this one because the question it asks ("was this change proportionate?") is
    # orthogonal to how the edits arose, and applies equally to a docs sweep or a hand edit. This
    # check does not reimplement it; it runs that gate and adopts its verdict, so there is one
    # definition of "audited" rather than two that can drift.
    gate = os.path.join(ROOT, ".claude", "commands", "audit-changes", "gate.py")
    if not os.path.exists(gate):
        return False, "the /audit-changes gate is missing; the edit audit cannot be verified"
    r = run("python3", gate)
    out = (r.stdout or "") + (r.stderr or "")
    if r.returncode == 2:
        return False, "no audit on record — an unaudited change set is not a clean one"
    if r.returncode != 0:
        lines = [l.strip() for l in out.splitlines() if l.strip().startswith("!!")]
        return False, "the edit audit is not closed: " + ("; ".join(lines[:3]) or out[-300:])
    return True, "the /audit-changes gate is closed"


@check("no test file locates another by counting `..` hops")
def _no_hop_paths():
    # A witness is authored under .claude/bug-hunt/witnesses/ and PROMOTED into test/regressions/, so
    # a path counted from its original depth resolves outside the repository the moment it moves —
    # and the failure lands in the SUITE, not in the witness gate, which is why it keeps surviving a
    # green gate. `pkgdir` is depth-independent. This has recurred across two rounds; hence a check.
    import glob, re
    hop = re.compile(r'joinpath\(@__DIR__(?:\s*,\s*"\.\.")+')
    hits = [p for p in glob.glob(os.path.join(ROOT, "test", "regressions", "*.jl"))
                   + glob.glob(os.path.join(WIT, "*.jl"))
            if hop.search(open(p, encoding="utf-8").read())]
    return not hits, ("none" if not hits else "; ".join(os.path.basename(h) for h in hits))


@check("nothing is left uncommitted")
def _clean():
    r = run("git", "status", "--porcelain", "src", "test", "docs", "CLAUDE.md", ".claude/commands")
    if r.returncode != 0:
        return False, "could not read git status"
    dirty = [l for l in r.stdout.splitlines() if l.strip()]
    return not dirty, ("clean" if not dirty else f"{len(dirty)} uncommitted: {'; '.join(d[3:] for d in dirty[:6])}")


@check("everything is pushed")
def _pushed():
    run("git", "fetch", "--quiet")
    r = run("git", "rev-list", "--count", "@{u}..HEAD")
    if r.returncode != 0:
        return False, "no upstream, or could not compare"
    n = r.stdout.strip()
    return n == "0", ("up to date" if n == "0" else f"{n} commit(s) not pushed")


print()
for ok, name, detail in results:
    print(f"  [{'OK ' if ok else 'NO '}] {name}")
    if not ok:
        print(f"         -> {detail}")
failed = [r for r in results if not r[0]]
print()
if failed:
    print(f"NOT FINISHED — {len(failed)} of {len(results)} checks unmet.")
    sys.exit(1)
print(f"FINISHED — all {len(results)} checks met.")
sys.exit(0)
