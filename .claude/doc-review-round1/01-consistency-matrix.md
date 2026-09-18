# Consistency Matrix — findings (hat: consistency-matrix)

Systematic cross-page audit of the rendered GBGHomogeneousTurbulence documentation
(`manuscript-full.md`, all 18 pages incl. Architecture). Each recurring entity —
physical quantity, symbol, formula, normalization, code name, numerical constant,
citation — was collected across every page and diffed. Divergences below.

Legend: severity = blocker / major / minor / nit; confidence = high / medium / low.

---

## 1. `E(κ)` defined as a spectral DENSITY (integral) on the model side but as a per-shell ENERGY (sum) on the measured side — and the two are compared directly

- **type:** contradiction  **severity:** major  **confidence:** medium
- **Locations:**
  - PAGE: Notation — Diagnostics: "`$E(\kappa)$` | energy spectrum (**energy per unit wavenumber**), `$k = \sum_\kappa E(\kappa)$`"
  - PAGE: API — Observables — `energy_spectrum`: "the turbulent kinetic energy resolved over wavenumber-magnitude shells, `$k = \sum_\kappa E(\kappa)$` … the shell-center wavenumber magnitudes and **the energy in each shell**"
  - PAGE: Phenomenology — Reference laws — `spectrum`: "the velocity energy spectrum `$E(\kappa)$` … (**the density in wavenumber** of the kinetic energy, `$k = \int_0^\infty E(\kappa)\,d\kappa$`)"
  - PAGE: Phenomenology — Spectra — `ScalarSpectrum`: "parametrizations of `$E_\varphi(\kappa)$`, **the density in wavenumber** of the scalar variance"
  - PAGE: API — SimulationRun — `validate_spectrum`: "the measured and predicted `$E(\kappa)$`, and the relative L² discrepancy over the resolved … shells"
- **Contradicts:** the document's own guard — PAGE: Architecture — §10 Conventions: "Category/type errors are their own correctness class … a **spectral density `$E(\kappa)$` with an energy**." The measured `E(κ)` is explicitly "the energy in each shell" reconstructed by a **bare sum** `k = Σ E(κ)`, whereas the model `E(κ)` is "the density in wavenumber" reconstructed by an **integral** `k = ∫ E dκ`. These are dimensionally different objects (a per-shell energy vs an energy density [energy·length]).
- **Description:** The same symbol `E(κ)` names a per-shell energy (measured/Notation/Observables) and a spectral density (Phenomenology). `validate_spectrum` puts the two side by side and takes their relative L² difference. For the default box `side_length = 2π` the shell spacing `Δκ = 2π/L = 1`, so the per-shell energy and the density coincide numerically and the mismatch is masked; for any `L ≠ 2π` the measured (per-shell) and predicted (density) `E(κ)` differ by the factor `Δκ = 2π/L`, so the comparison is off by that factor. The Notation cell is itself internally inconsistent: labelling `E` "energy per unit wavenumber" (a density) while reconstructing `k` by a bare sum `Σ E(κ)` (which only holds if `E` is energy-per-shell). At minimum the wording should be unified (density+integral OR per-shell+sum) across Notation, Observables, and Phenomenology; the `validate_spectrum` normalization deserves a second look for non-2π boxes.
- **resolution_hint:** Pick one convention for `E(κ)` (per-shell energy vs density) and state it identically everywhere; if measured is per-shell and model is density, `validate_spectrum` must reconcile them by `Δκ`.

---

## 2. Default `BandRescaling` is documented as holding the TOTAL energy by the run layer, but its own default mode `over = :band` holds only the BAND (total floats)

- **type:** contradiction  **severity:** major  **confidence:** medium
- **Locations:**
  - PAGE: API — SimulationRun — `Simulation`, "Setting the Reynolds number": "By default the run is forced and stationary — a `BandRescaling` **holds the total energy** at `kinetic_energy`"
  - PAGE: API — SimulationRun — `Simulation`, Keywords: "`velocity_forcing` … defaults to a `BandRescaling` **holding the total energy** at `kinetic_energy`"
  - PAGE: Architecture — §11 decision (2026-07 resolution-based viscosity): "a `BandRescaling` **holds the total energy** at `energy`, default `1.5`, i.e. `$u'=1$`"
  - PAGE: API — Forcing — `BandRescaling`: signature `BandRescaling(domain; target, over = :band, …)`; "`:band` (**default**) — hold the band's own value; **the whole-field value then floats**"; "`:total` — … the whole-field value equals `target` (… pins … `$u'$` and hence `$\mathrm{Re}_\lambda$`)"
- **Contradicts:** the run layer says the default forcing holds the TOTAL energy, but the `BandRescaling` type documents its default as `over = :band`, which "hold[s] the band's own value; the whole-field value then floats." Nowhere is it stated that `Simulation` overrides `over` to `:total`.
- **Description:** A reader cannot reconcile these. If `Simulation` uses the documented `BandRescaling` default (`over = :band`), the total energy floats and the "holds the total energy" claim is false; moreover the grid-mode promise ("picks **the highest Reynolds number the grid resolves**", `Re_λ ~ N^{2/3}`) breaks, because `over = :band` lets `u'` (hence `Re_λ`) float. If instead the constructor silently passes `over = :total`, that override is undocumented and directly contradicts the stated `:band` default a reader would assume. Either way the default-forcing behavior is stated two incompatible ways.
- **resolution_hint:** State explicitly whether the auto-built forcing uses `:total`; align "holds the total energy" with whichever mode is actually chosen.

---

## 3. Decision 19 names the `BandRescaling` mode selector `target = :band | :total`, but the API uses `over = :band|:total` (and `target` is the numeric value held)

- **type:** api-gap  **severity:** minor  **confidence:** high
- **Locations:**
  - PAGE: Architecture — §11 decision (2026-07): "`BandRescaling` can hold the band or the total energy (**`target = :band | :total`**). `:band` (default) fixes the forced band's energy…"
  - PAGE: API — Forcing — `BandRescaling`: `BandRescaling(domain; target, **over = :band**, …)` — here `target` is "the observable the forcing holds" (a number) and `over` is the `:band|:total` selector.
- **Contradicts:** decision 19 attaches the `:band | :total` values to the keyword `target`; the API attaches them to `over` and uses `target` for the numeric quantity (`kinetic_energy` / `scalar_variance`).
- **Description:** The decision-log entry conflates two distinct keywords, so `target = :band` in the log is a type error against the actual signature (`target` takes a Float, `over` takes the Symbol). A reader following the log would call `BandRescaling(target = :total)` incorrectly.

---

## 4. `PhaseShift` is a documented concrete dealiasing strategy, yet three enumerations list only `TwoThirds` and `HouLi`

- **type:** contradiction  **severity:** minor  **confidence:** high
- **Locations (omit PhaseShift):**
  - PAGE: API — SimulationDomain — `DealiasingStrategy`: "**Concrete strategies: `TwoThirds`** (the sharp `$2/3$` rule, the default) **and `HouLi`** (the smooth Hou–Li filter)."
  - PAGE: API — SimulationDomain — section intro "De-aliasing strategies": "the supertype, then **the sharp 2/3-rule default and the smooth Hou–Li filter**." (PhaseShift is documented in this very section.)
  - PAGE: API — SimulationDomain — `dealias!`: "The kernel is whatever the run's `DealiasingStrategy` built: **the sharp `$2/3$` cutoff (`TwoThirds`…) or the smooth `HouLi` filter**" (PhaseShift's spherical truncation also goes through `domain.dealias`).
- **Contradicts:** the same section and file document `PhaseShift` as a third concrete strategy — PAGE: API — SimulationDomain — module docstring: "`DealiasingStrategy` … `TwoThirds`, `HouLi`, **or `PhaseShift`**"; `FixedDomain` lists all three; `max_wavenumber`: "`$2/3$` for `TwoThirds`, `$1$` for `HouLi`, **`$2\sqrt2/3$` for `PhaseShift`**"; and the umbrella Index re-exports `PhaseShift`.
- **Description:** The supertype's "Concrete strategies:" enumeration, the section intro, and `dealias!` are stale — each names only two of the three strategies. This is the "capability list missing a builder" staleness class.

---

## 5. Structure function written `$S_p(r)$` in the Architecture but `$D_{L\dots}(r)$` everywhere in the Phenomenology surface (and `$S_p$` clashes with `$S$` = derivative skewness)

- **type:** contradiction  **severity:** minor  **confidence:** high
- **Locations:**
  - PAGE: Architecture — §4.8: "`StructureFunctions` — functions of `$r$` (the **`$S_p(r)$`** laws and the two-point correlations…)"
  - PAGE: Phenomenology — Overview / Reference laws / StructureFunctions (module, `StructureFunction`, `structure_function`, `scaling_exponent`): uniformly "**`$D_{L\dots}(r)$`**", with concretes `$D_{LL}(r)$`, `$D_{LLL}(r)$`.
- **Contradicts:** one object, two symbols (`$S_p(r)$` vs `$D_{L\dots}(r)$`). The Architecture also uses `$S$` for the derivative skewness (§4.3, §4.8 "the derivative skewness `$S$`"), so `$S_p(r)$` overloads a glyph already bound to a different quantity.
- **Description:** The whole reference-law API uses `$D_{L\dots}(r)$`; only the Architecture §4.8 sentence uses `$S_p(r)$`. Notation should be one symbol per concept; adopt `$D_{L\dots}(r)$` in §4.8 to match the API and avoid the `$S$` skewness clash.

---

## 6. Phase-shift dealiasing cited as "Patterson & Orszag (1971)" but the pseudospectral method / 2/3 rule as "Orszag & Patterson 1972" / "Orszag 1971"; only the 1972 work has a full reference entry

- **type:** citation  **severity:** minor  **confidence:** medium
- **Locations:**
  - PAGE: API — SimulationDomain — `PhaseShift`: "Phase-shift de-aliasing follows **Patterson & Orszag (1971)**; the combination with spherical truncation is Rogallo (1981)."
  - PAGE: Architecture — §11 decision 27: "(a single half-cell shift is exact only in 1-D; **Patterson & Orszag 1971**, Rogallo 1981)"
  - PAGE: Architecture — §4.2: "(the pseudospectral method; **Orszag & Patterson 1972**, the `$2/3$` rule **Orszag 1971**)"
  - PAGE: Architecture — References: "**Orszag, S. A. & Patterson, G. S. (1972)**. … Phys. Rev. Lett. 28, 76–79. (Pseudospectral method; the `$2/3$` dealiasing rule, Orszag 1971.)"
- **Contradicts:** author order and year flip between "Patterson & Orszag (1971)" (phase-shift) and "Orszag & Patterson (1972)" (pseudospectral). The References list resolves only the 1972 work; "Patterson & Orszag (1971)" and the standalone "Orszag 1971" (2/3 rule) have no full entries.
- **Description:** These may be distinct real papers (Patterson & Orszag, Phys. Fluids 1971 vs Orszag & Patterson, PRL 1972), but as written a reader sees a reversed-author, adjacent-year pair and cannot tell whether one is a typo of the other. Two of the three inline citations lack a reference-list entry.
- **resolution_hint:** Add explicit entries for Patterson & Orszag (1971) and Orszag (1971), or unify the author-year/order if they are the same work.

---

## 7. Decision 14 uses `ConstantPower(power = 0.1)` and `ForcingSpec`; the rest of the docs use `ConstantPower(target = 0.1)` and `DeferredForcing`

- **type:** contradiction  **severity:** minor  **confidence:** medium
- **Locations:**
  - PAGE: Architecture — §11 decision (2026-07 operator-free forcing): "Operator-free forcing construction via **`ForcingSpec`**. **`ConstantPower(power = 0.1)`** … return a `ForcingSpec` …"
  - PAGE: API — Forcing — `ConstantPower`: `ConstantPower(domain; **target**, …)`; operator-free `ConstantPower(; **target**)` returns a `DeferredForcing`
  - PAGE: Architecture — §2 and §4.4: "**`ConstantPower(target = 0.1)`**, a `DeferredForcing`"
  - PAGE: Notation — Forcing: "`$\varepsilon_{\text{target}}$` … `ConstantPower(**target**=…)`"
- **Contradicts:** the keyword is `power` in decision 14 but `target` everywhere else; the deferred type is `ForcingSpec` in decision 14 but `DeferredForcing` everywhere else.
- **Description:** The `ForcingSpec → DeferredForcing` rename is explicitly recorded in a later decision, so that half is a knowing append-only artifact. The `power → target` keyword change is **not** recorded anywhere, leaving `ConstantPower(power = 0.1)` as a live, unreconciled contradiction against the whole API (a reader copying decision 14 hits an unknown keyword).

---

## 8. Decision 20 refers to the energy keyword as `energy` (default `1.5`); the actual `Simulation` keyword is `kinetic_energy` (and `BandRescaling`'s numeric keyword is `target`)

- **type:** contradiction  **severity:** minor  **confidence:** medium
- **Locations:**
  - PAGE: Architecture — §11 decision (2026-07 resolution-based viscosity): "a `BandRescaling` holds the total energy at **`energy`, default `1.5`**"
  - PAGE: API — SimulationRun — `Simulation`: signature `Simulation(; grid_points_per_axis, k_max_η = 2, **kinetic_energy = 1.5**, …)`; keyword "`kinetic_energy = 1.5` — the initial, and when forced the held, kinetic energy `$k$`"
- **Contradicts:** decision 20's `energy` matches neither the `Simulation` keyword `kinetic_energy` nor the `BandRescaling` value keyword `target`.
- **Description:** The value `1.5` (⇒ `u' = 1`) is consistent, but the keyword name `energy` is wrong; the user-facing keyword is `kinetic_energy`.

---

## 9. Architecture §4.8 enumerates `Scalings` contents (skewness, flatness, Obukhov–Corrsin, Lagrangian C₀, mechanical-to-scalar ratio) that are not `Scalings` laws, and omits the one that is (`Li2008`)

- **type:** organization  **severity:** minor  **confidence:** low
- **Locations:**
  - PAGE: Architecture — §4.8: "`Scalings` — the dimensionless numbers … (`$C_K$`, the dissipation constant `$C_\varepsilon$`, the **derivative skewness `$S$`, the flatness, the Obukhov–Corrsin constant, the Lagrangian `$C_0$`, the mechanical-to-scalar timescale ratio**)."
  - PAGE: Phenomenology — Scalings — module: only "`Sreenivasan1998`" (`$C_\varepsilon$`), "`Sreenivasan1995`" (`$C_K$`), and "**`Li2008`** — the box-normalized dissipation group".
  - PAGE: Phenomenology — Spectra — `ObukhovCorrsin1949`: the Obukhov–Corrsin constant lives here (a `ScalarSpectrum`), not in `Scalings`.
- **Contradicts:** §4.8 places the Obukhov–Corrsin constant under `Scalings` (it is a `Spectra` law) and lists skewness/flatness/C₀/ratio (no such `Scalings` laws exist), while omitting the actually-present `Li2008` box-dissipation law.
- **Description:** Reads as a forward-looking scope list but is presented as current contents; it does not match the three laws the `Scalings` module documents. (The `ScalingLaw` supertype docstring similarly lists "the derivative skewness, …" as an example that has no implementing law.)

---

## 10. Leray projection named three ways: "Leray–Helmholtz" (majority), "Helmholtz (Leray)" (Notation), "Leray projection" (§5)

- **type:** typesetting  **severity:** nit  **confidence:** medium
- **Locations:**
  - PAGE: Home; PAGE: API — Generator (`velocity_nonlinear!`); PAGE: API — State (`random_solenoidal_velocity!`); PAGE: Architecture §4.2: "the **Leray–Helmholtz** projection `$\mathbb P$`"
  - PAGE: Notation — Spectral representation and operators: "`$\mathbb P$` | the **Helmholtz (Leray)** projection onto divergence-free fields | `helmholtz_projection`"
  - PAGE: Architecture — §5: "the **Leray projection** `helmholtz_projection!`"
- **Contradicts:** three orderings/names for the one operator `$\mathbb P$`.
- **Description:** Minor register drift; pick one (e.g. "Leray–Helmholtz projection") for the glossary and every docstring. (Also note the code identifier appears as `helmholtz_projection` in Notation vs `helmholtz_projection!` in §5 — an f/f! pair, acceptable but worth aligning.)

---

## 11. `random_solenoidal_velocity!` defaults `kinetic_energy = 0.5`; `Simulation` defaults `kinetic_energy = 1.5`

- **type:** other  **severity:** nit  **confidence:** low
- **Locations:**
  - PAGE: API — State — `random_solenoidal_velocity!`: `random_solenoidal_velocity!(û, domain; **kinetic_energy = 0.5**, peak_wavenumber = 2.0, …)`
  - PAGE: API — SimulationRun — `Simulation`: "`**kinetic_energy = 1.5**` … `1.5` gives `$u' = 1$`"
- **Description:** Same-named keyword, two different defaults across layers. Likely intentional (the low-level seeder vs the front door, which passes `1.5` explicitly), but the divergent default of the same keyword name is a small trap; `peak_wavenumber = 2.0` and `scalar_variance = 1.0` do agree across the two layers.

---

## 12. `ConstantPower` attributed to "Lundgren 2003" in the Architecture but carries no such citation in its own docstring

- **type:** citation  **severity:** minor  **confidence:** low
- **Locations:**
  - PAGE: Architecture — §4.4: "`Linear` and **`ConstantPower` (negative-damping, Lundgren 2003**, folded into `$\mathcal E$`)"
  - PAGE: API — Forcing — `Linear`: "Linear (negative-damping) forcing … (**Lundgren 2003**)"; `ConstantPower`: "Constant-injection-rate forcing … " (**no citation**)
- **Contradicts:** Architecture bundles `ConstantPower` under Lundgren 2003; the API page cites Lundgren only for `Linear`.
- **Description:** Either `ConstantPower` should carry the same attribution on its docstring or the Architecture should not extend Lundgren 2003 to it.

---

## 13. Reference-list completeness: "Grmela–Öttinger" GENERIC cites only Öttinger; the `Li2008` law name has no matching "Li (2008)" in its provenance

- **type:** citation  **severity:** minor  **confidence:** low
- **Locations:**
  - PAGE: Architecture — §8: "GENERIC (**Grmela–Öttinger**) is the same structure." — References list has only "Öttinger, H. C. (2005)"; no Grmela entry.
  - PAGE: Phenomenology — Scalings — `Li2008`: cites "Taylor 1935; Sreenivasan 1998; **Kaneda et al. 2003**" for the law, with no "Li (2008)" reference spelled out, though the type is named `Li2008`.
- **Description:** Named author-year handles ("Grmela–Öttinger", the type name "Li2008") that a reader would look up have no corresponding full citation. Minor, but flagged for the integrity pass.

---

## 14. Display equations render as raw `\[ … \]` throughout (no `$$` display spans) — possible silent display-math failure across all pages

- **type:** format  **severity:** major  **confidence:** low
- **Locations:**
  - Every display formula in the consolidated text appears as `\[ … \]` (23 occurrences; **zero** `$$` display spans), while inline math is properly `$…$`. Examples: PAGE: Home — "What it solves" (`\[\partial_t \boldsymbol{u} = …\]`); PAGE: API — Generator — `integrating_factor!` (`\[\mathcal{E}(\boldsymbol{\kappa}) = …\]`); PAGE: API — Observables — `derivative_skewness`, `integral_scale`; PAGE: Phenomenology — Spectra — `ModelSpectrum`.
- **Description:** Inline KaTeX rendered (captured as `$…$`), but every DISPLAY block surfaces as literal `\[ … \]` with no KaTeX display span. This is uniform (not a cross-page divergence), but the pattern suggests the built HTML may show display equations as un-rendered raw `\[ … \]` text rather than typeset math — which, if real, is a site-wide blocker. **Out of my lane and low-confidence** (I do not have the raw HTML); flagged for the style/raw-HTML reviewer to confirm against `docs/build`.
- **resolution_hint:** Confirm in the raw HTML whether `\[…\]` display blocks are rendered by KaTeX; if not, switch them to Documenter `$$…$$` / ```math``` blocks.

---

## 15. "Phenomenology is scaffolded" (Home) understates a fully documented reference-law library

- **type:** other  **severity:** minor  **confidence:** low
- **Locations:**
  - PAGE: Home — "Work in progress": "The reference turbulence laws (`Phenomenology`) are **scaffolded**; the Eulerian and Lagrangian statistics are being added."
  - PAGE: Phenomenology — Spectra / StructureFunctions / Scalings: a complete set of usable laws with published-fit presets (`Pope2000`, `VonKarman1948`, `Pao1965`, `ObukhovCorrsin1949`, `Kolmogorov1941/1962`, `SheLeveque1994`, `Yaglom1949`, `Lundgren2002`, `Sreenivasan1995/1998`, `Li2008`).
- **Description:** "Scaffolded" reads as a skeleton, but the documented `Phenomenology` surface is substantial and evaluatable (and is already consumed by `validate_spectrum` and grid-mode viscosity). The status line is stale/understated relative to the API pages.

---

## 16. Prose hyphenation "de-alias(ing)" vs code/Architecture "dealias(ing)"

- **type:** typesetting  **severity:** nit  **confidence:** medium
- **Locations:**
  - PAGE: API — SimulationDomain: "**De-aliasing** strategies", "**De-alias** filtering", "the **de-alias** kernel"; PAGE: Home: "**de-aliased** by the default `$2/3$` rule"
  - PAGE: Architecture — §4.1/§4.2/§7: "the **dealias** kernel", "**dealiased** by the `$2/3$` rule", "the run's chosen **dealiasing** strategy"; code identifiers `dealias!`, `DealiasingStrategy` (no hyphen)
- **Description:** The API pages consistently hyphenate ("de-aliasing") while the Architecture consistently does not ("dealiasing"); the code is un-hyphenated. Purely cosmetic, but it is a systematic site↔Architecture divergence of one term.
