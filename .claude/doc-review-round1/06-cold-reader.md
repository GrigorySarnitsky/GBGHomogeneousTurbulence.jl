# Cold Reader — first-year turbulence grad student, top-to-bottom self-containedness audit

Reading the rendered user-facing site (Architecture page excluded on purpose) as a newcomer who does
NOT know the codebase. I flag: symbols/terms/package concepts used before (or without ever) being
defined; arguments that appear only inside a formula; leaps that assume insider knowledge; and any
term used consistently but never introduced. Cross-referenced across all pages.

---

## F1 — The symbol `L` denotes two different physical quantities (box side vs integral scale)

- **type:** contradiction
- **severity:** major
- **confidence:** high

**Locations**
- PAGE: Notation, "Numerics": `| $L$ | box side ( $\Omega = [0,L)^3$ ) | side_length |`
- PAGE: Notation, "Derived scales": `$L_{11}$ | longitudinal (parallel) integral length scale, …` (the integral scale has its OWN symbol, `L₁₁`)
- PAGE: Phenomenology — Spectra, "The composed spectrum / ModelSpectrum": `$E(\kappa) = C_K\,\varepsilon^{2/3}\,\kappa^{-5/3}\,f_L(\kappa L)\,f_\eta(\kappa\eta)$ … Evaluated by spectrum(model, κ, fp), which reads $\varepsilon$ and $L$ from fp and forms $\eta$ with kolmogorov_length.`
- PAGE: Phenomenology — StructureFunctions, "Kolmogorov1941": `Both hold in the inertial range $\eta \ll r \ll L$.`
- PAGE: Phenomenology — Reference laws, "FlowParameters" fields: `integral_scale — the longitudinal integral length $L_{11}$` (fp carries `integral_scale = L₁₁`, and NO box side)

**contradicts:** The Notation page globally reserves `L` for the box side (`side_length`), and `Scalings`
uses it that way too (Li2008: "the periodic-box side length $L$"; `stationary_dissipation(law, energy,
side_length)` with `side_length` ≡ `L`). But `Spectra.ModelSpectrum` says it "reads … $L$ from fp",
and `fp` has no box side — its only length is `integral_scale = L₁₁`. So in `Spectra`/`StructureFunctions`
the bare `L` means the integral scale, while in `Notation`/`Scalings` it means the box side. Axis of
disagreement: **what `L` denotes** (box side `L` vs integral scale `L₁₁`).

**description:** A cold reader learns from the Notation page that `L` = box side, and that the integral
scale is `L₁₁`. Then in every model-spectrum and structure-function formula the same bare `L` silently
means the integral scale (a quantity that already owns the symbol `L₁₁`). This is exactly the "one
symbol, two concepts" the docs elsewhere forbid, and it is made sharper by Li2008 itself stating that
the box-normalized group is "written with the box side in place of the integral scale" — i.e. the two
ARE distinct quantities, yet both wear the bare `L`. The reader cannot tell whether `f_L(κL)` wants the
box side or the integral scale without inferring it from "reads … from fp". `resolution_hint`: in the
Phenomenology formulas write the integral scale as `L₁₁` (or `ℓ`), reserving `L` for the box side as the
Notation page promises.

---

## F2 — `DealiasingStrategy`'s own docstring lists only 2 of its 3 concrete strategies (omits `PhaseShift`)

- **type:** contradiction
- **severity:** minor
- **confidence:** high

**Locations**
- PAGE: API — SimulationDomain, "De-aliasing strategies / DealiasingStrategy": `Concrete strategies: TwoThirds (the sharp $2/3$ rule, the default) and HouLi (the smooth Hou–Li filter).`
- PAGE: API — SimulationDomain, section lead: `The aliasing-control strategy passed to FixedDomain — the supertype, then the sharp 2/3-rule default and the smooth Hou–Li filter.`
- PAGE: API — SimulationDomain, "dealias!": `The kernel is whatever the run's DealiasingStrategy built: the sharp $2/3$ cutoff (TwoThirds, exact de-aliasing) or the smooth HouLi filter …`

**contradicts:** The SAME page's module docstring and `FixedDomain` argument list all three:
- Module: `DealiasingStrategy — the aliasing-control strategy, TwoThirds, HouLi, or PhaseShift`
- `FixedDomain` arg: `… TwoThirds … HouLi … while PhaseShift averages a half-cell-displaced evaluation …`
- `max_wavenumber`: `$2\sqrt2/3$ for PhaseShift`
- and `PhaseShift` has its own Type entry immediately below.

Axis: **how many concrete de-aliasing strategies exist** — the supertype's own doc, the section lead,
and `dealias!` say two; the rest of the page says three.

**description:** The supertype docstring is the natural place a cold reader looks to enumerate the
available strategies, and it under-lists — a reader would conclude only `TwoThirds` and `HouLi` exist,
then be surprised by `PhaseShift` two entries later. This is a staleness/completeness defect (the list
predates `PhaseShift` and was never updated in three places).

---

## F3 — "scalar" is badly overloaded; `scalar_type` (element type) sits beside `scalar` (passive-scalar toggle)

- **type:** clarity
- **severity:** minor
- **confidence:** medium

**Locations**
- PAGE: API — SimulationRun, "The simulation / Simulation" signature: `… scalar_type = Float64, array_type = Array, …`
- Same, Keywords: `scalar_type = Float64, array_type = Array — the real element type and storage backend`
- Same, Keywords: `scalar = false, scalar_variance = 1.0, peak_wavenumber = 2.0 — whether to evolve a passive scalar (a mean-zero $\varphi$) …`
- PAGE: Notation, "Numerics": `| $T$ | the real element type ( Float32 / Float64 ) | scalar_type |`

**description:** In one constructor the reader meets `scalar_type` (the real element type `T`, nothing to
do with the passive scalar) directly alongside `scalar` (the passive-scalar on/off toggle),
`scalar_variance`, and `peak_wavenumber`. Elsewhere the "scalar" prefix means the passive scalar `φ`
throughout — `scalar_forcing`, `scalar_dissipation`, `scalar_variance`, `scalar_buffer`,
`scalar_spectral`/`scalar_physical` (allocators), `scalar_to_physical!`, `scalar_nonlinear!` — while
"scalar field" also denotes tensor rank ("a scalar field in spectral representation"). A newcomer can
easily read `scalar_type = Float64` as "the type of the passive scalar" (i.e. its precision or presence),
not "the global element type." The `scalar_type` name in particular collides with the passive scalar the
package otherwise reserves "scalar" for. `resolution_hint`: consider `element_type`/`real_type` for `T`.

---

## F4 — "Eulerian + Lagrangian statistics" is promised repeatedly but no statistics API is documented anywhere

- **type:** api-gap
- **severity:** minor
- **confidence:** high

**Locations**
- PAGE: Home (index), headline: `… with Lagrangian particle tracking and Eulerian + Lagrangian statistics.`
- PAGE: Home (index), "Work in progress": `The reference turbulence laws (Phenomenology) are scaffolded; the Eulerian and Lagrangian statistics are being added.`
- PAGE: API — Particles, "sample!": `Used to gather a field along the trajectories for the Lagrangian statistics.`
- PAGE: API — SimulationRun, "run!": `… the place to stream statistics along the run.`

**description:** The statistics subsystem is named in the very first sentence of the site and referenced
as the destination of `sample!` and the `run!` callback, yet there is no statistics module, type, or
function documented anywhere on the site, and the backing library is never named (only
`GBGPeriodicFields` is introduced as a dependency). A cold reader who wants to compute a single
statistic has nothing to reach for — the promised feature has no documented home. It is flagged WIP, so
minor, but the headline over-promises relative to the documented surface. `resolution_hint`: soften the
headline to what the site actually documents, or add a stub statistics page.

---

## F5 — Dependency (`GBGPeriodicFields`) types and, crucially, the tracer interpolation schemes are used but never explained

- **type:** api-gap
- **severity:** minor
- **confidence:** medium

**Locations**
- PAGE: API — Particles, "Tracers": `The scheme is the GBGPeriodicFields interpolation scheme used to evaluate the velocity … — CatmullRom (the default), LalescuSpline(n, m), or LagrangeSpline(n).`
- PAGE: API — SimulationRun, "Simulation" Keywords: `ntracers = 0, tracer_scheme = CatmullRom — the number of Lagrangian Tracers and their interpolation scheme.`
- PAGE: API — Particles, "sample!": `… a VectorPointValues for the velocity, a ScalarPointValues for the scalar $\varphi$ …`
- PAGE: API — SimulationDomain, "FixedDomain" Fields: `the Grid3D and its real–Fourier memory layout`, `the FieldSpectralMultipliers, the spectral first-derivative operators`
- PAGE: API — Observables, "derivative_skewness": `reduced to $\langle\boldsymbol{S}:\boldsymbol{S}\rangle$ (inner) and $\langle\det\boldsymbol{S}\rangle$ (det)`, `formed directly with symmetric_gradient`; "scalar_dissipation": `a fused weighted_inner`

**description:** The user MUST choose `tracer_scheme` from `CatmullRom` / `LalescuSpline(n, m)` /
`LagrangeSpline(n)`, but the site never says what these schemes are, what the parameters `n` and `m`
mean, or how to choose among them (accuracy vs. cost/smoothness). Likewise `VectorPointValues`,
`ScalarPointValues`, `Grid3D`, `FieldSpectralMultipliers`, and the reduction operators `inner`, `det`,
`weighted_inner`, `symmetric_gradient` are named as bare identifiers with no gloss — a cold reader
treats them as opaque. The reduction operators are defensible as dependency internals, but the tracer
interpolation schemes are a **user-facing choice with zero guidance**, which is the real gap.

---

## F6 — The keyword `k_max_η` uses `k` for the wavenumber `κ`, contradicting the Notation page's emphasized `k`/`κ` split (and it sits next to `kinetic_energy`)

- **type:** contradiction
- **severity:** minor
- **confidence:** high

**Locations**
- PAGE: Notation, "Conventions / Wavenumber clash": `Kept distinct: bold $\boldsymbol{\kappa}$ is the wavenumber vector, $\kappa = \lvert\boldsymbol{\kappa}\rvert$ its magnitude … and italic scalar $k$ is the turbulent kinetic energy.`
- PAGE: API — SimulationRun, "Simulation" Keywords: `k_max_η = 2 — the resolution criterion $\kappa_{\max}\eta$ used to set $\nu$ in grid mode`
- Same constructor: `kinetic_energy = 1.5 — the initial, and when forced the held, kinetic energy $k$`

**contradicts:** The Notation page goes out of its way to keep `k` (kinetic energy) and `κ` (wavenumber)
apart, yet the flagship constructor names a keyword `k_max_η` for the quantity it explicitly calls
`κ_max η` in prose — ASCII `k` standing in for `κ`. Axis: **which glyph denotes the wavenumber.**

**description:** The keyword prints as `k_max_η` (leading ASCII `k`) but denotes `κ_max·η`, and it appears
in the same signature as `kinetic_energy` (the genuine `k`). A newcomer who just read the "kept distinct"
rule reasonably wonders whether `k_max_η` involves the kinetic energy. This is a self-inflicted violation
of the page's own headline convention. (I understand a keyword can't literally be `κ`; a name like
`kmax_eta_resolution` or `kappa_max_eta` would at least not reuse `k`.)

---

## F7 — `structure_function`'s generic contract is "a velocity moment," but `Yaglom1949` returns a mixed velocity–scalar moment

- **type:** contradiction
- **severity:** minor
- **confidence:** medium

**Locations**
- PAGE: Phenomenology — Reference laws, "structure_function": `The reference velocity structure function $D_{L\dots}(r) = \langle(\delta u)^{\texttt{order}}\rangle$ … the moment of the longitudinal velocity increment $\delta u$ across a distance r.`
- PAGE: Phenomenology — StructureFunctions, "Yaglom1949": `$\langle\delta u_L\,(\delta\varphi)^2\rangle(r) = -\tfrac{4}{3}\,\varepsilon_\varphi\,r$ … structure_function(law, r, fp; order = 3) returns it`

**contradicts:** The generic evaluator says every `structure_function` result is a pure velocity moment
`⟨(δu)^order⟩`, but `Yaglom1949` (documented under `StructureFunctions` and evaluated by the same
`structure_function`) returns the **mixed** third-order velocity–scalar moment `⟨δu_L (δφ)²⟩`. Axis:
**what `structure_function` returns** (velocity-only vs mixed velocity–scalar).

**description:** A cold reader who reads the generic `structure_function` docstring builds the mental model
"this returns `⟨(δu)^order⟩`," then hits `Yaglom1949` returning a quantity that is not of that form. The
`StructureFunction` supertype likewise defines it as `⟨(δu_L)^p⟩` (pure velocity), which doesn't cover the
Yaglom case. The generic contract should mention the scalar/mixed case (as the `spectrum` generic already
mentions `E_φ` for `ScalarSpectrum`). Also, `δφ` (scalar increment) is used here without being introduced
(inferable by analogy to `δu`).

---

## F8 — `scaling_exponent`'s argument is named `order` in its signature but `p` where it is actually called

- **type:** contradiction
- **severity:** nit
- **confidence:** high

**Locations**
- PAGE: Phenomenology — Reference laws, "scaling_exponent": `scaling_exponent(law, order) -> Float64`
- PAGE: Phenomenology — StructureFunctions, "Kolmogorov1962": `Its scaling_exponent(law, p) gives …`
- PAGE: Phenomenology — StructureFunctions, "SheLeveque1994": `Its scaling_exponent(law, p) gives the anomalous exponent`

**contradicts:** The canonical signature names the second argument `order`; the two concrete laws that
use it write `scaling_exponent(law, p)`. Axis: **the argument's name** (`order` vs `p`).

**description:** A cold reader copying the call can't tell whether the parameter is `order` or `p`. Pick
one (the math symbol is `p`, and `structure_function` uses `order` as its keyword — settle the pair).

---

## F9 — `stationary_dissipation` is shown with two different argument-name sets

- **type:** contradiction
- **severity:** nit
- **confidence:** high

**Locations**
- PAGE: Phenomenology — Scalings, "Li2008": `inverted, stationary_dissipation(law, k, L) predicts the dissipation a stationary run of energy $k$ in a box $L$ sustains`
- PAGE: Phenomenology — Scalings, "stationary_dissipation" signature: `stationary_dissipation(law, energy, side_length)`

**contradicts:** `Li2008` calls it `stationary_dissipation(law, k, L)`; the function's own signature is
`stationary_dissipation(law, energy, side_length)`. Axis: **positional argument names** (`k, L` vs
`energy, side_length`). Minor, but a newcomer briefly wonders which is the real signature.

---

## F10 — On the SimulationRun page (an early, central page) the grid-mode explanation forward-references `Li2008` / `G`, defined only on the final page

- **type:** organization
- **severity:** nit
- **confidence:** medium

**Locations**
- PAGE: API — SimulationRun, "Simulation / Setting the Reynolds number": `It reads the dissipation the box sustains from the box-normalized dissipation law Li2008 (in Phenomenology.Scalings), $\varepsilon = (k/G)^{3/2}/L$ … and $G$ the box-normalization group constant ($\approx 0.9$)`
- Defined only later: PAGE: Phenomenology — Scalings, "Li2008" (the last page in reading order)

**description:** The default-viscosity story leans on `Li2008`, "the box-normalized dissipation law," and
the constant `G ≈ 0.9`, none of which the reader has met yet (Phenomenology is the last section). It is
defined inline just enough to follow, so nit, but it is a real forward-reference load on one of the first
API pages a user reads. (This also re-uses `L` = box side in `(k/G)^{3/2}/L`, per F1.)

---

## F11 — The scalar-forcing symbol `f_φ` is used on the Home page but never appears in the Notation glossary

- **type:** clarity
- **severity:** nit
- **confidence:** medium

**Locations**
- PAGE: Home (index), "What it solves": `$\partial_t \varphi = -\nabla\cdot(\boldsymbol{u}\,\varphi) + \frac{\nu}{\mathrm{Sc}}\nabla^{2}\varphi + f_\varphi$ … and $f_\varphi$ a forcing on the scalar.`
- PAGE: Notation, "Physical variables": lists only `| $\boldsymbol f$ | a body forcing on the momentum equation | AbstractForcing |` (no `$f_\varphi$` entry anywhere in the glossary)

**description:** The Notation page bills itself as "the single reference" for the symbols, but the scalar
forcing `f_φ` (introduced on Home) is absent from it — as is any symbol for the scalar-forcing term. Minor,
because it is defined inline on Home, but the glossary is meant to carry it.

---

## F12 — Undefined-in-the-text abbreviations and terms of art: `K41`, `K62`, "aliasing"

- **type:** clarity
- **severity:** nit
- **confidence:** medium

**Locations**
- PAGE: API — Observables, module map: `derivative_skewness — the velocity-derivative skewness, the K41 marker of developed turbulence.`
- PAGE: Phenomenology — StructureFunctions, module map: `Kolmogorov1962 / SheLeveque1994 — the K62 log-normal and She–Lévêque intermittency models`
- PAGE: Home (index): `the quadratic product is de-aliased by the default $2/3$ rule`; PAGE: API — SimulationDomain uses "aliasing"/"de-aliased" throughout.

**description:** `K41` and `K62` are never expanded (a reader must infer K41 = Kolmogorov 1941 from the
`Kolmogorov1941` type name, K62 = Kolmogorov 1962 similarly). "Aliasing" — the central concept the whole
`SimulationDomain`/dealiasing machinery addresses — is never actually defined for a newcomer (only used
and operationally described). Also "solenoidal" (= divergence-free) and "Dirichlet (H¹) energy" appear
without a first-use gloss, though each is contextually recoverable. Individually nits; collectively they
raise the assumed-knowledge floor above "first-year."

---

## F13 — `kinetic_energy` and `scalar_variance` are simultaneously constructor target-value keywords and observable functions

- **type:** clarity
- **severity:** nit
- **confidence:** medium

**Locations**
- PAGE: API — SimulationRun, "Simulation" Keywords: `kinetic_energy = 1.5 — the initial, and when forced the held, kinetic energy $k$`
- PAGE: API — Observables, "kinetic_energy": `kinetic_energy(u) … The turbulent kinetic energy $\tfrac12\langle\lvert\boldsymbol{u}\rvert^{2}\rangle$ …`
- Analogously `scalar_variance` (constructor keyword `scalar_variance = 1.0`) vs `scalar_variance(φ)` (observable).

**description:** The identifier `kinetic_energy` is both a constructor keyword (a scalar target value) and
a public observable function; same for `scalar_variance`. This is a deliberate/common Julia pattern (the
`BandRescaling` holds `kinetic_energy` at the `kinetic_energy` value), but for a cold reader the double
role — `kinetic_energy = 1.5` vs `kinetic_energy(sim)` — is momentarily confusing, especially since both
appear on the SimulationRun page. Noted at nit level.
