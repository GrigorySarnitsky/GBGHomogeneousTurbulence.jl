#!/usr/bin/env python3
"""Coverage check for a closure round — the measurement behind the tally.

A workflow script cannot see the filesystem, so nothing inside `verify.js` can confirm that a hat
actually WROTE its verdict file, or that the file covers every banked finding. This does that from
outside, and it is a MANDATORY post-step of a closure round: a tally is not a closure rate until
this passes.

It exists because both failures have happened here. On 2026-08-18 two hats returned an empty
structured result while writing a full verdict file (six verdicts silently missing from the tally),
and before that the verifier's hat list named 11 hats while the panel banked 15 (four hats never
verified, the run still reporting success).

    python3 coverage.py <pile-dir> [closure-subdir]     # default subdir: closure

Exit status is 1 when any hat is unverified, short, or missing — so it can gate a "converged" claim.
"""
import re, sys, glob, os

pile = sys.argv[1] if len(sys.argv) > 1 else '.claude/doc-review'
sub = sys.argv[2] if len(sys.argv) > 2 else 'closure'
closure = os.path.join(pile, sub)

FINDING = re.compile(r'^#{2,3} +(?:Finding +)?(\d+)[.:) ]', re.M)
VERDICT = re.compile(r'VERDICT[:*\s]*\**\s*(PRESENT|PARTIAL|REGRESSED|ABSENT|NOT-A-DEFECT)', re.I)

rows, bad = [], 0
for path in sorted(glob.glob(os.path.join(pile, '[0-9][0-9]-*.md'))):
    name = os.path.basename(path)
    if name.startswith('00-'):
        continue
    hat = name[:-3]
    banked = len(set(FINDING.findall(open(path, encoding='utf-8').read())))
    vpath = os.path.join(closure, name)
    if not os.path.exists(vpath):
        rows.append((hat, banked, None, 'NO VERDICT FILE — this hat was never verified'))
        bad += 1
        continue
    got = len(VERDICT.findall(open(vpath, encoding='utf-8').read()))
    if got < banked:
        rows.append((hat, banked, got, f'SHORT by {banked - got} — findings adjudicated silently'))
        bad += 1
    else:
        rows.append((hat, banked, got, 'ok'))

w = max((len(r[0]) for r in rows), default=10)
for hat, banked, got, note in rows:
    print(f'{hat:<{w}}  banked {banked:>3}  verdicts {"--" if got is None else got:>3}  {note}')
tb = sum(r[1] for r in rows)
tv = sum(r[2] or 0 for r in rows)
print(f'\n{len(rows)} hats  |  {tb} findings banked  |  {tv} adjudicated', end='')
print(f'  |  {"COMPLETE" if not bad else str(bad) + " HAT(S) UNVERIFIED OR SHORT — the tally is NOT a closure rate"}')
sys.exit(1 if bad else 0)
