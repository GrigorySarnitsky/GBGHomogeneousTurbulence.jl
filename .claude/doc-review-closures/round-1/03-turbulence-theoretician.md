# Closure audit — Hat 03: Turbulence theoretician

One verdict per banked finding, evidence-based against the current corpus only.

---

## 1. `max_speed` defined two incompatible ways

**VERDICT: PARTIAL**

Evidence: `src/Observables.jl:150-152` (`max_speed(u) = maximum(norm, u)`, docstring "the fastest flow
speed … $\max_x|u(x)|$") and `docs/src/observables_cache.md:94-96,340` ("keeps only the largest speed
$\max_x|u|$" / "forms the magnitude per grid point") now consistently read vector magnitude. But
`src/Cache.jl:24-25` (module docstring) still reads "`max_speed` — the cached maximum velocity
component" — the exact site quoted in the original finding, unchanged, still contradicting the
magnitude reading everywhere else.

Surviving class: `src/Cache.jl:24-25` ("the cached maximum velocity component").

---

## 2. "No component of the iteration computes k" false under the default configuration

**VERDICT: PARTIAL**

Evidence: `docs/src/observables_cache.md:86-91` (§1.2) now correctly explains the BandRescaling
counterexample ("the forcing *does* form the whole-field k every step … fails the surviving test
below rather than this [computed] one"). But `docs/src/observables_cache.md:182-183` (§1.3, "It is
the only number the iteration produces") and the §2.4 table row at `docs/src/observables_cache.md:336`
("not computed: no component of the iteration forms them", covering k) remain the flat, unqualified
claim the finding flags, now in direct tension with §1.2's own new paragraph in the same file.

Surviving class: `docs/src/observables_cache.md:182-183` and `:336`.

---

## 3. Zeroing the forced band described as "a step with no forcing at all"

**VERDICT: PARTIAL**

Evidence: `src/Forcing.jl:228-232` is fixed — now reads "the closest reachable state — and the most
violent intervention the rescale can make, not the absence of one … meaningless for turnovers
afterwards," matching the resolution hint. But `docs/ARCHITECTURE.md:1760` (decision log, item 55)
still says "a step with no forcing at all, which the docstring now states" — repeating the misleading
framing and now additionally misdescribing the (corrected) docstring's own content.

Surviving class: `docs/ARCHITECTURE.md:1760` (= `docs/src/architecture.md:1760`, identical file).

---

## 4. `Sreenivasan1995` defaults to a constant Sreenivasan (1995) does not give

**VERDICT: PRESENT**

Evidence: `src/phenomenology/Scalings.jl:88-106` unchanged — `Sreenivasan1995(; C_K = 1.5)` with
docstring "Sreenivasan (1995) found it close to universal, a reliable estimate being $C_K = 1.5 \pm
0.1$ (the default; Sagaut & Cambon 2018)". Same wording, same value, same attribution ordering
flagged in the original finding.

---

## 5. `Lundgren2002` sign flip below Re_λ ≈ 34, no validity floor stated

**VERDICT: ABSENT**

Evidence: `src/phenomenology/StructureFunctions.jl:186-192` now carries `!!! warning "The correction
has a floor, and it is not cosmetic"`, stating the bracket "vanishes at Re_λ = (8.45/0.8)^{3/2} ≈ 34
and turns **positive** below it," that "the law's `provenance` records a validity floor of Re_λ = 50,"
and that `valid_Reλ = (50.0, Inf)` is set at `:87`. Matches the resolution hint exactly.

---

## 6. Warm-up skewness gate's default floor is a fifth of the marker it claims to test

**VERDICT: PARTIAL**

Evidence: `src/SimulationRun.jl:560-564` (`skew_floor` argument doc) now states plainly "The default
`0.1` is a floor against a random-phase field … it is a fifth of the $|S| \approx 0.5$ of a developed
cascade, so clearing it means 'no longer Gaussian', not 'fully developed'. Raise it toward `0.4`…" —
resolves the primary docstring per the resolution hint. But `docs/ARCHITECTURE.md:874-875` (decision
13) still calls it "the strict 'real turbulence yet' gate" with no such qualification, unchanged from
the finding's quote.

Surviving class: `docs/ARCHITECTURE.md:874-875`.

---

## 7. Composed spectrum presets still described as factory functions

**VERDICT: PARTIAL**

Evidence: `docs/ARCHITECTURE.md:479-482` (§4.8) and the Spectra page are fixed — now read "an alias
naming the `ModelSpectrum` specialization … so `isa` holds on the preset name either way (decision
55)". But `src/Phenomenology.jl:20-21` (the module docstring, one of the two sites the finding
explicitly named) is unchanged: "or (for the composed velocity spectra like `Spectra.Pope2000`) a
factory function that assembles one" — directly contradicts `spec isa Pope2000` now holding.

Surviving class: `src/Phenomenology.jl:20-21`.

---

## 8. Re = 1/ν asserted absolutely while default box side is 2π

**VERDICT: ABSENT**

Evidence: `src/Generator.jl:54-56` now reads "with the box in units where $u' = L = 1$ this is
$\mathrm{Re} = 1/\nu$; on the shipped defaults ($u' = 1$, $L = 2\pi$) the box-scale value is
$2\pi/\nu$, and the integral-scale one smaller again." `src/SimulationRun.jl:133-134` likewise: "it is
$1/\nu$ only in units where $u' = L = 1$; measure $\mathrm{Re}_\lambda$ for the run's actual value."
Both docstrings named in the finding now carry the caveat; `docs/src/notation.md:47` already had it.

---

## 9. E_n ↔ E(κ) presented as an exact conversion by Δκ

**VERDICT: ABSENT**

Evidence: `src/Observables.jl:304-309` (`integral_scale`) now states "The cancellation is exact; what
is approximate is the *shell* itself — $E_n$ is the exact sum over a shell's lattice modes, and
identifying it with $E(\kappa_n)\Delta\kappa$ is a midpoint quadrature whose error is largest at the
low shells … read $L_{11}$ as resolution-limited at coarse grids." Matches the resolution hint
exactly; `energy_spectrum`'s own Δκ statement (`:275-277`) is unchanged but no longer the site making
the "cancels cleanly" claim.
