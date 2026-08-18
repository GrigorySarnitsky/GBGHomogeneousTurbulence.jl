# Hat 08 — Dimensional analysis & normalization

Mechanical verification pass over every formula, factor, and constant in the rendered site:
the ½ in `kinetic_energy`, the 2ϰ in `scalar_dissipation`, Parseval/spectral factors, the
per-shell E_n vs density E(κ) split and its Δκ = 2π/L, the L11 / L22 / L_E π-factors, the
integrating-factor exponent, the CFL constants, and the phase-shift cutoff.

**Verified correct and cross-page consistent** (recorded so the next round need not redo it):
`k = ½⟨|u|²⟩`; `ε = ν⟨|ω|²⟩ = 2ν⟨S:S⟩`; `ε_φ = 2ϰ⟨|∇φ|²⟩` with `⟨φ²⟩` (full-variance pairing,
consistent with Yaglom's `−(2/3)ε_φ r` and with Obukhov–Corrsin's full-variance `C_OC`);
`|κ×û|² = |κ|²|û|² − |κ·û|²`; `C_S = (4/7)√(15/2) ≈ 1.5649` with `⟨tr S³⟩ = (105/8)⟨(∂₁u₁)³⟩`
and `⟨S:S⟩ = (15/2)⟨(∂₁u₁)²⟩` (expanded: `(8/105)(15/2)^{3/2} = (4/7)√(15/2)` exactly);
`L11 = (3π/4)∫(E/κ)/∫E`, `L22 = L11/2`, `L_E = (π/2)∫(E/κ)/∫E = (2/3)L11 = (1/3)(L11+2L22)`;
`u' = √(2k/3)`, `k = (3/2)u'²`, `λ = √(15νu'²/ε)`, `Re_λ = u'²√(15/(νε))`, `η`, `τ_η`;
`G = k/(Lε)^{2/3}`, `ε = (k/G)^{3/2}/L`, `G = (3/2)C_ε^{-2/3}`, and the `C_ε ≈ 0.5 → G ≈ 0.81`
cross-check at `L/L11 ≈ 5`; `κ_max = f(N/2)(2π/L)` with `f = 2/3, 1, 2√2/3` — the phase-shift
cutoff `(√2/3)N(2π/L) = (2√2/3)κ_Ny ≈ 0.94κ_Ny`, `√2` wider, `2.8×` the modes — stated identically
on five surfaces; the quadratic alias-free condition `2κ_max < N`; `κ_maxΔx = 2π/3 ≈ 2.09` and
`C ≲ √3/2.09 ≈ 0.83`; `|R(iy)|² = 1 + y⁴/4`; Williamson `A/B/d` with `Σd = 1` and `c = (0,1/3,3/4)`;
the transform ledger (18/9, 21/18, ×2 for PhaseShift; RK2 14 → 28); the Gaussian-envelope
shell peak at `κ_p/√2`; `k_max_η = 2 ⇒ Δx ≈ 1.05η` and `Re_λ ∼ N^{2/3}`; HouLi `strength ≈ 36 / 16`;
`2AE_band` injection consistent for both fields; the memory arithmetic (384 MiB, 768 MiB,
322.5 MiB, 2.3 GiB).

The findings below are what did **not** survive that pass.

---

## 1. `max_speed`: the whole-vector magnitude or the largest single component? Four surfaces, two answers

- **type**: contradiction · **severity**: blocker · **confidence**: high

**Locations**

- PAGE: api / Observables, "Timestep control" — "The fastest flow speed on the grid,
  $\max_{\boldsymbol{x}}\lvert\boldsymbol{u}(\boldsymbol{x})\rvert$" and "The magnitude is formed per
  grid point in registers and consumed by the maximum immediately".
- PAGE: observables_cache, §2.4 table — "the max_speed reduction takes the largest component
  magnitude directly".
- PAGE: api / Cache, module map — "`max_speed` — the cached maximum velocity component".
- PAGE: observables_cache, §1.2 — "keeps only the largest speed $\max_{\boldsymbol{x}}\lvert\boldsymbol{u}\rvert$".

**Contradicts**: `max_x|u(x)|` (Observables; observables_cache §1.2 and the §2.4 row for the number
itself; `ObservablesCache`'s "the fastest flow speed on the grid") vs `max_{i,x}|u_i(x)|`
(observables_cache §2.4's speed row; the `Cache` module map). Axis: which reduction the number is.

**Description**: The two readings differ by up to √3, and this is the number the adaptive timestep
divides by: `recommended_cfl` states `Δt = C_CFL Δx / max_x|u|` and derives its ceiling from
`κ_max sup|u|`. If the deposited number is the largest *component*, every run takes a step up to 73 %
larger than the documented CFL formula implies, and the "conservative" 0.5 is not conservative by the
stated margin. The `observables_cache` page contradicts itself within two sections, so no surface can
be treated as the authority.

**Resolution hint (advisory)**: settle it against the backend reduction, then make all four sites say
the same thing; if it is the component maximum, the CFL formula and its ≈0.83 derivation need the
matching factor.

---

## 2. The CFL margin: two "loosenesses" that are said to pull the same way pull opposite ways

- **type**: physics · **severity**: major · **confidence**: high

**Locations**

- PAGE: api / Propagator, `recommended_cfl` — "Two loosenesses justify the conservative factor below,
  and they pull the same way"; then "the eigenvalue bound over-estimates the true spectral radius".
- PAGE: api / Observables, `max_speed` note — "The gap is absorbed by the conservative
  `recommended_cfl` ceiling, whose eigenvalue bound over-estimates the true spectral radius."

**Contradicts**: `recommended_cfl` (both loosenesses argue *for* shrinking 0.83 → 0.5) vs `max_speed`
(the eigenvalue over-estimate *compensates* the grid-maximum deficit). Axis: the sign of the second
margin.

**Description**: A grid maximum below the continuum `sup|u|` makes the computed Δt too large — it
argues for a smaller coefficient. An eigenvalue bound that *over*-estimates the spectral radius makes
the derived limit stricter than necessary — that is slack in the safe direction, and it argues the
coefficient could be *larger*. They cannot both justify shrinking the factor. `max_speed` uses the
same fact correctly, as compensation; `recommended_cfl` uses it as reinforcement.

---

## 3. `det S` — materialized by the warm-up gate, or never materialized?

- **type**: contradiction · **severity**: minor · **confidence**: high

**Locations**

- PAGE: observables_cache, §2.4 table — "$\boldsymbol{S}$, $\det\boldsymbol{S}$ … the skewness gate
  of warmup! materializes and discards both".
- PAGE: api / Observables, `derivative_skewness` — "$\langle\det\boldsymbol{S}\rangle$ (the fused
  mapped mean over the pointwise determinant, which materializes no determinant field)".
- PAGE: architecture, §11 (2026-08) — "`derivative_skewness` … stopped materializing its determinant
  field".

**Contradicts**: the cache page's residency row vs the observable's own docstring and the decision
that changed it. Axis: whether a `det S` field exists at any instant.

**Description**: The `det S` half of the §2.4 row is stale against the fused mapped mean. It matters
for the reader the page is written for: the row is the page's own account of what an occasional
diagnostic costs in peak memory, and it over-states that peak by one scalar field. The strain tensor
`S` half of the row is still correct.

---

## 4. The scalar Dirichlet form is written with the physical symbol where its twin writes the spectral one

- **type**: typesetting · **severity**: minor · **confidence**: high

**Locations**

- PAGE: api / Observables, `scalar_dissipation` — "equals $\langle\varphi,\lvert\boldsymbol{\kappa}\rvert^{2}\varphi\rangle$: a $\lvert\boldsymbol{\kappa}\rvert^{2}$-weighted spectral inner product".
- PAGE: api / Observables, `dissipation` — "$\langle\lvert\boldsymbol{\omega}\rvert^{2}\rangle = \langle\hat{\boldsymbol{u}},\lvert\boldsymbol{\kappa}\rvert^{2}\hat{\boldsymbol{u}}\rangle$".

**Contradicts**: `scalar_dissipation`'s `φ` vs `dissipation`'s `û` inside the identical
`|κ|²`-weighted spectral inner product. Axis: field vs its representation, across a variant pair.

**Description**: The operand of a spectral weighted inner product is the coefficient array `φ̂`, not
the physical field `φ` — the docstring's own signature takes `φ̂`. As written the formula reads as a
`|κ|²` multiplication of a physical field, exactly the field/representation conflation the house
category rule guards. Its velocity twin, two docstrings above, writes it correctly, so the pair drifts.

---

## 5. "Of order 10² flops per grid point" for a scalar transform, against the package's own 5/2·N³log₂N³

- **type**: performance · **severity**: nit · **confidence**: medium

**Locations**

- PAGE: observables_cache, §2.3 — "a scalar transform costs of order $10^{2}$ floating-point
  operations per grid point".
- PAGE: architecture, §11 (the compute audit) — "$\tfrac{5}{2} N^3\log_2 N^3$ per scalar transform".

**Contradicts**: 10² per point vs `(5/2)log₂(N³) = 7.5 log₂ N` per point. Axis: the per-point
transform cost.

**Description**: The architecture's own model gives 45 flops per point at N = 64, 60 at N = 256 and
75 at N = 1024 — never near 10² at any grid this package runs. The claim carries the traffic-vs-flops
argument the page is making, so a factor ≈2 overstatement is worth one word ("of order tens"), even
though the qualitative conclusion (transforms dominate the pointwise kernels) is untouched.

---

## 6. The composed spectrum presets: "factory function" in two places, "every preset is a type" in three

- **type**: contradiction · **severity**: minor · **confidence**: high

**Locations**

- PAGE: api / phenomenology / Phenomenology, module docstring — "or (for the composed velocity
  spectra like `Spectra.Pope2000`) a factory function that assembles one".
- PAGE: architecture, §4.8 — "or (for the composed velocity spectra) a factory function that
  assembles a `ModelSpectrum`".
- PAGE: api / phenomenology / Spectra — "Every preset is a type with a keyword constructor"; PAGE:
  phenomenology — "Every preset is a type, so `spec isa Pope2000` … both hold"; PAGE: architecture,
  §11 (2026-08) — "the composite spectrum presets are types, not factory functions".

**Contradicts**: the two module-level maps vs the three current-state statements. Axis: whether a
preset is a type or a function.

**Description**: `Pope2000` / `VonKarman1948` / `Pao1965` are now type aliases for `ModelSpectrum`
specializations, and the decision that made them so is recorded. The `Phenomenology` module map and
ARCHITECTURE §4.8 — the two places a reader meets the pattern first — still describe the retired
factory-function form. §4.8 is a current-state section, not decision-log history.
