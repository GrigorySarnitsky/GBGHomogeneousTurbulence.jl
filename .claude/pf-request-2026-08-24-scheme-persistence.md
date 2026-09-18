# Request from GBGIsotropicTurbulence (IT) — 2026-08-24, against GBGPeriodicFields master (post-decision-74): transfer-scheme persistence

> **DELIVERED 2026-08-24 (same day), PF decision 75.** `write_scheme`/`read_scheme` in the HDF5
> extension: `LalescuSpline` (neighbours, smoothness, eltype), `LagrangeSpline` (neighbours, eltype),
> `DirectDFT` (tag-only singleton), the `parent[name] = scheme` sugar — and the `NUFFT` refusal as a
> documented contract ("a compiled schedule, rebuilt never stored"), exactly the honest bound the
> request offered. Constructors revalidate parameters on read, so a malformed group throws at the
> guard that owns the invariant. IT-side acceptance verified: all four round-trip `===`-equal.
> This file is now a record.

One item, low priority — boundary hygiene in the same register as the 2026-08-24 Points round, not
performance or correctness. Expanded against the current surface before being raised: your HDF5
extension (`ext/GBGPeriodicFieldsHDF5Ext.jl`) persists the ten section/point classes through
self-describing groups — `_type_tag` + schema version + checked attributes, `write_field`/`read_field`
and `write_points`/`read_points` — and nothing in it, or anywhere public, persists a **transfer
scheme**. A scheme is a pure parameter record (`LalescuSpline{N2, M2, T, L}` built from
`(n, m; T)`, `LagrangeSpline(n; T)`, `CatmullRom = LalescuSpline(1, 1)`), so no composition of the
existing exports expresses this. The request states the need, not the API — surface design is yours.

## The need: write/read a transfer scheme to an HDF5 group, self-describing like the section pairs

**The consumer.** IT is building checkpoint/restore: `write_simulation` composes your
`write_field`/`write_points` groups into one simulation group a `read_simulation` fully restores —
every derivable object (physical charts, plans, multipliers, scratch) recomputed, never stored. The
recursion bottoms out cleanly on your pairs for every array-valued object IT holds… except one leaf:
IT's `Tracers` **owns its interpolation scheme** (a `Tracers` is positions + a chosen
`AbstractTransferScheme`), so fully restoring a tracer set means persisting a PF object your
extension does not cover.

**The workaround IT would otherwise ship, and why it is the wrong owner.** IT can write
`"GBGPeriodicFields.LalescuSpline"` tags plus `(n, m, T)` attributes itself and reconstruct through
your public constructors. Every piece is individually sanctioned — but the composition puts **PF type
tags, outside PF's schema version, in a second package**: when you add a scheme family (the recorded
van Hinsberg direction), rename one, or bump the schema, IT's registry drifts silently. This is the
same two-packages-can-drift argument that carried the reference-free allocator request (your decision
74): the tag machinery, the version discipline, and the checked-attribute idiom all live in your
extension already, and a scheme record is a few attributes riding exactly that machinery.

**Scope, honestly bounded.** IT's consumer is the **spline family** — the parameter-record schemes a
`Tracers` can hold (`LalescuSpline`, `LagrangeSpline`, and the `CatmullRom` alias, which needs no
identity of its own on disk). Whether the spectral-domain schemes are covered is your call and not
asked for: `DirectDFT` is a trivial singleton, but `NUFFT` carries plans and a reference and is a
different kind of object; a documented refusal there would serve IT fine.

**Acceptance.** IT's tracer writer persists `tracers.interpolation_scheme` through the PF pair and
the round trip reconstructs an `==`-equal scheme; IT's source contains no PF type tag and no
scheme-parameter schema of its own.

---

*Note, not an ask: the natural shape seems to be a `write_scheme`/`read_scheme` pair on a
group-with-attributes (a scheme has no `data` array), with the bare generics + docstrings in
`Interpolation` so `?write_scheme` works without HDF5 — mirroring your `write_points` arrangement —
but the surface is yours; an attribute-set-on-the-parent design would serve equally.*
