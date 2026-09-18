# Hat 14 — Dimensional analysis & normalization

Mechanical audit of every formula, normalization factor, and numerical constant in the rendered
site, checked for dimensional consistency and for agreement between pages.

**Verified clean** (no finding raised): the ½ in `kinetic_energy` and its absence in
`scalar_variance` / `E_φ`; the 2ϰ in `scalar_dissipation` and Yaglom's resulting −2/3 coefficient;
ε = ν⟨|ω|²⟩ = 2ν⟨S_ijS_ij⟩ and the Dirichlet route ⟨û,|κ|²û⟩; the Betchov constant
C_S = (4/7)√(15/2) ≈ 1.5649 and its two source relations (105/8, 15/2) — re-derived, exact;
E_n vs E(κ) and Δκ = 2π/L everywhere it appears; L₁₁ = (3π/4)∫(E/κ)/∫E, L₂₂ = L₁₁/2,
L_E = (π/2)(…) = ⅔L₁₁ = ⅓(L₁₁+2L₂₂); η, τ_η, λ, Re_λ and Re_λ = u'²√(15/νε); u' = √(2k/3);
the phase-shift cutoff (√2/3)N(2π/L) = (2√2/3)κ_Ny ≈ 0.94κ_Ny and its ≈2.8× mode count, stated
identically on five surfaces; κ_max = f(N/2)(2π/L) with f = 2/3 / 1 / 2√2/3; κ_maxΔx = 2π/3 ≈ 2.09,
y_s = √3 ⇒ C_CFL ≲ 0.83; κ_maxη = fπη/Δx, η ≈ 0.96Δx, ν ∝ f^(−4/3) ⇒ +31% Re_λ, Re_λ ∼ N^(2/3);
G = (3/2)C_ε^(−2/3), ε = (k/G)^(3/2)/L, and the 0.81-vs-0.9 reconciliation at L/L₁₁ ≈ 5;
ℓ₁₁/ℓ₀ = C_ε(2/3)^(3/2) with 0.42k and 0.57k; the IF exponent exp((A − D|κ|²)τ) and its parameter
triple (−Dτ, τ, Â); the IFRK2 stability function |R(iy)|² = 1 + y⁴/4; the RK3 A/B/d/c coefficients
(d sums to 1, d_i = Δc_i); the transform ledgers (18/9, 21/18, 36/18, 42/36; RK3 51→42, RK2 34→28);
384 MiB / 387 MiB / 2.3 GiB / 322.5 MiB / 2.52 GiB residency arithmetic; ζ_p for K62 and
She–Lévêque (both exact at ζ₃ = 1); the Lundgren zero at Re_λ ≈ 34; Pao's (3/2)C_K(κη)^(4/3);
the κ² / κ⁴ low-wavenumber slopes of PopeLargeScale and VonKarmanLarge; the IC envelope peak at
κ_p/√2; and the injection identity 2AE_band for both fields.

---

## 1. `VarianceController`: the "marginal law" is quoted with the wrong denominator (k, not k_f)

- **type**: contradiction
- **severity**: major
- **confidence**: high

**Locations**

- PAGE: api / Forcing, `VarianceController`: "The rate is the marginal law $A = \varepsilon/2k$ plus
  a proportional restoring term:" — followed immediately by
  "$A(\boldsymbol{\kappa}, t) = \frac{\varepsilon(t) - G[k(t) - k_\infty]/t_\ell}{2k_f(t)}$".
- Same docstring, three lines later: "The two variances there are not interchangeable: $k$ is the
  whole field's … and $k_f$ the forced band's".
- PAGE: decisions, §References (Bassenne et al. 2016): "the marginal law $A = \varepsilon/2k$ plus a
  proportional restoring term".

**Contradicts**: the displayed formula's denominator $2k_f(t)$ versus the prose's $2k$ — the axis is
*which* variance normalizes the rate.

**Description**

The lead-in sentence and the §References gloss both write the marginal law with the whole-field $k$
in the denominator; the displayed formula (and the physics) require the *band* variance $k_f$. Only
$2Ak_f$ equals the injected power, which is what makes the docstring's next claim,
$\mathrm dk/\mathrm dt = -G(k-k_\infty)/t_\ell$ "exactly", true. Decision 58's own postscript records
that swapping these two nearly shipped wrong physics and calls it a category error; the prose here
still carries the swapped form on two surfaces.

**resolution_hint**: write "the marginal law $A = \varepsilon/2k_f$" in both places, or say "the
marginal law $\varepsilon/2\times$(the forced band's variance)".

---

## 2. Two different "eddy-turnover times" in one corpus — k/ε and 2k/3ε

- **type**: dimensional
- **severity**: major
- **confidence**: medium

**Locations**

- PAGE: api / Forcing, `VarianceController`: "`turnover_time = nothing` — the large-eddy turnover
  time $t_\ell$. When omitted it is taken as $2k_\infty/3\varepsilon_\infty$".
- PAGE: api / SimulationRun, `StationarityCriterion`: "the kinetic energy $k$, which normalizes the
  eddy-turnover clock $\Delta t \varepsilon/k$ it accumulates".
- PAGE: observables_cache §1.3: "a budget in turnovers … accumulates $\Delta t \varepsilon/k$ — the
  eddy-turnover clock". Same in ARCHITECTURE §4.7 and api / Observables.

**Contradicts**: $t_\ell = 2k/3\varepsilon = u'^2/\varepsilon$ against the clock's implied
$k/\varepsilon$ — a factor 3/2 in a quantity both call "the (large-)eddy turnover time".

**Description**

Both are dimensionally times, but they are not the same time. A user reading `min_turnovers = 5`
(clock units $\varepsilon/k$) and then setting `gain`/`turnover_time` against "the large-eddy
turnover time" is working in two units that differ by 50%. Nothing on either surface flags the
difference, and the `VarianceController` settling time $t_\ell/G$ is quoted in the second convention
while `warmup!`'s budget is quoted in the first.

**resolution_hint**: name the controller's parameter for its own convention (e.g. "$u'^2/\varepsilon$,
i.e. $\tfrac{2}{3}$ of the $k/\varepsilon$ turnover the run's clock counts"), or align them.

---

## 3. "Four strategies are provided", then five are listed

- **type**: contradiction
- **severity**: minor
- **confidence**: high

**Locations**

- PAGE: architecture §4.4: "Four strategies are provided. `NoForcing` (free decay) and `Linear` …
  `ConstantPower` … and `VarianceController` … `VarianceRescaling` … is the one post-step projection".
- PAGE: Home, "Work in progress": "the forcing menu `NoForcing`, `Linear`, `ConstantPower`,
  `VarianceController` (the default), and `VarianceRescaling`" — five.

**Contradicts**: the count "Four" against the five names the same paragraph then gives.

**Description**

The sentence opens with a count of four and enumerates five strategies. The later sentence in the
same paragraph — "because these four methods are written through tensor-order-generic field
operators" — is correct if `NoForcing` is excluded, which suggests the opening count was never
updated when `VarianceController` was added (decision 58). The API page and the Home page both
list five.

---

## 4. `L` is the box side everywhere except `ModelSpectrum`, where it names the roll-off length

- **type**: notation
- **severity**: minor
- **confidence**: high

**Locations**

- PAGE: api / phenomenology / Spectra, `ModelSpectrum`: "reads $\varepsilon$ and the roll-off's own
  length $L$ (see `large_scale_length` — $L_{11}$ for most forms, $k^{3/2}/\varepsilon$ for Pope's)".
- Same page, `LargeScaleFactor`: "with $\ell$ the length that form's own coefficient was fitted
  against, not the box side $L$".
- PAGE: notation, Numerics: "$L$ | box side ($\Omega = [0,L)^3$) | side_length".

**Contradicts**: `ModelSpectrum` binds $L$ to the roll-off length; `LargeScaleFactor` and the
glossary bind $L$ to the box side and reserve $\ell$ for the roll-off length.

**Description**

The `ModelSpectrum` formula itself writes $f_L(\kappa\ell)$, so the prose one line below
contradicts its own display. The same page's `large_scale_factor(f, κL)` names the argument `κL`
where the docstring text calls it $\kappa\ell$. Since $\Delta\kappa = 2\pi/L$ and the Li2008 group
$k/(L\varepsilon)^{2/3}$ both use $L$ as the box side, the collision is load-bearing: a reader could
substitute the box side into a roll-off fitted at $L_{11}$ or $k^{3/2}/\varepsilon$.

---

## 5. The scalar spectrum is a density, but the glossary says it "sums to" the variance

- **type**: dimensional
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE: notation, Diagnostics: "$E_\varphi(\kappa)$ | the scalar-variance spectrum, summing to
  $\langle\varphi^{2}\rangle$ — with no $\tfrac{1}{2}$, unlike $E(\kappa)$".
- Same table, adjacent row: "$E(\kappa)$ | the energy spectrum as a density per unit wavenumber …
  $k = \int_0^\infty E(\kappa)\,\mathrm{d}\kappa$ (dimensions $L^3T^{-2}$)".
- PAGE: api / phenomenology / Spectra, `ScalarSpectrum`: "parametrizations of $E_\varphi(\kappa)$,
  the density in wavenumber of the scalar variance".

**Contradicts**: "summing to" (the $E_n$ per-shell verb, one row below) applied to a per-unit-
wavenumber density, which the neighbouring $E(\kappa)$ row and the `Spectra` page integrate.

**Description**

This is the exact per-shell-versus-density distinction the docs police elsewhere (decision 19,
`energy_spectrum`, `integral_scale`). The $E_\varphi$ row is the only spectrum entry that uses the
sum verb for a density, and it is also the only one carrying no dimensions, so a reader has nothing
to check the convention against.

**resolution_hint**: "integrating to $\langle\varphi^2\rangle$, $\langle\varphi^2\rangle =
\int_0^\infty E_\varphi(\kappa)\,\mathrm d\kappa$ (dimensions $[\varphi]^2 L$)".

---

## 6. "A resolution bound $1/(D\kappa_{\min}^2)$" is built from the *lowest* wavenumber

- **type**: dimensional
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE: api / SimulationRun, `Simulation`, `max_dt`: "a resolution bound $1/(D\kappa_{\min}^{2})$
  built from the run's own diffusivity and box".
- PAGE: api / SimulationDomain, `max_wavenumber`: "the resolution criterion $\kappa_{\max}\eta$".

**Contradicts**: "resolution" is bound to $\kappa_{\max}$ on every other surface (the criterion
$\kappa_{\max}\eta$, `κ_max_η`), and to $\kappa_{\min}$ only here.

**Description**

The quantity is dimensionally a time and $\kappa_{\min}$ is clearly intended — $\kappa_{\max}$ would
reinstate the diffusive stability limit decision 1 exists to remove. But what
$1/(D\kappa_{\min}^2)$ measures is the *largest-scale* diffusive time, i.e. the step past which the
integrating factor damps even the gravest mode; calling it a "resolution" bound points the reader
at the opposite end of the spectrum from the word's meaning everywhere else in the docs.

**resolution_hint**: "a diffusive-time bound $1/(D\kappa_{\min}^2)$ on the gravest mode".

---

## 7. The interpolation floor does not follow the $\Delta x^{d+1}$ scaling the same docstring asserts

- **type**: physics
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE: api / Particles, `EndpointHeun`: "a degree-$d$ interpolant's trajectory floor falls as
  $\Delta x^{d+1}$ … (at $N = 128$, floor $1\times10^{-5}$ against time error $6\times10^{-5}$)".
- PAGE: decisions (2026-08, AdamsBashforth): "Measured on a frozen ABC flow at $64^3$, $T = 1$:
  `CatmullRom` ($C^1$, degree 2) floors at $1.2\times10^{-5}$".

**Contradicts**: the same interpolant's floor is $1.2\times10^{-5}$ at $N = 64$ and
$1\times10^{-5}$ at $N = 128$ — a factor 1.2, where the asserted $\Delta x^{d+1} = \Delta x^{3}$
scaling predicts a factor 8.

**Description**

Two measurements of the `CatmullRom` trajectory-error floor, one grid doubling apart, differ by
20% while the stated scaling law demands 8×. Either the two numbers come from different test
problems (a frozen ABC flow versus "a band-limited field") and the docs should say so, or one of
them is stale. As written, a reader who takes the scaling law and the $N=64$ number to predict the
$N=128$ floor lands an order of magnitude away from the value printed three pages later.

---

## 8. The `IFRK2` register count is justified by an assembly register `allocate_buffers` never gives it

- **type**: contradiction
- **severity**: minor
- **confidence**: medium

**Locations**

- PAGE: architecture §4.5: "three spectral registers per field against the low-storage scheme's two,
  counting the same way on both sides: the scheme's own registers plus the dealiasing seam's
  assembly register".
- PAGE: api / Propagator, `allocate_buffers`: "`IFLowStorageRK3` allocates `stage1` and `nonlinear`;
  `IFRK2` allocates `stage1`, `stage2`, and `velocity_predictor_spectral`."
- PAGE: api / Propagator, `IntegratorBuffers`: "`nonlinear` — the assembled right-hand side;
  `IFLowStorageRK3` only, else `nothing`."

**Contradicts**: the claim that both counts are "own registers + one assembly register" against the
allocator, where only `IFLowStorageRK3` owns an assembly register.

**Description**

The totals (2 and 3) match the allocator, but the stated *decomposition* does not: `IFRK2` has no
`nonlinear` register at all, so its three are three scheme registers and zero assembly registers.
The sentence is offered precisely as the guarantee that the two schemes are counted alike, which is
what makes the mismatch worth fixing rather than ignoring.

---

## 9. The skewness episode is not "half again" the resident set the cache page reports

- **type**: dimensional
- **severity**: nit
- **confidence**: low

**Locations**

- PAGE: decisions (2026-07, the memory audit): "the velocity-derivative skewness $\approx 19.6$ —
  the dominant episode, about half again the default resident set".
- PAGE: observables_cache §1.4: "a velocity-only run … carries six vector-shaped fields … about
  2.3 GiB at $256^{3}$ in double precision".

**Contradicts**: 19.6 units of $N^3$ reals is 2.45 GiB at $256^3$/`Float64` — about 7% above the
2.3 GiB resident set, not 50%.

**Description**

Episodes are frozen "in units of $N^3$ reals"; one such unit is 128 MiB at $256^3$ in double
precision, so 19.6 units ≈ 2.45 GiB against the page's 2.3 GiB working set. The current
`derivative_skewness` docstring's weaker claim — "larger than the resident working set" — is
consistent with those numbers; the decision-log ratio is not. Flagged low-confidence because the
decision log is append-only history and the resident set has shrunk twice since (decisions 40, 41),
though the pre-shrink figure (≈3.8 GiB) does not fit "half again" either.
