# Closure audit — Hat 03: Turbulence theoretician

## 1. `max_speed` defined two incompatible ways — vector magnitude vs largest component

**VERDICT: ABSENT**

Evidence: `src/Observables.jl:159` `max_speed(u) = maximum(norm, u)` (vector-magnitude reduction).
All four originally-quoted sites now agree on that reading: `Observables.jl:128`
(``\max_{\boldsymbol x}\lvert\boldsymbol u\rvert``, "the magnitude is formed one grid point at a
time"); `Cache.jl:23` ("the cached largest flow speed
``\max_{\boldsymbol x}\lvert\boldsymbol u\rvert``"); `docs/src/observables_cache.md:96` ("only the
largest speed ``\max_{\boldsymbol x}\lvert\boldsymbol u\rvert``"); `docs/src/observables_cache.md:345`
("forms the magnitude per grid point in registers"). Searched all of `src/*.jl`,
`docs/src/*.md`, `docs/src/api/*.md`, `docs/ARCHITECTURE.md` for "largest component", "component
magnitude", "maximum velocity component", "max_i" — zero hits.

---

## 2. "No component of the iteration computes k" is false in the configuration the page assumes

**VERDICT: ABSENT**

Evidence: `docs/src/observables_cache.md` §2.4 table row for ``\varepsilon, k, \langle\varphi^2\rangle``
now reads "not surviving: no component of the iteration holds one at its end … (a constant-energy
forcing forms ``k`` mid-step and discards it)" — reworded from "not computed" to the kind/survival
test, exactly the resolution hint. §1.2 adds an explicit paragraph: "One case looks like a
counterexample… Under the default `BandRescaling(over = :total)` the forcing *does* form the
whole-field ``k`` every step… That value is the pre-rescale energy… so it fails the surviving test
below rather than this one." §1.3's "the only number the iteration produces" sentence no longer
appears in the file.

---

## 3. Zeroing the forced band is described as "a step with no forcing at all"

**VERDICT: ABSENT**

Evidence: `src/Forcing.jl:244-247` now reads "the band is zeroed — the closest reachable state — and
the most violent intervention the rescale can make, not the absence of one: it empties the
energy-containing range in a single step, so ``L_{11}``, ``u'`` and ``\mathrm{Re}_\lambda`` are
meaningless for turnovers afterwards." `docs/ARCHITECTURE.md` decision 55 (~line 1763) records the
same fix. Grep for "no forcing at all" in the corpus only matches an unrelated sentence about a
domain with no forcing configured at all (`ARCHITECTURE.md:1384`), not the band-zeroing case.

---

## 4. The `Sreenivasan1995` preset defaults to a constant Sreenivasan (1995) does not give

**VERDICT: PRESENT**

Evidence: `src/phenomenology/Scalings.jl:90,99-101` unchanged — `Sreenivasan1995(; C_K = 1.5)`, and
"Sreenivasan (1995) found it close to universal, a reliable estimate being ``C_K = 1.5 \pm 0.1`` (the
default; Sagaut & Cambon 2018)". The paper's own implied 3-D constant (``\tfrac{55}{18}\times 0.53
\approx 1.6``) is still not what the default carries, and the sentence still attaches the value to
Sreenivasan before crediting Sagaut & Cambon.

---

## 5. The `Lundgren2002` correction changes sign below Re_λ ≈ 34, with no validity floor stated

**VERDICT: ABSENT**

Evidence: `src/phenomenology/StructureFunctions.jl:186-192` now carries a `!!! warning "The
correction has a floor, and it is not cosmetic"` stating "The bracket vanishes at
``\mathrm{Re}_\lambda = (8.45/0.8)^{3/2} \approx 34`` and turns **positive** below it… This is why
the law's `provenance` records a validity floor of ``\mathrm{Re}_\lambda = 50``" — the exact
resolution hint (quote `valid_Reλ`, note the sign change).

---

## 6. The warm-up skewness gate's default floor is a fifth of the marker it claims to test

**VERDICT: ABSENT**

Evidence: `src/SimulationRun.jl:573-577` (`StationarityCriterion` docstring) now states "The default
`0.1` is a floor against a random-phase field… it is a fifth of the ``\lvert S\rvert \approx 0.5`` of
a developed cascade, so clearing it means 'no longer Gaussian', not 'fully developed'. Raise it toward
`0.4`…". `docs/ARCHITECTURE.md` decision 13 (~line 878) matches: "whose default floor is a permissive
one to be raised toward the developed ``\lvert S\rvert \approx 0.5`` when the run must be strict."
Default value itself (`0.1`) is unchanged, but the unqualified "strict" claim is gone from both sites.

---

## 7. Two pages still describe the composed spectrum presets as factory functions

**VERDICT: ABSENT**

Evidence: grep for "factory function" across `src/` and `docs/` returns only
`docs/ARCHITECTURE.md:1768`, itself the decision-log entry recording the rename ("are types, not
factory functions"). `src/Phenomenology.jl:18-22` (module docstring) now reads "…or (for the composed
velocity spectra like `Spectra.Pope2000`) an alias for one specialization of a composed type… so `spec
isa Spectra.Pope2000` holds either way." `docs/ARCHITECTURE.md:481-483` (§4.8) matches: "an alias
naming the `ModelSpectrum` specialization… so `isa` holds on the preset name either way (decision 55)."

---

## 8. Re = 1/ν is asserted absolutely while the default box side is 2π

**VERDICT: PARTIAL**

Evidence: the two originally-quoted docstrings are fixed — `src/Generator.jl:54-56`
(`FlowConditions`) now reads "with the box in units where ``u'=L=1`` this is ``\mathrm{Re}=1/\nu``; on
the shipped defaults (``u'=1``, ``L=2\pi``) the box-scale value is ``2\pi/\nu``"; `src/SimulationRun.jl:135-136`
(`Simulation`, `viscosity` argument) reads "it is ``1/\nu`` only in units where ``u'=L=1``; measure
``\mathrm{Re}_\lambda`` for the run's actual value."

**Surviving class**: `docs/ARCHITECTURE.md:231` (§4.2) still states flatly, with no qualifier,
"the viscosity ``\nu`` (``\mathrm{Re} = 1/\nu``)" — the identical unqualified-absolute-identity defect
the finding flags, on a current-state architecture page. `docs/src/notation.md:47`'s Parameters-table
code column still shows `1 / ν` for `Re` (the prose gestures at "units, not inputs" as the original
finding already credited, so this one is not new, but it still carries no explicit `2π/ν` factor).

---

## 9. E_n ↔ E(κ) is presented as an exact conversion by Δκ

**VERDICT: ABSENT**

Evidence: `src/Observables.jl:314-318` (`integral_scale` docstring) now reads "The cancellation is
exact; what is approximate is the *shell* itself — ``E_n`` is the exact sum over a shell's lattice
modes, and identifying it with ``E(\kappa_n)\Delta\kappa`` is a midpoint quadrature whose error is
largest at the low shells, where the mode count departs most from the continuum ``4\pi\kappa^2``.
Those are also the shells this ratio weights most, so read ``L_{11}`` as resolution-limited at coarse
grids." — the exact half-sentence the resolution hint asked for.
