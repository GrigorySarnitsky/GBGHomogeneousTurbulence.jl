# Hat: latex-typesetter

Panel round following `.claude/doc-review-adjudicated.md`. Scope: LaTeX/TeX typesetting idiom and
the house math-authoring style (`CLAUDE.md` "Documentation policy" — Notation block and
Silent-rendering micro-rules), audited against both the rendered manuscript and the authored source
(`src/*.jl` docstrings, `docs/src/*.md`, `docs/ARCHITECTURE.md`).

**Method.** Read the house rulebook and the adjudicated list first. Then swept every `` ``...`` ``
and `\[...\]`/````math``` span in `src/*.jl`, `docs/src/*.md`, and `docs/ARCHITECTURE.md` for: unbraced
`\boldsymbol`/`\tfrac` groups, `\mathbf`, bare-index `\partial_i`, bare imaginary `i`, un-upright named
operators, gratuitous `\,`/`\;`/`\:`/`\!`, `\left`/`\right` vs `\bigl`/`\Bigr`, `\mathbb` on a digit,
unbraced multi-letter subscripts/superscripts, multi-line formulas without an alignment environment,
and code identifiers loose inside math spans. The corpus turned out to be typeset with unusual
discipline — most of the house rules I checked for are followed with zero exceptions across the whole
tree (no unbraced `\boldsymbol`, no `\mathbf`, no bare `\partial_i`, no bare imaginary unit, no
`\left`/`\right` delimiter use anywhere, every `\,` immediately precedes a `\mathrm{d}`, every named
operator — `\det`, `\operatorname{tr}`, `\operatorname{sym}`, `\operatorname{dealias}`, `\sup`, `\log`,
`\exp` — is upright). Two genuine findings survived that sweep.

---

## Finding 1 — the low-storage accumulator is bold `\boldsymbol{h}` at its home, bare `h` in the decision log

- **type:** typesetting
- **severity:** minor
- **confidence:** high
- **locations:**
  - `src/Propagator.jl:222-230` (the `IFLowStorageRK3` docstring, the formula's home): `` ``\\boldsymbol{h}`` `` and the display block `\boldsymbol{h} \leftarrow A_i \boldsymbol{h} + \Delta t \widehat{\boldsymbol{N}}(\hat q)`` — the RK3 accumulator is consistently bold throughout.
  - `docs/ARCHITECTURE.md:1454` / `docs/src/architecture.md:1454` (decision-log entry 39): "the stage update ``\hat{\boldsymbol{u}} \leftarrow \mathcal{E}(\hat{\boldsymbol{u}} + B_i h)``" — same accumulator, rendered as bare italic `h`.
- **contradicts:** `Propagator.jl`'s own docstring, the formula's documented home per the house rule "the `!` form is the home … the allocating form is a thin wrapper with no notation that drifts across the pair" (the same discipline applies across any two renderings of one object) — here the accumulator vector is bold at its one true home and un-bold in the architecture's own abbreviated citation of the identical update rule.
- **description:** `\boldsymbol{h}` is the Runge–Kutta low-storage accumulator, a vector field (spectral representation), per its house-mandated home docstring. The architecture decision log's shorthand mention of the same fused update drops the bold, rendering it as a plain scalar-looking `h`. Since vectors are bold italic house-wide and this is the identical mathematical object (not a new, scalar quantity), the bare `h` is a notation drift a reader who cross-references the two pages would notice.
- **resolution_hint:** Render as `\boldsymbol{h}` in the decision-log entry to match its docstring home.

---

## Finding 2 — two display formulas are laid out as if multi-line but carry no alignment environment, unlike every sibling formula in the same file

- **type:** typesetting
- **severity:** major
- **confidence:** high
- **locations:**
  - `src/Observables.jl:78-81` (the `dissipation` docstring):
    ```
    \\varepsilon = \\nu \\langle\\lvert\\boldsymbol{\\omega}\\rvert^{2}\\rangle
                = 2\\nu\\langle S_{ij}S_{ij}\\rangle,
    ```
    — a bare ````math``` block, two source lines with the second manually indented to visually line up under the first "=", but *no* `\begin{aligned}...\end{aligned}` and no `\\` line-break command.
  - `src/Observables.jl:99-103` (immediately below, the vorticity-identity block): three source lines (`\lvert\boldsymbol{\kappa}\times\hat{\boldsymbol{u}}\rvert^{2} = ... - ...`), same pattern — manually indented, no alignment environment.
- **contradicts:** the same file's own convention at `src/Observables.jl:229-234` (`derivative_skewness`, three lines wrapped in `\begin{aligned}...\end{aligned}` with explicit `&` alignment) and `src/Observables.jl:326-331` (`integral_scale`'s second formula, same treatment) — and the corpus-wide pattern in `src/Propagator.jl:225-231`, `:338-342` and `src/Particles.jl:262-268`, every one of which wraps a visually-multi-line formula in `aligned`.
- **description:** TeX/KaTeX math mode ignores raw newlines and leading whitespace inside a plain (non-`aligned`) block — the source's careful indentation meant to align the two `=` signs has no effect on the render; the formula instead renders as one unbroken line (or, if it ever grows wide enough, produces the very horizontal-scroll the house rules warn against, with no alignment at all). Every other place in this exact file that wants a visually-stacked, `=`-aligned formula uses `\begin{aligned}`; these two do not, so the visual indentation is currently pure noise in the rendered page and a latent formatting bug if either formula is ever extended.
- **resolution_hint:** Wrap both blocks in `\begin{aligned}...\end{aligned}` with `&=` on the continuation lines, matching the file's own established idiom.

---

## Notes on what was checked and found clean (for the record, not separate findings)

- `\boldsymbol{...}` is fully and consistently braced everywhere (`grep` for unbraced instances returned nothing).
- No `\mathbf` anywhere; no bare-index `\partial_i` anywhere outside `\partial_t`/`\partial_{x_i}`.
- The imaginary unit is `\mathrm{i}` at every occurrence, including immediately before `\boldsymbol{\kappa}` (no bare-`i·κ` letter-run anywhere).
- No `\left`/`\right` delimiter usage exists in the corpus at all (only false-positive greps on `\leftarrow`); every sized delimiter uses `\bigl`/`\Bigl`/`\bigr`/`\Bigr`, consistent with the house preference.
- Every `\,` in the whole tree is immediately followed by `\mathrm{d}` — the differential-only convention is observed with zero exceptions.
- Named operators are uniformly upright: `\det`, `\operatorname{tr}`, `\operatorname{sym}`, `\operatorname{dealias}`, `\sup`, `\log`, `\exp`, `\max`/`\min` all appear as proper commands, never as an italic letter-product.
- Multi-letter subscripts are consistently `\mathrm{...}`-wrapped when they are labels (`\kappa_{\mathrm{Ny}}`, `\kappa_{\mathrm{max}}`... via `\max`, `C_{\mathrm{CFL}}`, `E_{\mathrm{band}}`, `y_{\mathrm{s}}`) and left italic when they are genuine index products (`S_{ij}`, `\operatorname{tr}\boldsymbol{S}^{3}`); no mixed-up case found.
- Every code-identifier-in-a-formula binding uses `\texttt{...}` (`\texttt{kinetic\_energy} \equiv k`, `\texttt{coefficient}`, `\texttt{offset\_scale}`, etc.) — none found loose inside a math span.
- The repeated `\exp\!\bigl(...)` idiom (six-plus occurrences across `Generator.jl`, `State.jl`, `SimulationDomain.jl`, `Spectra.jl`) is a consistent, deliberate kerning correction before a sized delimiter, not a gratuitous or isolated `\!` — not flagged.
- `\boldsymbol{A}^{\!\top}` (`docs/ARCHITECTURE.md:631`, the deferred sheared-frame formula) is the standard transpose-kerning idiom, a one-off but conventional use — not flagged.
