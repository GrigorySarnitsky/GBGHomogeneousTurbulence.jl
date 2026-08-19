# Panel review — hat: DNS practitioner (performance-focused)

Scope: numerical methods and performance claims across the rendered manuscript — rotational form,
integrating factor, dealiasing bands and transform counts, IF-RK2/RK3, the deposit-driven cache
schedule, particle interpolation, forcing. Cross-checked the dealias-band numbers (2/3, √2/3·N,
2√2/3·κ_Ny) and the transform/pass ledgers across every page that states them; both are internally
consistent everywhere they appear (the observables_cache design page's §2.3 table derives cleanly
from its own per-evaluation breakdown, and reproduces the "PhaseShift = exactly 2× a mask cell,
velocity and scalar alike" claim made on three separate pages). Register counts, CFL calibration
arithmetic (κ_maxΔx = 2π/3 ≈ 2.09, C_CFL ≲ 0.83 → 0.5), the N³-byte-size figures (384 MiB per
vector field at 256³/Float64, 2.3 GiB for six vector-shaped fields), and the Re_λ ∼ N^{2/3}
resolution-scaling claim all check out by direct derivation. Findings below are the residue.

---

## Finding 1 — StationarityCriterion's skewness "sampling interval" is referenced but never specified

**Type:** api-gap
**Severity:** major
**Confidence:** medium

**Locations:**
- PAGE: api / SimulationRun, `StationarityCriterion`'s `gate_skewness` argument: "The skewness costs
  transforms, so it is measured on the criterion's own sampling interval rather than every
  iteration."
- Same page, `StationarityCriterion(...)` signature and `# Arguments` list (`gate_scalar`,
  `gate_skewness`, `min_turnovers`, `window_turnovers`, `tol`, `skew_floor`, `max_turnovers`) — no
  keyword named for an interval, cadence, or sampling stride.
- PAGE: architecture, decision log 2026-08 entry: "the `every` cadence... leaves `run!` entirely: ...
  a cadence is the callback's own business."

**Description:** For a performance-focused reader this is exactly the number that matters: the
skewness diagnostic is priced elsewhere in the doc at ≈19.6 units of N³ transient allocation — "the
dominant episode, about half again the default resident set" — so how often `warmup!` pays that cost
is a first-order cost question. The docstring asserts a "sampling interval" exists and is
criterion-owned, but no keyword, default value, or even a qualitative description ("every k
turnovers", "every k iterations") is given anywhere in the rendered surface. A reader cannot size
the warm-up cost from what is documented. This also sits oddly against the decision-log's own claim
that cadence vocabulary was deliberately removed from the package and pushed to "the callback's own
business" — `StationarityCriterion` is a packaged callback, so if it has an internal cadence, that
cadence is exactly the kind of thing the same decision says the package no longer owns.

---

## Finding 2 — Worked example of fields-epoch vs current_step does not add up under the stated definition

**Type:** contradiction
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: api / SimulationRun, `current_step`: "after two steps and one announced mutation the clock
  reads step 2 and the fields epoch reads 4."
- PAGE: api / Cache, `ObservablesCache` Fields: "`fields_epoch` — the resolved fields' counter:
  advanced by every completed step and by `fields_modified!`... it counts changes to the state."

**Description:** By the stated rule ("counts changes to the state"), two completed steps plus one
announced mutation is three state-changing events. Starting from a natural zero baseline ("no
changes yet ⇒ epoch 0"), the epoch after these three events is 3, not 4 — the example only resolves
if the initial seeding deposit at construction is silently counted as a fourth, unstated
epoch-advancing event, which no page states explicitly (the construction deposit is elsewhere
described only as recording the *initial* state, never as itself "a change"). As written, the
worked example contradicts its own counting rule by one.

**Resolution hint:** either state explicitly that the seeding deposit sets the initial epoch to 1
(so "0 further changes" reads as epoch 1), or correct the example to "reads 3".

---

## Finding 3 — IFRK2's register count is framed with a different accounting convention than IFLowStorageRK3's own docstring uses

**Type:** clarity
**Severity:** minor
**Confidence:** low

**Locations:**
- PAGE: architecture §4.5: "`IFRK2`... dearer in memory — three spectral registers per field against
  the low-storage scheme's two."
- PAGE: api / Propagator, `IFLowStorageRK3`: "two field registers per field: the state's own array
  plus one accumulator (`stage1`)... The `IntegratorBuffers` a run allocates can hold more than that
  count — for this scheme it adds `nonlinear`... because the count measures the scheme, not the
  solver it is embedded in."
- Same page, `IntegratorBuffers` Fields: IFRK2 allocates `stage1`, `stage2`,
  `velocity_predictor_spectral` — three buffers, none flagged as excluded from the count the way
  `nonlinear` is for RK3.

**Description:** IFLowStorageRK3's own docstring is explicit that its "two" is the textbook
Williamson count (state + one accumulator), and separately warns that the real allocated working set
is larger (`nonlinear` is extra). IFRK2 gets no equivalent caveat, and its Fields list shows three
buffers besides the state array, not two — so a reader who takes the Architecture page's "three
registers... against two" as directly comparable absolute totals (the natural reading, since RK3's
own docstring uses "state + accumulator" as the yardstick for its "two") will size IFRK2 as one
buffer short of what `IntegratorBuffers` actually allocates for it. The *difference* between the
schemes (one extra register) is recoverable and correct under several countings I checked, but the
absolute "three" is not self-evidently the same kind of count as the "two" it is compared against,
and nothing on the page says so.

---

## Finding 4 — `deposit_sample!`'s two-hop staleness window is not cross-referenced from the page most likely to need it

**Type:** clarity
**Severity:** nit
**Confidence:** low

**Locations:**
- PAGE: api / Cache, `deposit_sample!`: "the write alone leaves the slot stale, and a read of it
  throws" — and `particles_modified!`: "A hand-run loop that repositions tracers itself must call
  this, then `record_particle_velocity!` to write the new values, and finally `deposit_sample!`."
- PAGE: api / Particles, `record_particle_velocity!`: describes writing the slot but does not mention
  that a caller driving the loop by hand must additionally call `deposit_sample!` before
  `particle_velocities` becomes readable — that three-call sequence is stated only on the Cache page.

**Description:** A hand-run particle loop that follows only the Particles page's own worked examples
(which never call `deposit_sample!` directly, since `advance!` does it internally) would plausibly
call `record_particle_velocity!` and then read `particle_velocities` and hit a throw, with the fix
documented on a different page than the one describing the write. Not a factual error, just a
one-hop-away caveat that would help where it is used, on `record_particle_velocity!` itself.

---

## Notes on claims verified and found consistent (no finding)

- Dealiasing bands: 2/3 vs √2/3·N vs 2√2/3·κ_Ny all agree across Home, architecture, notation,
  SimulationDomain, and the observables_cache design pages, including the "≈2.8×" mode-count and
  "≈0.94κ_Ny" numerics (both verified by direct computation).
- Transform ledger (§2.3 of observables_cache): the stated per-evaluation breakdown (3 inverse + 3
  inverse + 3 forward per mask evaluation) reproduces the table's "18 inverse, 9 forward" (velocity,
  3-stage RK3) and the scalar-augmented and PhaseShift-doubled cells exactly by arithmetic.
- CFL calibration: κ_maxΔx = 2π/3 ≈ 2.09 and C_CFL ≲ 0.83 → 0.5 for IFLowStorageRK3 both check out
  from y_s = √3.
- ConstantPower's shared "injection = 2A·E_band" formula is correct for both the velocity (with the
  ½ in kinetic energy) and the scalar (full-variance, no ½) — verified by differentiating the
  quadratic observable under linear growth; the shared coefficient is not a copy-paste bug.
- Re_λ ∼ N^{2/3} resolution-scaling claim (SimulationRun, grid mode) verified by chaining
  ε(k,L)-only ⇒ η∝ν^{3/4} ⇒ κ_maxη fixed ⇒ ν∝N^{-4/3} ⇒ Re_λ∝ν^{-1/2}∝N^{2/3}.
- Memory figures: 384 MiB per vector field and 2.3 GiB for six vector-shaped fields at 256³/Float64
  both reproduce from 3N³ reals × 8 bytes.
