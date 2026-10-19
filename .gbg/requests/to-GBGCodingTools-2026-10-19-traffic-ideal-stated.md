# To GBGCodingTools: a traffic row's ideal defaults to its measured count, so the row cannot fail

Status: approved by the owner on 2026-10-19, sent to the GBGCodingTools session the same day for
consideration.

## What happens

`TestHarness.Traffic` documents `ideal` as "the fused ideal documented beside it (each needed input
element read once, each output written once)", and `audit` requires a holder when `frozen != ideal`.
The three-argument form is

```julia
Traffic(role, array, frozen) = Traffic(role, array, frozen, frozen, "")
```

so a row written that way sets its ideal to the count it measures. Its holder test is
`frozen != ideal`, which is then false whatever the operation sweeps. `traffic_rows` does the same for
a baseline TOML: `ideal_reads` and `ideal_writes` default to `reads` and `writes`.

The form a row is easiest to write in is therefore the one form that certifies nothing. The frozen
count still catches a *change*. It never catches a count that was too high when it was frozen.

## How it was found

The owner asked whether HT keeps the shifted and the unshifted velocity at once under `PhaseShift`.
Recomputing that memory bound independently showed that it could not fail. A sweep of HT's other
audit bounds then found four more of the same kind (HT decision 116). One was in the traffic audit.
Before 2026-10-19, HT's 15 traffic rows were:

- 5 in the three-argument form, though the operation needs less than it measures:
  `add_forcing_source!` under `ConstantPower` and `VarianceController`, destination and source each,
  and `truncate_to_band!`. A band forcing needs the band's ``B`` entries, and the rows measured the
  whole field ``P``. The truncation needs to write the removed modes and read nothing, and the row
  measured ``(P, P)``.
- 2 with an ideal stated, but stated as the code's shape, ``(2P, P)``, and not as the band's
  ``(P + B, B)`` and ``(2B, B)``: `project_forcing!` under `VarianceRescaling`.
- 8 that are right: 4 zero rows, 3 tracer gathers whose stencil count is derived as the ideal, and
  the stochastic forcing's destination, already stated against the band with a holder.

All 15 passed. HT now states every ideal it can derive, and each of the eight rows above its ideal
carries a holder.

## Measured in PF, read only, 2026-10-19

`GBGPeriodicFields/test/pass_audit.jl` at `52cc2026` has 142 `Traffic` rows, all in the
three-argument form. Its comments state the ideals ("fused one-pass", "at ideal: decision 39 fused
the trace into a register"), and those statements may well all be true. But the comments are the
only place the ideal is stated. Nothing compares a comment with the count, so a regression frozen in
the same commit as its count would pass.

## What is asked

1. **Require the ideal.** Remove `Traffic(role, array, frozen)`, so that every row states
   `Traffic(role, array, frozen, ideal)`, or adds a holder when the two differ. A row at its ideal
   then writes the pair twice, and writing it is the claim. Make `ideal_reads` and `ideal_writes`
   required in `traffic_rows` in the same way.
2. **State the rule beside the check.** For example, in `testing-protocol.md`: *a traffic row's ideal
   is what the operation needs, derived without reading the code it judges; a measured count is never
   an ideal.* The constructor change is what enforces it. A rule without that change would be one
   more rule that reads as compliance.

## What it would cost

- HT: 7 rows gain a second tuple, all zeros or gathers.
- PF: 142 rows, a mechanical edit when the ideal equals the frozen count, which its comments say of
  most rows. A row whose comment does not say so is the review the change exists to force.

## A limit of the proposal

A stated ideal can still be copied from the measured count. The change makes that copy an explicit
act, visible in review, and no longer the default. Whether an ideal was derived independently stays a
reviewer's question.
