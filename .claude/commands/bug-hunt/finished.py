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


@check("the bug-hunting pass is recorded as closed")
def _round():
    if not os.path.exists(LEDGER):
        return False, "no ledger — the pass was never recorded"
    rounds = json.load(open(LEDGER))
    if not rounds:
        return False, "ledger is empty"
    last = rounds[-1]
    if "followup_confirmed" not in last:
        return False, (f"pass {last['round']} has no follow-up hunt recorded; a fix pass introduces "
                       "its own defects, so it is not closed until hunting again finds nothing new")
    if last["followup_confirmed"] != 0:
        return False, f"the follow-up hunt found {last['followup_confirmed']} new problem(s)"
    return True, f"pass {last['round']} closed with a clean follow-up"


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
