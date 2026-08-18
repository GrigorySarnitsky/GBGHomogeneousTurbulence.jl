# Closure audit — 04-dns-practitioner

## Finding 1 — "Float64 is the production precision" sits oddly for a GPU-primary, consumer-GPU code

**VERDICT: PRESENT**

Evidence: `docs/ARCHITECTURE.md:585-586` reads verbatim "Both precisions are supported equally,
with no privileged default. `Float32` is the development and desktop precision; `Float64` is the
production precision." and line 603 still says "the working point is chosen by *direct fitness
test*, never decreed." Same soft framing tension as banked. `src/SimulationRun.jl:66,180,273,275`
still default `element_type = Float64`.

---

## Finding 2 — §2.3 transform-count table's scheme scope stated once, not at the table

**VERDICT: PRESENT**

Evidence: `docs/src/observables_cache.md:221` states "a three-stage scheme" only in §2's opening
sentence. The per-evaluation recipe (lines 272-283) and the table itself (lines 293-294, `18
inverse, 9 forward` / `21 inverse, 18 forward` / `36...`/`42...`) carry no repeated "three-stage"
or scheme-name qualifier in the table, its caption, or the surrounding paragraphs (checked
lines 257-311). Unchanged from banked description.

---

## Finding 3 — `IFLowStorageRK3`'s "two field registers per field" sits next to a three-array `IntegratorBuffers` list

**VERDICT: PRESENT**

Evidence: `src/Propagator.jl:240-243` retains the identical wording: "two field registers per
field: the state's own array plus one accumulator (`stage1`; the raw-assembly register
`nonlinear` is the dealiasing seam's addition, not the scheme's)." `IntegratorBuffers`
(`src/Propagator.jl:85-99`) still lists `stage1`, `nonlinear`, `stage2`, `velocity_star_spectral`
as fields, with `nonlinear` documented as a real, distinct, allocated array for
`IFLowStorageRK3`. Same low-confidence nit as banked, unchanged.
