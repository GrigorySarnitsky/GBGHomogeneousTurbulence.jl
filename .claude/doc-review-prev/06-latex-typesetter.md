# Hat: LaTeX / mathematical-typesetting reviewer

Rubric: house rulebook in `CLAUDE.md` ("Documentation policy" → Notation / Silent-rendering
micro-rules). Read (1) the rendered manuscript, (2) the authored TeX source
(`src/*.jl`, `docs/src/*.md`, `docs/ARCHITECTURE.md`), (3) the rubric itself. Findings below are
judgment-level — house-style violations already caught deterministically by the build lints
(bare `\mathbf`, bare-index `\partial_i`, multi-line inline math) are not repeated here.

---

## Finding 1 — the restated governing equations switch derivative notation mid-corpus

**Type:** formatting (notation drift) · **Severity:** major · **Confidence:** high

**Locations:**
- `docs/src/observables_cache.md:231,234` (source): `\frac{\partial \boldsymbol{u}}{\partial t}` … `\frac{\partial \varphi}{\partial t}`
- vs. `docs/src/index.md:59,66`: `\partial_t \boldsymbol{u} = \mathbb{P}(\boldsymbol{u}\times\boldsymbol{\omega}) + …`
- vs. `docs/ARCHITECTURE.md:241`: `\partial_t\boldsymbol{u} = \mathbb{P} (\boldsymbol{u}\times\boldsymbol{\omega}) + …`
- vs. `src/Generator.jl:254,329`: `\partial_t\boldsymbol{u} = \mathbb{P} (\boldsymbol{u}\times\boldsymbol{\omega}) + …` and `\partial_t\boldsymbol{u} = \nu\nabla^{2}\boldsymbol{u}`
- vs. `docs/ARCHITECTURE.md:1121`: `\partial_t \hat q = A\hat q + N(\hat q)`

**Description:** The identical momentum/scalar equations are restated verbatim across the Home
page, `ARCHITECTURE.md` (three places), and `Generator.jl` (two places) — every one of them using
the `\partial_t X` shorthand, at least seven occurrences. The design page `observables_cache.md`
§2.1 restates the same two equations one more time but switches to the spelled-out fraction
`\frac{\partial X}{\partial t}` for both. This is the corpus's single most load-bearing pair of
formulas (the "what it solves" equation), and it is the one place the notation drifts.

---

## Finding 2 — the skewness constant loses its subscript inside its own defining formula

**Type:** notation · **Severity:** major · **Confidence:** high

**Locations:**
- `docs/ARCHITECTURE.md:318-319` (§4.3) and `docs/ARCHITECTURE.md:886-887` (decision log, both
  identical): `` 3C\langle\det\boldsymbol{S}\rangle/\langle\boldsymbol{S}:\boldsymbol{S}\rangle^{3/2} `` … `` with the exact isotropy constant C_S = \tfrac{4}{7}\sqrt{15/2} ``
- **Contradicts:** `src/Observables.jl:204-206` (the `derivative_skewness` home docstring, the
  authoritative source): `` S = C_S \frac{...}{...} = 3C_S \frac{\langle\det\boldsymbol{S}\rangle}{...} ``, `` C_S = \tfrac{4}{7}\sqrt{15/2} `` — subscripted **both** times.

**Description:** `ARCHITECTURE.md` writes the coefficient as bare `3C` in the formula, then names
it `C_S` one clause later — an unbound symbol at its own point of introduction (a cold reader sees
"C" defined nowhere before "C_S" appears). The canonical home docstring in `Observables.jl` writes
`3C_S` consistently. This is a plain copy/edit slip (the ARCHITECTURE prose was probably drafted
before the subscript was added at the `Observables.jl` home) surviving identically in two places.

---

## Finding 3 — mixed `\tfrac`/`\frac` sizes inside one display formula

**Type:** typesetting (silent size mismatch) · **Severity:** minor · **Confidence:** high

**Location:** `src/phenomenology/StructureFunctions.jl:177` (the `Lundgren2002` formula, a
```` ```math ```` display block):
```
D_{LLL}(r) = -\Bigl(\tfrac{4}{5} - \frac{8.45}{\mathrm{Re}_\lambda^{2/3}}\Bigr)\varepsilon r,
```

**Description:** Inside the same parenthetical, `4/5` is forced to text-style size (`\tfrac`) while
`8.45/\mathrm{Re}_\lambda^{2/3}` renders at full display size (`\frac`) — two visually
different-sized fractions sitting side by side in one expression, a classic "looks wrong" render
defect. Every other `\tfrac` in the corpus is used consistently across *all* occurrences of the
same recurring term (e.g. the `\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^2` Bernoulli term always
gets `\tfrac`); here the two fractions of one single formula disagree with each other.

---

## Finding 4 — the differential command is inconsistently braced

**Type:** typesetting (TeX idiom, internal consistency) · **Severity:** nit · **Confidence:** medium-high

**Locations (unbraced `\mathrm d`):** `src/Observables.jl:271,286`, `src/Phenomenology.jl:187`,
`src/SimulationRun.jl:335`, `docs/src/notation.md:18,69,80` — all `...\,\mathrm d\kappa` /
`\mathrm d\boldsymbol{x}` (no braces around `d`).
**Locations (braced `\mathrm{d}`):** `docs/ARCHITECTURE.md:607`, `docs/src/observables_cache.md:236`
— `\mathrm{d}\boldsymbol{\kappa}/\mathrm{d}t`, `\frac{\mathrm{d}\boldsymbol{X}}{\mathrm{d}t}`.

**Description:** The house rubric's TeX-idiom rule calls for braced group arguments
generally. Roughly two-thirds of the corpus's differentials write `\mathrm d` unbraced (harmless
for a single-character argument, since TeX/KaTeX applies `\mathrm` to just the next token either
way — but still a visible idiom split), while the remaining occurrences write `\mathrm{d}`. Worth
picking one spelling and applying it uniformly.

---

## Finding 5 — `\kappa^4` braced in one place, unbraced everywhere else in the same file

**Type:** typesetting (unbraced group, internal consistency) · **Severity:** nit · **Confidence:** high

**Locations:** `src/phenomenology/Spectra.jl:13,143,144,308` — `` \kappa^4 `` (unbraced), all
describing the identical "Batchelor-type κ⁴ energy-containing range" concept, **vs.**
`src/phenomenology/Spectra.jl:251` — `` \sigma = 4 `` (the Batchelor-type `` \kappa^{4} ``) — braced,
same file, same concept.

**Description:** No render difference for a single digit, but it is the one unbraced exponent
group in a corpus that otherwise braces every multi-digit or symbolic exponent
(`\kappa^{2}`, `\kappa^{-5/3}`, …); four unbraced instances against one braced instance of the exact
same physical quantity in the same file reads as a slip rather than a chosen style.

---

## Finding 6 — the Home page's scalar equation skips the house symbol ϰ that every other restatement uses

**Type:** notation · **Severity:** minor · **Confidence:** medium

**Locations:**
- `docs/src/index.md:66`: `` \partial_t \varphi = -\nabla\cdot(\boldsymbol{u} \varphi) + \frac{\nu}{\mathrm{Sc}}\nabla^{2}\varphi + f_\varphi ``
- **Contradicts:** `docs/src/observables_cache.md:234`: `` \frac{\partial \varphi}{\partial t} = -\nabla\cdot(\boldsymbol{u}\varphi) + \varkappa\nabla^{2}\varphi + f_\varphi `` (same equation, restated with the dedicated diffusivity symbol ϰ); `docs/ARCHITECTURE.md` and `notation.md` both establish ϰ as the one symbol for this quantity.

**Description:** `notation.md`'s own convention table calls ϰ "a fourth, deliberately distinct
glyph" reserved for exactly this quantity. The Home page's copy of the scalar equation spells it
out as the raw ratio `ν/Sc` instead, while the near-identical restatement in
`observables_cache.md` uses ϰ. Plausibly deliberate front-page simplification (ϰ is not yet
introduced that early), but it is the only formula in the corpus that needs the scalar diffusivity
and does not use the symbol the glossary reserves for it.

---

## Not flagged (checked and clean)

- No unbraced `\boldsymbol u` / `\tfrac12`-style violations anywhere in `src/*.jl` or `docs/src/*.md`.
- No `\left`/`\right` usage anywhere in the corpus — `\big`/`\Bigl`/`\Bigr` used throughout, sized
  by hand, consistently.
- Every code identifier appearing inside a math span is `\texttt{}`-wrapped
  (`\texttt{field}`, `\texttt{strength}`, `\texttt{coefficient}`, …) — no bare snake_case identifier
  found inside a `` `` … `` `` span.
- The imaginary unit is `\mathrm{i}` everywhere it appears (`Generator.jl`, `Propagator.jl`,
  `Observables.jl`, `observables_cache.md`) — no bare italic `i`.
- Named operators are correctly upright: `\det`, `\operatorname{tr}`, `\operatorname{sym}`,
  `\operatorname{dealias}`, `\sup`, `\max`, `\exp` — no letter-product operator names found.
- Multi-letter subscript labels are consistently `\mathrm{}`-wrapped
  (`\kappa_{\mathrm{Ny}}`, `y_{\mathrm{s}}`, `\mathrm{Re}_\lambda`, `C_{\varepsilon\infty}`), and
  index subscripts (`u_i`, `S_{ij}`) are consistently left italic.
- No brace mismatches detected in any single-line formula across `src/*.jl`, `docs/src/*.md`, or
  `docs/ARCHITECTURE.md`.
- The `\exp\!\big(...)` idiom (a `\!` tightening the gap KaTeX inserts after a function name before
  a `\big` delimiter) is used consistently everywhere an exponential is delimiter-wrapped
  (`State.jl`, `Generator.jl`, `SimulationDomain.jl`, `notation.md`, `observables_cache.md`,
  `architecture.md`) — a deliberate, uniformly-applied idiom, not a defect.
