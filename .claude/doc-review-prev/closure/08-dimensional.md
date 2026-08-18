# Closure audit — Hat 08 (dimensional analysis & normalization)

## 1. `Li2008`: the three numbers do not satisfy the identity
**VERDICT: ABSENT**

`src/phenomenology/Scalings.jl:134-139` now states the discrepancy explicitly: "but the quoted
`G ≈ 0.9` (box side) and `C_ε ≈ 0.5` (integral scale) sit at *different* lengths (`L/L₁₁ ≈ 5`), so
they must not be substituted into that identity directly — and, being fits to different datasets,
they are not expected to close exactly: carrying `C_ε ≈ 0.5` across at that ratio gives `G ≈ 0.81`
against the quoted `0.9`." Re-derived independently: 1.5·0.5^(-2/3)·(1/5)^(2/3) = 0.8143 ≈ 0.81,
matching the docstring's own number. The identity is no longer presented as closing; the gap is
now the point being made.

---

## 2. The advective-CFL derivation: √3 gap vs 0.83 → 0.5
**VERDICT: ABSENT**

`src/Propagator.jl:519-528` (`recommended_cfl`) no longer contains the word "absorbed" or any claim
that the conservative factor alone accounts for the √3 gap (`grep -n "absorbed" src/Propagator.jl`
→ no hits). The current text: "Two loosenesses justify the conservative factor below, and they pull
the same way" — citing both the grid-max-vs-continuum-sup gap and the loose eigenvalue bound
jointly, without asserting a specific quantitative closure that could be checked and fail.

---

## 3. "Caching costs nothing" vs the recorded +1 pass
**VERDICT: ABSENT**

`src/Propagator.jl` `deposit!` docstring: "so an iteration's transform counts are unchanged by
caching, and its pass counts are unchanged but for one: the maximum-speed reduction runs every
iteration, including under a hand-fixed `Δt` that never reads it." `docs/src/observables_cache.md:183`:
"It costs nothing on the memory axis, nothing on the transform axis, and — with one exception —
nothing on the traffic axis: the closing deposit's maximum-speed reduction is one physical-vector
pass every iteration, paid even by a hand-fixed-`Δt` run that never reads the number." Both pages
now name the exception; the old unqualified "unchanged"/"costs nothing" phrasing is gone
(`grep -n "unchanged by caching"` → no hits).

---

## 4. `C` bound to two different constants (CFL ceiling vs skewness constant)
**VERDICT: ABSENT**

`docs/src/architecture.md:321-322` (§4.3) and `:902-903` (decision log) both now write
`3C_S⟨det S⟩/⟨S:S⟩^{3/2}` with `C_S = (4/7)√(15/2)` — the subscripted symbol throughout, matching
the `derivative_skewness` docstring. `docs/src/notation.md:97` now names the CFL ceiling
`C_{\mathrm{CFL}}` (not bare `C`), so the two concepts no longer share a glyph anywhere found.

---

## 5. `peak_wavenumber` documented as not the peak, reused as `1/L₁₁`
**VERDICT: ABSENT**

`src/SimulationRun.jl:150-152` (the `Simulation` keyword table): "`peak_wavenumber = 2.0` — the
large-scale envelope wavenumber `κ_p` of the initial condition, for the velocity and the scalar
alike (each shell-summed spectrum peaks at `κ_p/√2`)". Lines 156-158 restate the √2 at the
`initial_spectrum` reuse site: "its integral scale set to `1/peak_wavenumber` (which is the
Gaussian envelope's characteristic wavenumber `κ_p`, not the shell-spectrum peak — that sits at
`κ_p/√2`...)". The keyword table now states the √2 at both points of use, exactly the resolution
hint given.

---

## 6. `max_wavenumber`: "zeroed each step" false for `HouLi`
**VERDICT: ABSENT**

`src/SimulationDomain.jl:285-287` (`max_wavenumber`): "The modes above it are zeroed each step by
the two sharp strategies; [`HouLi`](@ref), whose band runs to the Nyquist wavenumber, damps them
instead (to machine epsilon at Nyquist)." The absolute "zeroed" claim is now scoped to the two
sharp strategies and `HouLi`'s damping is stated separately — the exact resolution hint's wording.

---

## 7. `E(κ)` — one glyph for two dimensionally distinct quantities
**VERDICT: ABSENT**

`docs/src/notation.md:72-73` now carries two separate rows: `E(κ)` ("the energy spectrum as a
**density** per unit wavenumber, the `Phenomenology` model form... dimensions `L³T⁻²`") and `E_n`
("the **measured** spectrum: the energy in wavenumber-magnitude shell `n`... dimensions `L²T⁻²`, a
density times `Δκ`"). `src/Observables.jl:271-278` (`energy_spectrum`) reinforces: "What is returned
is a per-shell energy `E_n`... a model spectrum `E(κ)`... is instead a density... the two differ by
the shell width `Δκ = 2π/L` and are not interchangeable." Consistent naming carried through
`integral_scale` (`Observables.jl:297`, "per-shell energies `E_n`").

---

## 8. Pointwise-kernel cost: ten flops vs twenty-four bytes
**VERDICT: ABSENT**

`docs/src/observables_cache.md:42-43`: "a pointwise multiplication over a grid costs **one**
arithmetic operation per point against twenty-four bytes moved in double precision (twelve in
single)." Line 294: "floating-point operations per grid point, a pointwise multiplication of
**order one**." Both instances (§1.1 and §2.3 equivalents) changed from "ten"/"order ten" to
"one"/"order one", consistent with the 24-byte (2 reads + 1 write, double precision) scalar
multiply.

---

## 9. `2.51 GiB` should be `2.52 GiB`
**VERDICT: ABSENT**

`docs/src/architecture.md:1343-1344`: "322.5 MiB at `256³` in double precision... and **2.52 GiB**
at `512³`." 322.5 MiB × 8 = 2580 MiB = 2.5195 GiB, rounds to 2.52. The figure now matches the
correct rounding.
