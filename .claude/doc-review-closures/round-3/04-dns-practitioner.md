# Closure audit — 04-dns-practitioner

## Finding 1 — "Float64 is the production precision" framing tension
**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md` §6 (lines 581–606) no longer contains "Float64 is the production
precision" / "Float32 is the development and desktop precision" anywhere; it now reads only "Both
precisions are supported equally, with no privileged default… the working point is chosen by direct
fitness test, never decreed." `grep -rn "production precision\|development and desktop precision"
docs/ src/` returns nothing. `src/SimulationRun.jl:140` states `element_type = Float64,
array_type = Array` neutrally as "the real element type and storage backend (front door only)" with
no normative "production" label attached. The specific contradiction the finding quoted (a
normative label sitting next to "no privileged default") no longer exists in the source text.

---

## Finding 2 — §2.3 transform-count table's scheme scope stated only once, before the table
**VERDICT: ABSENT**

Evidence: `docs/src/observables_cache.md:293` now reads "Counts are per step of a three-stage
scheme (`IFLowStorageRK3`); a scheme with a different stage count scales them by its own." —
immediately above the table at lines 296–299 (`| dealiasing rule | velocity only | with the scalar
|`). The resolution hint asked to repeat the scheme-scope qualifier at the table; that is exactly
what is now present, directly adjacent, not just in §2's opening sentence two paragraphs earlier.

---

## Finding 3 — `IFLowStorageRK3` "two field registers" vs. three-array `IntegratorBuffers`
**VERDICT: ABSENT**

Evidence: `src/Propagator.jl:240–245` now reads "…two field registers per field: the state's own
array plus one accumulator (`stage1`). The `IntegratorBuffers` a run allocates can hold more than
that count — for this scheme it adds `nonlinear`, the dealiasing seam's assembly register —
because the count measures the scheme, not the solver it is embedded in." The disambiguation is now
an explicit standalone sentence (not a skippable trailing parenthetical as quoted in the finding),
directly preempting the confusion the finding flagged (mistaking the Williamson "2N" count for the
actual resident buffer count). `src/Propagator.jl:90–99` (`IntegratorBuffers` Fields) still lists
`nonlinear` as its own field, consistent with this explanation, not contradicting it.
