# Closure audit — Hat 08 (Dimensional analysis & normalization)

## 1. `max_speed`: whole-vector magnitude or largest single component?

**VERDICT: PARTIAL**

Three of the four originally-quoted sites now agree on the whole-vector reading
`max_x|u(x)|`: `src/Observables.jl:125` ("The fastest flow speed on the grid,
`max_x|u(x)|`"), `docs/src/observables_cache.md:96` ("keeps only the largest speed
`max_x|u|`"), and the §2.4 table row (`docs/src/observables_cache.md:333`, "the maximum
speed `max_x|u|`"). But the `Cache` module docstring itself — one of the four quoted
sites — is unchanged: `src/Cache.jl:24-25` still reads "`max_speed` — the cached
**maximum velocity component**, the number the timestep choice reads", and this renders
verbatim on `docs/build/api/Cache/index.html` ("the cached maximum velocity component").
The four-site contradiction is now 3-vs-1 instead of 2-vs-2, but the wrong reading
("component") survives at the exact site quoted in the finding.

**Surviving class**: `src/Cache.jl:24-25` (renders to `docs/src/api/Cache.md` /
`docs/build/api/Cache/index.html`) still asserts the component-maximum reading against
the corrected whole-vector reading everywhere else.

---

## 2. The CFL margin: two "loosenesses" said to pull the same way vs opposite ways

**VERDICT: PARTIAL**

`recommended_cfl` (`src/Propagator.jl:526-530`) is now correct: "Two loosenesses sit in
that estimate, and they pull in **opposite** directions... The conservative factor below
exists because the second is not guaranteed to cover the first." But the `max_speed`
note (`src/Observables.jl:130-135`) is unchanged from the finding's quote: "The gap is
absorbed by the conservative `recommended_cfl` ceiling, whose eigenvalue bound
over-estimates the true spectral radius" — still stating the over-estimate as the
mechanism that closes the grid-max gap (compensation), which `recommended_cfl`'s own
corrected text now explicitly denies ("not guaranteed to cover the first"). The two
docstrings still disagree on the sign/role of the second looseness.

**Surviving class**: `src/Observables.jl:132-134` (the `max_speed` docstring's "A grid
maximum, not a continuum supremum" note) retains the pre-fix framing.

---

## 3. `det S` — materialized by the warm-up gate, or never materialized?

**VERDICT: ABSENT**

All three sites now agree `det S` is never materialized. `docs/src/observables_cache.md`
§2.4 table (line ~340): "the skewness gate of `warmup!` materializes `S` and discards it,
while `det S` is formed per point in registers by a fused mapped mean and never
materialized at all". `src/Observables.jl:245`: "`⟨det S⟩` (the fused mapped mean over
the pointwise determinant, which materializes no determinant field)". `docs/ARCHITECTURE.md:1458`:
"`derivative_skewness` diagnostic also stopped materializing its determinant field." No
remaining site claims `det S` is materialized. Searched `src/Observables.jl`,
`docs/src/observables_cache.md`, `docs/ARCHITECTURE.md` for "det" / "materializ" —
consistent everywhere.

---

## 4. Scalar Dirichlet form written with physical symbol where its twin writes spectral

**VERDICT: ABSENT**

`scalar_dissipation` (`src/Observables.jl:196`) now reads
`\langle\hat\varphi,\lvert\boldsymbol{\kappa}\rvert^{2}\hat\varphi\rangle` — the spectral
`φ̂` operand, matching `dissipation`'s `\langle\hat u,\lvert\kappa\rvert^2\hat u\rangle`
form exactly (`src/Observables.jl:104`). Both docstrings now use the spectral-coefficient
symbol inside the `|κ|²`-weighted inner product; no field/representation conflation
remains in either.

---

## 5. "Of order 10² flops per grid point" against the package's own 5/2·N³log₂N³

**VERDICT: ABSENT**

`docs/src/observables_cache.md:298` now reads "a scalar transform costs of order
`10^1`-`10^2` floating-point operations per grid point" (widened range, not a bare 10²).
The architecture's own model gives 45-75 flops/point across the grids this package runs
(N=64..1024), which falls inside the stated `10^1`-`10^2` window — no contradiction with
`docs/ARCHITECTURE.md`'s `5/2 N^3 log_2 N^3` model remains.

---

## 6. Composed spectrum presets: "factory function" vs "every preset is a type"

**VERDICT: PARTIAL**

`docs/ARCHITECTURE.md:480-482` (§4.8, one of the two originally-quoted module-level maps)
is now fixed: "an alias naming the `ModelSpectrum` specialization... so `isa` holds on
the preset name either way (decision 55)". But the `Phenomenology` module docstring
itself — the other originally-quoted site — is unchanged: `src/Phenomenology.jl:20-21`
still reads "or (for the composed velocity spectra like `Spectra.Pope2000`) a **factory
function** that assembles one", and this renders verbatim on
`docs/build/api/phenomenology/Phenomenology/index.html` ("factory function that
assembles one"). This directly contradicts `docs/src/phenomenology.md:11` ("Every preset
is a type") and the decision log (`docs/ARCHITECTURE.md:1762-1763`, "the composite
spectrum presets are types, not factory functions") which remain correct.

**Surviving class**: `src/Phenomenology.jl:20-21` (renders to
`docs/src/api/phenomenology/Phenomenology.md`) still describes the retired
factory-function form.
