# Doc-Review Panel — Consolidated Findings (collect-only)

Eight fresh-eyed expert hats independently read the **rendered** site (18 pages incl. the Architecture
page) from a faithful HTML→text consolidation. Raw ≈ 84 findings → **~55 distinct** after dedup.
**Nothing has been edited — act only after your review.** Full per-hat detail in the sibling files
`01–08-*.md`; this file is the cross-hat synthesis (deduped, corroboration-tagged, ranked).

Corroboration tag `[N hats]` = flagged independently by N of the 8 — the highest-confidence signal.

## Verdict at a glance

- **1 blocker** (physics): the Yaglom 4/3 scalar structure-function law is a **factor of 2** off.
- **~11 major**, most **corroborated by 3–5 independent hats** — these are the real spine.
- The bulk are minor/nit: notation drift, citation-entry gaps, decision-log staleness, API-doc gaps.
- **The physics core is verified clean** by two independent hats (theoretician + dimensional): the ½/full
  energy-vs-variance split, the Betchov constant `C = (4/7)√(15/2) ≈ 1.5649`, the three dealias bands
  (`2/3`, `1`, `2√2/3`), the Williamson RK3 coefficients, IF-RK2 stability `|R(iy)|²=1+y⁴/4`, the derived
  scales, and every model-spectrum roll-off exponent — all correct **and** cross-page consistent.
- **1 alarm refuted**: display equations render correctly (a consolidation artifact, confirmed against raw HTML).

Severity: 🔴 blocker · 🟠 major · 🟡 minor · ⚪ nit.

---

## 🔴 BLOCKER

### B1 — Yaglom 4/3 scalar law is a factor of 2 too large  ·  [turbulence-theoretician, high]
`Yaglom1949`: `⟨δu_L (δφ)²⟩(r) = −(4/3) ε_φ r`, reading `ε_φ = fp.scalar_dissipation`. But the package
defines `ε_φ = 2ϰ⟨|∇φ|²⟩` (the **full**-variance rate), whereas the 4/3 coefficient is derived for the
**half**-variance rate `ε_θ = ϰ⟨|∇φ|²⟩ = ½ε_φ` — exactly as the velocity 4/5 law pairs with `ε = ν⟨|ω|²⟩`
(the half-*energy* rate) and is correct here. As written the scalar law evaluates to **twice** the exact
value. In the package's own variables the correct statement is `⟨δu_L (δφ)²⟩ = −(2/3) ε_φ r`. This is an
*exact* inertial-range law with no free constant → a hard error, not a tunable. (Obukhov–Corrsin `C_OC`
is *not* affected — there both dissipation and spectrum use the full variance.)
*Locations:* Phenomenology — StructureFunctions `Yaglom1949`; API — Observables `scalar_dissipation`.

---

## 🟠 MAJOR — corroborated contradictions (the main goal)

### M1 — `E(κ)`: measured **per-shell energy** (`k=ΣE`) vs model **spectral density** (`k=∫E dκ`), compared directly  ·  [4 hats: consistency-matrix, dns-practitioner, api-user, dimensional]
The measured `energy_spectrum` is "the energy in each shell", `k = Σ_κ E(κ)`; the Phenomenology model
`spectrum` is "the density in wavenumber", `k = ∫ E dκ`. They differ by the shell width `Δκ = 2π/L`.
`validate_spectrum` puts the two side-by-side and takes a relative-L² discrepancy. For the **default box
`side_length = 2π`**, `Δκ = 1` and they coincide — which is why it's gone unnoticed — but for any other
box a perfect run reports a spurious error `∝ 2π/L`. The Notation cell is itself internally inconsistent:
"energy per unit wavenumber" (density) yet `k = Σ E(κ)` (sum). This is the exact "spectral density vs an
energy" category error §10 lists as its own correctness class. (`integral_scale` is immune — the ratio
cancels Δκ.) *Highest-priority structural item.*

### M2 — Default `velocity_forcing` "holds the **total** energy", but `BandRescaling`'s own default `over=:band` holds the **band** (total floats)  ·  [3 hats: consistency-matrix, dns-practitioner, api-user]
`Simulation` (and decision 20) say the default `BandRescaling` "holds the total energy at `kinetic_energy`".
But `BandRescaling(domain; target, over=:band, …)` documents `:band` as the default — "hold the band's own
value; the whole-field value then floats"; only `:total` pins `u'` and hence `Re_λ`. The grid-mode viscosity
logic *requires* `:total` (it fixes `Re_λ` from `N`), so `Simulation` must silently pass `over=:total` — but
that override is never stated, so the two docstrings flatly contradict. Also breaks the grid-mode
`Re_λ ~ N^{2/3}` promise if read literally.

### M3 — `PhaseShift` dropped from three `DealiasingStrategy` enumerations  ·  [4 hats: consistency-matrix, dns-practitioner, api-user, cold-reader]
The `DealiasingStrategy` supertype docstring ("Concrete strategies: `TwoThirds` … and `HouLi`"), the
"De-aliasing strategies" section intro, and `dealias!` all name only two strategies — while the same page's
module docstring, `FixedDomain`, `max_wavenumber` (`2√2/3` for `PhaseShift`), the umbrella Index, and
`PhaseShift`'s own type docstring three paragraphs below all know it's a first-class third strategy. Stale
"capability list missing a builder". (`dealias!` is also incomplete for a PhaseShift domain — its kernel is
the spherical `2√2/3·κ_Ny` truncation, neither "the sharp 2/3 cutoff" nor "the HouLi filter".)

### M4 — Decision log names the mode selector `target = :band|:total`; the API uses `over` (and `target` is the numeric value)  ·  [3 hats: api-user, consistency-matrix, +style/dns]
Architecture §11 decision 19: "`BandRescaling` can hold the band or the total energy (`target = :band|:total`)".
Live API: `BandRescaling(domain; target, over=:band, …)` — `over` is the `:band|:total` selector, `target` is
the numeric energy held. A user copying the (rendered, public) decision log writes `BandRescaling(target=:total)`,
passing a `Symbol` where a `Float` is expected and never setting the mode.

### M5 — Decision log carries stale forcing/energy API names: `ConstantPower(power=)`, `ForcingSpec`, `energy`  ·  [4 hats: consistency-matrix, dns-practitioner, api-user, style-editor]
Decision 14: `ConstantPower(power = 0.1)` returning a `ForcingSpec`; decision 20: "holds the total energy at
`energy`, default 1.5". Live API: keyword is `target` (not `power`), type is `DeferredForcing` (not
`ForcingSpec`), held-energy keyword is `kinetic_energy` (not `energy`). The `ForcingSpec→DeferredForcing`
rename *is* recorded in a later entry; the **`power→target`** and **`energy→kinetic_energy`** renames are
recorded nowhere, so `ConstantPower(power=0.1)` reads as a currently-valid call that `MethodError`s.

### M6 — Phase-shift cited "Patterson & Orszag (1971)" with **no §References entry**; "Orszag 1971" (2/3 rule) also unlisted  ·  [3 hats: citations-integrity, consistency-matrix, dns-practitioner]
`PhaseShift` and decision 27 cite "Patterson & Orszag (1971)"; §References lists only "Orszag & Patterson
(1972)" (a genuinely different paper — reversed authors, +1 year). The 1971 phase-shift paper (Phys. Fluids
14, 2538) and "Orszag 1971" (the 2/3 rule, J. Atmos. Sci. 28, 1074) are both real and both **missing full
entries**, against §References' "full entries here" promise. Fix = add the missing entries (not a merge).

### M7 — Grid-mode "the highest Reynolds number the grid resolves" is an overclaim — the default `k_max_η=2` "trades Reynolds number for margin"  ·  [citations-integrity, high]
The superlative appears 3× (SimulationRun + Architecture §4.7 + decision 20), but the same page says
`k_max_η=2` sits *above* the `1.5` well-resolved floor and "trades Reynolds number for margin". Since
`Re_λ ~ N^{2/3}` grows as `k_max_η → 1.5`, the default delivers a **lower** Re than the grid can still
well-resolve. At most it's "the highest Re consistent with the chosen resolution criterion".

### M8 — The `f(sim)` observable convenience methods are undocumented and cover only 5 of 8 observables  ·  [api-user, high]
The example does `kinetic_energy(s::Simulation)`, and SimulationRun says the observables "accept a
`Simulation` directly" — but no observable's home docstring documents the `Simulation`-taking form, its
return, or the field it reads (e.g. `dissipation(sim)` sourcing `viscosity` from `sim.conditions`). Worse,
`derivative_skewness` (the headline warm-up gate), `scalar_dissipation`, and `max_speed` get **no** `sim`
method — undiscoverable from the docs.

### M9 — Symbol `L` denotes two different lengths: box side (Notation/`Li2008`/`κ_max`) vs integral scale `L₁₁` (`f_L(κL)` in Spectra/StructureFunctions)  ·  [2 hats: cold-reader (major), dimensional]
Notation reserves `L` for the box side (`side_length`); but `ModelSpectrum`'s roll-off `f_L(κL)` reads `L`
from `fp`, whose only length is `integral_scale = L₁₁`, and decision 20 writes bare `L` for that same `L₁₁`.
A reader mapping `f_L(κL)`'s `L` to Notation's box side evaluates the large-scale roll-off at the wrong scale
(here ~4× off). Sharpest in `Li2008` (`L` = box side) sitting one module from `ModelSpectrum` (`L` = `L₁₁`).

### M10 — `ExponentialDissipation` β ≈ 0.6 vs `PopeDissipation` β = 5.2 for the same far-dissipation tail (~9×)  ·  [turbulence-theoretician, medium]
Both govern `E ∝ exp(−β κη)` asymptotically, on the same page. `β ≈ 0.6` puts `exp(−0.6) ≈ 0.55` still
surviving at `κη = 1` (Pope's factor gives ≈0.04). Even a self-consistent pure-exponential fixed by the
dissipation integral gives `β ≈ 2.1`. `0.6` is anomalously small next to Pope's 5.2 with no explanation —
likely a mis-transcribed constant or a different normalization; needs a source re-check.

### M11 — English variety mixed corpus-wide, the *same words* both ways  ·  [style-editor, high]
Not a clean per-page split: `normalized`×17 vs `normalised`×2 (both on the user surface, same fixed phrase
across pages), `discretised`×9, `parametrization`×13, `realization`×11, `modelled`/`modeling`, `coloured`,
`fiber` (no `fibre`). The Observables docstring's "normalized third invariant" vs Architecture §4.3's
"normalised third invariant" describe the identical diagnostic. Pervasive, immediately visible; the API
surface already leans American.

---

## 🟡 MINOR — grouped

**Notation & symbols**
- `k_max_η` uses ASCII `k` for `κ_max`, violating the page's own emphatic `k`(energy)/`κ`(wavenumber) rule — and sits next to `kinetic_energy`. **[3 hats: dns, style, cold-reader]**
- Structure function written `S_p(r)` in Architecture §4.8 but `D_{L…}(r)` everywhere in the Phenomenology API; `S_p` also overloads `S` (= derivative skewness). **[consistency-matrix]**
- `scalar_type` (the element type `T`) collides with the "scalar" the package reserves for the passive scalar `φ`; a newcomer reads it as "type of the scalar". **[cold-reader]**
- Leray projection named three ways: "Leray–Helmholtz" (majority), "Helmholtz (Leray)" (Notation), "Leray projection" (§5). **[consistency-matrix]**

**Citations & attribution**
- Rogallo 1981 §References gloss credits only the deferred §7 sheared frame, omitting its shipped phase-shift + spherical-truncation use (the actual `PhaseShift` citation). **[citations-integrity]**
- `ConstantPower` bundled under "Lundgren 2003" in Architecture §4.4 but uncited in its own docstring; Lundgren is the fixed-rate `Linear` lineage, not constant-power. **[2 hats: consistency-matrix, citations]**
- `ObukhovCorrsin1949` breaks the stated "first-author-surname" convention (two surnames) and the year 1949 is Obukhov's alone (Corrsin 1951). **[citations-integrity]**
- `Li2008` attributes `Re_λ ≈ 400–2500` to "the JHTDB isotropic datasets"; JHTDB forced-isotropic is `Re_λ ≈ 433`, and 2500 is Kaneda/Ishihara box DNS. **[2 hats: theoretician, citations]**
- Inaccessible sources cited on the rendered Architecture page — "the DNS warm-up research review" and "PF decision 28" — against §10's own "never cite an inaccessible source". **[citations-integrity, low]**
- `SaffmanDissipation`'s `exp(−2(κη)²)` "(Saffman 1963)" attribution smells off (1963 is fine-scale structure, not a Gaussian energy cutoff); the σ=2 "Saffman-type" form is year-less. Verify. **[citations-integrity, low]**
- "Grmela–Öttinger" GENERIC lists only Öttinger in §References; the `Li2008` type name has no matching "Li (2008)" entry in its provenance. **[consistency-matrix, low]**

**Numerics & methods**
- IF-RK2 called "marginally-stable" in the Propagator section intro, but "imaginary-axis **unstable**" everywhere else (module, `IFRK2` note, §4.5). `|R(iy)|²=1+y⁴/4 > 1` ⇒ genuinely unstable, not marginal. **[dns-practitioner, high]**
- "`k_max_η=2` means `Δx ≈ η`" is stated as general but holds only for `f=2/3`; `HouLi` (f=1) gives `Δx ≈ 1.57η`, `PhaseShift` `≈1.48η`. **[2 hats: theoretician, dimensional]**
- `IntegratorBuffers` carries IF-RK2's predictor registers (`velocity_star*`) into the default low-storage RK3 run; "each scheme allocates **exactly** its working set (currently the **same for every scheme**)" is self-tensioning for a "minimal-footprint" default. **[dns-practitioner, low]**
- Home's blanket "the time loop is … allocation-free" is looser than invariant 4 ("a time *step* allocates no field-sized memory"); default `warmup!` gates on `derivative_skewness`, which allocates rank-2 buffers per call. **[citations-integrity, low]**

**API documentation gaps**
- `scalar_dissipation(φ, …)` names its **spectral** argument `φ` (not `φ̂`), the lone diagnostic to break the `û`/`φ̂` spectral-naming convention. **[api-user, high]**
- `flow_parameters` leaves `scalar_dissipation = NaN`; `ObukhovCorrsin1949`/`Yaglom1949` then evaluate to NaN with no hint. `flow_parameters` never says it doesn't populate it. **[api-user]**
- `structure_function`/`StructureFunction` generic contract is a pure-velocity moment `⟨(δu)^p⟩`, but `Yaglom1949` (same generic) returns the mixed `⟨δu_L(δφ)²⟩`. **[2 hats: theoretician, cold-reader]**
- `scaling_exponent`'s argument is `order` in the generic but `p` at the concrete laws; `structure_function`'s `order` is required in the generic yet defaulted (`=3`) at the laws. **[2 hats: api-user, cold-reader]**
- `Kolmogorov1941`'s module-map-promised `scaling_exponent` (`ζ_p=p/3`) is absent from its own type docstring. **[api-user]**
- `Simulation(domain; …)`'s positional `domain` isn't enumerated with the keywords (the "`domain`/`buffers` slip past" class). **[api-user]**
- `Simulation` kwargs drift from the `Tracers` constructor they forward to (`ntracers` vs `count`, `tracer_scheme` vs `scheme`). **[api-user]**
- Statistics ("Eulerian + Lagrangian") headlined on Home and referenced by `sample!`/`run!`, but no statistics API is documented anywhere; the backing library is never named. **[cold-reader]**
- Tracer interpolation schemes (`CatmullRom`/`LalescuSpline(n,m)`/`LagrangeSpline(n)`) are a user-facing choice with zero guidance on `n,m` or accuracy/cost. **[cold-reader]**

**Physics precision**
- `kinetic_energy` default differs by layer: `random_solenoidal_velocity!` = 0.5, `Simulation` = 1.5 (same keyword name). **[2 hats: consistency-matrix, theoretician]**
- `Li2008`: `k/(Lε)^{2/3}` is not `C_ε=εL/u'³` "written with the box side" — they relate by `G=(3/2)C_ε^{−2/3}` (a −3/2 power); the "≈0.5 becomes ≈0.9" narrative conflates the two groups' values. **[dimensional]**
- §4.8 lists `Scalings` contents (skewness, flatness, Obukhov–Corrsin, `C₀`, mech-to-scalar ratio) that aren't `Scalings` laws, and omits the one that is (`Li2008`); Obukhov–Corrsin lives in `Spectra`. **[consistency-matrix, low]**
- Spectrum presets render as "— Function" (velocity) vs "— Type" (scalar/others); no `Pope2000` type to dispatch on, unexplained. **[2 hats: style-editor, api-user]**

---

## ⚪ NITS

Hyphenation `de-alias`/`dealias` and `advective-CFL`/`advective CFL` (site vs Architecture) **[2 hats]** ·
`@extref` links target PF `/dev/` while own links use `/stable/` **[style]** · return-type annotations
inconsistent (`-> Float64` on Phenomenology, none on Observables) **[api-user]** · `max_speed(u)` doesn't
state physical representation **[api-user]** · `stationary_dissipation(law,k,L)` vs signature
`(law,energy,side_length)` **[cold-reader]** · `f_φ` scalar forcing on Home but absent from Notation glossary
**[cold-reader]** · `K41`/`K62`/"aliasing"/"solenoidal" never defined for a newcomer **[cold-reader]** ·
`kinetic_energy`/`scalar_variance` are both constructor keywords and observable functions **[cold-reader]** ·
Pope cited year-less ("Pope, Turbulent Flows") on Notation vs "Pope (2000)" elsewhere **[citations]** ·
`S ≈ −0.5 (Kolmogorov)` mis-attributes an empirical value to Kolmogorov **[citations]** · `2/3`-rule set as
plain text in one section lead vs `$2/3$` math everywhere **[style]** · "Phenomenology is scaffolded"
understates a full reference-law library **[consistency-matrix]** · `peak_wavenumber` `κ_p` doesn't locate
the shell-summed spectral peak (peaks at `κ_p/√2`) **[dimensional, low]** · §2 warm-up comment blames
"constant-energy forcing would clamp it flat" beside a `ConstantPower` (fixed-injection → rings) example **[dns]**.

---

## ✅ Verified clean (recorded for confidence)

Two independent hats (theoretician + dimensional) re-derived and cross-checked, finding **no defect**: the
½-energy / full-variance split and both budgets; the energy-spectrum halving; `ε = ν⟨|ω|²⟩ = 2ν⟨SᵢⱼSᵢⱼ⟩`;
the Betchov skewness constant `C = (4/7)√(15/2) ≈ 1.5649` (and `tr S³ = 3 det S`); the three dealias bands
and `κ_maxΔx = 2π/3`; `u' = √(2k/3)`; `η, τ_η, λ, Re_λ`; the Williamson RK3 coefficients (Σd=1); IF-RK2
`|R(iy)|²=1+y⁴/4`; the integrating-factor exponent and its `ν`/`ϰ` split; every `Spectra` roll-off exponent;
the intermittency exponents (`ζ₃=1`); and `stationary_dissipation = (k/G)^{3/2}/L`. Register is uniform (no
"knob"). The silent-render surface is **clean**: no `katex-error`, every `@ref`/`@extref` resolves, no `\mathbf`.

## ↩︎ Investigated — not a defect

**Display equations render fine.** The consistency-matrix hat flagged (low-confidence, out-of-lane) that
display math surfaced as raw `\[ … \]`. The style-editor, reading the **raw HTML**, refuted it: display math
is standard client-side KaTeX (`<p class="math-container">\[…\]</p>`, auto-rendered). The `\[…\]` was a
limitation of *our consolidation* (it converts inline `span.katex` but not the client-rendered display
blocks) — the content hats still read the display formulas as valid TeX, so their physics/dimensional checks
were unaffected.

---

## Per-hat files (full detail + exact quotes)

`01-consistency-matrix.md` (33) · `02-turbulence-theoretician.md` (7, incl. the blocker) ·
`03-dns-practitioner.md` (9) · `04-style-editor.md` (7 + raw-HTML render pass) · `05-api-user.md` (16) ·
`06-cold-reader.md` (13) · `07-citations-integrity.md` (12) · `08-dimensional.md` (5 + a long verified-clean list).
