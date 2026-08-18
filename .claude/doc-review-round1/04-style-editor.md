# Doc-review panel — Hat 04: Technical copy-editor (internal uniformity + silent-render)

Scope: the whole rendered site incl. Architecture (`manuscript-full.md`), plus the raw built
HTML under `docs/build/` for silent-render inspection.

**Silent-render surface is clean** (verified in `docs/build/`): no `katex-error` spans on any
page; every in-page `@ref` cross-reference and every `@extref` external link (GBGPeriodicFields,
CUDA `CuArray`, AMDGPU `ROCArray`) resolves to a real `href`; the lone literal `@ref` is a
deliberate mention of the token in Architecture §10; no `\mathbf` anywhere (the build lint holds);
run-in labels are uniformly `<strong>Arguments/Keywords/Fields</strong>`; admonitions all render as
`admonition is-info` boxes with intact headers; no code identifier is trapped inside a `$…$` span;
display math is standard client-side KaTeX (`<p class="math-container">\[…\]</p>`). The findings
below are therefore all *textual* uniformity defects, not rendering breakage. Register/voice is
uniform (no "knob", one neutral academic voice).

---

## F1 — No single English variety: British and American spellings mixed corpus-wide, the *same words* both ways
- **type:** language-tone
- **severity:** minor
- **confidence:** high
- **locations:**
  - Observables › `derivative_skewness` (line 850): "written coordinate-free as the **normalized** third invariant of the strain-rate tensor"
  - Architecture §4.3 (line 1619): "computed coordinate-free as the **normalised** third invariant of the strain rate" — and the very same Architecture page, decision entry (line 1748): "becomes the **normalized** third invariant" (mixed *within one page*)
  - British `-ise/-isation` totals: `discretised`×9, `materialised`×5, `realises`×4, `realisation`×4, `realised`×2, `normalised`×2, `generalisation`×2, `stabilised`, `stabilisation`, `specialises`, `parametrised`, `discretisation`, …
  - American `-ize/-ization` totals: `normalized`×17, `parametrization`×13, `realization`×11, `parametrizations`×5, `normalization`×2, `materialized`×2, `specialize`, `generalized`, `characterizing`, …
  - Same lemma both ways on the *user-facing* surface: British `discretised` is site-wide (Home line 36; API-Overview line 150; SimulationDomain lines 427/436/443) while American `normalized` is equally site-wide (SimulationRun lines 321/335; `kinetic_energy` line 818; `scalar_variance` line 824). British `materialises/materialised` sits on the Forcing page (lines 620/664/669) beside American `parametrization`/`normalized` elsewhere.
  - Other axes confirm the mix, not a clean per-page split: `modelled`×6 / `modelling`×1 (BrE) vs `modeling`×2 (AmE); `coloured` (BrE, §8 "a coloured-noise term"); `fiber/fibered`×4 (AmE, no `fibre`).
- **contradicts:** internal — the Observables docstring's "normalized third invariant" vs Architecture §4.3's "normalised third invariant" describe the identical diagnostic with opposite spellings; axis of disagreement = English variety (`-ize` vs `-ise`).
- **description:** The corpus commits to neither British nor American English; the split is not surface-by-surface (which could be defended) but word-by-word, with several lemmas appearing in both spellings, sometimes on the same page and even in the same fixed phrase across pages. This is exactly the uniformity a copy-editor enforces. Not misleading, hence minor — but pervasive and immediately visible on the primary user surface.
- **resolution_hint:** pick one variety (the code/API surface already leans American — `normalized`, `parametrization`, `realization` dominate) and normalize every prose spelling to it; add to the doc-check battery.

## F2 — Hyphenation of two recurring compound terms is inconsistent ("de-alias"/"dealias"; "advective-CFL"/"advective CFL")
- **type:** typesetting
- **severity:** minor
- **confidence:** high
- **locations:**
  - *de-alias vs dealias* — hyphenated prose dominates the site (~28 lines: Home "the quadratic product is **de-aliased**"; SimulationDomain headings "**De-aliasing** strategies", "**De-alias** filtering"; TwoThirds "Exact **de-aliasing**"; PhaseShift "Phase-shift **de-aliasing**"). Unhyphenated leaks onto the user surface: Notation Spectral-operators table (line 98) "the **dealias**/band/envelope kernels"; Notation Numerics table (line 129) "**dealiased** maximum wavenumber"; and TwoThirds itself (line 471) mixes both in one docstring — "$\kappa_{\max}$ the **dealiased** maximum … Exact **de-aliasing** of the quadratic nonlinearity". The Architecture page is uniformly unhyphenated ("**dealiased** by the $2/3$ rule", "the **dealias** kernel", "its **dealiasing**", "the **dealias** fraction"; lines 1600/1608/1670/1681…).
  - *advective-CFL vs advective CFL* — hyphenated ×14 (Notation line 128; SimulationRun; `recommended_cfl` lines 981/987; etc.). Spaced ×4: Observables `max_speed` (line 865) "used to set the **advective CFL** timestep"; Architecture §2 (line 1563) "the **advective CFL** condition"; §4.3 (line 1618); §7 (line 1693).
- **contradicts:** site convention (hyphenated) vs Architecture-page convention (unhyphenated), with cross-leaks in both directions; axis = presence/absence of the hyphen in a fixed compound term. Code identifiers (`dealias!`, `DealiasingStrategy`, `domain.dealias`, the `dealiasing=` keyword) are correctly exempt.
- **description:** The same terms are spelled two ways depending on surface, and one docstring (TwoThirds) uses both forms in adjacent sentences. Purely cosmetic, but it is the archetypal internal-uniformity defect.
- **resolution_hint:** the majority user-facing form is hyphenated ("de-alias*", "advective-CFL"); normalize the Architecture page and the Notation-table / TwoThirds leaks to match, or vice-versa — but pick one.

## F3 — Architecture decision-log code identifiers have drifted from the live API (`energy`, `ConstantPower(power=)`)
- **type:** contradiction
- **severity:** minor
- **confidence:** high
- **locations:**
  - Architecture decision "Resolution-based `viscosity`" (line 1751): "a `BandRescaling` holds the total energy at **`energy`**, default `1.5`, i.e. $u'=1$" — but the constructor keyword is `kinetic_energy` (Simulation, line 312 "`kinetic_energy = 1.5`") and SimulationRun's own "Setting the Reynolds number" (line 319) says "a `BandRescaling` holds the total energy at **`kinetic_energy`**". (The other backticked `energy`, line 1523, is the legitimate positional arg of `stationary_dissipation(law, energy, side_length)` — not this defect.)
  - Architecture decision 14 (line 1745): "`ConstantPower(**power** = 0.1)` … return a `ForcingSpec`" — the keyword is `target` everywhere else (`ConstantPower(domain; target, …)` line 657; `ConstantPower(target = 0.1)` in Architecture §2/§4.4 lines 1551/1565/1628; Notation forcing table `ConstantPower(target=…)` line 138). The later "design-review batch" decision records only the `ForcingSpec → DeferredForcing` rename, not `power → target`.
- **contradicts:** line 1751 "`energy`" vs line 319 "`kinetic_energy`" (and the constructor signature) — same keyword, two names; line 1745 "`power`" vs the live `target` — same keyword, two names.
- **description:** Two code identifiers on the Architecture page name API surface that no longer exists. The append-only decision log partly excuses this, but a reader who copies `ConstantPower(power = 0.1)` or looks up an `energy` keyword hits nothing; the log entry also silently contradicts the live pages it sits beside.
- **resolution_hint:** update the `energy` mention (a live-behavior sentence, not history) to `kinetic_energy`; add a "(keyword since renamed `power → target`)" note to decision 14, or leave the historical `power` but flag it, matching how `ForcingSpec` is annotated as superseded.

## F4 — Spectrum presets are documented as two different object kinds: velocity presets "— Function", the scalar preset "— Type"
- **type:** organization
- **severity:** minor
- **confidence:** low
- **locations:**
  - Spectra › Velocity models: "`…Spectra.Pope2000` — **Function**" (line 1350), "`…VonKarman1948` — **Function**" (1358), "`…Pao1965` — **Function**" (1367)
  - Spectra › Scalar spectra: "`…Spectra.ObukhovCorrsin1949` — **Type**" (1386)
  - Spectra module map treats them symmetrically: "`Pope2000` / `VonKarman1948` / `Pao1965` — named **velocity-spectrum presets** of `ModelSpectrum`" vs "`ObukhovCorrsin1949` is the inertial-convective range" (line 1247-1248)
- **contradicts:** the module's own framing of all four as named preset spectra vs the rendered object-kind labels (Function for velocity, Type for scalar) and the differing docstring skeletons (factory-call signature `Pope2000(; …)` returning a `ModelSpectrum` vs a concrete subtype `ObukhovCorrsin1949(; …) <: ScalarSpectrum`).
- **description:** Likely intentional (the velocity spectrum is *composed*, so a preset is a factory function; the scalar spectrum is a single closed form, so a preset is a concrete type). But nothing in the rendered docs says so, and a reader scanning the Spectra page sees two "presets" presented as different kinds of object with different construction idioms. Marked low confidence because the asymmetry may be a defensible design choice rather than a defect.
- **resolution_hint:** if intentional, add one sentence to the Spectra module map explaining why velocity presets are factory functions and the scalar preset is a type; if not, make them uniform.

## F5 — The dealiasing "2/3 rule" is math `$2/3$` everywhere except one section lead, which uses plain-text "2/3-rule"
- **type:** typesetting
- **severity:** nit
- **confidence:** medium
- **locations:**
  - SimulationDomain › "De-aliasing strategies" section lead (line 460): "the supertype, then the sharp **2/3-rule** default and the smooth Hou–Li filter."
  - Everywhere else the dealiasing rule is set as math: Home "the default `$2/3$` rule"; FixedDomain "the sharp `$2/3$` rule, the default"; TwoThirds "`$2/3$`-rule truncation"; `max_wavenumber` "`$2/3$` for `TwoThirds`"; Architecture "`$2/3$` rule".
- **contradicts:** line 460 plain "2/3" vs the corpus norm `$2/3$` (math) for the same dealiasing rule; axis = math span vs plain text for the same fraction.
- **description:** A lone plain-text fraction where the fraction is otherwise LaTeX. (Note the K41 "2/3 law" / "4/5 law" *are* consistently plain text throughout — that is internally uniform and not part of this finding; only the dealiasing "2/3 rule" breaks.)
- **resolution_hint:** set line 460 as "sharp `$2/3$`-rule default" to match the rest.

## F6 — Keyword `k_max_η` uses `k` for the wavenumber `κ_max`, against the page's own emphatic k/κ distinction
- **type:** typesetting
- **severity:** nit
- **confidence:** low
- **locations:**
  - Notation › Conventions (line 64): "italic scalar `$k$` is the **turbulent kinetic energy**"; "`$\kappa$` … its magnitude (the spectrum coordinate)"
  - Simulation constructor + prose (lines 312/321/326): the resolution-criterion keyword is `k_max_η`, glossed "so that `$\kappa_{\max}\eta$` equals `k_max_η`" — the `k` here denotes `κ_max`, not kinetic energy.
- **contradicts:** the Notation page reserves `k` for kinetic energy and `κ` for wavenumber; the keyword `k_max_η` uses `k` in the `κ_max` role. Axis = which quantity the letter `k` denotes.
- **description:** A mild notation collision on the very axis the docs are most careful about (the κ/k/ϰ set gets a dedicated Notation row). It is an ASCII-constrained code identifier (κ is awkward in a keyword), so this may be an accepted compromise — hence low confidence — but it is worth a look given the surrounding rigor.
- **resolution_hint:** consider `kmax_eta_target` / `resolution` naming, or add a one-line note that `k_max` here is the ASCII rendering of `κ_max`; or accept and record as a deliberate exception.

## F7 — External cross-links target GBGPeriodicFields `/dev/` docs while the site's own canonical links use `/stable/`
- **type:** format
- **severity:** nit
- **confidence:** medium
- **locations:** (from `docs/build/` rendered `href`s)
  - Self / canonical links: `https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl/**stable**/api/…`
  - `@extref` cross-links: `https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/**dev**/api/DifferentialOperators/#…curl` (and `…helmholtz_projection`, `…to_spectral`, `VectorPointValues`, `Grid3D`, etc. — all under `/dev/`)
- **contradicts:** IT's own pages resolve to the pinned `/stable/` channel, while every `@extref` into the sibling PF docs resolves to the moving `/dev/` channel; axis = release channel of the link target.
- **description:** Not a broken link (all resolve), but the cross-package references point at PF's *dev* docs — a moving target that can drift out from under an anchor — while the same build treats its own docs as `/stable/`. Config-driven (the `objects.inv` used by DocumenterInterLinks), and low-impact, but an internal inconsistency surfaced by inspecting the built HTML.
- **resolution_hint:** point the PF interlink inventory at PF's `/stable/` (or whichever channel IT itself pins) so both sides use the same release channel.
