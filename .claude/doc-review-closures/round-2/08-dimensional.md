# Closure audit — Hat 08 (Dimensional analysis & normalization)

## 1. `max_speed`: whole-vector magnitude vs largest component

**VERDICT: ABSENT**

Evidence: `src/Observables.jl:159` `max_speed(u) = maximum(norm, u)` — whole-vector norm, confirming
the whole-vector reading. All four flagged surfaces now agree: `src/Observables.jl:125-131` ("the
fastest flow speed on the grid, `max_x|u(x)|`"); `docs/src/observables_cache.md:345` ("the speed
`|u|` … `max_speed` forms the magnitude per grid point … consumes it immediately"); `src/Cache.jl:24`
("the cached largest flow speed `max_x|u|`"); `docs/src/api/Cache.md:22` (no formula, no longer
"velocity component"). Grepped `docs/src/`, `src/`, `docs/ARCHITECTURE.md` for "largest component" /
"component magnitude" / "velocity component" — zero hits. No surface states the per-component
reading anywhere in the corpus.

---

## 2. CFL margin: the two loosenesses pulling opposite ways vs "the same way"

**VERDICT: ABSENT**

Evidence: `src/Propagator.jl:527-534` (`recommended_cfl`) now reads "Two loosenesses sit in that
estimate, and they pull in **opposite** directions" and correctly attributes: the grid-max
under-estimate makes the step too long, the eigenvalue over-estimate makes the ceiling too small —
"the conservative factor below exists because the second is not guaranteed to cover the first."
`src/Observables.jl:132-138` (`max_speed` note) is consistent: "not guaranteed to cover the first."
Grepped for "pull the same way" / "absorbed by the conservative" across `docs/src/`, `src/` — only
one surface (`Propagator.jl`) discusses it now, and it states the physically correct direction.

---

## 3. `det S`: materialized by warm-up gate vs never materialized

**VERDICT: ABSENT**

Evidence: `docs/src/observables_cache.md:344` now reads "the skewness gate of `warmup!` materializes
`S` and discards it, while `det S` is formed per point in registers by a fused mapped mean and never
materialized at all" — matches `src/Observables.jl:252-253` ("the fused mapped mean over the
pointwise determinant, which materializes no determinant field") and the architecture decision log.
All three surfaces now agree: `S` is materialized, `det S` never is.

---

## 4. Scalar Dirichlet form: physical `φ` vs spectral `φ̂` inside the `|κ|²`-weighted inner product

**VERDICT: ABSENT**

Evidence: `src/Observables.jl:203` now reads `⟨φ̂,|κ|²φ̂⟩` (spectral hat symbol), matching its
velocity twin `dissipation`'s `⟨û,|κ|²û⟩` (`src/Observables.jl:117`). Confirmed identically rendered
in `docs/build/api/Observables/index.html`: `\langle\hat\varphi,\lvert\boldsymbol{\kappa}\rvert^{2}\hat\varphi\rangle`.
No remaining instance of the bare physical `φ` inside that inner product.

---

## 5. "Order 10² flops per grid point" vs the package's own `(5/2)N³log₂N³` (45–75 flops/point)

**VERDICT: ABSENT**

Evidence: `docs/src/observables_cache.md:303-304` now reads "a scalar transform costs of order
`10¹`–`10²` floating-point operations per grid point" — a range, not a fixed `10²`. The
architecture's own model (`docs/src/architecture.md:1259`, `(5/2)N³log₂N³` per scalar transform)
gives 45–75 flops/point across the package's grid sizes, which falls inside the now-stated
`10¹`–`10²` range.

---

## 6. Composed spectrum presets: "factory function" (module map / §4.8) vs "type" (three other surfaces)

**VERDICT: ABSENT**

Evidence: `src/Phenomenology.jl:20` now reads "an alias for one specialization of a composed type,
with a keyword constructor that fills in the published fit — so `spec isa Spectra.Pope2000` holds
either way." `docs/ARCHITECTURE.md:482` (§4.8, current-state) now reads "an alias naming the
`ModelSpectrum` specialization that carries its two roll-off factors, so `isa` holds on the preset
name either way (decision 55)." Grepped for "factory function" across `src/`, `docs/src/`,
`docs/ARCHITECTURE.md`: the only remaining hit is the decision-log entry (§11, `docs/ARCHITECTURE.md:1768`)
describing the *retired* form historically — correct and expected there. All current-state surfaces
now agree the presets are types/aliases.
