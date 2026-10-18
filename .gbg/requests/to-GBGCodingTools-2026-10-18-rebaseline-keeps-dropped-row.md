# To GBGCodingTools: `gbg check --rebaseline --unit` reports a row DROPPED and keeps it

Status: approved by the owner on 2026-10-18, sent to the GBGCodingTools session the same day. The
owner asks GBGCodingTools to decide whether it is worth fixing.

## What happens

At rc.80, a unit-scoped rebaseline of a renamed docstring lists the old row as `DROPPED`, then
writes a baseline that still holds it. Renaming `integral_scale(û, domain)` to
`integral_length(û, domain)` (HT 7707460f) and running

```
gbg check --rebaseline --unit "Observables.jl :: integral_"
```

printed

```
  NEW      Observables.jl :: integral_length(û, domain): words 263, longest paragraph 90, admonitions 0
  DROPPED  Observables.jl :: integral_scale(û, domain)
rebaseline: 2 row(s) above.
rebaseline: wrote docs/prose_shape.csv, the unit(s) matching "Observables.jl :: integral_" alone.
```

and `docs/prose_shape.csv` then held both rows, the new one and the old. Running it again with
`--unit "Observables.jl :: integral_scale"` printed the same `DROPPED` line and left the row in
place. It was removed by hand.

## The cause

`changes` and `write_baseline` in `src/Rules/shape.jl` disagree about a dropped row. `changes`
reports every baseline row no unit carries. `write_baseline` with `only` starts from the old
baseline and overwrites or adds the measured units whose key holds `only`; a baseline row that holds
`only` and has no unit any more is never removed. A full rebaseline, with no `--unit`, rebuilds from
the units and drops it.

## What it costs

A stale row is not checked against anything, so no check goes wrong today. It grows the baseline
with rows for units that no longer exist, and a unit that later takes the old key back inherits the
old ceiling. The report also says the row was dropped when it was not, which is how it was noticed.

## A fix, if it is worth one

In the `only` branch, remove the rows that `changes` would list as `DROPPED` and whose key holds
`only`. A row a renamed unit is still measured against under its new key (`changes`' `carried`
set) is not one of them and stays.
