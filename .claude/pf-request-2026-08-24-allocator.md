# Request from GBGIsotropicTurbulence (IT) — 2026-08-24, against GBGPeriodicFields master: a reference-free field allocator

> **DELIVERED 2026-08-24 (same day), PF decision 74.** The six field constructors accept a storage
> family in place of the array; element type from the grid; uninitialized by contract. Wired in IT
> decision 64: `_reference`/`_blank` deleted, `FixedDomain` stores `storage_family`. A record now.

One item, low priority (correctness is unaffected; this closes IT's last off-label use of a PF
surface). Expanded against the current exports before being raised: every public allocator is
**reference-value-based** — `similar_field(reference::AbstractField, data | ::Val{R})` copies
metadata from an existing field, `similar_pointvalues` likewise from existing point values, and the
explicit field constructors take a raw storage array the *caller* must already have produced on the
right backend. Nothing public produces field storage without an existing value in hand. The request
states the need, not the API — surface design is yours.

## The need: allocate a field from (grid, layout, tensor order, representation, element type, backend) — with no field in hand

**The consumer.** IT's `FixedDomain` — the read-only frame a run lives on — holds **zero
field-scale arrays by ledger-proven design**: when your lazy kernels landed, the dealias mask and
``\lvert k\rvert^2`` stopped being fields, and IT's memory audit now *asserts* the frame ledger is
empty. But the frame is also where IT's public allocators live (`new_vector_field_spectral(domain)`
and five siblings), so the one place that must allocate fields on demand is, by its own memory
discipline, the one place with no reference field to copy from — and keeping a field just to serve
as an allocator template would put an ``N^3`` array back into the ledger the completeness test
proves empty.

**The workaround today** (src/SimulationDomain.jl), legal but off-label:

```julia
# GBGPeriodicFields `similar(reference, …)` allocation discipline (its invariant 6). The dealias
# kernel no longer serves as the template: a compressed kernel stores no field-sized array.
_reference(domain::FixedDomain) = domain.multipliers.squared_wavenumber_1
_blank(domain::FixedDomain, ::Type{S}, dims) where {S} = fill!(similar(_reference(domain), S, dims), zero(S))
```

The multipliers' axis vector is a *documented public field* — but it is being read as a
**backend-and-element-type witness** for `Base.similar`, not for its wavenumbers, and the result is
then hand-wrapped through the explicit constructors with shapes from
`spectral_field_shape`/`physical_field_shape`. Every piece is individually sanctioned; the
composition reproduces, outside your package, exactly the metadata logic (`representation × tensor
order → storage shape`, backend propagation, zero-fill) that your reference-based allocators own
inside it.

**The ask.** A public route from *metadata alone* to allocated field storage: grid + layout +
tensor order + representation (physical/spectral) + element type + backend, with your Nyquist/shape
conventions applied — the reference-free completion of the `similar_field` family. How the backend
is conveyed (an array type, a `KernelAbstractions` backend value, an `adapt`-style target) is your
design; IT holds it as a constructor keyword (`array_type`) it currently discards.

**Why it is yours rather than ours:** the shape-and-backend logic is the definition of what "a
field's storage" *is*, and any other frame-zero consumer (the design your own lazy kernels enable)
hits the same wall. The alternative — IT storing `array_type`/`element_type` on its frame and
keeping the raw-`similar` composition — works, and is what IT will do if you'd rather not own this;
but then the storage-metadata logic lives in two packages and can drift.

**Acceptance.** IT deletes `_reference`/`_blank`; the six `new_<Type>` allocators become thin
wrappers over the PF allocator; no IT code reads a multipliers field for any purpose other than
wavenumbers.
