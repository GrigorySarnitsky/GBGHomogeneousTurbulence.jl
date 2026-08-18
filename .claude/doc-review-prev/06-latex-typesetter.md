# Panel hat: latex-typesetter

Fresh-eyed audit of math typesetting and house-style conformance, cross-referencing the rendered
manuscript against the authored TeX in `src/*.jl` and `docs/src/*.md` / `docs/ARCHITECTURE.md`,
against the rubric in `CLAUDE.md`'s "Documentation policy" (Notation + Silent-rendering
micro-rules). Build-enforced items (`\mathbf`, bare-index `\partial_i`, inline-math-on-one-line)
were checked and found clean corpus-wide — not repeated here. Findings below are the
judgment-level residue a grep cannot make on its own.

---

## Finding 1 — `C_{OC}` renders as a bare italic letter-product, not the upright abbreviation label

- **Type:** formatting
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - Source: `src/phenomenology/Spectra.jl:386` — `` E_\varphi(\kappa) = C_{OC} \varepsilon_\varphi \varepsilon^{-1/3} \kappa^{-5/3}, ``
  - Rendered: PAGE `api / phenomenology / Spectra`, `ObukhovCorrsin1949` — "$E_\varphi(\kappa) = C_{OC} \varepsilon_\varphi \varepsilon^{-1/3} \kappa^{-5/3},$"
- **Description:** `OC` is a two-letter abbreviation label (Obukhov–Corrsin), not a product of two
  independent index letters, yet it is typeset bare inside the subscript braces (`C_{OC}`), so it
  renders as the italic letter-product "O·C" rather than a unified label. This is the exact class
  CLAUDE.md's own rubric names as the required upright-label case — "a multi-letter subscript LABEL
  upright, `k_{\mathrm{lo}}`, vs a product of index letters italic" — and the corpus gets the
  analogous cases right elsewhere (`\kappa_{\mathrm{Ny}}`, `C_{\mathrm{CFL}}`, `y_{\mathrm{s}}`).
  Should be `C_{\mathrm{OC}}`. All four occurrences of `C_OC` in the same docstring (constructor
  signature aside) carry the same subscript.

---

## Finding 2 — The Big-O order symbol is styled two different ways for the same concept

- **Type:** formatting
- **Severity:** minor
- **Confidence:** high
- **Locations:**
  - `docs/src/observables_cache.md:363` — `` \mathcal O(\Delta t^{2}) `` (mirrored in the rendered
    `observables_cache` page, §2.5: "differs from the endpoint by $\mathcal O(\Delta t^{2})$")
  - `docs/ARCHITECTURE.md:414` — `` O(\Delta t^2) `` (rendered `architecture` page §4.6: "differs
    from the next sample only at $O(\Delta t^2)$")
  - `docs/ARCHITECTURE.md:1093` — `` O(\Delta t) `` (decision log)
  - `docs/ARCHITECTURE.md:1538` — `` O(\Delta t^2) `` (decision log)
- **Description:** The same asymptotic-order notation for the identical claim (the tracer
  predictor-position error term, discussed almost verbatim in both places) is set calligraphic
  (`\mathcal O`) once and plain italic (`O`) three times. One glyph should be chosen and used
  throughout; `\mathcal O` is the more standard choice for Big-O and is already the corpus's
  apparent intent in the design page.

---

## Finding 3 — Word-subscript labels mix `\text{…}` and `\mathrm{…}`, including within the same page

- **Type:** formatting
- **Severity:** minor
- **Confidence:** medium-high
- **Locations:**
  - `docs/src/notation.md:604` (Forcing table) — `` \varepsilon_{\text{target}} ``, versus the same
    page's `` C_{\mathrm{CFL}} `` (line 594) and `` y_{\mathrm{s}} `` (line 597)
  - `docs/ARCHITECTURE.md:708` — `` S_{\text{fine}} ``, `` S_{\text{coarse}} ``
  - `docs/ARCHITECTURE.md:1456` — `` (D, \tau, \text{rate}) `` (decision log)
- **Description:** Both `\text{}` and `\mathrm{}` are legitimate ways to set a word as an upright
  subscript label, but the corpus uses `\mathrm{}` as its evident default (Re, Sc, Ny, CFL, s,
  max, target-in-code-form elsewhere) while these four instances switch to `\text{}` for no
  apparent reason — including one on the very `notation.md` glossary page that fixes the house
  convention. Pick one command for the word-label family and use it everywhere.

---

## Finding 4 — The same numeric coefficient is typeset as a stacked fraction in most places and a bare slash fraction in others, within one file

- **Type:** formatting
- **Severity:** minor
- **Confidence:** high
- **Locations:**
  - `src/SimulationDomain.jl:47,107,112,119` — `` \tfrac{2\sqrt{2}}{3}\kappa_{\mathrm{Ny}} ``
    (stacked fraction, e.g. the `PhaseShift` docstring's headline formula)
  - `src/SimulationDomain.jl:125,361` — `` 2\sqrt{2}/3 \kappa_{\mathrm{Ny}} `` (bare inline slash,
    no `\tfrac`) — same quantity, the `PhaseShift`-cutoff Nyquist fraction, in the same file
- **Description:** `2√2/3 · κ_Ny` is the identical numerical constant discussed four times with a
  properly stacked `\tfrac{2\sqrt{2}}{3}` and twice with a bare `2\sqrt{2}/3` slash form (once in
  a `!!! note` block, once in `truncate_to_band!`'s docstring). Both render legibly, but the
  switch mid-file between the two conventions for the same symbol is an avoidable inconsistency —
  line 283's compact parenthetical list (`2/3` for `TwoThirds`, `1` for `HouLi`, `2\sqrt{2}/3` for
  `PhaseShift`) is a defensible exception since the whole list is in slash form; 125 and 361 are
  standalone prose uses that break from the file's own display-formula convention.

---

## Finding 5 — `θ` reused for an unrelated quantity in the archived `StochasticOU` docstring, against the house glyph rule

- **Type:** formatting
- **Severity:** nit
- **Confidence:** medium
- **Locations:** `src/Forcing.jl:383-384` — `` \hat f \leftarrow \theta \hat f + \sqrt{\sigma^{2}(1-\theta^{2})} \xi, \qquad \theta = \exp(-\Delta t / T_L), ``
- **Description:** CLAUDE.md's Notation block states "the scalar is $\varphi$, never $\theta$" —
  and `notation.md`'s glossary repeats it verbatim ("$\varphi$ | the passive scalar (never
  $\theta$)"). `StochasticOU`'s docstring nonetheless uses `\theta` for the OU-process
  autocorrelation coefficient `exp(-Δt/T_L)`. The quantity is legitimately different from the
  passive scalar, and the docstring is currently archived (un-exported, absent from the rendered
  API per ARCHITECTURE §7), so no live page collides — but the glyph is the one the house rule
  singles out by name, and the type would surface again the day `StochasticOU` is de-archived. A
  different letter (e.g. `\rho`) would remove the risk at no cost.

---

## Finding 6 — `\exp\!\big(…\big)` uses the non-directional `\big` throughout, while other multi-tier formulas use directional `\bigl/\bigr`/`\Bigl/\Bigr`

- **Type:** formatting
- **Severity:** nit
- **Confidence:** low
- **Locations:** e.g. `src/Generator.jl:385`, `src/State.jl:75,78,147,150`,
  `src/SimulationDomain.jl:73`, `docs/src/notation.md:62`, `docs/src/observables_cache.md:258`
  (all `` \exp\!\big(\dots\big) ``) versus `src/phenomenology/StructureFunctions.jl:179`
  (`` \Bigl[1-\bigl(\tfrac{2}{3}\bigr)^{p/3}\Bigr] ``, correctly directional and nested).
- **Description:** `\big(`/`\big)` do not set the Open/Close math class the way `\bigl(`/`\bigr)`
  do, so inter-atom spacing around them is technically less correct than the directional forms the
  corpus otherwise knows to use (the She–Lévêque nesting is a good example of doing it right). The
  `\exp\!\big(` idiom is at least internally consistent with itself everywhere it appears, and the
  `\!` already overrides the operator-open spacing that would matter most, so this is a low-stakes
  nit rather than a visible defect — noted for completeness since the corpus demonstrably knows the
  directional forms and simply doesn't apply them to this one recurring construction.
