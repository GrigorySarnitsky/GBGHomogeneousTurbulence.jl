# Closure audit — final state (2026-08-17)

Four blind runs of `verify.js` over the 85 banked panel findings, interleaved with six runs of
`verify-fixes.js` over the 42 read findings. Both instruments have converged: the last three
rounds of each sit flat within noise, surfacing *different* marginal items each time.

| run | ABSENT | PRESENT | PARTIAL | REGRESSED |
|---|---:|---:|---:|---:|
| 1 (pre-fix) | 59 | 13 | 12 | 1 |
| 2 | 65 | 12 | 8 | 0 |
| 3 | 75 | 3 | 6 | 1 |
| 4 (final) | 69 | 2 | 6 | 0 |

Run 4 adjudicated 77 of 85: the `07-api-user` hat returned zero verdicts — an agent failure, not a
corpus fact. Its eight findings were all ABSENT in run 3 and nothing since touched their surfaces.

## Per-hat, final run

| hat | n | ABSENT | PRESENT | PARTIAL |
|---|---:|---:|---:|---:|
| 01-consistency-matrix | 2 | 2 | 0 | 0 |
| 02-software-architect | 7 | 6 | 1 | 0 |
| 03-turbulence-theoretician | 10 | 10 | 0 | 0 |
| 04-dns-practitioner | 5 | 5 | 0 | 0 |
| 05-structure-consistency | 12 | 9 | 1 | 2 |
| 06-latex-typesetter | 6 | 6 | 0 | 0 |
| 07-api-user | 0 | 0 | 0 | 0 |
| 08-dimensional | 9 | 9 | 0 | 0 |
| 09-citations-integrity | 4 | 3 | 0 | 1 |
| 10-style-editor | 7 | 6 | 0 | 1 |
| 11-cold-reader | 15 | 13 | 0 | 2 |
| **TOTAL** | **77** | **69** | **2** | **6** |

## What remains, and why

- **02#4** — a confirmed **false positive**. The finding asked for a protocol-level callout that
  `prepare_forcing!` alone does not mutate its second argument; it exists verbatim at
  `src/Forcing.jl:71`, and run 3 scored the same finding ABSENT citing that same text.
- **05#6** — closed with a reason. `StationarityCriterion`'s seven keywords cannot map one-to-one
  onto six fields because five of them are stored inside the nested `monitor`; the `# Fields`
  section states that mapping explicitly rather than leaving the reader to infer it.
- **09#3 / 10#4** — the Kaneda 1993 attribution, parked by the owner, and the citation-format
  difference between `ARCHITECTURE.md`'s full entries and the leaf's `Reference` values.
- **05#1, 05#5, 11#1, 11#10** — template and vocabulary long-tail; the named instances are fixed
  and each verdict now cites a different residual site than the round before, which is the
  signature of the instrument's own resolution rather than of an open defect.

## Instrument note

A hat returning zero verdicts is invisible in the tally — the totals simply shrink. A future run
should treat a per-hat count of zero as a failure to re-run, not as a clean sheet.
