# Closure audit — Hat 08 (Dimensional analysis & normalization)

## 1. `max_speed`: whole-vector magnitude vs largest single component

**VERDICT: ABSENT**

Evidence: `src/Observables.jl:159` `max_speed(u) = maximum(norm, u)` (vector norm), and its docstring
(line 125) states `max_x|u(x)|` with no per-component reading. Grepped all four originally-quoted
surfaces: `docs/src/observables_cache.md:96` ("keeps only the largest speed
`max_x|u|`"), `:345` (magnitude formed per grid point, never per-component), `docs/src/api/Cache.md:22`
and `src/Cache.jl:23` ("the cached largest flow speed `max_x|u|`"). Searched
`grep -rn "largest component\|maximum velocity component" src/ docs/src/ docs/ARCHITECTURE.md` — zero
hits anywhere in the corpus. All four sites now agree: whole-vector magnitude, not a component.

---

## 2. The CFL margin: the two "loosenesses" pulling opposite ways

**VERDICT: ABSENT**

Evidence: `src/Propagator.jl:527-534` (`recommended_cfl`) now reads "Two loosenesses sit in that
estimate, and they pull in **opposite** directions" — the grid-max deficit makes the step too long,
the eigenvalue over-estimate makes the ceiling too small, "the second is not guaranteed to cover the
first." `src/Observables.jl` `max_speed` docstring (note block) says the same thing: the ceiling
"pulls the other way... but the two are independent." `grep -n "pull the same way\|absorbed by the
conservative"` across `src/`, `docs/src/`, `docs/ARCHITECTURE.md` returns nothing — the contradictory
"reinforcement" framing is gone from both sites.

---

## 3. `det S` — materialized by the warm-up gate, or never materialized?

**VERDICT: ABSENT**

Evidence: `docs/src/observables_cache.md:344` now reads "the skewness gate of `warmup!` materializes
`S` and discards it, while `det S` is formed per point in registers by a fused mapped mean and never
materialized at all" — matching `src/Observables.jl:252` ("the fused mapped mean over the pointwise
determinant, which materializes no determinant field") and `docs/ARCHITECTURE.md:1462` ("stopped
materializing its determinant field"). All three now distinguish `S` (materialized) from `det S`
(never materialized).

---

## 4. Scalar Dirichlet form written with physical `φ` where velocity twin writes spectral `û`

**VERDICT: ABSENT**

Evidence: `src/Observables.jl:203-204` now reads "equals `⟨φ̂, |κ|²φ̂⟩`" (spectral coefficient,
matching the `φ̂` argument bound in the signature), not the physical `φ`. This mirrors `dissipation`'s
`⟨û, |κ|²û⟩` two docstrings above. The field/representation conflation the finding flagged is gone;
both variants of the pair now use the spectral-representation symbol inside the weighted inner product.

---

## 5. "Of order 10² flops per grid point" vs the package's own 5/2·N³log₂N³

**VERDICT: ABSENT**

Evidence: `docs/src/observables_cache.md:302-303` now reads "a scalar transform costs of order
`10¹`–`10²` floating-point operations per grid point" — a range, not a bare `10²`. The architecture's
own model (`(5/2)log₂(N³)` per point) gives 45/60/75 flops/point at N=64/256/1024, all falling inside
the stated `10¹`–`10²` range; the prior single-decade overstatement is corrected.

---

## 6. Composed spectrum presets: "factory function" vs "every preset is a type"

**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:482` and `src/Phenomenology.jl:20` (the two sites the finding quoted
as still describing the retired factory-function form) now both read "an alias naming the
`ModelSpectrum` specialization" / "an alias for one specialization of a composed type" — not "a
factory function that assembles one". This matches `docs/src/phenomenology.md:11` ("Every preset is a
type") and the decision log at `docs/ARCHITECTURE.md:1767-1768` ("the composite spectrum presets are
types, not factory functions"). `grep -rn "factory function"` across `src/`, `docs/src/`,
`docs/ARCHITECTURE.md` returns no remaining hits describing the spectrum presets this way.
