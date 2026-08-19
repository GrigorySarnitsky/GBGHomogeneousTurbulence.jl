# Hat: LaTeX / Mathematical-Typesetting Reviewer

Scope: house-style enforcement (`CLAUDE.md`'s Notation + Silent-rendering micro-rules) and
professional typesetting judgment, cross-checked against the AUTHORED source (`src/*.jl`,
`docs/src/*.md`, `docs/ARCHITECTURE.md`) and the rendered manuscript. Build-enforced items
(`\mathbf`, bare-index `\partial_i`, inline-math-on-one-line) were swept and found clean —
not reported here, since a grep-level lint already guards them. The corpus is, overall,
**very disciplined**: `\boldsymbol{}` is universally braced, `\lvert…\rvert` is used
consistently (never bare `|…|` except the one instance below), delimiter-sizing hierarchies
(`\Bigl(\bigl[…\bigr]\Bigr)`) are correctly graduated, and every multi-letter subscript label
is `\mathrm`-wrapped. The findings below are the exceptions to that otherwise-clean pattern.

---

## Finding 1 — bare `|\kappa|^2` breaks the house `\lvert\boldsymbol{\kappa}\rvert^2` convention, self-contradicting within the same decision-log passage

- **Type:** typesetting
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - `docs/ARCHITECTURE.md:1444` — `` the stored real ``|\kappa|^2`` array is gone ``
  - `docs/ARCHITECTURE.md:1449` — `` at ``256^3``/`Float64`, ``|\kappa|^2`` no longer resident twice ``
  - (identical text in `docs/src/architecture.md` at the same line numbers — a byte-identical copy)
- **Contradicts:** the same decision-log entry's own immediate neighbors, describing the *identical*
  quantity (`domain.squared_wavenumber_kernel`), all nine lines earlier in decision 36/37:
  `docs/ARCHITECTURE.md:1367` — `` It holds three field-scale arrays — ``\lvert\boldsymbol{\kappa}\rvert^{2}`` `` ,
  `:1368`, `:1374`, `:1390`, `:1392`, `:1397`, `:1402` — seven more instances, all
  `\lvert\boldsymbol{\kappa}\rvert^{2}`. Also `docs/src/notation.md:59` (the glossary's own canonical
  form): `` ``\lvert\boldsymbol{\kappa}\rvert^2`` | squared wavenumber ``. Axis: bare pipes `|…|` vs.
  the house `\lvert…\rvert` pair, and non-bold `\kappa` vs. the vector `\boldsymbol{\kappa}` the
  squared-magnitude is built from.
- **Description:** Every other occurrence of the squared-wavenumber quantity in the corpus (at least
  a dozen, across `Observables.jl`, `SimulationDomain.jl`, `notation.md`, and seven lines of this
  same ARCHITECTURE.md decision-log passage) writes it `\lvert\boldsymbol{\kappa}\rvert^{2}`. Decision
  38's two instances alone drop to bare, non-stretchy `|\kappa|^2` — both a delimiter regression
  (`\lvert/\rvert` render as proper math-open/close atoms with correct spacing; a bare `|` does not)
  and a bolding regression (the vector glyph collapses to the scalar one for the same object). Since
  this sits four lines below decision 37's own correct usage of the phrase, it reads as a copy/paste
  slip rather than a deliberate choice.

## Finding 2 — `\mathcal F` is the corpus's only unbraced `\mathcal` argument

- **Type:** typesetting
- **Severity:** minor
- **Confidence:** high
- **Locations:** `docs/src/notation.md:60` — `` ``\mathcal F``, ``\mathcal F^{-1}`` | forward / inverse real transform ``
- **Contradicts:** every other `\mathcal` invocation in the corpus (64 counted: 51×`\mathcal{E}`,
  7×`\mathcal{O}`, 6×`\mathcal{P}`) braces its argument even though it is always a single letter —
  e.g. `docs/ARCHITECTURE.md:706` `` \mathcal{P} `` splits the full state…``, `src/Generator.jl:411`
  `` \\mathcal{E}(\\boldsymbol{\\kappa}) = \\exp… ``. Axis: braced vs. unbraced single-letter macro
  argument for the same command family.
- **Description:** `\mathcal F` (no braces) is harmless in isolation — a single token needs no
  grouping — but it is the lone holdout against a corpus that otherwise always writes
  `\mathcal{<letter>}`, including for the sibling operators `\mathcal{E}`/`\mathcal{O}`/`\mathcal{P}`
  on the very same notation.md page. Bracing it would cost nothing and would make the glossary
  internally uniform on its own house convention.

## Finding 3 — the von Kármán roll-off formula is set at two different delimiter sizes across its two docstrings

- **Type:** typesetting
- **Severity:** minor
- **Confidence:** high
- **Locations:**
  - `src/phenomenology/Spectra.jl:175` (`VonKarmanLarge` docstring) —
    `` f_L(\\kappa L) = \\Bigl(\\frac{(\\kappa L)^2}{(\\kappa L)^2 + c_L}\\Bigr)^{17/6} ``
  - `src/phenomenology/Spectra.jl:358` (`VonKarman1948` docstring) —
    `` \\bigl((\\kappa L)^{2}/((\\kappa L)^{2} + c_L)\\bigr)^{17/6} ``
- **Contradicts:** each other — same formula (von Kármán's large-scale roll-off factor, same
  fraction, same `17/6` exponent), same enclosing parenthesis height, but sized `\Bigl(…\Bigr)` in
  one docstring and `\bigl(…\bigr)` in the other. Axis: `\Bigl`/`\Bigr` vs. `\bigl`/`\bigr` for an
  identical parenthesized fraction.
- **Description:** The house rubric asks for fixed-size delimiters sized by hand rather than
  `\left`/`\right` auto-sizing — which this corpus otherwise does very well (graduated
  `\Bigl(\bigl[…\bigr]\Bigr)` nesting appears correctly elsewhere, e.g. `SheLeveque1994` at
  `StructureFunctions.jl:89`). Here the *same* enclosed fraction earns two different hand-picked
  sizes depending on which docstring quotes it — a minor visual mismatch a reader who looks at both
  pages back to back would notice (one parenthesis pair visibly taller than the other around an
  identical fraction).

## Finding 4 — kerning idiom `\exp\!\bigl(…\bigr)`, `\!` around a function name (advisory only, not filed as a defect)

- **Type:** typesetting
- **Severity:** nit
- **Confidence:** low
- **Locations:** `src/State.jl:75,78,156,159`, `src/SimulationDomain.jl:76`, `src/Generator.jl:412`,
  `docs/src/notation.md:63`, `docs/ARCHITECTURE.md:269` — all `\exp\!\bigl(…\bigr)`.
- **Contradicts:** nothing — this is internally uniform (every `\exp` before a `\bigl(` gets the same
  `\!`) and is a standard italic-correction kern, not a spacing-around-a-relation violation.
- **Description:** Recorded only because the rubric singles out manual spacing commands for
  scrutiny. On inspection this is the professional idiom (tightening the gap `\exp`'s slight italic
  overhang leaves before an opening delimiter), applied consistently corpus-wide. Not a defect — no
  action suggested; kept here only so the panel can see it was checked rather than missed.

---

## Swept clean (no findings)

For the record, the following classes were checked exhaustively across every `src/*.jl` docstring,
`docs/ARCHITECTURE.md`, and every `docs/src/*.md` page, and found with **zero** violations:
`\mathbf` (build-enforced, confirmed absent); bare-index `\partial_i` vs. `\partial_{x_i}`
(build-enforced, confirmed — the only bare `\partial_t` instances are the *time* derivative, which
the house rule does not require subscript-braced since `t` is not a spatial coordinate); unbraced
`\boldsymbol` argument; unbraced `\tfrac`; `\mathbb` on a digit; the imaginary unit (always
`\mathrm{i}`, never bare `i` or `\imath`); named operators (`\det`, `\operatorname{tr}`,
`\operatorname{sym}`, `\max`, `\sup`, `\log`, `\cos`, `\exp` — all upright, never italic
letter-products); `\texttt{}`-wrapping of every code identifier that appears inside a formula (30
instances, all correctly wrapped); `\lvert`/`\rvert` pairing balance (matched count in every file);
`` `` `` math-span balance (even count in every file); stray `$`-delimited math (none — the corpus
uses ```` ```math ```` / ` `` ` exclusively); `\left`/`\right` (not used anywhere in the corpus —
`\bigl`/`\Bigl` used instead, correctly paired throughout); a `\begin{cases}` / `\left\{…\right.`
system block (none present, so the sanctioned exception was never needed nor abused); multi-line
`\begin{aligned}` blocks (all six checked — `Propagator.jl:229,342`, `Observables.jl:78,101,233,330`
— align correctly at `&` before `=`/`\leftarrow`).
