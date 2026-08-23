# Closure — hat 03: TURBULENCE THEORETICIAN

## 1. `Li2008` attributes this package's own fit to Li et al. (2008)

**VERDICT: ABSENT**

`src/phenomenology/Scalings.jl:132` now reads: "The value is this package's own reduction of the
Johns Hopkins Turbulence Database (JHTDB) forced-isotropic dataset (Re_λ ≈ 433) and consistent with
higher-Reynolds-number periodic-box DNS." This directly disambiguates data source (Li et al. 2008,
the JHTDB paper) from the fit (ours). `SimulationRun.jl:103` links `Li2008` (`@ref`) before citing
"≈ 0.9; Li et al. 2008" at line 106, so a reader following the link sees the true provenance. Searched
for `own reduction|own fit|package's own` across `src/`, `docs/src/`, `ARCHITECTURE.md` — only the one
instance, no other misattributed own-fit found. `ARCHITECTURE.md:1871`'s `§References` entry still
labels it "the box-normalized dissipation law `Li2008`" but is consistent with the now-clarified
docstring, not contradicting it.

---

## 2. Grid mode's `κ_max_η` treats `HouLi`'s merely-damped band as clean signal

**VERDICT: ABSENT**

`SimulationRun.jl:116-121` now quotes the exact numbers the finding asked for: "The gap is not
cosmetic: f = 1 puts η ≈ 0.64 Δx at κ_max_η = 2 (against 0.96 Δx for 2/3), and since ν ∝ f^{-4/3},
`HouLi` is handed a Re_λ about 31% higher on the same grid at the same nominal criterion — raise
`κ_max_η` when comparing across strategies." This is exactly the resolution_hint ("quote η/Δx per
strategy"), landed verbatim with both numbers.

---

## 3. Grid mode is self-consistent only under a k-clamping forcing, and only `BandRescaling` says so

**VERDICT: ABSENT**

`SimulationRun.jl:122-125` (the grid-mode paragraph itself, not only the `BandRescaling` docstring)
now states: "The choice is self-consistent only if the run actually holds k at `kinetic_energy`, which
the front door's `BandRescaling(over = :total)` guarantees and `:band` does not — override
`velocity_forcing` with a forcing that lets k float and the ν grid mode picked no longer matches the
run." The trap is now named at the site the finding flagged as silent.

---

## 4. `VonKarman1948` does not integrate to k, and the page does not say so

**VERDICT: PRESENT**

`src/phenomenology/Spectra.jl:362-364` (the `VonKarman1948` docstring) is unchanged in substance:
"`c_L` fixes where the spectrum peaks and is a shape parameter of this form rather than a
normalization — unlike `PopeLargeScale`'s `c_L`, no energy condition determines it, and the default
`1.0` is the conventional choice." No offset number (the ≈0.65k–0.88k claimed by the finding) is
given anywhere for `VonKarman1948`. The only quantified offset in the file (`large_scale_length`,
lines 105-108: 0.42k / 0.57k) is Pope's cross-length-substitution error, a different scenario, not
`VonKarman1948`'s intrinsic non-normalization at its own correct length `L₁₁`.

---

## 5. The assumed integral scale `1/envelope_wavenumber` is not the seeded field's `L₁₁`

**VERDICT: PRESENT**

`SimulationRun.jl:173` still asserts "the integral scale as `1/envelope_wavenumber`" and
`SimulationRun.jl:285` still computes `integral_scale = inv(envelope_wavenumber)`. The Gaussian
envelope in `State.jl:74-79` is unchanged (`exp(-|κ|²/κ_p²)` on amplitudes, shell-summed spectrum
`∝ κ²exp(-2κ²/κ_p²)`), whose true `L₁₁ = 3.76/κ_p` per the package's own `integral_scale` formula —
not `1/κ_p`. No reconciling text or renormalization was added.

---

## 6. `envelope_wavenumber` is said both to feed and not to feed the `initial_spectrum` branch

**VERDICT: PRESENT**

Both sentences stand verbatim. `SimulationRun.jl:166-167`: "it also sets the integral scale in the
assumed state `initial_spectrum` reads." `State.jl:79` (and the identical text in `random_scalar_spectral!`,
`State.jl:160`): "The `envelope_wavenumber` setting has no effect in the `initial_spectrum` branch
below." Neither sentence was qualified with the resolution_hint's suggested "no effect *on this
call*; the front door uses it to build the spectrum function" or any equivalent cross-layer pointer.

---

## 7. The resolution criterion is silent about the scalar's Batchelor scale

**VERDICT: PRESENT**

Searched `Batchelor` across `src/SimulationRun.jl`, `src/Generator.jl`, `src/Observables.jl` — no
hits. `SimulationRun.jl:155` (`schmidt = 1.0`) and `Generator.jl:52-82` (`FlowConditions`) still give
no bound or caveat on `schmidt`, and the grid-mode `κ_max_η` paragraph (`SimulationRun.jl:101-126`)
still says nothing about the scalar's Batchelor scale `η_B = η/√Sc` or that the criterion covers the
velocity field only.

---

## 8. Under `over = :band` the claim "k still measures the flow" overstates what is left free

**VERDICT: PRESENT**

`Forcing.jl:246-248` is unchanged: "The band's energy is then set by the forcing rather than by the
flow, while k still measures the flow itself." Default `lowest_shell = 1`, `highest_shell = 2`
unchanged (`Forcing.jl:100-102`, `273`, `319`). `ARCHITECTURE.md:1772` still reads "under `:band` the
band is the artifact and k is a measurable of the flow." The suggested softening ("k retains its
out-of-band fluctuation") was not applied anywhere.

---

## 9. The glossary binds ω to a producer verb, and leaves Re_λ the one scale without its formula

**VERDICT: PRESENT**

`docs/src/notation.md:31` still lists ω's Code column as `` [`vorticity_physical!`](@ref …) `` (the
verb), not `Cache.vorticity_physical` (the storage), unlike the neighboring rows' pattern. Line 89
still gives Re_λ's Meaning column as "Taylor-microscale Reynolds number, measured from the flow
state," with no defining expression, while every other row in the Derived-scales table (u', L₁₁, η,
τ_η, λ) carries its formula inline (lines 84-88, 90).
