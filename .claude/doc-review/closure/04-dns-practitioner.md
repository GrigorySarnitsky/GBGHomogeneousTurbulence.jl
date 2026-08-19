# Closure audit — hat 04: performance-focused DNS practitioner

## Finding 1 — "IFLowStorageRK3's two registers" defined two different ways
**VERDICT: PRESENT**

Evidence: `docs/ARCHITECTURE.md` L383-389 still reads "three spectral registers per field against
the low-storage scheme's two, counting the same way on both sides: the scheme's own registers plus
the dealiasing seam's assembly register" — cross-checked against `docs/src/observables_cache.md`
L215 ("six vector-shaped fields — four in spectral representation") this "two" resolves to
`{stage1, nonlinear}` (IntegratorBuffers content, excluding the state array). `src/Propagator.jl`
L244-249 (`IFLowStorageRK3` docstring) still defines its "two field registers" as "the state's own
array plus one accumulator (`stage1`)" — explicitly excluding `nonlinear` — and adds a clarifying
sentence that `IntegratorBuffers` "can hold more than that count... because the count measures the
scheme, not the solver it is embedded in." This sentence explains *that* the two countings differ,
but the two headline "two"s named in ARCHITECTURE.md and Propagator.jl are still two different pairs
of arrays (`{stage1, nonlinear}` vs `{state, stage1}`) sharing a cardinality — the exact contradiction
the finding describes, textually unchanged from the finding's own quotes.

---

## Finding 2 — Quickstart's default forcing is a deterministic clamp, undisclosed at first contact
**VERDICT: PRESENT**

Evidence: `docs/src/index.md` L30-45 (quickstart code block) still reads only `# a 64³
forced-stationary run; ... ν is set so the grid resolves the dissipation scale`, with no mention of
`BandRescaling`, its clamp character, or a link to the caveat. Grepped the whole page
(`grep -n "BandRescaling|clamp|forcing" docs/src/index.md`): `BandRescaling` appears once, in the
work-in-progress note listing the forcing menu — not at the quickstart. The caveat itself is present
and unchanged at `src/SimulationRun.jl` L93-98 ("a deterministic clamp... suppresses the physical
fluctuation of the quantity it holds") and `src/Forcing.jl` L290-299, three modules away from the
page that most needs it, exactly as the finding describes.

---

## Finding 3 — PhaseShift's per-term scratch-buffer count stated only vaguely
**VERDICT: PRESENT**

Evidence: `src/SimulationDomain.jl` L121-123 (`PhaseShift` docstring) still reads "the
displaced-evaluation scratch (a field-scale spectral-representation buffer per phase-shifted term)"
— no number. `src/Generator.jl` L222-223 (`ResolvedGenerator` Fields) still reads "`phase_shift` —
the displaced-evaluation scratch and translation kernels... else `nothing`" — no number. The actual
buffer count lives only in `PhaseShiftBuffers` (`src/Generator.jl` L107-119), which carries a plain
`#` comment, not a docstring, so it is not user-facing. Searched `docs/ARCHITECTURE.md` for
`PhaseShift` buffer/register counts (decision 36, decision 45 passages) — these state transform and
materialized-symbol counts, never the scratch-buffer cardinality. No page states the count.

---

## Finding 4 — Re_λ ~ N^(2/3) reads strategy-independent when the hidden constant depends on `f`
**VERDICT: ABSENT**

Evidence: `src/SimulationRun.jl` L118-122 now carries a worked numeric comparison immediately before
the scaling-law sentence: "``f = 1`` puts ``\eta \approx 0.64\,\Delta x`` at `κ_max_η = 2` (against
``0.96\,\Delta x`` for ``2/3``), and since ``\nu \propto f^{-4/3}``, `HouLi` is handed a
``\mathrm{Re}_\lambda`` about 31% higher on the same grid at the same nominal criterion — raise
`κ_max_η` when comparing across strategies," directly followed by "The `kinetic_energy` and
`side_length` fix the units; the grid and `κ_max_η` fix ``\mathrm{Re}_\lambda \sim N^{2/3}``." This
is exactly the kind of worked comparison the finding proposed ("HouLi buys ~1.5× the Re_λ of
TwoThirds...") and closes the gap between the strategy-independent-reading headline sentence and the
strategy-dependent surrounding prose.
