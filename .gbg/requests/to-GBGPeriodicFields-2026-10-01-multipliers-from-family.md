Status: open — sent to the GBGPeriodicFields session 2026-10-01, for its evaluation; HT records the
residual inside the :PF_RAISE gap TRANSFORM PLANNING (test/audit_ops.jl).

# To GBGPeriodicFields: wavenumber multipliers from the storage family

Since PF decision 93, HT's `FixedDomain` plans its transforms from `(family, grid, layout)` and
builds no field for the planner. It still builds one scalar field in spectral representation, about
1.03 N³ reals, freed at once, for a single purpose: `FieldSpectralMultipliers(field)` takes a field.
It reads only the storage type, through `field_data(field)` as the reference for its axis arrays.

A `FieldSpectralMultipliers(family, grid, layout)`, the multipliers' counterpart of decision 93's
planner form, would remove that last template. The result would be canonical, like the field form,
so its kernels merge as today.

The cost is small: once per construction, about 1 N³ real. It is listed because the ledger lists
everything above the floor; the decision is PF's.
