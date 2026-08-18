# Closure audit — Hat 03: Turbulence theoretician

## 1. `max_speed` defined two incompatible ways

**VERDICT: ABSENT**

`src/Observables.jl:159` — `max_speed(u) = maximum(norm, u)`, docstring at :125-134 states
``\max_{\boldsymbol{x}}\lvert\boldsymbol{u}(\boldsymbol{x})\rvert`` and "the magnitude is formed per grid
point in registers". `src/Cache.jl:24-26` matches (`\max_{\boldsymbol{x}}\lvert\boldsymbol{u}\rvert`).
`docs/src/observables_cache.md:95-96,345` and `docs/ARCHITECTURE.md:381` all use the same vector-magnitude
reading. Searched the whole repo for "cached maximum velocity component", "largest component magnitude",
"component maximum" — zero hits anywhere (src, docs/src, docs/build, ARCHITECTURE.md). The
component-maximum reading is gone from every site the finding named.

---

## 2. "No component of the iteration computes k" false under the default configuration

**VERDICT: ABSENT**

`docs/src/observables_cache.md:339` now: "not surviving: no component of the iteration **holds one at
its end**; each is one reduction at an observation (a constant-energy forcing forms `k` mid-step and
discards it)" — restated on the survival test, not "not computed". §1.3 (line ~182-184) now reads: "It
is the only number the iteration produces *and still holds at its end*, so it is the only number the
cache holds; ... A constant-energy forcing does form `k` mid-step, but discards it before the end — the
qualification §1.2 draws." This is exactly the resolution hint's fix (kind/survival test, not "not
computed"), and it no longer contradicts `BandRescaling`'s mid-step `kinetic_energy` use.

---

## 3. Zeroing the forced band described as "a step with no forcing at all"

**VERDICT: ABSENT**

`src/Forcing.jl:244-247`: "the band is zeroed — the closest reachable state — and the most violent
intervention the rescale can make, not the absence of one: it empties the energy-containing range in a
single step, so `L_{11}`, `u'` and `Re_λ` are meaningless for turnovers afterwards." `docs/ARCHITECTURE.md`
decision 54 (~line 1763-1764) matches: "the docstring states what that is — the most violent
intervention the strategy can make, not the absence of one." The unrelated "carries no forcing at all"
at ARCHITECTURE.md:1384 is about an unforced *domain* in the frame-ledger discussion, a different
referent, not a recurrence of the defect.

---

## 4. `Sreenivasan1995` preset defaults to a constant Sreenivasan (1995) does not give

**VERDICT: PRESENT**

`src/phenomenology/Scalings.jl:90-96` unchanged: `Sreenivasan1995(; C_K = 1.5)`, docstring: "Sreenivasan
(1995) found it close to universal, a reliable estimate being `C_K = 1.5 ± 0.1` (the default; Sagaut &
Cambon 2018)" — the value is still attached to the Sreenivasan citation in the lead clause with Sagaut &
Cambon only parenthetical, and the default is still 1.5, not the ≈1.6 the finding computes from
Sreenivasan's reported 1D constant. No `valid_Reλ`-style caveat or explicit source separation added.

---

## 5. `Lundgren2002` correction changes sign below Re_λ≈34, no validity floor stated

**VERDICT: ABSENT**

`src/phenomenology/StructureFunctions.jl:170` sets `valid_Reλ = (50.0, Inf)` on the `Reference`, and the
docstring (:186-192) now carries an explicit `!!! warning "The correction has a floor, and it is not
cosmetic"` block: "The bracket vanishes at `Re_λ = (8.45/0.8)^{3/2} ≈ 34` and turns **positive** below
it ... Even at `Re_λ = 100` the correction still removes about half the coefficient. This is why the
law's `provenance` records a validity floor of `Re_λ = 50`." Matches the resolution hint exactly.

---

## 6. Warm-up skewness gate default floor is a fifth of the marker it claims to test

**VERDICT: ABSENT**

`src/SimulationRun.jl:573-577`: "The default `0.1` is a **floor against a random-phase field** ... it is
a fifth of the `|S| ≈ 0.5` of a developed cascade, so clearing it means 'no longer Gaussian', not 'fully
developed'. Raise it toward `0.4` when the run's statistics depend on the cascade being mature."
`docs/ARCHITECTURE.md` decision 13 (~line 877-879) matches: "whose default floor is a permissive one to
be raised toward the developed `|S| ≈ 0.5` when the run must be strict." Default value (0.1) unchanged,
but the claim now matches the code instead of contradicting it.

---

## 7. Composed spectrum presets still described as factory functions on two pages

**VERDICT: ABSENT**

`src/Phenomenology.jl:20-22`: "...or (for the composed velocity spectra like `Spectra.Pope2000`) an
alias for one specialization of a composed type, with a keyword constructor that fills in the published
fit — so `spec isa Spectra.Pope2000` holds either way." `docs/ARCHITECTURE.md` §4.8 (~line 481-483):
"...or (for the composed velocity spectra) an alias naming the `ModelSpectrum` specialization that
carries its two roll-off factors, so `isa` holds on the preset name either way (decision 55)." Code
confirms: `src/phenomenology/Spectra.jl:308` — `const Pope2000 = ModelSpectrum{PopeLargeScale,
PopeDissipation}`, a genuine type alias. "factory function" no longer appears describing these presets
anywhere in src/ or ARCHITECTURE.md (only the historical decision-54/55 log entries use the phrase to
describe what changed).

---

## 8. Re = 1/ν asserted absolutely while the default box side is 2π

**VERDICT: ABSENT**

`src/Generator.jl:53-56` (`FlowConditions` docstring): "...with the box in units where `u' = L = 1` this
is `Re = 1/ν`; on the shipped defaults (`u' = 1`, `L = 2π`) the box-scale value is `2π/ν`, and the
integral-scale one smaller again." `src/SimulationRun.jl:135-136`: "`viscosity` — ... (it is `1/ν` only
in units where `u' = L = 1`; measure `Re_λ` for the run's actual value)". `docs/src/notation.md:47`
already carried the "units, not inputs" qualifier and is unchanged. All three sites the finding named now
state the same qualified relation.

---

## 9. E_n ↔ E(κ) presented as an exact conversion by Δκ

**VERDICT: ABSENT**

`src/Observables.jl:314-317` (`integral_scale` docstring): "...whose common shell width cancels in the
ratio, so no conversion between the two is needed here. The cancellation is exact; what is approximate is
the *shell* itself — `E_n` is the exact sum over a shell's lattice modes, and identifying it with
`E(κ_n)Δκ` is a midpoint quadrature whose error is largest at the low shells, where the mode count departs
most from the continuum `4πκ²`. Those are also the shells this ratio weights most, so read `L_{11}` as
resolution-limited at coarse grids." Matches the resolution hint exactly — the midpoint-quadrature caveat
is now stated where the finding said it was missing.
