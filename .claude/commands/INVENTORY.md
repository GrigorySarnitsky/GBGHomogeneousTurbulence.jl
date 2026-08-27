# Instrument inventory — IT, and what it shares with PF

Recorded 2026-08-27, from the IT/PF harmonization exchange. **Tracked deliberately**: it was
produced in a cross-session message and the findings piles it draws on are untracked working notes,
so a transcript is the most fragile place it could live. PF keeps the same content in its own
`CLAUDE.md`.

**Status: the shared instrument package is DEFERRED** (PF's owner, 2026-08-27 — "not a priority now,
we will make it later"). This file is the fact base a later proposal would be written against, so it
is not re-derived. Nothing here is a commitment by IT.

## Sizes

IT: 33 files, 4583 lines. PF: 17 files, 1977. Second column is lines naming the package
specifically — grep over `GBGIsotropicTurbulence`, `ARCHITECTURE.md`, turbulence/pseudospectral/
dealias/forcing/tracer/vorticity/varphi/kappa/integrating-factor, IT module names, `decision N`,
`invariant N`.

    audit-changes/attack-design.js   136   1     check-consistency/panel.js            339  22
    audit-changes/audit.js           176   6     check-consistency/recall.py           110   0
    audit-changes/gate.py             87   0     check-consistency/rubric_audit.js     166   1
    audit-changes.md                 100   1     check-consistency/rubric_extract.py    83   0
    bug-hunt/closure.py              115   0     check-consistency/rubric_prep.py       46   0
    bug-hunt/dismissals.js           102   0     check-consistency/seed_defects.py      88   4
    bug-hunt/finished.py             206   0     check-consistency/severity_recheck.js  58   1
    bug-hunt/hunt.js                 324  12     check-consistency/verify-fixes.js     224   2
    bug-hunt/verify-fixes.js          81   1     check-consistency/verify.js           269   4
    bug-hunt/witnesses.jl            112   0     check-docs/abutting_spans.py           44   2
    bug-hunt.md                      247   1     check-docs/argcov.jl                   62   0
    check-consistency/consolidate.py 109   2     check-docs/doi_crosscheck.py           51   1
    check-consistency/coverage.py     73   0     check-docs/dupref.jl                   23   0
    check-consistency.md             440   8     check-docs/lanes.js                    92  11
    manifest.py                      110   0     check-docs.md                         296  21
                                                 check-docs/signature_fidelity.jl      140   6
                                                 check-docs/xlink.jl                    73   5

## The split the numbers imply

**Shared engines + per-package config + per-package `.md`.** 1029 lines across 12 IT scripts have
ZERO package coupling and would move unchanged: `gate.py`, `closure.py`, `dismissals.js`,
`finished.py`, `witnesses.jl`, `coverage.py`, `recall.py`, `rubric_extract.py`, `rubric_prep.py`,
`argcov.jl`, `dupref.jl`, `manifest.py`.

Both packages' zero-lists agree on `gate.py`, `coverage.py`, `recall.py`, `witnesses.jl`,
`argcov.jl`, `manifest.py`. Where coupling is real it is concentrated and it is DATA rather than
logic: `panel.js`'s 22 hits are almost all inside its 27 `persona:` strings plus one package-
description paragraph; `hunt.js`'s 12 are module names and the Julia invocation. The config a shared
engine would need is therefore: hat personas, the seeded-defect catalog, notation patterns for the
greps, paths, and a one-line package description.

## Behavioural divergences a shared package must resolve

| | IT | PF | which wins |
|---|---|---|---|
| `class_surfaces` demotion | tests EMPTINESS | parses content | **IT** — PF's content match demoted 10 sound answers of 13 on notation alone |
| staleness | self-reported `head`, DEFAULTS TO STALE | filesystem mtime | **PF** — mtime needs no compliance; keep IT's default-direction rule beside it |
| disposition gate | `gate.py` answers findings | no equivalent outside the build | IT |
| bug-hunt verdict set | 5 verdicts incl. `WITNESS-WRONG` | may differ | **unresolved — a SCHEMA divergence, not wording**: `dismissals`, `closure` and `finished` all key off it |

Line counts differ 1.5–2× on same-named files (`hunt.js` 324/213, `verify.js` 269/186). Some is IT's
long postmortem headers; some will be behaviour. That needs a real diff, not a count comparison.

## No counterpart, both ways

- **IT has, PF does not:** the whole `audit-changes` instrument (499 lines); bug-hunt's `closure.py`,
  `finished.py`, `dismissals.js`; the `rubric_*` triple; `severity_recheck.js`; `abutting_spans.py`,
  `dupref.jl`, `signature_fidelity.jl`, `xlink.jl`, `lanes.js`.
- **PF has, IT does not:** `lint_review_closure()` (a build lint in PF's `docs/make.jl`),
  `guards.sh`, `recall_selftest.py`.

`recall_selftest.py` is the one IT most lacks, and why is the point: IT's perturbation arms are a
COMMENT in `recall.py`'s header instructing a human to re-run them, where PF's is a script. That is
the rule-versus-check distinction from this file's own `CLAUDE.md` weakness entry, found in IT's tree
after that entry was written — the rule's author failing it in the file next door. It belongs in the
shared package rather than being ported.

## Two design constraints, established before any code

1. **`lint_review_closure()` cannot move unchanged** — IT's build is not PF's. It has to become a
   script both builds call.
2. **A shared closure gate would pass vacuously on IT.** IT's findings piles are untracked by
   standing decision, so on a fresh clone the gate finds no round, finds nothing unclosed, and
   passes — violating the rule that the missing case must be the failing case. The design needs
   either a tracked open-round marker or a gate that fails when the pile it expects is absent.

## What `manifest.py` is for, after sharing

Not retired, demoted. Diffing detects divergence after the fact and a shared package prevents it —
but a shared package can be PINNED AT TWO VERSIONS in two consumers, and then the toolboxes are
being diffed again. It is the right solution to a smaller problem.
