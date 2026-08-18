# Panel hat 03 — Turbulence theoretician

Fresh-eyed audit of the rendered site (`manuscript-full.md`) against established turbulence theory and
against itself. Collect-only; no edits made. Verified by expansion where possible: the Betchov constant
(`C_S = 4/7·√(15/2)` ⇒ `⟨tr S³⟩ = 105/8 ⟨(∂₁u₁)³⟩`, `⟨S:S⟩ = 15/2 ⟨(∂₁u₁)²⟩` — consistent), the
`G = 3/2 C_ε^{-2/3}` identity and its `G ≈ 0.81` cross-carry, `L_E = 2/3 L₁₁`, the K62/She–Lévêque
`ζ₃ = 1`, the Yaglom half/full-variance factor 2, `C_OC` 1D↔3D (0.4 → 0.67), the `2κ_max < N`
alias-free condition, `2√2/3 κ_Ny ≈ 0.94`, the `C_CFL ≲ 0.83` eigenvalue bound, the RK3/RK2 stage
formulas and `|R(iy)|² = 1 + y⁴/4`, and the `κ_p/√2` shell-spectrum peak. Those all check out; what
follows is what does not.

---

## 1. `max_speed` is defined two incompatible ways — vector magnitude vs largest component

- **type**: contradiction
- **severity**: major
- **confidence**: high

**Locations**

- PAGE: api / Observables, "Timestep control":
  > "The fastest flow speed on the grid, $\max_{\boldsymbol{x}}\lvert\boldsymbol{u}(\boldsymbol{x})\rvert$"
  and "The magnitude is formed per grid point in registers and consumed by the maximum immediately".
- PAGE: observables_cache, §2.4 (table, row "the speed $\lvert\boldsymbol{u}\rvert$"):
  > "the max_speed reduction takes the largest component magnitude directly"
- PAGE: api / Cache, module docstring:
  > "`max_speed` — the cached maximum velocity component"
- PAGE: observables_cache, §1.2:
  > "keeps only the largest speed $\max_{\boldsymbol{x}}\lvert\boldsymbol{u}\rvert$ — the advective-CFL bound"

**Contradicts**: the same quantity is `max_x |u|` (a vector magnitude) in Observables, notation
(`Δt = C_CFL Δx / max_x|u|`) and cache §1.2, but `max_i max_x |u_i|` (a component maximum) in cache §2.4
and the Cache module map. Axis: which scalar the reduction returns.

**Description**: The two differ by up to √3 in three dimensions, and the CFL derivation in
`recommended_cfl` is built on the magnitude ("advective eigenvalues … of magnitude up to
$\kappa_{\max}\sup\lvert\boldsymbol{u}\rvert$"). A reader calibrating their own `cfl` override, or
reproducing the stability margin, gets a timestep up to √3 off. Exactly one of the two readings can be
what the reduction computes.

**Resolution hint**: pick the reading the code implements, then sweep all four sites plus the notation
table; if it really is the component maximum, the `recommended_cfl` eigenvalue argument needs its own
factor stated.

---

## 2. "No component of the iteration computes k" is false in the configuration the page assumes

- **type**: contradiction
- **severity**: major
- **confidence**: high

**Locations**

- PAGE: observables_cache, §2.4 (table row):
  > "$\varepsilon$, $k$, $\langle\varphi^{2}\rangle$ … not computed: no component of the iteration forms them"
- PAGE: observables_cache, §1.3:
  > "It is the only number the iteration produces, so it is the only number the cache holds"
- PAGE: observables_cache, §2 (the configuration under discussion): "the default rescaling velocity forcing"
- PAGE: architecture, §11 decision (2026-07, optimality audit):
  > "three blocking readbacks per step — the CFL speed bound, and `BandRescaling`'s band and whole-field observables"
- PAGE: api / Forcing, `BandRescaling`:
  > "the kinetic energy $\tfrac{1}{2}\langle\lvert\boldsymbol{u}\rvert^{2}\rangle$ (`kinetic_energy`) for the velocity"

**Contradicts**: the cache page says the iteration forms no `k` and produces exactly one number; the
architecture's synchronization ledger says the default forcing reads back a band energy *and* a
whole-field energy every step — and `BandRescaling`'s held whole-field observable for a velocity *is* `k`.

**Description**: Under the default `BandRescaling(over = :total)` — the very configuration §2 fixes —
the iteration computes the whole-field kinetic energy every step. The stated exclusion reason ("not
computed") is therefore wrong for `k`; `max_speed` is not "the only number the iteration produces". A
defensible reason exists (the forcing's `k` is measured pre-rescale, so it belongs to no deposited
$t_n$), but it is not the reason the page gives.

**Resolution hint**: restate the exclusion on the kind/survival test (a pre-projection value dates to no
deposited state), rather than on "not computed".

---

## 3. Zeroing the forced band is described as "a step with no forcing at all"

- **type**: physics
- **severity**: major
- **confidence**: high

**Locations**

- PAGE: api / Forcing, `BandRescaling`, `:total` bullet:
  > "the band is zeroed — the closest reachable state, and a step with no forcing at all"
- PAGE: architecture, §11 decision (2026-08, `over` required):
  > "`:total` zeroes the band when the out-of-band energy alone exceeds `target`, a step with no forcing at all"

**Description**: Setting the shells 1–2 amplitude to zero is the *maximal* intervention available to the
rescale (factor 0), not the absence of one — no forcing is factor 1. Physically it deletes the entire
energy-containing range in a single step, decapitating the cascade and invalidating every large-scale
diagnostic ($L_{11}$, $u'$, $\mathrm{Re}_\lambda$) for several turnovers. "Closest reachable state" is
correct; "no forcing at all" is not, and it reads as reassurance where a warning belongs.

**Resolution hint**: say "the band is emptied — the strongest damping the rescale can apply", and warn
that the large scales are destroyed for the following turnovers.

---

## 4. The `Sreenivasan1995` preset defaults to a constant Sreenivasan (1995) does not give

- **type**: citation
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE: api / phenomenology / Scalings, `Sreenivasan1995`:
  > "Sreenivasan (1995) found it close to universal, a reliable estimate being $C_K = 1.5 \pm 0.1$ (the default; Sagaut & Cambon 2018)"

**Description**: Sreenivasan (1995) reports the *one-dimensional* longitudinal constant
$C_1 \approx 0.53 \pm 0.055$; the three-dimensional constant that follows from it is
$C_K = \tfrac{55}{18}C_1 \approx 1.6$, not 1.5. The author-year handle promises the paper's fit while
the default is another source's rounder number, and the docstring's own sentence attaches the value to
Sreenivasan before crediting Sagaut & Cambon parenthetically.

**Resolution hint**: either default to the paper's implied $\approx 1.6$, or state explicitly that the
paper fixes universality while the coefficient is Sagaut & Cambon's consensus value.

---

## 5. The `Lundgren2002` correction changes sign below $\mathrm{Re}_\lambda \approx 34$, with no validity floor stated

- **type**: physics
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE: api / phenomenology / StructureFunctions, `Lundgren2002`:
  > "$D_{LLL}(r) = -\Bigl(\tfrac{4}{5} - \tfrac{8.45}{\mathrm{Re}_\lambda^{2/3}}\Bigr)\varepsilon r$"

**Description**: The bracket vanishes at $\mathrm{Re}_\lambda = (8.45/0.8)^{3/2} \approx 34$ and turns
positive below it — a third-order longitudinal structure function of the wrong sign, i.e. an inverse
energy flux. At $\mathrm{Re}_\lambda = 100$ the correction still removes half the coefficient. The
rendered docstring states no lower validity bound, although `Reference` carries a `valid_Reλ` field
precisely for this; a DNS user spinning up a 64³ box sits in the danger zone.

**Resolution hint**: quote the law's `valid_Reλ` floor in the docstring and note the sign change below it.

---

## 6. The warm-up skewness gate's default floor is a fifth of the marker it claims to test

- **type**: method
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE: api / SimulationRun, `StationarityCriterion`: signature default `skew_floor = 0.1`, with
  > "only a developed cascade reaches $S \approx -0.5$"
- PAGE: architecture, §11 (2026-07 warm-up decision):
  > "the strict \"real turbulence yet\" gate ($S$ runs from $0$ toward $\approx -0.5$)"

**Description**: A run passes the "decisive" and "strict" gate at $\lvert S\rvert \ge 0.1$ — 20 % of the
developed value, a state a random-phase field reaches long before the cascade is established. Either the
floor is loose for the claim made for it, or the claim overstates what the default enforces. Both the
docstring and the decision log call the gate strict without qualifying the default.

**Resolution hint**: raise the default toward $\approx 0.3$–0.4, or say plainly that 0.1 is a permissive
"non-Gaussian yet" screen and the physical marker is 0.5.

---

## 7. Two pages still describe the composed spectrum presets as factory functions

- **type**: contradiction
- **severity**: minor
- **confidence**: high

**Locations**

- PAGE: api / phenomenology / Phenomenology, module docstring:
  > "(for the composed velocity spectra like `Spectra.Pope2000`) a factory function that assembles one"
- PAGE: architecture, §4.8:
  > "or (for the composed velocity spectra) a factory function that assembles a `ModelSpectrum`"
- PAGE: api / phenomenology / Spectra: "Every preset is a type with a keyword constructor"; PAGE:
  architecture, §11 (2026-08): "They are now type aliases".

**Contradicts**: the current state (every preset a type, `spec isa Pope2000` holds) against two
current-state sections still promising a factory function. Axis: what kind of object a preset is.

**Description**: The type-alias change is recorded in the log and reflected on the Spectra and
phenomenology overview pages, but the `Phenomenology` module map and ARCHITECTURE §4.8 — both
current-state surfaces, not history — were missed. A reader of the module map still expects
`Pope2000` to be a function and `isa` to fail.

---

## 8. $\mathrm{Re} = 1/\nu$ is asserted absolutely while the default box side is $2\pi$

- **type**: dimensional
- **severity**: nit
- **confidence**: medium

**Locations**

- PAGE: notation, Parameters: "$\mathrm{Re}$ | Reynolds number, set through the viscosity on the box's
  order-one reference scales"; code column "1 / ν".
- PAGE: api / Generator, `FlowConditions`: "the Reynolds number is $\mathrm{Re} = 1/\nu$".
- PAGE: api / SimulationRun, `Simulation`: "`side_length = 2π`", "`kinetic_energy = 1.5` … $u' = 1$".

**Description**: With the shipped defaults ($u' = 1$, $L = 2\pi$) the box-scale Reynolds number is
$2\pi/\nu$, and the integral-scale one is smaller again — the same pages give $L/L_{11} \approx 5$.
$\mathrm{Re} = 1/\nu$ holds only under an implicit $U = L = 1$, which the notation entry gestures at
("units, not inputs") but the two docstrings state flatly. Since $\nu$ is the one control a user sets,
the factor matters when comparing against a literature $\mathrm{Re}$.

**Resolution hint**: write $\mathrm{Re} = UL/\nu$ with $U = u'$, $L$ the side, and note that the
defaults make it $2\pi/\nu$; keep $1/\nu$ as the nominal control.

---

## 9. $E_n \leftrightarrow E(\kappa)$ is presented as an exact conversion by $\Delta\kappa$

- **type**: category
- **severity**: nit
- **confidence**: medium

**Locations**

- PAGE: api / Observables, `energy_spectrum`:
  > "the two differ by the shell width $\Delta\kappa = 2\pi/L$ and are not interchangeable"
- PAGE: api / Observables, `integral_scale`:
  > "whose common shell width cancels in the ratio, so no conversion between the two is needed here"

**Description**: $E_n = \int_{\text{shell}} E\,\mathrm{d}\kappa$ exactly; $E_n = E(\kappa_n)\Delta\kappa$
only as a midpoint Riemann sum. At the low shells that dominate $L_{11}$ (the $\int E/\kappa$ integrand
is weighted to small $\kappa$) the lattice mode count deviates strongly from the continuum
$4\pi\kappa^2$, so the "shell width cancels" argument carries a real discretization bias, not merely a
change of units. The distinction between the shell energy and the density is otherwise handled
carefully throughout — this is the one place the conversion is claimed clean.

**Resolution hint**: add half a sentence that the identification is a midpoint quadrature, biased at the
first few shells.
