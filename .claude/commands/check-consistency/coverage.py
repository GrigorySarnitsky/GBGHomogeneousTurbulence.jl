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

# The heading delimiter is optional: hats write "## 3. Title", "## Finding 3 — Title" and bare
# "## Finding 3". Requiring punctuation after the number made one hat parse to ZERO findings while
# it had banked eleven — and because a hat with 0 banked needs 0 verdicts, it then passed the gate
# as "ok". Both holes are closed here: the delimiter may be end-of-line, and a hat that parses to
# nothing is an error rather than a pass.
FINDING = re.compile(r'^#{2,3} +(?:Finding +)?(\d+)(?=[.:)\s-]|$)', re.M)
# Agents render the verdict two ways — "VERDICT: PARTIAL" and a standalone "**PARTIAL**" — and an
# earlier version of this regex demanded the literal word VERDICT, so it reported a complete 21/21
# hat as SHORT by 21. A coverage gate that cries wolf is one the operator learns to wave through,
# which is the failure it exists to prevent, so it accepts both renderings.
TOKEN = r'(?:PRESENT|PARTIAL|REGRESSED|ABSENT|NOT-A-DEFECT)'
VERDICT = re.compile(r'(?:VERDICT[:*\s]*\**\s*' + TOKEN + r'|^\s*\**' + TOKEN + r'\**\s*$)', re.I | re.M)

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
    if banked == 0:
        rows.append((hat, banked, got, 'NO FINDINGS PARSED — heading format not recognized?'))
        bad += 1
    elif got < banked:
        rows.append((hat, banked, got, f'SHORT by {banked - got} — findings adjudicated silently'))
        bad += 1
    else:
        rows.append((hat, banked, got, 'ok'))

# Pointed at a directory holding no hat files at all, an earlier version of THIS script printed
# "0 hats | 0 findings | COMPLETE" and exited 0 — the same silent-success shape it exists to catch,
# in the tool written to catch it. A pile with no hats is a bad argument, not a clean result.
if not rows:
    print(f'no hat files (NN-*.md) under {pile!r} — wrong pile directory?')
    sys.exit(2)

w = max((len(r[0]) for r in rows), default=10)
for hat, banked, got, note in rows:
    print(f'{hat:<{w}}  banked {banked:>3}  verdicts {"--" if got is None else got:>3}  {note}')
tb = sum(r[1] for r in rows)
tv = sum(r[2] or 0 for r in rows)
print(f'\n{len(rows)} hats  |  {tb} findings banked  |  {tv} adjudicated', end='')
print(f'  |  {"COMPLETE" if not bad else str(bad) + " HAT(S) UNVERIFIED OR SHORT — the tally is NOT a closure rate"}')
sys.exit(1 if bad else 0)
