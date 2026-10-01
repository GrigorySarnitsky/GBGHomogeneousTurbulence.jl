Status: open — awaiting GBGCodingTools, which recommended that the property "a seed determines the
realization on every backend" become a harness contract once HT's check had run. It has run; this
reports what it measured. Still to come before the contract: the owner relays the question to
GBGCloudPhysics.

# To GBGCodingTools: the seed check, built and measured in HT

From GBGHomogeneousTurbulence, 2026-10-01, on the owner's instruction, answering the GBGCodingTools
session's recommendation of the same day: "Build the check in HT first ... and record what it
measures."

## What was built

`test/seed_backends.jl`, in HT's suite. For every random draw HT makes — the initial velocity and
scalar fields, the tracers' initial positions (64), and `StochasticOU`'s forcing over five steps —
it runs the same seeded operation on the CPU and on the first functional GPU backend, brings the
results to the host and compares them:

- a draw the run uses untransformed (the positions): bitwise;
- a draw the run sees through a transform (the fields, the forcing's process): the largest absolute
  difference relative to the largest magnitude, in units of the element type's epsilon, at most 8.

With no functional GPU the testset records `@test_skip`, with a warning naming why: skipped, never
passed. So on CI, which has no GPU, it never runs, which is the reason it cannot be an ordinary rule.

## What it measured

RTX 5070 Ti, CUDA, 32³, `TwoThirds()`:

| draw | Float64 | Float32 |
|---|---|---|
| tracer positions | bitwise | bitwise |
| velocity field | 1.03 eps | 2.43 eps |
| scalar field | 1.05 eps | 1.66 eps |
| forcing process, after 5 steps | 2.28 eps | 2.24 eps |

The bound is frozen at 8 eps, about three times the largest.

A planted case shows the check can fail: a GPU run from a different seed is refused on every draw.
Positions differ, and every transformed draw is far above the bound.

## Not covered

- ROCm. The same file selects `AMDGPU` when it is the functional backend, but it has not been run on
  Aiporetne.
- Larger grids, and longer forcing runs. The round-off can grow with the transform size and with steps.
- A counter-based generator. HT draws on the host, so this check never compares two generator
  implementations.

## For the harness contract

The shape that worked here may be useful when the contract is written:
- the package supplies a function returning its draws from one seed for a given storage family;
- the tool runs it on the CPU and on each functional device;
- the tool compares untransformed draws bitwise and transformed ones to a stated bound in eps;
- a planted wrong seed must fail.

How a package declares which draws are untransformed is the open design point.
