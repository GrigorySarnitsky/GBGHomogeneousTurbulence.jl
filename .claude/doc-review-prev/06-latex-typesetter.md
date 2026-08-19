# LaTeX / Typesetting Panel — Findings

Hat: **latex-typesetter** (house math-authoring-style enforcer + general LaTeX/KaTeX professional review)

Substrate read in full: the rendered manuscript (`manuscript-full.md`), the authored TeX in every
`src/*.jl` and `src/phenomenology/*.jl` docstring, every `docs/src/*.md` page, and
`docs/ARCHITECTURE.md`; the house rulebook is `CLAUDE.md`'s "Documentation policy" (Notation +
Silent-rendering micro-rules blocks).

## Summary

This corpus is unusually disciplined. Systematic sweeps for every build-enforced and judgment-level
house-style violation came back clean:

- `\mathbf` — zero hits (build-enforced, confirmed).
- Bare-index `\partial_i` — zero hits (build-enforced, confirmed).
- Unbraced `\boldsymbol X` (no braces) — zero hits.
- `\mathbb` on a digit — zero hits.
- Bare `\phi` (should be `\varphi`) — zero hits; `\theta` appears only in the two places that name it
  as the *forbidden* symbol.
- `\mathrm{i}` for the imaginary unit — used consistently everywhere it denotes
  ``\sqrt{-1}`` (Generator.jl:464, Observables.jl:171, Propagator.jl:355,
  observables_cache.md:294); never left bare italic.
- `\mathrm{Re}`, `\mathrm{Sc}`, and every multi-letter subscript label (`\kappa_{\mathrm{Ny}}`,
  `C_{\mathrm{CFL}}`, `y_{\mathrm{s}}`, `E_{\mathrm{band}}`) — upright and consistent throughout;
  every genuine index product (`S_{ij}`, `R_{ii}`, the literature-standard `D_{LL}`/`D_{LLL}`) is
  correctly left italic.
- `\lvert…\rvert` delimiter counts balance in every file; `\bigl`/`\bigr` and `\Bigl`/`\Bigr` counts
  balance in every file; overall brace balance is clean file-by-file.
- `\left`/`\right` auto-sizing delimiters — **zero** uses anywhere in the corpus; every sized
  delimiter uses the house `\bigl`/`\Bigl` idiom by hand, and the arrow-command exemption
  (`\leftarrow`) is the only "left/right" text that appears.
- `\,` (thin space) — every occurrence in the corpus precedes a `\mathrm{d}` differential; none is
  gratuitous.
- `\!` (negative thin space) — every occurrence is the standard `\exp\!\bigl(` idiom (cancelling the
  TeX-inserted space between an `Op`-class function and a following opening delimiter), applied
  consistently everywhere `\exp` is followed by a sized parenthesis.
- Code identifiers inside a formula are `\texttt{}`-wrapped everywhere (`\texttt{coefficient}`,
  `\texttt{kinetic\_energy}`, `f = A\texttt{field}`, …), never bare.

Given that baseline, the two findings below are genuine but low-severity: one internal
delimiter-sizing inconsistency, and one cosmetic source-formatting slip between two copies of an
identical formula.

---

## Finding 1 — Nested delimiters left unsized where the corpus's own convention sizes them

- **Type:** typesetting
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - `src/phenomenology/Spectra.jl:149` (docstring of `PopeDissipation`):
    `` f_\eta(\kappa\eta) = \exp\!\bigl(-\beta\{[(\kappa\eta)^4 + c_\eta^4]^{1/4} - c_\eta\}\bigr) ``
  - Contrast: `src/phenomenology/StructureFunctions.jl:90` (docstring of `SheLeveque1994`):
    `` \zeta_p = \frac{p}{9} + 2\Bigl[1 - \bigl(\tfrac{2}{3}\bigr)^{p/3}\Bigr] ``
- **Description:** `PopeDissipation`'s formula nests four delimiter levels — outer `\exp\!\bigl(
  \bigr)`, then a literal (unsized) `\{ \}`, then a literal (unsized) `[ ]`, then a literal
  (unsized) `( )` around `\kappa\eta` — so only the outermost pair is manually sized while the three
  levels immediately inside it are left at default size. The corpus's own better practice sits two
  files away: `SheLeveque1994`'s formula tiers a two-level nest correctly, `\Bigl[ \dots \bigl(
  \dots \bigr) \dots \Bigr]`, the outer bracket visibly larger than the inner parenthesis. The
  `PopeDissipation` formula is the one nested construction in the corpus that does not tier its
  delimiter sizes at all beyond the outermost pair, which reads as an inconsistency in an otherwise
  careful, hand-sized-delimiter corpus rather than a deliberate choice.
- **Contradicts:** the same "size by hand, tier by nesting depth" idiom, correctly applied at
  `StructureFunctions.jl:90` (`\Bigl[ \bigl( \bigr) \Bigr]`) and used single-level correctly
  everywhere else (`PopeLargeScale`, `VonKarmanLarge`, `Sreenivasan1998`, `Lundgren2002`, all using
  one `\Bigl(\Bigr)` or `\bigl(\bigr)` sized to their content).
- **Resolution hint:** tier the three inner levels, e.g.
  `\exp\!\Bigl(-\beta\bigl\{[(\kappa\eta)^4 + c_\eta^4]^{1/4} - c_\eta\bigr\}\Bigr)`, or accept the
  current form as intentional and note the exception (this is a taste call, not a build break).

---

## Finding 2 — Duplicate formula disagrees on a stray space before its terminal period

- **Type:** typesetting
- **Severity:** nit
- **Confidence:** high
- **Locations:**
  - `docs/ARCHITECTURE.md:252` (identically duplicated at `docs/src/architecture.md:252`, the
    generated build copy):
    `` \partial_t\boldsymbol{u} = \mathbb{P} (\boldsymbol{u}\times\boldsymbol{\omega}) + \nu\nabla^{2}\boldsymbol{u} + \boldsymbol{f} . ``
  - `src/Generator.jl:319` (docstring of `velocity_rhs!`):
    `` \partial_t\boldsymbol{u} = \mathbb{P} (\boldsymbol{u}\times\boldsymbol{\omega}) + \nu\nabla^{2}\boldsymbol{u} + \boldsymbol{f}. ``
- **Contradicts:** the two spans are the *same* momentum-equation display, restated once in the
  architecture narrative and once in the `velocity_rhs!` docstring; the `ARCHITECTURE.md` copy has a
  literal space between `\boldsymbol{f}` and the closing `.`, the `Generator.jl` copy does not.
- **Description:** a source-level inconsistency between two copies of an identical formula. Because
  TeX/KaTeX math mode discards raw literal whitespace between tokens (spacing is governed entirely by
  atom-class rules and explicit spacing commands, never by a bare space character in the source), this
  particular slip renders pixel-identically either way — it is invisible in the built HTML. It is
  worth recording only as a source-hygiene inconsistency between the two copies of the formula, not as
  a visible defect.
- **Resolution hint:** drop the stray space in `docs/ARCHITECTURE.md:252` for source-level
  consistency with `Generator.jl:319`; no visible change results.

---

## Not flagged (checked and clean)

- The two- and four-column `aligned` blocks (`Particles.jl:267-273`'s Heun update, the coupled
  Navier–Stokes/scalar/tracer system in `observables_cache.md:246-255` and its `ARCHITECTURE.md`
  twin) use uneven ampersand counts per row (one row pairs two side-by-side equations, later rows
  give one each). This is valid `aligned`/`amsmath` usage — rows do not need matching column counts —
  and is not a break.
- Several formulas carry a single literal space between a control sequence and the following token
  (`f\pi \eta/\Delta x` in `SimulationRun.jl:112`, `- \texttt{strength}` in `SimulationDomain.jl:76`
  and the identical span in `notation.md`/manuscript). These are inert: math-mode whitespace is
  discarded by TeX/KaTeX regardless of the source, so there is no rendering difference and no fix is
  needed.
- `\exp\!\bigl(` appears as a fixed idiom at every site where `\exp` is followed by a sized
  parenthesis (`Generator.jl`, `SimulationDomain.jl`, `State.jl` ×4, `observables_cache.md`,
  `notation.md`, `ARCHITECTURE.md`) — this cancels the TeX-inserted `Op`-class spacing before an
  opening delimiter, a standard, deliberate typesetting trick, applied uniformly. Not a defect.
