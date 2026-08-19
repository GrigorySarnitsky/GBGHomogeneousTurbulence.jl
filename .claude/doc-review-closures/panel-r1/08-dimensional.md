# Closure — Hat 08 (Dimensional analysis & normalization)

## 1. Pope2000's c_L = 6.78 evaluated at κL₁₁ instead of κL₀

**VERDICT: ABSENT**

`src/phenomenology/Spectra.jl` now defines `large_scale_length` as a generic dispatching function
(default `fp.integral_scale`, i.e. L₁₁) with an explicit `PopeLargeScale` override:
`large_scale_length(::PopeLargeScale, fp) = (3*fp.rms_velocity^2/2)^(3//2) / fp.dissipation` (L₀ =
k^{3/2}/ε), and `spectrum(m::ModelSpectrum, κ, fp)` calls
`large_scale_factor(m.large_scale, κ * large_scale_length(m.large_scale, fp))` — so Pope's factor is
now evaluated at κL₀, matching c_L = 6.78's normalization. `ModelSpectrum`'s docstring states this
explicitly ("L₁₁ for most forms, k^{3/2}/ε for Pope's"), and `docs/ARCHITECTURE.md:512-513` states the
length-dependence generically ("each form evaluated at the length its own coefficient was fitted
against"). No remaining mention of κL₁₁ for Pope in src or docs/src.

## 2. recommended_cfl: eigenvalue×C_CFL compared to y_s without the Δt step

**VERDICT: ABSENT**

`src/Propagator.jl:528-531`: "stability needs that rate times the step —
``C_{\mathrm{CFL}}\,\kappa_{\max}\Delta x``, once ``\Delta t`` is substituted — to stay within the
scheme's imaginary-axis stability limit ``y_{\mathrm{s}}``". The Δt substitution is now stated
explicitly, exactly the resolution_hint's wording.

## 3. Two different β values for far-dissipation decay (5.2 vs 6.7) with no reconciling note

**VERDICT: ABSENT**

`src/phenomenology/Spectra.jl`, `ExponentialDissipation` docstring now reconciles the two directly:
"[`PopeDissipation`](@ref) is asymptotically ``\exp(-\beta\kappa\eta)`` too, and carries
``\beta = 5.2`` — a lower rate, because Pope fits his ``\beta`` across the whole dissipation range
including the near-dissipation bend, while the values here are fitted to the far range alone. The two
are the same symbol for the same decay, calibrated on different intervals." No stray unreconciled
mention found elsewhere (`rg` for the two literals in docs/src and ARCHITECTURE.md empty).

## 4. Parseval / "normalized inner product" asserted without stating the transform normalization

**VERDICT: ABSENT**

`docs/src/notation.md:18` now carries a "Normalized inner product" glossary row:
"``\langle f, g \rangle`` | ``\frac{1}{\lvert\Omega\rvert}\int_\Omega f\cdot g\,\mathrm{d}\boldsymbol{x}``,
the box average of the pointwise product. Parseval holds for it in this normalization, which is why
the quadratic reductions (``k``, ``\varepsilon``, the variances) take a field in either representation
and return the same number." This is exactly the resolution_hint's requested row.

## 5. FlowParameters calls dependent quantities "independent"; examples violate C_ε

**VERDICT: PARTIAL**

The primary instance is fixed: `src/Phenomenology.jl:71-74` no longer uses the word "independent"
("It carries the dimensional quantities a law reads off a homogeneous isotropic state"), and its own
worked example (`Phenomenology.jl:105-106`) now uses `dissipation = 1.0, rms_velocity = 1.0,
integral_scale = 0.5` → C_ε = ε·L₁₁/u'³ = 0.5, exactly matching `Sreenivasan1998`'s `asymptote = 0.5`
default (`src/phenomenology/Scalings.jl:52-79`, unchanged).

**surviving_class**: `docs/src/phenomenology.md:20` — the front-page example explicitly named in the
original finding — is untouched: `fp = FlowParameters(viscosity = 1e-3, dissipation = 0.1,
rms_velocity = 1.0, integral_scale = 1.0)` gives C_ε = 0.1·1.0/1.0³ = 0.1, still ~5× off the package's
own C_ε ≈ 0.5 asymptote, i.e. off the realizable-HIT manifold every scaling law here is fitted on.

## 6. Sreenivasan1995's C_K = 1.5 ± 0.1 attributed to the wrong paper/normalization

**VERDICT: PRESENT**

`src/phenomenology/Scalings.jl:98-101`, unchanged from the finding's quote: "Sreenivasan (1995) found
it close to universal, a reliable estimate being ``C_K = 1.5 \pm 0.1`` (the default; Sagaut & Cambon
2018)". Still no 1-D→3-D conversion note (``C_K = (55/18)C_1``), unlike the sibling
`ObukhovCorrsin1949` docstring which does state its 3-D conversion explicitly ("≈ 0.67 for the
three-dimensional spectrum").

## 7. Re = 1/ν stated on three surfaces under an unmet units condition, correction on only one

**VERDICT: ABSENT**

`docs/src/notation.md:48` and `docs/ARCHITECTURE.md:238-239` now both carry the box-scale correction
inline: "`1 / ν` (in units where ``u' = L = 1``; on the shipped defaults, where ``L = 2\pi``, the
box-scale value is ``2\pi/\nu``)" (notation.md) and "(``\mathrm{Re} = 1/\nu`` in units where
``u' = L = 1``; ``2\pi/\nu`` on the shipped defaults, where ``L = 2\pi``)" (ARCHITECTURE.md). All three
named surfaces (notation glossary, architecture, `FlowConditions`/`Generator.jl`) now state the
correction, not just the one the finding flagged as sole holder.

## 8. χ assigned to the half-variance rate against the more common convention

**VERDICT: ABSENT**

`src/Phenomenology.jl:87-91`, the `scalar_dissipation` field doc, no longer names χ at all: "a law fed
the half-variance form ``\varkappa\langle\lvert\nabla\varphi\rvert^{2}\rangle`` instead is off by a
factor of two with no error" — the half-variance rate is now named by its formula, not by the
contested glyph, exactly per the finding's resolution_hint. `rg` for `\chi` across `src/`, `docs/src/`,
and `docs/ARCHITECTURE.md` returns only this one line, which no longer uses the symbol.
