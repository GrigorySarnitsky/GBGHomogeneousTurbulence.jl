Status: open — sent to the GBGPeriodicFields session 2026-10-01, for its evaluation; HT records both
as :PF_RAISE gaps, TRANSFORM PLANNING and CHECKPOINT STAGING COPY (test/audit_ops.jl).

# To GBGPeriodicFields: two memory gaps in PF code that HT's temporary ledger found

Measured on the CPU, Float64, in N³ reals, with each call warmed up before measuring.

1. **Planning.** `FieldTransformPlans(p, s)`, with `p` a scalar physical field and `s` a scalar
   field in spectral representation, allocates about 3.06 N³ reals it does not keep (64³). It also
   needs those two templates handed to it (2.03), so building an HT `FixedDomain` costs 5.1, all of it
   at the planner. HT has removed its own share (11.2 → 5.1). Questions: what are the 3.06, and could
   the planner work without the caller's templates, or free what it allocates?
2. **Checkpoint copies.** `write_field` writes `Array(field_data(field))`, under the comment
   "no-op on CPU", but `Array(a)` copies even an `Array` (`Array(a) === a` is false). The same
   pattern is at the HDF5 extension's line 198. `read_field` returns a new host field the caller then
   copies into its own. Each costs about 4.1 for HT's velocity and scalar. Questions: skip the copy
   when the storage is already host memory; and would a `read_field!(destination, parent, name)` that
   reads into an existing field fit PF, staging one component at a time on a device?

No urgency: both are construction-time or checkpoint-time costs, never in the time loop.
